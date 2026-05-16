local startContexts = {}
local startupStates = {}
local startupStateTtlSeconds = 12
local startAttemptSequence = 0
local startPlaybackSequence = 0
local endedEventGuards = {}
local deviceSessions = {}
local deviceSessionRevision = 0
local maxDeviceHistoryEntries = 50
local sessionLocks = {}
local sessionLockIdleSeconds = 10 * 60
local commitDeviceSession
local isYoutubeLikeUrl
local pushImmediateSync
local getDeviceCapabilityState

local function cloneTable(source)
    local copy = {}
    for k, v in pairs(source or {}) do
        copy[k] = v
    end
    return copy
end

local function cloneDeepTable(source, seen)
    if type(source) ~= "table" then
        return source
    end

    seen = seen or {}
    if seen[source] then
        return seen[source]
    end

    local copy = {}
    seen[source] = copy

    for key, value in pairs(source) do
        copy[cloneDeepTable(key, seen)] = cloneDeepTable(value, seen)
    end

    return copy
end

local function getMaxHistorySyncItems()
    local uiConfig = type(Config.ui) == "table" and Config.ui or {}
    return math.max(0, tonumber(uiConfig.maxHistorySyncItems) or 30)
end

local function cloneRecentHistoryForSync(history)
    if type(history) ~= "table" then
        return {}
    end

    local total = #history
    local limit = getMaxHistorySyncItems()
    if limit <= 0 or total <= limit then
        return cloneDeepTable(history)
    end

    local copy = {}
    local first = total - limit + 1
    for index = first, total do
        copy[#copy + 1] = cloneDeepTable(history[index])
    end
    return copy
end

local function createStartAttemptId(handle)
    startAttemptSequence = startAttemptSequence + 1
    return ("%s:%d:%d"):format(tostring(handle), os.time(), startAttemptSequence)
end

local function createPlaybackToken(handle)
    startPlaybackSequence = startPlaybackSequence + 1
    return ("%s:%d:%d"):format(tostring(handle), os.time(), startPlaybackSequence)
end

local function getConfiguredDirectLinkProbeTimeoutMs()
    local directLinkConfig = type(Config.directLinks) == "table" and Config.directLinks or {}
    return math.max(1000, tonumber(directLinkConfig.probeTimeoutMs) or 2500)
end

local function getStartupWatchdogMs()
    local resolver = type(Config.resolver) == "table" and Config.resolver or {}
    local extractor = type(resolver.extractor) == "table" and resolver.extractor or {}
    local resolverTimeoutMs = math.max(2000, tonumber(resolver.timeoutMs) or 6000)
    local extractorTimeoutMs = math.max(resolverTimeoutMs, tonumber(extractor.timeoutMs) or resolverTimeoutMs)
    local browserTimeoutMs = math.max(5000, tonumber(Config.dui and Config.dui.timeout) or 30000)
    local baselineMs = math.max(
        browserTimeoutMs,
        resolverTimeoutMs + getConfiguredDirectLinkProbeTimeoutMs() + 5000,
        extractorTimeoutMs + getConfiguredDirectLinkProbeTimeoutMs() + 5000
    )
    return math.max(8000, math.min(30000, baselineMs))
end

local function getStartContextTtlSeconds()
    local resolver = type(Config.resolver) == "table" and Config.resolver or {}
    local retryAttempts = math.max(0, tonumber(resolver.retryAttempts) or 1)
    local resolverTimeoutMs = math.max(2000, tonumber(resolver.timeoutMs) or 6000)
    local totalMs = getStartupWatchdogMs() + resolverTimeoutMs + (retryAttempts * math.max(4000, resolverTimeoutMs))
    return math.max(18, math.min(60, math.ceil(totalMs / 1000) + 2))
end

local function applyPlaybackToken(target, playbackToken)
    if type(target) ~= "table" then
        return target
    end

    target.playbackToken = playbackToken or target.playbackToken or nil
    return target
end

local function setStartupState(handle, phase, message, details)
    local state = startupStates[handle] or {}
    state.handle = handle
    state.phase = phase
    state.message = message
    state.updatedAt = os.time()
    state.expiresAt = nil

    if type(details) == "table" then
        for key, value in pairs(details) do
            state[key] = value
        end
    end

    startupStates[handle] = state
    MarkDirty()
    if pushImmediateSync then
        pushImmediateSync()
    end
    PMMSDebug("player", "startup state changed", {
        handle = handle,
        phase = phase,
        message = message,
        attemptId = state.attemptId,
        provider = state.provider,
        instance = state.instance,
        resolverStatus = state.resolverStatus,
        resolverReason = state.resolverReason,
        retryCount = state.retryCount,
    })
    return state
end

local function expireStartupState(handle, phase, message, details, ttl)
    local state = setStartupState(handle, phase, message, details)
    state.expiresAt = os.time() + math.max(1, tonumber(ttl) or startupStateTtlSeconds)
    startupStates[handle] = state
    MarkDirty()
    return state
end

local function clearStartupState(handle)
    if startupStates[handle] then
        PMMSDebug("player", "startup state cleared", {
            handle = handle,
            phase = startupStates[handle] and startupStates[handle].phase or nil,
            attemptId = startupStates[handle] and startupStates[handle].attemptId or nil,
        })
        startupStates[handle] = nil
        MarkDirty()
        if pushImmediateSync then
            pushImmediateSync()
        end
    end
end

local function buildStartupStateDetails(context, resolvedOptions, extras)
    local details = {}
    local resolved = resolvedOptions or {}
    local resolver = resolved.resolver or {}

    if type(context) == "table" then
        details.attemptId = context.currentAttemptId
        details.playbackToken = context.playbackToken
        details.retryCount = tonumber(context.retries) or 0
        details.fallbackUsed = context.embedFallbackUsed == true or resolver.status == "fallback"
    end

    details.provider = resolver.provider
    details.instance = resolver.instance
    details.resolverStatus = resolver.status
    details.resolverReason = resolver.reason
    details.title = resolved.title
    details.url = resolved.originalUrl or resolved.url

    if type(extras) == "table" then
        for key, value in pairs(extras) do
            details[key] = value
        end
    end

    return details
end

function NormalizeLoopMode(loopMode, legacyLoop)
    if type(loopMode) == "string" then
        local normalized = loopMode:lower()
        if normalized == "off"
            or normalized == "track"
            or normalized == "queue"
            or normalized == "shuffle_once"
            or normalized == "shuffle_loop" then
            return normalized
        end
    end

    if legacyLoop == true then
        return "track"
    end

    return "off"
end

local function applyLoopMode(options, loopMode, legacyLoop)
    local normalized = NormalizeLoopMode(loopMode, legacyLoop)
    options.loopMode = normalized
    options.loop = normalized == "track"
    return normalized
end

local function normalizePin(pin)
    if pin == nil then
        return nil
    end

    local asString = tostring(pin)
    asString = asString:match("^%s*(.-)%s*$")
    if asString == "" then
        return nil
    end

    if #asString < 4 or #asString > 12 then
        return nil
    end

    return asString
end

local function hasSessionLock(handle)
    return sessionLocks[handle] ~= nil
end

local function clearSessionLock(handle)
    if sessionLocks[handle] then
        sessionLocks[handle] = nil
        local session = deviceSessions[handle]
        if session then
            commitDeviceSession(handle, session)
        else
            MarkDirty()
        end
        if type(ReconcilePmmsDeviceRequestState) == "function" then
            ReconcilePmmsDeviceRequestState(handle, {
                reason = "session_lock_cleared",
            })
        end
    end
end

function ForceClearSessionLock(handle)
    clearSessionLock(tonumber(handle) or handle)
end

function GetPmmsSessionLockSnapshot(handle)
    local lock = sessionLocks[tonumber(handle) or handle]
    if type(lock) ~= "table" then
        return nil
    end
    return cloneDeepTable(lock)
end

local function isSessionLockOwner(lock, src)
    if not lock then
        return false
    end

    local identifier = GetUserIdentifier(src)
    return identifier ~= nil and lock.ownerLicense ~= nil and identifier == lock.ownerLicense
end

local function isSessionPinAuthorized(lock, src)
    return lock and lock.authorized and lock.authorized[src] == true and lock.pin ~= nil
end

local function touchSessionLock(handle, src)
    local lock = sessionLocks[handle]
    if not lock then
        return
    end
    lock.lastActivity = os.time()
    if src then
        lock.lastSource = src
    end
end

function CanAccessSessionLock(src, handle, bypassManage)
    local lock = sessionLocks[handle]
    if not lock then
        return true, nil
    end

    if bypassManage ~= false and HasPmmsPermission(src, "manage") then
        touchSessionLock(handle, src)
        return true, lock
    end

    if isSessionLockOwner(lock, src) or isSessionPinAuthorized(lock, src) then
        touchSessionLock(handle, src)
        return true, lock
    end

    return false, lock
end

local function buildSessionLockStateForPlayer(src, handle)
    local lock = sessionLocks[handle]
    if not lock then
        return nil
    end

    local isOwner = isSessionLockOwner(lock, src)
    local isAuthorized = HasPmmsPermission(src, "manage")
        or isOwner
        or isSessionPinAuthorized(lock, src)

    return {
        active = true,
        ownerName = lock.ownerName or ("Player " .. tostring(lock.ownerSource or "?")),
        hasPin = lock.pin ~= nil,
        isOwner = isOwner,
        accessGranted = isAuthorized,
    }
end

local function upsertSessionLock(handle, src, pin)
    local normalizedPin = normalizePin(pin)
    local identifier = GetUserIdentifier(src)
    if not identifier then
        return false, "Could not identify this player."
    end

    local lock = sessionLocks[handle]
    if not lock then
        lock = {
            ownerSource = src,
            ownerLicense = identifier,
            ownerName = GetPlayerName(src) or ("Player " .. tostring(src)),
            pin = normalizedPin,
            authorized = {},
            lastActivity = os.time(),
            lastSource = src,
        }
        sessionLocks[handle] = lock
    else
        lock.ownerSource = lock.ownerSource or src
        lock.ownerLicense = lock.ownerLicense or identifier
        lock.ownerName = lock.ownerName or (GetPlayerName(src) or ("Player " .. tostring(src)))
        lock.pin = normalizedPin
        lock.authorized = lock.authorized or {}
        lock.lastActivity = os.time()
        lock.lastSource = src
    end

    lock.authorized[src] = true
    local session = deviceSessions[handle]
    if session then
        commitDeviceSession(handle, session)
    else
        MarkDirty()
    end
    if type(ReconcilePmmsDeviceRequestState) == "function" then
        ReconcilePmmsDeviceRequestState(handle, {
            source = src,
            reason = "session_lock_updated",
        })
    end
    return true, nil
end

local function setSessionLockPin(handle, src, pin)
    local lock = sessionLocks[handle]
    if not lock then
        return false, "No active session lock exists."
    end

    if not (HasPmmsPermission(src, "manage") or isSessionLockOwner(lock, src)) then
        return false, "Only the lock owner can change the PIN."
    end

    lock.pin = normalizePin(pin)
    lock.lastActivity = os.time()
    lock.lastSource = src
    lock.authorized = {}
    lock.authorized[src] = true
    local session = deviceSessions[handle]
    if session then
        commitDeviceSession(handle, session)
    else
        MarkDirty()
    end
    return true, nil
end

local function authorizeSessionLockPin(handle, src, pin)
    local lock = sessionLocks[handle]
    if not lock then
        return false, "No active session lock exists."
    end

    if lock.pin == nil then
        return false, "This lock does not have a PIN."
    end

    if normalizePin(pin) ~= lock.pin then
        return false, "Invalid PIN."
    end

    lock.authorized = lock.authorized or {}
    lock.authorized[src] = true
    lock.lastActivity = os.time()
    lock.lastSource = src
    local session = deviceSessions[handle]
    if session then
        commitDeviceSession(handle, session)
    else
        MarkDirty()
    end
    return true, nil
end

local function unlockSessionLock(handle, src)
    local lock = sessionLocks[handle]
    if not lock then
        return false, "No active session lock exists."
    end

    if not (HasPmmsPermission(src, "manage") or isSessionLockOwner(lock, src)) then
        return false, "Only the lock owner can unlock this session."
    end

    clearSessionLock(handle)
    return true, nil
end

function BuildMediaPlayersSyncStateForPlayer(src)
    local states = {}
    for handle, info in pairs(GetMediaPlayers()) do
        local copy = cloneDeepTable(info)
        local session = deviceSessions[handle]
        local sessionLock = buildSessionLockStateForPlayer(src, handle)
        local requestState = type(GetPmmsDeviceRequestState) == "function" and GetPmmsDeviceRequestState(handle) or nil
        copy.sessionLock = sessionLock
        copy.sessionLocked = sessionLock ~= nil
        copy.playbackMode = copy.video == false and "audio" or "video"
        copy.deviceCapability = getDeviceCapabilityState(copy, session)
        copy.requestState = requestState
        copy.configuredRequestMode = requestState and requestState.configuredMode or copy.requestMode
        copy.requestModeReason = requestState and requestState.reason or nil
        copy.requestMode = requestState and requestState.effectiveMode or (type(GetPmmsDeviceRequestMode) == "function" and GetPmmsDeviceRequestMode(handle) or copy.requestMode)
        copy.linkedSpeakers = type(GetPmmsLinkedSpeakers) == "function" and GetPmmsLinkedSpeakers(handle) or copy.linkedSpeakers
        copy.equalizerProfile = type(GetDeviceEqProfile) == "function" and GetDeviceEqProfile(handle) or copy.equalizerProfile
        if session then
            copy.stateRevision = session.stateRevision
            copy.idleResetAt = session.idleResetAt
            copy.resetActive = session.resetActive == true
        end
        states[handle] = copy
    end

    local startupStateCopy = {}
    for handle, info in pairs(startupStates) do
        startupStateCopy[handle] = cloneDeepTable(info)
    end

    local sessionStateCopy = {}
    for handle, session in pairs(deviceSessions) do
        local sessionLock = buildSessionLockStateForPlayer(src, handle)
        local requestState = type(GetPmmsDeviceRequestState) == "function" and GetPmmsDeviceRequestState(handle) or nil
        local fullHistoryCount = type(session.history) == "table" and #session.history or 0
        local history = cloneRecentHistoryForSync(session.history)
        local preview = type(BuildPlaybackPreview) == "function"
            and BuildPlaybackPreview(handle, GetMediaPlayer(handle), session)
            or cloneDeepTable(session.queue)
        sessionStateCopy[handle] = {
            handle = handle,
            settings = cloneDeepTable(session.settings),
            defaults = cloneDeepTable(session.defaults),
            queue = cloneDeepTable(session.queue),
            history = history,
            playbackPreview = preview,
            queueLength = type(session.queue) == "table" and #session.queue or 0,
            historyCount = fullHistoryCount,
            canGoPrevious = type(session.history) == "table" and #session.history > 0 or false,
            currentTrack = cloneDeepTable(session.currentTrack),
            idleResetAt = session.idleResetAt,
            resetActive = session.resetActive == true,
            stateRevision = session.stateRevision,
            playbackActive = IsMediaPlayerActive(handle),
            sessionLock = sessionLock,
            sessionLocked = sessionLock ~= nil,
            deviceCapability = getDeviceCapabilityState(nil, session),
            requestState = requestState,
            configuredRequestMode = requestState and requestState.configuredMode or nil,
            requestModeReason = requestState and requestState.reason or nil,
            requestMode = requestState and requestState.effectiveMode or (type(GetPmmsDeviceRequestMode) == "function" and GetPmmsDeviceRequestMode(handle) or nil),
            linkedSpeakers = type(GetPmmsLinkedSpeakers) == "function" and GetPmmsLinkedSpeakers(handle) or nil,
            equalizerProfile = type(GetDeviceEqProfile) == "function" and GetDeviceEqProfile(handle) or nil,
            pendingRequests = type(GetPmmsPendingRequestsForHandle) == "function" and GetPmmsPendingRequestsForHandle(handle) or {},
        }
    end

    local payload = {
        mediaPlayers = states,
        startupStates = startupStateCopy,
        deviceSessions = sessionStateCopy,
    }

    if type(BuildPmmsAdminSyncState) == "function" then
        payload.admin = BuildPmmsAdminSyncState(src)
    end

    return payload
end

pushImmediateSync = function(target)
    if target ~= nil then
        TriggerClientEvent("pmms:sync", target, BuildMediaPlayersSyncStateForPlayer(target))
        return
    end

    for _, playerId in ipairs(GetPlayers()) do
        local resolvedTarget = tonumber(playerId) or playerId
        TriggerClientEvent("pmms:sync", resolvedTarget, BuildMediaPlayersSyncStateForPlayer(resolvedTarget))
    end
end

function PushPmmsImmediateSync(target)
    pushImmediateSync(target)
end

function CleanupSessionLocks(now)
    now = now or os.time()
    for handle, lock in pairs(sessionLocks) do
        if not deviceSessions[handle] then
            clearSessionLock(handle)
        elseif (now - (lock.lastActivity or now)) > sessionLockIdleSeconds then
            clearSessionLock(handle)
        end
    end
end

local function requirePermission(src, handle, permission, plate)
    local isPublicInteract = permission == "interact"
    if not isPublicInteract and not HasPmmsPermission(src, permission) then
        TriggerClientEvent("pmms:error", src, "You do not have permission for this action")
        return false
    end

    local mp = GetMediaPlayer(handle)
    local session = deviceSessions[handle]
    if type(CanUsePmmsAdminLockedDevice) == "function" and not CanUsePmmsAdminLockedDevice(src, handle, plate) then
        TriggerClientEvent("pmms:error", src, "This device is restricted by staff.")
        return false
    end

    if mp and mp.locked and not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "This media player is locked")
        return false
    end

    if (mp or session) and hasSessionLock(handle) then
        local canAccess, lock = CanAccessSessionLock(src, handle, true)
        if not canAccess then
            local msg = "This media session is locked by another player."
            if lock and lock.pin ~= nil then
                msg = "This media session is PIN-protected. Enter the PIN in Device Settings."
            end
            TriggerClientEvent("pmms:error", src, msg)
            return false
        end
    end

    return true
end

local function requireStaffDevicePermission(src, action)
    if HasPmmsPermission(src, "manage") or HasPmmsPermission(src, "overrideDevice") then
        return true
    end
    TriggerClientEvent("pmms:error", src, action or "Only staff can change advanced device settings.")
    return false
end

local function isUrlAllowed(url)
    for _, pattern in ipairs(Config.allowedUrls) do
        if url:match(pattern) then
            return true
        end
    end
    return false
end

local function getRandomPreset()
    local presets = {}
    for preset in pairs(Config.presets) do
        presets[#presets + 1] = preset
    end
    return #presets > 0 and presets[math.random(#presets)] or ""
end

local function stripUrlQuery(url)
    if type(url) ~= "string" then
        return nil
    end
    return (url:gsub("[?#].*$", ""))
end

local function redactUrlForDebug(url)
    if type(url) ~= "string" then
        return url
    end

    local redacted = url
    local queryStart = redacted:find("?", 1, true)
    if queryStart then
        redacted = redacted:sub(1, queryStart - 1) .. "?<redacted>"
    end

    local hashStart = redacted:find("#", 1, true)
    if hashStart then
        redacted = redacted:sub(1, hashStart - 1) .. "#<redacted>"
    end

    if #redacted > 180 then
        redacted = redacted:sub(1, 177) .. "..."
    end

    return redacted
end

local function getUrlExtension(url)
    local stripped = stripUrlQuery(url)
    if type(stripped) ~= "string" then
        return nil
    end
    return stripped:match("%.([%w]+)$")
end

local function isObviousPageUrl(url)
    local extension = getUrlExtension(url)
    if type(extension) ~= "string" then
        return false
    end

    local lower = extension:lower()
    return lower == "html"
        or lower == "htm"
        or lower == "php"
        or lower == "asp"
        or lower == "aspx"
        or lower == "jsp"
        or lower == "txt"
        or lower == "json"
        or lower == "xml"
end

local function resolvePreset(url, title, filter, video)
    if url == "random" then
        url = getRandomPreset()
    end

    if Config.presets[url] then
        return Config.presets[url]
    end

    return {
        url = url,
        title = title,
        filter = filter,
        video = video,
    }
end

local function parseOffset(value)
    local offset = tonumber(value)
    if not offset then
        return 0
    end
    if offset < 0 then
        return 0
    end
    return offset
end

local function normalizeDuration(value)
    local duration = tonumber(value)
    if duration and duration > 0 then
        return duration
    end
    return nil
end

local function normalizeAudioTrackSelection(value)
    if value == nil then
        return nil
    end

    local selection = {}
    if type(value) == "number" or type(value) == "string" then
        selection.index = math.floor(tonumber(value) or -1)
    elseif type(value) == "table" then
        local rawIndex = value.index
            or value.audioTrackIndex
            or value.trackIndex
            or value.id
        local index = tonumber(rawIndex)
        if index and index >= 0 then
            selection.index = math.floor(index)
        end

        local function copyString(targetKey, sourceKey)
            if type(value[sourceKey]) == "string" and value[sourceKey] ~= "" then
                selection[targetKey] = value[sourceKey]:sub(1, 128)
            end
        end

        copyString("id", "id")
        copyString("label", "label")
        copyString("name", "name")
        copyString("language", "language")
        copyString("language", "lang")
        copyString("groupId", "groupId")
    end

    if selection.index == nil
        and selection.id == nil
        and selection.language == nil
        and selection.label == nil
        and selection.name == nil then
        return nil
    end

    return selection
end

local function clampTransitionSeconds(value)
    local maxTransition = tonumber(Config.maxTransitionSeconds) or 8.0
    local defaultTransition = tonumber(Config.defaultTransitionSeconds) or 2.0
    return Clamp(tonumber(value), 0.0, maxTransition, defaultTransition)
end

local function getConfiguredMaxRange()
    return tonumber(Config.maxRange) or 200.0
end

local function getConfiguredAdminMaxRange()
    local base = getConfiguredMaxRange()
    local admin = tonumber(Config.adminMaxRange)
    if not admin or admin < base then
        return base
    end
    return admin
end

local function getAllowedRangeForPlayer(src)
    if HasPmmsPermission(src, "overrideDevice") then
        return getConfiguredAdminMaxRange()
    end
    return getConfiguredMaxRange()
end

getDeviceCapabilityState = function(info, session)
    local sessionSettings = type(session) == "table" and type(session.settings) == "table" and session.settings or nil
    local explicitCapability = nil

    if sessionSettings and type(sessionSettings.deviceCapability) == "string" then
        explicitCapability = sessionSettings.deviceCapability
    elseif type(session) == "table" and type(session.deviceCapability) == "string" then
        explicitCapability = session.deviceCapability
    elseif type(info) == "table" and type(info.deviceCapability) == "string" then
        explicitCapability = info.deviceCapability
    elseif type(info) == "table" and type(info.capabilities) == "table" then
        local caps = info.capabilities
        if caps.video == false and caps.audio ~= false then
            explicitCapability = "audio"
        elseif caps.video == true then
            explicitCapability = "video"
        end
    end

    if explicitCapability == "audio" or explicitCapability == "audio_only" then
        return "audio"
    end
    if explicitCapability == "video" or explicitCapability == "screen" then
        return "video"
    end

    if sessionSettings and sessionSettings.isVehicle == true then
        return "audio"
    end

    if type(info) == "table" and info.isVehicle == true then
        return "audio"
    end

    return "video"
end

local function nextDeviceSessionRevision()
    deviceSessionRevision = deviceSessionRevision + 1
    return deviceSessionRevision
end

local function buildRuntimeSettings(options)
    options = options or {}
    local attenuation = options.attenuation or {}

    return {
        volume = Clamp(tonumber(options.volume), 0, 100, tonumber(Config.defaultVolume) or 100),
        attenuation = {
            sameRoom = Clamp(tonumber(attenuation.sameRoom), 0.0, 10.0, tonumber(Config.defaultSameRoomAttenuation) or 4.0),
            diffRoom = Clamp(tonumber(attenuation.diffRoom), 0.0, 10.0, tonumber(Config.defaultDiffRoomAttenuation) or 6.0),
        },
        diffRoomVolume = Clamp(tonumber(options.diffRoomVolume), 0.0, 1.0, tonumber(Config.defaultDiffRoomVolume) or 0.25),
        range = Clamp(tonumber(options.range), 0.0, getConfiguredAdminMaxRange(), tonumber(Config.defaultRange) or 30.0),
        transitionSeconds = clampTransitionSeconds(options.transitionSeconds),
        isVehicle = options.isVehicle == true or Config.defaultVehicleMode == true,
        loopMode = NormalizeLoopMode(options.loopMode, options.loop),
        label = options.label or options.name,
        profile = options.profile,
        persistent = options.persistent == true,
        mode = options.mode,
        propModel = options.propModel,
        coords = cloneDeepTable(options.coords or options.position),
        requestMode = options.requestMode,
        adminLock = cloneDeepTable(options.adminLock),
        linkedSpeakers = cloneDeepTable(options.linkedSpeakers),
        equalizerProfile = cloneDeepTable(options.equalizerProfile),
        vehiclePlate = options.vehiclePlate,
    }
end

local function mergePersistentSeed(handle, seedOptions)
    local seed = cloneDeepTable(seedOptions or {})
    if type(GetPersistentPmmsDeviceEntry) ~= "function" then
        return seed
    end

    local entry = GetPersistentPmmsDeviceEntry(handle)
    if type(entry) ~= "table" then
        return seed
    end

    for key, value in pairs(entry) do
        if seed[key] == nil then
            seed[key] = cloneDeepTable(value)
        end
    end

    if seed.coords == nil then
        seed.coords = type(ToPlainCoords) == "function" and ToPlainCoords(entry.position) or cloneDeepTable(entry.position)
    end
    seed.persistent = true
    return seed
end

local function buildTrackSnapshot(options)
    if type(options) ~= "table" or type(options.url) ~= "string" or options.url == "" then
        return nil
    end

    local snapshot = {
        url = options.originalUrl or options.url,
        title = options.title or options.url,
        duration = normalizeDuration(options.duration),
        author = options.author,
        thumbnail = options.thumbnail,
        live = options.live == true,
        volume = options.volume,
        offset = 0,
        filter = options.filter,
        video = options.video,
        visualization = options.visualization,
        originalUrl = options.originalUrl,
        resolvedUrl = options.resolvedUrl,
        resolver = cloneDeepTable(options.resolver),
        directLink = cloneDeepTable(options.directLink),
        audioTracks = cloneDeepTable(options.audioTracks),
        audioTrack = cloneDeepTable(options.audioTrack or options.selectedAudioTrack),
        selectedAudioTrack = cloneDeepTable(options.selectedAudioTrack or options.audioTrack),
        playbackToken = options.playbackToken,
    }

    snapshot.originalUrl = options.originalUrl or snapshot.url
    snapshot.resolvedUrl = options.resolvedUrl or options.url
    snapshot.resolver = snapshot.resolver or { status = "unknown" }
    snapshot.resolverStatus = snapshot.resolver.status or "unknown"
    snapshot.resolverReason = snapshot.resolver.reason or "unknown"
    snapshot.resolverWarning = snapshot.resolver.warning
    snapshot.resolverFallback = snapshot.resolverStatus == "fallback"
    return snapshot
end

local function applySessionSettingsToTarget(target, session)
    if type(target) ~= "table" or type(session) ~= "table" or type(session.settings) ~= "table" then
        return
    end

    target.volume = session.settings.volume
    target.attenuation = cloneDeepTable(session.settings.attenuation)
    target.diffRoomVolume = session.settings.diffRoomVolume
    target.range = session.settings.range
    target.transitionSeconds = session.settings.transitionSeconds
    target.isVehicle = session.settings.isVehicle == true
    target.loopMode = NormalizeLoopMode(session.settings.loopMode, target.loop)
    target.loop = target.loopMode == "track"
    target.label = session.settings.label or target.label
    target.profile = session.settings.profile or target.profile
    target.persistent = session.settings.persistent == true or target.persistent == true
    target.mode = session.settings.mode or target.mode
    target.propModel = session.settings.propModel or target.propModel
    target.coords = cloneDeepTable(session.settings.coords or target.coords)
    target.requestMode = session.settings.requestMode or target.requestMode
    target.adminLock = cloneDeepTable(session.settings.adminLock or target.adminLock)
    target.linkedSpeakers = cloneDeepTable(session.settings.linkedSpeakers or target.linkedSpeakers)
    target.equalizerProfile = cloneDeepTable(session.settings.equalizerProfile or target.equalizerProfile)
    target.vehiclePlate = session.settings.vehiclePlate or target.vehiclePlate
end

local function syncActiveMediaPlayerWithSession(handle, session)
    local mp = GetMediaPlayer(handle)
    if not mp or type(session) ~= "table" then
        return
    end

    applySessionSettingsToTarget(mp, session)
    mp.queue = session.queue
    mp.stateRevision = session.stateRevision
end

commitDeviceSession = function(handle, session)
    if type(session) ~= "table" then
        return nil
    end

    session.handle = handle
    session.updatedAt = os.time()
    session.stateRevision = nextDeviceSessionRevision()
    deviceSessions[handle] = session
    syncActiveMediaPlayerWithSession(handle, session)
    MarkDirty()
    return session
end

local function buildDeviceSession(handle, seedOptions)
    seedOptions = mergePersistentSeed(handle, seedOptions)
    local defaults = buildRuntimeSettings(seedOptions)

    return {
        handle = handle,
        defaults = cloneDeepTable(defaults),
        settings = cloneDeepTable(defaults),
        queue = {},
        history = {},
        currentTrack = nil,
        playerTemplate = nil,
        nextQueueEntryId = 0,
        shufflePreviewIds = {},
        idleResetAt = nil,
        resetActive = false,
        stateRevision = nextDeviceSessionRevision(),
        createdAt = os.time(),
        updatedAt = os.time(),
    }
end

function GetDeviceSession(handle)
    return deviceSessions[handle]
end

function GetDeviceSessions()
    return deviceSessions
end

function CommitDeviceSessionState(handle)
    local session = deviceSessions[handle]
    if not session then
        return nil
    end
    return commitDeviceSession(handle, session)
end

function EnsureDeviceSession(handle, seedOptions)
    local session = deviceSessions[handle]
    if session then
        seedOptions = mergePersistentSeed(handle, seedOptions)
        if type(session.queue) ~= "table" then
            session.queue = {}
        end
        if type(session.history) ~= "table" then
            session.history = {}
        end
        session.nextQueueEntryId = tonumber(session.nextQueueEntryId) or 0
        session.shufflePreviewIds = type(session.shufflePreviewIds) == "table" and session.shufflePreviewIds or {}
        if type(session.defaults) ~= "table" then
            session.defaults = buildRuntimeSettings(seedOptions)
        end
        if type(session.settings) ~= "table" then
            session.settings = cloneDeepTable(session.defaults)
        end
        local persistentDefaults = buildRuntimeSettings(seedOptions)
        for key, value in pairs(persistentDefaults) do
            if session.defaults[key] == nil then
                session.defaults[key] = cloneDeepTable(value)
            end
            if session.settings[key] == nil then
                session.settings[key] = cloneDeepTable(value)
            end
        end
        return session
    end

    session = buildDeviceSession(handle, seedOptions)
    deviceSessions[handle] = session
    MarkDirty()
    return session
end

local function cancelDeviceIdleReset(handle)
    local session = deviceSessions[handle]
    if not session then
        return
    end

    if session.idleResetAt ~= nil or session.resetActive == true then
        session.idleResetAt = nil
        session.resetActive = false
        commitDeviceSession(handle, session)
    end
end

local function startDeviceIdleReset(handle, now)
    local session = deviceSessions[handle]
    if not session then
        return
    end

    local idleSeconds = math.max(1, tonumber(Config.deviceIdleResetSeconds) or 300)
    session.idleResetAt = (now or os.time()) + idleSeconds
    session.resetActive = true
    session.currentTrack = nil
    commitDeviceSession(handle, session)
end

function ResetDeviceSession(handle)
    if IsMediaPlayerActive(handle) or startContexts[handle] then
        return false
    end

    if deviceSessions[handle] then
        deviceSessions[handle] = nil
        MarkDirty()
    end

    clearSessionLock(handle)
    return true
end

function CleanupDeviceSessions(now)
    now = now or os.time()
    local expiredHandles = {}

    for handle, session in pairs(deviceSessions) do
        if not IsMediaPlayerActive(handle)
            and not startContexts[handle]
            and session.idleResetAt
            and now >= session.idleResetAt then
            expiredHandles[#expiredHandles + 1] = handle
        end
    end

    for _, handle in ipairs(expiredHandles) do
        ResetDeviceSession(handle)
    end
end

local function pushDeviceHistoryEntry(handle, options)
    local snapshot = buildTrackSnapshot(options)
    if not snapshot then
        return
    end

    local session = EnsureDeviceSession(handle, options)
    local history = session.history or {}
    history[#history + 1] = snapshot

    while #history > maxDeviceHistoryEntries do
        table.remove(history, 1)
    end

    session.history = history
    session.currentTrack = nil
    commitDeviceSession(handle, session)
end

function PopDeviceHistoryEntry(handle)
    local session = deviceSessions[handle]
    if not session or type(session.history) ~= "table" or #session.history <= 0 then
        return nil
    end

    local entry = table.remove(session.history)
    session.currentTrack = nil
    commitDeviceSession(handle, session)
    return cloneDeepTable(entry)
end

function PrependDeviceQueueEntry(handle, sourceId, options)
    local snapshot = buildTrackSnapshot(options)
    if not snapshot then
        return
    end

    local session = EnsureDeviceSession(handle, options)
    local queue = session.queue or {}
    table.insert(queue, 1, {
        source = sourceId,
        name = sourceId and GetPlayerName(sourceId) or nil,
        options = snapshot,
    })
    session.queue = queue
    commitDeviceSession(handle, session)
end

local function setDeviceSessionCurrentTrack(handle, options)
    local session = EnsureDeviceSession(handle, options)
    session.currentTrack = buildTrackSnapshot(options)
    session.playerTemplate = cloneDeepTable(options)
    if options and options.lastSource then
        session.lastSource = tonumber(options.lastSource) or session.lastSource
    end
    session.resetActive = false
    session.idleResetAt = nil
    commitDeviceSession(handle, session)
end

local function isLockedDefaultMediaPlayer(handle)
    for _, mp in ipairs(Config.defaultMediaPlayers) do
        if handle == GetHandleFromCoords(mp.position) and mp.locked then
            return true
        end
    end
    return false
end

local function addFallbackWarningNotification(src, warning)
    local resolverConfig = Config.resolver or {}
    if warning and resolverConfig.warnOnFallback ~= false then
        TriggerClientEvent("pmms:notify", src, {
            title = "7-PMMS",
            text = warning,
            color = "#ffaa00",
            duration = 6500,
        })
    end
end

local function normalizeYoutubeResolverProvider(value)
    if type(value) ~= "string" then
        return nil
    end

    local provider = value:lower():gsub("%s+", "_"):gsub("%-", "_")
    if provider == "" or provider == "auto" then
        return "auto"
    end
    if provider == "youtube" or provider == "youtube_embed" or provider == "embed" then
        return "embed"
    end
    if provider == "yt_dlp" or provider == "ytdlp" or provider == "yt_dlp_local" then
        return "yt_dlp_local"
    end
    if provider == "extractor" or provider == "extractor_http" then
        return "extractor_http"
    end
    if provider == "cobalt" or provider == "invidious" or provider == "piped" then
        return provider
    end

    return nil
end

local function getRequestedYoutubeResolverProvider(options)
    if type(options) ~= "table" then
        return nil, false
    end

    local raw = options.youtubeProvider
        or options.youtubeResolverProvider
        or options.resolverProvider
        or options.provider
    local provider = normalizeYoutubeResolverProvider(raw)
    local explicit = provider ~= nil or options.youtubeProviderExplicit == true
    return provider, explicit
end

local function buildEffectiveResolverOptions(options, resolverOptions)
    local effective = cloneDeepTable(resolverOptions or {})
    local provider, explicit = getRequestedYoutubeResolverProvider(options)

    if provider and provider ~= "auto" then
        effective.forceProvider = provider
        effective.forceRefresh = true
        effective.allowAudioFallback = false
        if provider == "embed" then
            effective.allowFallback = true
            effective.allowEmbedFallback = true
        else
            effective.allowEmbedFallback = false
        end
    elseif explicit then
        effective.allowEmbedFallback = false
    end

    return effective
end

local function isEmbedResolver(resolver)
    if type(resolver) ~= "table" then
        return false
    end

    return resolver.provider == "embed"
        or resolver.instance == "youtube_embed"
        or resolver.status == "fallback"
end

local function isExplicitEmbedProvider(options)
    local provider, explicit = getRequestedYoutubeResolverProvider(options)
    return explicit == true and provider == "embed"
end

local function isRetryableEmbedFallbackFailure(reason, options, resolver)
    return reason == "youtube_embed_blocked"
        and isEmbedResolver(resolver)
        and not isExplicitEmbedProvider(options)
end

local function getRetryMaxInstances(resolverConfig, widenSearch)
    local configured = tonumber(resolverConfig and resolverConfig.maxInstances) or 6
    if widenSearch then
        return math.max(12, configured)
    end
    return math.max(6, configured)
end

local function recordAutoProviderPlayback(options, resolver, outcome, reason, context)
    if type(RecordResolverProviderPlayback) ~= "function"
        or type(options) ~= "table"
        or type(resolver) ~= "table"
        or type(resolver.provider) ~= "string"
        or resolver.provider == "" then
        return
    end

    local provider, explicit = getRequestedYoutubeResolverProvider(options)
    if provider and provider ~= "auto" then
        return
    end
    if explicit and provider ~= "auto" then
        return
    end

    local sourceUrl = options.originalUrl or options.url
    if not isYoutubeLikeUrl(sourceUrl) then
        return
    end

    local elapsedMs = 0
    if context and context.createdAt then
        elapsedMs = math.max(0, (os.time() - context.createdAt) * 1000)
    end

    RecordResolverProviderPlayback(resolver.provider, resolver.instance, outcome, elapsedMs, reason)
end

local function resolvePlaybackAndNotify(src, options, resolverOptions, callback)
    if type(ResolvePlaybackOptions) ~= "function" then
        PMMSDebug("resolver", "resolver function unavailable, using original options", {
            src = src,
            url = redactUrlForDebug(options and options.url or nil),
        })
        callback(true, cloneTable(options), nil)
        return
    end

    resolverOptions = buildEffectiveResolverOptions(options, resolverOptions)
    local notifyOnFailure = resolverOptions == nil or resolverOptions.notifyOnFailure ~= false
    PMMSDebug("resolver", "resolve requested", {
        src = src,
        url = redactUrlForDebug(options and options.url or nil),
        originalUrl = redactUrlForDebug(options and options.originalUrl or nil),
        forceRefresh = resolverOptions and resolverOptions.forceRefresh == true,
        forceProvider = resolverOptions and resolverOptions.forceProvider or nil,
        avoidProvider = resolverOptions and resolverOptions.avoidProvider or nil,
        avoidInstance = resolverOptions and resolverOptions.avoidInstance or nil,
        allowAudioFallback = resolverOptions and resolverOptions.allowAudioFallback,
        allowEmbedFallback = resolverOptions and resolverOptions.allowEmbedFallback,
    })
    ResolvePlaybackOptions(options, resolverOptions or {}, function(ok, resolvedOptions, warning)
        if not ok or type(resolvedOptions) ~= "table" then
            PMMSDebug("resolver", "resolve failed", {
                src = src,
                url = redactUrlForDebug(options and options.url or nil),
                warning = warning,
            })
            if notifyOnFailure then
                TriggerClientEvent("pmms:error", src, warning or "Unable to resolve media URL.")
            end
            callback(false, nil, warning)
            return
        end

        local resolver = type(resolvedOptions.resolver) == "table" and resolvedOptions.resolver or {}
        PMMSDebug("resolver", "resolve succeeded", {
            src = src,
            url = redactUrlForDebug(options and options.url or nil),
            resolvedUrl = redactUrlForDebug(resolvedOptions.resolvedUrl or resolvedOptions.url),
            status = resolver.status,
            provider = resolver.provider,
            instance = resolver.instance,
            reason = resolver.reason,
            warning = warning,
        })
        addFallbackWarningNotification(src, warning)
        callback(true, resolvedOptions, warning)
    end)
end

local function applyResolvedMetadata(target, source)
    source = source or {}

    target.originalUrl = source.originalUrl or target.originalUrl or source.url or target.url
    target.resolvedUrl = source.resolvedUrl or target.resolvedUrl or source.url or target.url
    target.resolver = source.resolver or target.resolver or { status = "unknown" }
    target.resolverStatus = target.resolver.status or target.resolverStatus or "unknown"
    target.resolverReason = target.resolver.reason or target.resolverReason or "unknown"
    target.resolverWarning = target.resolver.warning or target.resolverWarning
    target.resolverFallback = target.resolverStatus == "fallback"
    target.audioUrl = source.audioUrl or target.audioUrl
    target.pairedStreams = source.pairedStreams == true or target.pairedStreams == true
    target.videoMime = source.videoMime or target.videoMime
    target.audioMime = source.audioMime or target.audioMime
    if type(source.audioTracks) == "table" then
        target.audioTracks = cloneDeepTable(source.audioTracks)
    end
    local audioTrack = normalizeAudioTrackSelection(source.audioTrack or source.selectedAudioTrack)
    if audioTrack then
        target.audioTrack = audioTrack
        target.selectedAudioTrack = cloneDeepTable(audioTrack)
    end
end

local function jsonEquivalent(left, right)
    if left == right then
        return true
    end
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end

    local okLeft, encodedLeft = pcall(json.encode, left)
    local okRight, encodedRight = pcall(json.encode, right)
    return okLeft and okRight and encodedLeft == encodedRight
end

local function applyPlaybackMetadata(target, details)
    if type(target) ~= "table" or type(details) ~= "table" then
        return false
    end

    local changed = false
    local duration = normalizeDuration(details.duration)
    if duration and tonumber(target.duration) ~= duration then
        target.duration = duration
        changed = true
    elseif details.live == true and target.duration ~= nil then
        target.duration = nil
        changed = true
    end

    if details.live == true or details.live == false then
        if target.live ~= (details.live == true) then
            target.live = details.live == true
            changed = true
        end
    end

    if type(details.title) == "string" and details.title ~= "" and details.title ~= target.url and target.title ~= details.title then
        target.title = details.title
        changed = true
    end
    if type(details.author) == "string" and details.author ~= "" and target.author ~= details.author then
        target.author = details.author
        changed = true
    end
    if type(details.thumbnail) == "string" and details.thumbnail ~= "" and target.thumbnail ~= details.thumbnail then
        target.thumbnail = details.thumbnail
        changed = true
    end
    if details.video == false and target.video ~= false then
        target.video = false
        changed = true
    elseif details.video == true and target.video ~= true then
        target.video = true
        changed = true
    end

    if type(details.audioTracks) == "table" then
        if not jsonEquivalent(target.audioTracks, details.audioTracks) then
            target.audioTracks = cloneDeepTable(details.audioTracks)
            changed = true
        end
    end

    local selectedAudioTrack = normalizeAudioTrackSelection(
        details.audioTrack
            or details.selectedAudioTrack
            or details.audioTrackIndex
    )
    if selectedAudioTrack then
        if not jsonEquivalent(target.audioTrack, selectedAudioTrack)
            or not jsonEquivalent(target.selectedAudioTrack, selectedAudioTrack) then
            target.audioTrack = cloneDeepTable(selectedAudioTrack)
            target.selectedAudioTrack = cloneDeepTable(selectedAudioTrack)
            changed = true
        end
    end

    return changed
end

local function beginStartContext(handle, src, options, retries)
    local playbackToken = options and options.playbackToken or nil
    if type(playbackToken) ~= "string" or playbackToken == "" then
        playbackToken = createPlaybackToken(handle)
    end

    local initialOptions = applyPlaybackToken(cloneDeepTable(options), playbackToken)
    local context = {
        handle = handle,
        source = src,
        options = initialOptions,
        currentOptions = cloneDeepTable(initialOptions),
        currentAttemptId = createStartAttemptId(handle),
        playbackToken = playbackToken,
        createdAt = os.time(),
        updatedAt = os.time(),
        retries = tonumber(retries) or 0,
        lastResolvedUrl = nil,
        lastProvider = nil,
        lastInstance = nil,
        lastResolverStatus = nil,
        errorHistory = {},
        audioFallbackAttempted = options and options.video == false or false,
        embedFallbackUsed = false,
    }

    startContexts[handle] = context
    SetRestricted(handle, src)
    PMMSDebug("player", "start context created", {
        handle = handle,
        src = src,
        attemptId = context.currentAttemptId,
        playbackToken = context.playbackToken,
        url = redactUrlForDebug(initialOptions.url),
        originalUrl = redactUrlForDebug(initialOptions.originalUrl),
        title = initialOptions.title,
        video = initialOptions.video,
    })
    return context
end

local function updateStartContextResolved(handle, resolvedOptions)
    local context = startContexts[handle]
    if not context then
        return nil
    end

    local resolved = applyPlaybackToken(resolvedOptions or context.currentOptions or context.options or {}, context.playbackToken)
    context.currentOptions = cloneDeepTable(resolved)
    context.lastResolvedUrl = resolved.resolvedUrl or resolved.url or context.lastResolvedUrl
    context.lastProvider = resolved.resolver and resolved.resolver.provider or context.lastProvider or nil
    context.lastInstance = resolved.resolver and resolved.resolver.instance or context.lastInstance or nil
    context.lastResolverStatus = resolved.resolver and resolved.resolver.status or context.lastResolverStatus or nil
    context.embedFallbackUsed = context.embedFallbackUsed == true
        or (resolved.resolver and resolved.resolver.status == "fallback")
    context.updatedAt = os.time()
    startContexts[handle] = context
    PMMSDebug("player", "start context resolved", {
        handle = handle,
        attemptId = context.currentAttemptId,
        url = redactUrlForDebug(resolved.originalUrl or resolved.url),
        resolvedUrl = redactUrlForDebug(resolved.resolvedUrl or resolved.url),
        provider = context.lastProvider,
        instance = context.lastInstance,
        resolverStatus = context.lastResolverStatus,
        fallbackUsed = context.embedFallbackUsed,
    })
    return context
end

local function rotateStartAttempt(handle)
    local context = startContexts[handle]
    if not context then
        return nil, nil
    end

    local previousAttemptId = context.currentAttemptId
    context.currentAttemptId = createStartAttemptId(handle)
    context.updatedAt = os.time()
    startContexts[handle] = context
    return context, previousAttemptId
end

local function clearStartContext(handle, preserveStartupState, notifyClient)
    local context = startContexts[handle]
    startContexts[handle] = nil

    if context and notifyClient ~= false and context.source and context.currentAttemptId then
        TriggerClientEvent("pmms:startupStop", context.source, handle, context.currentAttemptId, context.playbackToken)
    end

    if not preserveStartupState then
        clearStartupState(handle)
    end
end

local function cancelStartupForSource(src, handle, attemptId, playbackToken)
    handle = tonumber(handle)
    if not handle then
        PMMSDebug("player", "cancel startup ignored: invalid handle", {
            src = src,
            handle = handle,
            attemptId = attemptId,
        })
        return false
    end

    local startupContext = startContexts[handle]
    if not startupContext then
        PMMSDebug("player", "cancel startup ignored: no active start context", {
            src = src,
            handle = handle,
            attemptId = attemptId,
        })
        return false
    end

    if not requirePermission(src, handle, "interact") then
        PMMSDebug("player", "cancel startup rejected: permission denied", {
            src = src,
            handle = handle,
            owner = startupContext.source,
            attemptId = attemptId,
        })
        return false
    end

    if startupContext.source ~= src and not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "This player is busy")
        PMMSDebug("player", "cancel startup rejected: source mismatch", {
            src = src,
            owner = startupContext.source,
            handle = handle,
            attemptId = attemptId,
        })
        return false
    end

    if attemptId ~= nil
        and tostring(attemptId) ~= ""
        and tostring(startupContext.currentAttemptId) ~= tostring(attemptId) then
        PMMSDebug("player", "cancel startup ignored: stale attempt", {
            src = src,
            handle = handle,
            requestedAttemptId = attemptId,
            currentAttemptId = startupContext.currentAttemptId,
        })
        return false
    end

    if type(playbackToken) == "string"
        and playbackToken ~= ""
        and tostring(startupContext.playbackToken) ~= tostring(playbackToken) then
        PMMSDebug("player", "cancel startup ignored: stale playback token", {
            src = src,
            handle = handle,
            requestedToken = playbackToken,
            currentToken = startupContext.playbackToken,
        })
        return false
    end

    local currentAttemptId = startupContext.currentAttemptId
    local currentPlaybackToken = startupContext.playbackToken
    local retryCount = tonumber(startupContext.retries) or 0

    clearStartContext(handle, false, true)
    ClearRestricted(handle)
    expireStartupState(handle, "stopped", "Playback startup was cancelled.", {
        attemptId = currentAttemptId,
        playbackToken = currentPlaybackToken,
        retryCount = retryCount,
    }, 4)
    PMMSDebug("player", "startup cancelled", {
        src = src,
        handle = handle,
        attemptId = currentAttemptId,
        playbackToken = currentPlaybackToken,
        retryCount = retryCount,
    })
    return true
end

function CleanupPendingStarts(now)
    now = now or os.time()

    for handle, context in pairs(startContexts) do
        if not context.createdAt or (now - context.createdAt) > getStartContextTtlSeconds() then
            local src = context.source
            local attemptId = context.currentAttemptId
            clearStartContext(handle, true, true)
            expireStartupState(handle, "timed_out", "Playback startup timed out.", {
                attemptId = attemptId,
                playbackToken = context.playbackToken,
                retryCount = tonumber(context.retries) or 0,
            }, 8)
            if src and GetPlayerName(src) then
                TriggerClientEvent("pmms:error", src, "Playback startup timed out.")
            end
        end
    end

    for handle, state in pairs(startupStates) do
        if state.expiresAt and now >= state.expiresAt then
            clearStartupState(handle)
        end
    end
end

local function classifyPlaybackError(message)
    local text = type(message) == "string" and message:lower() or ""
    if text == "" then
        return "unknown"
    end
    if text:find("pipeline_error_read", 1, true)
        or text:find("ffmpegdemuxer", 1, true)
        or text:find("data source error", 1, true)
        or text:find("mediaerrorcode=2", 1, true)
        or text:find("networkstate=3", 1, true)
        or text:find("net::", 1, true)
        or text:find("err_", 1, true)
        or text:find("read failure", 1, true)
        or text:find("failed to fetch", 1, true) then
        return "stream_read_failure"
    end
    if text:find("youtube error 101", 1, true)
        or text:find("youtube error 150", 1, true)
        or text:find("blocked embedded", 1, true)
        or text:find("embedded youtube playback is blocked", 1, true)
        or text:find("youtube playback is blocked", 1, true)
        or text:find("video unavailable", 1, true) then
        return "youtube_embed_blocked"
    end
    if text:find("youtube error 100", 1, true) then
        return "youtube_not_found"
    end
    if text:find("media error code", 1, true)
        or text:find("format error", 1, true)
        or text:find("unknown playback error", 1, true)
        or text:find("html5 playback error", 1, true) then
        return "stream_decode_failure"
    end
    return "unknown"
end

local function isTwitchLikeUrl(url)
    if type(url) ~= "string" then
        return false
    end

    local lower = url:lower()
    return lower:find("twitch%.tv", 1, false) ~= nil
end

local function getDirectLinkConfig()
    return type(Config.directLinks) == "table" and Config.directLinks or {}
end

local function isAllowedDirectLinkExtension(extension)
    if type(extension) ~= "string" or extension == "" then
        return false
    end

    local allowed = getDirectLinkConfig().allowedExtensions
    if type(allowed) ~= "table" then
        return false
    end

    local lower = extension:lower()
    for _, value in ipairs(allowed) do
        if type(value) == "string" and value:lower() == lower then
            return true
        end
    end

    return false
end

local function decodeUrlComponent(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end

    local decoded = value:gsub("+", " ")
    decoded = decoded:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return decoded
end

local function extractNestedDirectLinkUrl(url)
    if type(url) ~= "string" or url == "" then
        return nil
    end

    local query = url:match("%?([^#]+)")
    if type(query) ~= "string" or query == "" then
        return nil
    end

    local candidateKeys = {
        url = true,
        u = true,
        src = true,
        source = true,
        media = true,
        stream = true,
        target = true,
    }

    for pair in query:gmatch("[^&]+") do
        local rawKey, rawValue = pair:match("^([^=]+)=?(.*)$")
        local key = rawKey and decodeUrlComponent(rawKey)
        if key and candidateKeys[key:lower()] and type(rawValue) == "string" and rawValue ~= "" then
            local decoded = rawValue
            for _ = 1, 2 do
                local nextDecoded = decodeUrlComponent(decoded)
                if not nextDecoded or nextDecoded == decoded then
                    break
                end
                decoded = nextDecoded
            end

            if type(decoded) == "string"
                and decoded:match("^https?://")
                and not decoded:find("[%c<>\"'`]", 1, false)
                and not decoded:find("^https?://[^/]-@", 1, false)
                and not isYoutubeLikeUrl(decoded)
                and not isTwitchLikeUrl(decoded) then
                local extension = getUrlExtension(decoded)
                if extension and isAllowedDirectLinkExtension(extension) then
                    return decoded
                end
            end
        end
    end

    return nil
end

local function getDirectLinkPlaybackMode(extension, contentType)
    local lowerExt = type(extension) == "string" and extension:lower() or ""
    local lowerType = type(contentType) == "string" and contentType:lower() or ""

    if lowerExt == "mp4" or lowerExt == "m4v" or lowerExt == "webm" or lowerExt == "ogv" or lowerExt == "m3u8" then
        return "video"
    end

    if lowerExt == "mp3" or lowerExt == "m4a" or lowerExt == "aac" or lowerExt == "wav" or lowerExt == "oga" then
        return "audio"
    end

    if lowerExt == "ogg" then
        if lowerType:find("video/", 1, true) == 1 then
            return "video"
        end
        return "audio"
    end

    if lowerType:find("mpegurl", 1, true)
        or lowerType:find("application/vnd.apple.mpegurl", 1, true)
        or lowerType:find("application/x-mpegurl", 1, true) then
        return "video"
    end

    if lowerType:find("video/", 1, true) == 1 then
        return "video"
    end

    if lowerType:find("audio/", 1, true) == 1 or lowerType == "application/ogg" then
        return "audio"
    end

    return nil
end

local function isLikelyHtmlResponse(body)
    if type(body) ~= "string" then
        return false
    end

    local head = body:sub(1, 512):lower()
    return head:find("<!doctype html", 1, true) ~= nil
        or head:find("<html", 1, true) ~= nil
end

local function isHlsManifestBody(body)
    if type(body) ~= "string" then
        return false
    end

    return body:sub(1, 1024):find("#EXTM3U", 1, true) ~= nil
end

local function extractHeaderValue(headers, name)
    if type(headers) ~= "table" or type(name) ~= "string" then
        return nil
    end

    local target = name:lower()
    for key, value in pairs(headers) do
        if tostring(key):lower() == target then
            if type(value) == "table" then
                value = value[1]
            end
            if type(value) == "string" and value ~= "" then
                return value
            end
        end
    end

    return nil
end

local function isClearlyInvalidDirectLinkUrl(url)
    if type(url) ~= "string" then
        return true
    end

    if url:find("[%c<>\"'`]", 1, false) then
        return true
    end

    if url:find("^https?://[^/]-@", 1, false) then
        return true
    end

    return false
end

local function isDirectLinkCandidate(url)
    if type(url) ~= "string" or not url:match("^https?://") then
        return false
    end

    local extension = getUrlExtension(url)
    if type(extension) ~= "string" or extension == "" then
        return false
    end

    return not isYoutubeLikeUrl(url) and not isTwitchLikeUrl(url)
end

local function validateAndTagDirectLink(url, prepared)
    if not isDirectLinkCandidate(url) then
        local isRadioDirect = type(prepared) == "table" and (prepared.source == "radio" or prepared.radio == true)
        if isRadioDirect and type(url) == "string" and url:match("^https?://") and not isYoutubeLikeUrl(url) and not isTwitchLikeUrl(url) then
            local directLinkConfig = getDirectLinkConfig()
            if directLinkConfig.requireHttps ~= false and not url:match("^https://") then
                return false, "Direct radio links must use HTTPS on this server."
            end
            if isClearlyInvalidDirectLinkUrl(url) then
                return false, "This radio stream URL looks unsafe or malformed."
            end
            prepared.directLink = {
                candidate = true,
                extension = (getUrlExtension(url) or "radio"):lower(),
                radio = true,
            }
            prepared.video = false
            prepared.live = true
        end
        return true, nil
    end

    local directLinkConfig = getDirectLinkConfig()
    if directLinkConfig.requireHttps ~= false and not url:match("^https://") then
        return false, "Direct links must use HTTPS."
    end

    if isClearlyInvalidDirectLinkUrl(url) then
        return false, "This direct link looks unsafe or malformed."
    end

    if isObviousPageUrl(url) then
        return false, "This URL points to a webpage, not a direct media file."
    end

    local extension = getUrlExtension(url)
    if type(extension) ~= "string" or extension == "" then
        return false, "Direct links must end with a supported media file extension."
    end

    local lowerExtension = extension:lower()
    if not isAllowedDirectLinkExtension(lowerExtension) then
        return false, "This direct-link format is not supported."
    end

    prepared.directLink = {
        candidate = true,
        extension = lowerExtension,
    }

    local playbackMode = getDirectLinkPlaybackMode(lowerExtension, nil)
    if playbackMode == "audio" then
        prepared.video = false
    elseif playbackMode == "video" and prepared.video == nil then
        prepared.video = true
    end

    return true, nil
end

local function probePreparedDirectLink(prepared, callback)
    local directLink = prepared and prepared.directLink
    if type(directLink) ~= "table" or directLink.candidate ~= true then
        callback(true, prepared, nil)
        return
    end

    local url = prepared.url
    local extension = directLink.extension
    local timeoutMs = math.max(1000, tonumber(getDirectLinkConfig().probeTimeoutMs) or 2500)
    local requestOptions = { timeout = math.floor(timeoutMs) }

    local function finalizeSuccess(contentType)
        local playbackMode = getDirectLinkPlaybackMode(extension, contentType)
        if playbackMode == "audio" then
            prepared.video = false
        elseif playbackMode == "video" then
            prepared.video = true
        else
            callback(false, nil, "This direct link is secure but the format is not playable by the DUI.")
            return
        end

        directLink.validated = true
        directLink.contentType = contentType
        prepared.directLink = directLink
        callback(true, prepared, nil)
    end

    local function handleProbeResult(statusCode, body, headers, followUp)
        local status = tonumber(statusCode) or 0
        if status >= 300 and status < 400 and followUp ~= true then
            callback(false, nil, "Redirected direct links are not supported.")
            return true
        end
        if status <= 0 or status >= 400 then
            return false
        end

        local contentType = extractHeaderValue(headers, "content-type")
        if not contentType or contentType == "" then
            if followUp == true and isLikelyHtmlResponse(body) then
                callback(false, nil, "This direct link does not point to playable media.")
                return true
            end
            if extension == "m3u8" and followUp == true and isHlsManifestBody(body) then
                finalizeSuccess("application/vnd.apple.mpegurl")
                return true
            end
            if followUp == true and isAllowedDirectLinkExtension(extension) then
                finalizeSuccess(nil)
                return true
            end
            return false
        end

        local lowerType = contentType:lower()
        if lowerType:find("text/html", 1, true)
            or lowerType:find("application/json", 1, true)
            or (lowerType:find("text/plain", 1, true) and extension ~= "m3u8")
            or lowerType:find("application/xml", 1, true)
            or lowerType:find("text/xml", 1, true) then
            callback(false, nil, "This direct link does not point to playable media.")
            return true
        end

        if extension == "m3u8" and followUp == true and isHlsManifestBody(body) then
            finalizeSuccess("application/vnd.apple.mpegurl")
            return true
        end

        finalizeSuccess(contentType)
        return true
    end

    PerformHttpRequest(url, function(statusCode, _, headers)
        if handleProbeResult(statusCode, nil, headers, false) then
            return
        end

        PerformHttpRequest(url, function(statusCodeGet, bodyGet, headersGet)
            if handleProbeResult(statusCodeGet, bodyGet, headersGet, true) then
                return
            end

            callback(false, nil, "Could not verify this direct media link.")
        end, "GET", "", {
            ["User-Agent"] = "7-PMMS-DirectLinkProbe",
            ["Accept"] = "audio/*,video/*;q=0.9,*/*;q=0.1",
            ["Range"] = "bytes=0-4095",
        }, requestOptions)
    end, "HEAD", "", {
        ["User-Agent"] = "7-PMMS-DirectLinkProbe",
        ["Accept"] = "audio/*,video/*;q=0.9,*/*;q=0.1",
    }, requestOptions)
end

isYoutubeLikeUrl = function(url)
    if type(url) ~= "string" then
        return false
    end

    local lower = url:lower()
    return lower:find("youtube%.com", 1, false) ~= nil
        or lower:find("youtu%.be", 1, false) ~= nil
end

local function failPlaybackStart(handle, src, message, details)
    local finalMessage = message or "Playback failed after retries. Please try another source."
    if type(details) == "string" and details ~= "" then
        local compact = details:gsub("%s+", " ")
        if #compact > 220 then
            compact = compact:sub(1, 217) .. "..."
        end
        finalMessage = ("%s (%s)"):format(finalMessage, compact)
    end

    local context = startContexts[handle]
    local stateDetails = buildStartupStateDetails(context, context and context.currentOptions or nil)
    stateDetails.message = finalMessage
    PMMSDebug("player", "playback start failed", {
        src = src,
        handle = handle,
        attemptId = context and context.currentAttemptId or nil,
        playbackToken = context and context.playbackToken or nil,
        message = finalMessage,
        details = details,
        provider = stateDetails.provider,
        instance = stateDetails.instance,
        resolverStatus = stateDetails.resolverStatus,
        resolverReason = stateDetails.resolverReason,
        retryCount = stateDetails.retryCount,
    })
    if type(LogPmmsAdminEvent) == "function" then
        LogPmmsAdminEvent("playback_start_failed", handle, src, {
            message = finalMessage,
            details = details,
            provider = stateDetails.provider,
            reason = stateDetails.resolverReason,
        })
    end

    clearStartContext(handle, true, true)
    ClearRestricted(handle)
    if IsMediaPlayerActive(handle) then
        RemoveMediaPlayer(handle, true, { archiveCurrent = false })
    end

    expireStartupState(handle, "failed", finalMessage, stateDetails, 8)
    TriggerClientEvent("pmms:error", src, finalMessage)
end

local function playbackUrlMatches(options, failedUrl)
    if type(failedUrl) ~= "string" or failedUrl == "" then
        return true
    end

    for _, candidate in ipairs({
        options and options.url,
        options and options.resolvedUrl,
        options and options.originalUrl,
    }) do
        if type(candidate) == "string" and candidate ~= "" and candidate == failedUrl then
            return true
        end
    end

    return false
end

local function getLivePlaybackOffset(options)
    if type(options) ~= "table" then
        return 0
    end

    if options.paused == true then
        return parseOffset(options.offset)
    end

    if options.startTime then
        return math.max(0, os.time() - (tonumber(options.startTime) or os.time()))
    end

    return parseOffset(options.offset)
end

local function failActiveLocalPlayback(handle, src, message, details)
    local mp = GetMediaPlayer(handle)
    local finalMessage = message or "Playback failed on this client."
    if type(details) == "string" and details ~= "" then
        local compact = details:gsub("%s+", " ")
        if #compact > 220 then
            compact = compact:sub(1, 217) .. "..."
        end
        finalMessage = ("%s (%s)"):format(finalMessage, compact)
    end

    local resolver = type(mp and mp.resolver) == "table" and mp.resolver or {}
    local stateDetails = {
        playbackToken = mp and mp.playbackToken or nil,
        retryCount = tonumber(mp and mp.localPlaybackRetryCount) or 0,
        provider = resolver.provider,
        instance = resolver.instance,
        resolverStatus = resolver.status,
        resolverReason = resolver.reason,
        title = mp and mp.title or nil,
        url = mp and (mp.originalUrl or mp.url) or nil,
        message = finalMessage,
    }

    PMMSDebug("player", "active local playback failed", {
        src = src,
        handle = handle,
        playbackToken = mp and mp.playbackToken or nil,
        message = finalMessage,
        details = details,
        provider = resolver.provider,
        instance = resolver.instance,
        resolverStatus = resolver.status,
        resolverReason = resolver.reason,
        retryCount = stateDetails.retryCount,
    })
    if type(LogPmmsAdminEvent) == "function" then
        LogPmmsAdminEvent("dui_playback_error", handle, src, {
            message = finalMessage,
            details = details,
            provider = resolver.provider,
            reason = resolver.reason,
        })
    end

    if IsMediaPlayerActive(handle) then
        RemoveMediaPlayer(handle, true, { archiveCurrent = false })
    end
    ClearRestricted(handle)
    expireStartupState(handle, "failed", finalMessage, stateDetails, 8)
    TriggerClientEvent("pmms:error", src, finalMessage)
    if pushImmediateSync then
        pushImmediateSync()
    end
end

local function validateAndPrepareStartOptions(src, options)
    if type(options) ~= "table" or type(options.url) ~= "string" or options.url == "" then
        return false, nil, "You must specify a URL to play."
    end

    local prepared = cloneDeepTable(options)

    if prepared.url == "random" then
        prepared.url = getRandomPreset()
    end

    if Config.presets[prepared.url] then
        local preset = Config.presets[prepared.url]
        prepared.title = preset.title
        prepared.filter = preset.filter or false
        prepared.video = preset.video or prepared.visualization ~= nil
        prepared.url = preset.url
        prepared.lastSource = tonumber(src) or prepared.lastSource
        return true, prepared
    end

    local nestedDirectUrl = extractNestedDirectLinkUrl(prepared.url)
    if nestedDirectUrl then
        prepared.proxyUrl = prepared.url
        prepared.originalUrl = prepared.originalUrl or prepared.url
        prepared.url = nestedDirectUrl
    end

    local directLinkOk, directLinkError = validateAndTagDirectLink(prepared.url, prepared)
    if not directLinkOk then
        return false, nil, directLinkError
    end

    local requestedProvider, providerExplicit = getRequestedYoutubeResolverProvider(prepared)
    if providerExplicit then
        prepared.youtubeProvider = requestedProvider or "auto"
        prepared.youtubeProviderExplicit = true
    end

    if nestedDirectUrl and type(prepared.directLink) == "table" then
        prepared.directLink.unwrapped = true
        prepared.directLink.proxyUrl = prepared.proxyUrl
    end

    prepared.title = prepared.title or prepared.url
    prepared.lastSource = tonumber(src) or prepared.lastSource
    return true, prepared
end

function AddMediaPlayer(handle, options)
    local replaceActive = type(options) == "table" and options.replaceActive == true
    if IsMediaPlayerActive(handle) and not replaceActive then
        return
    end

    options = cloneDeepTable(options)
    options.replaceActive = nil
    options.playbackToken = type(options.playbackToken) == "string" and options.playbackToken ~= ""
        and options.playbackToken
        or createPlaybackToken(handle)

    if not options.title then
        options.title = options.url
    end

    local session = EnsureDeviceSession(handle, options)
    if type(options.queue) == "table" and (not session.queue or #session.queue <= 0) then
        session.queue = cloneDeepTable(options.queue)
    end

    applySessionSettingsToTarget(options, session)
    options.author = options.author or ""
    options.thumbnail = options.thumbnail or ""

    local defaultVolume = tonumber(Config.defaultVolume) or 100
    options.volume = Clamp(options.volume or defaultVolume, 0, 100, defaultVolume)
    options.duration = normalizeDuration(options.duration)
    options.offset = parseOffset(options.offset)
    options.startTime = os.time() - options.offset
    options.videoSize = Clamp(options.videoSize or Config.defaultVideoSize, 10, 100, Config.defaultVideoSize)
    options.paused = false
    options.pausedAt = nil
    applyLoopMode(options, options.loopMode, options.loop)

    if options.filter == nil then
        options.filter = Config.enableFilterByDefault
    end

    if options.attenuation then
        options.attenuation.sameRoom = Clamp(options.attenuation.sameRoom, 0.0, 10.0, Config.defaultSameRoomAttenuation)
        options.attenuation.diffRoom = Clamp(options.attenuation.diffRoom, 0.0, 10.0, Config.defaultDiffRoomAttenuation)
    else
        options.attenuation = {
            sameRoom = Config.defaultSameRoomAttenuation,
            diffRoom = Config.defaultDiffRoomAttenuation,
        }
    end

    options.diffRoomVolume = Clamp(options.diffRoomVolume, 0.0, 1.0, Config.defaultDiffRoomVolume)
    options.range = Clamp(options.range, 0, getConfiguredAdminMaxRange(), Config.defaultRange)
    options.transitionSeconds = clampTransitionSeconds(options.transitionSeconds)

    if options.scaleform then
        options.scaleform.position = options.scaleform.position and ToVector3(options.scaleform.position) or nil
        options.scaleform.rotation = options.scaleform.rotation and ToVector3(options.scaleform.rotation) or nil
        options.scaleform.scale = options.scaleform.scale and ToVector3(options.scaleform.scale) or nil
        if not options.label then
            options.label = "Scaleform"
        end
    end

    applyResolvedMetadata(options, options)
    options.queue = session.queue or {}

    cancelDeviceIdleReset(handle)
    if replaceActive then
        RemoveMediaPlayerEntry(handle)
    end
    SetMediaPlayer(handle, options)
    setDeviceSessionCurrentTrack(handle, options)
    local liveSession = deviceSessions[handle]
    if liveSession then
        options.stateRevision = liveSession.stateRevision
        syncActiveMediaPlayerWithSession(handle, liveSession)
    end
    clearStartupState(handle)
    if type(SchedulePreparedQueueForHandle) == "function" then
        SchedulePreparedQueueForHandle(handle)
    end

    EnqueueSync(function()
        TriggerClientEvent("pmms:play", -1, handle)
    end)
end

function RemoveMediaPlayer(handle, preserveSessionLock, removeOptions)
    removeOptions = type(removeOptions) == "table" and removeOptions or {}
    local mp = GetMediaPlayer(handle)

    if mp and removeOptions.archiveCurrent ~= false then
        pushDeviceHistoryEntry(handle, mp)
    end

    RemoveMediaPlayerEntry(handle)
    clearStartContext(handle, false, true)

    local session = deviceSessions[handle]
    if removeOptions.keepSession == false then
        if preserveSessionLock ~= true then
            clearSessionLock(handle)
        end
        if session then
            ResetDeviceSession(handle)
        end
    elseif session then
        startDeviceIdleReset(handle)
    end

    EnqueueSync(function()
        TriggerClientEvent("pmms:stop", -1, handle)
    end)
end

function DestroyPmmsDeviceLifecycle(handle, options)
    handle = tonumber(handle) or handle
    options = type(options) == "table" and options or {}
    local hadActivePlayer = IsMediaPlayerActive(handle)

    local persistentEntry, persistentCoords = nil, nil
    if type(GetPersistentPmmsDeviceEntry) == "function" then
        persistentEntry, persistentCoords = GetPersistentPmmsDeviceEntry(handle)
    end

    if options.clearPendingRequests ~= false and type(ClearPmmsPendingRequestsForHandle) == "function" then
        ClearPmmsPendingRequestsForHandle(handle, {
            source = options.source or 0,
            reason = options.reason or "device_destroyed",
            logEventName = options.pendingLogEventName,
            logEvent = options.logPending ~= false,
        })
    end

    if IsMediaPlayerActive(handle) then
        RemoveMediaPlayer(handle, false, {
            archiveCurrent = options.archiveCurrent == true,
            keepSession = false,
        })
    else
        clearStartContext(handle, false, true)
        clearSessionLock(handle)
        ResetDeviceSession(handle)
        EnqueueSync(function()
            TriggerClientEvent("pmms:stop", -1, handle)
        end)
    end

    ClearRestricted(handle)

    if options.removePersistent == true and persistentCoords and type(RemoveEntityPermanently) == "function" then
        RemoveEntityPermanently(persistentCoords)
        if persistentEntry and type(LogPmmsAdminEvent) == "function" and options.logRemovalEvent then
            LogPmmsAdminEvent(options.logRemovalEvent, handle, options.source or 0, {
                label = persistentEntry.label or persistentEntry.name,
            })
        end
        TriggerClientEvent("pmms:speakersCleared", -1, handle)
        TriggerClientEvent("pmms:refreshPersistentEntities", -1)
    end

    if type(ReconcilePmmsDeviceRequestState) == "function" then
        ReconcilePmmsDeviceRequestState(handle, {
            source = options.source,
            reason = options.reason or "device_destroyed",
        })
    end

    if pushImmediateSync then
        pushImmediateSync()
    end

    return {
        removedPersistent = options.removePersistent == true and persistentCoords ~= nil,
        hadPersistent = persistentCoords ~= nil,
        hadActivePlayer = hadActivePlayer,
    }
end

local function triggerStartOnClient(handle, src, resolvedOptions, intentOptions, retries, phase, message)
    local context = updateStartContextResolved(handle, resolvedOptions)
    if not context or context.source ~= src then
        return
    end

    context.retries = tonumber(retries) or tonumber(context.retries) or 0
    startContexts[handle] = context

    local resolved = cloneDeepTable(resolvedOptions)
    resolved.playbackToken = context.playbackToken
    local resolvedPhase = phase

    if not resolvedPhase then
        if resolved.resolver and resolved.resolver.status == "fallback" then
            resolvedPhase = "fallback"
        elseif (tonumber(context.retries) or 0) > 0 then
            resolvedPhase = "retrying"
        else
            resolvedPhase = "starting"
        end
    end

    setStartupState(
        handle,
        resolvedPhase,
        message or (resolvedPhase == "fallback" and "Using fallback playback." or "Starting playback."),
        buildStartupStateDetails(context, resolved)
    )

    PMMSDebug("player", "startup attempt sent to client", {
        src = src,
        handle = handle,
        attemptId = context.currentAttemptId,
        playbackToken = context.playbackToken,
        phase = resolvedPhase,
        url = redactUrlForDebug(resolved.originalUrl or resolved.url),
        resolvedUrl = redactUrlForDebug(resolved.resolvedUrl or resolved.url),
        provider = resolved.resolver and resolved.resolver.provider or nil,
        instance = resolved.resolver and resolved.resolver.instance or nil,
        resolverStatus = resolved.resolver and resolved.resolver.status or nil,
        resolverReason = resolved.resolver and resolved.resolver.reason or nil,
        retryCount = context.retries,
    })

    TriggerClientEvent("pmms:startupAttempt", src, {
        handle = handle,
        attemptId = context.currentAttemptId,
        playbackToken = context.playbackToken,
        phase = resolvedPhase,
        startupTimeoutMs = getStartupWatchdogMs(),
        resolvedOptions = resolved,
    })
end

local function startMediaPlayerForClient(handle, src, intentOptions, resolverOptions)
    if type(intentOptions) ~= "table" or type(intentOptions.url) ~= "string" or intentOptions.url == "" then
        PMMSDebug("player", "start rejected: invalid playback options", {
            src = src,
            handle = handle,
            optionsType = type(intentOptions),
            url = redactUrlForDebug(intentOptions and intentOptions.url or nil),
        })
        TriggerClientEvent("pmms:error", src, "Invalid playback options.")
        ClearRestricted(handle)
        return
    end

    resolverOptions = type(resolverOptions) == "table" and resolverOptions or {}

    local context = beginStartContext(handle, src, intentOptions, 0)
    context.replaceActiveOnReady = resolverOptions.replaceActiveOnReady == true
    startContexts[handle] = context
    local attemptId = context.currentAttemptId

    setStartupState(handle, "resolving", "Resolving media source.", buildStartupStateDetails(context, intentOptions))

    probePreparedDirectLink(intentOptions, function(directOk, probedOptions, directError)
        local liveContext = startContexts[handle]
        if not liveContext or liveContext.source ~= src or tostring(liveContext.currentAttemptId) ~= tostring(attemptId) then
            return
        end

        if not directOk then
            PMMSDebug("player", "start rejected: direct link probe failed", {
                src = src,
                handle = handle,
                attemptId = attemptId,
                url = redactUrlForDebug(intentOptions.url),
                error = directError,
            })
            failPlaybackStart(handle, src, directError or "This direct media link could not be verified.")
            return
        end

        local finalIntent = probedOptions or intentOptions

        if (not resolverOptions or resolverOptions.forceRefresh ~= true)
            and type(finalIntent.resolvedUrl) == "string"
            and finalIntent.resolvedUrl ~= ""
            and type(finalIntent.resolver) == "table"
            and finalIntent.resolver.status == "resolved" then
            local alreadyResolved = cloneDeepTable(finalIntent)
            alreadyResolved.url = finalIntent.resolvedUrl
            applyResolvedMetadata(alreadyResolved, finalIntent)
            PMMSDebug("player", "using already resolved media", {
                src = src,
                handle = handle,
                attemptId = attemptId,
                url = redactUrlForDebug(finalIntent.originalUrl or finalIntent.url),
                resolvedUrl = redactUrlForDebug(finalIntent.resolvedUrl),
                provider = finalIntent.resolver and finalIntent.resolver.provider or nil,
                instance = finalIntent.resolver and finalIntent.resolver.instance or nil,
            })
            triggerStartOnClient(handle, src, alreadyResolved, finalIntent, 0, "starting", "Starting playback.")
            return
        end

        resolvePlaybackAndNotify(src, finalIntent, resolverOptions or {}, function(ok, resolvedOptions, warning)
            local activeContext = startContexts[handle]
            if not activeContext or activeContext.source ~= src or tostring(activeContext.currentAttemptId) ~= tostring(attemptId) then
                return
            end

            if not ok then
                local failureMessage = warning or "Failed to resolve media source."
                if type(warning) == "string" and warning:find("No ad-free playable source found", 1, true) then
                    failureMessage = "No ad-free playable source found."
                end
                failPlaybackStart(handle, src, failureMessage)
                return
            end

            triggerStartOnClient(handle, src, resolvedOptions, finalIntent, 0)
        end)
    end)
end

function StartMediaPlayerForClient(handle, src, intentOptions, resolverOptions)
    startMediaPlayerForClient(handle, src, intentOptions, resolverOptions)
end

function PauseMediaPlayer(handle)
    local mp = GetMediaPlayer(handle)
    if not mp then
        return
    end

    local now = os.time()

    if mp.paused == true then
        mp.startTime = mp.startTime + (now - (mp.pausedAt or now))
        mp.paused = false
        mp.pausedAt = nil
    else
        mp.offset = math.max(0, now - mp.startTime)
        mp.paused = true
        mp.pausedAt = now
    end

    local session = deviceSessions[handle]
    if session then
        commitDeviceSession(handle, session)
    else
        MarkDirty()
    end
end

local function getRuntimeSessionForHandle(handle)
    local mp = GetMediaPlayer(handle)
    local session = deviceSessions[handle]
    if not session and mp then
        session = EnsureDeviceSession(handle, mp)
    end
    return mp, session
end

local function commitRuntimeSettingsChange(handle, mutator)
    local mp, session = getRuntimeSessionForHandle(handle)
    if not mp and not session then
        return false
    end

    if not session then
        session = EnsureDeviceSession(handle, mp or {})
    end

    mutator(session.settings, mp)
    commitDeviceSession(handle, session)
    return true
end

function StartMediaPlayerByNetworkId(netId, options)
    local resolved = resolvePreset(options.url, options.title, options.filter, options.video)
    options.url = resolved.url
    options.title = resolved.title
    options.filter = resolved.filter
    options.video = resolved.video
    options.queue = nil
    options.coords = nil
    AddMediaPlayer(netId, options)
    return netId
end

function StartMediaPlayerByCoords(x, y, z, options)
    local coords = vector3(x, y, z)
    local handle = GetHandleFromCoords(coords)
    local resolved = resolvePreset(options.url, options.title, options.filter, options.video)
    options.url = resolved.url
    options.title = resolved.title
    options.filter = resolved.filter
    options.video = resolved.video
    options.queue = nil
    options.coords = coords
    AddMediaPlayer(handle, options)
    return handle
end

function StartMediaPlayerScaleform(scaleform, options)
    options.scaleform = scaleform
    options.scaleform.standalone = true
    return StartMediaPlayerByCoords(scaleform.position.x, scaleform.position.y, scaleform.position.z, options)
end

function StartDefaultMediaPlayers()
    for _, mp in ipairs(Config.defaultMediaPlayers) do
        if mp.url then
            StartMediaPlayerByCoords(mp.position.x, mp.position.y, mp.position.z, mp)
        end
    end
end

local function copyMediaPlayer(oldHandle, newHandle, newCoords)
    local old = GetMediaPlayer(oldHandle)
    if not old then
        return
    end

    local options = cloneTable(old)
    options.label = nil
    options.model = nil
    options.renderTarget = nil

    if newHandle then
        StartMediaPlayerByNetworkId(newHandle, options)
    elseif newCoords then
        StartMediaPlayerByCoords(newCoords.x, newCoords.y, newCoords.z, options)
    end
end

exports("startByNetworkId", StartMediaPlayerByNetworkId)
exports("startByCoords", StartMediaPlayerByCoords)
exports("startScaleform", StartMediaPlayerScaleform)
exports("stop", RemoveMediaPlayer)
exports("pause", PauseMediaPlayer)
exports("lock", function(handle)
    local mp = GetMediaPlayer(handle)
    if mp then
        mp.locked = true
        MarkDirty()
    end
end)
exports("unlock", function(handle)
    local mp = GetMediaPlayer(handle)
    if mp then
        mp.locked = false
        MarkDirty()
    end
end)
exports("mute", function(handle)
    local mp = GetMediaPlayer(handle)
    if mp then
        mp.muted = true
        MarkDirty()
    end
end)
exports("unmute", function(handle)
    local mp = GetMediaPlayer(handle)
    if mp then
        mp.muted = false
        MarkDirty()
    end
end)
exports("getMediaPlayerInfo", GetMediaPlayer)
exports("getAllMediaPlayers", GetMediaPlayers)

RegisterNetEvent("pmms:start", function(handle, options)
    local src = source
    handle = tonumber(handle) or handle

    PMMSDebug("player", "start event received", {
        src = src,
        handle = handle,
        url = redactUrlForDebug(type(options) == "table" and options.url or nil),
        title = type(options) == "table" and options.title or nil,
        video = type(options) == "table" and options.video or nil,
    })

    if type(handle) ~= "number" and options and options.coords then
        handle = GetHandleFromCoords(options.coords)
    end

    if type(handle) ~= "number" then
        PMMSDebug("player", "start rejected: invalid media player handle", {
            src = src,
            handle = handle,
        })
        TriggerClientEvent("pmms:error", src, "Invalid media player handle.")
        return
    end

    local restricted = GetRestrictedHandles()
    if restricted[handle] then
        if restricted[handle] ~= src then
            PMMSDebug("player", "start rejected: restricted by another player", {
                src = src,
                handle = handle,
                owner = restricted[handle],
            })
            TriggerClientEvent("pmms:error", src, "This player is busy")
            return
        end
        PMMSDebug("player", "clearing existing restriction for same player", {
            src = src,
            handle = handle,
        })
        ClearRestricted(handle)
    end

    if not requirePermission(src, handle, "interact") then
        return
    end

    if isLockedDefaultMediaPlayer(handle) and not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "You do not have permission to play on a locked media player")
        return
    end

    local ok, preparedOptions, errorMessage = validateAndPrepareStartOptions(src, options)
    if not ok then
        PMMSDebug("player", "start rejected: validation failed", {
            src = src,
            handle = handle,
            url = redactUrlForDebug(type(options) == "table" and options.url or nil),
            error = errorMessage,
        })
        if type(LogPmmsAdminEvent) == "function" then
            LogPmmsAdminEvent("playback_start_rejected", handle, src, {
                reason = errorMessage,
                url = redactUrlForDebug(type(options) == "table" and options.url or nil),
            })
        end
        TriggerClientEvent("pmms:error", src, errorMessage)
        return
    end

    if type(HandlePmmsDeviceRequestMode) == "function"
        and not HandlePmmsDeviceRequestMode(src, handle, preparedOptions) then
        return
    end

    local startupContext = startContexts[handle]
    if startupContext then
        if startupContext.source ~= src then
            PMMSDebug("player", "start rejected: active startup belongs to another player", {
                src = src,
                handle = handle,
                owner = startupContext.source,
                attemptId = startupContext.currentAttemptId,
            })
            TriggerClientEvent("pmms:error", src, "This player is busy")
            return
        end
        PMMSDebug("player", "replacing existing startup context from same player", {
            src = src,
            handle = handle,
            attemptId = startupContext.currentAttemptId,
        })
        clearStartContext(handle, false, true)
    end

    if IsMediaPlayerActive(handle) then
        PMMSDebug("player", "active media player found, queueing request", {
            src = src,
            handle = handle,
            url = redactUrlForDebug(preparedOptions.url),
            title = preparedOptions.title,
        })
        AddToQueue(handle, src, preparedOptions)
        if type(LogPmmsAdminEvent) == "function" then
            LogPmmsAdminEvent("playback_queued", handle, src, { title = preparedOptions.title })
        end
        return
    end

    if type(LogPmmsAdminEvent) == "function" then
        LogPmmsAdminEvent("playback_start_requested", handle, src, { title = preparedOptions.title })
    end
    startMediaPlayerForClient(handle, src, preparedOptions, {})
end)

RegisterNetEvent("pmms:playPlaylistTracks", function(handle, playlistId, tracks)
    local src = source
    handle = tonumber(handle) or handle

    if type(handle) ~= "number" then
        TriggerClientEvent("pmms:error", src, "Invalid media player handle.")
        return
    end

    local requestedPlate = type(options) == "table" and options.vehiclePlate or nil
    if not requirePermission(src, handle, "interact", requestedPlate) then
        return
    end

    if isLockedDefaultMediaPlayer(handle) and not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "You do not have permission to play on a locked media player")
        return
    end

    if type(tracks) ~= "table" or #tracks <= 0 then
        TriggerClientEvent("pmms:error", src, "This playlist has no playable tracks.")
        return
    end

    local preparedTracks = {}
    local rejectedCount = 0
    for _, track in ipairs(tracks) do
        local candidate = type(track) == "table" and cloneDeepTable(track) or nil
        if candidate then
            candidate.video = candidate.video ~= false
            local ok, prepared = validateAndPrepareStartOptions(src, candidate)
            if ok and prepared then
                preparedTracks[#preparedTracks + 1] = prepared
            else
                rejectedCount = rejectedCount + 1
            end
        else
            rejectedCount = rejectedCount + 1
        end
    end

    if #preparedTracks <= 0 then
        TriggerClientEvent("pmms:error", src, "No valid playlist tracks could be played.")
        return
    end

    if type(GetPmmsDeviceRequestMode) == "function" and not HasPmmsPermission(src, "manage") then
        local requestMode = GetPmmsDeviceRequestMode(handle)
        if requestMode == "disabled" then
            TriggerClientEvent("pmms:error", src, "Requests are disabled on this device.")
            return
        elseif requestMode == "pending" and type(HandlePmmsDeviceRequestMode) == "function" then
            for _, prepared in ipairs(preparedTracks) do
                HandlePmmsDeviceRequestMode(src, handle, prepared)
            end
            return
        end
    end

    local restricted = GetRestrictedHandles()
    if restricted[handle] then
        if restricted[handle] ~= src then
            TriggerClientEvent("pmms:error", src, "This player is busy")
            return
        end
        ClearRestricted(handle)
    end

    if IsMediaPlayerActive(handle) then
        for _, prepared in ipairs(preparedTracks) do
            AddToQueue(handle, src, prepared)
        end
        TriggerClientEvent("pmms:notify", src, {
            title = "Library",
            text = ("Queued %d playlist track%s%s."):format(
                #preparedTracks,
                #preparedTracks == 1 and "" or "s",
                rejectedCount > 0 and (" (" .. rejectedCount .. " skipped)") or ""
            ),
        })
        return
    end

    local startupContext = startContexts[handle]
    if startupContext then
        if startupContext.source ~= src then
            TriggerClientEvent("pmms:error", src, "This player is busy")
            return
        end
        clearStartContext(handle, false, true)
    end

    for index = 2, #preparedTracks do
        AddToQueue(handle, src, preparedTracks[index])
    end

    PMMSDebug("player", "playlist batch start requested", {
        src = src,
        handle = handle,
        playlistId = playlistId,
        startTitle = preparedTracks[1].title,
        queuedCount = math.max(0, #preparedTracks - 1),
        rejectedCount = rejectedCount,
    })

    startMediaPlayerForClient(handle, src, preparedTracks[1], {})
    if rejectedCount > 0 then
        TriggerClientEvent("pmms:notify", src, {
            title = "Library",
            text = ("Started playlist; %d invalid track%s skipped."):format(rejectedCount, rejectedCount == 1 and "" or "s"),
        })
    end
end)

RegisterNetEvent("pmms:startupReady", function(handle, attemptId, metadata, playbackToken)
    local src = source
    handle = tonumber(handle)

    if not handle then
        return
    end

    local context = startContexts[handle]
    if not context
        or context.source ~= src
        or tostring(context.currentAttemptId) ~= tostring(attemptId)
        or (type(playbackToken) == "string" and playbackToken ~= "" and tostring(context.playbackToken) ~= tostring(playbackToken)) then
        PMMSDebug("player", "startup ready ignored: stale or missing context", {
            src = src,
            handle = handle,
            attemptId = attemptId,
            playbackToken = playbackToken,
            currentSource = context and context.source or nil,
            currentAttemptId = context and context.currentAttemptId or nil,
            currentPlaybackToken = context and context.playbackToken or nil,
        })
        return
    end

    local merged = cloneDeepTable(context.currentOptions or context.options or {})
    merged.playbackToken = context.playbackToken
    local details = type(metadata) == "table" and metadata or {}
    local duration = normalizeDuration(details.duration)
    if duration then
        merged.duration = duration
    end
    if type(details.title) == "string" and details.title ~= "" and details.title ~= merged.url then
        merged.title = details.title
    end
    if type(details.author) == "string" and details.author ~= "" then
        merged.author = details.author
    end
    if type(details.thumbnail) == "string" and details.thumbnail ~= "" then
        merged.thumbnail = details.thumbnail
    end
    if details.video == false then
        merged.video = false
    end
    if type(details.audioTracks) == "table" then
        merged.audioTracks = cloneDeepTable(details.audioTracks)
    end
    local selectedAudioTrack = normalizeAudioTrackSelection(
        details.audioTrack
            or details.selectedAudioTrack
            or details.audioTrackIndex
    )
    if selectedAudioTrack then
        merged.audioTrack = selectedAudioTrack
        merged.selectedAudioTrack = cloneDeepTable(selectedAudioTrack)
    end
    applyPlaybackMetadata(merged, details)
    merged.replaceActive = context.replaceActiveOnReady == true

    recordAutoProviderPlayback(merged, merged.resolver, "success", "startup_ready", context)
    AddMediaPlayer(handle, merged)
    clearStartContext(handle, false, false)
    ClearRestricted(handle)
    PMMSDebug("player", "startup ready accepted, media player added", {
        src = src,
        handle = handle,
        attemptId = attemptId,
        playbackToken = context.playbackToken,
        url = redactUrlForDebug(merged.originalUrl or merged.url),
        resolvedUrl = redactUrlForDebug(merged.resolvedUrl or merged.url),
        provider = merged.resolver and merged.resolver.provider or nil,
        instance = merged.resolver and merged.resolver.instance or nil,
        resolverStatus = merged.resolver and merged.resolver.status or nil,
        duration = merged.duration,
        video = merged.video,
    })
    pushImmediateSync()
end)

RegisterNetEvent("pmms:updatePlaybackMetadata", function(handle, metadata, playbackToken)
    local src = source
    handle = tonumber(handle)

    if not handle or type(metadata) ~= "table" then
        return
    end

    local context = startContexts[handle]
    if context
        and type(playbackToken) == "string"
        and playbackToken ~= ""
        and tostring(context.playbackToken) == tostring(playbackToken) then
        local contextChanged = false
        contextChanged = applyPlaybackMetadata(context.currentOptions, metadata) or contextChanged
        contextChanged = applyPlaybackMetadata(context.options, metadata) or contextChanged
        if contextChanged then
            context.updatedAt = os.time()
            startContexts[handle] = context
        end
        return
    end

    local mp = GetMediaPlayer(handle)
    if not mp or type(mp) ~= "table" then
        return
    end

    local currentToken = type(mp.playbackToken) == "string" and mp.playbackToken or nil
    if currentToken
        and (
            type(playbackToken) ~= "string"
            or playbackToken == ""
            or tostring(currentToken) ~= tostring(playbackToken)
        ) then
        PMMSDebug("player", "playback metadata ignored: stale playback token", {
            src = src,
            handle = handle,
            requestedToken = playbackToken,
            currentToken = currentToken,
        })
        return
    end

    local changed = applyPlaybackMetadata(mp, metadata)
    local session = deviceSessions[handle]
    if session then
        if type(session.currentTrack) == "table" then
            changed = applyPlaybackMetadata(session.currentTrack, metadata) or changed
        end
        if type(session.playerTemplate) == "table" then
            changed = applyPlaybackMetadata(session.playerTemplate, metadata) or changed
        end
        if changed then
            commitDeviceSession(handle, session)
        end
    elseif changed then
        MarkDirty()
    end

    if changed then
        PMMSDebug("player", "playback metadata updated", {
            src = src,
            handle = handle,
            playbackToken = playbackToken,
            duration = mp.duration,
            live = mp.live == true,
            audioTrackCount = type(mp.audioTracks) == "table" and #mp.audioTracks or 0,
        })
        if pushImmediateSync then
            pushImmediateSync()
        end
    end
end)

RegisterNetEvent("pmms:ended", function(handle, metadata, playbackToken)
    local src = source
    handle = tonumber(handle)

    if not handle then
        return
    end

    local mp = GetMediaPlayer(handle)
    if not mp or type(mp) ~= "table" then
        PMMSDebug("player", "playback ended ignored: no active media player", {
            src = src,
            handle = handle,
            playbackToken = playbackToken,
        })
        return
    end

    local currentToken = type(mp.playbackToken) == "string" and mp.playbackToken or nil
    if currentToken
        and (
            type(playbackToken) ~= "string"
            or playbackToken == ""
            or tostring(currentToken) ~= tostring(playbackToken)
        ) then
        PMMSDebug("player", "playback ended ignored: stale playback token", {
            src = src,
            handle = handle,
            requestedToken = playbackToken,
            currentToken = currentToken,
        })
        return
    end

    metadata = type(metadata) == "table" and metadata or {}
    local duration = normalizeDuration(mp.duration or metadata.duration)
    if not duration or duration <= 0 or mp.live == true then
        PMMSDebug("player", "playback ended ignored: missing or live duration", {
            src = src,
            handle = handle,
            playbackToken = playbackToken,
            duration = mp.duration or metadata.duration,
            live = mp.live == true,
        })
        return
    end

    local clientTime = parseOffset(metadata.currentTime or metadata.offset)
    local liveOffset = getLivePlaybackOffset(mp)
    local nearDuration = math.max(0, duration - 2)
    if clientTime < nearDuration and liveOffset < nearDuration then
        PMMSDebug("player", "playback ended ignored: not near duration", {
            src = src,
            handle = handle,
            playbackToken = playbackToken,
            clientTime = clientTime,
            serverOffset = liveOffset,
            duration = duration,
        })
        return
    end

    local now = os.time()
    for key, timestamp in pairs(endedEventGuards) do
        if now - timestamp > 8 then
            endedEventGuards[key] = nil
        end
    end

    local guardKey = ("%s:%s"):format(tostring(handle), tostring(currentToken or playbackToken or ""))
    if endedEventGuards[guardKey] and now - endedEventGuards[guardKey] <= 4 then
        PMMSDebug("player", "playback ended ignored: duplicate end event", {
            src = src,
            handle = handle,
            playbackToken = playbackToken,
            clientTime = clientTime,
            serverOffset = liveOffset,
            duration = duration,
        })
        return
    end
    endedEventGuards[guardKey] = now

    local loopMode = NormalizeLoopMode(mp.loopMode, mp.loop)
    local shouldAdvanceQueue = (type(mp.queue) == "table" and #mp.queue > 0)
        or loopMode == "queue"
        or loopMode == "shuffle_loop"

    PMMSDebug("player", "playback ended accepted", {
        src = src,
        handle = handle,
        playbackToken = playbackToken,
        loopMode = loopMode,
        clientTime = clientTime,
        serverOffset = liveOffset,
        duration = duration,
        queueLength = type(mp.queue) == "table" and #mp.queue or 0,
    })

    if loopMode == "track" then
        mp.offset = 0
        mp.startTime = now
        mp.paused = false
        mp.pausedAt = nil
        MarkDirty()
        if pushImmediateSync then
            pushImmediateSync()
        end
    elseif shouldAdvanceQueue then
        PlayNextInQueue(handle, { reason = "client_ended", source = src })
    else
        RemoveMediaPlayer(handle)
    end
end)

RegisterNetEvent("pmms:startupError", function(handle, attemptId, failedUrl, failedMessage, playbackToken)
    local src = source
    local resolverConfig = Config.resolver or {}
    handle = tonumber(handle)

    if not handle then
        return
    end

    local context = startContexts[handle]
    if not context
        or context.source ~= src
        or tostring(context.currentAttemptId) ~= tostring(attemptId)
        or (type(playbackToken) == "string" and playbackToken ~= "" and tostring(context.playbackToken) ~= tostring(playbackToken))
        or type(context.options) ~= "table" then
        PMMSDebug("player", "startup error ignored: stale or missing context", {
            src = src,
            handle = handle,
            attemptId = attemptId,
            playbackToken = playbackToken,
            failedUrl = redactUrlForDebug(failedUrl),
            message = failedMessage,
            currentSource = context and context.source or nil,
            currentAttemptId = context and context.currentAttemptId or nil,
            currentPlaybackToken = context and context.playbackToken or nil,
        })
        return
    end

    local currentOptions = context.currentOptions or context.options or {}
    local currentResolver = type(currentOptions.resolver) == "table" and currentOptions.resolver or {}
    local retryAttempts = math.max(0, tonumber(resolverConfig.retryAttempts) or 1)
    local playbackFailureReason = classifyPlaybackError(failedMessage)
    local retryEmbedFallbackFailure = isRetryableEmbedFallbackFailure(playbackFailureReason, context.options, currentResolver)

    recordAutoProviderPlayback(currentOptions, currentResolver, "failure", playbackFailureReason, context)

    context.errorHistory = context.errorHistory or {}
    context.errorHistory[#context.errorHistory + 1] = {
        url = failedUrl,
        message = failedMessage,
        reason = playbackFailureReason,
        at = os.time(),
    }
    startContexts[handle] = context

    if type(SuppressResolverInstance) == "function"
        and type(currentResolver.provider) == "string"
        and type(currentResolver.instance) == "string" then
        SuppressResolverInstance(currentResolver.provider, currentResolver.instance, playbackFailureReason)
    end

    PMMSDebug("player", "startup error received", {
        src = src,
        handle = handle,
        attemptId = attemptId,
        failedUrl = redactUrlForDebug(failedUrl),
        message = failedMessage,
        reason = context.errorHistory[#context.errorHistory].reason,
        resolverStatus = currentResolver.status,
        provider = currentResolver.provider,
        instance = currentResolver.instance,
        retries = context.retries,
        retryAttempts = retryAttempts,
    })

    if resolverConfig.retryOnPlaybackError == false
        or currentResolver.status == "bypass"
        or (currentResolver.status == "fallback" and not retryEmbedFallbackFailure)
        or not isYoutubeLikeUrl(context.options.originalUrl or context.options.url)
        or (tonumber(context.retries) or 0) >= retryAttempts then
        PMMSDebug("player", "startup retry skipped", {
            src = src,
            handle = handle,
            retryOnPlaybackError = resolverConfig.retryOnPlaybackError ~= false,
            resolverStatus = currentResolver.status,
            isYoutubeLike = isYoutubeLikeUrl(context.options.originalUrl or context.options.url),
            retryEmbedFallbackFailure = retryEmbedFallbackFailure,
            retries = context.retries,
            retryAttempts = retryAttempts,
        })
        failPlaybackStart(handle, src, failedMessage or "Playback failed.")
        return
    end

    local retryContext, previousAttemptId = rotateStartAttempt(handle)
    if not retryContext then
        failPlaybackStart(handle, src, failedMessage or "Playback failed.")
        return
    end

    retryContext.retries = (tonumber(context.retries) or 0) + 1
    retryContext.updatedAt = os.time()
    startContexts[handle] = retryContext

    PMMSDebug("player", "startup retry scheduled", {
        src = src,
        handle = handle,
        previousAttemptId = previousAttemptId,
        nextAttemptId = retryContext.currentAttemptId,
        retryCount = retryContext.retries,
        avoidProvider = retryContext.lastProvider,
        avoidInstance = retryContext.lastInstance,
        avoidResolvedUrl = redactUrlForDebug(failedUrl),
    })

    if previousAttemptId and previousAttemptId ~= retryContext.currentAttemptId then
        TriggerClientEvent("pmms:startupStop", src, handle, previousAttemptId, retryContext.playbackToken)
    end

    setStartupState(
        handle,
        "retrying",
        "Retrying playback with a different provider.",
        buildStartupStateDetails(retryContext, retryContext.currentOptions)
    )

    local resolverRetryOptions = {
        forceRefresh = true,
        avoidResolvedUrl = failedUrl,
        avoidProvider = retryContext.lastProvider,
        avoidInstance = retryContext.lastInstance,
        maxInstances = getRetryMaxInstances(resolverConfig, retryEmbedFallbackFailure),
        notifyOnFailure = false,
        allowFallback = true,
        allowAudioFallback = resolverConfig.allowAudioFallback ~= false,
        allowEmbedFallback = retryEmbedFallbackFailure and false or resolverConfig.allowEmbedFallback == true,
    }

    resolvePlaybackAndNotify(src, retryContext.options, resolverRetryOptions, function(ok, resolvedOptions, warning)
        local activeContext = startContexts[handle]
        if not activeContext
            or activeContext.source ~= src
            or tostring(activeContext.currentAttemptId) ~= tostring(retryContext.currentAttemptId) then
            return
        end

        if not ok then
            failPlaybackStart(handle, src, "Playback failed after retries. Please try another source.", warning)
            return
        end

        local nextPhase = resolvedOptions and resolvedOptions.resolver and resolvedOptions.resolver.status == "fallback"
            and "fallback"
            or "retrying"
        local nextMessage = nextPhase == "fallback" and "Using fallback playback." or "Loading retried media."
        triggerStartOnClient(handle, src, resolvedOptions, retryContext.options, retryContext.retries, nextPhase, nextMessage)
    end)
end)

RegisterNetEvent("pmms:localPlaybackError", function(handle, failedUrl, failedMessage, playbackToken)
    local src = source
    local resolverConfig = Config.resolver or {}
    handle = tonumber(handle)

    if not handle then
        return
    end

    local mp = GetMediaPlayer(handle)
    if not mp or type(mp) ~= "table" then
        return
    end

    local currentToken = type(mp.playbackToken) == "string" and mp.playbackToken or nil
    if currentToken
        and (
            type(playbackToken) ~= "string"
            or playbackToken == ""
            or tostring(currentToken) ~= tostring(playbackToken)
        ) then
        PMMSDebug("player", "local playback error ignored: stale playback token", {
            src = src,
            handle = handle,
            failedUrl = redactUrlForDebug(failedUrl),
            message = failedMessage,
            requestedToken = playbackToken,
            currentToken = currentToken,
        })
        return
    end

    if not playbackUrlMatches(mp, failedUrl) then
        PMMSDebug("player", "local playback error ignored: url mismatch", {
            src = src,
            handle = handle,
            failedUrl = redactUrlForDebug(failedUrl),
            currentUrl = redactUrlForDebug(mp.url),
            originalUrl = redactUrlForDebug(mp.originalUrl),
            resolvedUrl = redactUrlForDebug(mp.resolvedUrl),
            message = failedMessage,
        })
        return
    end

    local lastSource = tonumber(mp.lastSource)
    if lastSource and lastSource ~= tonumber(src) and not HasPmmsPermission(src, "manage") then
        PMMSDebug("player", "local playback error ignored: source mismatch", {
            src = src,
            handle = handle,
            owner = lastSource,
            failedUrl = redactUrlForDebug(failedUrl),
            message = failedMessage,
        })
        return
    end

    local sourceUrl = mp.originalUrl or mp.url
    local currentResolver = type(mp.resolver) == "table" and mp.resolver or {}
    local retryAttempts = math.max(0, tonumber(resolverConfig.retryAttempts) or 1)
    local retryCount = tonumber(mp.localPlaybackRetryCount) or 0
    local playbackFailureReason = classifyPlaybackError(failedMessage)
    local retryEmbedFallbackFailure = isRetryableEmbedFallbackFailure(playbackFailureReason, mp, currentResolver)

    recordAutoProviderPlayback(mp, currentResolver, "failure", playbackFailureReason, nil)

    if type(SuppressResolverInstance) == "function"
        and type(currentResolver.provider) == "string"
        and type(currentResolver.instance) == "string" then
        SuppressResolverInstance(currentResolver.provider, currentResolver.instance, playbackFailureReason)
    end

    if resolverConfig.retryOnPlaybackError == false
        or not isYoutubeLikeUrl(sourceUrl)
        or currentResolver.status == "bypass"
        or (currentResolver.status == "fallback" and not retryEmbedFallbackFailure)
        or retryCount >= retryAttempts then
        PMMSDebug("player", "local playback retry skipped", {
            src = src,
            handle = handle,
            sourceUrl = redactUrlForDebug(sourceUrl),
            failedUrl = redactUrlForDebug(failedUrl),
            message = failedMessage,
            retryOnPlaybackError = resolverConfig.retryOnPlaybackError ~= false,
            isYoutubeLike = isYoutubeLikeUrl(sourceUrl),
            resolverStatus = currentResolver.status,
            provider = currentResolver.provider,
            instance = currentResolver.instance,
            retryEmbedFallbackFailure = retryEmbedFallbackFailure,
            retryCount = retryCount,
            retryAttempts = retryAttempts,
        })
        failActiveLocalPlayback(handle, src, failedMessage or "Playback failed.", currentResolver.warning)
        return
    end

    local retryOptions = cloneDeepTable(mp)
    retryOptions.url = sourceUrl
    retryOptions.originalUrl = sourceUrl
    retryOptions.resolvedUrl = nil
    retryOptions.resolver = nil
    retryOptions.directLink = nil
    retryOptions.resolverStatus = nil
    retryOptions.resolverReason = nil
    retryOptions.resolverWarning = nil
    retryOptions.resolverFallback = nil
    retryOptions.playbackToken = nil
    retryOptions.localPlaybackRetryCount = retryCount + 1
    retryOptions.lastSource = tonumber(src) or retryOptions.lastSource
    retryOptions.offset = getLivePlaybackOffset(mp)
    retryOptions.startTime = nil
    retryOptions.pausedAt = nil

    setStartupState(handle, "retrying", "Refreshing media source after a playback read failure.", {
        playbackToken = currentToken,
        retryCount = retryOptions.localPlaybackRetryCount,
        provider = currentResolver.provider,
        instance = currentResolver.instance,
        resolverStatus = currentResolver.status,
        resolverReason = currentResolver.reason,
        title = mp.title,
        url = sourceUrl,
    })

    PMMSDebug("player", "local playback retry scheduled", {
        src = src,
        handle = handle,
        sourceUrl = redactUrlForDebug(sourceUrl),
        failedUrl = redactUrlForDebug(failedUrl),
        message = failedMessage,
        retryCount = retryOptions.localPlaybackRetryCount,
        avoidProvider = currentResolver.provider,
        avoidInstance = currentResolver.instance,
        avoidResolvedUrl = redactUrlForDebug(failedUrl),
    })

    startMediaPlayerForClient(handle, src, retryOptions, {
        forceRefresh = true,
        avoidResolvedUrl = failedUrl,
        avoidProvider = currentResolver.provider,
        avoidInstance = currentResolver.instance,
        maxInstances = getRetryMaxInstances(resolverConfig, retryEmbedFallbackFailure),
        notifyOnFailure = false,
        allowFallback = true,
        allowAudioFallback = resolverConfig.allowAudioFallback ~= false,
        allowEmbedFallback = retryEmbedFallbackFailure and false or resolverConfig.allowEmbedFallback == true,
        replaceActiveOnReady = true,
    })
end)

RegisterNetEvent("pmms:pause", function(handle)
    local src = source
    local mp = GetMediaPlayer(handle)
    if not mp then
        return
    end
    if not mp.duration then
        TriggerClientEvent("pmms:error", src, "You cannot pause live streams.")
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    PauseMediaPlayer(handle)
end)

RegisterNetEvent("pmms:play", function(handle)
    local src = source
    local mp = GetMediaPlayer(handle)
    if not mp then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    if mp.paused then
        PauseMediaPlayer(handle)
    end
end)

RegisterNetEvent("pmms:stop", function(handle)
    local src = source
    handle = tonumber(handle)
    if not handle then
        PMMSDebug("player", "stop ignored: invalid handle", {
            src = src,
            handle = handle,
        })
        return
    end

    local startupContext = startContexts[handle]

    if not IsMediaPlayerActive(handle) and not startupContext then
        PMMSDebug("player", "stop ignored: no active player or startup", {
            src = src,
            handle = handle,
        })
        return
    end
    if not requirePermission(src, handle, "interact") then
        PMMSDebug("player", "stop rejected: permission denied", {
            src = src,
            handle = handle,
        })
        return
    end
    if startupContext then
        PMMSDebug("player", "stop converted to startup cancel", {
            src = src,
            handle = handle,
            attemptId = startupContext.currentAttemptId,
            playbackToken = startupContext.playbackToken,
        })
        cancelStartupForSource(src, handle, startupContext.currentAttemptId, startupContext.playbackToken)
        return
    end
    PMMSDebug("player", "active media player stopped", {
        src = src,
        handle = handle,
    })
    if type(LogPmmsAdminEvent) == "function" then
        LogPmmsAdminEvent("playback_stopped", handle, src, {})
    end
    RemoveMediaPlayer(handle)
end)

RegisterNetEvent("pmms:cancelStartup", function(handle, attemptId, playbackToken)
    cancelStartupForSource(source, handle, attemptId, playbackToken)
end)

RegisterNetEvent("pmms:showControls", function()
    TriggerClientEvent("pmms:showControls", source)
end)

RegisterNetEvent("pmms:toggleStatus", function()
    TriggerClientEvent("pmms:toggleStatus", source)
end)

RegisterNetEvent("pmms:setVolume", function(handle, volume)
    local src = source
    if not IsMediaPlayerActive(handle) and not deviceSessions[handle] then
        return
    end
    if not requireStaffDevicePermission(src) then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    commitRuntimeSettingsChange(handle, function(settings, mp)
        settings.volume = Clamp(volume, 0, 100, 100)
        if mp then
            mp.volume = settings.volume
        end
    end)
    if type(LogPmmsAdminEvent) == "function" then
        LogPmmsAdminEvent("volume_changed", handle, src, { volume = tonumber(volume) })
    end
end)

RegisterNetEvent("pmms:setAudioTrack", function(handle, audioTrack)
    local src = source
    handle = tonumber(handle)
    if not handle or (not IsMediaPlayerActive(handle) and not deviceSessions[handle]) then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end

    local selection = normalizeAudioTrackSelection(audioTrack)
    if not selection then
        TriggerClientEvent("pmms:error", src, "Invalid audio track selection.")
        return
    end

    local mp, session = getRuntimeSessionForHandle(handle)
    if mp then
        mp.audioTrack = cloneDeepTable(selection)
        mp.selectedAudioTrack = cloneDeepTable(selection)
    end
    if session then
        if type(session.currentTrack) == "table" then
            session.currentTrack.audioTrack = cloneDeepTable(selection)
            session.currentTrack.selectedAudioTrack = cloneDeepTable(selection)
        end
        if type(session.playerTemplate) == "table" then
            session.playerTemplate.audioTrack = cloneDeepTable(selection)
            session.playerTemplate.selectedAudioTrack = cloneDeepTable(selection)
        end
        commitDeviceSession(handle, session)
    else
        MarkDirty()
    end

    if pushImmediateSync then
        pushImmediateSync()
    end
end)

RegisterNetEvent("pmms:setAttenuation", function(handle, sameRoom, diffRoom)
    local src = source
    if not IsMediaPlayerActive(handle) and not deviceSessions[handle] then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    commitRuntimeSettingsChange(handle, function(settings, mp)
        settings.attenuation = {
            sameRoom = Clamp(sameRoom, 0.0, 10.0, Config.defaultSameRoomAttenuation),
            diffRoom = Clamp(diffRoom, 0.0, 10.0, Config.defaultDiffRoomAttenuation),
        }
        if mp then
            mp.attenuation = cloneDeepTable(settings.attenuation)
        end
    end)
end)

RegisterNetEvent("pmms:setDiffRoomVolume", function(handle, diffRoomVolume)
    local src = source
    if not IsMediaPlayerActive(handle) and not deviceSessions[handle] then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    commitRuntimeSettingsChange(handle, function(settings, mp)
        settings.diffRoomVolume = Clamp(diffRoomVolume, 0.0, 1.0, Config.defaultDiffRoomVolume)
        if mp then
            mp.diffRoomVolume = settings.diffRoomVolume
        end
    end)
end)

RegisterNetEvent("pmms:setRange", function(handle, range)
    local src = source
    if not IsMediaPlayerActive(handle) and not deviceSessions[handle] then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    commitRuntimeSettingsChange(handle, function(settings, mp)
        settings.range = Clamp(range, 0.0, getAllowedRangeForPlayer(src), Config.defaultRange)
        if mp then
            mp.range = settings.range
        end
    end)
    if type(LogPmmsAdminEvent) == "function" then
        LogPmmsAdminEvent("range_changed", handle, src, { range = tonumber(range) })
    end
end)

RegisterNetEvent("pmms:forceResetDevice", function(handle)
    local src = source
    if not requireStaffDevicePermission(src) then
        return
    end

    if not IsMediaPlayerActive(handle) and not deviceSessions[handle] and not startContexts[handle] then
        TriggerClientEvent("pmms:error", src, "No live device session was found.")
        return
    end

    if type(DestroyPmmsDeviceLifecycle) == "function" then
        DestroyPmmsDeviceLifecycle(handle, {
            source = src,
            reason = "device_force_reset",
            removePersistent = false,
            archiveCurrent = false,
            clearPendingRequests = true,
            pendingLogEventName = false,
            logPending = false,
        })
    else
        if IsMediaPlayerActive(handle) then
            RemoveMediaPlayer(handle, false, {
                archiveCurrent = false,
                keepSession = false,
            })
        else
            clearStartContext(handle, false, true)
            clearSessionLock(handle)
            ResetDeviceSession(handle)
            EnqueueSync(function()
                TriggerClientEvent("pmms:stop", -1, handle)
            end)
        end

        ClearRestricted(handle)
    end
    if type(LogPmmsAdminEvent) == "function" then
        LogPmmsAdminEvent("device_force_reset", handle, src, {})
    end
    TriggerClientEvent("pmms:notify", src, {
        title = "Device Settings",
        text = "Live device session cleared.",
    })
end)

RegisterNetEvent("pmms:setTransition", function(handle, transitionSeconds)
    local src = source
    if not IsMediaPlayerActive(handle) and not deviceSessions[handle] then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end

    commitRuntimeSettingsChange(handle, function(settings, mp)
        settings.transitionSeconds = clampTransitionSeconds(transitionSeconds)
        if mp then
            mp.transitionSeconds = settings.transitionSeconds
        end
    end)
end)

RegisterNetEvent("pmms:setIsVehicle", function(handle, isVehicle)
    local src = source
    if not IsMediaPlayerActive(handle) and not deviceSessions[handle] then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    commitRuntimeSettingsChange(handle, function(settings, mp)
        settings.isVehicle = isVehicle == true
        if mp then
            mp.isVehicle = settings.isVehicle
        end
    end)
end)

RegisterNetEvent("pmms:setScaleform", function(handle, scaleform)
    local src = source
    local mp = GetMediaPlayer(handle)
    if not mp then
        return
    end
    if not requireStaffDevicePermission(src) then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end

    if mp.scaleform and mp.scaleform.standalone then
        scaleform.standalone = true
        mp.scaleform = scaleform
        mp.coords = scaleform.position
    else
        mp.scaleform = scaleform
    end
    MarkDirty()
end)

RegisterNetEvent("pmms:setStartTime", function(handle, time)
    local src = source
    local mp = GetMediaPlayer(handle)
    if not mp then
        return
    end

    if not mp.duration then
        TriggerClientEvent("pmms:error", src, "You cannot seek on live streams")
        return
    end

    if not requirePermission(src, handle, "interact") then
        return
    end

    local now = os.time()
    local startTime = math.floor(tonumber(time) or mp.startTime or now)
    local offset = math.max(0, now - startTime)

    if mp.duration and mp.duration > 0 then
        if offset > mp.duration then
            offset = mp.duration
        end
        startTime = now - offset
    end

    mp.startTime = startTime
    mp.offset = offset

    if mp.paused == true then
        mp.pausedAt = now
    end

    local session = deviceSessions[handle]
    if session then
        commitDeviceSession(handle, session)
    else
        MarkDirty()
    end
end)

RegisterNetEvent("pmms:seekToTime", function(handle, offset)
    local src = source
    local mp = GetMediaPlayer(handle)
    if not mp then
        return
    end

    if not mp.duration then
        TriggerClientEvent("pmms:error", src, "You cannot seek on live streams")
        return
    end

    if not requirePermission(src, handle, "interact") then
        return
    end

    local now = os.time()
    local targetOffset = math.max(0, tonumber(offset) or 0)

    if mp.duration and mp.duration > 0 and targetOffset > mp.duration then
        targetOffset = mp.duration
    end

    mp.startTime = now - targetOffset
    mp.offset = targetOffset

    if mp.paused == true then
        mp.pausedAt = now
    end

    local session = deviceSessions[handle]
    if session then
        commitDeviceSession(handle, session)
    else
        MarkDirty()
    end
end)

RegisterNetEvent("pmms:lockSession", function(handle, pin)
    local src = source
    if not IsMediaPlayerActive(handle) and not deviceSessions[handle] then
        TriggerClientEvent("pmms:error", src, "No active or remembered media session on this device.")
        return
    end

    if not HasPmmsPermission(src, "interact") then
        TriggerClientEvent("pmms:error", src, "You do not have permission for this action")
        return
    end
    if type(CanUsePmmsAdminLockedDevice) == "function" and not CanUsePmmsAdminLockedDevice(src, handle) then
        TriggerClientEvent("pmms:error", src, "This device is restricted by staff.")
        return
    end

    local canAccess = CanAccessSessionLock(src, handle, true)
    if hasSessionLock(handle) and not canAccess then
        TriggerClientEvent("pmms:error", src, "This media session is already locked by another player.")
        return
    end

    local normalizedPin = normalizePin(pin)
    if pin ~= nil and normalizedPin == nil then
        TriggerClientEvent("pmms:error", src, "PIN must be 4 to 12 characters.")
        return
    end

    local existingLock = sessionLocks[handle]
    if existingLock then
        if not (HasPmmsPermission(src, "manage") or isSessionLockOwner(existingLock, src)) then
            TriggerClientEvent("pmms:error", src, "Only the lock owner can change this session lock.")
            return
        end

        if existingLock.pin ~= normalizedPin then
            local ok, err = setSessionLockPin(handle, src, normalizedPin)
            if not ok then
                TriggerClientEvent("pmms:error", src, err or "Unable to update this session lock.")
                return
            end

            TriggerClientEvent("pmms:notify", src, {
                title = "Device Settings",
                text = normalizedPin and "Session lock updated with PIN." or "Session lock updated.",
            })
            return
        end

        touchSessionLock(handle, src)
        existingLock.authorized = existingLock.authorized or {}
        existingLock.authorized[src] = true
        MarkDirty()
        TriggerClientEvent("pmms:notify", src, {
            title = "Device Settings",
            text = "Session is already locked.",
        })
        return
    end

    local ok, err = upsertSessionLock(handle, src, normalizedPin)
    if not ok then
        TriggerClientEvent("pmms:error", src, err or "Unable to lock this media session.")
        return
    end

    TriggerClientEvent("pmms:notify", src, {
        title = "Device Settings",
        text = normalizedPin and "Session locked with PIN." or "Session locked.",
    })
end)

RegisterNetEvent("pmms:unlockSession", function(handle)
    local src = source
    local ok, err = unlockSessionLock(handle, src)
    if not ok then
        TriggerClientEvent("pmms:error", src, err or "Unable to unlock this session.")
        return
    end

    TriggerClientEvent("pmms:notify", src, {
        title = "Device Settings",
        text = "Session unlocked.",
    })
end)

RegisterNetEvent("pmms:setSessionPin", function(handle, pin)
    local src = source
    if pin ~= nil and normalizePin(pin) == nil then
        TriggerClientEvent("pmms:error", src, "PIN must be 4 to 12 characters.")
        return
    end

    local ok, err = setSessionLockPin(handle, src, pin)
    if not ok then
        TriggerClientEvent("pmms:error", src, err or "Unable to update session PIN.")
        return
    end

    TriggerClientEvent("pmms:notify", src, {
        title = "Device Settings",
        text = normalizePin(pin) and "PIN updated." or "PIN cleared.",
    })
end)

RegisterNetEvent("pmms:authorizeSessionPin", function(handle, pin)
    local src = source
    local ok, err = authorizeSessionLockPin(handle, src, pin)
    if not ok then
        TriggerClientEvent("pmms:error", src, err or "Unable to authorize PIN.")
        return
    end

    TriggerClientEvent("pmms:notify", src, {
        title = "Device Settings",
        text = "PIN accepted. You now have access.",
    })
end)

RegisterNetEvent("pmms:lock", function(handle)
    local src = source
    if not IsMediaPlayerActive(handle) then
        return
    end
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "You do not have permission to lock media players")
        return
    end
    GetMediaPlayer(handle).locked = true
    MarkDirty()
end)

RegisterNetEvent("pmms:unlock", function(handle)
    local src = source
    if not IsMediaPlayerActive(handle) then
        return
    end
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "You do not have permission to unlock media players")
        return
    end
    GetMediaPlayer(handle).locked = false
    MarkDirty()
end)

RegisterNetEvent("pmms:enableVideo", function(handle)
    local src = source
    if not IsMediaPlayerActive(handle) then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    GetMediaPlayer(handle).video = true
    MarkDirty()
end)

RegisterNetEvent("pmms:disableVideo", function(handle)
    local src = source
    if not IsMediaPlayerActive(handle) then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    GetMediaPlayer(handle).video = false
    MarkDirty()
end)

RegisterNetEvent("pmms:setVideoSize", function(handle, size)
    local src = source
    if not IsMediaPlayerActive(handle) then
        return
    end
    if not requireStaffDevicePermission(src) then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    GetMediaPlayer(handle).videoSize = Clamp(size, 10, 100, Config.defaultVideoSize)
    MarkDirty()
end)

RegisterNetEvent("pmms:mute", function(handle)
    local src = source
    if not IsMediaPlayerActive(handle) then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    GetMediaPlayer(handle).muted = true
    MarkDirty()
end)

RegisterNetEvent("pmms:unmute", function(handle)
    local src = source
    if not IsMediaPlayerActive(handle) then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    GetMediaPlayer(handle).muted = false
    MarkDirty()
end)

RegisterNetEvent("pmms:copy", function(oldHandle, newHandle, newCoords)
    local src = source
    if not IsMediaPlayerActive(oldHandle) then
        return
    end
    if not requirePermission(src, oldHandle, "interact") then
        return
    end
    copyMediaPlayer(oldHandle, newHandle, newCoords)
end)

RegisterNetEvent("pmms:setLoop", function(handle, loop)
    local src = source
    if not IsMediaPlayerActive(handle) and not deviceSessions[handle] then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    commitRuntimeSettingsChange(handle, function(settings, mp)
        settings.loopMode = NormalizeLoopMode(loop == true and "track" or "off", settings.loopMode == "track")
        if mp then
            applyLoopMode(mp, settings.loopMode, mp.loop)
        end
    end)
end)

RegisterNetEvent("pmms:setLoopMode", function(handle, loopMode)
    local src = source
    if not IsMediaPlayerActive(handle) and not deviceSessions[handle] then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    commitRuntimeSettingsChange(handle, function(settings, mp)
        settings.loopMode = NormalizeLoopMode(loopMode, settings.loopMode == "track")
        if mp then
            applyLoopMode(mp, settings.loopMode, mp.loop)
        end
    end)
    if type(SchedulePreparedQueueForHandle) == "function" then
        SchedulePreparedQueueForHandle(handle)
    end
end)

RegisterNetEvent("pmms:next", function(handle)
    local src = source
    if not IsMediaPlayerActive(handle) then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    PlayNextInQueue(handle, { manual = true, immediate = true, reason = "manual_next", source = src })
end)

RegisterNetEvent("pmms:previous", function(handle)
    local src = source
    if not IsMediaPlayerActive(handle) and not deviceSessions[handle] then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    PlayPreviousFromHistory(handle, { immediate = true, reason = "manual_previous", source = src })
end)

RegisterNetEvent("pmms:removeFromQueue", function(handle, id)
    local src = source
    if not IsMediaPlayerActive(handle) and not deviceSessions[handle] then
        return
    end
    if not requirePermission(src, handle, "interact") then
        return
    end
    RemoveFromQueue(handle, id)
end)

RegisterNetEvent("pmms:loadSettings", function()
    local defaultMediaPlayers = type(GetDefaultMediaPlayersForClient) == "function" and GetDefaultMediaPlayersForClient() or Config.defaultMediaPlayers
    TriggerClientEvent("pmms:loadSettings", source, Config.models, defaultMediaPlayers)
end)

RegisterNetEvent("pmms:loadPermissions", function()
    local src = source
    local permissions = GetPmmsPermissions(src)
    TriggerClientEvent("pmms:loadPermissions", src, permissions)
    TriggerClientEvent("pmms:sync", src, BuildMediaPlayersSyncStateForPlayer(src))
end)

AddEventHandler("playerJoining", function()
    local src = source
    TriggerClientEvent("pmms:sync", src, BuildMediaPlayersSyncStateForPlayer(src))
end)

AddEventHandler("playerDropped", function()
    local src = source
    for handle, context in pairs(startContexts) do
        if context.source == src then
            clearStartContext(handle, true, false)
            expireStartupState(handle, "stopped", "Playback startup was cancelled.", {
                attemptId = context.currentAttemptId,
                playbackToken = context.playbackToken,
                retryCount = tonumber(context.retries) or 0,
            }, 6)
        end
    end

    for _, lock in pairs(sessionLocks) do
        if lock.authorized then
            lock.authorized[src] = nil
        end
        if lock.ownerSource == src then
            lock.ownerSource = nil
        end
    end
end)
