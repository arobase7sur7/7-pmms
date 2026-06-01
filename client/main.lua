local mediaPlayerStates = {}
local startupStates = {}
local deviceSessions = {}
local adminSyncState = nil
local modelSettings = {}
local defaultMediaPlayers = {}
local disabledStaticEmitters = {}
local syncSnapshots = {}
local isInitialized = false
local hasReceivedFullSync = false
local lastFullSyncRequestAt = 0
local lastUpdateUi = 0
local failedPlayers = {}
local handleRangeState = {}
local cachedUsableMediaPlayers = {}
local lastUsableMediaPlayersBuild = 0
local lastUiOpenSignature = nil
local lastUiClosedSignature = nil
local lastUiOpenSendAt = 0
local lastUiClosedSendAt = 0
local lastUiPayloadSize = 0
local maxSyncCompensationSeconds = 3.0

local function countTableEntries(value)
    local count = 0
    if type(value) == "table" then
        for _ in pairs(value) do
            count = count + 1
        end
    end
    return count
end

local function appendSortedStateSummary(parts, prefix, value, mapper)
    local rows = {}
    if type(value) == "table" then
        for key, item in pairs(value) do
            rows[#rows + 1] = tostring(mapper(key, item))
        end
    end
    table.sort(rows)
    parts[#parts + 1] = prefix .. ":" .. table.concat(rows, ",")
end

local function permissionSignature(permissions)
    local parts = {}
    for _, key in ipairs({ "interact", "anyEntity", "customUrl", "anyUrl", "manage", "overrideDevice" }) do
        parts[#parts + 1] = key .. "=" .. (permissions and permissions[key] and "1" or "0")
    end
    return table.concat(parts, ";")
end

local function buildUiStateSignature(isOpen, activeMediaPlayersUI, usableMediaPlayers, permissions)
    local parts = {
        isOpen and "open" or "closed",
        "vol=" .. tostring(math.floor(tonumber(GetBaseVolume()) or 100)),
        "perms=" .. permissionSignature(permissions),
    }

    appendSortedStateSummary(parts, "startup", startupStates, function(handle, state)
        return table.concat({
            tostring(handle),
            tostring(state and state.phase or ""),
            tostring(state and state.attemptId or ""),
            tostring(state and state.playbackToken or ""),
            tostring(state and state.retryCount or 0),
        }, "|")
    end)

    appendSortedStateSummary(parts, "failed", failedPlayers, function(handle, state)
        return table.concat({
            tostring(handle),
            tostring(type(state) == "table" and state.playbackToken or ""),
            tostring(type(state) == "table" and state.retryCount or 0),
            tostring(type(state) == "table" and state.message or state or ""),
        }, "|")
    end)

    appendSortedStateSummary(parts, "sessions", deviceSessions, function(handle, session)
        local queueCount = type(session and session.queue) == "table" and #session.queue or 0
        local historyCount = tonumber(session and session.historyCount) or (type(session and session.history) == "table" and #session.history or 0)
        return table.concat({
            tostring(handle),
            tostring(session and session.stateRevision or 0),
            tostring(queueCount),
            tostring(historyCount),
            tostring(session and session.locked and 1 or 0),
        }, "|")
    end)

    if isOpen then
        if type(adminSyncState) == "table" and type(adminSyncState.devices) == "table" then
            appendSortedStateSummary(parts, "adminDevices", adminSyncState.devices, function(_, row)
                return table.concat({
                    tostring(row and row.handle or ""),
                    tostring(row and row.label or ""),
                    tostring(row and row.active and 1 or 0),
                    tostring(row and row.persistent and 1 or 0),
                    tostring(row and row.requestMode or ""),
                    tostring(row and row.pendingCount or 0),
                    tostring(row and row.stateRevision or 0),
                }, "|")
            end)
            local logs = type(adminSyncState.logs) == "table" and adminSyncState.logs or {}
            local lastLog = logs[#logs]
            parts[#parts + 1] = "adminLog:" .. tostring(lastLog and lastLog.id or 0)
        end

        appendSortedStateSummary(parts, "active", activeMediaPlayersUI, function(handle, row)
            local info = row and row.info or {}
            return table.concat({
                tostring(handle),
                tostring(info and info.playbackToken or ""),
                tostring(info and info.stateRevision or 0),
                tostring(info and info.paused and 1 or 0),
                tostring(info and info.muted and 1 or 0),
                tostring(info and info.volume or ""),
                tostring(math.floor(tonumber(row and row.distance) or -1)),
                tostring(row and row.canInteract and 1 or 0),
            }, "|")
        end)

        local deviceRows = {}
        for _, row in ipairs(usableMediaPlayers or {}) do
            deviceRows[#deviceRows + 1] = table.concat({
                tostring(row.handle or ""),
                tostring(row.label or ""),
                tostring(row.type or ""),
                tostring(row.active and 1 or 0),
                tostring(math.floor(tonumber(row.distance) or -1)),
                tostring(row.visibleBecause or ""),
            }, "|")
        end
        table.sort(deviceRows)
        parts[#parts + 1] = "usable:" .. table.concat(deviceRows, ",")
    end

    return table.concat(parts, "\n")
end

local function sendUiUpdateIfChanged(isOpen, payload, signature, heartbeatMs)
    local now = GetGameTimer()
    local lastSignature = isOpen and lastUiOpenSignature or lastUiClosedSignature
    local lastSendAt = isOpen and lastUiOpenSendAt or lastUiClosedSendAt

    if signature == lastSignature and (now - lastSendAt) < heartbeatMs then
        return false
    end

    SendNUIMessage(payload)
    local ok, encoded = pcall(json.encode, payload)
    lastUiPayloadSize = ok and encoded and #encoded or 0
    if isOpen then
        lastUiOpenSignature = signature
        lastUiOpenSendAt = now
    else
        lastUiClosedSignature = signature
        lastUiClosedSendAt = now
    end
    return true
end

function GetUiPerfStats()
    return {
        lastPayloadBytes = lastUiPayloadSize,
        lastOpenSendAt = lastUiOpenSendAt,
        lastClosedSendAt = lastUiClosedSendAt,
        cachedUsable = #cachedUsableMediaPlayers,
    }
end

function InvalidateUiUpdateSignature()
    lastUiOpenSignature = nil
    lastUiClosedSignature = nil
    lastUiOpenSendAt = 0
    lastUiClosedSendAt = 0
    lastUpdateUi = 0
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

function GetMediaPlayerStates()
    return mediaPlayerStates
end

function GetStartupStates()
    return startupStates
end

function GetDeviceSessions()
    return deviceSessions
end

function GetAdminSyncState()
    return adminSyncState
end

function GetFailedPlayers()
    return failedPlayers
end

local function getPlaybackToken(info)
    local token = info and info.playbackToken or nil
    if type(token) == "string" and token ~= "" then
        return token
    end
    return nil
end

function MarkMediaPlayerFailed(handle, message, context)
    local now = GetGameTimer()
    local previous = failedPlayers[handle]
    local playbackToken = getPlaybackToken(context)
    local retryCount = 1

    if type(previous) == "table"
        and playbackToken
        and type(previous.playbackToken) == "string"
        and previous.playbackToken == playbackToken then
        retryCount = math.max(1, tonumber(previous.retryCount) or 1) + 1
    end

    failedPlayers[handle] = {
        at = now,
        message = type(message) == "string" and message ~= "" and message or nil,
        playbackToken = playbackToken,
        stateRevision = tonumber(context and context.stateRevision) or nil,
        url = context and context.url or nil,
        retryCount = retryCount,
        nextRetryAt = now + math.min(8000, 1500 * retryCount),
    }
end

function GetModelSettings()
    return modelSettings
end

local function disableStaticEmitter(name)
    if not disabledStaticEmitters[name] then
        SetStaticEmitterEnabled(name, false)
        disabledStaticEmitters[name] = true
    end
end

local function enableStaticEmitter(name)
    if disabledStaticEmitters[name] then
        SetStaticEmitterEnabled(name, true)
        disabledStaticEmitters[name] = nil
    end
end

local function autoDisableStaticEmitters()
    if not Config.autoDisableStaticEmitters then
        return
    end

    for _, emitter in ipairs(StaticEmitters) do
        if emitter.enabled then
            disableStaticEmitter(emitter.name)
        end
    end
end

local function autoEnableStaticEmitters()
    for name in pairs(disabledStaticEmitters) do
        enableStaticEmitter(name)
    end
end

local function isSameRoom(_, entity, entityType, isVehicle)
    if not entity then
        return true
    end

    if entityType == "vehicle" and isVehicle ~= false then
        local playerVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
        return playerVehicle ~= 0 and playerVehicle == entity
    end

    return true
end

local function findEntityForHandle(handle, info)
    if info.coords then
        if type(GetPersistentPropEntity) == "function" then
            local entity, model, entityType = GetPersistentPropEntity(handle)
            if entity then
                return entity, model, entityType
            end
        end
        return nil, nil, nil
    end

    if type(GetEntityEntryByNetworkId) == "function" then
        local entry = GetEntityEntryByNetworkId(handle)
        if entry then
            return entry.entity, entry.model, entry.type
        end
    end

    return nil, nil, nil
end

local function getPersistentDeviceForEntity(entity)
    if not entity or not DoesEntityExist(entity) then
        return nil, nil
    end

    local coords = GetEntityCoords(entity)
    local defaultMp = GetDefaultMediaPlayer(Config.defaultMediaPlayers, coords)
    if not defaultMp then
        local bestDistance = 0.75
        for _, entry in ipairs(Config.defaultMediaPlayers or {}) do
            if type(entry) == "table" then
                local position = ToVector3(entry.position)
                local distance = position and #(coords - position) or nil
                if distance and distance < bestDistance then
                    bestDistance = distance
                    defaultMp = entry
                end
            end
        end
    end
    if defaultMp then
        local position = ToVector3(defaultMp.position)
        if position then
            return GetHandleFromCoords(position), defaultMp
        end
    end

    return nil, nil
end

local function getHandleDistance(playerPos, handle, info, knownEntity)
    local bestDistance = nil
    if info.coords then
        local coords = ToVector3(info.coords)
        if coords then
            bestDistance = #(playerPos - coords)
        end
    elseif knownEntity and DoesEntityExist(knownEntity) then
        bestDistance = #(playerPos - GetEntityCoords(knownEntity))
    else
        local player = GetActivePlayer(handle)
        if player and player.entity and DoesEntityExist(player.entity) then
            bestDistance = #(playerPos - GetEntityCoords(player.entity))
        end
    end

    if type(info) == "table" and type(info.linkedSpeakers) == "table" then
        for _, speaker in ipairs(info.linkedSpeakers) do
            local coords = speaker and speaker.coords or speaker
            local speakerCoords = ToVector3(coords)
            if speakerCoords then
                local speakerDistance = #(playerPos - speakerCoords)
                if not bestDistance or speakerDistance < bestDistance then
                    bestDistance = speakerDistance
                end
            end
        end
    end

    return bestDistance or -1
end

local function getHandleRangeState(handle)
    if not handleRangeState[handle] then
        handleRangeState[handle] = {
            lastDistance = -1,
            lastSeenAt = 0,
            inRange = false,
        }
    end
    return handleRangeState[handle]
end

local function getSmoothedHandleDistance(handle, rawDistance, nowMs)
    local state = getHandleRangeState(handle)
    if rawDistance and rawDistance >= 0 then
        state.lastDistance = rawDistance
        state.lastSeenAt = nowMs
        return rawDistance, state
    end

    if state.lastDistance and state.lastDistance >= 0 and (nowMs - (state.lastSeenAt or 0)) <= 2000 then
        return state.lastDistance, state
    end

    return -1, state
end

local function getVehicleLabel(model)
    if not model then
        return nil
    end

    local displayName = GetDisplayNameFromVehicleModel(model)
    if not displayName or displayName == "" or displayName == "CARNOTFOUND" then
        return nil
    end

    local localized = GetLabelText(displayName)
    if localized and localized ~= "NULL" then
        return localized
    end

    return displayName
end

local function resolveEntityLabel(modelConfig, defaultMp, model, entityType)
    if defaultMp and type(defaultMp.label) == "string" and defaultMp.label ~= "" then
        return defaultMp.label
    end

    if modelConfig and type(modelConfig.label) == "string" and modelConfig.label ~= "" then
        return modelConfig.label
    end

    if entityType == "vehicle" then
        return getVehicleLabel(model) or "Vehicle"
    end

    return "Device"
end

local function resolveActiveLabel(handle, info, player)
    if info and type(info.label) == "string" and info.label ~= "" then
        return info.label
    end

    if info and info.coords then
        local coords = ToVector3(info.coords)
        local defaultMp = GetDefaultMediaPlayer(Config.defaultMediaPlayers, coords)
        if defaultMp and type(defaultMp.label) == "string" and defaultMp.label ~= "" then
            return defaultMp.label
        end
    end

    if player and player.entity and DoesEntityExist(player.entity) then
        local model = GetEntityModel(player.entity)
        local modelConfig = GetModelConfig(model)
        return resolveEntityLabel(modelConfig, nil, model, player.entityType)
    end

    return "Device"
end

local function normalizePlaybackOffset(offset, info)
    offset = math.max(0.0, tonumber(offset) or 0.0)
    local duration = tonumber(info and info.duration)
    if duration and duration > 0 then
        if info and (info.loop == true or info.loopMode == "track") then
            offset = offset % duration
        elseif offset > duration then
            offset = duration
        end
    end
    return offset
end

local function getSyncLatencySeconds(payload)
    local latencyMs = tonumber(payload and payload._latencyMs) or 0
    if latencyMs < 0 then
        latencyMs = 0
    end

    local maxLatencyMs = maxSyncCompensationSeconds * 1000
    if latencyMs > maxLatencyMs then
        latencyMs = maxLatencyMs
    end

    return latencyMs / 1000.0
end

local function updateSnapshot(handle, info, syncLatencySeconds)
    local offset = tonumber(info.offset) or 0.0
    local latencySeconds = tonumber(syncLatencySeconds) or 0.0
    if info.paused ~= true then
        offset = offset + latencySeconds
    end

    offset = normalizePlaybackOffset(offset, info)
    info.offset = offset

    syncSnapshots[handle] = {
        offset = offset,
        paused = info.paused and true or false,
        duration = tonumber(info.duration),
        receivedAt = GetGameTimer(),
        latencySeconds = latencySeconds,
    }
end

local function getStateRevision(info)
    local revision = tonumber(info and info.stateRevision)
    if revision ~= nil and revision >= 0 then
        return revision
    end
    return nil
end

local function getInterpolatedOffset(handle, info, nowMs)
    local snapshot = syncSnapshots[handle]
    local baseOffset = tonumber(info.offset) or 0.0

    if snapshot then
        baseOffset = snapshot.offset
    end

    if not info.paused and snapshot and snapshot.receivedAt then
        local elapsedSeconds = math.max(0.0, (nowMs - snapshot.receivedAt) / 1000.0)
        baseOffset = baseOffset + elapsedSeconds
    end

    return normalizePlaybackOffset(baseOffset, info)
end

local function getConfiguredPlaybackRange(info)
    local defaultRange = tonumber(Config.defaultRange) or 30.0
    local maxRange = tonumber(Config.maxRange) or defaultRange
    local range = tonumber(info and info.range) or defaultRange

    if maxRange > 0 and range > maxRange then
        range = maxRange
    end

    return math.max(0.0, range)
end

local function isHandleAudibleForNearby(handle, info, distance, entity, entityType)
    if type(info) ~= "table" or type(info.url) ~= "string" or info.url == "" then
        return false
    end

    if info.paused == true or info.muted == true then
        return false
    end

    local volume = tonumber(info.volume)
    if volume and volume <= 0 then
        return false
    end

    if isSameRoom(nil, entity, entityType, info.isVehicle) ~= true then
        local diffRoomVolume = tonumber(info.diffRoomVolume)
        if diffRoomVolume and diffRoomVolume <= 0 then
            return false
        end
    end

    local numericDistance = tonumber(distance) or -1
    if numericDistance < 0 then
        return false
    end

    local range = getConfiguredPlaybackRange(info)
    if range <= 0 then
        return numericDistance <= 0.5
    end

    return numericDistance <= (range + 0.5)
end

local function getEffectivePlaybackVolume(info)
    local deviceVolume = tonumber(info and info.volume) or 100
    local localVolume = type(GetBaseVolume) == "function" and tonumber(GetBaseVolume()) or 100
    return Clamp((deviceVolume * localVolume) / 100, 0, 100, deviceVolume)
end

local function getClosestActiveHandle(maxDistance)
    local playerPos = GetEntityCoords(PlayerPedId())
    local nearby = GetNearbyActiveMediaPlayers(playerPos, mediaPlayerStates)

    for _, entry in ipairs(nearby) do
        if (entry.distance and entry.distance >= 0 and entry.distance <= maxDistance)
            or isHandleAudibleForNearby(entry.handle, entry.info, entry.distance, entry.player and entry.player.entity or nil, entry.player and entry.player.entityType or nil) then
            return entry.handle
        end
    end

    return nil
end

local function getUiDiscoveryRefreshMs()
    if type(GetSelectedUiHandle) == "function" and GetSelectedUiHandle() ~= nil then
        return 300
    end
    if type(GetAdminDiscoveryRange) == "function" and GetAdminDiscoveryRange() ~= nil then
        return 450
    end
    return 650
end

RegisterNetEvent("pmms:startupAttempt", function(payload)
    if type(payload) ~= "table" or not payload.handle or not payload.attemptId or type(payload.resolvedOptions) ~= "table" then
        PMMSDebug("player", "client startup attempt ignored: invalid payload", {
            payloadType = type(payload),
            handle = payload and payload.handle or nil,
            attemptId = payload and payload.attemptId or nil,
        })
        return
    end

    PMMSDebug("player", "client startup attempt received", {
        handle = payload.handle,
        attemptId = payload.attemptId,
        playbackToken = payload.playbackToken,
        phase = payload.phase,
        startupTimeoutMs = payload.startupTimeoutMs,
        url = redactUrlForDebug(payload.resolvedOptions.originalUrl or payload.resolvedOptions.url),
        resolvedUrl = redactUrlForDebug(payload.resolvedOptions.resolvedUrl or payload.resolvedOptions.url),
        provider = payload.resolvedOptions.resolver and payload.resolvedOptions.resolver.provider or nil,
        instance = payload.resolvedOptions.resolver and payload.resolvedOptions.resolver.instance or nil,
        resolverStatus = payload.resolvedOptions.resolver and payload.resolvedOptions.resolver.status or nil,
    })
    failedPlayers[payload.handle] = nil
    StartMediaPlayerStartupAttempt(
        payload.handle,
        payload.attemptId,
        payload.resolvedOptions,
        payload.playbackToken,
        payload.startupTimeoutMs
    )
end)

RegisterNetEvent("pmms:startupStop", function(handle, attemptId, playbackToken)
    PMMSDebug("player", "client startup stop received", {
        handle = handle,
        attemptId = attemptId,
        playbackToken = playbackToken,
    })
    StopMediaPlayerStartupAttempt(handle, attemptId, playbackToken)
end)

RegisterNetEvent("pmms:start", function(handle)
    PMMSDebug("player", "client start received", {
        handle = handle,
    })
    failedPlayers[handle] = nil
end)

RegisterNetEvent("pmms:stop", function(handle)
    PMMSDebug("player", "client stop received", {
        handle = handle,
    })
    failedPlayers[handle] = nil
    DestroyMediaPlayer(handle)
    syncSnapshots[handle] = nil
    handleRangeState[handle] = nil
    startupStates[handle] = nil
    SendNUIMessage({
        type = "stop",
        handle = handle,
    })
end)

RegisterNetEvent("pmms:play", function(handle)
    failedPlayers[handle] = nil
end)

local function removeStateKey(collection, key)
    if type(collection) ~= "table" then
        return
    end

    collection[key] = nil
    collection[tostring(key)] = nil

    local numericKey = tonumber(key)
    if numericKey ~= nil then
        collection[numericKey] = nil
    end
end

local function removeStateKeys(collection, keys)
    if type(keys) ~= "table" then
        return
    end

    for _, key in ipairs(keys) do
        removeStateKey(collection, key)
    end
end

local function applyStateUpdates(collection, updates)
    if type(collection) ~= "table" or type(updates) ~= "table" then
        return
    end

    for key, value in pairs(updates) do
        removeStateKey(collection, key)
        collection[key] = value
    end
end

local function applyFullSyncPayload(payload)
    if type(payload) == "table" and payload.mediaPlayers then
        mediaPlayerStates = payload.mediaPlayers or {}
        startupStates = payload.startupStates or {}
        deviceSessions = payload.deviceSessions or {}
        adminSyncState = payload.admin
    else
        mediaPlayerStates = payload or {}
        startupStates = {}
        deviceSessions = {}
        adminSyncState = nil
    end

    hasReceivedFullSync = true
end

local function applyDeltaSyncPayload(payload)
    if type(payload) ~= "table" then
        return false
    end

    local removed = type(payload.removed) == "table" and payload.removed or {}
    removeStateKeys(mediaPlayerStates, removed.mediaPlayers)
    removeStateKeys(startupStates, removed.startupStates)
    removeStateKeys(deviceSessions, removed.deviceSessions)

    applyStateUpdates(mediaPlayerStates, payload.mediaPlayers)
    applyStateUpdates(startupStates, payload.startupStates)
    applyStateUpdates(deviceSessions, payload.deviceSessions)

    if payload.adminRemoved == true then
        adminSyncState = nil
    elseif payload.admin ~= nil then
        adminSyncState = payload.admin
    end

    return true
end

local function reconcileSyncState(syncType, syncLatencySeconds)
    local now = GetGameTimer()
    PMMSDebug("player", "client sync received", {
        syncType = syncType,
        mediaPlayerCount = countTableEntries(mediaPlayerStates),
        startupStateCount = countTableEntries(startupStates),
        deviceSessionCount = countTableEntries(deviceSessions),
        latencySeconds = syncLatencySeconds,
    })

    for handle, info in pairs(mediaPlayerStates) do
        local incomingRevision = getStateRevision(info)
        local incomingUrl = type(info) == "table" and info.url or nil
        local incomingToken = getPlaybackToken(info)
        local failureState = failedPlayers[handle]
        local failureRevision = tonumber(failureState and failureState.stateRevision) or nil
        local failureUrl = type(failureState) == "table" and failureState.url or nil
        local failureToken = type(failureState) == "table" and failureState.playbackToken or nil

        if failureState and (
            (incomingToken and failureToken and incomingToken ~= failureToken)
            or (incomingRevision and failureRevision and incomingRevision > failureRevision)
            or (type(incomingUrl) == "string" and incomingUrl ~= "" and type(failureUrl) == "string" and failureUrl ~= "" and incomingUrl ~= failureUrl)
        ) then
            failedPlayers[handle] = nil
        end

        updateSnapshot(handle, info, syncLatencySeconds)
    end

    for handle, startupState in pairs(startupStates) do
        local failureState = failedPlayers[handle]
        if failureState
            and not mediaPlayerStates[handle]
            and type(startupState) == "table"
            and (
                startupState.phase == "failed"
                or startupState.phase == "timed_out"
                or startupState.phase == "stopped"
                or startupState.phase == "superseded"
            ) then
            failedPlayers[handle] = nil
        end
    end

    for handle, player in pairs(GetActivePlayers()) do
        if not mediaPlayerStates[handle] then
            local keepPendingStart = player.pendingStart
                and startupStates[handle]
                and tostring(startupStates[handle].attemptId) == tostring(player.startupAttemptId)
            if not keepPendingStart then
                DestroyMediaPlayer(handle)
                syncSnapshots[handle] = nil
                handleRangeState[handle] = nil
            end
        end
    end

    for handle, snapshot in pairs(syncSnapshots) do
        if not mediaPlayerStates[handle] and (now - (snapshot.receivedAt or 0)) > 2000 then
            syncSnapshots[handle] = nil
        end
    end

    for handle in pairs(handleRangeState) do
        if not mediaPlayerStates[handle] then
            handleRangeState[handle] = nil
        end
    end

    for handle in pairs(failedPlayers) do
        if not mediaPlayerStates[handle] and not startupStates[handle] then
            failedPlayers[handle] = nil
        end
    end

    if not isInitialized then
        isInitialized = true
        autoDisableStaticEmitters()
    end
end

local function requestInitialStateSync(minIntervalMs)
    local now = GetGameTimer()
    local interval = tonumber(minIntervalMs) or 1000
    if lastFullSyncRequestAt ~= 0 and (now - lastFullSyncRequestAt) < interval then
        return false
    end

    lastFullSyncRequestAt = now
    TriggerServerEvent("pmms:loadSettings")
    TriggerServerEvent("pmms:loadPermissions")
    return true
end

RegisterNetEvent("pmms:sync", function(payload)
    local syncLatencySeconds = getSyncLatencySeconds(payload)
    applyFullSyncPayload(payload)
    reconcileSyncState("full", syncLatencySeconds)
end)

RegisterNetEvent("pmms:syncDelta", function(payload)
    local syncLatencySeconds = getSyncLatencySeconds(payload)
    if not hasReceivedFullSync then
        requestInitialStateSync(2000)
        return
    end

    if applyDeltaSyncPayload(payload) then
        reconcileSyncState("delta", syncLatencySeconds)
    end
end)

RegisterNetEvent("pmms:loadSettings", function(models, defaultMPs)
    if models then
        for model, data in pairs(models) do
            modelSettings[model] = data
            Config.models[model] = data
        end
    end

    if type(InvalidateModelConfigCache) == "function" then
        InvalidateModelConfigCache()
    end

    if defaultMPs then
        defaultMediaPlayers = defaultMPs
        Config.defaultMediaPlayers = defaultMPs
    end

    InvalidateEntityCache()
    cachedUsableMediaPlayers = {}
    lastUsableMediaPlayersBuild = 0
end)

RegisterNetEvent("pmms:startClosestMediaPlayer", function(options)
    local playerPos = GetEntityCoords(PlayerPedId())
    local closest = GetClosestEntity(playerPos)

    if not closest then
        ShowNotification("No media player in range", nil, "#ff4444")
        return
    end

    local netId = getEntityNetworkId(closest.entity)
    if not netId then
        ShowNotification("No media player in range", nil, "#ff4444")
        return
    end

    options = options or {}

    TriggerServerEvent("pmms:start", netId, options)
end)

RegisterNetEvent("pmms:pauseClosestMediaPlayer", function()
    local handle = getClosestActiveHandle(Config.maxDiscoveryDistance or 30.0)
    if handle then
        TriggerServerEvent("pmms:pause", handle)
    else
        ShowNotification("No active media player in range", nil, "#ff4444")
    end
end)

RegisterNetEvent("pmms:stopClosestMediaPlayer", function()
    local handle = getClosestActiveHandle(Config.maxDiscoveryDistance or 30.0)
    if handle then
        TriggerServerEvent("pmms:stop", handle)
    else
        ShowNotification("No active media player in range", nil, "#ff4444")
    end
end)

Citizen.CreateThread(function()
    requestInitialStateSync(0)
    local discoveryJitterMs = type(GetDiscoveryJoinJitterMs) == "function" and tonumber(GetDiscoveryJoinJitterMs()) or 0
    if discoveryJitterMs and discoveryJitterMs > 0 then
        Citizen.Wait(discoveryJitterMs)
    end

    while true do
        local selectedHandle = type(GetSelectedUiHandle) == "function" and GetSelectedUiHandle() or nil
        local waitTime = IsUiOpen() and (selectedHandle ~= nil and 250 or 500) or 1000
        local playerPos = GetEntityCoords(PlayerPedId())
        local maxRange = Config.maxRange or 60.0
        local rangeBuffer = 5.0
        local nowMs = GetGameTimer()
        local permissions = GetPermissions() or {}
        local defaultDiscovery = tonumber(Config.maxDiscoveryDistance) or 30.0
        local adminRange = type(GetAdminDiscoveryRange) == "function" and GetAdminDiscoveryRange() or nil
        local discoveryDistance = defaultDiscovery
        if (permissions.manage == true or permissions.overrideDevice == true) and adminRange then
            local cap = tonumber(Config.adminMaxRange) or tonumber(Config.maxRange) or defaultDiscovery
            discoveryDistance = math.max(defaultDiscovery, math.min(tonumber(adminRange) or defaultDiscovery, cap))
        end

        for handle, info in pairs(mediaPlayerStates) do
            local player = GetActivePlayer(handle)
            local failState = failedPlayers[handle]
            local failRetryAt = type(failState) == "table" and tonumber(failState.nextRetryAt) or tonumber(failState)
            local failToken = type(failState) == "table" and failState.playbackToken or nil
            local infoToken = getPlaybackToken(info)
            local entity, model, entityType = findEntityForHandle(handle, info)
            local rawDistance = getHandleDistance(playerPos, handle, info, entity)
            local distance, rangeState = getSmoothedHandleDistance(handle, rawDistance, nowMs)
            local enterThreshold = maxRange + 1.0
            local exitThreshold = maxRange + rangeBuffer

            if distance >= 0 and distance <= enterThreshold then
                waitTime = math.min(waitTime, 500)
                if not player and info.url then
                    if not failRetryAt or (failToken and infoToken and failToken ~= infoToken) or nowMs >= failRetryAt then
                        InitMediaPlayer(handle, info, entity, model, entityType, nil, infoToken)
                        player = GetActivePlayer(handle)
                        if player then
                            failedPlayers[handle] = nil
                        end
                    end
                end
                rangeState.inRange = true
            elseif player and (
                (distance >= 0 and distance > exitThreshold)
                or (distance < 0 and (nowMs - (rangeState.lastSeenAt or 0)) > 4500)
            ) then
                DestroyMediaPlayer(handle)
                player = nil
                rangeState.inRange = false
            end

            if info.scaleform and info.scaleform.attached then
                if entity and NetworkGetEntityIsNetworked(entity) then
                    local mediaPos = GetEntityCoords(entity)
                    local mediaRot = GetEntityRotation(entity, 0)

                    local r = math.rad(mediaRot.z)
                    local cosr = math.cos(r)
                    local sinr = math.sin(r)

                    local posX = (info.scaleform.position.x * cosr - info.scaleform.position.y * sinr) + mediaPos.x
                    local posY = (info.scaleform.position.y * cosr + info.scaleform.position.x * sinr) + mediaPos.y
                    local posZ = info.scaleform.position.z + mediaPos.z

                    info.scaleform.finalPosition = vector3(posX, posY, posZ)
                    info.scaleform.finalRotation = -(mediaRot + info.scaleform.rotation)
                elseif info.scaleform.finalPosition and info.scaleform.finalRotation then
                    info.scaleform.finalPosition = nil
                    info.scaleform.finalRotation = nil
                end
            end

            if player then
                if infoToken and tostring(player.playbackToken or "") ~= tostring(infoToken) then
                    player.playbackToken = infoToken
                    if type(player.options) == "table" then
                        player.options.playbackToken = infoToken
                    end
                end

                if entity and (player.entity ~= entity or player.model ~= model or player.entityType ~= entityType) then
                    LinkEntityToMediaPlayer(handle, entity, model, entityType)
                elseif not entity and player.entity then
                    UnlinkEntityFromMediaPlayer(handle)
                end

                if player.pendingStart then
                    MarkStartupAttemptReady(handle, player.startupAttemptId, info, infoToken)
                end

                local effectiveEqProfile = type(GetEffectiveEqProfileForDui) == "function" and GetEffectiveEqProfileForDui(info.equalizerProfile) or info.equalizerProfile
                local eqSignature = effectiveEqProfile and json.encode(effectiveEqProfile) or ""
                if player.equalizerProfileSignature ~= eqSignature then
                    player.browser:sendMessage({ type = "applyEqProfile", profile = effectiveEqProfile })
                    player.equalizerProfileSignature = eqSignature
                end

                local currentOffset = getInterpolatedOffset(handle, info, nowMs)
                local renderBuffer = tonumber(Config.dui and Config.dui.renderDistanceBuffer) or 5.0
                local playbackRange = getConfiguredPlaybackRange(info)
                local visualSurfaceActive = info.video ~= false and (
                    player.browser.renderTarget ~= nil
                    or player.browser.sfHandle ~= nil
                    or player.browser.scaleform ~= nil
                )
                player.browser:setRenderState(
                    visualSurfaceActive
                    and distance >= 0
                    and distance <= (playbackRange + renderBuffer)
                )

                player.browser:sendMessage({
                    type = "update",
                    handle = handle,
                    distance = distance,
                    volume = LocalPlayerVolumes[handle] or getEffectivePlaybackVolume(info),
                    offset = currentOffset,
                    options = info,
                    sameRoom = isSameRoom(playerPos, entity, entityType, info.isVehicle),
                })
            end
        end

        Citizen.Wait(waitTime)
        local uiNow = GetGameTimer()

        if IsUiOpen() and (uiNow - lastUpdateUi) >= 250 then
            lastUpdateUi = uiNow
            local uiPlayerPos = GetEntityCoords(PlayerPedId())
            local usableMediaPlayers = cachedUsableMediaPlayers

            if (uiNow - lastUsableMediaPlayersBuild) >= getUiDiscoveryRefreshMs() then
                lastUsableMediaPlayersBuild = uiNow
                usableMediaPlayers = {}
                local entities = GetEntityDistanceSorted(uiPlayerPos)
                local visibleHandles = {}

                for _, entry in ipairs(entities) do
                    if entry.distance <= discoveryDistance then
                        local netId = getEntityNetworkId(entry.entity)
                        if netId then
                            local modelConfig = GetModelConfig(entry.model)
                            local persistentHandle, defaultMp = getPersistentDeviceForEntity(entry.entity)
                            local resolvedHandle = persistentHandle or netId
                            local resolvedKey = tostring(resolvedHandle)
                            local label = resolveEntityLabel(modelConfig, defaultMp, entry.model, entry.type)

                            if not visibleHandles[resolvedKey] then
                                usableMediaPlayers[#usableMediaPlayers + 1] = {
                                    handle = resolvedHandle,
                                    label = label,
                                    type = entry.type,
                                    distance = entry.distance,
                                    active = mediaPlayerStates[resolvedHandle] ~= nil or mediaPlayerStates[resolvedKey] ~= nil or startupStates[resolvedHandle] ~= nil or startupStates[resolvedKey] ~= nil,
                                    hasVideo = modelConfig and modelConfig.renderTarget ~= nil or false,
                                    visibleBecause = "nearby",
                                    coords = {
                                        x = entry.coords.x,
                                        y = entry.coords.y,
                                        z = entry.coords.z,
                                    },
                                }
                                visibleHandles[resolvedKey] = true
                            end
                        end
                    end
                end

                for handle, info in pairs(mediaPlayerStates) do
                    local key = tostring(handle)
                    if not visibleHandles[key] then
                        local player = GetActivePlayer(handle)
                        local entity, model, entityType = findEntityForHandle(handle, info)
                        if not entity and player and player.entity and DoesEntityExist(player.entity) then
                            entity = player.entity
                            model = player.model
                            entityType = player.entityType
                        end

                        local rawDistance = getHandleDistance(uiPlayerPos, handle, info, entity)
                        local distance = select(1, getSmoothedHandleDistance(handle, rawDistance, uiNow))

                        if isHandleAudibleForNearby(handle, info, distance, entity, entityType) then
                            local label = resolveActiveLabel(handle, info, player)
                            local modelConfig = model and GetModelConfig(model) or nil
                            local coords = nil

                            if info.coords then
                                coords = ToPlainCoords(info.coords)
                            elseif entity and DoesEntityExist(entity) then
                                local entityCoords = GetEntityCoords(entity)
                                coords = {
                                    x = entityCoords.x,
                                    y = entityCoords.y,
                                    z = entityCoords.z,
                                }
                            end

                            usableMediaPlayers[#usableMediaPlayers + 1] = {
                                handle = handle,
                                label = label,
                                type = entityType or (info.isVehicle == true and "vehicle" or "object"),
                                distance = distance,
                                active = true,
                                hasVideo = info.video ~= false or (modelConfig and modelConfig.renderTarget ~= nil or false),
                                visibleBecause = "audible",
                                coords = coords,
                            }
                            visibleHandles[key] = true
                        end
                    end
                end

                for _, entry in ipairs(Config.defaultMediaPlayers or {}) do
                    if type(entry) == "table" then
                        local coords = ToVector3(entry.position)
                        local plain = ToPlainCoords(entry.position)
                        if coords and plain then
                            local handle = GetHandleFromCoords(coords)
                            local key = tostring(handle)
                            if not visibleHandles[key] then
                                local dist = #(uiPlayerPos - coords)
                                if dist <= discoveryDistance then
                                    usableMediaPlayers[#usableMediaPlayers + 1] = {
                                        handle = handle,
                                        label = entry.label or entry.name or "Persistent Device",
                                        type = entry.mode == "interaction" and "interaction" or (entry.propModel and "prop" or "device"),
                                        distance = dist,
                                        active = mediaPlayerStates[handle] ~= nil or mediaPlayerStates[key] ~= nil or startupStates[handle] ~= nil or startupStates[key] ~= nil,
                                        hasVideo = entry.video ~= false and entry.mode ~= "interaction",
                                        visibleBecause = "persistent",
                                        coords = plain,
                                    }
                                    visibleHandles[key] = true
                                end
                            end
                        end
                    end
                end

                if type(adminSyncState) == "table" and type(adminSyncState.devices) == "table" then
                    for _, dev in ipairs(adminSyncState.devices) do
                        local devPos = ToVector3(dev.coords)
                        local devCoords = ToPlainCoords(dev.coords)
                        local handle = tostring(dev.handle or (devPos and GetHandleFromCoords(devPos)) or "")
                        if handle ~= "" and not visibleHandles[handle] and devPos and devCoords then
                            local dist = #(uiPlayerPos - devPos)
                            if dist <= discoveryDistance then
                                usableMediaPlayers[#usableMediaPlayers + 1] = {
                                    handle = handle,
                                    label = dev.label,
                                    type = dev.type == "interaction" and "interaction" or "prop",
                                    distance = dist,
                                    active = mediaPlayerStates[handle] ~= nil or startupStates[handle] ~= nil,
                                    hasVideo = false,
                                    visibleBecause = "admin",
                                    coords = devCoords,
                                }
                                visibleHandles[handle] = true
                            end
                        end
                    end
                end

                table.sort(usableMediaPlayers, function(a, b)
                    local aDistance = tonumber(a and a.distance) or math.huge
                    local bDistance = tonumber(b and b.distance) or math.huge
                    if aDistance == bDistance then
                        return tostring(a and a.handle or "") < tostring(b and b.handle or "")
                    end
                    return aDistance < bDistance
                end)

                cachedUsableMediaPlayers = usableMediaPlayers
            end

            local activeMediaPlayersUI = {}
            for handle, info in pairs(mediaPlayerStates) do
                local player = GetActivePlayer(handle)
                local entity, _, entityType = findEntityForHandle(handle, info)
                if not entity and player and player.entity and DoesEntityExist(player.entity) then
                    entity = player.entity
                    entityType = player.entityType
                end
                local rawDistance = getHandleDistance(uiPlayerPos, handle, info, entity)
                local distance = select(1, getSmoothedHandleDistance(handle, rawDistance, uiNow))
                local currentOffset = getInterpolatedOffset(handle, info, uiNow)
                local audibleVisible = isHandleAudibleForNearby(handle, info, distance, entity, entityType)
                local canInteract = permissions.manage == true
                    or (distance >= 0 and distance <= discoveryDistance)
                    or audibleVisible

                local uiInfo = info
                local localVol = LocalPlayerVolumes[handle]
                if localVol then
                    uiInfo = {}
                    for k,v in pairs(info) do uiInfo[k] = v end
                    uiInfo.volume = localVol
                end

                activeMediaPlayersUI[tostring(handle)] = {
                    handle = handle,
                    info = uiInfo,
                    offset = currentOffset,
                    distance = distance,
                    label = resolveActiveLabel(handle, info, player),
                    canInteract = canInteract,
                    visibleBecause = audibleVisible and distance > discoveryDistance and "audible" or "nearby",
                }
            end

            local payload = {
                type = "updateUi",
                uiIsOpen = true,
                activeMediaPlayers = activeMediaPlayersUI,
                deviceSessions = deviceSessions,
                usableMediaPlayers = usableMediaPlayers,
                startupStates = startupStates,
                failedPlayers = failedPlayers,
                permissions = permissions,
                baseVolume = GetBaseVolume(),
                admin = {
                    adminState = adminSyncState,
                    propModels = BuildPropModelsForClient(),
                    speakerModels = BuildSpeakerModelsForClient(),
                    deviceProfiles = BuildDeviceProfilesForClient(),
                    adminMaxRange = Config.adminMaxRange or Config.maxRange,
                },
            }
            sendUiUpdateIfChanged(true, payload, buildUiStateSignature(true, activeMediaPlayersUI, usableMediaPlayers, permissions), 1500)
        elseif (uiNow - lastUpdateUi) > 1000 then
            lastUpdateUi = uiNow
            local payload = {
                type = "updateUi",
                uiIsOpen = false,
                startupStates = startupStates,
                deviceSessions = deviceSessions,
                failedPlayers = failedPlayers,
                permissions = permissions,
            }
            sendUiUpdateIfChanged(false, payload, buildUiStateSignature(false, nil, nil, permissions), 5000)
        end

    end
end)

RegisterNetEvent("pmms:perf:request", function()
    local duiStats = type(GetDuiBrowserPerfStats) == "function" and GetDuiBrowserPerfStats() or {}
    local entityStats = type(GetEntityCacheStats) == "function" and GetEntityCacheStats() or {}
    local uiStats = GetUiPerfStats()
    local message = (
        "DUI total=%s renderable=%s rendered=%s lastFrame=%sms | entities cached=%s networked=%s scan=%sms | UI payload=%s bytes"
    ):format(
        tostring(duiStats.total or 0),
        tostring(duiStats.renderable or 0),
        tostring(duiStats.rendered or 0),
        tostring(duiStats.lastFrameMs or 0),
        tostring(entityStats.cached or 0),
        tostring(entityStats.networkedCount or 0),
        tostring(entityStats.lastScanMs or 0),
        tostring(uiStats.lastPayloadBytes or 0)
    )
    print("[7-pmms][perf] " .. message)
    ShowNotification(message, "7-PMMS Perf")
end)

Citizen.CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local usableMediaPlayers = {}
        local seenInteractions = {}

        for _, entry in ipairs(Config.defaultMediaPlayers or {}) do
            if type(entry) == "table" and entry.mode == "interaction" then
                local coords = ToVector3(entry.position)
                local plain = ToPlainCoords(entry.position)
                if coords and plain then
                    local handle = GetHandleFromCoords(coords)
                    local key = tostring(handle)
                    seenInteractions[key] = true
                    usableMediaPlayers[#usableMediaPlayers + 1] = {
                        handle = handle,
                        label = entry.label or entry.name or "Interaction Point",
                        type = "interaction",
                        coords = plain,
                    }
                end
            end
        end

        for _, row in ipairs(cachedUsableMediaPlayers or {}) do
            if row.type == "interaction" and row.coords then
                local key = tostring(row.handle or "")
                if key == "" or not seenInteractions[key] then
                    usableMediaPlayers[#usableMediaPlayers + 1] = row
                    if key ~= "" then
                        seenInteractions[key] = true
                    end
                end
            end
        end

        for _, mp in ipairs(usableMediaPlayers) do
            if mp.type == "interaction" and mp.coords then
                local mpPos = ToVector3(mp.coords)
                local dist = mpPos and #(pos - mpPos) or nil
                if dist and dist < 5.0 then
                    sleep = 0
                    DrawMarker(27, mpPos.x, mpPos.y, mpPos.z - 0.95, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 1.0, 104, 216, 166, 100, false, false, 2, false, nil, nil, false)
                    if dist < 1.5 then
                        SetTextComponentFormat("STRING")
                        AddTextComponentString("Press ~INPUT_CONTEXT~ to open " .. tostring(mp.label))
                        DisplayHelpTextFromStringLabel(0, 0, 1, -1)
                        if IsControlJustPressed(0, 38) then
                            TriggerEvent("pmms:openUiForHandle", mp.handle)
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler("onResourceStop", function(name)
    if name == GetCurrentResourceName() then
        DestroyAllMediaPlayers()
        autoEnableStaticEmitters()
    end
end)

AddEventHandler("onClientResourceStart", function(name)
    if name == GetCurrentResourceName() then
        requestInitialStateSync(1000)
    end
end)
