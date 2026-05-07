local mediaPlayerStates = {}
local startupStates = {}
local deviceSessions = {}
local modelSettings = {}
local defaultMediaPlayers = {}
local disabledStaticEmitters = {}
local syncSnapshots = {}
local isInitialized = false
local lastUpdateUi = 0
local failedPlayers = {}
local handleRangeState = {}
local cachedUsableMediaPlayers = {}
local lastUsableMediaPlayersBuild = 0

local function countTableEntries(value)
    local count = 0
    if type(value) == "table" then
        for _ in pairs(value) do
            count = count + 1
        end
    end
    return count
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

local function getHandleDistance(playerPos, handle, info, knownEntity)
    if info.coords then
        local coords = vector3(info.coords.x, info.coords.y, info.coords.z)
        return #(playerPos - coords)
    end

    if knownEntity and DoesEntityExist(knownEntity) then
        return #(playerPos - GetEntityCoords(knownEntity))
    end

    local player = GetActivePlayer(handle)
    if player and player.entity and DoesEntityExist(player.entity) then
        return #(playerPos - GetEntityCoords(player.entity))
    end

    return -1
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
        local coords = vector3(info.coords.x, info.coords.y, info.coords.z)
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

local function updateSnapshot(handle, info)
    syncSnapshots[handle] = {
        offset = tonumber(info.offset) or 0.0,
        paused = info.paused and true or false,
        duration = tonumber(info.duration),
        receivedAt = GetGameTimer(),
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

    local duration = tonumber(info.duration)
    if duration and duration > 0 then
        if info.loop then
            baseOffset = baseOffset % duration
        elseif baseOffset > duration then
            baseOffset = duration
        end
    end

    return baseOffset
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
        url = payload.resolvedOptions.originalUrl or payload.resolvedOptions.url,
        resolvedUrl = payload.resolvedOptions.resolvedUrl or payload.resolvedOptions.url,
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

RegisterNetEvent("pmms:sync", function(payload)
    local previousStates = mediaPlayerStates
    if type(payload) == "table" and payload.mediaPlayers then
        mediaPlayerStates = payload.mediaPlayers or {}
        startupStates = payload.startupStates or {}
        deviceSessions = payload.deviceSessions or {}
    else
        mediaPlayerStates = payload or {}
        startupStates = {}
        deviceSessions = {}
    end
    local now = GetGameTimer()
    PMMSDebug("player", "client sync received", {
        mediaPlayerCount = countTableEntries(mediaPlayerStates),
        startupStateCount = countTableEntries(startupStates),
        deviceSessionCount = countTableEntries(deviceSessions),
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

        updateSnapshot(handle, info)
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
            if player.pendingStart and startupStates[handle] and tostring(startupStates[handle].attemptId) == tostring(player.startupAttemptId) then
                goto continue_active_player
            end
            DestroyMediaPlayer(handle)
            syncSnapshots[handle] = nil
            handleRangeState[handle] = nil
        end
        ::continue_active_player::
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
    TriggerServerEvent("pmms:loadSettings")
    TriggerServerEvent("pmms:loadPermissions")

    while true do
        local waitTime = IsUiOpen() and 240 or 1000
        local playerPos = GetEntityCoords(PlayerPedId())
        local maxRange = Config.maxRange or 60.0
        local rangeBuffer = 5.0
        local nowMs = GetGameTimer()
        local permissions = GetPermissions() or {}
        local discoveryDistance = tonumber(Config.maxDiscoveryDistance) or 30.0

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
                waitTime = math.min(waitTime, 170)
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

                local currentOffset = getInterpolatedOffset(handle, info, nowMs)

                player.browser:sendMessage({
                    type = "update",
                    handle = handle,
                    distance = distance,
                    volume = info.volume or 100,
                    offset = currentOffset,
                    options = info,
                    sameRoom = isSameRoom(playerPos, entity, entityType, info.isVehicle),
                })
            end
        end

        Citizen.Wait(waitTime)
        local uiNow = GetGameTimer()

        if IsUiOpen() and (uiNow - lastUpdateUi) >= 220 then
            lastUpdateUi = uiNow
            local uiPlayerPos = GetEntityCoords(PlayerPedId())
            local usableMediaPlayers = cachedUsableMediaPlayers

            if (uiNow - lastUsableMediaPlayersBuild) >= 650 then
                lastUsableMediaPlayersBuild = uiNow
                usableMediaPlayers = {}
                local entities = GetEntityDistanceSorted(uiPlayerPos)
                local visibleHandles = {}

                for _, entry in ipairs(entities) do
                    if entry.distance <= discoveryDistance then
                        local netId = getEntityNetworkId(entry.entity)
                        if netId then
                            local modelConfig = GetModelConfig(entry.model)
                            local defaultMp = GetDefaultMediaPlayer(Config.defaultMediaPlayers, entry.coords)
                            local label = resolveEntityLabel(modelConfig, defaultMp, entry.model, entry.type)

                            usableMediaPlayers[#usableMediaPlayers + 1] = {
                                handle = netId,
                                label = label,
                                type = entry.type,
                                distance = entry.distance,
                                active = mediaPlayerStates[netId] ~= nil or startupStates[netId] ~= nil,
                                hasVideo = modelConfig and modelConfig.renderTarget ~= nil or false,
                                visibleBecause = "nearby",
                                coords = {
                                    x = entry.coords.x,
                                    y = entry.coords.y,
                                    z = entry.coords.z,
                                },
                            }
                            visibleHandles[tostring(netId)] = true
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
                                coords = {
                                    x = info.coords.x,
                                    y = info.coords.y,
                                    z = info.coords.z,
                                }
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

                activeMediaPlayersUI[tostring(handle)] = {
                    handle = handle,
                    info = info,
                    offset = currentOffset,
                    distance = distance,
                    label = resolveActiveLabel(handle, info, player),
                    canInteract = canInteract,
                    visibleBecause = audibleVisible and distance > discoveryDistance and "audible" or "nearby",
                }
            end

            SendNUIMessage({
                type = "updateUi",
                uiIsOpen = true,
                activeMediaPlayers = activeMediaPlayersUI,
                deviceSessions = deviceSessions,
                usableMediaPlayers = usableMediaPlayers,
                startupStates = startupStates,
                failedPlayers = failedPlayers,
                permissions = permissions,
                baseVolume = GetBaseVolume(),
            })
        elseif (uiNow - lastUpdateUi) > 3000 then
            lastUpdateUi = uiNow
            SendNUIMessage({
                type = "updateUi",
                uiIsOpen = false,
                startupStates = startupStates,
                deviceSessions = deviceSessions,
                failedPlayers = failedPlayers,
                permissions = permissions,
            })
        end
    end
end)

AddEventHandler("onResourceStop", function(name)
    if name == GetCurrentResourceName() then
        DestroyAllMediaPlayers()
        autoEnableStaticEmitters()
    end
end)
