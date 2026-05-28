'use strict';

var mediaPlayerStates  = {};
var startupStates      = {};
var deviceSessions     = {};
var activePlayerHandle = null;
var permissions        = {};
var adminState         = null;
var deviceProfiles     = [];
var propModels         = [];
var speakerModels      = [];
var adminQuickActions  = {};
var requestConfig      = {};
var speakerConfig      = {};
var selectedAdminDeviceHandle = null;
var radioFavorites     = {};
var searchSources      = {};
var defaultSearchSource = 'youtube';
var defaultTransitionSeconds = 5.0;
var maxTransitionSeconds = 15.0;
var maxRange = 200;
var adminMaxRange = 200;
var searchMinimumBusyMs = 500;
var searchProxyThumbnails = true;
var currentServerEndpoint = '';
var showYoutubeProviderSelector = false;
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
var pendingPlaylistCreates = {};
var pendingPlaylistCreateSeq = 0;
var cachedFriends      = [];
var currentPlaylistId  = null;
var currentPlaylistName = '';
var currentPlaylistTracks = [];
var pendingTrackForPlaylist = null;
var pendingFavoriteState = {};
var confirmedFavoriteState = {};
var favoriteRequestSeq = 0;
var favoriteResponseFloor = {};
var quietPlaylistRefreshUntil = 0;
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
var _uiVisible = false;
var _lastUiUpdateSignature = '';
var _hideUiDisplayTimer = null;

var _lastGridHandles   = [];
var _lastActiveHandle  = null;
var _lastNowPlayingPanelKey = '';
var _lastBottomPlayerKey = '';

var URL_PATTERN = /^(https?:\/\/|www\.)[^\s]+$/i;
var YOUTUBE_URL_PATTERN = /(?:youtube\.com\/watch\?[^#\s]*v=|youtu\.be\/|youtube\.com\/shorts\/|youtube\.com\/embed\/)/i;
var youtubeProviderMode = 'auto';
var YOUTUBE_PROVIDER_OPTIONS = [
    { value: 'auto', label: 'Browser', description: 'Use the client Chromium YouTube player.' },
    { value: 'chromium_youtube', label: 'Browser', description: 'Force client Chromium playback.' },
    { value: 'yt_dlp_local', label: 'yt-dlp', description: 'Developer-only local extractor fallback.' },
    { value: 'extractor_http', label: 'Extractor API', description: 'Developer-only resolver endpoint fallback.' },
    { value: 'cobalt', label: 'Cobalt', description: 'Developer-only Cobalt endpoint fallback.' },
    { value: 'invidious', label: 'Invidious', description: 'Manual best-effort fallback; public instances can be slow.' },
    { value: 'piped', label: 'Piped', description: 'Manual best-effort fallback; public instances can be slow.' }
];
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
var FAVORITE_CONFIRMED_TTL_MS = 1800;
var pendingControlState = {};
var _searchBusySince = 0;
var _searchRetryTimer = null;
var _playerSuggestionTimer = null;
var localPlaybackFailures = {};
var requestedStartupStates = {};
var debugConfig = { enabled: false };
var localBaseVolume = 100;
var MAX_RENDERED_HISTORY_ITEMS = 30;
var selectedDeviceTheme = 'none';

function setUiVisible(visible) {
    _uiVisible = visible === true;
    if (_hideUiDisplayTimer) {
        clearTimeout(_hideUiDisplayTimer);
        _hideUiDisplayTimer = null;
    }
    document.body.style.display = 'block';
    document.body.classList.toggle('pmms-ui-visible', _uiVisible);
    document.body.classList.toggle('pmms-ui-hidden', !_uiVisible);
    window.dispatchEvent(new CustomEvent('pmms:motionStateChanged'));
}

function getStateMapSignature(map, includeOffsets) {
    var parts = [];
    Object.keys(map || {}).sort().forEach(function(key) {
        var value = map[key] || {};
        var info = value.info || value;
        parts.push([
            handleKey(key) || key,
            info.stateRevision || value.stateRevision || '',
            info.queueRevision || value.queueRevision || '',
            info.playbackToken || value.playbackToken || '',
            info.phase || value.phase || '',
            info.message || value.message || '',
            info.queueLength || value.queueLength || (Array.isArray(info.queue) ? info.queue.length : ''),
            info.historyCount || value.historyCount || '',
            includeOffsets ? Math.floor((Number(value.offset) || Number(info.offset) || 0) * 2) / 2 : ''
        ].join(':'));
    });
    return parts.join('|');
}

function getUiUpdateSignature(data) {
    if (!data || data.showUi || data.hideUi) return '';
    return [
        getStateMapSignature(data.activeMediaPlayers, true),
        getStateMapSignature(data.startupStates, false),
        getStateMapSignature(data.deviceSessions, false),
        getStateMapSignature(data.failedPlayers, false),
        Array.isArray(data.usableMediaPlayers)
            ? data.usableMediaPlayers.map(function(device) {
                return [
                    getDeviceRenderKey(device),
                    device && Math.round((Number(device.distance) || 0) * 2) / 2,
                    device && device.active ? 1 : 0,
                    device && device.visibleBecause || ''
                ].join(':');
            }).join('|')
            : '',
        data.admin && Array.isArray(data.admin.devices)
            ? data.admin.devices.map(function(device) {
                return [
                    handleKey(device && device.handle),
                    device && device.label || '',
                    device && device.requestMode || '',
                    device && device.pendingCount || 0,
                    device && device.stateRevision || 0,
                    device && device.active ? 1 : 0
                ].join(':');
            }).join('|')
            : '',
        data.admin && Array.isArray(data.admin.logs) && data.admin.logs.length
            ? (data.admin.logs[data.admin.logs.length - 1].id || 0)
            : '',
        data.baseVolume !== undefined ? clampPercent(data.baseVolume, localBaseVolume) : ''
    ].join('~');
}

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

function clampPercent(value, fallback) {
    var numeric = Number(value);
    if (!Number.isFinite(numeric)) {
        numeric = Number.isFinite(Number(fallback)) ? Number(fallback) : 100;
    }
    return Math.max(0, Math.min(100, Math.round(numeric)));
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

function encodeBase64Url(value) {
    try {
        return btoa(unescape(encodeURIComponent(value)))
            .replace(/\+/g, '-')
            .replace(/\//g, '_')
            .replace(/=+$/g, '');
    } catch (_) {
        return '';
    }
}

function getResourceHttpBase() {
    if (!currentServerEndpoint || typeof GetParentResourceName !== 'function') return '';
    return 'http://' + String(currentServerEndpoint).replace(/\/+$/g, '') + '/' + GetParentResourceName();
}

function getThumbnailDisplayUrl(url) {
    var normalized = normalizeRemoteAssetUrl(url);
    if (!normalized) return '';
    if (searchProxyThumbnails === false) return normalized;

    var encoded = encodeBase64Url(normalized);
    var base = encoded ? getResourceHttpBase() : '';
    return base ? (base + '/thumb/' + encoded) : normalized;
}

function getSearchThumbnailCandidates(result) {
    var candidates = [];
    var seen = {};

    function add(value) {
        var normalized = normalizeRemoteAssetUrl(value || '');
        if (!normalized) return;
        var key = normalized.toLowerCase();
        if (seen[key]) return;
        seen[key] = true;
        candidates.push(normalized);
    }

    if (Array.isArray(result && result.thumbnailCandidates)) {
        result.thumbnailCandidates.forEach(add);
    }
    add(result && result.thumbnail);
    return candidates;
}

function getMediaThumbnailCandidates(info) {
    var candidates = [];
    var seen = {};

    function add(value) {
        var normalized = normalizeRemoteAssetUrl(value || '');
        if (!normalized) return;
        var key = normalized.toLowerCase();
        if (seen[key]) return;
        seen[key] = true;
        candidates.push(normalized);
    }

    if (Array.isArray(info && info.thumbnailCandidates)) {
        info.thumbnailCandidates.forEach(add);
    }
    add(info && info.thumbnail);
    return candidates;
}

function getSearchThumbnailFallbackHtml(isRadioResult) {
    return '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">' +
        (isRadioResult
            ? '<path d="M4.9 19.1A10 10 0 0 1 2 12a10 10 0 0 1 20 0 10 10 0 0 1-2.9 7.1"/><circle cx="12" cy="12" r="2"/><path d="M12 14v8"/>'
            : '<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>') +
        '</svg>';
}

function bindSearchThumbnailFallback(thumbEl, candidates, isRadioResult) {
    if (!thumbEl) return;
    var img = thumbEl.querySelector('img');
    if (!img) return;

    var index = 0;
    var showNext = function() {
        while (index < candidates.length) {
            var src = getThumbnailDisplayUrl(candidates[index++]);
            if (src) {
                img.src = src;
                return;
            }
        }

        thumbEl.classList.add('sr-thumb-empty');
        thumbEl.removeAttribute('data-thumb');
        thumbEl.innerHTML = getSearchThumbnailFallbackHtml(isRadioResult);
    };

    img.onerror = showNext;
    showNext();
}

function bindMediaThumbnailFallback(thumbEl, candidates) {
    if (!thumbEl) return;
    var img = thumbEl.querySelector('img');
    if (!img) return;

    var index = 0;
    var showNext = function() {
        while (index < candidates.length) {
            var src = getThumbnailDisplayUrl(candidates[index++]);
            if (src) {
                img.src = src;
                return;
            }
        }

        thumbEl.classList.add('np-thumb-empty');
        thumbEl.innerHTML = '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>';
    };

    img.onerror = showNext;
    showNext();
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
        var renderKey = getDeviceRenderKey(device);
        if (renderKey) usableMediaPlayerIndex[renderKey] = device;
    });
}

function getDeviceRenderKey(device) {
    if (!device) return '';
    return handleKey(device.deviceKey || device.handle);
}

function getDeviceEntry(handle) {
    var key = handleKey(handle);
    return key ? usableMediaPlayerIndex[key] || null : null;
}

function getDeviceThemeFromDevice(device, handle) {
    var type = String((device && (device.type || device.deviceType)) || '').toLowerCase();
    var key = handleKey(handle || (device && device.handle));
    var state = key ? mediaPlayerStates[key] : null;
    var info = state && state.info ? getEffectiveInfo(key, state.info) : (state || null);

    if (type === 'vehicle' || (device && device.isVehicle === true) || (info && info.isVehicle === true)) {
        return 'vehicle';
    }

    if (type === 'interaction') {
        return 'interaction';
    }

    if (
        type === 'screen' ||
        type === 'tv' ||
        type === 'monitor' ||
        type === 'cinema' ||
        type === 'projector' ||
        type === 'laptop' ||
        type === 'tablet' ||
        type === 'computer' ||
        (device && device.hasVideo === true) ||
        (info && info.video !== false)
    ) {
        return 'screen';
    }

    return 'speaker';
}

function getDeviceThemeForHandle(handle) {
    var key = handleKey(handle);
    if (!key) return 'none';

    var device = getDeviceEntry(key);
    if (device) {
        return getDeviceThemeFromDevice(device, key);
    }

    return getDeviceThemeFromDevice(null, key);
}

function applySelectedDeviceTheme(theme) {
    selectedDeviceTheme = theme || 'none';
    if (!document.body) return;
    if (selectedDeviceTheme === 'none') {
        document.body.removeAttribute('data-pmms-device-theme');
    } else {
        document.body.setAttribute('data-pmms-device-theme', selectedDeviceTheme);
    }
    window.dispatchEvent(new CustomEvent('pmms:motionStateChanged'));
}

function refreshSelectedDeviceTheme() {
    applySelectedDeviceTheme(activePlayerHandle ? getDeviceThemeForHandle(activePlayerHandle) : 'none');
}

function getQueueRevisionForHandle(handle) {
    var key = handleKey(handle);
    if (!key) return 0;

    var session = deviceSessions[key] || null;
    if (session && Number.isFinite(Number(session.queueRevision))) {
        return Number(session.queueRevision);
    }

    var mp = mediaPlayerStates[key] || null;
    var info = mp && mp.info ? mp.info : mp;
    if (info && Number.isFinite(Number(info.queueRevision))) {
        return Number(info.queueRevision);
    }

    if (session && Number.isFinite(Number(session.stateRevision))) {
        return Number(session.stateRevision);
    }
    if (info && Number.isFinite(Number(info.stateRevision))) {
        return Number(info.stateRevision);
    }
    return 0;
}

function buildQueueMutationPayload(handle, extra) {
    var payload = extra || {};
    payload.handle = handle;
    payload.queueRevision = getQueueRevisionForHandle(handle);
    payload.expectedRevision = payload.queueRevision;
    return payload;
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

function isStaffUser() {
    return permissions && (permissions.manage === true || permissions.overrideDevice === true || permissions.staff === true);
}

function isAdminUser() {
    return permissions && permissions.manage === true;
}

function updateStaffVisibility() {
    var isStaff = isStaffUser();
    var isAdmin = isAdminUser();
    document.body.classList.toggle('is-staff', isStaff);
    document.body.classList.toggle('is-admin', isAdmin);
    if (!isAdmin && currentViewId === 'view-admin') {
        switchView('view-home');
    }
}



function getProfileOptionsHtml(selected) {
    var options = Array.isArray(deviceProfiles) ? deviceProfiles : [];
    if (!options.length) {
        return '<option value="">No profiles configured</option>';
    }
    return options.map(function(profile) {
        var key = profile && profile.key ? String(profile.key) : '';
        return '<option value="' + safeText(key) + '"' + (key === selected ? ' selected' : '') + '>' +
            safeText((profile && profile.label) || key) +
        '</option>';
    }).join('');
}

function normalizeAdminHandle(handle) {
    var numeric = Number(handle);
    return Number.isFinite(numeric) ? String(numeric) : null;
}

function getAdminDevices() {
    return adminState && Array.isArray(adminState.devices) ? adminState.devices : [];
}

function getAdminDeviceByHandle(handle) {
    var key = normalizeAdminHandle(handle);
    if (!key) return null;
    var devices = getAdminDevices();
    for (var i = 0; i < devices.length; i++) {
        if (normalizeAdminHandle(devices[i] && devices[i].handle) === key) {
            return devices[i];
        }
    }
    return null;
}

function getRequestModeLabel(mode) {
    if (mode === 'pending') return 'Pending approval';
    if (mode === 'disabled') return 'Disabled';
    return 'Direct queue';
}

function loadRadioFavorites() {
    try {
        var raw = window.localStorage && window.localStorage.getItem('pmms_radio_favorites:v1');
        radioFavorites = raw ? JSON.parse(raw) || {} : {};
    } catch (_) {
        radioFavorites = {};
    }
}

function saveRadioFavorites() {
    try {
        if (window.localStorage) {
            window.localStorage.setItem('pmms_radio_favorites:v1', JSON.stringify(radioFavorites || {}));
        }
    } catch (_) {}
}

function getRadioFavoriteKey(station) {
    return station && (station.stationId || station.id || station.url) ? String(station.stationId || station.id || station.url) : null;
}

loadRadioFavorites();

function timeToString(time) {
    if (!time || isNaN(time) || time <= 0) return '0:00';
    var t = Math.round(time);
    var h = Math.floor(t / 3600);
    var m = Math.floor((t % 3600) / 60);
    var s = t % 60;
    if (h > 0) return h + ':' + (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
    return m + ':' + (s < 10 ? '0' : '') + s;
}

function getDurationLabel(info) {
    var duration = Number(info && info.duration);
    if (Number.isFinite(duration) && duration > 0) {
        return timeToString(duration);
    }
    return info && info.live === true ? 'Live' : '--:--';
}

function getPlaybackTimeLabel(offset, info) {
    return timeToString(offset) + ' / ' + getDurationLabel(info);
}

function isDirectUrl(str) {
    return URL_PATTERN.test(str);
}

function isYoutubeLikeUrl(url) {
    return typeof url === 'string' && YOUTUBE_URL_PATTERN.test(url);
}

function normalizeDirectInputUrl(str) {
    var value = String(str || '').trim();
    if (/^www\./i.test(value)) {
        return 'https://' + value;
    }
    return value;
}

function getYoutubeProviderOption(value) {
    for (var i = 0; i < YOUTUBE_PROVIDER_OPTIONS.length; i++) {
        if (YOUTUBE_PROVIDER_OPTIONS[i].value === value) {
            return YOUTUBE_PROVIDER_OPTIONS[i];
        }
    }
    return YOUTUBE_PROVIDER_OPTIONS[0];
}

function getCurrentYoutubeProviderMode() {
    var selected = getYoutubeProviderOption(youtubeProviderMode);
    return selected ? selected.value : 'auto';
}

function shouldShowYoutubeProviderControl() {
    return showYoutubeProviderSelector === true && getCurrentSearchSource && getCurrentSearchSource() === 'youtube';
}

function positionYoutubeProviderMenu(menu, btn) {
    if (!menu || !btn) return;
    var rect = btn.getBoundingClientRect();
    menu.style.left = Math.max(12, Math.round(rect.left)) + 'px';
    menu.style.top = Math.round(rect.bottom + 8) + 'px';
}

function closeYoutubeProviderMenu() {
    var menu = document.getElementById('youtube-provider-menu');
    if (menu) menu.classList.remove('open');
}

function updateYoutubeProviderControl() {
    var btn = document.getElementById('youtube-provider-btn');
    if (!btn) return;

    var mode = getCurrentYoutubeProviderMode();
    var option = getYoutubeProviderOption(mode);
    var visible = shouldShowYoutubeProviderControl();
    btn.classList.toggle('visible', visible);
    btn.classList.remove('embed-selected');
    btn.textContent = option && option.label ? option.label : 'Auto';
    btn.title = 'Choose the YouTube resolver provider.';

    if (!visible) {
        closeYoutubeProviderMenu();
    }

    document.querySelectorAll('#youtube-provider-menu .youtube-provider-option').forEach(function(item) {
        item.classList.toggle('active', item.dataset.provider === mode);
    });
}

function ensureYoutubeProviderMenu() {
    var btn = document.getElementById('youtube-provider-btn');
    if (!btn) return;

    var menu = document.getElementById('youtube-provider-menu');
    if (!menu) {
        menu = document.createElement('div');
        menu.id = 'youtube-provider-menu';
        menu.className = 'youtube-provider-menu';
        menu.innerHTML = YOUTUBE_PROVIDER_OPTIONS.map(function(option) {
            return '<button type="button" class="youtube-provider-option' + (option.danger ? ' danger' : '') + '" data-provider="' + safeText(option.value) + '">' +
                '<span class="youtube-provider-option-title">' + safeText(option.label) + '</span>' +
                '<span class="youtube-provider-option-desc">' + safeText(option.description) + '</span>' +
            '</button>';
        }).join('');
        document.body.appendChild(menu);

        menu.querySelectorAll('.youtube-provider-option').forEach(function(item) {
            item.onclick = function(e) {
                e.stopPropagation();
                youtubeProviderMode = this.dataset.provider || 'auto';
                updateYoutubeProviderControl();
                closeYoutubeProviderMenu();
            };
        });
    }

    btn.onclick = function(e) {
        e.stopPropagation();
        ensureYoutubeProviderMenu();
        positionYoutubeProviderMenu(menu, btn);
        menu.classList.toggle('open');
        updateYoutubeProviderControl();
    };

    if (!btn.dataset.providerClickBound) {
        btn.dataset.providerClickBound = '1';
        document.addEventListener('click', function() {
            closeYoutubeProviderMenu();
        });
        window.addEventListener('resize', closeYoutubeProviderMenu);
    }

    updateYoutubeProviderControl();
}

function applyYoutubeProviderPreference(options) {
    var next = clonePlainObject(options || {});
    if (showYoutubeProviderSelector !== true) {
        return next;
    }
    if (!isYoutubeLikeUrl(next.url || '') || next.youtubeProvider || next.youtubeResolverProvider || next.resolverProvider) {
        return next;
    }

    var mode = getCurrentYoutubeProviderMode();
    var currentSource = getCurrentSearchSource && getCurrentSearchSource();

    if (currentSource === 'youtube_embed' || next.source === 'youtube_embed') {
        next.source = 'youtube';
        return next;
    }

    if (mode === 'auto') {
        return next;
    }

    if (currentSource !== 'youtube' && next.source !== 'youtube') {
        return next;
    }

    next.youtubeProvider = mode;
    next.youtubeProviderExplicit = true;
    next.resolverProvider = mode;
    return next;
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
    if (!_uiVisible && data && data.uiIsOpen === true) {
        return;
    }
    var nextSignature = getUiUpdateSignature(data);
    if (nextSignature && nextSignature === _lastUiUpdateSignature) {
        return;
    }
    if (nextSignature) {
        _lastUiUpdateSignature = nextSignature;
    }

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
    if (viewId === 'view-admin' && !isAdminUser()) {
        viewId = 'view-home';
    }
    var changed = currentViewId !== viewId;
    currentViewId = viewId;
    document.querySelectorAll('.nav-item').forEach(function(el) {
        el.classList.toggle('active', el.dataset.target === viewId);
    });
    document.querySelectorAll('.view').forEach(function(el) {
        var isActive = el.id === viewId;
        el.classList.toggle('active', isActive);
        if (isActive && changed) {
            el.classList.remove('view-motion-in');
            requestAnimationFrame(function() {
                requestAnimationFrame(function() {
                    el.classList.add('view-motion-in');
                    setTimeout(function() { el.classList.remove('view-motion-in'); }, 520);
                });
            });
        }
    });
    window.dispatchEvent(new CustomEvent('pmms:viewChanged', { detail: { viewId: viewId } }));
    if (viewId === 'view-library') {
        requestPlaylists(hasPendingFavoriteMutations());
        requestSharedPlaylists(false);
    } else if (viewId === 'view-social') {
        requestSocial(false);
    } else if (viewId === 'view-admin') {
        renderAdminPanel();
    }
}

function closeTransientUiSurfaces() {
    clearSearchResults();
    hidePlayerSuggestions();
    document.querySelectorAll('.modal-backdrop').forEach(function(modal) {
        modal.style.display = 'none';
    });
    var notifications = document.getElementById('notification-container');
    if (notifications) {
        notifications.innerHTML = '';
    }
}

function updateUi(data) {
    if (data.baseVolume !== undefined) {
        localBaseVolume = clampPercent(data.baseVolume, localBaseVolume);
    }
    if (data.showUi) {
        _lastUiUpdateSignature = '';
        setUiVisible(true);
        if (data.debug !== undefined) {
            debugConfig = data.debug || { enabled: false };
            debugLog('nui', 'debug config updated from showUi', debugConfig);
        }
        if (data.searchSources && Object.keys(data.searchSources).length) {
            searchSources = data.searchSources;
            defaultSearchSource = data.defaultSearchSource || defaultSearchSource || 'youtube';
            populateSearchSources(searchSources, defaultSearchSource);
        }
        if (data.permissions) {
            permissions = data.permissions;
            updateStaffVisibility();
        }
        if (Array.isArray(data.deviceProfiles)) {
            deviceProfiles = data.deviceProfiles;
        }
        if (Array.isArray(data.propModels)) {
            propModels = data.propModels;
        }
        if (Array.isArray(data.speakerModels)) {
            speakerModels = data.speakerModels;
        }
        if (data.adminQuickActions) {
            adminQuickActions = data.adminQuickActions || {};
        }
        if (data.requestConfig) {
            requestConfig = data.requestConfig || {};
        }
        if (data.speakerConfig) {
            speakerConfig = data.speakerConfig || {};
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
        if (typeof data.currentServerEndpoint === 'string') {
            currentServerEndpoint = data.currentServerEndpoint;
        }
        if (data.searchProxyThumbnails !== undefined) {
            searchProxyThumbnails = data.searchProxyThumbnails !== false;
        }
        if (data.showYoutubeProviderSelector !== undefined) {
            showYoutubeProviderSelector = data.showYoutubeProviderSelector === true;
        }
        if (data.deviceDefaults) {
            setGlobalDeviceDefaults(data.deviceDefaults);
        }
        if (data.selectedHandle != null) {
            activePlayerHandle = handleKey(data.selectedHandle);
            _lastActiveHandle = activePlayerHandle;
        } else {
            activePlayerHandle = null;
            _lastActiveHandle = null;
        }
        refreshSelectedDeviceTheme();
        if (data.openView) {
            switchView(data.openView);
        } else if (currentViewId === 'view-admin' && !data.selectedHandle) {
            switchView('view-home');
        }
        activateSearchBtn();
        if (libraryState.playlistsDirty || !libraryState.playlistsLoaded || hasPendingFavoriteMutations()) {
            requestPlaylists(hasPendingFavoriteMutations());
        }
        if (currentViewId === 'view-library' || currentViewId === 'view-playlist') {
            requestSharedPlaylists(false);
        }
        if (currentViewId === 'view-social') {
            requestSocial(false);
        }
        return;
    }
    if (data.hideUi) {
        setUiVisible(false);
        _lastUiUpdateSignature = '';
        _queuedUiData = null;
        _uiFrameScheduled = false;
        pendingControlState = {};
        activePlayerHandle = null;
        _lastActiveHandle = null;
        applySelectedDeviceTheme('none');
        _activeSearchRequestId = null;
        clearTimeout(_searchRetryTimer);
        _searchRetryTimer = null;
        clearTimeout(_playerSuggestionTimer);
        _playerSuggestionTimer = null;
        playerSuggestionState.visible = false;
        playerSuggestionState.suggestions = [];
        playerSuggestionState.pendingRequestId = null;
        closeTransientUiSurfaces();
        return;
    }

    if (data.permissions) {
        permissions = data.permissions;
        updateStaffVisibility();
    }
    if (data.admin !== undefined) {
        if (data.admin && data.admin.adminState !== undefined) {
            adminState = data.admin.adminState || null;
            if (Array.isArray(data.admin.propModels)) propModels = data.admin.propModels;
            if (Array.isArray(data.admin.speakerModels)) speakerModels = data.admin.speakerModels;
            if (Array.isArray(data.admin.deviceProfiles)) deviceProfiles = data.admin.deviceProfiles;
            if (Number.isFinite(Number(data.admin.adminMaxRange))) adminMaxRange = Number(data.admin.adminMaxRange);
        } else {
            adminState = data.admin || null;
        }
        renderAdminPanel();
        dispatchAdminUpdate();
    }
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
            var currentHandles = data.usableMediaPlayers.map(function(d) { return getDeviceRenderKey(d); });
            refreshSelectedDeviceTheme();
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
        dispatchAdminUpdate();
    }
}

function dispatchAdminUpdate() {
    var speakerModelList = Array.isArray(speakerModels) && speakerModels.length > 0
        ? speakerModels
        : (speakerConfig && Array.isArray(speakerConfig.models) && speakerConfig.models.length > 0)
        ? speakerConfig.models
        : propModels;
    window.dispatchEvent(new CustomEvent('pmms:adminUpdate', {
        detail: {
            adminState: adminState,
            deviceSessions: deviceSessions,
            usableMediaPlayers: usableMediaPlayers,
            deviceProfiles: deviceProfiles,
            propModels: propModels,
            speakerModels: speakerModelList,
            permissions: permissions,
            activePlayerHandle: activePlayerHandle,
            adminMaxRange: adminMaxRange || maxRange,
        }
    }));
}

function getPropImageSrc(model, index) {
    var exts = ['png', 'jpg', 'webp', 'svg'];
    if (index >= exts.length) return './assets/props/fallback.svg';
    return './assets/props/' + encodeURIComponent(model) + '.' + exts[index];
}

function showPropModelPicker(title, actionLabel, onPick, sourceModels) {
    var models = Array.isArray(sourceModels) ? sourceModels.slice() : (Array.isArray(propModels) ? propModels.slice() : []);
    if (!models.length) {
        showNotification('No placeable prop models are available.', title || 'Props', '#ff4444');
        return;
    }

    var existing = document.getElementById('prop-picker-modal');
    if (existing && existing.parentNode) existing.parentNode.removeChild(existing);

    var modal = document.createElement('div');
    modal.id = 'prop-picker-modal';
    modal.className = 'modal-backdrop';
    modal.style.display = 'flex';
    modal.innerHTML =
        '<div class="modal modal-wide prop-picker-modal">' +
            '<div class="modal-header">' +
                '<h3>' + safeText(title || 'Choose Prop') + '</h3>' +
                '<button class="btn-icon btn-sm" id="prop-picker-close">x</button>' +
            '</div>' +
            '<div class="modal-body">' +
                '<input type="text" id="prop-picker-search" placeholder="Filter props..." style="margin-bottom:12px;">' +
                '<div class="prop-picker-grid" id="prop-picker-grid"></div>' +
                '<div style="display:flex;justify-content:flex-end;gap:10px;margin-top:14px;">' +
                    '<button class="btn-outline" id="prop-picker-cancel">Cancel</button>' +
                '</div>' +
            '</div>' +
        '</div>';
    document.body.appendChild(modal);

    var grid = modal.querySelector('#prop-picker-grid');
    var search = modal.querySelector('#prop-picker-search');
    var close = function() {
        if (modal.parentNode) modal.parentNode.removeChild(modal);
    };

    var render = function() {
        var q = String(search && search.value || '').toLowerCase();
        var filtered = models.filter(function(model) {
            return !q || String(model.label || '').toLowerCase().indexOf(q) !== -1 || String(model.model || '').toLowerCase().indexOf(q) !== -1;
        });
        grid.innerHTML = filtered.map(function(model) {
            return '<button class="prop-picker-item" data-model="' + safeText(model.model) + '">' +
                '<img src="' + safeText(getPropImageSrc(model.model, 0)) + '" data-model="' + safeText(model.model) + '" data-img-index="0" alt="' + safeText(model.model) + '">' +
                '<span>' + safeText(model.label || model.model) + '</span>' +
                '<small>' + safeText(model.model) + '</small>' +
                '<b>' + safeText(actionLabel || 'Select') + '</b>' +
            '</button>';
        }).join('') || '<div class="admin-empty-small">No props match this filter.</div>';

        grid.querySelectorAll('img').forEach(function(img) {
            img.onerror = function() {
                var index = Number(img.getAttribute('data-img-index') || '0') + 1;
                img.setAttribute('data-img-index', String(index));
                img.src = getPropImageSrc(img.getAttribute('data-model') || '', index);
            };
        });

        grid.querySelectorAll('.prop-picker-item').forEach(function(button) {
            button.onclick = function() {
                var model = button.getAttribute('data-model');
                close();
                if (model && typeof onPick === 'function') onPick(model);
            };
        });
    };

    modal.querySelector('#prop-picker-close').onclick = close;
    modal.querySelector('#prop-picker-cancel').onclick = close;
    modal.onclick = function(event) {
        if (event.target === modal) close();
    };
    if (search) search.oninput = render;
    render();
    if (search) search.focus();
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

function _getNearbyDeviceRowLimit() {
    return 4;
}

function _splitNearbyDevices(devices) {
    var source = (devices || []).filter(function(device) {
        return device && device.handle != null;
    });
    var limit = _getNearbyDeviceRowLimit();
    if (source.length <= limit) {
        return { visible: source, hidden: [] };
    }

    var capacity = limit - 1;
    var visible = source.slice(0, capacity);
    var activeDevice = null;
    if (activePlayerHandle) {
        for (var i = 0; i < source.length; i++) {
            if (String(source[i].handle) === String(activePlayerHandle)) {
                activeDevice = source[i];
                break;
            }
        }
    }

    if (activeDevice) {
        var hasActive = visible.some(function(device) {
            return String(device.handle) === String(activeDevice.handle);
        });
        if (!hasActive) {
            visible[visible.length - 1] = activeDevice;
        }
    }

    var visibleMap = {};
    visible.forEach(function(device) {
        visibleMap[String(device.handle)] = true;
    });

    return {
        visible: visible,
        hidden: source.filter(function(device) {
            return !visibleMap[String(device.handle)];
        })
    };
}

function closeNearbyDevicesModal() {
    var modal = document.getElementById('nearby-devices-modal');
    if (modal) modal.style.display = 'none';
}

function ensureNearbyDevicesModal() {
    var modal = document.getElementById('nearby-devices-modal');
    if (modal) return modal;

    modal = document.createElement('div');
    modal.id = 'nearby-devices-modal';
    modal.className = 'modal-backdrop';
    modal.style.display = 'none';
    modal.innerHTML =
        '<div class="modal modal-wide nearby-devices-modal">' +
            '<div class="modal-header">' +
                '<h3>Nearby Devices</h3>' +
                '<button class="btn-icon btn-sm" id="nearby-devices-close" aria-label="Close nearby devices">' +
                    '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>' +
                '</button>' +
            '</div>' +
            '<div class="modal-body">' +
                '<div id="nearby-devices-modal-list" class="nearby-device-modal-list"></div>' +
            '</div>' +
        '</div>';

    var host = document.getElementById('app-container') || document.body;
    host.appendChild(modal);

    var closeBtn = document.getElementById('nearby-devices-close');
    if (closeBtn) closeBtn.onclick = closeNearbyDevicesModal;
    modal.onclick = function(event) {
        if (event.target === modal) {
            closeNearbyDevicesModal();
        }
    };

    return modal;
}

function populateNearbyDevicesModal(devices) {
    var modal = ensureNearbyDevicesModal();
    var list = modal.querySelector('#nearby-devices-modal-list');
    if (!list) return;

    list.innerHTML = '';
    devices.forEach(function(device) {
        if (!device || device.handle == null) return;
        var handle = device.handle.toString();
        var card = _buildDeviceCard(device, handle, activePlayerHandle === handle);
        if (!card) return;
        card.classList.add('device-modal-card');
        card.onclick = function() {
            selectDevice(handle, device);
            closeNearbyDevicesModal();
        };
        card.onkeydown = function(e) {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                selectDevice(handle, device);
                closeNearbyDevicesModal();
            }
        };
        list.appendChild(card);
    });
}

function openNearbyDevicesModal(devices) {
    var modal = ensureNearbyDevicesModal();
    populateNearbyDevicesModal(devices || usableMediaPlayers || []);
    modal.style.display = 'flex';
    applyStaticTooltips();
}

function _buildMoreDevicesCard(hiddenCount, devices) {
    var card = document.createElement('div');
    card.className = 'device-card device-more-card';
    card.setAttribute('role', 'button');
    card.setAttribute('tabindex', '0');
    card.onclick = function() { openNearbyDevicesModal(devices); };
    card.onkeydown = function(e) {
        if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            openNearbyDevicesModal(devices);
        }
    };
    card.innerHTML =
        '<div class="device-card-icon device-more-icon">' +
            '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/></svg>' +
        '</div>' +
        '<div class="device-card-body">' +
            '<div class="device-label">More devices</div>' +
            '<div class="device-dist">' + hiddenCount + ' hidden</div>' +
        '</div>' +
        '<div class="device-card-badges"><span class="badge badge-type">+' + hiddenCount + '</span></div>';
    return card;
}

function renderDevicesGrid(devices) {
    var grid  = document.getElementById('devices-grid');
    if (!grid) return;

    if (!devices || devices.length === 0) {
        grid.innerHTML = '<div class="empty-state"><svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="4" y="2" width="16" height="20" rx="2"/><circle cx="12" cy="14" r="4"/><line x1="12" y1="6" x2="12.01" y2="6"/></svg><p>No media players nearby</p></div>';
        _updateDevicesCount(devices);
        return;
    }

    var split = _splitNearbyDevices(devices);
    grid.innerHTML = '';
    _updateDevicesCount(devices);
    split.visible.forEach(function(device) {
        if (!device || device.handle == null) return;
        var handle = device.handle.toString();
        var isActive = activePlayerHandle === handle;
        var newCard = _buildDeviceCard(device, handle, isActive);
        if (newCard) grid.appendChild(newCard);
    });
    if (split.hidden.length > 0) {
        grid.appendChild(_buildMoreDevicesCard(split.hidden.length, devices));
    }
    applyStaticTooltips();
}

function updateDevicesGridInPlace(devices) {
    var grid = document.getElementById('devices-grid');
    if (!grid) return;

    var split = _splitNearbyDevices(devices || []);
    var cardsByKey = {};
    grid.querySelectorAll('.device-card[data-device-key]').forEach(function(card) {
        cardsByKey[card.dataset.deviceKey] = card;
    });

    var missingCard = false;
    split.visible.forEach(function(device) {
        var key = getDeviceRenderKey(device);
        var card = key ? cardsByKey[key] : null;
        if (!card) {
            missingCard = true;
            return;
        }
        updateDeviceCard(card, device, activePlayerHandle === handleKey(device.handle));
    });

    if (missingCard) {
        renderDevicesGrid(devices);
        return;
    }

    var moreCard = grid.querySelector('.device-more-card');
    if (split.hidden.length > 0) {
        if (!moreCard) {
            renderDevicesGrid(devices);
            return;
        }
        var hiddenLabel = moreCard.querySelector('.device-dist');
        var hiddenBadge = moreCard.querySelector('.badge-type');
        if (hiddenLabel) hiddenLabel.textContent = split.hidden.length + ' hidden';
        if (hiddenBadge) hiddenBadge.textContent = '+' + split.hidden.length;
        moreCard.onclick = function() { openNearbyDevicesModal(devices); };
    } else if (moreCard) {
        renderDevicesGrid(devices);
        return;
    }

    _updateDevicesCount(devices);
    applyStaticTooltips();
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

    var split = _splitNearbyDevices(devices);
    var visibleSlots = split.visible.length + (split.hidden.length > 0 ? 1 : 0);
    var countLabel = visibleSlots + ' visible';
    if (split.hidden.length > 0) {
        countLabel += ' | ' + split.hidden.length + ' hidden';
    }

    count.textContent = countLabel
        + (playing > 0 ? ' | ' + playing + ' playing' : '')
        + (starting > 0 ? ' | ' + starting + ' starting' : '');
}

function _buildDeviceCard(device, handle, isActive) {
    var card = document.createElement('div');
    var theme = getDeviceThemeFromDevice(device, handle);
    card.className = 'device-card device-theme-' + theme + (isActive ? ' active' : '');
    card.dataset.handle = handle;
    card.dataset.deviceKey = getDeviceRenderKey(device);
    card.dataset.deviceType = device.type || '';
    card.dataset.deviceTheme = theme;
    card.setAttribute('role', 'button');
    card.setAttribute('tabindex', '0');
    card.onclick = function() { selectDevice(handle, device); };
    card.onkeydown = function(e) { if (e.key === 'Enter' || e.key === ' ') selectDevice(handle, device); };

    var deviceIcon = _getDeviceIcon(device, handle);
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

function updateDeviceCard(card, device, isActive) {
    if (!card || !device) return;
    var handle = handleKey(device.handle);
    var theme = getDeviceThemeFromDevice(device, handle);
    card.dataset.handle = handle;
    card.dataset.deviceKey = getDeviceRenderKey(device);
    card.classList.toggle('active', !!isActive);
    ['vehicle', 'screen', 'speaker', 'interaction'].forEach(function(name) {
        card.classList.toggle('device-theme-' + name, theme === name);
    });
    card.onclick = function() { selectDevice(handle, device); };
    card.onkeydown = function(e) { if (e.key === 'Enter' || e.key === ' ') selectDevice(handle, device); };

    if (card.dataset.deviceType !== (device.type || '') || card.dataset.deviceTheme !== theme) {
        var icon = card.querySelector('.device-card-icon');
        if (icon) icon.innerHTML = _getDeviceIcon(device, handle);
        card.dataset.deviceType = device.type || '';
        card.dataset.deviceTheme = theme;
    }

    var label = card.querySelector('.device-label');
    if (label) label.textContent = _deviceLabel(device);
    var dist = card.querySelector('.device-dist');
    if (dist) dist.textContent = _formatDist(device.distance);
    var badges = card.querySelector('.device-card-badges');
    if (badges) badges.innerHTML = _buildDeviceCardBadges(device, handle);
}

function selectDevice(handle, device) {
    activePlayerHandle = handleKey(handle);
    _lastActiveHandle  = activePlayerHandle;
    var theme = device ? getDeviceThemeFromDevice(device, activePlayerHandle) : getDeviceThemeForHandle(activePlayerHandle);
    applySelectedDeviceTheme(theme);
    document.querySelectorAll('.device-card').forEach(function(c) {
        c.classList.toggle('active', c.dataset.handle === handleKey(handle));
    });
    updateBottomPlayer();
    updateNowPlayingPanel();
    dispatchAdminUpdate();
    sendMessage('selectDevice', { handle: activePlayerHandle, deviceType: theme });
    window.dispatchEvent(new CustomEvent('pmms:adminSelectHandle', {
        detail: { handle: activePlayerHandle }
    }));
}

function _deviceLabel(device) {
    return getDeviceLabelByHandle(device && device.handle);
}

function _formatDist(d) {
    return d >= 0 ? Math.round(d) + 'm away' : 'Nearby';
}

function _getDeviceIcon(device, handle) {
    var theme = getDeviceThemeFromDevice(device, handle);
    if (theme === 'vehicle') return _iconCar();
    if (theme === 'screen') return _iconScreen();
    if (theme === 'interaction') return _iconInteraction();
    return _iconSpeaker();
}

function _iconSpeaker() { return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="4" y="2" width="16" height="20" rx="2"/><circle cx="12" cy="14" r="4"/><line x1="12" y1="6" x2="12.01" y2="6"/></svg>'; }
function _iconCar()     { return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 17H3a2 2 0 01-2-2V9a2 2 0 012-2h18a2 2 0 012 2v6a2 2 0 01-2 2h-2M5 17h14M5 17l-1 4m14-4l1 4"/><rect x="5" y="7" width="14" height="6" rx="1"/></svg>'; }
function _iconScreen()  { return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8"/><path d="M12 17v4"/></svg>'; }
function _iconInteraction() { return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 8v5"/><path d="M12 16h.01"/></svg>'; }
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

function getPlayPauseMotionHtml() {
    return '<span class="play-pause-motion" aria-hidden="true">' +
        '<span class="play-pause-ring"></span>' +
        '<span class="play-pause-spark play-pause-spark-a"></span>' +
        '<span class="play-pause-spark play-pause-spark-b"></span>' +
        '<span class="play-pause-spark play-pause-spark-c"></span>' +
        '<svg class="play-pause-shape play-pause-play" width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><polygon points="6 4 19 12 6 20"/></svg>' +
        '<svg class="play-pause-shape play-pause-pause" width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/></svg>' +
    '</span>';
}

function animatePlayPauseButton(button, nextState) {
    if (!button || typeof button.animate !== 'function') return;
    if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

    var ring = button.querySelector('.play-pause-ring');
    if (ring && typeof ring.animate === 'function') {
        ring.animate([
            { opacity: 0.55, transform: 'scale(0.45)' },
            { opacity: 0.18, transform: 'scale(1.24)' },
            { opacity: 0, transform: 'scale(1.48)' }
        ], {
            duration: 420,
            easing: 'cubic-bezier(0.16, 1, 0.3, 1)'
        });
    }

    button.animate([
        { transform: 'scale(0.94)' },
        { transform: 'scale(1.1)' },
        { transform: 'scale(1)' }
    ], {
        duration: 360,
        easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)'
    });

    var entering = button.querySelector(nextState === 'playing' ? '.play-pause-pause' : '.play-pause-play');
    if (entering && typeof entering.animate === 'function') {
        entering.animate([
            { filter: 'blur(2px)', transform: 'scale(0.68) rotate(-14deg)' },
            { filter: 'blur(0)', transform: 'scale(1.14) rotate(4deg)' },
            { filter: 'blur(0)', transform: 'scale(1) rotate(0deg)' }
        ], {
            duration: 380,
            easing: 'cubic-bezier(0.16, 1, 0.3, 1)'
        });
    }

    button.querySelectorAll('.play-pause-spark').forEach(function(spark, index) {
        if (typeof spark.animate !== 'function') return;
        var x = index === 0 ? -12 : (index === 1 ? 2 : 12);
        var y = index === 1 ? -14 : 10;
        spark.animate([
            { opacity: 0.75, transform: 'translate(-50%, -50%) scale(0.35)' },
            { opacity: 0, transform: 'translate(calc(-50% + ' + x + 'px), calc(-50% + ' + y + 'px)) scale(1)' }
        ], {
            duration: 360,
            easing: 'cubic-bezier(0.16, 1, 0.3, 1)'
        });
    });
}

function setPlayPauseButtonState(button, state) {
    if (!button) return;
    if (button.dataset.motionReady !== '1') {
        button.innerHTML = getPlayPauseMotionHtml();
        button.dataset.motionReady = '1';
    }
    var previous = button.dataset.state;
    button.dataset.state = state;
    if (previous && previous !== state) {
        animatePlayPauseButton(button, state);
    }
}

function getVolumeIconHtml(state) {
    var waves = '';
    if (state === 'low') {
        waves = '<path class="volume-wave volume-wave-1" d="M15 10a3 3 0 0 1 0 4"/>';
    } else if (state === 'medium') {
        waves = '<path class="volume-wave volume-wave-1" d="M15 9a4 4 0 0 1 0 6"/><path class="volume-wave volume-wave-2" d="M18 7a7 7 0 0 1 0 10"/>';
    } else if (state === 'high') {
        waves = '<path class="volume-wave volume-wave-1" d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path class="volume-wave volume-wave-2" d="M19.07 4.93a10 10 0 0 1 0 14.14"/>';
    } else {
        waves = '<line class="volume-muted-line" x1="18" y1="9" x2="22" y2="15"/><line class="volume-muted-line" x1="22" y1="9" x2="18" y2="15"/>';
    }

    return '<span class="volume-motion" aria-hidden="true">' +
        '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
            '<polygon class="volume-body" points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/>' +
            waves +
        '</svg>' +
    '</span>';
}

function setVolumeButtonState(button, value, muted) {
    if (!button) return;
    var volume = clampPercent(value, localBaseVolume);
    var state = (muted || volume <= 0)
        ? 'muted'
        : (volume < 34 ? 'low' : (volume < 67 ? 'medium' : 'high'));

    if (button.dataset.volumeState !== state) {
        button.innerHTML = getVolumeIconHtml(state);
        button.dataset.volumeState = state;
    }
    button.dataset.state = state === 'muted' ? 'muted' : 'unmuted';
    button.classList.toggle('active', state === 'muted');
}

function updateVolumeAffordance(value, muted) {
    setVolumeButtonState(document.getElementById('np-mute'), value, muted);
}

function _h() { return activePlayerHandle ? parseInt(activePlayerHandle, 10) : null; }

function requestPlaybackOnHandle(handle, options) {
    var numericHandle = Number(handle);
    if (!Number.isFinite(numericHandle)) {
        return;
    }

    options = applyYoutubeProviderPreference(options || {});

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
    var now = Date.now();
    if (!force && (now - _lastVolumeSendAt) < _volumeThrottleMs) return;
    _lastVolumeSendAt = now;
    localBaseVolume = clampPercent(value, localBaseVolume);
    sendMessage('setBaseVolume', { volume: localBaseVolume });
}

function updateSeekPreviewLabels(value, duration) {
    var cur = document.getElementById('np-time-current');
    var tot = document.getElementById('np-time-total');
    if (cur) cur.textContent = timeToString(value);
    if (tot) {
        tot.textContent = (duration && duration > 0) ? timeToString(duration) : '--:--';
    }
}

function initPlayerControls() {
    var progress = document.getElementById('np-progress');
    var volume   = document.getElementById('np-volume');

    if (progress) {
        var beginSeek = function() {
            if (progress.disabled) return;
            _isScrubbing = true;
            progress.classList.add('is-scrubbing');
            _seekDragValue = parseFloat(progress.value) || 0;
        };

        var commitSeek = function() {
            if (!_isScrubbing) return;
            var value = parseFloat(progress.value) || 0;
            sendSeekUpdate(value, true);
            _isScrubbing = false;
            progress.classList.remove('is-scrubbing');
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
            volume.classList.add('is-scrubbing');
            _volumeDragValue = parseInt(volume.value, 10) || 0;
        };

        var commitVolume = function() {
            if (!_isAdjustingVolume) return;
            var value = parseInt(volume.value, 10) || 0;
            sendVolumeUpdate(value, true);
            _isAdjustingVolume = false;
            volume.classList.remove('is-scrubbing');
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
            updateVolumeAffordance(v, v <= 0);
            sendVolumeUpdate(v, false);
        });

        volume.addEventListener('change', commitVolume);
        volume.addEventListener('mouseup', commitVolume);
        volume.addEventListener('touchend', commitVolume);
        volume.addEventListener('blur', commitVolume);
    }
}

function _updateBottomPlayerLive(progress, vol, volVal, timeCur, timeTot, hasInfo, hasDuration, canSeek, canControl, duration, offset, currentVol, isLiveStream, isMuted) {
    if (vol) {
        vol.disabled = false;
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
        updateVolumeAffordance(volForLabel, isMuted || volForLabel <= 0);
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
            if (timeTot) timeTot.textContent = hasInfo ? (isLiveStream ? 'Live' : '--:--') : '0:00';
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
    var isLiveStream = hasInfo && info.live === true;
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
    var currentVol = clampPercent(localBaseVolume, 100);
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
        localBaseVolume,
        hasDuration ? duration : (isLiveStream ? 'live' : 'unknown-duration'),
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
            _updateBottomPlayerLive(progress, vol, volVal, timeCur, timeTot, hasInfo, hasDuration, canSeek, canControl, duration, offset, currentVol, isLiveStream, isMuted);
        } else {
            if (progress) {
                progress.disabled = true;
                progress.max = 100;
                progress.value = 0;
                _updateProgressFill(progress);
            }
            if (vol) {
                vol.disabled = false;
                vol.value = localBaseVolume;
                _updateProgressFill(vol);
            }
            if (volVal) volVal.textContent = localBaseVolume + '%';
            updateVolumeAffordance(localBaseVolume, localBaseVolume <= 0);
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
            setPlayPauseButtonState(playBtn, playState);
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
            sendMessage('previous', buildQueueMutationPayload(_h()));
        };
    }

    if (nextBtn) {
        nextBtn.disabled = !canControl;
        nextBtn.setAttribute('data-tooltip', 'Next track');
        nextBtn.setAttribute('aria-label', 'Next track');
        nextBtn.onclick  = function() { sendMessage('next', buildQueueMutationPayload(_h())); };
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
        setVolumeButtonState(muteBtn, currentVol, isMuted);
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
        _updateBottomPlayerLive(progress, vol, volVal, timeCur, timeTot, hasInfo, hasDuration, canSeek, canControl, duration, offset, currentVol, isLiveStream, isMuted);
        return;
    }

    if (progress) {
        progress.disabled = true;
        progress.max = 100;
        progress.value = 0;
        _updateProgressFill(progress);
    }
    if (vol) {
        vol.disabled = false;
        vol.value = localBaseVolume;
        _updateProgressFill(vol);
    }
    if (volVal) volVal.textContent = localBaseVolume + '%';
    updateVolumeAffordance(localBaseVolume, localBaseVolume <= 0);
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
    if (vol)      { vol.disabled = true; vol.value = localBaseVolume; _updateProgressFill(vol); }
    var volVal = document.getElementById('np-volume-val');
    if (volVal) volVal.textContent = localBaseVolume + '%';
    if (timeCur)  timeCur.textContent = '0:00';
    if (timeTot)  timeTot.textContent = '0:00';
    setPlayPauseButtonState(playBtn, 'paused');
    if (loopBtn) {
        loopBtn.dataset.mode = 'off';
        loopBtn.innerHTML = getLoopIcon('off');
    }
    setVolumeButtonState(muteBtn, localBaseVolume, false);
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
    return list.map(function(entry, index) {
        var sourceIndex = newestFirst ? (list.length - 1 - index) : index;
        if (entry && entry.options) {
            return {
                source: entry.source,
                name: entry.name,
                options: entry.options,
                queueId: entry.queueId,
                _sourceIndex: sourceIndex
            };
        }
        return { options: entry, _sourceIndex: sourceIndex };
    });
}

function getTrackEntriesSignature(entries) {
    var wrapped = wrapTrackEntries(entries, false);
    return getQueueSignature(wrapped, false);
}

function getRenderedHistorySignature(entries) {
    var wrapped = wrapTrackEntries(entries, true).slice(0, MAX_RENDERED_HISTORY_ITEMS);
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
        html += '<div class="np-queue-list" data-list-key="manual-queue">';
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

function getReadOnlyTrackListHtml(title, entries, emptyText, subtitleText, newestFirst, actions) {
    var wrapped = wrapTrackEntries(entries, newestFirst);
    actions = actions || {};
    var totalCount = Number.isFinite(Number(actions.totalCount)) ? Math.max(0, Number(actions.totalCount)) : wrapped.length;
    var limit = Number(actions.limit) || 0;
    if (limit > 0 && wrapped.length > limit) {
        wrapped = wrapped.slice(0, limit);
        subtitleText = actions.limitText || ('Showing newest ' + limit + ' of ' + totalCount + '.');
    } else if (limit > 0 && totalCount > wrapped.length) {
        subtitleText = actions.limitText || ('Showing newest ' + wrapped.length + ' of ' + totalCount + '.');
    }
    var listKey = String(title || 'list').toLowerCase().replace(/[^a-z0-9]+/g, '-');
    var html =
        '<div class="np-queue-section">' +
            '<div class="np-queue-header">' +
                '<span class="np-queue-title">' + safeText(title) + '</span>' +
                '<span class="np-queue-count">' + (totalCount !== wrapped.length ? (wrapped.length + '/' + totalCount) : wrapped.length) + '</span>' +
            '</div>';

    if (subtitleText) {
        html += '<div class="np-queue-next">' + safeText(subtitleText) + '</div>';
    }

    if (wrapped.length === 0) {
        html += '<div class="np-queue-empty">' + safeText(emptyText) + '</div>';
    } else {
        html += '<div class="np-queue-list" data-list-key="' + safeText(listKey) + '">';
        wrapped.forEach(function(entry, index) {
            html +=
                '<div class="np-queue-item np-queue-item-readonly">' +
                    '<div class="np-queue-item-left">' +
                        '<span class="np-queue-index">' + (index + 1) + '</span>' +
                        '<div class="np-queue-item-meta">' +
                            '<div class="np-queue-item-title">' + safeText(getQueueItemTitle(entry, index)) + '</div>' +
                            '<div class="np-queue-item-sub">' + safeText(getQueueItemSubtitle(entry)) + '</div>' +
                        '</div>' +
                    '</div>';
            if (actions.addToPlaylist || actions.replayQueue) {
                html += '<div class="np-queue-actions">';
                if (actions.addToPlaylist) {
                    html +=
                        '<button class="btn-icon btn-sm np-history-add" data-history-add-index="' + entry._sourceIndex + '" data-tooltip="Add to playlist" aria-label="Add history item to playlist">' +
                            '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>' +
                        '</button>';
                }
                if (actions.replayQueue) {
                    html +=
                        '<button class="btn-icon btn-sm np-history-replay" data-history-replay-index="' + entry._sourceIndex + '" data-tooltip="Replay / queue again" aria-label="Replay history item">' +
                            '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/></svg>' +
                        '</button>';
                }
                html += '</div>';
            }
            html +=
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
        true,
        {
            addToPlaylist: true,
            replayQueue: true,
            limit: MAX_RENDERED_HISTORY_ITEMS,
            totalCount: Number.isFinite(Number(effectiveSession.historyCount)) ? Number(effectiveSession.historyCount) : history.length,
            limitText: 'Showing newest ' + MAX_RENDERED_HISTORY_ITEMS + ' history items. Older plays remain in device history.'
        }
    );
}

function removeQueueItemLocally(handle, index) {
    var key = handleKey(handle);
    if (!key || !mediaPlayerStates[key] || !mediaPlayerStates[key].info) return;
    var queue = mediaPlayerStates[key].info.queue;
    if (!Array.isArray(queue)) return;
    queue.splice(index - 1, 1);
}

function getHistoryTrackByIndex(index) {
    var session = getEffectiveDeviceSession(activePlayerHandle);
    var history = session && Array.isArray(session.history) ? session.history : [];
    if (!Number.isFinite(index) || index < 0 || index >= history.length) {
        return null;
    }
    return history[index];
}

function getTrackOptions(entry) {
    return entry && entry.options ? entry.options : entry;
}

function buildPlaybackOptionsFromTrack(track) {
    var options = getTrackOptions(track);
    if (!options || !options.url) {
        return null;
    }
    return {
        url: options.originalUrl || options.url,
        title: options.title || options.url,
        duration: options.duration,
        author: options.author,
        thumbnail: options.thumbnail,
        video: options.video !== false,
        audioTrack: cloneValue(options.audioTrack || options.selectedAudioTrack),
        selectedAudioTrack: cloneValue(options.selectedAudioTrack || options.audioTrack)
    };
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
            sendMessage('previous', buildQueueMutationPayload(_h()));
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
            sendMessage('removeFromQueue', buildQueueMutationPayload(_h(), { index: index }));
        };
    });

    panel.querySelectorAll('[data-history-add-index]').forEach(function(btn) {
        btn.onclick = function() {
            var index = parseInt(this.dataset.historyAddIndex, 10);
            var options = buildPlaybackOptionsFromTrack(getHistoryTrackByIndex(index));
            if (!options || !options.url) return;
            openAddToPlaylistModal(options);
        };
    });

    panel.querySelectorAll('[data-history-replay-index]').forEach(function(btn) {
        btn.onclick = function() {
            if (!activePlayerHandle) return;
            var index = parseInt(this.dataset.historyReplayIndex, 10);
            var options = buildPlaybackOptionsFromTrack(getHistoryTrackByIndex(index));
            if (!options || !options.url) return;
            requestPlaybackOnHandle(_h(), options);
            showNotification('Added back to the queue.', 'History');
        };
    });

    var audioTrackSelect = panel.querySelector('#np-audio-track');
    if (audioTrackSelect) {
        audioTrackSelect.onchange = function() {
            if (!activePlayerHandle) return;
            var mp = getCurrentLiveMP();
            var info = mp && mp.info ? mp.info : null;
            var tracks = getAudioTracks(info);
            var index = parseInt(audioTrackSelect.value, 10);
            if (!Number.isFinite(index) || index < 0 || index >= tracks.length) return;

            var selectedTrack = cloneValue(tracks[index]);
            if (info) {
                info.audioTracks = tracks.map(function(track, trackIndex) {
                    var copy = cloneValue(track);
                    copy.selected = trackIndex === index;
                    return copy;
                });
                info.audioTrack = selectedTrack;
                info.selectedAudioTrack = selectedTrack;
            }
            sendMessage('setAudioTrack', { handle: _h(), audioTrack: selectedTrack });
        };
    }
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
    var historySignature = getRenderedHistorySignature(session && session.history ? session.history : []);
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
        + (info.live === true ? 'live' : 'vod') + '|'
        + getAudioTrackSignature(info) + '|'
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

    var text = getPlaybackTimeLabel(offset, info);
    var timeEl = panel.querySelector('#np-meta-time');
    if (timeEl && timeEl.textContent !== text) {
        timeEl.textContent = text;
    }
}

function capturePanelScrollPositions(panel) {
    var positions = {};
    if (!panel) return positions;
    panel.querySelectorAll('.np-queue-list').forEach(function(list, index) {
        var key = list.dataset.listKey || String(index);
        positions[key] = list.scrollTop || 0;
    });
    return positions;
}

function restorePanelScrollPositions(panel, positions) {
    if (!panel || !positions) return;
    panel.querySelectorAll('.np-queue-list').forEach(function(list, index) {
        var key = list.dataset.listKey || String(index);
        if (positions[key] != null) {
            list.scrollTop = positions[key];
        }
    });
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
    var panelScrollPositions = capturePanelScrollPositions(panel);

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
        restorePanelScrollPositions(panel, panelScrollPositions);
        applyStaticTooltips();
        return;
    }

    var info = liveMp.info;
    var offset = liveMp.offset || 0;
    var thumbnailCandidates = getMediaThumbnailCandidates(info);
    var statusHtml = hasLocalFailure
        ? '<div class="np-panel-actions" style="margin-top:12px;align-items:flex-start;flex-direction:column;gap:8px;color:var(--red);"><span>' + safeText(localFailure.message || 'Playback failed on this client.') + '</span></div>'
        : '';
    var thumbHtml = thumbnailCandidates.length
        ? '<div class="np-thumb" data-thumb="1"><img class="np-thumb-img" alt="" loading="lazy"></div>'
        : '<div class="np-thumb np-thumb-empty"><svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg></div>';
    var canControlNowPlaying = canControlMediaPlayer(liveMp);
    var audioTrackControlHtml = getAudioTrackControlHtml(info, canControlNowPlaying);

    panel.innerHTML =
        '<div class="np-panel-inner">' +
            thumbHtml +
            '<div class="np-meta">' +
                '<div class="np-meta-title" title="' + safeText(info.title) + '">' + safeText(info.title || 'Untitled') + '</div>' +
                '<div class="np-meta-author">' + safeText(info.author || '') + '</div>' +
                '<div class="np-meta-time" id="np-meta-time">' + getPlaybackTimeLabel(offset, info) + '</div>' +
                (info.url ? '<div class="np-meta-url" title="' + safeText(info.url) + '">' + safeText(_truncateUrl(info.url)) + '</div>' : '') +
                audioTrackControlHtml +
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
    bindMediaThumbnailFallback(panel.querySelector('.np-thumb[data-thumb="1"]'), thumbnailCandidates);
    restorePanelScrollPositions(panel, panelScrollPositions);
    updateNowPlayingPanelTimeOnly(panel, liveMp);
    applyStaticTooltips();
}

function _truncateUrl(url) {
    if (!url) return '';
    if (url.length <= 50) return url;
    return url.substring(0, 47) + '...';
}

function getAudioTracks(info) {
    if (!info || !Array.isArray(info.audioTracks)) return [];
    return info.audioTracks.map(function(track, index) {
        var copy = cloneValue(track || {});
        copy.index = Number.isFinite(Number(copy.index)) ? Number(copy.index) : index;
        copy.id = copy.id !== undefined && copy.id !== null ? String(copy.id) : String(copy.index);
        copy.label = copy.label || copy.name || copy.language || ('Track ' + (index + 1));
        return copy;
    });
}

function getSelectedAudioTrackIndex(info) {
    var tracks = getAudioTracks(info);
    if (!tracks.length) return -1;
    var selected = info && (info.audioTrack || info.selectedAudioTrack);

    if (selected && Number.isFinite(Number(selected.index))) {
        var index = Number(selected.index);
        if (index >= 0 && index < tracks.length) return index;
    }
    if (selected && selected.id !== undefined && selected.id !== null) {
        var id = String(selected.id);
        for (var byId = 0; byId < tracks.length; byId++) {
            if (String(tracks[byId].id) === id) return byId;
        }
    }
    for (var bySelected = 0; bySelected < tracks.length; bySelected++) {
        if (tracks[bySelected].selected === true) return bySelected;
    }
    return 0;
}

function getAudioTrackSignature(info) {
    var tracks = getAudioTracks(info);
    if (!tracks.length) return '';
    return getSelectedAudioTrackIndex(info) + ':' + tracks.map(function(track) {
        return [track.index, track.id, track.label, track.language].join(',');
    }).join('|');
}

function getAudioTrackDisplayName(track, index) {
    track = track || {};
    var label = track.label || track.name || ('Track ' + (index + 1));
    var language = track.language || track.lang || '';
    if (language && String(label).toLowerCase().indexOf(String(language).toLowerCase()) === -1) {
        return label + ' (' + language + ')';
    }
    return label;
}

function getAudioTrackControlHtml(info, canControl) {
    var tracks = getAudioTracks(info);
    if (tracks.length === 1) {
        var onlyTrack = tracks[0] || {};
        if (!onlyTrack.language && !onlyTrack.label && !onlyTrack.name) return '';
        return '<span class="np-audio-track-badge" title="Current audio track">' +
            '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9v6h4l5 4V5L8 9H4Zm13.5-1.5-1.4 1.4A4.2 4.2 0 0 1 17.3 12c0 1.2-.4 2.3-1.2 3.1l1.4 1.4A6.1 6.1 0 0 0 19.3 12c0-1.8-.7-3.4-1.8-4.5Z"/></svg>' +
            safeText(getAudioTrackDisplayName(onlyTrack, 0)) +
        '</span>';
    }
    if (tracks.length <= 1) return '';
    var selectedIndex = getSelectedAudioTrackIndex(info);
    var options = tracks.map(function(track, index) {
        return '<option value="' + safeText(String(index)) + '"' + (index === selectedIndex ? ' selected' : '') + '>' +
            safeText(getAudioTrackDisplayName(track, index)) +
        '</option>';
    }).join('');

    return '<label class="np-audio-track-control">' +
        '<span class="np-audio-track-label"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9v6h4l5 4V5L8 9H4Zm13.5-1.5-1.4 1.4A4.2 4.2 0 0 1 17.3 12c0 1.2-.4 2.3-1.2 3.1l1.4 1.4A6.1 6.1 0 0 0 19.3 12c0-1.8-.7-3.4-1.8-4.5Z"/></svg>Audio</span>' +
        '<select id="np-audio-track" ' + (canControl ? '' : 'disabled') + '>' + options + '</select>' +
    '</label>';
}


'use strict';

var _searchDebounceTimer = null;
var _searchDebounceMs = 320;
var _searchRequestSeq = 0;
var _activeSearchRequestId = null;

function getSearchSourceConfig(source) {
    var key = source || defaultSearchSource || 'youtube';
    return searchSources && searchSources[key] ? searchSources[key] : (searchSources.youtube || {});
}

function getCurrentSearchSource() {
    var select = document.getElementById('search-source');
    return select && select.value ? select.value : (defaultSearchSource || 'youtube');
}

function updateSearchPlaceholder() {
    var input = document.getElementById('search-input');
    var btn = document.getElementById('search-btn');
    var source = getCurrentSearchSource();
    var config = getSearchSourceConfig(source);

    if (input) {
        input.placeholder = config.placeholder || 'Search or paste a URL...';
    }
    if (btn) {
        btn.textContent = source === 'direct' ? 'Play' : 'Search';
    }
    updateYoutubeProviderControl();
}

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
            updateSearchPlaceholder();
            updateYoutubeProviderControl();
            clearSearchResults();
            if (getCurrentSearchSource() === 'radio' && (!input.value || !input.value.trim())) {
                renderRadioFavoriteResults();
                return;
            }
            if (!input.value || !input.value.trim()) return;
            if (getCurrentSearchSource() === 'direct') return;
            performSearch(true);
        });
    }

    input.addEventListener('input', function() {
        if (!input.value || !input.value.trim()) {
            _activeSearchRequestId = null;
            clearTimeout(_searchDebounceTimer);
            clearSearchResults();
            _setSearchState('idle');
            if (getCurrentSearchSource() === 'radio') {
                renderRadioFavoriteResults();
            }
            return;
        }

        if (getCurrentSearchSource() === 'direct') {
            clearTimeout(_searchDebounceTimer);
            _setSearchState('idle');
            return;
        }

        clearTimeout(_searchDebounceTimer);
        _searchDebounceTimer = setTimeout(function() {
            performSearch(false);
        }, _searchDebounceMs);
    });

    updateSearchPlaceholder();
    ensureYoutubeProviderMenu();
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
    updateSearchPlaceholder();
    ensureYoutubeProviderMenu();
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

    if (source === 'direct' && !isDirectUrl(q)) {
        clearSearchResults();
        var err = document.getElementById('search-status');
        if (err) {
            err.textContent = 'Paste a direct http(s) media URL.';
            err.className = 'search-status muted';
            err.style.display = 'block';
        }
        return;
    }

    if (isDirectUrl(q)) {
        if (!activePlayerHandle) {
            showNotification('Please select a nearby device first!', 'Play', '#ff4444');
            return;
        }
        requestPlaybackOnHandle(_h(), {
            url: normalizeDirectInputUrl(q),
            label: getCurrentDeviceLabel(),
            video: source === 'radio' ? false : true,
            source: source,
            live: source === 'radio',
            radio: source === 'radio'
        });
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

function renderRadioFavoriteResults() {
    var favorites = Object.keys(radioFavorites || {}).map(function(key) {
        var station = cloneValue(radioFavorites[key] || {});
        station.stationId = station.stationId || key;
        station.source = 'radio';
        station.radio = true;
        station.live = true;
        return station;
    });
    if (!favorites.length) return;
    renderSearchResults(favorites, null);
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
            var resultSource = res.source || getCurrentSearchSource();
            var isRadioResult = resultSource === 'radio' || res.radio === true;
            var favoriteKey = isRadioResult ? getRadioFavoriteKey(res) : null;
            var isRadioFavorite = favoriteKey && radioFavorites[favoriteKey];

            var thumbCandidates = getSearchThumbnailCandidates(res);
            var thumbSrc = thumbCandidates[0] || '';
            var thumbHtml = thumbSrc
                ? '<div class="sr-thumb" data-thumb="1"><img class="sr-thumb-img" alt="" loading="lazy"></div>'
                : '<div class="sr-thumb sr-thumb-empty">' + getSearchThumbnailFallbackHtml(isRadioResult) + '</div>';

            var sourceBadge = res.source ? '<span class="badge badge-source">' + safeText(res.source) + '</span>' : '';
            var liveBadge = (res.live === true || isRadioResult) ? '<span class="badge badge-live">LIVE</span>' : '';

            item.innerHTML =
                thumbHtml +
                '<div class="sr-info">' +
                    '<div class="sr-title">' + safeText(res.title || 'Untitled') + '</div>' +
                    '<div class="sr-meta">' +
                        safeText(res.author || 'Unknown') +
                        (res.duration ? ' - ' + timeToString(res.duration) : '') +
                        ' ' + sourceBadge + liveBadge +
                    '</div>' +
                '</div>' +
                '<div class="sr-actions">' +
                    (isRadioResult
                        ? '<button class="btn-icon btn-sm sr-radio-fav-btn' + (isRadioFavorite ? ' active' : '') + '" data-tooltip="Favorite station" aria-label="Favorite station">' +
                            '<svg width="16" height="16" viewBox="0 0 24 24" fill="' + (isRadioFavorite ? 'currentColor' : 'none') + '" stroke="currentColor" stroke-width="2"><polygon points="12 2 15 8.5 22 9.2 16.8 14 18.2 21 12 17.4 5.8 21 7.2 14 2 9.2 9 8.5 12 2"/></svg>' +
                        '</button>'
                        : '') +
                    '<button class="btn-icon btn-sm sr-play-btn" data-tooltip="Play now" aria-label="Play now">' +
                        '<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21"/></svg>' +
                    '</button>' +
                    '<button class="btn-icon btn-sm sr-add-btn" data-tooltip="Add to playlist" aria-label="Add to playlist">' +
                        '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>' +
                    '</button>' +
                '</div>';

            var thumbEl = item.querySelector('.sr-thumb[data-thumb="1"]');
            if (thumbEl) {
                bindSearchThumbnailFallback(thumbEl, thumbCandidates, isRadioResult);
            }

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
                    thumbnailCandidates: thumbCandidates,
                    source: resultSource,
                    radio: isRadioResult,
                    live: res.live === true || isRadioResult,
                    video: isRadioResult ? false : res.video !== false
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
            var favBtn = item.querySelector('.sr-radio-fav-btn');
            if (favBtn && favoriteKey) {
                favBtn.onclick = function(e) {
                    e.stopPropagation();
                    if (radioFavorites[favoriteKey]) {
                        delete radioFavorites[favoriteKey];
                        favBtn.classList.remove('active');
                        var icon = favBtn.querySelector('svg');
                        if (icon) icon.setAttribute('fill', 'none');
                        showNotification('Radio station removed from favorites.', 'Radio');
                    } else {
                        radioFavorites[favoriteKey] = {
                            title: res.title,
                            url: res.url,
                            author: res.author,
                            thumbnail: res.thumbnail,
                            source: 'radio',
                            live: true,
                            radio: true
                        };
                        favBtn.classList.add('active');
                        var filledIcon = favBtn.querySelector('svg');
                        if (filledIcon) filledIcon.setAttribute('fill', 'currentColor');
                        showNotification('Radio station saved locally.', 'Radio');
                    }
                    saveRadioFavorites();
                };
            }

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
    showPrompt('New Playlist', 'Enter playlist name... (max 50 chars)', function(name) {
        var trimmed = name && name.trim();
        if (trimmed && trimmed.length > 0 && trimmed.length <= 50) {
            if (!addPendingPlaylistCreate(trimmed)) {
                showNotification('Playlist creation is already pending.', 'Library');
                return;
            }
            showNotification('Creating playlist...', 'Library');
            sendMessage('createPlaylist', { name: trimmed });
        } else if (trimmed && trimmed.length > 50) {
            showNotification('Playlist name too long (max 50 characters).', 'Library', '#ff4444');
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

function markConfirmedFavorite(key, favorite, requestId) {
    if (!key) return;
    confirmedFavoriteState[key] = {
        favorite: favorite === true,
        requestId: Number.isFinite(Number(requestId)) ? Number(requestId) : null,
        expiresAt: Date.now() + FAVORITE_CONFIRMED_TTL_MS
    };
}

function getConfirmedFavorite(key) {
    if (!key) return null;
    var confirmed = confirmedFavoriteState[key];
    if (!confirmed) return null;
    if (Number(confirmed.expiresAt) <= Date.now()) {
        delete confirmedFavoriteState[key];
        return null;
    }
    return confirmed;
}

function clearExpiredConfirmedFavorites() {
    var now = Date.now();
    Object.keys(confirmedFavoriteState).forEach(function(key) {
        if (!confirmedFavoriteState[key] || Number(confirmedFavoriteState[key].expiresAt) <= now) {
            delete confirmedFavoriteState[key];
        }
    });
}

function applyPendingFavoritesSnapshot(playlists) {
    if (!Array.isArray(playlists)) return [];
    clearExpiredConfirmedFavorites();

    return playlists.map(function(pl) {
        if (!pl) return pl;
        var merged = {};
        Object.keys(pl).forEach(function(key) { merged[key] = pl[key]; });
        var key = normalizePlaylistId(merged.id);
        var pending = key ? pendingFavoriteState[key] : null;
        if (pending) {
            merged.is_favorite = pending.favorite === true ? 1 : 0;
            merged.isFavorite = pending.favorite === true;
        } else {
            var confirmed = getConfirmedFavorite(key);
            if (confirmed) {
                merged.is_favorite = confirmed.favorite === true ? 1 : 0;
                merged.isFavorite = confirmed.favorite === true;
            }
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

function getPendingPlaylistCreateRows() {
    return Object.keys(pendingPlaylistCreates).map(function(key) {
        return pendingPlaylistCreates[key];
    }).sort(function(a, b) {
        return (a.createdAt || 0) - (b.createdAt || 0);
    });
}

function normalizePlaylistNameKey(name) {
    return String(name || '').trim().toLowerCase();
}

function clearPendingPlaylistCreateByName(name) {
    var key = normalizePlaylistNameKey(name);
    var pending = pendingPlaylistCreates[key];
    if (!pending) return;
    if (pending.timeoutId) clearTimeout(pending.timeoutId);
    delete pendingPlaylistCreates[key];
}

function addPendingPlaylistCreate(name) {
    var key = normalizePlaylistNameKey(name);
    if (!key || pendingPlaylistCreates[key]) {
        return false;
    }

    pendingPlaylistCreateSeq += 1;
    pendingPlaylistCreates[key] = {
        id: 'pending-playlist-' + pendingPlaylistCreateSeq,
        name: String(name || '').trim(),
        pendingCreate: true,
        createdAt: Date.now(),
        timeoutId: setTimeout(function() {
            if (!pendingPlaylistCreates[key]) return;
            delete pendingPlaylistCreates[key];
            refreshPlaylistsDisplay({ quiet: false });
            showNotification('Playlist creation was not confirmed. Refreshed library state.', 'Library', '#ff4444');
            requestPlaylists(true);
        }, 8000)
    };
    refreshPlaylistsDisplay({ quiet: true });
    return true;
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

    authoritativePlaylists.forEach(function(pl) {
        if (pl && pl.name) {
            clearPendingPlaylistCreateByName(pl.name);
        }
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

    refreshDisplayedPlaylists({ quiet: shouldQuietPlaylistRefresh() });
}

function markQuietPlaylistRefresh(ms) {
    quietPlaylistRefreshUntil = Math.max(quietPlaylistRefreshUntil, Date.now() + (Number(ms) || 900));
}

function shouldQuietPlaylistRefresh() {
    return Date.now() < quietPlaylistRefreshUntil;
}

function updatePlaylistGridFavoriteState(lists, targetId) {
    var grid = document.getElementById(targetId);
    if (!grid || !Array.isArray(lists) || !lists.length) {
        return false;
    }

    var cards = Array.prototype.slice.call(grid.querySelectorAll('.playlist-card[data-playlist-id]'));
    if (cards.length !== lists.length) {
        return false;
    }

    for (var i = 0; i < lists.length; i++) {
        var pl = lists[i];
        var key = normalizePlaylistId(pl && pl.id);
        var card = cards[i];
        if (!key || !card || card.dataset.playlistId !== key) {
            return false;
        }

        var isFavorite = isPlaylistFavorite(pl);
        var isFavoritePending = !!pendingFavoriteState[key];
        card.classList.toggle('favorite-active', isFavorite);
        card.classList.toggle('favorite-pending', isFavoritePending);

        var sub = card.querySelector('.playlist-sub');
        if (sub) {
            sub.textContent = isFavorite ? 'Pinned favorite' : 'Playlist';
        }

        var pinBtn = card.querySelector('.playlist-pin-btn');
        if (pinBtn) {
            pinBtn.classList.toggle('active', isFavorite);
            pinBtn.classList.toggle('favorite-pending', isFavoritePending);
            pinBtn.title = isFavorite ? 'Unpin Favorite' : 'Pin Favorite';
            pinBtn.disabled = isFavoritePending;
        }
    }

    return true;
}

function refreshDisplayedPlaylists(options) {
    var quiet = !!(options && options.quiet) || shouldQuietPlaylistRefresh();
    cachedPlaylists = applyPendingFavoritesSnapshot(authoritativePlaylists);
    if (!(quiet && updatePlaylistGridFavoriteState(cachedPlaylists, 'playlists-grid'))) {
        populatePlaylists(cachedPlaylists, 'playlists-grid', { allowFavorite: true, quiet: quiet });
    }
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
    var displayedFavorite = previous;
    (cachedPlaylists || []).some(function(pl) {
        if (!pl) return false;
        if (String(pl.id) !== key) return false;
        displayedFavorite = isPlaylistFavorite(pl);
        return true;
    });

    if (!existingPending && displayedFavorite === normalizedFavorite) {
        debugLog('favorites', 'favorite request ignored because displayed state already matches target', {
            playlistId: playlistId,
            key: key,
            favorite: normalizedFavorite
        });
        markQuietPlaylistRefresh(1200);
        refreshDisplayedPlaylists({ quiet: true });
        return;
    }

    favoriteRequestSeq += 1;
    favoriteResponseFloor[key] = favoriteRequestSeq;
    delete confirmedFavoriteState[key];
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

    markQuietPlaylistRefresh(1800);
    refreshDisplayedPlaylists({ quiet: true });

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
        refreshDisplayedPlaylists({ quiet: true });
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
        refreshDisplayedPlaylists({ quiet: true });
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
    var hasOlderRevision = incomingRevision !== null && currentRevision !== null && incomingRevision < currentRevision;
    var payloadFavorite = normalizeFavoritePayloadValue(payload);
    var hasAuthoritativeFavoriteValue = payloadFavorite !== null && !hasStaleFavoriteAck && (Number.isFinite(requestId) || payload.success !== undefined);
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
        hasOlderRevision: hasOlderRevision,
        hasStaleFavoriteAck: hasStaleFavoriteAck,
        hasAuthoritativeFavoriteValue: hasAuthoritativeFavoriteValue,
        confirmsPending: confirmsPending
    });

    if (hasOlderRevision && !hasAuthoritativeFavoriteValue) {
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
    if (incomingRevision !== null && !hasOlderRevision) {
        libraryState.libraryRevision = incomingRevision;
    }
    if (!hasStaleFavoriteAck && payloadFavorite !== null) {
        if (payload.success === false) {
            delete confirmedFavoriteState[key];
        } else {
            markConfirmedFavorite(key, payloadFavorite, requestId);
        }
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
            markQuietPlaylistRefresh(1200);
            refreshDisplayedPlaylists({ quiet: true });
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
    if (hasOlderRevision) {
        if (patchCanonicalPlaylistFavorite(key, payload, payloadFavorite)) {
            markQuietPlaylistRefresh(1200);
            refreshDisplayedPlaylists({ quiet: true });
            if (payload.success === false && payload.message) {
                showNotification(payload.message, 'Library', '#ff4444');
            }
            return;
        }
        requestCanonicalPlaylistsRefresh();
        return;
    }
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
    var quiet = !!(options && options.quiet);
    var grid = document.getElementById(targetId);
    if (!grid) return;
    grid.classList.toggle('playlist-grid-quiet', quiet);

    var renderLists = Array.isArray(lists) ? lists.slice() : [];
    if (targetId === 'playlists-grid') {
        renderLists = renderLists.concat(getPendingPlaylistCreateRows());
    }

    if (!renderLists.length) {
        grid.innerHTML = '<div class="empty-state"><p>No playlists here.</p></div>';
        return;
    }

    grid.innerHTML = '';
    renderLists.forEach(function(pl) {
        var isPendingCreate = pl && pl.pendingCreate === true;
        var isFavorite = isPlaylistFavorite(pl);
        var isFavoritePending = !!pendingFavoriteState[normalizePlaylistId(pl.id)];
        var card = document.createElement('div');
        card.className = 'playlist-card' + (isFavorite ? ' favorite-active' : '') + (isFavoritePending ? ' favorite-pending' : '') + (isPendingCreate ? ' playlist-pending-create' : '');
        card.dataset.playlistId = normalizePlaylistId(pl.id) || '';
        card.innerHTML =
            '<div class="playlist-card-icon">' +
                '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>' +
            '</div>' +
            '<div class="playlist-card-body">' +
                '<div class="playlist-name">' + safeText(pl.name) + '</div>' +
                '<div class="playlist-sub">' + (isPendingCreate ? 'Creating...' : (isFavorite ? 'Pinned favorite' : 'Playlist')) + '</div>' +
            '</div>' +
            '<div class="playlist-card-actions">' +
                (allowFavorite && !isPendingCreate
                    ? '<button class="btn-icon btn-sm playlist-pin-btn' + (isFavorite ? ' active' : '') + (isFavoritePending ? ' favorite-pending' : '') + '" title="' + (isFavorite ? 'Unpin Favorite' : 'Pin Favorite') + '"' + (isFavoritePending ? ' disabled' : '') + '>' +
                        '<svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.9 6.1L22 9.3l-5 4.8L18.2 22 12 18.7 5.8 22 7 14.1 2 9.3l7.1-1.2z"/></svg>' +
                    '</button>'
                    : '') +
                (!isPendingCreate ? '<button class="btn-icon btn-sm playlist-share-btn" title="Share">' +
                    '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>' +
                '</button>' : '<span class="search-status-spinner" aria-hidden="true"></span>') +
            '</div>';

        card.onclick = function(e) {
            if (isPendingCreate) return;
            if (e.target.closest('.playlist-share-btn') || e.target.closest('.playlist-pin-btn')) return;
            openPlaylist(pl.id, pl.name);
        };

        var pinBtn = card.querySelector('.playlist-pin-btn');
        if (pinBtn) {
            pinBtn.onclick = function(e) {
                e.stopPropagation();
                setPlaylistFavoriteOptimistic(pl.id, !this.classList.contains('active'));
            };
        }

        var shareBtn = card.querySelector('.playlist-share-btn');
        if (shareBtn) {
            shareBtn.onclick = function(e) {
                e.stopPropagation();
                openShareModal(pl.id);
            };
        }

        grid.appendChild(card);
    });
    applyStaticTooltips();
}

function populatePlaylistTracks(pid, tracks) {
    var list = document.getElementById('tracks-list');
    if (!list) return;
    currentPlaylistTracks = Array.isArray(tracks) ? tracks.map(function(track) { return cloneValue(track); }) : [];

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
                    '<div class="list-item-sub">' + (tr.live === true ? 'LIVE' : timeToString(tr.duration)) + '</div>' +
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
            playTrack(tr);
        };
        item.querySelector('.track-remove-btn').onclick = function(e) {
            e.stopPropagation();
            sendMessage('removeTrack', { playlistId: pid, trackId: tr.id });
        };

        list.appendChild(item);
    });
    applyStaticTooltips();
}

function playTrack(track) {
    if (!activePlayerHandle) {
        showNotification('Select a device first!', 'Play', '#ff4444');
        return;
    }
    if (!track || !track.url) return;
    requestPlaybackOnHandle(_h(), {
        url: track.url,
        title: track.title || track.url,
        duration: track.duration,
        author: track.author,
        thumbnail: track.thumbnail,
        source: track.source,
        live: track.live === true,
        radio: track.radio === true,
        video: track.video !== false
    });
}

function playPlaylist() {
    if (!activePlayerHandle) {
        showNotification('Select a device first!', 'Play', '#ff4444');
        return;
    }
    if (!currentPlaylistId) return;
    var tracks = currentPlaylistTracks.filter(function(track) {
        return track && typeof track.url === 'string' && track.url !== '';
    }).map(function(track) {
        return {
            url: track.url,
            title: track.title || track.url,
            duration: track.duration,
            author: track.author,
            thumbnail: track.thumbnail,
            source: track.source,
            live: track.live === true,
            radio: track.radio === true,
            video: track.video !== false,
            audioTrack: cloneValue(track.audioTrack || track.selectedAudioTrack),
            selectedAudioTrack: cloneValue(track.selectedAudioTrack || track.audioTrack)
        };
    });
    if (tracks.length === 0) {
        showNotification('This playlist has no playable tracks.', 'Library', '#ff4444');
        return;
    }
    sendMessage('playPlaylistTracks', {
        handle: _h(),
        playlistId: currentPlaylistId,
        tracks: tracks
    });
    showNotification('Queued ' + tracks.length + ' track' + (tracks.length === 1 ? '' : 's') + ': ' + currentPlaylistName, 'Library');
}

function deleteCurrentPlaylist() {
    if (!currentPlaylistId) return;
    showConfirm('Delete Playlist?', 'Are you sure you want to permanently delete "' + currentPlaylistName + '"?', function(ok) {
        if (!ok) return;
        sendMessage('deletePlaylist', { playlistId: currentPlaylistId });
        switchView('view-library');
        currentPlaylistId = null;
        currentPlaylistTracks = [];
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
                trackData: {
                    title: pendingTrackForPlaylist.title,
                    url: pendingTrackForPlaylist.url,
                    duration: pendingTrackForPlaylist.duration,
                    author: pendingTrackForPlaylist.author,
                    thumbnail: pendingTrackForPlaylist.thumbnail,
                    source: pendingTrackForPlaylist.source,
                    live: pendingTrackForPlaylist.live === true,
                    radio: pendingTrackForPlaylist.radio === true,
                    video: pendingTrackForPlaylist.video !== false
                }
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
            '<div style="display:flex; gap:8px;">' +
                '<button class="btn-outline btn-sm" title="Decline">Decline</button>' +
                '<button class="btn-accent btn-sm" title="Accept">Accept</button>' +
            '</div>';

        item.querySelector('.btn-accent').onclick = function() {
            sendMessage('acceptFriendRequest', { requestId: r.id });
        };
        item.querySelector('.btn-outline').onclick = function() {
            sendMessage('declineFriendRequest', { requestId: r.id });
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

function selectAdminDevice(handle) {
    var key = normalizeAdminHandle(handle);
    if (!key) return;
    selectedAdminDeviceHandle = key;
    if (currentViewId !== 'view-admin') {
        switchView('view-admin');
    } else {
        renderAdminPanel();
    }
    try {
        window.dispatchEvent(new CustomEvent('pmms:adminSelectHandle', { detail: { handle: key } }));
    } catch (_) {}
}

function formatAdminCoords(coords) {
    if (!coords) return 'Unknown position';
    var x = Number(coords.x);
    var y = Number(coords.y);
    var z = Number(coords.z);
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) {
        return 'Unknown position';
    }
    return x.toFixed(1) + ', ' + y.toFixed(1) + ', ' + z.toFixed(1);
}

function getAdminLockMode(device) {
    var lock = device && device.adminLock;
    return lock && lock.mode ? String(lock.mode) : 'public';
}

function renderPendingRequestsHtml(device) {
    var pending = device && Array.isArray(device.pendingRequests) ? device.pendingRequests : [];
    if (!pending.length) {
        return '<div class="admin-empty-small">No pending requests.</div>';
    }
    return pending.map(function(request) {
        var options = request && request.options ? request.options : {};
        return '<div class="admin-pending-row" data-request-id="' + safeText(String(request.id || '')) + '">' +
            '<div class="admin-pending-main">' +
                '<strong>' + safeText(options.title || options.url || 'Requested media') + '</strong>' +
                '<span>' + safeText(request.playerName || ('Player ' + (request.source || ''))) + '</span>' +
            '</div>' +
            '<div class="admin-pending-actions">' +
                '<button class="btn-outline btn-sm" data-admin-approve-next="' + safeText(String(request.id || '')) + '">Next</button>' +
                '<button class="btn-outline btn-sm" data-admin-approve="' + safeText(String(request.id || '')) + '">Queue</button>' +
                '<button class="btn-danger btn-sm" data-admin-reject="' + safeText(String(request.id || '')) + '">Reject</button>' +
            '</div>' +
        '</div>';
    }).join('');
}

function renderLinkedSpeakersHtml(device) {
    var speakers = device && Array.isArray(device.linkedSpeakers) ? device.linkedSpeakers : [];
    if (!speakers.length) {
        return '<div class="admin-empty-small">No linked speakers.</div>';
    }
    return speakers.map(function(speaker, index) {
        return '<div class="admin-speaker-row">' +
            '<div class="admin-speaker-info">' +
                '<span>Speaker ' + (index + 1) + '</span>' +
                '<span>' + safeText(formatAdminCoords(speaker.coords || speaker.position)) + '</span>' +
                (speaker.persistent ? '<span class="badge badge-source">Persistent</span>' : '<span class="badge badge-type">Session</span>') +
            '</div>' +
            '<button class="btn-icon btn-sm btn-danger-sm" data-admin-remove-speaker="' + safeText(String(speaker.id || '')) + '" title="Remove speaker">' +
                '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M9 6V4h6v2"/></svg>' +
            '</button>' +
        '</div>';
    }).join('');
}

function renderAdminLogsHtml() {
    var logs = adminState && Array.isArray(adminState.logs) ? adminState.logs : [];
    if (!logs.length) {
        return '<div class="admin-empty-small">No logs yet.</div>';
    }
    return logs.slice(-30).reverse().map(function(log) {
        var details = log && log.data ? JSON.stringify(log.data) : '';
        return '<div class="admin-log-row">' +
            '<div><strong>' + safeText(log.event || 'event') + '</strong><span>#' + safeText(String(log.id || '')) + ' handle ' + safeText(String(log.handle || '')) + '</span></div>' +
            '<small>' + safeText(details.length > 120 ? details.substring(0, 117) + '...' : details) + '</small>' +
        '</div>';
    }).join('');
}

function renderAdminPanel() {
}

function parseAdminGrades(value) {
    return String(value || '').split(',').map(function(part) {
        var grade = Number(part.trim());
        return Number.isFinite(grade) ? grade : null;
    }).filter(function(grade) {
        return grade !== null;
    });
}

function buildAdminLockFromDetail() {
    var modeEl = document.getElementById('admin-detail-lock-mode');
    var jobEl = document.getElementById('admin-detail-lock-job');
    var gradeEl = document.getElementById('admin-detail-lock-grade');
    var gradesEl = document.getElementById('admin-detail-lock-grades');
    var mode = modeEl ? modeEl.value : 'public';
    var lock = { mode: mode };
    var job = jobEl ? String(jobEl.value || '').trim() : '';
    if (job) lock.job = job;
    var grade = gradeEl ? Number(gradeEl.value) : NaN;
    if (mode === 'job_grade' && Number.isFinite(grade)) lock.exactGrade = grade;
    if (mode === 'job_min_grade' && Number.isFinite(grade)) lock.minGrade = grade;
    if (mode === 'job_grades') lock.grades = parseAdminGrades(gradesEl ? gradesEl.value : '');
    return lock;
}

function bindAdminDetailActions(handle) {
    var saveBtn = document.getElementById('admin-detail-save-main');
    if (saveBtn) {
        saveBtn.onclick = function() {
            var nameEl = document.getElementById('admin-detail-name');
            var profileEl = document.getElementById('admin-detail-profile');
            var requestModeEl = document.getElementById('admin-detail-request-mode');
            var rangeEl = document.getElementById('admin-detail-range');
            var volumeEl = document.getElementById('admin-detail-volume');
            var transitionEl = document.getElementById('admin-detail-transition');
            if (nameEl && nameEl.value.trim()) {
                sendMessage('adminRenameDevice', { handle: handle, name: nameEl.value.trim() });
            }
            if (profileEl && profileEl.value) {
                sendMessage('adminApplyProfile', { handle: handle, profile: profileEl.value });
            }
            if (requestModeEl) {
                sendMessage('adminSetRequestMode', { handle: handle, mode: requestModeEl.value });
            }
            sendMessage('adminSetDeviceSettings', {
                handle: handle,
                settings: {
                    range: rangeEl ? Number(rangeEl.value) : undefined,
                    volume: volumeEl ? Number(volumeEl.value) : undefined,
                    transitionSeconds: transitionEl ? Number(transitionEl.value) : undefined
                }
            });
            sendMessage('adminSetLock', { handle: handle, lock: buildAdminLockFromDetail() });
            showNotification('Admin settings sent.', 'Admin');
        };
    }

    var settingsBtn = document.getElementById('admin-detail-open-settings');
    if (settingsBtn) settingsBtn.onclick = function() { openAdminModal(handle); };

    var resetBtn = document.getElementById('admin-detail-force-reset');
    if (resetBtn) resetBtn.onclick = function() {
        showConfirm('Force reset device?', 'This clears the live runtime state for this device.', function(ok) {
            if (ok) sendMessage('forceResetDevice', { handle: handle });
        });
    };

    var linkBtn = document.getElementById('admin-detail-link-speaker');
    if (linkBtn) linkBtn.onclick = function() {
        sendMessage('addLinkedSpeakerHere', { handle: handle, persistent: true });
    };

    var clearSpeakersBtn = document.getElementById('admin-detail-clear-speakers');
    if (clearSpeakersBtn) clearSpeakersBtn.onclick = function() {
        sendMessage('adminClearLinkedSpeakers', { handle: handle });
    };

    var clearPendingBtn = document.getElementById('admin-detail-clear-pending');
    if (clearPendingBtn) clearPendingBtn.onclick = function() {
        sendMessage('adminClearRequests', { handle: handle });
    };

    var removePersistentBtn = document.getElementById('admin-detail-remove-persistent');
    if (removePersistentBtn) removePersistentBtn.onclick = function() {
        showConfirm('Remove persistent device?', 'This removes the saved device entry from the resource data.', function(ok) {
            if (ok) sendMessage('adminRemovePersistentDevice', { handle: handle });
        });
    };

    document.querySelectorAll('[data-admin-approve]').forEach(function(btn) {
        btn.onclick = function() {
            sendMessage('adminApproveRequest', { handle: handle, requestId: this.dataset.adminApprove, playNext: false });
        };
    });
    document.querySelectorAll('[data-admin-approve-next]').forEach(function(btn) {
        btn.onclick = function() {
            sendMessage('adminApproveRequest', { handle: handle, requestId: this.dataset.adminApproveNext, playNext: true });
        };
    });
    document.querySelectorAll('[data-admin-reject]').forEach(function(btn) {
        btn.onclick = function() {
            sendMessage('adminRejectRequest', { handle: handle, requestId: this.dataset.adminReject });
        };
    });

    document.querySelectorAll('[data-admin-remove-speaker]').forEach(function(btn) {
        btn.onclick = function() {
            var speakerId = this.dataset.adminRemoveSpeaker;
            showConfirm('Remove linked speaker?', 'This will remove the physical speaker prop.', function(ok) {
                if (ok) sendMessage('removeLinkedSpeaker', { handle: handle, speakerId: speakerId });
            });
        };
    });
}

function bindAdminCreateButtons() {
    var interactionBtn = document.getElementById('admin-add-interaction-btn');
    if (interactionBtn && !interactionBtn.dataset.bound) {
        interactionBtn.dataset.bound = '1';
        interactionBtn.onclick = function() {
            promptCreatePersistentDevice('interaction');
        };
    }
    var propBtn = document.getElementById('admin-add-prop-btn');
    if (propBtn && !propBtn.dataset.bound) {
        propBtn.dataset.bound = '1';
        propBtn.onclick = function() {
            promptCreatePersistentDevice('prop');
        };
    }
}

function promptCreatePersistentDevice(mode) {
    showPrompt(mode === 'prop' ? 'New Prop Device' : 'New Interaction Point', 'Device name', function(name) {
        if (name == null) return;
        showPrompt('Device Profile', 'public, club, cinema, radio...', function(profile) {
            if (profile == null) return;
            var profileKey = String(profile || '').trim() || 'public';
            var payload = {
                mode: mode,
                label: String(name || '').trim() || (mode === 'prop' ? 'Persistent Prop' : 'Interaction Point'),
                profile: profileKey,
                requestMode: (requestConfig && requestConfig.defaultMode) || 'queue',
                adminLock: { mode: 'public' },
            };
            if (mode === 'prop') {
                showPrompt('Prop Model', 'prop_tv_flat_01', function(propModel) {
                    if (propModel == null) return;
                    payload.propModel = String(propModel || '').trim();
                    sendMessage('adminAddPersistentDevice', payload);
                });
            } else {
                sendMessage('adminAddPersistentDevice', payload);
            }
        });
    });
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
    if (attSameInput) attSameInput.value = state.attSame.toFixed(1);
    if (attDiffInput) attDiffInput.value = state.attDiff.toFixed(1);
    if (diffRoomInput) diffRoomInput.value = state.diffRoomVolume.toFixed(2);
    if (transitionInput) transitionInput.value = state.transitionSeconds.toFixed(1);

    var rangeLabel = body.querySelector('#val-range');
    var attSameLabel = body.querySelector('#val-att-same');
    var attDiffLabel = body.querySelector('#val-att-diff');
    var diffRoomLabel = body.querySelector('#val-diff-room');
    var transitionLabel = body.querySelector('#val-transition');

    if (rangeLabel) rangeLabel.textContent = Math.round(state.range) + 'm';
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
        var canEditAdvanced = canEdit;
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
        var showForceReset = permissions.overrideDevice === true || permissions.manage === true;
        var showStaffQuick = isStaffUser();

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
        '</div>';

        var speakerList = (session && session.settings && Array.isArray(session.settings.linkedSpeakers))
            ? session.settings.linkedSpeakers
            : (session && Array.isArray(session.linkedSpeakers) ? session.linkedSpeakers : []);
        var speakerHtml = '';
        if (speakerList.length > 0) {
            speakerHtml = '<div class="admin-speaker-list" id="admin-speaker-list">';
            speakerList.forEach(function(spk) {
                var canDeleteSpk = spk.persistent === true
                    ? isAdminUser()
                    : (isStaffUser() || (spk.createdBy && spk.createdBy === (permissions && permissions.identifier)));
                speakerHtml +=
                    '<div class="admin-speaker-row" data-speaker-id="' + safeText(String(spk.id || '')) + '">' +
                        '<div class="admin-speaker-info">' +
                            '<span class="admin-speaker-name">' + safeText(spk.propModel || 'Speaker') + '</span>' +
                            '<span class="admin-speaker-meta">' + safeText(spk.createdByName || '') + (spk.persistent ? ' Â· persistent' : '') + '</span>' +
                        '</div>' +
                        (canDeleteSpk
                            ? '<button class="btn-danger btn-xs admin-speaker-remove" data-speaker-id="' + safeText(String(spk.id || '')) + '">Remove</button>'
                            : '<span class="admin-speaker-locked">ðŸ”’</span>') +
                    '</div>';
            });
            speakerHtml += '</div>';
        } else {
            speakerHtml = '<p class="admin-speaker-empty">No linked speakers.</p>';
        }

        var staffPillsHtml = '';
        if (showStaffQuick) {
            staffPillsHtml =
                '<div class="admin-section staff-pills">' +
                '<label class="admin-label">Staff Actions</label>' +
                '<div class="admin-pill-bar">' +
                    (isAdminUser() ? '<button class="pill-btn" id="staff-open-admin-panel" title="Open Admin Panel">Admin Panel</button>' : '') +
                    '<button class="pill-btn" id="staff-clear-session-lock" title="Remove session lock/PIN">Clear Lock</button>' +
                    (adminQuickActions && adminQuickActions.applyProfiles
                        ? '<select id="staff-profile-select" class="pill-select">' + getProfileOptionsHtml(info.profile || '') + '</select>' +
                          '<button class="pill-btn" id="staff-apply-profile">Apply Profile</button>'
                        : '') +
                    '<button class="pill-btn" id="staff-link-persistent-speaker" title="Place a persistent speaker (stays after restart)">Persistent Speaker</button>' +
                    (adminQuickActions && adminQuickActions.extendedRangeToggle
                        ? '<button class="pill-btn" id="staff-extended-range" title="Enable extended range slider">Ext. Range</button>'
                        : '') +
                    (showForceReset ? '<button class="pill-btn pill-btn-danger" id="staff-force-reset" title="Force reset the live device session">Force Reset</button>' : '') +
                '</div>' +
                '</div>';
        }



        body.innerHTML +=
            '<div class="admin-section">' +
                '<div class="admin-row">' +
                    '<label>Speakers</label>' +
                    '<button class="btn-outline btn-sm" id="link-speaker-btn"' + (canInteract ? '' : ' disabled') + '>Add Speaker</button>' +
                '</div>' +
                speakerHtml +
            '</div>' +

            staffPillsHtml +

            '<div class="admin-section">' +
                '<label class="admin-label">Range <span id="val-range">' + Math.round(state.range) + 'm</span></label>' +
                '<input type="range" class="slider' + (allowAdminRange ? ' slider-admin-range' : '') + '" id="set-range" min="0" max="' + rangeSliderMax + '" value="' + rangeSliderValue + '"' + (canEditAdvanced ? '' : ' disabled') + '>' +
                '<div class="admin-range-meta"><span>Normal max ' + Math.round(maxRange) + 'm</span>' + (allowAdminRange ? '<span class="admin-range-admin">Admin max ' + Math.round(maxAllowedRange) + 'm</span>' : '') + '</div>' +
            '</div>' +

            '<div class="admin-section">' +
                '<label class="admin-label">Same-Room Attenuation <span id="val-att-same">' + state.attSame.toFixed(1) + '</span></label>' +
                '<input type="range" class="slider" id="set-att-same" min="0" max="10" step="0.1" value="' + state.attSame.toFixed(1) + '"' + (canEditAdvanced ? '' : ' disabled') + '>' +
            '</div>' +

            '<div class="admin-section">' +
                '<label class="admin-label">Diff-Room Attenuation <span id="val-att-diff">' + state.attDiff.toFixed(1) + '</span></label>' +
                '<input type="range" class="slider" id="set-att-diff" min="0" max="10" step="0.1" value="' + state.attDiff.toFixed(1) + '"' + (canEditAdvanced ? '' : ' disabled') + '>' +
            '</div>' +

            '<div class="admin-section">' +
                '<label class="admin-label">Diff-Room Volume <span id="val-diff-room">' + (state.diffRoomVolume * 100).toFixed(0) + '%</span></label>' +
                '<input type="range" class="slider" id="set-diff-room" min="0" max="1" step="0.01" value="' + state.diffRoomVolume.toFixed(2) + '"' + (canEditAdvanced ? '' : ' disabled') + '>' +
            '</div>' +

            '<div class="admin-section">' +
                '<label class="admin-label">Transition <span id="val-transition">' + state.transitionSeconds.toFixed(1) + 's</span></label>' +
                '<input type="range" class="slider" id="set-transition" min="0" max="' + maxTransitionSeconds.toFixed(1) + '" step="0.1" value="' + state.transitionSeconds.toFixed(1) + '"' + (canEditAdvanced ? '' : ' disabled') + '>' +
            '</div>' +

            '<div class="admin-section admin-row" id="admin-reset-row" style="display:none;">' +
                '<label>Defaults</label>' +
                '<button class="btn-outline btn-sm" id="admin-reset-btn"' + (canEditAdvanced ? '' : ' disabled') + '>Reset to Defaults</button>' +
            '</div>' +

            '<div class="admin-section admin-row">' +
                '<label>Vehicle Mode</label>' +
                '<button class="toggle-btn' + (state.isVehicle ? ' toggle-on' : '') + '" id="toggle-veh"' + (canEditAdvanced ? '' : ' disabled') + '>' + (state.isVehicle ? 'ON' : 'OFF') + '</button>' +
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
        updateAdminResetControls(body, state, defaults, canEditAdvanced, function() {
            var previous = {
                range: state.range,
                attSame: state.attSame,
                attDiff: state.attDiff,
                diffRoomVolume: state.diffRoomVolume,
                transitionSeconds: state.transitionSeconds,
                isVehicle: state.isVehicle
            };

            resetAdminWriteTimers();
            state.range = defaults.range;
            state.attSame = defaults.attSame;
            state.attDiff = defaults.attDiff;
            state.diffRoomVolume = defaults.diffRoomVolume;
            state.transitionSeconds = defaults.transitionSeconds;
            state.isVehicle = defaults.isVehicle;

            syncAdminControls(body, state);

            if (Math.abs(previous.range - state.range) >= 0.01) sendRange();
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
        var linkSpeakerBtn = body.querySelector('#link-speaker-btn');
        if (linkSpeakerBtn) {
            linkSpeakerBtn.onclick = function() {
                showPropModelPicker('Choose Speaker Prop', 'Place', function(model) {
                    closeAdminModal();
                    sendMessage('addLinkedSpeakerHere', { handle: handle, persistent: false, propModel: model });
                }, speakerModels);
            };
        }

        body.querySelectorAll('.admin-speaker-remove').forEach(function(btn) {
            btn.onclick = function() {
                var sid = btn.dataset.speakerId;
                if (!sid) return;
                showConfirm('Remove Speaker?', 'This will remove the linked speaker from this device.', function(ok) {
                    if (!ok) return;
                    sendMessage('removeLinkedSpeaker', { handle: handle, speakerId: sid });
                    var row = body.querySelector('.admin-speaker-row[data-speaker-id="' + sid + '"]');
                    if (row) row.remove();
                });
            };
        });

        var staffOpenPanelBtn = body.querySelector('#staff-open-admin-panel');
        if (staffOpenPanelBtn) {
            staffOpenPanelBtn.onclick = function() {
                closeAdminModal();
                selectAdminDevice(handle);
            };
        }

        var staffClearLockBtn = body.querySelector('#staff-clear-session-lock');
        if (staffClearLockBtn) {
            staffClearLockBtn.onclick = function() {
                sendMessage('adminClearSessionLock', { handle: handle });
            };
        }

        var staffApplyProfileBtn = body.querySelector('#staff-apply-profile');
        if (staffApplyProfileBtn) {
            staffApplyProfileBtn.onclick = function() {
                var select = body.querySelector('#staff-profile-select');
                if (select && select.value) {
                    sendMessage('adminApplyProfile', { handle: handle, profile: select.value });
                }
            };
        }

        var staffExtendedRangeBtn = body.querySelector('#staff-extended-range');
        if (staffExtendedRangeBtn) {
            staffExtendedRangeBtn.onclick = function() {
                var rangeInput = body.querySelector('#set-range');
                if (!rangeInput) return;
                rangeInput.disabled = false;
                rangeInput.focus();
                showNotification('Extended range control enabled for this edit.', 'Device Settings');
            };
        }

        var staffPersistentSpeakerBtn = body.querySelector('#staff-link-persistent-speaker');
        if (staffPersistentSpeakerBtn) {
            staffPersistentSpeakerBtn.onclick = function() {
                showPropModelPicker('Choose Persistent Speaker Prop', 'Place Persistent', function(model) {
                    closeAdminModal();
                    sendMessage('addLinkedSpeakerHere', { handle: handle, persistent: true, propModel: model });
                }, speakerModels);
            };
        }

        var staffForceResetBtn = body.querySelector('#staff-force-reset');
        if (staffForceResetBtn) {
            staffForceResetBtn.onclick = function() {
                showConfirm('Force reset device?', 'This clears the live runtime state for this device.', function(ok) {
                    if (ok) {
                        sendMessage('forceResetDevice', { handle: handle });
                        closeAdminModal();
                    }
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
        '#friend-suggestions{' +
            'position:absolute;left:0;right:0;top:calc(100% + 8px);display:none;flex-direction:column;gap:4px;' +
            'padding:8px;background:var(--bg-elevated);border:1px solid var(--border);border-radius:10px;' +
            'box-shadow:var(--shadow);z-index:1000;max-height:260px;overflow-y:auto;' +
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
    if (hint && hint.parentNode) {
        hint.parentNode.removeChild(hint);
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
    setUiVisible(false);

    document.addEventListener('keydown', function(e) {
        if (e.key !== 'Escape') return;
        var modals = ['admin-modal', 'share-modal', 'add-to-playlist-modal', 'loop-help-modal', 'nearby-devices-modal', 'confirm-modal', 'prompt-modal'];
        for (var i = 0; i < modals.length; i++) {
            var m = document.getElementById(modals[i]);
            if (m && m.style.display === 'flex') {
                if (modals[i] === 'admin-modal')        closeAdminModal();
                else if (modals[i] === 'nearby-devices-modal') closeNearbyDevicesModal();
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
                searchProxyThumbnails: d.searchProxyThumbnails,
                currentServerEndpoint: d.currentServerEndpoint,
                deviceDefaults: d.deviceDefaults,
                openView: d.openView,
                baseVolume: d.baseVolume,
                permissions: d.permissions,
                deviceProfiles: d.deviceProfiles,
                propModels: d.propModels,
                speakerModels: d.speakerModels,
                adminQuickActions: d.adminQuickActions,
                requestConfig: d.requestConfig,
                speakerConfig: d.speakerConfig,
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
            applySelectedDeviceTheme('none');
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
            currentPlaylistTracks = [];
            Object.keys(pendingFavoriteState).forEach(function(key) {
                clearPendingFavoriteTimers(key);
            });
            pendingFavoriteState = {};
            confirmedFavoriteState = {};
            favoriteRequestSeq = 0;
            favoriteResponseFloor = {};
            pendingControlState = {};
            adminState = null;
            selectedAdminDeviceHandle = null;
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


