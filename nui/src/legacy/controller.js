'use strict';

var mediaPlayerStates  = {};
var startupStates      = {};
var deviceSessions     = {};
var activePlayerHandle = null;
var permissions        = {};
var searchSources      = {};
var defaultSearchSource = 'youtube';
var defaultTransitionSeconds = 5.0;
var maxTransitionSeconds = 15.0;
var maxRange = 200;
var adminMaxRange = 200;
var searchMinimumBusyMs = 500;
var deviceDefaults = {
    volume: 100,
    attenuation: {
        sameRoom: 4.0,
        diffRoom: 6.0
    },
    diffRoomVolume: 0.25,
    range: 30.0,
    transitionSeconds: 5.0,
    isVehicle: false
};
var authoritativePlaylists = [];
var cachedPlaylists    = [];
var cachedSharedPlaylists = [];
var cachedFriends      = [];
var currentPlaylistId  = null;
var currentPlaylistName = '';
var pendingTrackForPlaylist = null;
var pendingFavoriteState = {};
var favoriteRequestSeq = 0;
var favoriteResponseFloor = {};
var usableMediaPlayers = [];
var usableMediaPlayerIndex = {};
var currentViewId = 'view-home';
var libraryState = {
    playlistsLoaded: false,
    playlistsLoading: false,
    playlistsDirty: true,
    playlistRequestSeq: 0,
    playlistPendingRequestId: null,
    playlistResponseFloor: 0,
    libraryRevision: 0,
    sharedLoaded: false,
    sharedLoading: false,
    sharedDirty: true,
    sharedRequestSeq: 0,
    sharedPendingRequestId: null
};
var socialState = {
    friendsLoaded: false,
    requestsLoaded: false,
    dirty: true
};
var librarySummary = {
    playlistCount: 0,
    favoriteCount: 0,
    maxPlaylists: 0,
    maxFavorites: 0
};
var playerSuggestionState = {
    suggestions: [],
    requestSeq: 0,
    pendingRequestId: null,
    requestFloor: 0,
    selectedLicense: null,
    selectedSource: null,
    visible: false
};
var _queuedUiData = null;
var _uiFrameScheduled = false;

var _lastGridHandles   = [];
var _lastActiveHandle  = null;
var _lastNowPlayingPanelKey = '';
var _lastBottomPlayerKey = '';

var URL_PATTERN = /^(https?:\/\/|www\.)[^\s]+$/i;
var LOOP_MODE_ORDER = ['off', 'track', 'queue', 'shuffle_once', 'shuffle_loop'];
var LOOP_MODE_LABELS = {
    off: 'Loop Off',
    track: 'Loop Track',
    queue: 'Loop Queue',
    shuffle_once: 'Shuffle 1x',
    shuffle_loop: 'Shuffle Loop'
};
var PENDING_CONTROL_TIMEOUT_MS = 2500;
var FAVORITE_SYNC_TIMEOUT_MS = 12000;
var FAVORITE_HARD_TIMEOUT_MS = 20000;
var pendingControlState = {};
var _searchBusySince = 0;
var _searchRetryTimer = null;
var _playerSuggestionTimer = null;
var localPlaybackFailures = {};
var requestedStartupStates = {};
var debugConfig = { enabled: false };

function debugEnabled(category) {
    var cfg = debugConfig || {};
    if (cfg === true) return true;
    if (!cfg.enabled) return false;
    if (cfg.all) return true;
    if (category === 'favorite') return cfg.favorites === true;
    if (category === 'startup') return cfg.player === true;
    return cfg[category] === true;
}

function debugLog(category, message, data) {
    if (!debugEnabled(category)) return;
    try {
        var suffix = '';
        if (data !== undefined) {
            try {
                suffix = ' | ' + JSON.stringify(data);
            } catch (_) {
                suffix = ' | ' + String(data);
            }
        }
        console.debug('[7-pmms][debug:' + category + '] ' + message + suffix);
    } catch (_) {}
}

function handleKey(handle) {
    if (handle === undefined || handle === null) return null;
    return String(handle);
}

function cloneValue(source) {
    if (Array.isArray(source)) {
        return source.map(function(entry) {
            return cloneValue(entry);
        });
    }

    if (source && typeof source === 'object') {
        var copy = {};
        Object.keys(source).forEach(function(key) {
            copy[key] = cloneValue(source[key]);
        });
        return copy;
    }

    return source;
}

function clonePlainObject(source) {
    return cloneValue(source || {});
}

function copyStateMap(source) {
    var result = {};
    Object.keys(source || {}).forEach(function(key) {
        var normalizedKey = handleKey(key);
        if (!normalizedKey) return;
        var value = source[key];
        result[normalizedKey] = cloneValue(value);
    });
    return result;
}

function normalizeStateRevision(value) {
    var numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : null;
}

function normalizeLibraryRevision(value) {
    var numeric = Number(value);
    return Number.isFinite(numeric) && numeric >= 0 ? numeric : null;
}

function getMediaStateRevision(state) {
    return normalizeStateRevision(state && state.info && state.info.stateRevision);
}

function getDeviceSessionRevision(state) {
    return normalizeStateRevision(state && state.stateRevision);
}

function normalizeDeviceDefaults(source) {
    var next = source && typeof source === 'object' ? source : {};
    var attenuation = next.attenuation && typeof next.attenuation === 'object' ? next.attenuation : {};
    var transitionSeconds = Number(next.transitionSeconds);
    if (!Number.isFinite(transitionSeconds)) {
        transitionSeconds = defaultTransitionSeconds;
    }

    return {
        volume: Number.isFinite(Number(next.volume)) ? Number(next.volume) : 100,
        attenuation: {
            sameRoom: Number.isFinite(Number(attenuation.sameRoom)) ? Number(attenuation.sameRoom) : 4.0,
            diffRoom: Number.isFinite(Number(attenuation.diffRoom)) ? Number(attenuation.diffRoom) : 6.0
        },
        diffRoomVolume: Number.isFinite(Number(next.diffRoomVolume)) ? Number(next.diffRoomVolume) : 0.25,
        range: Number.isFinite(Number(next.range)) ? Number(next.range) : 30.0,
        transitionSeconds: Math.max(0, Math.min(maxTransitionSeconds, transitionSeconds)),
        isVehicle: next.isVehicle === true
    };
}

function setGlobalDeviceDefaults(source) {
    deviceDefaults = normalizeDeviceDefaults(source);
}

function getGlobalDeviceDefaults() {
    return normalizeDeviceDefaults(deviceDefaults);
}

function normalizeRemoteAssetUrl(url) {
    if (typeof url !== 'string') return '';
    var trimmed = url.trim();
    if (!trimmed) return '';
    if (trimmed.indexOf('//') === 0) return 'https:' + trimmed;
    if (trimmed.indexOf('http://') === 0) return 'https://' + trimmed.slice(7);
    if (trimmed.indexOf('https://') === 0) return trimmed;
    return '';
}

function resetDevicesGridState() {
    _lastGridHandles = [];
    _lastActiveHandle = null;
    var grid = document.getElementById('devices-grid');
    if (grid) grid.innerHTML = '';
    var count = document.getElementById('devices-count');
    if (count) count.textContent = 'None found';
}

function getLocalPlaybackFailure(handle) {
    var key = handleKey(handle);
    if (!key) return null;
    var failure = localPlaybackFailures[key];
    if (!failure) return null;
    if (failure && typeof failure === 'object') {
        return failure;
    }
    return { at: Number(failure) || 0 };
}

function syncLibrarySummary(summary) {
    var nextSummary = summary && typeof summary === 'object' ? summary : {};
    if (nextSummary.playlistCount !== undefined) {
        librarySummary.playlistCount = Number(nextSummary.playlistCount) || 0;
    }
    if (nextSummary.favoriteCount !== undefined) {
        librarySummary.favoriteCount = Number(nextSummary.favoriteCount) || 0;
    }
    if (nextSummary.maxPlaylists !== undefined) {
        librarySummary.maxPlaylists = Number(nextSummary.maxPlaylists) || 0;
    }
    if (nextSummary.maxFavorites !== undefined) {
        librarySummary.maxFavorites = Number(nextSummary.maxFavorites) || 0;
    }
    updateLibrarySummaryDisplay();
}

function getDisplayedLibrarySummary() {
    var playlistCount = librarySummary.playlistCount || 0;
    var favoriteCount = librarySummary.favoriteCount || 0;

    if (libraryState.playlistsLoaded) {
        playlistCount = Array.isArray(authoritativePlaylists) ? authoritativePlaylists.length : 0;
        favoriteCount = applyPendingFavoritesSnapshot(authoritativePlaylists).filter(function(pl) {
            return isPlaylistFavorite(pl);
        }).length;
    }

    return {
        playlistCount: playlistCount,
        favoriteCount: favoriteCount,
        maxPlaylists: librarySummary.maxPlaylists || 0,
        maxFavorites: librarySummary.maxFavorites || 0
    };
}

function updateLibrarySummaryDisplay() {
    var header = document.querySelector('#view-library .view-header-actions');
    if (!header) return;

    var summaryEl = document.getElementById('library-summary');
    if (!summaryEl) {
        summaryEl = document.createElement('div');
        summaryEl.id = 'library-summary';
        header.appendChild(summaryEl);
    }

    var displaySummary = getDisplayedLibrarySummary();

    if (!displaySummary.maxFavorites && !displaySummary.maxPlaylists) {
        summaryEl.textContent = '';
        return;
    }

    var text = displaySummary.favoriteCount + '/' + displaySummary.maxFavorites + ' favorites';
    if (displaySummary.maxPlaylists) {
        text += ' - ' + displaySummary.playlistCount + '/' + displaySummary.maxPlaylists + ' playlists';
    }
    summaryEl.textContent = text;
    summaryEl.className = displaySummary.favoriteCount >= (displaySummary.maxFavorites || Number.MAX_SAFE_INTEGER)
        ? 'library-summary-warning'
        : '';
}

function setUsableMediaPlayers(devices) {
    usableMediaPlayers = Array.isArray(devices) ? devices.slice() : [];
    usableMediaPlayerIndex = {};

    usableMediaPlayers.forEach(function(device) {
        if (!device || device.handle == null) return;
        usableMediaPlayerIndex[handleKey(device.handle)] = device;
    });
}

function getDeviceEntry(handle) {
    var key = handleKey(handle);
    return key ? usableMediaPlayerIndex[key] || null : null;
}

function getStartupState(handle) {
    var key = handleKey(handle);
    if (!key) return null;

    var serverState = startupStates[key] || null;
    if (serverState) {
        delete requestedStartupStates[key];
        return serverState;
    }

    var requestedState = requestedStartupStates[key] || null;
    if (!requestedState) return null;
    if ((requestedState.expiresAt || 0) <= Date.now()) {
        delete requestedStartupStates[key];
        return null;
    }

    return requestedState;
}

function getCurrentStartupState() {
    return getStartupState(activePlayerHandle);
}

function getCurrentLocalPlaybackFailure() {
    return getLocalPlaybackFailure(activePlayerHandle);
}

function isStartupPending(state) {
    if (!state || !state.phase) return false;
    return ['requested', 'resolving', 'loading', 'starting', 'retrying', 'fallback'].indexOf(state.phase) !== -1;
}

function isStartupFailed(state) {
    if (!state || !state.phase) return false;
    return ['failed', 'timed_out'].indexOf(state.phase) !== -1;
}

function getStartupPhaseLabel(state) {
    var phase = state && state.phase;
    if (phase === 'requested') return 'Requested';
    if (phase === 'resolving') return 'Resolving';
    if (phase === 'starting') return 'Starting';
    if (phase === 'loading') return 'Loading';
    if (phase === 'retrying') return 'Retrying';
    if (phase === 'fallback') return 'Fallback';
    if (phase === 'timed_out') return 'Timed Out';
    if (phase === 'superseded') return 'Superseded';
    if (phase === 'stopped') return 'Stopped';
    if (phase === 'failed') return 'Failed';
    if (phase === 'ready') return 'Ready';
    return 'Starting';
}

function getStartupStatusText(state) {
    if (!state) return '';
    if (typeof state.message === 'string' && state.message.trim()) {
        return state.message.trim();
    }
    if (state.phase === 'requested') return 'Preparing playback.';
    if (state.phase === 'resolving') return 'Resolving media source.';
    if (state.phase === 'starting') return 'Starting playback.';
    if (state.phase === 'loading') return 'Loading media.';
    if (state.phase === 'retrying') return 'Retrying playback with a different provider.';
    if (state.phase === 'fallback') return 'Using fallback playback.';
    if (state.phase === 'timed_out') return 'Playback startup timed out.';
    if (state.phase === 'superseded') return 'Playback request was replaced.';
    if (state.phase === 'stopped') return 'Playback startup was stopped.';
    if (state.phase === 'failed') return 'Playback failed.';
    if (state.phase === 'ready') return 'Ready.';
    return 'Starting playback.';
}

function getStartupDisplayTitle(state) {
    if (!state) return 'Loading media';
    if (state.title) return state.title;
    if (state.url) return state.url;
    return getStartupPhaseLabel(state);
}

function getDeviceLabelByHandle(handle) {
    var key = handleKey(handle);
    var mp = key ? mediaPlayerStates[key] : null;
    if (mp && mp.label) return mp.label;

    var device = getDeviceEntry(key);
    if (device && device.label) return device.label;

    return key ? 'Device' : 'No Device';
}

function requestPlaylists(force) {
    if (!force && libraryState.playlistsLoading) return;
    if (!force && libraryState.playlistsLoaded && !libraryState.playlistsDirty) return;

    var requestId = ++libraryState.playlistRequestSeq;
    libraryState.playlistsLoading = true;
    libraryState.playlistPendingRequestId = requestId;
    sendMessage('getPlaylists', { requestId: requestId });
}

function requestSharedPlaylists(force) {
    if (!force && libraryState.sharedLoading) return;
    if (!force && libraryState.sharedLoaded && !libraryState.sharedDirty) return;

    var requestId = ++libraryState.sharedRequestSeq;
    libraryState.sharedLoading = true;
    libraryState.sharedPendingRequestId = requestId;
    sendMessage('getSharedPlaylists', { requestId: requestId });
}

function requestLibrary(force) {
    requestPlaylists(force);
    requestSharedPlaylists(force);
}

function requestSocial(force) {
    if (force || socialState.dirty || !socialState.friendsLoaded) {
        sendMessage('getFriends');
    }
    if (force || socialState.dirty || !socialState.requestsLoaded) {
        sendMessage('getFriendRequests');
    }
}

function sendMessage(name, data) {
    if (typeof GetParentResourceName !== 'function') return;
    var resourceName = GetParentResourceName();
    fetch('https://' + resourceName + '/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {})
    }).catch(function() {});
}

function sendRequest(name, data) {
    if (typeof GetParentResourceName !== 'function') {
        return Promise.resolve({});
    }
    var resourceName = GetParentResourceName();
    return fetch('https://' + resourceName + '/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {})
    }).then(function(response) {
        return response.json();
    }).catch(function() {
        return {};
    });
}

function safeText(str) {
    if (!str) return '';
    var d = document.createElement('div');
    d.appendChild(document.createTextNode(str));
    return d.innerHTML;
}

function timeToString(time) {
    if (!time || isNaN(time) || time <= 0) return '0:00';
    var t = Math.round(time);
    var h = Math.floor(t / 3600);
    var m = Math.floor((t % 3600) / 60);
    var s = t % 60;
    if (h > 0) return h + ':' + (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
    return m + ':' + (s < 10 ? '0' : '') + s;
}

function isDirectUrl(str) {
    return URL_PATTERN.test(str);
}

function getCurrentDeviceLabel() {
    return getDeviceLabelByHandle(activePlayerHandle);
}

function getDeviceSession(handle) {
    var key = handleKey(handle);
    return key ? deviceSessions[key] || null : null;
}

function getEffectiveDeviceSession(handle, rawSession) {
    var session = rawSession || getDeviceSession(handle);
    if (!session) return null;

    var key = handleKey(handle);
    var pending = key ? pendingControlState[key] : null;
    if (!pending) {
        return session;
    }

    var nextSession = cloneValue(session);
    nextSession.settings = nextSession.settings || {};

    if (pending.loopMode) {
        nextSession.settings.loopMode = normalizeLoopMode(pending.loopMode.value, nextSession.settings.loopMode === 'track');
    }
    if (pending.range) nextSession.settings.range = pending.range.value;
    if (pending.volume) nextSession.settings.volume = pending.volume.value;
    if (pending.attSame || pending.attDiff) {
        nextSession.settings.attenuation = nextSession.settings.attenuation || {};
        if (pending.attSame) nextSession.settings.attenuation.sameRoom = pending.attSame.value;
        if (pending.attDiff) nextSession.settings.attenuation.diffRoom = pending.attDiff.value;
    }
    if (pending.diffRoomVolume) nextSession.settings.diffRoomVolume = pending.diffRoomVolume.value;
    if (pending.isVehicle) nextSession.settings.isVehicle = pending.isVehicle.value === true;
    if (pending.transitionSeconds) nextSession.settings.transitionSeconds = pending.transitionSeconds.value;

    return nextSession;
}

function buildSessionInfo(handle, session) {
    if (!session) return null;

    var settings = cloneValue(session.settings || {});
    settings.attenuation = settings.attenuation || {};
    settings.queue = Array.isArray(session.queue) ? cloneValue(session.queue) : [];
    settings.history = Array.isArray(session.history) ? cloneValue(session.history) : [];
    settings.playbackPreview = Array.isArray(session.playbackPreview) ? cloneValue(session.playbackPreview) : [];
    settings.queueLength = Number.isFinite(Number(session.queueLength)) ? Number(session.queueLength) : settings.queue.length;
    settings.historyCount = Number.isFinite(Number(session.historyCount)) ? Number(session.historyCount) : settings.history.length;
    settings.sessionLock = session.sessionLock || null;
    settings.sessionLocked = session.sessionLocked === true;
    settings.idleResetAt = session.idleResetAt || null;
    settings.resetActive = session.resetActive === true;
    settings.stateRevision = session.stateRevision || settings.stateRevision;
    settings.loopMode = normalizeLoopMode(settings.loopMode, settings.loop);
    settings.loop = settings.loopMode === 'track';
    settings.currentTrack = session.currentTrack || null;
    settings.deviceCapability = session.deviceCapability || (settings.isVehicle === true ? 'audio' : 'video');
    return settings;
}

function buildSessionDeviceState(handle, session) {
    var key = handleKey(handle);
    var effectiveSession = getEffectiveDeviceSession(key, session);
    if (!effectiveSession) return null;

    var device = getDeviceEntry(key);
    var info = buildSessionInfo(key, effectiveSession);
    return {
        handle: handle,
        label: getDeviceLabelByHandle(key),
        canInteract: permissions.manage === true || !!device,
        distance: device && Number.isFinite(Number(device.distance)) ? Number(device.distance) : -1,
        info: info,
        session: effectiveSession,
        isSessionOnly: true,
        visibleBecause: device && device.visibleBecause ? device.visibleBecause : 'nearby'
    };
}

function getCurrentLiveMP() {
    var key = handleKey(activePlayerHandle);
    if (!key) return null;
    return mediaPlayerStates[key] || null;
}

function getCurrentSessionMP() {
    var key = handleKey(activePlayerHandle);
    if (!key) return null;
    return buildSessionDeviceState(key);
}

function getCurrentMP() {
    return getCurrentLiveMP() || getCurrentSessionMP();
}

function getDeviceCapability(handle, info, session) {
    if (session && session.settings && session.settings.isVehicle === true) {
        return 'audio';
    }
    if (info && info.deviceCapability) {
        return info.deviceCapability;
    }
    if (session && session.deviceCapability) {
        return session.deviceCapability;
    }
    if (info && info.isVehicle === true) {
        return 'audio';
    }
    return 'video';
}

function normalizeLoopMode(loopMode, legacyLoop) {
    if (typeof loopMode === 'string') {
        var normalized = loopMode.toLowerCase();
        if (LOOP_MODE_ORDER.indexOf(normalized) !== -1) {
            return normalized;
        }
    }
    return legacyLoop === true ? 'track' : 'off';
}

function nextLoopMode(loopMode) {
    var current = normalizeLoopMode(loopMode, false);
    var idx = LOOP_MODE_ORDER.indexOf(current);
    if (idx < 0) idx = 0;
    return LOOP_MODE_ORDER[(idx + 1) % LOOP_MODE_ORDER.length];
}

function getLoopIcon(loopMode) {
    var mode = normalizeLoopMode(loopMode, false);
    var repeatBase = '<path d="m17 2 4 4-4 4" /><path d="M3 11v-1a4 4 0 0 1 4-4h14" /><path d="m7 22-4-4 4-4" /><path d="M21 13v1a4 4 0 0 1-4 4H3" />';
    var repeatOne = '<circle cx="12" cy="12" r="4.2" fill="none" /><text x="12" y="14.2" text-anchor="middle" font-size="6.5" font-weight="700" fill="currentColor" stroke="none">1</text>';
    var shuffleBase = '<polyline points="16 3 21 3 21 8" /><line x1="4" y1="20" x2="21" y2="3" /><polyline points="21 16 21 21 16 21" /><line x1="15" y1="15" x2="21" y2="21" /><line x1="4" y1="4" x2="9" y2="9" />';
    var shuffleOne = '<circle cx="8" cy="16.5" r="3.2" fill="none" /><text x="8" y="18.6" text-anchor="middle" font-size="5.8" font-weight="700" fill="currentColor" stroke="none">1</text>';

    if (mode === 'off') {
        return '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + repeatBase + '<line x1="4" y1="4" x2="20" y2="20" /></svg>';
    }
    if (mode === 'track') {
        return '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + repeatBase + repeatOne + '</svg>';
    }
    if (mode === 'queue') {
        return '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + repeatBase + '</svg>';
    }
    if (mode === 'shuffle_once') {
        return '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + shuffleBase + shuffleOne + '</svg>';
    }
    if (mode === 'shuffle_loop') {
        return '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + shuffleBase + '</svg>';
    }

    return '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + repeatBase + '<line x1="4" y1="4" x2="20" y2="20" /></svg>';
}

function normalizeControlValue(field, value, info) {
    if (field === 'paused') return value === true;
    if (field === 'muted') return value === true;
    if (field === 'video') return value !== false;
    if (field === 'loopMode') return normalizeLoopMode(value, info && info.loop);
    if (field === 'transitionSeconds') {
        var numeric = Number(value);
        if (!Number.isFinite(numeric)) return 0;
        return Math.max(0, numeric);
    }
    if (field === 'range' || field === 'volume' || field === 'attSame' || field === 'attDiff' || field === 'diffRoomVolume') {
        var n = Number(value);
        return Number.isFinite(n) ? n : 0;
    }
    if (field === 'isVehicle') return value === true;
    return value;
}

function getServerControlValue(field, info) {
    if (!info) return null;
    if (field === 'paused') return info.paused === true;
    if (field === 'muted') return info.muted === true;
    if (field === 'video') return info.video !== false;
    if (field === 'loopMode') return normalizeLoopMode(info.loopMode, info.loop);
    if (field === 'transitionSeconds') {
        var transition = Number(info.transitionSeconds);
        return Number.isFinite(transition) ? Math.max(0, transition) : 0;
    }
    if (field === 'range') return Number(info.range);
    if (field === 'volume') return Number(info.volume);
    if (field === 'attSame') return Number(info.attenuation && info.attenuation.sameRoom);
    if (field === 'attDiff') return Number(info.attenuation && info.attenuation.diffRoom);
    if (field === 'diffRoomVolume') return Number(info.diffRoomVolume);
    if (field === 'isVehicle') return info.isVehicle === true;
    return info[field];
}

function setPendingControlField(handle, field, value) {
    var key = handleKey(handle);
    if (!key) return;
    var now = Date.now();
    if (!pendingControlState[key]) pendingControlState[key] = {};
    pendingControlState[key][field] = {
        value: normalizeControlValue(field, value, null),
        expiresAt: now + PENDING_CONTROL_TIMEOUT_MS
    };
}

function clearPendingControlField(handle, field) {
    var key = handleKey(handle);
    if (!key || !pendingControlState[key]) return;
    delete pendingControlState[key][field];
    if (Object.keys(pendingControlState[key]).length === 0) {
        delete pendingControlState[key];
    }
}

function clearPendingControlForHandle(handle) {
    var key = handleKey(handle);
    if (!key) return;
    delete pendingControlState[key];
}

function getEffectiveInfo(handle, rawInfo) {
    if (!rawInfo) return rawInfo;
    var key = handleKey(handle);
    var pending = key ? pendingControlState[key] : null;
    if (!pending) return rawInfo;

    var info = {};
    Object.keys(rawInfo).forEach(function(prop) {
        info[prop] = rawInfo[prop];
    });

    if (pending.paused) info.paused = pending.paused.value === true;
    if (pending.muted) info.muted = pending.muted.value === true;
    if (pending.video) info.video = pending.video.value !== false;
    if (pending.loopMode) {
        info.loopMode = normalizeLoopMode(pending.loopMode.value, info.loop);
        info.loop = info.loopMode === 'track';
    }
    if (pending.range) info.range = pending.range.value;
    if (pending.volume) info.volume = pending.volume.value;
    if (pending.attSame || pending.attDiff) {
        info.attenuation = info.attenuation || {};
        if (pending.attSame) info.attenuation.sameRoom = pending.attSame.value;
        if (pending.attDiff) info.attenuation.diffRoom = pending.attDiff.value;
    }
    if (pending.diffRoomVolume) info.diffRoomVolume = pending.diffRoomVolume.value;
    if (pending.isVehicle) info.isVehicle = pending.isVehicle.value === true;
    if (pending.transitionSeconds) info.transitionSeconds = pending.transitionSeconds.value;
    return info;
}

function mergeMediaPlayerStates(incomingStates) {
    var source = incomingStates || {};
    var seen = {};

    Object.keys(source).forEach(function(key) {
        var normalizedKey = handleKey(key);
        if (!normalizedKey) return;
        seen[normalizedKey] = true;
        var incomingState = cloneValue(source[key]);
        var currentRevision = getMediaStateRevision(mediaPlayerStates[normalizedKey]);
        var incomingRevision = getMediaStateRevision(incomingState);
        if (currentRevision !== null && incomingRevision !== null && incomingRevision < currentRevision) {
            return;
        }
        mediaPlayerStates[normalizedKey] = incomingState;
    });

    Object.keys(mediaPlayerStates).forEach(function(key) {
        if (!seen[key]) {
            var session = deviceSessions[key];
            if (session && session.playbackActive === true) {
                return;
            }
            delete mediaPlayerStates[key];
        }
    });
}

function queueUiUpdate(data) {
    _queuedUiData = data;
    if (_uiFrameScheduled) return;
    _uiFrameScheduled = true;
    requestAnimationFrame(function() {
        _uiFrameScheduled = false;
        var payload = _queuedUiData;
        _queuedUiData = null;
        if (payload) updateUi(payload);
    });
}

function reconcilePendingControls(states) {
    var now = Date.now();
    var stateMap = states || {};

    Object.keys(pendingControlState).forEach(function(handle) {
        var serverInfo = stateMap[handle] && stateMap[handle].info ? stateMap[handle].info : null;
        if (!serverInfo) {
            var session = getDeviceSession(handle);
            serverInfo = session ? buildSessionInfo(handle, session) : null;
        }
        var fields = pendingControlState[handle];
        Object.keys(fields).forEach(function(field) {
            var pending = fields[field];
            if (!pending) return;

            var serverValue = getServerControlValue(field, serverInfo);
            var pendingValue = normalizeControlValue(field, pending.value, serverInfo);
            if (serverValue !== null && serverValue === pendingValue) {
                clearPendingControlField(handle, field);
                return;
            }

            if ((pending.expiresAt || 0) <= now) {
                clearPendingControlField(handle, field);
                if (serverInfo && handleKey(activePlayerHandle) === handle) {
                    showNotification('A control update timed out and reverted.', 'Controls', '#ff4444', 1800);
                }
            }
        });

        if (!stateMap[handle] && !getDeviceSession(handle)) {
            clearPendingControlForHandle(handle);
        }
    });
}

function switchView(viewId) {
    currentViewId = viewId;
    document.querySelectorAll('.nav-item').forEach(function(el) {
        el.classList.toggle('active', el.dataset.target === viewId);
    });
    document.querySelectorAll('.view').forEach(function(el) {
        el.classList.toggle('active', el.id === viewId);
    });
    if (viewId === 'view-library') {
        requestPlaylists(hasPendingFavoriteMutations());
        requestSharedPlaylists(false);
    } else if (viewId === 'view-social') {
        requestSocial(false);
    }
}

function updateUi(data) {
    if (data.showUi) {
        document.body.style.display = 'block';
        if (data.debug !== undefined) {
            debugConfig = data.debug || { enabled: false };
            debugLog('nui', 'debug config updated from showUi', debugConfig);
        }
        if (data.searchSources && Object.keys(data.searchSources).length) {
            searchSources = data.searchSources;
            defaultSearchSource = data.defaultSearchSource || defaultSearchSource || 'youtube';
            populateSearchSources(searchSources, defaultSearchSource);
        }
        if (Number.isFinite(Number(data.defaultTransitionSeconds))) {
            defaultTransitionSeconds = Number(data.defaultTransitionSeconds);
        }
        if (Number.isFinite(Number(data.maxTransitionSeconds))) {
            maxTransitionSeconds = Number(data.maxTransitionSeconds);
        }
        if (Number.isFinite(Number(data.maxRange))) {
            maxRange = Number(data.maxRange);
        }
        if (Number.isFinite(Number(data.adminMaxRange))) {
            adminMaxRange = Number(data.adminMaxRange);
        }
        if (Number.isFinite(Number(data.searchMinimumBusyMs))) {
            searchMinimumBusyMs = Number(data.searchMinimumBusyMs);
        }
        if (data.deviceDefaults) {
            setGlobalDeviceDefaults(data.deviceDefaults);
        }
        if (data.selectedHandle != null) {
            activePlayerHandle = handleKey(data.selectedHandle);
            _lastActiveHandle = activePlayerHandle;
        }
        resetDevicesGridState();
        activateSearchBtn();
        requestPlaylists(hasPendingFavoriteMutations());
        if (currentViewId === 'view-library' || currentViewId === 'view-playlist') {
            requestSharedPlaylists(false);
        }
        if (currentViewId === 'view-social') {
            requestSocial(false);
        }
        return;
    }
    if (data.hideUi) {
        document.body.style.display = 'none';
        activePlayerHandle = null;
        pendingControlState = {};
        _activeSearchRequestId = null;
        _lastNowPlayingPanelKey = '';
        _lastBottomPlayerKey = '';
        usableMediaPlayers = [];
        usableMediaPlayerIndex = {};
        deviceSessions = {};
        localPlaybackFailures = {};
        requestedStartupStates = {};
        clearTimeout(_searchRetryTimer);
        _searchRetryTimer = null;
        clearTimeout(_playerSuggestionTimer);
        _playerSuggestionTimer = null;
        playerSuggestionState.visible = false;
        playerSuggestionState.suggestions = [];
        playerSuggestionState.pendingRequestId = null;
        hidePlayerSuggestions();
        resetDevicesGridState();
        updateBottomPlayer();
        updateNowPlayingPanel();
        return;
    }

    if (data.permissions) permissions = data.permissions;
    if (data.startupStates) startupStates = copyStateMap(data.startupStates);
    if (data.deviceSessions) mergeDeviceSessions(data.deviceSessions);
    if (data.failedPlayers) localPlaybackFailures = copyStateMap(data.failedPlayers);

    Object.keys(startupStates).forEach(function(handle) {
        delete requestedStartupStates[handleKey(handle)];
    });

    if (data.activeMediaPlayers) {
        mergeMediaPlayerStates(data.activeMediaPlayers);
        Object.keys(data.activeMediaPlayers || {}).forEach(function(handle) {
            delete requestedStartupStates[handleKey(handle)];
        });
        reconcilePendingControls(mediaPlayerStates);

        if (data.usableMediaPlayers) {
            setUsableMediaPlayers(data.usableMediaPlayers);
            var currentHandles = data.usableMediaPlayers.map(function(d) { return d.handle.toString(); });
            if (activePlayerHandle && currentHandles.indexOf(activePlayerHandle) === -1) {
                var hasMediaState = !!mediaPlayerStates[activePlayerHandle];
                var hasStartupState = !!startupStates[activePlayerHandle];
                var hasSessionState = !!deviceSessions[activePlayerHandle];
                var hasRequestedState = !!requestedStartupStates[activePlayerHandle];
                if (!hasMediaState && !hasStartupState && !hasSessionState && !hasRequestedState) {
                    clearPendingControlForHandle(activePlayerHandle);
                    activePlayerHandle = null;
                }
            }
            var handlesChanged  = currentHandles.length !== _lastGridHandles.length ||
                currentHandles.some(function(h, i) { return h !== _lastGridHandles[i]; });

            if (handlesChanged || activePlayerHandle !== _lastActiveHandle) {
                renderDevicesGrid(data.usableMediaPlayers);
                _lastGridHandles  = currentHandles;
                _lastActiveHandle = activePlayerHandle;
            } else {
                updateDevicesGridInPlace(data.usableMediaPlayers);
            }
        }

        updateBottomPlayer();
        updateNowPlayingPanel();

        var adminModal = document.getElementById('admin-modal');
        if (adminModal && adminModal.style.display === 'flex') {
            refreshAdminModalFromState();
        }
    }
}


'use strict';

function showNotification(text, title, color, dur) {
    var c = document.getElementById('notification-container');
    if (!c) return;

    var toast = document.createElement('div');
    toast.className = 'toast';
    if (color) toast.style.borderLeftColor = color;

    toast.innerHTML =
        '<div class="toast-icon">' +
            (color === '#ff4444' || color === 'var(--red)'
                ? '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>'
                : '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>'
            ) +
        '</div>' +
        '<div class="toast-body">' +
            '<div class="toast-title">' + safeText(typeof title !== 'undefined' ? title : '7-PMMS') + '</div>' +
            '<div class="toast-text">'  + safeText(typeof text !== 'undefined' ? text : '') + '</div>' +
        '</div>' +
        '<button class="toast-close" onclick="this.parentElement.remove()">' +
            '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>' +
        '</button>';

    c.appendChild(toast);

    requestAnimationFrame(function() { toast.classList.add('toast-in'); });

    var timeout = setTimeout(function() {
        toast.classList.remove('toast-in');
        toast.classList.add('toast-out');
        setTimeout(function() { if (toast.parentNode) toast.remove(); }, 350);
    }, dur || 4000);

    toast.addEventListener('click', function(e) {
        if (e.target.classList.contains('toast-close')) return;
        clearTimeout(timeout);
        toast.classList.remove('toast-in');
        toast.classList.add('toast-out');
        setTimeout(function() { if (toast.parentNode) toast.remove(); }, 350);
    });
}


'use strict';

function renderDevicesGrid(devices) {
    var grid  = document.getElementById('devices-grid');
    if (!grid) return;

    if (!devices || devices.length === 0) {
        grid.innerHTML = '<div class="empty-state"><svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="4" y="2" width="16" height="20" rx="2"/><circle cx="12" cy="14" r="4"/><line x1="12" y1="6" x2="12.01" y2="6"/></svg><p>No media players nearby</p></div>';
        _updateDevicesCount(devices);
        return;
    }

    grid.innerHTML = '';
    _updateDevicesCount(devices);
    devices.forEach(function(device) {
        if (!device || device.handle == null) return;
        var handle = device.handle.toString();
        var isActive = activePlayerHandle === handle;
        var newCard = _buildDeviceCard(device, handle, isActive);
        if (newCard) grid.appendChild(newCard);
    });
    applyStaticTooltips();
}

function updateDevicesGridInPlace(devices) {
    var grid = document.getElementById('devices-grid');
    if (!grid) return;

    var expectedHandles = (devices || []).map(function(device) {
        return device && device.handle != null ? String(device.handle) : null;
    }).filter(Boolean);
    var existingCards = Array.prototype.slice.call(grid.querySelectorAll('.device-card'));
    var existingHandles = existingCards.map(function(card) {
        return card.dataset.handle;
    }).filter(Boolean);
    var hasEmptyState = !!grid.querySelector('.empty-state');

    if (!devices || devices.length === 0) {
        if (existingCards.length > 0 || !hasEmptyState) {
            renderDevicesGrid([]);
        } else {
            _updateDevicesCount([]);
        }
        return;
    }

    if (hasEmptyState || existingHandles.length !== expectedHandles.length) {
        renderDevicesGrid(devices);
        return;
    }

    for (var i = 0; i < expectedHandles.length; i++) {
        if (existingHandles[i] !== expectedHandles[i]) {
            renderDevicesGrid(devices);
            return;
        }
    }

    _updateDevicesCount(devices);

    devices.forEach(function(device) {
        var handle = device.handle.toString();
        var card = document.querySelector('[data-handle="' + handle + '"]');
        if (!card) {
            renderDevicesGrid(devices);
            return;
        }

        var labelEl = card.querySelector('.device-label');
        var distEl = card.querySelector('.device-dist');
        var badgesEl = card.querySelector('.device-card-badges');

        if (labelEl) labelEl.textContent = _deviceLabel(device);
        if (distEl) distEl.textContent = _formatDist(device.distance);
        if (badgesEl) badgesEl.innerHTML = _buildDeviceCardBadges(device, handle);
        card.classList.toggle('active', activePlayerHandle === handle);
    });
}

function _isDevicePlaying(handle) {
    var mp = mediaPlayerStates[handle];
    var info = mp && mp.info ? getEffectiveInfo(handle, mp.info) : null;
    return !!(info && info.url && !info.paused);
}

function _getDeviceStartupBadge(handle) {
    var state = getStartupState(handle);
    if (!state) return '';

    var label = getStartupPhaseLabel(state).toUpperCase();
    var style = 'background:var(--accent-dim);color:var(--text-accent);border:1px solid var(--accent);';

    if (state.phase === 'failed' || state.phase === 'timed_out') {
        style = 'background:var(--red-dim);color:var(--red);border:1px solid var(--red);';
    } else if (state.phase === 'fallback') {
        style = 'background:rgba(245, 158, 11, 0.14);color:var(--yellow);border:1px solid var(--yellow);';
    } else if (state.phase === 'stopped' || state.phase === 'superseded') {
        style = 'background:rgba(148, 163, 184, 0.14);color:var(--muted);border:1px solid rgba(148, 163, 184, 0.35);';
    }

    return '<span class="badge" style="' + style + '">' + safeText(label) + '</span>';
}

function _buildDeviceCardBadges(device, handle) {
    var resolvedHandle = handle;
    if (!resolvedHandle && device && device.handle != null) {
        resolvedHandle = device.handle.toString();
    }

    var mp = resolvedHandle ? mediaPlayerStates[resolvedHandle] : null;
    var info = mp && mp.info ? getEffectiveInfo(resolvedHandle, mp.info) : null;
    var isPlaybackVideo = info ? info.video !== false : !!(device && device.hasVideo);
    var typeIcon = isPlaybackVideo ? _iconVideo() : _iconMusic();

    var audibleBadge = device && device.visibleBecause === 'audible'
        ? '<span class="badge badge-type">AUDIBLE</span>'
        : '';

    return (_isDevicePlaying(resolvedHandle) ? '<span class="badge badge-playing">PLAYING</span>' : '') +
        _getDeviceStartupBadge(resolvedHandle) +
        audibleBadge +
        '<span class="badge badge-type">' + typeIcon + '</span>';
}

function _updateDevicesCount(devices) {
    var count = document.getElementById('devices-count');
    if (!count) return;

    if (!devices || devices.length === 0) {
        count.textContent = 'None found';
        return;
    }

    var playing = devices.reduce(function(total, device) {
        var handle = device && device.handle != null ? device.handle.toString() : null;
        return total + (handle && _isDevicePlaying(handle) ? 1 : 0);
    }, 0);
    var starting = devices.reduce(function(total, device) {
        var handle = device && device.handle != null ? device.handle.toString() : null;
        return total + (handle && isStartupPending(getStartupState(handle)) ? 1 : 0);
    }, 0);

    count.textContent = devices.length + ' visible'
        + (playing > 0 ? ' | ' + playing + ' playing' : '')
        + (starting > 0 ? ' | ' + starting + ' starting' : '');
}

function _buildDeviceCard(device, handle, isActive) {
    var card = document.createElement('div');
    card.className = 'device-card' + (isActive ? ' active' : '');
    card.dataset.handle = handle;
    card.setAttribute('role', 'button');
    card.setAttribute('tabindex', '0');
    card.onclick = function() { selectDevice(handle); };
    card.onkeydown = function(e) { if (e.key === 'Enter' || e.key === ' ') selectDevice(handle); };

    var deviceIcon = device.type === 'vehicle' ? _iconCar() : _iconSpeaker();
    card.innerHTML =
        '<div class="device-card-icon">' + deviceIcon + '</div>' +
        '<div class="device-card-body">' +
            '<div class="device-label">' + safeText(_deviceLabel(device)) + '</div>' +
            '<div class="device-dist">' + _formatDist(device.distance) + '</div>' +
        '</div>' +
        '<div class="device-card-badges">' +
            _buildDeviceCardBadges(device, handle) +
        '</div>';

    return card;
}

function selectDevice(handle) {
    activePlayerHandle = handleKey(handle);
    _lastActiveHandle  = activePlayerHandle;
    document.querySelectorAll('.device-card').forEach(function(c) {
        c.classList.toggle('active', c.dataset.handle === handleKey(handle));
    });
    updateBottomPlayer();
    updateNowPlayingPanel();
}

function _deviceLabel(device) {
    return getDeviceLabelByHandle(device && device.handle);
}

function _formatDist(d) {
    return d >= 0 ? Math.round(d) + 'm away' : 'Nearby';
}

function _iconSpeaker() { return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="4" y="2" width="16" height="20" rx="2"/><circle cx="12" cy="14" r="4"/><line x1="12" y1="6" x2="12.01" y2="6"/></svg>'; }
function _iconCar()     { return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 17H3a2 2 0 01-2-2V9a2 2 0 012-2h18a2 2 0 012 2v6a2 2 0 01-2 2h-2M5 17h14M5 17l-1 4m14-4l1 4"/><rect x="5" y="7" width="14" height="6" rx="1"/></svg>'; }
function _iconMusic()   { return '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>'; }
function _iconVideo()   { return '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>'; }


'use strict';

var _isScrubbing = false;
var _isAdjustingVolume = false;
var _seekDragValue = null;
var _volumeDragValue = null;
var _lastSeekSendAt = 0;
var _lastVolumeSendAt = 0;
var _seekThrottleMs = 180;
var _volumeThrottleMs = 120;

function _h() { return activePlayerHandle ? parseInt(activePlayerHandle, 10) : null; }

function requestPlaybackOnHandle(handle, options) {
    var numericHandle = Number(handle);
    if (!Number.isFinite(numericHandle)) {
        return;
    }

    selectDevice(numericHandle);
    requestedStartupStates[String(numericHandle)] = {
        handle: numericHandle,
        phase: 'requested',
        title: options && options.title ? options.title : (options && options.url ? options.url : ''),
        url: options && options.url ? options.url : '',
        message: 'Preparing playback.',
        requestedAt: Date.now(),
        expiresAt: Date.now() + 5000
    };
    updateBottomPlayer();
    updateNowPlayingPanel();
    sendMessage('play', {
        handle: numericHandle,
        options: options || {}
    });
}

function hasSessionAccess(info) {
    var lock = info && info.sessionLock;
    if (!lock || lock.active !== true) return true;
    if (permissions.manage === true) return true;
    return lock.accessGranted === true || lock.isOwner === true;
}

function canControlMediaPlayer(mp) {
    if (!mp || !mp.info || !mp.info.url) return false;
    if (mp.canInteract === false) return false;
    if (mp.info.locked && !permissions.manage) return false;
    if (!hasSessionAccess(mp.info)) return false;
    return true;
}

function canUsePrevious(handle, mp) {
    var session = getEffectiveDeviceSession(handle);
    if (!session || session.canGoPrevious !== true) return false;
    if (mp && mp.canInteract === false) return false;
    return hasSessionAccess((mp && mp.info) || buildSessionInfo(handle, session));
}

function formatRemainingTime(targetTime) {
    var target = Number(targetTime);
    if (!Number.isFinite(target) || target <= 0) return '';

    var remaining = Math.max(0, Math.ceil(target - (Date.now() / 1000)));
    var minutes = Math.floor(remaining / 60);
    var seconds = remaining % 60;
    return minutes + ':' + (seconds < 10 ? '0' : '') + seconds;
}

function getResetStatusText(handle) {
    var session = getEffectiveDeviceSession(handle);
    if (!session || session.resetActive !== true || !session.idleResetAt) {
        return '';
    }

    return 'Reset in ' + formatRemainingTime(session.idleResetAt);
}

function canCancelStartupForHandle(handle) {
    var state = getStartupState(handle);
    return !!(handle && isStartupPending(state));
}

function cancelStartupForCurrentHandle() {
    if (!activePlayerHandle) return;
    var startupState = getCurrentStartupState();
    sendMessage('cancelStartup', {
        handle: _h(),
        attemptId: startupState ? startupState.attemptId || null : null,
        playbackToken: startupState ? startupState.playbackToken || null : null
    });
}

function sendSeekUpdate(value, force) {
    if (!activePlayerHandle) return;
    var now = Date.now();
    if (!force && (now - _lastSeekSendAt) < _seekThrottleMs) return;
    _lastSeekSendAt = now;
    var key = handleKey(activePlayerHandle);
    if (key && mediaPlayerStates[key]) {
        mediaPlayerStates[key].offset = value;
    }
    sendMessage('seekToTime', { handle: _h(), offset: value });
}

function sendVolumeUpdate(value, force) {
    if (!activePlayerHandle) return;
    var now = Date.now();
    if (!force && (now - _lastVolumeSendAt) < _volumeThrottleMs) return;
    _lastVolumeSendAt = now;
    setPendingControlField(activePlayerHandle, 'volume', value);
    var key = handleKey(activePlayerHandle);
    if (key && mediaPlayerStates[key] && mediaPlayerStates[key].info) {
        mediaPlayerStates[key].info.volume = value;
    }
    if (key && deviceSessions[key] && deviceSessions[key].settings) {
        deviceSessions[key].settings.volume = value;
    }
    sendMessage('setVolume', { handle: _h(), volume: value });
}

function updateSeekPreviewLabels(value, duration) {
    var cur = document.getElementById('np-time-current');
    var tot = document.getElementById('np-time-total');
    if (cur) cur.textContent = timeToString(value);
    if (tot) {
        tot.textContent = (duration && duration > 0) ? timeToString(duration) : 'Live';
    }
}

function initPlayerControls() {
    var progress = document.getElementById('np-progress');
    var volume   = document.getElementById('np-volume');

    if (progress) {
        var beginSeek = function() {
            if (progress.disabled) return;
            _isScrubbing = true;
            _seekDragValue = parseFloat(progress.value) || 0;
        };

        var commitSeek = function() {
            if (!_isScrubbing) return;
            var value = parseFloat(progress.value) || 0;
            sendSeekUpdate(value, true);
            _isScrubbing = false;
            _seekDragValue = null;
        };

        progress.addEventListener('mousedown', beginSeek);
        progress.addEventListener('touchstart', beginSeek, { passive: true });

        progress.addEventListener('input', function() {
            if (!_isScrubbing) beginSeek();
            var value = parseFloat(this.value) || 0;
            var max = parseFloat(this.max) || 0;
            _seekDragValue = value;
            _updateProgressFill(this);
            updateSeekPreviewLabels(value, max);
            sendSeekUpdate(value, false);
        });

        progress.addEventListener('change', commitSeek);
        progress.addEventListener('mouseup', commitSeek);
        progress.addEventListener('touchend', commitSeek);
        progress.addEventListener('blur', commitSeek);
    }

    if (volume) {
        var beginVolume = function() {
            if (volume.disabled) return;
            _isAdjustingVolume = true;
            _volumeDragValue = parseInt(volume.value, 10) || 0;
        };

        var commitVolume = function() {
            if (!_isAdjustingVolume) return;
            var value = parseInt(volume.value, 10) || 0;
            sendVolumeUpdate(value, true);
            _isAdjustingVolume = false;
            _volumeDragValue = null;
        };

        volume.addEventListener('mousedown', beginVolume);
        volume.addEventListener('touchstart', beginVolume, { passive: true });

        volume.addEventListener('input', function() {
            if (!_isAdjustingVolume) beginVolume();
            var v = parseInt(this.value, 10) || 0;
            _volumeDragValue = v;
            var volumeLabel = document.getElementById('np-volume-val');
            if (volumeLabel) volumeLabel.textContent = v + '%';
            _updateProgressFill(this);
            sendVolumeUpdate(v, false);
        });

        volume.addEventListener('change', commitVolume);
        volume.addEventListener('mouseup', commitVolume);
        volume.addEventListener('touchend', commitVolume);
        volume.addEventListener('blur', commitVolume);
    }
}

function _updateBottomPlayerLive(progress, vol, volVal, timeCur, timeTot, hasInfo, hasDuration, canSeek, canControl, duration, offset, currentVol) {
    if (vol) {
        vol.disabled = !canControl;
        if (_isAdjustingVolume && _volumeDragValue != null) {
            vol.value = _volumeDragValue;
        } else {
            vol.value = currentVol;
        }
        _updateProgressFill(vol);
    }

    if (volVal) {
        var volForLabel = (_isAdjustingVolume && _volumeDragValue != null) ? _volumeDragValue : currentVol;
        volVal.textContent = volForLabel + '%';
    }

    if (progress) {
        if (hasDuration) {
            progress.max = duration;
            progress.disabled = !canSeek;
            if (_isScrubbing && _seekDragValue != null) {
                progress.value = _seekDragValue;
                updateSeekPreviewLabels(_seekDragValue, duration);
            } else {
                progress.value = Math.max(0, Math.min(offset, duration));
                if (timeCur) timeCur.textContent = timeToString(offset);
                if (timeTot) timeTot.textContent = timeToString(duration);
            }
        } else {
            progress.disabled = true;
            progress.max = 100;
            progress.value = 0;
            if (timeCur) timeCur.textContent = hasInfo ? timeToString(offset) : '0:00';
            if (timeTot) timeTot.textContent = hasInfo ? 'Live' : '0:00';
        }
        _updateProgressFill(progress);
    }
}

function updateBottomPlayer() {
    var titleEl   = document.getElementById('np-title');
    var subtitleEl = document.getElementById('np-subtitle');
    var playBtn   = document.getElementById('np-play');
    var prevBtn   = document.getElementById('np-prev');
    var nextBtn   = document.getElementById('np-next');
    var stopBtn   = document.getElementById('np-stop');
    var loopBtn   = document.getElementById('np-loop');
    var muteBtn   = document.getElementById('np-mute');
    var videoBtn  = document.getElementById('np-video');
    var progress  = document.getElementById('np-progress');
    var vol       = document.getElementById('np-volume');
    var volVal    = document.getElementById('np-volume-val');
    var timeCur   = document.getElementById('np-time-current');
    var timeTot   = document.getElementById('np-time-total');

    if (!titleEl) return;

    var liveMp = getCurrentLiveMP();
    var mp = liveMp || getCurrentSessionMP();
    var currentHandle = handleKey(activePlayerHandle);
    var startupState = getStartupState(currentHandle);
    var startupPending = isStartupPending(startupState);
    var startupFailed = isStartupFailed(startupState);
    var localFailure = getLocalPlaybackFailure(currentHandle);
    var hasLocalFailure = !!(localFailure && !startupPending);

    if (!activePlayerHandle) {
        _setPlayerIdle(titleEl, subtitleEl, playBtn, prevBtn, nextBtn, stopBtn, loopBtn, muteBtn, videoBtn, progress, vol, timeCur, timeTot);
        return;
    }

    var rawInfo = liveMp && liveMp.info ? liveMp.info : null;
    var info = getEffectiveInfo(currentHandle, rawInfo);
    var session = getEffectiveDeviceSession(currentHandle);
    var hasInfo = !!(info && info.url);
    var canControl = canControlMediaPlayer(liveMp);
    var duration = hasInfo ? Number(info.duration) : 0;
    var hasDuration = Number.isFinite(duration) && duration > 0;
    var canSeek = canControl && hasDuration;
    var canGoPrevious = canUsePrevious(currentHandle, liveMp || mp);
    var isPaused = hasInfo && info.paused;
    var isMuted = hasInfo && info.muted;
    var loopMode = normalizeLoopMode(info && info.loopMode, info && info.loop);
    var deviceCapability = getDeviceCapability(currentHandle, info, session);
    var loopLabel = LOOP_MODE_LABELS[loopMode] || LOOP_MODE_LABELS.off;
    var nextMode = nextLoopMode(loopMode);
    var offset = (liveMp && liveMp.offset !== undefined) ? Number(liveMp.offset) || 0 : 0;
    if (hasDuration && offset > duration) {
        offset = duration;
    }
    var currentVol = (hasInfo && info.volume != null) ? parseInt(info.volume, 10) : 100;
    if (!Number.isFinite(currentVol)) currentVol = 100;
    var canCancelStartup = canCancelStartupForHandle(currentHandle);
    var titleText = hasInfo && info.title ? info.title : (startupPending ? getStartupDisplayTitle(startupState) : (startupFailed ? 'Playback Failed' : 'Nothing Playing'));
    var subtitleText = getCurrentDeviceLabel();
    var resetStatusText = getResetStatusText(currentHandle);
    if (startupPending) {
        subtitleText += ' - ' + getStartupPhaseLabel(startupState);
    } else if (hasLocalFailure) {
        subtitleText += ' - ' + (localFailure.message || 'Playback failed on this client.');
    } else if (startupFailed) {
        subtitleText += ' - ' + getStartupStatusText(startupState);
    } else if (!hasInfo && resetStatusText) {
        subtitleText += ' - ' + resetStatusText;
    }

    var playerKey = [
        currentHandle || 'none',
        hasInfo ? 1 : 0,
        hasInfo && info.title ? info.title : '',
        subtitleText,
        canControl ? 1 : 0,
        canSeek ? 1 : 0,
        isPaused ? 1 : 0,
        isMuted ? 1 : 0,
        (hasInfo && info.video !== false) ? 1 : 0,
        deviceCapability,
        loopMode,
        currentVol,
        hasDuration ? duration : 'live',
        hasLocalFailure ? 1 : 0,
        hasLocalFailure ? (localFailure.message || '') : '',
        startupState ? startupState.attemptId || '' : '',
        startupState ? startupState.phase || '' : '',
        startupState ? startupState.message || '' : '',
        canCancelStartup ? 1 : 0,
        canGoPrevious ? 1 : 0,
        resetStatusText,
        session && session.historyCount ? session.historyCount : 0
    ].join('|');

    if (playerKey === _lastBottomPlayerKey) {
        if (hasInfo) {
            _updateBottomPlayerLive(progress, vol, volVal, timeCur, timeTot, hasInfo, hasDuration, canSeek, canControl, duration, offset, currentVol);
        } else {
            if (progress) {
                progress.disabled = true;
                progress.max = 100;
                progress.value = 0;
                _updateProgressFill(progress);
            }
            if (vol) {
                vol.disabled = true;
                vol.value = 100;
                _updateProgressFill(vol);
            }
            if (volVal) volVal.textContent = '100%';
            if (timeCur) timeCur.textContent = startupPending ? getStartupPhaseLabel(startupState) : (hasLocalFailure ? 'Error' : '0:00');
            if (timeTot) timeTot.textContent = startupPending ? '...' : (hasLocalFailure ? 'Local' : '0:00');
        }
        return;
    }
    _lastBottomPlayerKey = playerKey;

    titleEl.textContent = titleText;
    if (subtitleEl) subtitleEl.textContent = subtitleText;

    if (playBtn) {
        var playDisabled = !canControl;
        var playLabel = (!hasInfo || isPaused) ? 'Play' : 'Pause';
        playBtn.disabled = playDisabled;
        playBtn.setAttribute('data-tooltip', playLabel);
        playBtn.setAttribute('aria-label', playLabel);
        var playState = (!hasInfo || isPaused) ? 'paused' : 'playing';
        if (playBtn.dataset.state !== playState) {
            playBtn.innerHTML = (!hasInfo || isPaused)
                ? '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21"/></svg>'
                : '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg>';
            playBtn.dataset.state = playState;
        }
        playBtn.onclick = function() {
            if (playDisabled) return;
            var nextPaused = !isPaused;
            setPendingControlField(activePlayerHandle, 'paused', nextPaused);
            updateBottomPlayer();
            sendMessage(nextPaused ? 'pause' : 'play', { handle: _h() });
        };
    }

    if (stopBtn) {
        stopBtn.disabled = !(canControl || canCancelStartup);
        stopBtn.setAttribute('data-tooltip', canCancelStartup ? 'Cancel startup' : 'Stop playback');
        stopBtn.setAttribute('aria-label', canCancelStartup ? 'Cancel startup' : 'Stop playback');
        stopBtn.onclick  = function() {
            if (canCancelStartup) {
                cancelStartupForCurrentHandle();
                return;
            }
            sendMessage('stop', { handle: _h() });
        };
    }

    if (prevBtn) {
        prevBtn.disabled = !canGoPrevious;
        prevBtn.setAttribute('data-tooltip', 'Previous track');
        prevBtn.setAttribute('aria-label', 'Previous track');
        prevBtn.onclick  = function() {
            if (!canGoPrevious) return;
            sendMessage('previous', { handle: _h() });
        };
    }

    if (nextBtn) {
        nextBtn.disabled = !canControl;
        nextBtn.setAttribute('data-tooltip', 'Next track');
        nextBtn.setAttribute('aria-label', 'Next track');
        nextBtn.onclick  = function() { sendMessage('next', { handle: _h() }); };
    }

    if (loopBtn) {
        loopBtn.disabled = !canControl;
        loopBtn.classList.toggle('active', loopMode !== 'off');
        loopBtn.title = loopLabel + ' (next: ' + (LOOP_MODE_LABELS[nextMode] || nextMode) + ')';
        loopBtn.setAttribute('data-tooltip', loopBtn.title);
        loopBtn.setAttribute('aria-label', loopBtn.title);
        if (loopBtn.dataset.mode !== loopMode) {
            loopBtn.innerHTML = getLoopIcon(loopMode);
            loopBtn.dataset.mode = loopMode;
        }
        loopBtn.onclick = function() {
            setPendingControlField(activePlayerHandle, 'loopMode', nextMode);
            updateBottomPlayer();
            sendMessage('setLoopMode', { handle: _h(), loopMode: nextMode });
        };
    }

    if (muteBtn) {
        muteBtn.disabled = !canControl;
        muteBtn.classList.toggle('active', !!isMuted);
        muteBtn.setAttribute('data-tooltip', isMuted ? 'Unmute' : 'Mute');
        muteBtn.setAttribute('aria-label', isMuted ? 'Unmute' : 'Mute');
        var muteState = isMuted ? 'muted' : 'unmuted';
        if (muteBtn.dataset.state !== muteState) {
            muteBtn.innerHTML = isMuted
                ? '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><line x1="23" y1="9" x2="17" y2="15"/><line x1="17" y1="9" x2="23" y2="15"/></svg>'
                : '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/></svg>';
            muteBtn.dataset.state = muteState;
        }
        muteBtn.onclick = function() {
            var nextMuted = !isMuted;
            setPendingControlField(activePlayerHandle, 'muted', nextMuted);
            updateBottomPlayer();
            sendMessage(nextMuted ? 'mute' : 'unmute', { handle: _h() });
        };
    }

    if (videoBtn) {
        var hasVideo = hasInfo && info.video !== false;
        var canToggleVideo = canControl && deviceCapability !== 'audio';
        var videoLabel = canToggleVideo ? (hasVideo ? 'Disable video' : 'Enable video') : 'Audio-only device';
        videoBtn.disabled = !canToggleVideo;
        videoBtn.classList.toggle('active', !!hasVideo && canToggleVideo);
        videoBtn.setAttribute('data-tooltip', videoLabel);
        videoBtn.setAttribute('aria-label', videoLabel);
        videoBtn.onclick  = function() {
            if (!canToggleVideo) return;
            var nextVideo = !hasVideo;
            setPendingControlField(activePlayerHandle, 'video', nextVideo);
            updateBottomPlayer();
            sendMessage(nextVideo ? 'enableVideo' : 'disableVideo', { handle: _h() });
        };
    }

    if (hasInfo) {
        _updateBottomPlayerLive(progress, vol, volVal, timeCur, timeTot, hasInfo, hasDuration, canSeek, canControl, duration, offset, currentVol);
        return;
    }

    if (progress) {
        progress.disabled = true;
        progress.max = 100;
        progress.value = 0;
        _updateProgressFill(progress);
    }
    if (vol) {
        vol.disabled = true;
        vol.value = 100;
        _updateProgressFill(vol);
    }
    if (volVal) volVal.textContent = '100%';
    if (timeCur) timeCur.textContent = startupPending ? getStartupPhaseLabel(startupState) : (hasLocalFailure ? 'Error' : '0:00');
    if (timeTot) timeTot.textContent = startupPending ? '...' : (hasLocalFailure ? 'Local' : '0:00');
}

function _setPlayerIdle(titleEl, subtitleEl, playBtn, prevBtn, nextBtn, stopBtn, loopBtn, muteBtn, videoBtn, progress, vol, timeCur, timeTot) {
    _isScrubbing = false;
    _isAdjustingVolume = false;
    _seekDragValue = null;
    _volumeDragValue = null;

    titleEl.textContent    = 'No Device Selected';
    subtitleEl.textContent = 'Select a nearby device to begin';
    [playBtn, prevBtn, nextBtn, stopBtn, loopBtn, muteBtn, videoBtn].forEach(function(b) { if (b) b.disabled = true; });
    if (progress) { progress.disabled = true; progress.value = 0; _updateProgressFill(progress); }
    if (vol)      { vol.disabled = true; vol.value = 100; _updateProgressFill(vol); }
    if (timeCur)  timeCur.textContent = '0:00';
    if (timeTot)  timeTot.textContent = '0:00';
    if (playBtn) playBtn.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21"/></svg>';
    if (playBtn) playBtn.dataset.state = 'paused';
    if (loopBtn) {
        loopBtn.dataset.mode = 'off';
        loopBtn.innerHTML = getLoopIcon('off');
    }
    if (muteBtn) muteBtn.dataset.state = 'unmuted';
    _lastBottomPlayerKey = '';
}

function _updateProgressFill(el) {
    if (!el) return;
    var pct = el.max > 0 ? (el.value / el.max) * 100 : 0;
    el.style.setProperty('--fill', pct + '%');
}

function getQueueItemTitle(queueEntry, index) {
    return (queueEntry && queueEntry.options && queueEntry.options.title)
        || (queueEntry && queueEntry.options && queueEntry.options.url)
        || ('Track ' + (index + 1));
}

function getQueueItemSubtitle(queueEntry) {
    var bits = [];
    var author = queueEntry && queueEntry.options && queueEntry.options.author;
    if (author) bits.push(author);

    var addedBy = queueEntry && queueEntry.name;
    if (addedBy) bits.push('Added by ' + addedBy);

    var duration = queueEntry && queueEntry.options ? Number(queueEntry.options.duration) : 0;
    if (Number.isFinite(duration) && duration > 0) {
        bits.push(timeToString(duration));
    }

    return bits.length > 0 ? bits.join(' | ') : 'Queued';
}

function getQueueSignature(queue, canControl) {
    if (!Array.isArray(queue) || queue.length === 0) {
        return '0:' + (canControl ? '1' : '0');
    }

    var parts = [String(queue.length), canControl ? '1' : '0'];
    queue.forEach(function(q, idx) {
        parts.push(getQueueItemTitle(q, idx));
        parts.push(getQueueItemSubtitle(q));
    });
    return parts.join('~');
}

function wrapTrackEntries(entries, newestFirst) {
    var list = Array.isArray(entries) ? entries.slice() : [];
    if (newestFirst) {
        list.reverse();
    }
    return list.map(function(entry) {
        if (entry && entry.options) {
            return entry;
        }
        return { options: entry };
    });
}

function getTrackEntriesSignature(entries) {
    var wrapped = wrapTrackEntries(entries, false);
    return getQueueSignature(wrapped, false);
}

function getInlineQueueHtml(mp) {
    var info = mp && mp.info ? mp.info : null;
    var queue = info && Array.isArray(info.queue) ? info.queue : [];
    var canControl = canControlMediaPlayer(mp);
    var nextUpTitle = queue.length > 0 ? getQueueItemTitle(queue[0], 0) : '';

    var html =
        '<div class="np-queue-section">' +
            '<div class="np-queue-header">' +
                '<span class="np-queue-title">Manual Queue</span>' +
                '<span class="np-queue-count">' + queue.length + '</span>' +
            '</div>';

    if (nextUpTitle) {
        html += '<div class="np-queue-next" title="' + safeText(nextUpTitle) + '">First queued: ' + safeText(nextUpTitle) + '</div>';
    }

    if (queue.length === 0) {
        html += '<div class="np-queue-empty">Queue is empty.</div>';
    } else {
        html += '<div class="np-queue-list">';
        queue.forEach(function(q, idx) {
            var qTitle = getQueueItemTitle(q, idx);
            var qSub = getQueueItemSubtitle(q);
            html +=
                '<div class="np-queue-item">' +
                    '<div class="np-queue-item-left">' +
                        '<span class="np-queue-index">' + (idx + 1) + '</span>' +
                        '<div class="np-queue-item-meta">' +
                            '<div class="np-queue-item-title">' + safeText(qTitle) + '</div>' +
                            '<div class="np-queue-item-sub">' + safeText(qSub) + '</div>' +
                        '</div>' +
                    '</div>' +
                    '<button class="btn-icon btn-sm np-queue-add" data-queue-playlist-index="' + idx + '" data-tooltip="Add to playlist" aria-label="Add queue item to playlist">' +
                        '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>' +
                    '</button>' +
                    '<button class="btn-icon btn-sm np-queue-remove" data-queue-index="' + (idx + 1) + '"' + (canControl ? '' : ' disabled') + ' data-tooltip="Remove from queue" aria-label="Remove from queue">' +
                        '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4h6v2"/></svg>' +
                    '</button>' +
                '</div>';
        });
        html += '</div>';
    }

    html += '</div>';
    return html;
}

function getReadOnlyTrackListHtml(title, entries, emptyText, subtitleText, newestFirst) {
    var wrapped = wrapTrackEntries(entries, newestFirst);
    var html =
        '<div class="np-queue-section">' +
            '<div class="np-queue-header">' +
                '<span class="np-queue-title">' + safeText(title) + '</span>' +
                '<span class="np-queue-count">' + wrapped.length + '</span>' +
            '</div>';

    if (subtitleText) {
        html += '<div class="np-queue-next">' + safeText(subtitleText) + '</div>';
    }

    if (wrapped.length === 0) {
        html += '<div class="np-queue-empty">' + safeText(emptyText) + '</div>';
    } else {
        html += '<div class="np-queue-list">';
        wrapped.forEach(function(entry, index) {
            html +=
                '<div class="np-queue-item np-queue-item-readonly">' +
                    '<div class="np-queue-item-left">' +
                        '<span class="np-queue-index">' + (index + 1) + '</span>' +
                        '<div class="np-queue-item-meta">' +
                            '<div class="np-queue-item-title">' + safeText(getQueueItemTitle(entry, index)) + '</div>' +
                            '<div class="np-queue-item-sub">' + safeText(getQueueItemSubtitle(entry)) + '</div>' +
                        '</div>' +
                    '</div>' +
                '</div>';
        });
        html += '</div>';
    }

    html += '</div>';
    return html;
}

function getNowPlayingSecondaryListsHtml(handle, mp, session) {
    var activeInfo = mp && mp.info ? mp.info : null;
    var effectiveSession = session || getEffectiveDeviceSession(handle);
    if (!effectiveSession) {
        return '';
    }

    var manualQueue = activeInfo && Array.isArray(activeInfo.queue) ? activeInfo.queue : (effectiveSession.queue || []);
    var playbackPreview = Array.isArray(effectiveSession.playbackPreview) ? effectiveSession.playbackPreview : [];
    var history = Array.isArray(effectiveSession.history) ? effectiveSession.history : [];
    var loopMode = normalizeLoopMode(
        activeInfo && activeInfo.loopMode ? activeInfo.loopMode : (effectiveSession.settings && effectiveSession.settings.loopMode),
        activeInfo ? activeInfo.loop : (effectiveSession.settings && effectiveSession.settings.loopMode === 'track')
    );

    if ((!manualQueue || manualQueue.length === 0) && playbackPreview.length === 0 && history.length === 0) {
        return '';
    }

    return getReadOnlyTrackListHtml(
        'Playback Preview',
        playbackPreview,
        'Nothing is scheduled after the current loop mode.',
        LOOP_MODE_LABELS[loopMode] || LOOP_MODE_LABELS.off,
        false
    ) + getReadOnlyTrackListHtml(
        'History',
        history,
        'Nothing has been played on this device yet.',
        'Clears when the device session resets.',
        true
    );
}

function removeQueueItemLocally(handle, index) {
    var key = handleKey(handle);
    if (!key || !mediaPlayerStates[key] || !mediaPlayerStates[key].info) return;
    var queue = mediaPlayerStates[key].info.queue;
    if (!Array.isArray(queue)) return;
    queue.splice(index - 1, 1);
}

function getStartupMetaHtml(state) {
    if (!state) return '';

    var chips = [
        '<span class="badge badge-source">' + safeText(getStartupPhaseLabel(state)) + '</span>'
    ];

    if (state.provider) {
        chips.push('<span class="badge badge-type">' + safeText(state.provider) + '</span>');
    }
    if (state.retryCount) {
        chips.push('<span class="badge badge-type">Retry ' + safeText(String(state.retryCount)) + '</span>');
    }
    if (state.fallbackUsed) {
        chips.push('<span class="badge" style="background:rgba(245, 158, 11, 0.14);color:var(--yellow);border:1px solid var(--yellow);">Fallback</span>');
    }

    return '<div class="np-panel-actions" style="margin-top:12px;flex-wrap:wrap;">' + chips.join('') + '</div>';
}

function bindNowPlayingPanelActions(panel) {
    var settingsBtn = panel.querySelector('[data-action="open-device-settings"]');
    if (settingsBtn) settingsBtn.onclick = openAdminModal;

    var previousBtn = panel.querySelector('[data-action="play-previous"]');
    if (previousBtn) {
        previousBtn.onclick = function() {
            if (!activePlayerHandle) return;
            sendMessage('previous', { handle: _h() });
        };
    }

    var cancelStartupBtn = panel.querySelector('[data-action="cancel-startup"]');
    if (cancelStartupBtn) {
        cancelStartupBtn.onclick = function() {
            cancelStartupForCurrentHandle();
        };
    }

    var addCurrentBtn = panel.querySelector('[data-action="add-current-to-playlist"]');
    if (addCurrentBtn) {
        addCurrentBtn.onclick = function() {
            var mp = getCurrentLiveMP();
            if (!mp || !mp.info || !mp.info.url) return;
            openAddToPlaylistModal({
                title: mp.info.title,
                url: mp.info.originalUrl || mp.info.url,
                duration: mp.info.duration,
                author: mp.info.author,
                thumbnail: mp.info.thumbnail
            });
        };
    }

    panel.querySelectorAll('[data-queue-playlist-index]').forEach(function(btn) {
        btn.onclick = function() {
            var mp = getCurrentLiveMP() || getCurrentSessionMP();
            var queue = mp && mp.info && Array.isArray(mp.info.queue) ? mp.info.queue : [];
            var index = parseInt(this.dataset.queuePlaylistIndex, 10);
            var entry = Number.isFinite(index) ? queue[index] : null;
            var options = entry && entry.options ? entry.options : null;
            if (!options || !options.url) return;
            openAddToPlaylistModal({
                title: options.title || options.url,
                url: options.originalUrl || options.url,
                duration: options.duration,
                author: options.author,
                thumbnail: options.thumbnail
            });
        };
    });

    panel.querySelectorAll('[data-queue-index]').forEach(function(btn) {
        btn.onclick = function() {
            if (!activePlayerHandle) return;
            var index = parseInt(this.dataset.queueIndex, 10);
            if (!index || index < 1) return;
            removeQueueItemLocally(activePlayerHandle, index);
            updateNowPlayingPanel();
            sendMessage('removeFromQueue', { handle: _h(), index: index });
        };
    });
}

function getNowPlayingPanelRenderKey(mp) {
    if (!activePlayerHandle) {
        return 'idle';
    }

    var key = 'h:' + activePlayerHandle;
    var hasMedia = !!(mp && mp.info && mp.info.url);
    var startupState = getCurrentStartupState();
    var localFailure = getCurrentLocalPlaybackFailure();
    var session = getEffectiveDeviceSession(activePlayerHandle);
    var currentTrack = session && session.currentTrack ? session.currentTrack : null;
    var historySignature = getTrackEntriesSignature(session && session.history ? session.history : []);
    var previewSignature = getTrackEntriesSignature(session && session.playbackPreview ? session.playbackPreview : []);
    if (!hasMedia) {
        var queueOnly = mp && mp.info && Array.isArray(mp.info.queue) ? mp.info.queue : [];
        return key + ':selected:'
            + getCurrentDeviceLabel() + ':'
            + getQueueSignature(queueOnly, canControlMediaPlayer(mp)) + ':'
            + (startupState ? startupState.attemptId || '' : '') + '|'
            + (startupState ? startupState.phase || '' : '') + '|'
            + (startupState ? startupState.message || '' : '') + '|'
            + (localFailure ? localFailure.message || '' : '') + '|'
            + (session && session.historyCount ? session.historyCount : 0) + '|'
            + (session && session.canGoPrevious ? 1 : 0) + '|'
            + getResetStatusText(activePlayerHandle) + '|'
            + (currentTrack ? (currentTrack.title || currentTrack.url || '') : '') + '|'
            + historySignature + '|'
            + previewSignature;
    }

    var info = mp.info;
    var queue = Array.isArray(info.queue) ? info.queue : [];
    var duration = Number(info.duration);
    if (!Number.isFinite(duration)) duration = 0;

    return key + ':playing:'
        + (info.title || '') + '|'
        + (info.author || '') + '|'
        + (info.url || '') + '|'
        + (info.thumbnail || '') + '|'
        + duration + '|'
        + (localFailure ? localFailure.message || '' : '') + '|'
        + getQueueSignature(queue, canControlMediaPlayer(mp)) + '|'
        + historySignature + '|'
        + previewSignature;
}

function updateNowPlayingPanelTimeOnly(panel, mp) {
    if (!panel || !mp || !mp.info || !mp.info.url) return;
    var info = mp.info;
    var offset = Number(mp.offset) || 0;
    var duration = Number(info.duration);
    var hasDuration = Number.isFinite(duration) && duration > 0;

    if (hasDuration && offset > duration) {
        offset = duration;
    }

    var text = timeToString(offset) + ' / ' + (hasDuration ? timeToString(duration) : 'Live');
    var timeEl = panel.querySelector('#np-meta-time');
    if (timeEl && timeEl.textContent !== text) {
        timeEl.textContent = text;
    }
}

function updateNowPlayingPanel() {
    var panel = document.getElementById('now-playing-panel');
    if (!panel) return;

    var liveMp = getCurrentLiveMP();
    var mp = liveMp || getCurrentSessionMP();
    var startupState = getCurrentStartupState();
    var startupPending = isStartupPending(startupState);
    var startupFailed = isStartupFailed(startupState);
    var localFailure = getCurrentLocalPlaybackFailure();
    var hasLocalFailure = !!(localFailure && !startupPending);
    var settingsButtonHtml = '<button class="btn-outline btn-sm np-settings-btn" data-action="open-device-settings">Device Settings</button>';
    var panelKey = getNowPlayingPanelRenderKey(mp);

    if (panelKey === _lastNowPlayingPanelKey) {
        updateNowPlayingPanelTimeOnly(panel, mp);
        return;
    }

    _lastNowPlayingPanelKey = panelKey;

    if (!activePlayerHandle) {
        panel.innerHTML =
            '<div class="np-panel-empty">' +
                '<svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>' +
                '<p>Select a nearby device to begin</p>' +
                '<span class="np-panel-hint">Choose one device from the list above to reveal controls and settings.</span>' +
            '</div>';
        return;
    }

    if (!liveMp || !liveMp.info || !liveMp.info.url) {
        var statusHtml = '';
        var actionHtml = settingsButtonHtml;
        var session = getEffectiveDeviceSession(activePlayerHandle);
        var currentTrack = session && session.currentTrack ? session.currentTrack : null;
        var resetStatusText = getResetStatusText(activePlayerHandle);
        var canGoPrevious = canUsePrevious(activePlayerHandle, mp);
        var historyCount = session && Array.isArray(session.history)
            ? session.history.length
            : (session && Number.isFinite(Number(session.historyCount)) ? Number(session.historyCount) : 0);
        var queueCount = session && Number.isFinite(Number(session.queueLength))
            ? Number(session.queueLength)
            : ((session && Array.isArray(session.queue)) ? session.queue.length : 0);

        if (startupPending) {
            actionHtml += '<button class="btn-danger" data-action="cancel-startup">Cancel</button>';
            statusHtml =
                '<div class="np-panel-actions" style="margin-top:12px;align-items:flex-start;flex-direction:column;gap:8px;">' +
                    '<div style="display:flex;align-items:center;gap:10px;">' +
                        '<span class="search-status-spinner" aria-hidden="true"></span>' +
                        '<span>' + safeText(getStartupStatusText(startupState)) + '</span>' +
                    '</div>' +
                '</div>' +
                getStartupMetaHtml(startupState);
        } else if (startupFailed) {
            statusHtml =
                '<div class="np-panel-actions" style="margin-top:12px;align-items:flex-start;flex-direction:column;gap:8px;color:var(--red);">' +
                    '<span>' + safeText(getStartupStatusText(startupState)) + '</span>' +
                '</div>' +
                getStartupMetaHtml(startupState);
        }

        if (resetStatusText) {
            statusHtml +=
                '<div class="np-panel-actions" style="margin-top:12px;align-items:flex-start;flex-direction:column;gap:6px;">' +
                    '<span class="badge badge-type">' + safeText(resetStatusText) + '</span>' +
                '</div>';
        }

        if (historyCount > 0 || queueCount > 0) {
            statusHtml +=
                '<div class="np-panel-actions" style="margin-top:12px;flex-wrap:wrap;">' +
                    '<span class="badge badge-source">History ' + safeText(String(historyCount)) + '</span>' +
                    '<span class="badge badge-type">Queue ' + safeText(String(queueCount)) + '</span>' +
                '</div>';
        }

        if (canGoPrevious) {
            actionHtml += '<button class="btn-outline btn-sm" data-action="play-previous">Previous</button>';
        }

        var hintText = startupPending || startupFailed
            ? getStartupStatusText(startupState)
            : 'Play something from search or a playlist, or configure this device now.';
        if (!startupPending && !startupFailed && currentTrack) {
            hintText = 'Last played: ' + (currentTrack.title || currentTrack.url || 'Unknown media') + '.';
        }

        panel.innerHTML =
            '<div class="np-panel-empty np-panel-empty-selected">' +
                '<svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1"><circle cx="12" cy="12" r="9"/><path d="M12 8v4"/><circle cx="12" cy="16" r="1"/></svg>' +
                '<p>' + safeText(getCurrentDeviceLabel()) + ' is selected</p>' +
                '<span class="np-panel-hint">' + safeText(hintText) + '</span>' +
                statusHtml +
                '<div class="np-panel-actions">' + actionHtml + '</div>' +
                getInlineQueueHtml(mp) +
                getNowPlayingSecondaryListsHtml(activePlayerHandle, mp, session) +
            '</div>';
        bindNowPlayingPanelActions(panel);
        applyStaticTooltips();
        return;
    }

    var info = liveMp.info;
    var offset = liveMp.offset || 0;
    var normalizedThumb = normalizeRemoteAssetUrl(info.thumbnail || '');
    var statusHtml = hasLocalFailure
        ? '<div class="np-panel-actions" style="margin-top:12px;align-items:flex-start;flex-direction:column;gap:8px;color:var(--red);"><span>' + safeText(localFailure.message || 'Playback failed on this client.') + '</span></div>'
        : '';
    var thumbHtml = normalizedThumb
        ? '<div class="np-thumb" style="background-image:url(' + encodeURI(normalizedThumb) + ')"></div>'
        : '<div class="np-thumb np-thumb-empty"><svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg></div>';

    panel.innerHTML =
        '<div class="np-panel-inner">' +
            thumbHtml +
            '<div class="np-meta">' +
                '<div class="np-meta-title" title="' + safeText(info.title) + '">' + safeText(info.title || 'Untitled') + '</div>' +
                '<div class="np-meta-author">' + safeText(info.author || '') + '</div>' +
                '<div class="np-meta-time" id="np-meta-time">' + timeToString(offset) + ' / ' + (info.duration ? timeToString(info.duration) : 'Live') + '</div>' +
                (info.url ? '<div class="np-meta-url" title="' + safeText(info.url) + '">' + safeText(_truncateUrl(info.url)) + '</div>' : '') +
                statusHtml +
                '<div class="np-panel-actions">' +
                    settingsButtonHtml +
                    '<button class="btn-outline btn-sm" data-action="add-current-to-playlist" data-tooltip="Add to playlist" aria-label="Add current media to playlist">Add to Playlist</button>' +
                '</div>' +
            '</div>' +
        '</div>' +
        getInlineQueueHtml(liveMp) +
        getNowPlayingSecondaryListsHtml(activePlayerHandle, liveMp, getEffectiveDeviceSession(activePlayerHandle));

    bindNowPlayingPanelActions(panel);
    updateNowPlayingPanelTimeOnly(panel, liveMp);
    applyStaticTooltips();
}

function _truncateUrl(url) {
    if (!url) return '';
    if (url.length <= 50) return url;
    return url.substring(0, 47) + '...';
}


'use strict';

var _searchDebounceTimer = null;
var _searchDebounceMs = 320;
var _searchRequestSeq = 0;
var _activeSearchRequestId = null;

function initSearch() {
    var btn   = document.getElementById('search-btn');
    var input = document.getElementById('search-input');
    var select = document.getElementById('search-source');
    if (!btn || !input) return;

    btn.onclick = function() {
        performSearch(true);
    };

    input.addEventListener('keydown', function(e) {
        if (e.key === 'Enter') performSearch(true);
    });

    if (select) {
        select.addEventListener('change', function() {
            if (!input.value || !input.value.trim()) return;
            performSearch(true);
        });
    }

    input.addEventListener('input', function() {
        if (!input.value || !input.value.trim()) {
            _activeSearchRequestId = null;
            clearTimeout(_searchDebounceTimer);
            clearSearchResults();
            _setSearchState('idle');
            return;
        }

        clearTimeout(_searchDebounceTimer);
        _searchDebounceTimer = setTimeout(function() {
            performSearch(false);
        }, _searchDebounceMs);
    });
}

function populateSearchSources(sources, preferredSource) {
    var select = document.getElementById('search-source');
    if (!select || !sources) return;
    select.innerHTML = '';
    var count = 0;
    var firstEnabled = null;
    var preferred = preferredSource || defaultSearchSource || 'youtube';
    for (var key in sources) {
        if (sources[key].enabled) {
            var opt = document.createElement('option');
            opt.value = key;
            opt.textContent = sources[key].label || key;
            select.appendChild(opt);
            count++;
            if (!firstEnabled) firstEnabled = key;
        }
    }
    select.style.display = count > 1 ? '' : 'none';

    if (count > 0) {
        if (sources[preferred] && sources[preferred].enabled) {
            select.value = preferred;
        } else {
            select.value = firstEnabled;
        }
    }
}

function activateSearchBtn() {
    var btn = document.getElementById('search-btn');
    if (btn) btn.disabled = false;
}

function getCurrentSearchSnapshot() {
    var input = document.getElementById('search-input');
    var select = document.getElementById('search-source');
    return {
        query: input ? input.value.trim() : '',
        source: select && select.value ? select.value : 'youtube'
    };
}

function finishSearchAfterBusy(requestId, fn) {
    var remaining = Math.max(0, searchMinimumBusyMs - (Date.now() - _searchBusySince));
    setTimeout(function() {
        if (requestId && _activeSearchRequestId && requestId !== _activeSearchRequestId) {
            return;
        }
        fn();
    }, remaining);
}

function scheduleSearchRetry(requestId, retryAfterMs) {
    clearTimeout(_searchRetryTimer);

    var snapshot = getCurrentSearchSnapshot();
    if (!snapshot.query) {
        _setSearchState('idle', requestId);
        return;
    }

    _searchRetryTimer = setTimeout(function() {
        var current = getCurrentSearchSnapshot();
        if (current.query !== snapshot.query || current.source !== snapshot.source) {
            _setSearchState('idle', requestId);
            return;
        }
        performSearch(true);
    }, Math.max(0, Number(retryAfterMs) || 0));
}

function performSearch(forceImmediate) {
    var input  = document.getElementById('search-input');
    var select = document.getElementById('search-source');
    var q      = input ? input.value.trim() : '';
    var source = select && select.value ? select.value : 'youtube';

    if (forceImmediate) {
        clearTimeout(_searchDebounceTimer);
    }

    if (!q) return;
    clearTimeout(_searchRetryTimer);

    if (isDirectUrl(q)) {
        if (!activePlayerHandle) {
            showNotification('Please select a nearby device first!', 'Play', '#ff4444');
            return;
        }
        requestPlaybackOnHandle(_h(), { url: q, label: getCurrentDeviceLabel(), video: true });
        if (input) input.value = '';
        clearSearchResults();
        return;
    }

    var requestId = (++_searchRequestSeq) + ':' + Date.now();
    _activeSearchRequestId = requestId;
    _setSearchState('loading', requestId, 'Searching...');
    sendMessage('searchMedia', { query: q, source: source, requestId: requestId });
}

function _setSearchState(state, requestId, message) {
    var tray = document.getElementById('search-results');
    var err  = document.getElementById('search-status');
    var btn  = document.getElementById('search-btn');

    if (requestId && _activeSearchRequestId && requestId !== _activeSearchRequestId) {
        return;
    }

    if (state === 'loading') {
        _searchBusySince = Date.now();
        if (tray) tray.style.display = 'none';
        if (err)  {
            err.innerHTML = '<span class="search-status-spinner" aria-hidden="true"></span><span>' + safeText(message || 'Searching...') + '</span>';
            err.className = 'search-status muted loading';
            err.style.display = 'flex';
        }
        if (btn)  btn.disabled = true;
    } else if (state === 'idle') {
        if (err)  {
            err.style.display = 'none';
            err.className = 'search-status';
            err.textContent = '';
        }
        if (btn)  btn.disabled = false;
    }
}

function clearSearchResults() {
    clearTimeout(_searchRetryTimer);
    var tray = document.getElementById('search-results');
    var err  = document.getElementById('search-status');
    if (tray) { tray.style.display = 'none'; tray.innerHTML = ''; }
    if (err)  {
        err.style.display = 'none';
        err.className = 'search-status';
        err.textContent = '';
    }
    _activeSearchRequestId = 'cleared:' + Date.now();
}

function handleSearchError(message, requestId, state, retryAfterMs) {
    if (requestId && _activeSearchRequestId && requestId !== _activeSearchRequestId) {
        return;
    }

    if (state === 'cooldown') {
        _setSearchState('loading', requestId, 'Preparing next search...');
        scheduleSearchRetry(requestId, retryAfterMs);
        return;
    }

    finishSearchAfterBusy(requestId, function() {
        _setSearchState('idle', requestId);
        var tray = document.getElementById('search-results');
        var err  = document.getElementById('search-status');
        if (tray) tray.style.display = 'none';
        if (err) {
            err.textContent = message || 'No results found. Try a different search.';
            err.className = 'search-status muted';
            err.style.display = 'block';
        }
    });
}

function mergeDeviceSessions(incomingStates) {
    var source = incomingStates || {};
    var seen = {};

    Object.keys(source).forEach(function(key) {
        var normalizedKey = handleKey(key);
        if (!normalizedKey) return;
        seen[normalizedKey] = true;
        var incomingState = cloneValue(source[key]);
        var currentRevision = getDeviceSessionRevision(deviceSessions[normalizedKey]);
        var incomingRevision = getDeviceSessionRevision(incomingState);
        if (currentRevision !== null && incomingRevision !== null && incomingRevision < currentRevision) {
            return;
        }
        deviceSessions[normalizedKey] = incomingState;
    });

    Object.keys(deviceSessions).forEach(function(key) {
        if (!seen[key]) {
            delete deviceSessions[key];
        }
    });
}

function renderSearchResults(results, requestId) {
    if (requestId && _activeSearchRequestId && requestId !== _activeSearchRequestId) {
        return;
    }

    finishSearchAfterBusy(requestId, function() {
        _setSearchState('idle', requestId);
        var tray = document.getElementById('search-results');
        var err  = document.getElementById('search-status');

        if (!results || results.length === 0) {
            handleSearchError('No results found. Try a different search.', requestId);
            return;
        }

        if (err) err.style.display = 'none';
        if (!tray) return;
        tray.innerHTML = '';

        results.forEach(function(res) {
            var item = document.createElement('div');
            item.className = 'search-result';

            var thumbSrc = normalizeRemoteAssetUrl(res.thumbnail || '');
            var thumbHtml = thumbSrc
                ? '<div class="sr-thumb" style="background-image:url(' + encodeURI(thumbSrc) + ')"></div>'
                : '<div class="sr-thumb sr-thumb-empty"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg></div>';

            var sourceBadge = res.source ? '<span class="badge badge-source">' + safeText(res.source) + '</span>' : '';

            item.innerHTML =
                thumbHtml +
                '<div class="sr-info">' +
                    '<div class="sr-title">' + safeText(res.title || 'Untitled') + '</div>' +
                    '<div class="sr-meta">' +
                        safeText(res.author || 'Unknown') +
                        (res.duration ? ' - ' + timeToString(res.duration) : '') +
                        ' ' + sourceBadge +
                    '</div>' +
                '</div>' +
                '<div class="sr-actions">' +
                    '<button class="btn-icon btn-sm sr-play-btn" data-tooltip="Play now" aria-label="Play now">' +
                        '<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21"/></svg>' +
                    '</button>' +
                    '<button class="btn-icon btn-sm sr-add-btn" data-tooltip="Add to playlist" aria-label="Add to playlist">' +
                        '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>' +
                    '</button>' +
                '</div>';

            function playThis(e) {
                if (e && e.target.closest('.sr-add-btn')) return;
                if (!activePlayerHandle) {
                    showNotification('Please select a nearby device first!', 'Play', '#ff4444');
                    return;
                }
                requestPlaybackOnHandle(_h(), {
                    url: res.url,
                    title: res.title,
                    duration: res.duration,
                    author: res.author,
                    thumbnail: thumbSrc || res.thumbnail,
                    video: true
                });
                clearSearchResults();
                var input = document.getElementById('search-input');
                if (input) input.value = '';
            }

            item.onclick = playThis;
            item.querySelector('.sr-play-btn').onclick = function(e) {
                e.stopPropagation();
                playThis(e);
            };
            item.querySelector('.sr-add-btn').onclick  = function(e) {
                e.stopPropagation();
                openAddToPlaylistModal(res);
            };

            tray.appendChild(item);
        });

        tray.style.display = 'block';
        applyStaticTooltips();
    });
}


'use strict';

function openCreatePlaylist() {
    var displaySummary = getDisplayedLibrarySummary();
    if (displaySummary.maxPlaylists > 0 && displaySummary.playlistCount >= displaySummary.maxPlaylists) {
        showNotification('You have reached the maximum of ' + displaySummary.maxPlaylists + ' playlists.', 'Library', '#ff4444');
        return;
    }
    showPrompt('New Playlist', 'Enter playlist name...', function(name) {
        if (name && name.trim().length > 0 && name.trim().length <= 100) {
            sendMessage('createPlaylist', { name: name.trim() });
        }
    });
}

function openPlaylist(playlistId, playlistName) {
    currentPlaylistId   = playlistId;
    currentPlaylistName = playlistName || '';
    document.getElementById('current-playlist-title').textContent = playlistName || 'Playlist';
    switchView('view-playlist');
    sendMessage('getPlaylistTracks', { playlistId: playlistId });
}

function isPlaylistFavorite(playlist) {
    return !!(playlist && (playlist.is_favorite === true || Number(playlist.is_favorite) === 1));
}

function normalizePlaylistId(playlistId) {
    var n = Number(playlistId);
    return Number.isFinite(n) ? String(n) : null;
}

function clearPendingFavoriteTimers(key) {
    var pending = key ? pendingFavoriteState[key] : null;
    if (!pending) return;
    if (pending.syncTimeoutId) clearTimeout(pending.syncTimeoutId);
    if (pending.hardTimeoutId) clearTimeout(pending.hardTimeoutId);
    pending.syncTimeoutId = null;
    pending.hardTimeoutId = null;
}

function dropPendingFavorite(key) {
    if (!key || !pendingFavoriteState[key]) return;
    debugLog('favorites', 'pending favorite dropped', {
        key: key,
        favorite: pendingFavoriteState[key].favorite,
        requestId: pendingFavoriteState[key].requestId
    });
    clearPendingFavoriteTimers(key);
    delete pendingFavoriteState[key];
}

function applyPendingFavoritesSnapshot(playlists) {
    if (!Array.isArray(playlists)) return [];

    return playlists.map(function(pl) {
        if (!pl) return pl;
        var merged = {};
        Object.keys(pl).forEach(function(key) { merged[key] = pl[key]; });
        var key = normalizePlaylistId(merged.id);
        var pending = key ? pendingFavoriteState[key] : null;
        if (pending) {
            merged.is_favorite = pending.favorite === true ? 1 : 0;
            merged.isFavorite = pending.favorite === true;
        }
        return merged;
    });
}

function hasPendingFavoriteMutations() {
    return Object.keys(pendingFavoriteState).some(function(key) {
        return !!pendingFavoriteState[key];
    });
}

function clonePlaylistEntry(playlist) {
    var copy = {};
    Object.keys(playlist || {}).forEach(function(key) {
        copy[key] = playlist[key];
    });
    return copy;
}

function normalizeFavoritePayloadValue(payload) {
    if (!payload || typeof payload !== 'object') return null;
    if (payload.isFavorite === true || payload.isFavorite === false) {
        return payload.isFavorite === true;
    }
    if (payload.favorite === true || payload.favorite === false) {
        return payload.favorite === true;
    }
    if (payload.is_favorite !== undefined && payload.is_favorite !== null) {
        var numeric = Number(payload.is_favorite);
        if (Number.isFinite(numeric)) return numeric === 1;
        if (payload.is_favorite === 'true') return true;
        if (payload.is_favorite === 'false') return false;
    }
    return null;
}

function mergePlaylistFavoritePayload(row, payload, favoriteValue) {
    if (!row || !payload) return row;
    var merged = clonePlaylistEntry(row);
    if (payload.playlist && typeof payload.playlist === 'object') {
        Object.keys(payload.playlist).forEach(function(prop) {
            merged[prop] = payload.playlist[prop];
        });
    }
    if (favoriteValue !== null) {
        merged.is_favorite = favoriteValue ? 1 : 0;
        merged.isFavorite = favoriteValue;
    }
    return merged;
}

function patchCanonicalPlaylistFavorite(key, payload, favoriteValue) {
    if (!key || favoriteValue === null) return false;
    var changed = false;
    authoritativePlaylists = (authoritativePlaylists || []).map(function(row) {
        if (!row || String(row.id) !== key) return row;
        changed = true;
        return mergePlaylistFavoritePayload(row, payload, favoriteValue);
    });
    return changed;
}

function normalizeFavoriteSnapshotFromPayload(playlists, key, payload, favoriteValue) {
    if (!Array.isArray(playlists)) return playlists;
    if (!key || favoriteValue === null) return playlists;
    var found = false;
    var normalized = playlists.map(function(row) {
        if (!row || String(row.id) !== key) return row;
        found = true;
        return mergePlaylistFavoritePayload(row, payload, favoriteValue);
    });
    if (!found && payload && payload.playlist && String(payload.playlist.id) === key) {
        normalized.push(mergePlaylistFavoritePayload(payload.playlist, payload, favoriteValue));
    }
    return normalized;
}

function commitCanonicalPlaylists(playlists, summary, libraryRevision) {
    var incomingRevision = normalizeLibraryRevision(libraryRevision);

    libraryState.playlistsLoaded = true;
    libraryState.playlistsLoading = false;
    libraryState.playlistsDirty = false;
    if (incomingRevision !== null) {
        libraryState.libraryRevision = incomingRevision;
    }
    syncLibrarySummary(summary);
    authoritativePlaylists = (Array.isArray(playlists) ? playlists : []).map(function(pl) {
        return clonePlaylistEntry(pl);
    });

    Object.keys(pendingFavoriteState).forEach(function(key) {
        var pending = pendingFavoriteState[key];
        if (!pending) return;

        var row = authoritativePlaylists.find(function(pl) {
            return pl && String(pl.id) === key;
        });
        if (!row) {
            debugLog('favorites', 'pending favorite dropped because playlist disappeared', {
                key: key,
                requestId: pending.requestId
            });
            dropPendingFavorite(key);
            return;
        }

        if (isPlaylistFavorite(row) === (pending.favorite === true)) {
            debugLog('favorites', 'pending favorite confirmed by canonical snapshot', {
                key: key,
                favorite: pending.favorite,
                requestId: pending.requestId,
                libraryRevision: incomingRevision
            });
            dropPendingFavorite(key);
        }
    });

    refreshDisplayedPlaylists();
}

function refreshDisplayedPlaylists() {
    cachedPlaylists = applyPendingFavoritesSnapshot(authoritativePlaylists);
    populatePlaylists(cachedPlaylists, 'playlists-grid', { allowFavorite: true });
    renderSidebarFavorites();
    updateLibrarySummaryDisplay();
}

function requestCanonicalPlaylistsRefresh() {
    libraryState.playlistsDirty = true;
    libraryState.playlistResponseFloor = Math.max(
        libraryState.playlistResponseFloor,
        libraryState.playlistRequestSeq + 1
    );
    requestPlaylists(true);
}

function setPlaylistFavoriteOptimistic(playlistId, favorite) {
    var normalizedFavorite = favorite === true;
    var key = normalizePlaylistId(playlistId);
    if (!key) return;
    var existingPending = pendingFavoriteState[key] || null;
    if (existingPending && existingPending.favorite === normalizedFavorite) {
        debugLog('favorites', 'favorite request ignored because same target is already pending', {
            playlistId: playlistId,
            key: key,
            favorite: normalizedFavorite,
            requestId: existingPending.requestId
        });
        return;
    }

    var displaySummary = getDisplayedLibrarySummary();
    if (normalizedFavorite && displaySummary.maxFavorites > 0 && displaySummary.favoriteCount >= displaySummary.maxFavorites) {
        debugLog('favorites', 'favorite request blocked client-side by favorite limit', {
            playlistId: playlistId,
            favoriteCount: displaySummary.favoriteCount,
            maxFavorites: displaySummary.maxFavorites
        });
        showNotification('You can only pin ' + displaySummary.maxFavorites + ' playlists at once.', 'Library', '#ff4444');
        return;
    }

    var previous = false;
    (authoritativePlaylists || []).some(function(pl) {
        if (!pl) return false;
        if (String(pl.id) !== key) return false;
        previous = isPlaylistFavorite(pl);
        return true;
    });

    favoriteRequestSeq += 1;
    favoriteResponseFloor[key] = favoriteRequestSeq;
    clearPendingFavoriteTimers(key);
    pendingFavoriteState[key] = {
        favorite: normalizedFavorite,
        previous: existingPending ? existingPending.previous : previous,
        requestId: favoriteRequestSeq,
        expiresAt: Date.now() + FAVORITE_HARD_TIMEOUT_MS,
        refreshing: false,
        syncTimeoutId: null,
        hardTimeoutId: null
    };
    libraryState.playlistPendingRequestId = null;

    debugLog('favorites', 'favorite optimistic state applied', {
        playlistId: playlistId,
        key: key,
        favorite: normalizedFavorite,
        previous: pendingFavoriteState[key].previous,
        requestId: favoriteRequestSeq,
        replacingRequestId: existingPending ? existingPending.requestId : null
    });

    refreshDisplayedPlaylists();

    var expectedKey = key;
    var expectedRequestId = favoriteRequestSeq;
    pendingFavoriteState[key].syncTimeoutId = setTimeout(function() {
        var pending = pendingFavoriteState[expectedKey];
        if (!pending || pending.requestId !== expectedRequestId) return;
        pending.refreshing = true;
        debugLog('favorites', 'favorite ack slow, requesting canonical refresh', {
            key: expectedKey,
            requestId: expectedRequestId
        });
        requestCanonicalPlaylistsRefresh();
    }, FAVORITE_SYNC_TIMEOUT_MS);

    pendingFavoriteState[key].hardTimeoutId = setTimeout(function() {
        var pending = pendingFavoriteState[expectedKey];
        if (!pending || pending.requestId !== expectedRequestId) return;
        dropPendingFavorite(expectedKey);
        refreshDisplayedPlaylists();
        requestCanonicalPlaylistsRefresh();
        debugLog('favorites', 'favorite ack hard timeout, reverting to canonical refresh', {
            key: expectedKey,
            requestId: expectedRequestId
        });
        showNotification('Favorite change could not be confirmed. Refreshed library state.', 'Library', '#ff4444');
    }, FAVORITE_HARD_TIMEOUT_MS);

    setTimeout(function() {
        if (!pendingFavoriteState[expectedKey]) return;
        if (pendingFavoriteState[expectedKey].requestId !== expectedRequestId) return;
        refreshDisplayedPlaylists();
    }, 160);

    sendMessage('setPlaylistFavorite', {
        playlistId: playlistId,
        favorite: normalizedFavorite,
        requestId: favoriteRequestSeq
    });
    debugLog('favorites', 'favorite request sent to client bridge', {
        playlistId: playlistId,
        favorite: normalizedFavorite,
        requestId: favoriteRequestSeq
    });
}

function applyServerPlaylists(playlists, requestId, summary, libraryRevision) {
    var numericRequestId = Number(requestId);
    var incomingRevision = normalizeLibraryRevision(libraryRevision);
    var currentRevision = normalizeLibraryRevision(libraryState.libraryRevision);
    var hasNewerRevision = incomingRevision !== null && (currentRevision === null || incomingRevision > currentRevision);

    if (incomingRevision !== null && currentRevision !== null && incomingRevision < currentRevision) {
        return;
    }

    if (requestId !== undefined && requestId !== null) {
        if (!Number.isFinite(numericRequestId)) {
            return;
        }
        if (!hasNewerRevision && numericRequestId < libraryState.playlistResponseFloor) {
            return;
        }
        if (!hasNewerRevision && libraryState.playlistPendingRequestId != null && numericRequestId < libraryState.playlistPendingRequestId) {
            return;
        }
        if (libraryState.playlistPendingRequestId === numericRequestId) {
            libraryState.playlistPendingRequestId = null;
        }
    }

    commitCanonicalPlaylists(playlists, summary, incomingRevision);
}

function applySharedPlaylists(playlists, requestId) {
    var numericRequestId = Number(requestId);
    if (requestId !== undefined && requestId !== null) {
        if (!Number.isFinite(numericRequestId)) {
            return;
        }
        if (libraryState.sharedPendingRequestId != null && numericRequestId < libraryState.sharedPendingRequestId) {
            return;
        }
        if (libraryState.sharedPendingRequestId === numericRequestId) {
            libraryState.sharedPendingRequestId = null;
        }
    }

    libraryState.sharedLoaded = true;
    libraryState.sharedLoading = false;
    libraryState.sharedDirty = false;
    cachedSharedPlaylists = Array.isArray(playlists) ? playlists.slice() : [];
    populatePlaylists(cachedSharedPlaylists, 'shared-playlists-grid', { allowFavorite: false });
}

function handlePlaylistFavoriteUpdate(payload) {
    if (!payload) return;

    var key = normalizePlaylistId(payload.playlistId);
    if (!key) return;
    var pending = pendingFavoriteState[key] || null;
    var requestId = Number(payload.requestId);
    var floor = Number(favoriteResponseFloor[key]);
    var incomingRevision = normalizeLibraryRevision(payload.libraryRevision);
    var currentRevision = normalizeLibraryRevision(libraryState.libraryRevision);
    var hasNewerRevision = incomingRevision !== null && (currentRevision === null || incomingRevision > currentRevision);
    var hasStaleFavoriteAck = Number.isFinite(floor) && Number.isFinite(requestId) && requestId < floor;
    var payloadFavorite = normalizeFavoritePayloadValue(payload);
    var confirmsPending = !!(
        pending
        && !hasStaleFavoriteAck
        && payload.success !== false
        && payloadFavorite !== null
        && payloadFavorite === (pending.favorite === true)
    );

    debugLog('favorites', 'favorite update received from server', {
        key: key,
        requestId: requestId,
        floor: floor,
        success: payload.success,
        isFavorite: payload.isFavorite,
        payloadFavorite: payloadFavorite,
        pendingFavorite: pending ? pending.favorite : null,
        pendingRequestId: pending ? pending.requestId : null,
        message: payload.message,
        incomingRevision: incomingRevision,
        currentRevision: currentRevision,
        hasNewerRevision: hasNewerRevision,
        hasStaleFavoriteAck: hasStaleFavoriteAck,
        confirmsPending: confirmsPending
    });

    if (incomingRevision !== null && currentRevision !== null && incomingRevision < currentRevision) {
        debugLog('favorites', 'favorite update ignored: older library revision', {
            key: key,
            incomingRevision: incomingRevision,
            currentRevision: currentRevision
        });
        return;
    }

    if (!hasNewerRevision && Number.isFinite(floor) && (!Number.isFinite(requestId) || requestId < floor)) {
        debugLog('favorites', 'favorite update ignored: stale request id', {
            key: key,
            requestId: requestId,
            floor: floor
        });
        return;
    }
    if (!hasStaleFavoriteAck && Number.isFinite(requestId)) {
        favoriteResponseFloor[key] = requestId;
    }
    if (incomingRevision !== null) {
        libraryState.libraryRevision = incomingRevision;
    }

    if (confirmsPending) {
        debugLog('favorites', 'favorite pending confirmed directly by server ack', {
            key: key,
            requestId: requestId,
            favorite: payloadFavorite
        });
        dropPendingFavorite(key);
    }

    if (!Array.isArray(payload.playlists)) {
        if (!hasStaleFavoriteAck) {
            if (payload.success === false || payloadFavorite !== null) {
                dropPendingFavorite(key);
            }
        }
        if (!hasStaleFavoriteAck && payload.success === false && payload.message) {
            showNotification(payload.message, 'Library', '#ff4444');
        }
        if (!hasStaleFavoriteAck && payload.success !== false && patchCanonicalPlaylistFavorite(key, payload, payloadFavorite)) {
            refreshDisplayedPlaylists();
            return;
        }
        debugLog('favorites', 'favorite update missing playlist snapshot, requesting refresh', {
            key: key,
            requestId: requestId,
            staleAck: hasStaleFavoriteAck
        });
        requestCanonicalPlaylistsRefresh();
        return;
    }

    if (!hasStaleFavoriteAck && payload.success === false) {
        dropPendingFavorite(key);
    } else if (hasStaleFavoriteAck) {
        debugLog('favorites', 'favorite update applied only as canonical snapshot because a newer request is pending', {
            key: key,
            requestId: requestId,
            floor: floor
        });
    }
    var normalizedPlaylists = normalizeFavoriteSnapshotFromPayload(payload.playlists, key, payload, payloadFavorite);
    commitCanonicalPlaylists(normalizedPlaylists, payload.summary || payload, incomingRevision);
    if (!hasStaleFavoriteAck && payload.success === false && payload.message) {
        showNotification(payload.message, 'Library', '#ff4444');
    }
}

function renderSidebarFavorites() {
    var container = document.getElementById('sidebar-favorites-list');
    if (!container) return;

    var favorites = (cachedPlaylists || []).filter(function(pl) {
        return isPlaylistFavorite(pl);
    });

    if (favorites.length === 0) {
        container.innerHTML = '<div class="sidebar-favorites-empty">No favorites pinned</div>';
        return;
    }

    container.innerHTML = '';
    favorites.forEach(function(pl) {
        var row = document.createElement('div');
        var pending = !!pendingFavoriteState[normalizePlaylistId(pl.id)];
        row.className = 'sidebar-favorite-row' + (pending ? ' favorite-pending' : '');

        var openBtn = document.createElement('button');
        openBtn.className = 'sidebar-favorite-item';
        openBtn.title = pl.name || 'Playlist';
        openBtn.textContent = pl.name || 'Untitled Playlist';
        openBtn.onclick = function() {
            openPlaylist(pl.id, pl.name);
        };

        var unpinBtn = document.createElement('button');
        unpinBtn.className = 'sidebar-favorite-unpin' + (pending ? ' favorite-pending' : '');
        unpinBtn.title = 'Unpin favorite';
        unpinBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.9 6.1L22 9.3l-5 4.8L18.2 22 12 18.7 5.8 22 7 14.1 2 9.3l7.1-1.2z"/></svg>';
        unpinBtn.disabled = pending;
        unpinBtn.onclick = function() {
            setPlaylistFavoriteOptimistic(pl.id, false);
        };

        row.appendChild(openBtn);
        row.appendChild(unpinBtn);
        container.appendChild(row);
    });
}

function populatePlaylists(lists, targetId, options) {
    var allowFavorite = !!(options && options.allowFavorite);
    var grid = document.getElementById(targetId);
    if (!grid) return;

    if (!lists || lists.length === 0) {
        grid.innerHTML = '<div class="empty-state"><p>No playlists here.</p></div>';
        return;
    }

    grid.innerHTML = '';
    lists.forEach(function(pl) {
        var isFavorite = isPlaylistFavorite(pl);
        var isFavoritePending = !!pendingFavoriteState[normalizePlaylistId(pl.id)];
        var card = document.createElement('div');
        card.className = 'playlist-card' + (isFavorite ? ' favorite-active' : '') + (isFavoritePending ? ' favorite-pending' : '');
        card.innerHTML =
            '<div class="playlist-card-icon">' +
                '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>' +
            '</div>' +
            '<div class="playlist-card-body">' +
                '<div class="playlist-name">' + safeText(pl.name) + '</div>' +
                '<div class="playlist-sub">' + (isFavorite ? 'Pinned favorite' : 'Playlist') + '</div>' +
            '</div>' +
            '<div class="playlist-card-actions">' +
                (allowFavorite
                    ? '<button class="btn-icon btn-sm playlist-pin-btn' + (isFavorite ? ' active' : '') + (isFavoritePending ? ' favorite-pending' : '') + '" title="' + (isFavorite ? 'Unpin Favorite' : 'Pin Favorite') + '"' + (isFavoritePending ? ' disabled' : '') + '>' +
                        '<svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.9 6.1L22 9.3l-5 4.8L18.2 22 12 18.7 5.8 22 7 14.1 2 9.3l7.1-1.2z"/></svg>' +
                    '</button>'
                    : '') +
                '<button class="btn-icon btn-sm playlist-share-btn" title="Share">' +
                    '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>' +
                '</button>' +
            '</div>';

        card.onclick = function(e) {
            if (e.target.closest('.playlist-share-btn') || e.target.closest('.playlist-pin-btn')) return;
            openPlaylist(pl.id, pl.name);
        };

        var pinBtn = card.querySelector('.playlist-pin-btn');
        if (pinBtn) {
            pinBtn.onclick = function(e) {
                e.stopPropagation();
                setPlaylistFavoriteOptimistic(pl.id, !isFavorite);
            };
        }

        card.querySelector('.playlist-share-btn').onclick = function(e) {
            e.stopPropagation();
            openShareModal(pl.id);
        };

        grid.appendChild(card);
    });
    applyStaticTooltips();
}

function populatePlaylistTracks(pid, tracks) {
    var list = document.getElementById('tracks-list');
    if (!list) return;

    if (!tracks || tracks.length === 0) {
        list.innerHTML = '<div class="empty-state"><p>This playlist is empty.</p></div>';
        return;
    }

    list.innerHTML = '';
    tracks.forEach(function(tr, idx) {
        var item = document.createElement('div');
        item.className = 'list-item';
        item.innerHTML =
            '<div class="list-item-left">' +
                '<div class="list-item-num">' + (idx + 1) + '</div>' +
                '<div>' +
                    '<div class="list-item-title">' + safeText(tr.title || 'Untitled') + '</div>' +
                    '<div class="list-item-sub">' + timeToString(tr.duration) + '</div>' +
                '</div>' +
            '</div>' +
            '<div class="list-item-right">' +
                '<button class="btn-icon btn-sm track-play-btn" title="Play">' +
                    '<svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21"/></svg>' +
                '</button>' +
                '<button class="btn-icon btn-sm track-remove-btn" title="Remove">' +
                    '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M9 6V4h6v2"/></svg>' +
                '</button>' +
            '</div>';

        item.querySelector('.track-play-btn').onclick = function(e) {
            e.stopPropagation();
            playTrack(tr.url, tr.title);
        };
        item.querySelector('.track-remove-btn').onclick = function(e) {
            e.stopPropagation();
            sendMessage('removeTrack', { playlistId: pid, trackId: tr.id });
        };

        list.appendChild(item);
    });
    applyStaticTooltips();
}

function playTrack(url, title) {
    if (!activePlayerHandle) {
        showNotification('Select a device first!', 'Play', '#ff4444');
        return;
    }
    requestPlaybackOnHandle(_h(), { url: url, title: title, video: true });
}

function playPlaylist() {
    if (!activePlayerHandle) {
        showNotification('Select a device first!', 'Play', '#ff4444');
        return;
    }
    if (!currentPlaylistId) return;
    var firstBtn = document.querySelector('#tracks-list .track-play-btn');
    if (firstBtn) firstBtn.click();
    showNotification('Playing playlist: ' + currentPlaylistName, 'Library');
}

function deleteCurrentPlaylist() {
    if (!currentPlaylistId) return;
    showConfirm('Delete Playlist?', 'Are you sure you want to permanently delete "' + currentPlaylistName + '"?', function(ok) {
        if (!ok) return;
        sendMessage('deletePlaylist', { playlistId: currentPlaylistId });
        switchView('view-library');
        currentPlaylistId = null;
    });
}

function openAddToPlaylistModal(track) {
    if (!cachedPlaylists || cachedPlaylists.length === 0) {
        showNotification('Create a playlist first!', 'Library', '#ff4444');
        return;
    }
    pendingTrackForPlaylist = track;

    var modal   = document.getElementById('add-to-playlist-modal');
    var body    = document.getElementById('atp-list');
    if (!modal || !body) return;

    body.innerHTML = '';
    cachedPlaylists.forEach(function(pl) {
        var item = document.createElement('div');
        item.className = 'list-item list-item-clickable';
        item.innerHTML =
            '<div class="list-item-left">' +
                '<div class="list-item-num"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/></svg></div>' +
                '<div class="list-item-title">' + safeText(pl.name) + '</div>' +
            '</div>';
        item.onclick = function() {
            sendMessage('addTrack', {
                playlistId: pl.id,
                trackData: { title: pendingTrackForPlaylist.title, url: pendingTrackForPlaylist.url, duration: pendingTrackForPlaylist.duration }
            });
            modal.style.display = 'none';
            pendingTrackForPlaylist = null;
        };
        body.appendChild(item);
    });

    modal.style.display = 'flex';
}


'use strict';

function sendFriendRequest() {
    var inp = document.getElementById('friend-id-input');
    var val = inp ? inp.value.trim() : '';
    if (!val && !playerSuggestionState.selectedLicense && !playerSuggestionState.selectedSource) {
        showNotification('Select a player or start typing to search.', 'Friends', '#ff4444');
        return;
    }

    var targetSrc = playerSuggestionState.selectedSource;
    var targetLicense = playerSuggestionState.selectedLicense;

    if (!targetSrc && !targetLicense && val && !isNaN(parseInt(val, 10))) {
        targetSrc = parseInt(val, 10);
    } else if (!targetSrc && !targetLicense && val) {
        targetLicense = val;
    }

    sendMessage('sendFriendRequest', {
        targetSrc: targetSrc || null,
        targetLicense: targetLicense || null
    });

    if (inp) inp.value = '';
    playerSuggestionState.selectedLicense = null;
    playerSuggestionState.selectedSource = null;
    hidePlayerSuggestions();
}

function populateFriends(friends) {
    var container = document.getElementById('friends-list');
    if (!container) return;

    if (!friends || friends.length === 0) {
        container.innerHTML = '<div class="empty-state"><p>No friends yet.</p></div>';
        return;
    }

    container.innerHTML = '';
    friends.forEach(function(f) {
        var item = document.createElement('div');
        item.className = 'list-item';
        item.innerHTML =
            '<div class="list-item-left">' +
                '<div class="avatar">' + _initials(f.friend_name || f.friend_license) + '</div>' +
                '<div class="list-item-title">' + safeText(f.friend_name || f.friend_license) + '</div>' +
            '</div>' +
            '<button class="btn-icon btn-sm btn-danger-sm" title="Remove friend">' +
                '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M9 6V4h6v2"/></svg>' +
            '</button>';

        item.querySelector('.btn-danger-sm').onclick = function() {
            showConfirm('Remove Friend?', 'Remove ' + (f.friend_name || f.friend_license) + ' from your friends?', function(ok) {
                if (ok) sendMessage('removeFriend', { friendLicense: f.friend_license });
            });
        };

        container.appendChild(item);
    });
    applyStaticTooltips();
}

function populateRequests(requests) {
    var container = document.getElementById('requests-list');
    if (!container) return;

    if (!requests || requests.length === 0) {
        container.innerHTML = '<div class="empty-state"><p>No pending requests.</p></div>';
        return;
    }

    container.innerHTML = '';
    requests.forEach(function(r) {
        var item = document.createElement('div');
        item.className = 'list-item';
        item.innerHTML =
            '<div class="list-item-left">' +
                '<div class="avatar">' + _initials(r.requester_name || '?') + '</div>' +
                '<div class="list-item-title">' + safeText(r.requester_name || 'Unknown') + '</div>' +
            '</div>' +
            '<button class="btn-accent btn-sm" title="Accept">Accept</button>';

        item.querySelector('.btn-accent').onclick = function() {
            sendMessage('acceptFriendRequest', { requestId: r.id });
        };

        container.appendChild(item);
    });
    applyStaticTooltips();
}

function openShareModal(playlistId) {
    if (!cachedFriends || cachedFriends.length === 0) {
        showNotification('You have no friends to share with.', 'Social');
        return;
    }

    var modal = document.getElementById('share-modal');
    var body  = document.getElementById('share-friends-list');
    if (!modal || !body) return;

    body.innerHTML = '';
    cachedFriends.forEach(function(f) {
        var item = document.createElement('div');
        item.className = 'list-item list-item-clickable';
        item.innerHTML =
            '<div class="list-item-left">' +
                '<div class="avatar">' + _initials(f.friend_name || f.friend_license) + '</div>' +
                '<div class="list-item-title">' + safeText(f.friend_name || f.friend_license) + '</div>' +
            '</div>';
        item.onclick = function() {
            sendMessage('sharePlaylist', { playlistId: playlistId, friendLicense: f.friend_license });
            modal.style.display = 'none';
            showNotification('Playlist shared!', 'Library');
        };
        body.appendChild(item);
    });

    modal.style.display = 'flex';
}

function _initials(name) {
    if (!name) return '?';
    var parts = name.trim().split(/\s+/);
    return (parts[0][0] + (parts[1] ? parts[1][0] : '')).toUpperCase();
}


'use strict';

var _adminEditState = null;

function _clearAdminEditState() {
    if (!_adminEditState || !_adminEditState.timers) {
        _adminEditState = null;
        return;
    }

    Object.keys(_adminEditState.timers).forEach(function(key) {
        clearTimeout(_adminEditState.timers[key]);
    });
    _adminEditState = null;
}

function _queueAdminWrite(key, callback, delayMs) {
    if (!_adminEditState) return;
    var wait = Number(delayMs) || 140;
    clearTimeout(_adminEditState.timers[key]);
    _adminEditState.timers[key] = setTimeout(function() {
        if (_adminEditState && typeof callback === 'function') {
            callback();
        }
    }, wait);
}

function _flushAdminWrite(key, callback) {
    if (_adminEditState && _adminEditState.timers[key]) {
        clearTimeout(_adminEditState.timers[key]);
    }
    if (typeof callback === 'function') {
        callback();
    }
}

function buildAdminLockState(mp) {
    var info = (mp && mp.info) ? mp.info : {};
    var sessionLock = (info.sessionLock && info.sessionLock.active) ? info.sessionLock : null;
    var canInteract = mp && mp.canInteract !== false;
    var hasSessionAccessFlag = !sessionLock || sessionLock.accessGranted === true || sessionLock.isOwner === true || permissions.manage === true;
    var canEdit = canInteract && hasSessionAccessFlag;
    var isLockOwner = permissions.manage === true || (sessionLock && sessionLock.isOwner === true);

    var lockStatusText;
    if (!sessionLock) {
        lockStatusText = 'Session is unlocked. Anyone with access can manage playback.';
    } else if (sessionLock.hasPin) {
        lockStatusText = 'Locked by ' + (sessionLock.ownerName || 'another player') + '. PIN access enabled.';
    } else {
        lockStatusText = 'Locked by ' + (sessionLock.ownerName || 'another player') + '. Owner access only.';
    }

    var lockActionsHtml = '';
    if (!sessionLock) {
        lockActionsHtml =
            '<button class="btn-outline btn-sm" id="lock-session-btn"' + (canInteract ? '' : ' disabled') + '>Lock Session</button>' +
            '<button class="btn-outline btn-sm" id="lock-session-pin-btn"' + (canInteract ? '' : ' disabled') + '>Lock With PIN</button>';
    } else if (hasSessionAccessFlag) {
        if (isLockOwner) {
            lockActionsHtml =
                '<button class="btn-outline btn-sm" id="unlock-session-btn"' + (canInteract ? '' : ' disabled') + '>Unlock Session</button>' +
                '<button class="btn-outline btn-sm" id="set-session-pin-btn"' + (canInteract ? '' : ' disabled') + '>Set or Change PIN</button>' +
                '<button class="btn-outline btn-sm" id="clear-session-pin-btn"' + ((sessionLock.hasPin && canInteract) ? '' : ' disabled') + '>Clear PIN</button>';
        } else {
            lockActionsHtml = '<span class="admin-hint">Access granted by PIN for this session.</span>';
        }
    } else if (sessionLock.hasPin) {
        lockActionsHtml = '<button class="btn-outline btn-sm" id="authorize-session-pin-btn"' + (canInteract ? '' : ' disabled') + '>Enter PIN</button>';
    } else {
        lockActionsHtml = '<span class="admin-hint">This session is owner-locked and has no PIN.</span>';
    }

    var signature = [
        sessionLock ? 1 : 0,
        sessionLock && sessionLock.ownerName ? sessionLock.ownerName : '',
        sessionLock && sessionLock.hasPin ? 1 : 0,
        sessionLock && sessionLock.isOwner ? 1 : 0,
        sessionLock && sessionLock.accessGranted ? 1 : 0,
        canInteract ? 1 : 0,
        permissions.manage === true ? 1 : 0
    ].join('|');

    return {
        info: info,
        sessionLock: sessionLock,
        canInteract: canInteract,
        canEdit: canEdit,
        lockStatusText: lockStatusText,
        lockActionsHtml: lockActionsHtml,
        signature: signature
    };
}

function bindAdminLockButtons(handle, body) {
    if (!body) return;

    var lockBtn = body.querySelector('#lock-session-btn');
    if (lockBtn) {
        lockBtn.onclick = function() {
            sendMessage('lockSession', { handle: handle });
        };
    }

    var lockPinBtn = body.querySelector('#lock-session-pin-btn');
    if (lockPinBtn) {
        lockPinBtn.onclick = function() {
            showPrompt('Lock Session', 'Enter a 4-12 character PIN', function(pin) {
                if (pin == null) return;
                var trimmed = (pin || '').trim();
                if (!trimmed) {
                    showNotification('PIN cannot be empty.', 'Device Settings', '#ff4444');
                    return;
                }
                sendMessage('lockSession', { handle: handle, pin: trimmed });
            });
        };
    }

    var unlockBtn = body.querySelector('#unlock-session-btn');
    if (unlockBtn) {
        unlockBtn.onclick = function() {
            sendMessage('unlockSession', { handle: handle });
        };
    }

    var setPinBtn = body.querySelector('#set-session-pin-btn');
    if (setPinBtn) {
        setPinBtn.onclick = function() {
            showPrompt('Session PIN', 'Enter a 4-12 character PIN', function(pin) {
                if (pin == null) return;
                var trimmed = (pin || '').trim();
                if (!trimmed) {
                    showNotification('PIN cannot be empty.', 'Device Settings', '#ff4444');
                    return;
                }
                sendMessage('setSessionPin', { handle: handle, pin: trimmed });
            });
        };
    }

    var clearPinBtn = body.querySelector('#clear-session-pin-btn');
    if (clearPinBtn) {
        clearPinBtn.onclick = function() {
            sendMessage('setSessionPin', { handle: handle, pin: null });
        };
    }

    var authorizeBtn = body.querySelector('#authorize-session-pin-btn');
    if (authorizeBtn) {
        authorizeBtn.onclick = function() {
            showPrompt('Unlock With PIN', 'Enter session PIN', function(pin) {
                if (pin == null) return;
                var trimmed = (pin || '').trim();
                if (!trimmed) {
                    showNotification('PIN cannot be empty.', 'Device Settings', '#ff4444');
                    return;
                }
                sendMessage('authorizeSessionPin', { handle: handle, pin: trimmed });
            });
        };
    }
}

function getAdminStateFromInfo(info) {
    var defaults = getGlobalDeviceDefaults();
    var state = {
        range: info && info.range != null ? Number(info.range) : defaults.range,
        volume: info && info.volume != null ? Number(info.volume) : defaults.volume,
        attSame: info && info.attenuation && info.attenuation.sameRoom != null ? Number(info.attenuation.sameRoom) : defaults.attenuation.sameRoom,
        attDiff: info && info.attenuation && info.attenuation.diffRoom != null ? Number(info.attenuation.diffRoom) : defaults.attenuation.diffRoom,
        diffRoomVolume: info && info.diffRoomVolume != null ? Number(info.diffRoomVolume) : defaults.diffRoomVolume,
        transitionSeconds: info && info.transitionSeconds != null ? Number(info.transitionSeconds) : defaults.transitionSeconds,
        isVehicle: info && info.isVehicle === true
    };

    if (!Number.isFinite(state.range)) state.range = defaults.range;
    if (!Number.isFinite(state.volume)) state.volume = defaults.volume;
    if (!Number.isFinite(state.attSame)) state.attSame = defaults.attenuation.sameRoom;
    if (!Number.isFinite(state.attDiff)) state.attDiff = defaults.attenuation.diffRoom;
    if (!Number.isFinite(state.diffRoomVolume)) state.diffRoomVolume = defaults.diffRoomVolume;
    if (!Number.isFinite(state.transitionSeconds)) state.transitionSeconds = defaults.transitionSeconds;

    state.range = Math.max(0, Math.min(Math.max(maxRange, adminMaxRange), state.range));
    state.volume = Math.max(0, Math.min(100, state.volume));
    state.attSame = Math.max(0, Math.min(10, state.attSame));
    state.attDiff = Math.max(0, Math.min(10, state.attDiff));
    state.diffRoomVolume = Math.max(0, Math.min(1, state.diffRoomVolume));
    state.transitionSeconds = Math.max(0, Math.min(maxTransitionSeconds, state.transitionSeconds));

    return state;
}

function getAdminDefaultsFromPayload(payload) {
    var merged = getGlobalDeviceDefaults();
    if (payload && typeof payload === 'object') {
        if (payload.attenuation && typeof payload.attenuation === 'object') {
            merged.attenuation = {
                sameRoom: payload.attenuation.sameRoom,
                diffRoom: payload.attenuation.diffRoom
            };
        }
        Object.keys(payload).forEach(function(key) {
            if (key === 'attenuation') return;
            merged[key] = payload[key];
        });
    }
    return getAdminStateFromInfo(merged);
}

function adminStatesMatch(state, defaults) {
    if (!state || !defaults) return true;
    return Math.abs(state.range - defaults.range) < 0.01
        && Math.abs(state.volume - defaults.volume) < 0.01
        && Math.abs(state.attSame - defaults.attSame) < 0.01
        && Math.abs(state.attDiff - defaults.attDiff) < 0.01
        && Math.abs(state.diffRoomVolume - defaults.diffRoomVolume) < 0.001
        && Math.abs(state.transitionSeconds - defaults.transitionSeconds) < 0.01
        && state.isVehicle === defaults.isVehicle;
}

function canUseAdminRange() {
    return permissions.overrideDevice === true && adminMaxRange > maxRange;
}

function clampRangeValue(value, allowAdmin) {
    var numeric = Number(value);
    if (!Number.isFinite(numeric)) {
        numeric = 0;
    }
    return Math.max(0, Math.min(allowAdmin ? adminMaxRange : maxRange, numeric));
}

function getRangeSliderValue(rangeValue, allowAdmin) {
    var clamped = clampRangeValue(rangeValue, allowAdmin);
    if (!allowAdmin || adminMaxRange <= maxRange) {
        return Math.round(clamped);
    }
    if (clamped <= maxRange) {
        return Math.round((clamped / maxRange) * 500);
    }
    return 500 + Math.round(((clamped - maxRange) / (adminMaxRange - maxRange)) * 500);
}

function getRangeFromSliderValue(sliderValue, allowAdmin) {
    var numeric = Number(sliderValue);
    if (!Number.isFinite(numeric)) {
        numeric = 0;
    }
    if (!allowAdmin || adminMaxRange <= maxRange) {
        return clampRangeValue(numeric, false);
    }
    if (Math.abs(numeric - 500) <= 10) {
        numeric = 500;
    }
    if (numeric <= 500) {
        return clampRangeValue((numeric / 500) * maxRange, true);
    }
    return clampRangeValue(maxRange + (((numeric - 500) / 500) * (adminMaxRange - maxRange)), true);
}

function updateAdminRangeSliderVisual(input, allowAdmin) {
    if (!input) return;
    input.classList.toggle('slider-admin-range', !!allowAdmin);
}

function syncAdminControls(body, state) {
    if (!body || !state) return;

    var rangeInput = body.querySelector('#set-range');
    var volumeInput = body.querySelector('#set-volume');
    var attSameInput = body.querySelector('#set-att-same');
    var attDiffInput = body.querySelector('#set-att-diff');
    var diffRoomInput = body.querySelector('#set-diff-room');
    var transitionInput = body.querySelector('#set-transition');
    var vehicleToggle = body.querySelector('#toggle-veh');
    var allowAdminRange = canUseAdminRange();

    if (rangeInput) {
        rangeInput.value = String(getRangeSliderValue(state.range, allowAdminRange));
        updateAdminRangeSliderVisual(rangeInput, allowAdminRange);
    }
    if (volumeInput) volumeInput.value = String(Math.round(state.volume));
    if (attSameInput) attSameInput.value = state.attSame.toFixed(1);
    if (attDiffInput) attDiffInput.value = state.attDiff.toFixed(1);
    if (diffRoomInput) diffRoomInput.value = state.diffRoomVolume.toFixed(2);
    if (transitionInput) transitionInput.value = state.transitionSeconds.toFixed(1);

    var rangeLabel = body.querySelector('#val-range');
    var volumeLabel = body.querySelector('#val-volume');
    var attSameLabel = body.querySelector('#val-att-same');
    var attDiffLabel = body.querySelector('#val-att-diff');
    var diffRoomLabel = body.querySelector('#val-diff-room');
    var transitionLabel = body.querySelector('#val-transition');

    if (rangeLabel) rangeLabel.textContent = Math.round(state.range) + 'm';
    if (volumeLabel) volumeLabel.textContent = Math.round(state.volume) + '%';
    if (attSameLabel) attSameLabel.textContent = state.attSame.toFixed(1);
    if (attDiffLabel) attDiffLabel.textContent = state.attDiff.toFixed(1);
    if (diffRoomLabel) diffRoomLabel.textContent = (state.diffRoomVolume * 100).toFixed(0) + '%';
    if (transitionLabel) transitionLabel.textContent = state.transitionSeconds.toFixed(1) + 's';

    if (vehicleToggle) {
        vehicleToggle.textContent = state.isVehicle ? 'ON' : 'OFF';
        vehicleToggle.classList.toggle('toggle-on', state.isVehicle);
    }
}

function resetAdminWriteTimers() {
    if (!_adminEditState || !_adminEditState.timers) return;
    Object.keys(_adminEditState.timers).forEach(function(key) {
        clearTimeout(_adminEditState.timers[key]);
    });
    _adminEditState.timers = {};
}

function updateAdminResetControls(body, state, defaults, canEdit, onReset) {
    if (!body) return;
    var row = body.querySelector('#admin-reset-row');
    var button = body.querySelector('#admin-reset-btn');
    if (!row || !button) return;

    var shouldShow = canEdit && !adminStatesMatch(state, defaults);
    row.style.display = shouldShow ? 'flex' : 'none';
    button.disabled = !shouldShow;
    button.onclick = shouldShow ? onReset : null;
}

function openAdminModal(forcedHandle) {
    var handle = Number.isFinite(Number(forcedHandle)) ? Number(forcedHandle) : _h();
    var mpKey = handleKey(handle);
    var mp = mpKey ? mediaPlayerStates[mpKey] : null;
    if (!mp && mpKey) {
        mp = buildSessionDeviceState(mpKey);
    }
    if (!mp) {
        mp = getCurrentMP();
    }

    if (!handle) {
        showNotification('Select a nearby device first.', 'Device Settings');
        return;
    }
    if (!mp) {
        showNotification('This device is no longer available.', 'Device Settings', '#ff4444');
        return;
    }

    sendRequest('getMediaPlayerDefaults', { handle: handle }).then(function(defaultsPayload) {
        var currentMpKey = handleKey(handle);
        var currentMp = currentMpKey ? mediaPlayerStates[currentMpKey] : null;
        if (!currentMp && currentMpKey) {
            currentMp = buildSessionDeviceState(currentMpKey);
        }
        if (!currentMp) {
            currentMp = getCurrentMP();
        }
        if (!currentMp) {
            showNotification('This device is no longer available.', 'Device Settings', '#ff4444');
            return;
        }

        var modal = document.getElementById('admin-modal');
        var body  = document.getElementById('admin-body');
        if (!modal || !body) return;

        _clearAdminEditState();
        _adminEditState = { timers: {} };

        var lockState = buildAdminLockState(currentMp);
        var info = lockState.info;
        var canEdit = lockState.canEdit;
        var canInteract = lockState.canInteract;
        var session = getEffectiveDeviceSession(handle);
        var defaults = getAdminDefaultsFromPayload(defaultsPayload);
        var state = getAdminStateFromInfo(info);
        var resetStatusText = getResetStatusText(handle) || 'No reset scheduled';
        var historyCount = session && Array.isArray(session.history)
            ? session.history.length
            : (session && Number.isFinite(Number(session.historyCount)) ? Number(session.historyCount) : 0);
        var queueCount = session && Number.isFinite(Number(session.queueLength)) ? Number(session.queueLength) : ((info.queue && info.queue.length) || 0);
        var allowAdminRange = canUseAdminRange();
        var maxAllowedRange = allowAdminRange ? adminMaxRange : maxRange;
        var rangeSliderMax = allowAdminRange ? 1000 : Math.round(maxRange);
        var rangeSliderValue = getRangeSliderValue(state.range, allowAdminRange);
        var showForceReset = permissions.overrideDevice === true;

        body.dataset.handle = String(handle);
        body.dataset.lockSignature = lockState.signature;
        body.dataset.stateSignature = [
            lockState.signature,
            session && session.stateRevision ? session.stateRevision : 0,
            currentMp && currentMp.info && currentMp.info.url ? 1 : 0
        ].join('|');

        body.innerHTML =
            '<div class="admin-section">' +
                '<div class="admin-row"><label>Device</label><span class="admin-val">' + safeText(currentMp.label || 'Device') + '</span></div>' +
            '</div>' +

        '<div class="admin-section admin-lock" id="admin-lock-section">' +
            '<label class="admin-label">Session Lock</label>' +
            '<div class="admin-lock-status" id="admin-lock-status">' + safeText(lockState.lockStatusText) + '</div>' +
            '<div class="admin-lock-actions" id="admin-lock-actions">' + lockState.lockActionsHtml + '</div>' +
        '</div>' +

        '<div class="admin-section">' +
            '<div class="admin-row"><label>Idle Reset</label><span class="admin-val" id="admin-reset-countdown">' + safeText(resetStatusText) + '</span></div>' +
            '<div class="admin-row"><label>History</label><span class="admin-val" id="admin-history-count">' + safeText(String(historyCount)) + '</span></div>' +
            '<div class="admin-row"><label>Queue</label><span class="admin-val" id="admin-queue-count">' + safeText(String(queueCount)) + '</span></div>' +
        '</div>' +

        '<div class="admin-section">' +
            '<label class="admin-label">Range <span id="val-range">' + Math.round(state.range) + 'm</span></label>' +
            '<input type="range" class="slider' + (allowAdminRange ? ' slider-admin-range' : '') + '" id="set-range" min="0" max="' + rangeSliderMax + '" value="' + rangeSliderValue + '"' + (canEdit ? '' : ' disabled') + '>' +
            '<div class="admin-range-meta"><span>Normal max ' + Math.round(maxRange) + 'm</span>' + (allowAdminRange ? '<span class="admin-range-admin">Admin max ' + Math.round(maxAllowedRange) + 'm</span>' : '') + '</div>' +
        '</div>' +

        '<div class="admin-section">' +
            '<label class="admin-label">Volume <span id="val-volume">' + Math.round(state.volume) + '%</span></label>' +
            '<input type="range" class="slider" id="set-volume" min="0" max="100" value="' + Math.round(state.volume) + '"' + (canEdit ? '' : ' disabled') + '>' +
        '</div>' +

        '<div class="admin-section">' +
            '<label class="admin-label">Same-Room Attenuation <span id="val-att-same">' + state.attSame.toFixed(1) + '</span></label>' +
            '<input type="range" class="slider" id="set-att-same" min="0" max="10" step="0.1" value="' + state.attSame.toFixed(1) + '"' + (canEdit ? '' : ' disabled') + '>' +
        '</div>' +

        '<div class="admin-section">' +
            '<label class="admin-label">Diff-Room Attenuation <span id="val-att-diff">' + state.attDiff.toFixed(1) + '</span></label>' +
            '<input type="range" class="slider" id="set-att-diff" min="0" max="10" step="0.1" value="' + state.attDiff.toFixed(1) + '"' + (canEdit ? '' : ' disabled') + '>' +
        '</div>' +

        '<div class="admin-section">' +
            '<label class="admin-label">Diff-Room Volume <span id="val-diff-room">' + (state.diffRoomVolume * 100).toFixed(0) + '%</span></label>' +
            '<input type="range" class="slider" id="set-diff-room" min="0" max="1" step="0.01" value="' + state.diffRoomVolume.toFixed(2) + '"' + (canEdit ? '' : ' disabled') + '>' +
        '</div>' +

        '<div class="admin-section">' +
            '<label class="admin-label">Transition <span id="val-transition">' + state.transitionSeconds.toFixed(1) + 's</span></label>' +
            '<input type="range" class="slider" id="set-transition" min="0" max="' + maxTransitionSeconds.toFixed(1) + '" step="0.1" value="' + state.transitionSeconds.toFixed(1) + '"' + (canEdit ? '' : ' disabled') + '>' +
        '</div>' +

        '<div class="admin-section admin-row" id="admin-reset-row" style="display:none;">' +
            '<label>Defaults</label>' +
            '<button class="btn-outline btn-sm" id="admin-reset-btn"' + (canEdit ? '' : ' disabled') + '>Reset to Defaults</button>' +
        '</div>' +

        '<div class="admin-section admin-row">' +
            '<label>Vehicle Mode</label>' +
            '<button class="toggle-btn' + (state.isVehicle ? ' toggle-on' : '') + '" id="toggle-veh"' + (canEdit ? '' : ' disabled') + '>' + (state.isVehicle ? 'ON' : 'OFF') + '</button>' +
        '</div>' +

        (showForceReset
            ? '<div class="admin-section admin-row admin-danger-row">' +
                '<label>Live Session</label>' +
                '<button class="btn-danger btn-sm" id="admin-force-reset-btn">Delete Device</button>' +
            '</div>'
            : '');

        var sendRange = function() {
        setPendingControlField(handle, 'range', state.range);
        sendMessage('setRange', { handle: handle, range: Math.round(state.range) });
        };
        var sendVolume = function() {
        setPendingControlField(handle, 'volume', state.volume);
        sendMessage('setVolume', { handle: handle, volume: Math.round(state.volume) });
        };
        var sendAttenuation = function() {
        setPendingControlField(handle, 'attSame', state.attSame);
        setPendingControlField(handle, 'attDiff', state.attDiff);
        sendMessage('setAttenuation', { handle: handle, sameRoom: state.attSame, diffRoom: state.attDiff });
        };
        var sendDiffRoomVolume = function() {
        setPendingControlField(handle, 'diffRoomVolume', state.diffRoomVolume);
        sendMessage('setDiffRoomVolume', { handle: handle, diffRoomVolume: state.diffRoomVolume });
        };
        var sendTransition = function() {
        setPendingControlField(handle, 'transitionSeconds', state.transitionSeconds);
        sendMessage('setTransition', { handle: handle, transitionSeconds: state.transitionSeconds });
        };
        var refreshResetControls = function() {
        updateAdminResetControls(body, state, defaults, canEdit, function() {
            var previous = {
                range: state.range,
                volume: state.volume,
                attSame: state.attSame,
                attDiff: state.attDiff,
                diffRoomVolume: state.diffRoomVolume,
                transitionSeconds: state.transitionSeconds,
                isVehicle: state.isVehicle
            };

            resetAdminWriteTimers();
            state.range = defaults.range;
            state.volume = defaults.volume;
            state.attSame = defaults.attSame;
            state.attDiff = defaults.attDiff;
            state.diffRoomVolume = defaults.diffRoomVolume;
            state.transitionSeconds = defaults.transitionSeconds;
            state.isVehicle = defaults.isVehicle;

            syncAdminControls(body, state);

            if (Math.abs(previous.range - state.range) >= 0.01) sendRange();
            if (Math.abs(previous.volume - state.volume) >= 0.01) sendVolume();
            if (Math.abs(previous.attSame - state.attSame) >= 0.01 || Math.abs(previous.attDiff - state.attDiff) >= 0.01) sendAttenuation();
            if (Math.abs(previous.diffRoomVolume - state.diffRoomVolume) >= 0.001) sendDiffRoomVolume();
            if (Math.abs(previous.transitionSeconds - state.transitionSeconds) >= 0.01) sendTransition();
            if (previous.isVehicle !== state.isVehicle) {
                setPendingControlField(handle, 'isVehicle', state.isVehicle);
                sendMessage('setIsVehicle', { handle: handle, isVehicle: state.isVehicle });
            }

            refreshResetControls();
        });
        };

        _adminSlider('set-range', 'val-range', function(v) {
        var numeric = Number(v);
        if (allowAdminRange && Math.abs(numeric - 500) <= 10) {
            numeric = 500;
        }
        return Math.round(getRangeFromSliderValue(numeric, allowAdminRange)) + 'm';
    }, function(v) {
        var numeric = Number(v);
        if (allowAdminRange && Math.abs(numeric - 500) <= 10) {
            numeric = 500;
            var rangeInput = body.querySelector('#set-range');
            if (rangeInput) {
                rangeInput.value = '500';
            }
        }
        state.range = getRangeFromSliderValue(numeric, allowAdminRange);
        setPendingControlField(handle, 'range', state.range);
        refreshResetControls();
        _queueAdminWrite('range', sendRange, 120);
    }, function() {
        _flushAdminWrite('range', sendRange);
    });

        _adminSlider('set-volume', 'val-volume', function(v) {
        return Math.round(parseFloat(v) || 0) + '%';
    }, function(v) {
        state.volume = Math.max(0, Math.min(100, parseFloat(v) || 0));
        setPendingControlField(handle, 'volume', state.volume);
        refreshResetControls();
        _queueAdminWrite('volume', sendVolume, 100);
    }, function() {
        _flushAdminWrite('volume', sendVolume);
    });

        _adminSlider('set-att-same', 'val-att-same', function(v) {
        return (parseFloat(v) || 0).toFixed(1);
    }, function(v) {
        state.attSame = Math.max(0, Math.min(10, parseFloat(v) || 0));
        setPendingControlField(handle, 'attSame', state.attSame);
        refreshResetControls();
        _queueAdminWrite('attenuation', sendAttenuation, 140);
    }, function() {
        _flushAdminWrite('attenuation', sendAttenuation);
    });

        _adminSlider('set-att-diff', 'val-att-diff', function(v) {
        return (parseFloat(v) || 0).toFixed(1);
    }, function(v) {
        state.attDiff = Math.max(0, Math.min(10, parseFloat(v) || 0));
        setPendingControlField(handle, 'attDiff', state.attDiff);
        refreshResetControls();
        _queueAdminWrite('attenuation', sendAttenuation, 140);
    }, function() {
        _flushAdminWrite('attenuation', sendAttenuation);
    });

        _adminSlider('set-diff-room', 'val-diff-room', function(v) {
        return ((parseFloat(v) || 0) * 100).toFixed(0) + '%';
    }, function(v) {
        state.diffRoomVolume = Math.max(0, Math.min(1, parseFloat(v) || 0));
        setPendingControlField(handle, 'diffRoomVolume', state.diffRoomVolume);
        refreshResetControls();
        _queueAdminWrite('diffRoomVolume', sendDiffRoomVolume, 120);
    }, function() {
        _flushAdminWrite('diffRoomVolume', sendDiffRoomVolume);
    });

        _adminSlider('set-transition', 'val-transition', function(v) {
        return (parseFloat(v) || 0).toFixed(1) + 's';
    }, function(v) {
        state.transitionSeconds = Math.max(0, Math.min(maxTransitionSeconds, parseFloat(v) || 0));
        setPendingControlField(handle, 'transitionSeconds', state.transitionSeconds);
        refreshResetControls();
        _queueAdminWrite('transition', sendTransition, 120);
    }, function() {
        _flushAdminWrite('transition', sendTransition);
    });

        var vehToggle = body.querySelector('#toggle-veh');
        if (vehToggle) {
            vehToggle.onclick = function() {
                if (this.disabled) return;
                state.isVehicle = !state.isVehicle;
                this.textContent = state.isVehicle ? 'ON' : 'OFF';
                this.classList.toggle('toggle-on', state.isVehicle);
                setPendingControlField(handle, 'isVehicle', state.isVehicle);
                refreshResetControls();
                sendMessage('setIsVehicle', { handle: handle, isVehicle: state.isVehicle });
            };
        }

        var forceResetBtn = body.querySelector('#admin-force-reset-btn');
        if (forceResetBtn) {
            forceResetBtn.onclick = function() {
                showConfirm('Delete Device?', 'This clears the live device session only. Saved model and world defaults stay intact.', function(ok) {
                    if (!ok) return;
                    sendMessage('forceResetDevice', { handle: handle });
                    closeAdminModal();
                });
            };
        }
        bindAdminLockButtons(handle, body);
        refreshResetControls();
        syncAdminControls(body, state);

        modal.style.display = 'flex';
    });
}

function _adminSlider(inputId, valId, format, onInput, onCommit) {
    var inp = document.getElementById(inputId);
    var val = document.getElementById(valId);
    if (!inp || !val) return;

    var updateLabel = function() {
        val.textContent = format(inp.value);
    };

    inp.oninput = function() {
        updateLabel();
        if (typeof onInput === 'function') {
            onInput(inp.value);
        }
    };

    inp.onchange = function() {
        updateLabel();
        if (typeof onCommit === 'function') {
            onCommit(inp.value);
        }
    };
}

function closeAdminModal() {
    _clearAdminEditState();
    var m = document.getElementById('admin-modal');
    if (m) m.style.display = 'none';
}

function refreshAdminModalFromState() {
    var modal = document.getElementById('admin-modal');
    var body = document.getElementById('admin-body');
    if (!modal || !body || modal.style.display !== 'flex') return;

    var handle = Number(body.dataset.handle);
    if (!Number.isFinite(handle)) return;

    var key = handleKey(handle);
    var mp = key ? mediaPlayerStates[key] : null;
    if (!mp) {
        mp = buildSessionDeviceState(key);
    }
    if (!mp) {
        closeAdminModal();
        return;
    }

    var lockState = buildAdminLockState(mp);
    var session = getEffectiveDeviceSession(handle);

    var resetCountdown = body.querySelector('#admin-reset-countdown');
    if (resetCountdown) {
        resetCountdown.textContent = getResetStatusText(handle) || 'No reset scheduled';
    }

    var historyCount = body.querySelector('#admin-history-count');
    if (historyCount) {
        historyCount.textContent = session && Array.isArray(session.history)
            ? String(session.history.length)
            : (session && Number.isFinite(Number(session.historyCount)) ? String(Number(session.historyCount)) : '0');
    }

    var queueCount = body.querySelector('#admin-queue-count');
    if (queueCount) {
        var count = session && Number.isFinite(Number(session.queueLength))
            ? Number(session.queueLength)
            : (((mp.info && mp.info.queue) || []).length || 0);
        queueCount.textContent = String(count);
    }

    if (body.dataset.lockSignature !== lockState.signature) {
        openAdminModal(handle);
    }
}

function showPrompt(title, placeholder, callback) {
    var modal   = document.getElementById('prompt-modal');
    var input   = document.getElementById('prompt-input');
    var confirm = document.getElementById('prompt-confirm');
    var cancel  = document.getElementById('prompt-cancel');
    var ttl     = document.getElementById('prompt-title');
    if (!modal) return;

    if (ttl)   ttl.textContent   = title;
    if (input) { input.placeholder = placeholder || 'Enter value...'; input.value = ''; }

    modal.style.display = 'flex';
    if (input) setTimeout(function() { input.focus(); }, 50);

    function done(val) {
        modal.style.display = 'none';
        _cleanup();
        callback(val);
    }

    function _cleanup() {
        if (confirm) confirm.onclick = null;
        if (cancel)  cancel.onclick  = null;
        if (input)   input.onkeydown = null;
    }

    if (confirm) confirm.onclick = function() { done(input ? input.value : null); };
    if (cancel)  cancel.onclick  = function() { done(null); };
    if (input)   input.onkeydown = function(e) {
        if (e.key === 'Enter') done(input.value);
        if (e.key === 'Escape') done(null);
    };
}

function showConfirm(title, message, callback) {
    var modal  = document.getElementById('confirm-modal');
    var ok     = document.getElementById('confirm-ok');
    var cancel = document.getElementById('confirm-cancel');
    var ttl    = document.getElementById('confirm-title');
    var msg    = document.getElementById('confirm-message');
    if (!modal) return;

    if (ttl) ttl.textContent = title;
    if (msg) msg.textContent = message;

    modal.style.display = 'flex';

    function done(v) {
        modal.style.display = 'none';
        if (ok)     ok.onclick     = null;
        if (cancel) cancel.onclick = null;
        callback(v);
    }

    if (ok)     ok.onclick     = function() { done(true); };
    if (cancel) cancel.onclick = function() { done(false); };
}

function ensureUiEnhancements() {
    if (document.getElementById('pmms-ui-enhancements')) {
        return;
    }

    var style = document.createElement('style');
    style.id = 'pmms-ui-enhancements';
    style.textContent =
        '[data-tooltip]{position:relative;}' +
        '[data-tooltip]:hover::after,[data-tooltip]:focus-visible::after{' +
            'content:attr(data-tooltip);position:absolute;left:50%;bottom:calc(100% + 8px);transform:translateX(-50%);' +
            'background:rgba(8,8,12,0.96);color:#f0f0f8;border:1px solid rgba(255,255,255,0.12);' +
            'border-radius:8px;padding:6px 9px;font-size:11px;white-space:nowrap;pointer-events:none;z-index:1200;' +
            'box-shadow:0 10px 28px rgba(0,0,0,0.45);' +
        '}' +
        '#friend-suggestions{' +
            'position:absolute;left:0;right:0;top:calc(100% + 8px);display:none;flex-direction:column;gap:4px;' +
            'padding:8px;background:rgba(18,18,28,0.98);border:1px solid rgba(255,255,255,0.08);border-radius:12px;' +
            'box-shadow:0 18px 42px rgba(0,0,0,0.45);z-index:1000;max-height:260px;overflow-y:auto;' +
        '}' +
        '.add-friend-bar{position:relative;}' +
        '.friend-suggestion{' +
            'display:flex;justify-content:space-between;align-items:center;gap:10px;padding:10px 12px;border-radius:10px;' +
            'cursor:pointer;color:var(--text-primary);transition:background 0.18s ease;' +
        '}' +
        '.friend-suggestion:hover,.friend-suggestion:focus-visible{background:rgba(255,255,255,0.06);outline:none;}' +
        '.friend-suggestion-meta{display:flex;flex-direction:column;min-width:0;}' +
        '.friend-suggestion-name{font-size:13px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}' +
        '.friend-suggestion-sub{font-size:11px;color:var(--text-muted);}' +
        '.friend-suggestion-badge{font-size:10px;font-weight:700;padding:3px 7px;border-radius:999px;border:1px solid rgba(255,255,255,0.08);}' +
        '.friend-suggestion-badge.online{color:#4ade80;background:rgba(74,222,128,0.12);}' +
        '.friend-suggestion-badge.offline{color:#fbbf24;background:rgba(251,191,36,0.12);}' +
        '#library-summary{font-size:12px;color:var(--text-muted);}' +
        '.library-summary-warning{color:#fbbf24;}' +
        '.social-hint{font-size:12px;color:var(--text-muted);margin-top:8px;}' +
        '.np-queue-item .np-queue-add{margin-right:4px;}';
    document.head.appendChild(style);
}

function applyStaticTooltips() {
    document.querySelectorAll('[title]').forEach(function(element) {
        var title = element.getAttribute('title');
        if (!title) return;
        if (!element.getAttribute('data-tooltip')) {
            element.setAttribute('data-tooltip', title);
        }
        if (!element.getAttribute('aria-label')) {
            element.setAttribute('aria-label', title);
        }
    });
}

function ensurePlayerSuggestionsContainer() {
    var bar = document.querySelector('.add-friend-bar');
    if (!bar) return null;

    var existing = document.getElementById('friend-suggestions');
    if (existing) return existing;

    var container = document.createElement('div');
    container.id = 'friend-suggestions';
    container.setAttribute('role', 'listbox');
    bar.appendChild(container);
    return container;
}

function hidePlayerSuggestions() {
    var container = ensurePlayerSuggestionsContainer();
    if (container) {
        container.style.display = 'none';
    }
    playerSuggestionState.visible = false;
}

function renderPlayerSuggestions() {
    var container = ensurePlayerSuggestionsContainer();
    if (!container) return;

    var suggestions = playerSuggestionState.suggestions || [];
    if (!playerSuggestionState.visible || suggestions.length === 0) {
        container.style.display = 'none';
        container.innerHTML = '';
        return;
    }

    container.innerHTML = '';
    suggestions.forEach(function(entry) {
        var row = document.createElement('div');
        row.className = 'friend-suggestion';
        row.setAttribute('role', 'option');
        row.setAttribute('tabindex', '0');
        row.innerHTML =
            '<div class="friend-suggestion-meta">' +
                '<div class="friend-suggestion-name">' + safeText(entry.displayName || entry.license || 'Unknown') + '</div>' +
                '<div class="friend-suggestion-sub">' + safeText(entry.license || '') + '</div>' +
            '</div>' +
            '<span class="friend-suggestion-badge ' + (entry.online ? 'online' : 'offline') + '">' + (entry.online ? 'Online' : 'Recent') + '</span>';
        row.onclick = function() {
            var input = document.getElementById('friend-id-input');
            if (input) input.value = entry.displayName || entry.license || '';
            playerSuggestionState.selectedLicense = entry.license || null;
            playerSuggestionState.selectedSource = entry.targetSrc || null;
            hidePlayerSuggestions();
        };
        row.onkeydown = function(e) {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                row.click();
            }
        };
        container.appendChild(row);
    });

    container.style.display = 'flex';
}

function requestPlayerSuggestions(query) {
    var requestId = ++playerSuggestionState.requestSeq;
    playerSuggestionState.pendingRequestId = requestId;
    sendMessage('getPlayerSuggestions', {
        query: query || '',
        requestId: requestId
    });
}

function handlePlayerSuggestions(suggestions, requestId) {
    var numericRequestId = Number(requestId);
    if (!Number.isFinite(numericRequestId)) {
        return;
    }
    if (playerSuggestionState.pendingRequestId != null && numericRequestId < playerSuggestionState.pendingRequestId) {
        return;
    }

    playerSuggestionState.pendingRequestId = null;
    playerSuggestionState.suggestions = Array.isArray(suggestions) ? suggestions.slice() : [];
    playerSuggestionState.visible = playerSuggestionState.suggestions.length > 0;
    renderPlayerSuggestions();
}

function initSocialAutocomplete() {
    ensurePlayerSuggestionsContainer();
    var input = document.getElementById('friend-id-input');
    if (!input) return;

    input.placeholder = 'Search players or enter a server ID...';

    var hint = document.getElementById('social-invite-hint');
    if (!hint) {
        hint = document.createElement('div');
        hint.id = 'social-invite-hint';
        hint.className = 'social-hint';
        hint.textContent = 'Suggestions include online players and recent visitors.';
        input.parentNode && input.parentNode.parentNode && input.parentNode.parentNode.insertBefore(hint, input.parentNode.nextSibling);
    }

    var refresh = function() {
        playerSuggestionState.selectedLicense = null;
        playerSuggestionState.selectedSource = null;
        clearTimeout(_playerSuggestionTimer);
        _playerSuggestionTimer = setTimeout(function() {
            requestPlayerSuggestions(input.value.trim());
        }, 120);
    };

    input.addEventListener('focus', refresh);
    input.addEventListener('input', refresh);
    input.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
            hidePlayerSuggestions();
        }
    });
}


var pmmsLegacyInitialized = false;

export function initLegacyUi() {
    if (pmmsLegacyInitialized) return;
    pmmsLegacyInitialized = true;

    ensureUiEnhancements();
    applyStaticTooltips();
    initSearch();
    initPlayerControls();
    initSocialAutocomplete();
    renderSidebarFavorites();

    document.addEventListener('keydown', function(e) {
        if (e.key !== 'Escape') return;
        var modals = ['admin-modal', 'share-modal', 'add-to-playlist-modal', 'loop-help-modal', 'confirm-modal', 'prompt-modal'];
        for (var i = 0; i < modals.length; i++) {
            var m = document.getElementById(modals[i]);
            if (m && m.style.display === 'flex') {
                if (modals[i] === 'admin-modal')        closeAdminModal();
                else if (modals[i] === 'confirm-modal') document.getElementById('confirm-cancel') && document.getElementById('confirm-cancel').click();
                else if (modals[i] === 'prompt-modal')  document.getElementById('prompt-cancel')  && document.getElementById('prompt-cancel').click();
                else m.style.display = 'none';
                return;
            }
        }
        sendMessage('closeUi');
    });

    document.addEventListener('click', function(e) {
        if (!e.target.closest('#search-bar') && !e.target.closest('#search-results')) {
            clearSearchResults();
        }
        if (!e.target.closest('.add-friend-bar')) {
            hidePlayerSuggestions();
        }
    });
}

export var legacyActions = {
    switchView: switchView,
    sendMessage: sendMessage,
    openCreatePlaylist: openCreatePlaylist,
    playPlaylist: playPlaylist,
    deleteCurrentPlaylist: deleteCurrentPlaylist,
    sendFriendRequest: sendFriendRequest,
    closeAdminModal: closeAdminModal
};

window.addEventListener('message', function(event) {
    var d = event.data;
    if (!d || !d.type) return;

    switch (d.type) {
        case 'showUi':
            updateUi({
                showUi: true,
                searchSources: d.searchSources,
                defaultSearchSource: d.defaultSearchSource,
                selectedHandle: d.selectedHandle,
                defaultTransitionSeconds: d.defaultTransitionSeconds,
                maxTransitionSeconds: d.maxTransitionSeconds,
                maxRange: d.maxRange,
                adminMaxRange: d.adminMaxRange,
                searchMinimumBusyMs: d.searchMinimumBusyMs,
                deviceDefaults: d.deviceDefaults,
                debug: d.debug
            });
            break;

        case 'hideUi':
            updateUi({ hideUi: true });
            break;

        case 'updateUi':
            queueUiUpdate(d);
            break;

        case 'showNotification':
            if (d.args) showNotification(d.args.text, d.args.title, d.args.color, d.args.duration);
            break;

        case 'searchResults':
            renderSearchResults(d.results, d.requestId);
            break;

        case 'searchError':
            handleSearchError(d.message, d.requestId, d.state, d.retryAfterMs);
            break;

        case 'setPlaylists':
            applyServerPlaylists(d.playlists || [], d.requestId, d.summary, d.libraryRevision);
            break;

        case 'playlistFavoriteUpdated':
            handlePlaylistFavoriteUpdate(d.payload || d);
            break;

        case 'setSharedPlaylists':
            applySharedPlaylists(d.playlists || [], d.requestId);
            break;

        case 'setPlaylistTracks':
            populatePlaylistTracks(d.playlistId, d.tracks);
            break;

        case 'setFriends':
            cachedFriends = d.friends || [];
            socialState.friendsLoaded = true;
            socialState.dirty = false;
            populateFriends(d.friends);
            break;

        case 'setFriendRequests':
            socialState.requestsLoaded = true;
            socialState.dirty = false;
            populateRequests(d.requests);
            break;

        case 'setPlayerSuggestions':
            handlePlayerSuggestions(d.suggestions || [], d.requestId);
            break;

        case 'refreshLibrary':
            libraryState.playlistsDirty = true;
            libraryState.sharedDirty = true;
            requestLibrary(true);
            break;

        case 'refreshSocial':
            socialState.dirty = true;
            requestSocial(true);
            break;

        case 'refreshPlaylist':
            if (currentPlaylistId && currentPlaylistId === d.playlistId) {
                sendMessage('getPlaylistTracks', { playlistId: d.playlistId });
            }
            break;

        case 'reset':
            activePlayerHandle = null;
            mediaPlayerStates  = {};
            startupStates = {};
            deviceSessions = {};
            usableMediaPlayers = [];
            usableMediaPlayerIndex = {};
            localPlaybackFailures = {};
            requestedStartupStates = {};
            authoritativePlaylists = [];
            cachedPlaylists = [];
            cachedSharedPlaylists = [];
            cachedFriends = [];
            Object.keys(pendingFavoriteState).forEach(function(key) {
                clearPendingFavoriteTimers(key);
            });
            pendingFavoriteState = {};
            favoriteRequestSeq = 0;
            favoriteResponseFloor = {};
            pendingControlState = {};
            librarySummary = {
                playlistCount: 0,
                favoriteCount: 0,
                maxPlaylists: 0,
                maxFavorites: 0
            };
            playerSuggestionState = {
                suggestions: [],
                requestSeq: 0,
                pendingRequestId: null,
                requestFloor: 0,
                selectedLicense: null,
                selectedSource: null,
                visible: false
            };
            libraryState = {
                playlistsLoaded: false,
                playlistsLoading: false,
                playlistsDirty: true,
                playlistRequestSeq: 0,
                playlistPendingRequestId: null,
                playlistResponseFloor: 0,
                libraryRevision: 0,
                sharedLoaded: false,
                sharedLoading: false,
                sharedDirty: true,
                sharedRequestSeq: 0,
                sharedPendingRequestId: null
            };
            socialState = {
                friendsLoaded: false,
                requestsLoaded: false,
                dirty: true
            };
            _lastNowPlayingPanelKey = '';
            _lastBottomPlayerKey = '';
            _activeSearchRequestId = null;
            clearTimeout(_playerSuggestionTimer);
            _playerSuggestionTimer = null;
            resetDevicesGridState();
            updateLibrarySummaryDisplay();
            updateBottomPlayer();
            updateNowPlayingPanel();
            renderSidebarFavorites();
            break;

        case 'stop':
            if (d.handle != null) {
                clearPendingControlForHandle(d.handle);
                delete localPlaybackFailures[handleKey(d.handle)];
                delete requestedStartupStates[handleKey(d.handle)];
                updateBottomPlayer();
                updateNowPlayingPanel();
            }
            break;
    }
});


