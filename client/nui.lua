local uiIsOpen = false
local baseVolume = 100
local baseVolumeKvpKey = "pmms:baseVolume:v1"
local tooltipsEnabled = true
local permissions = {}
local localEqProfile = nil
local selectedUiHandle = nil
local selectedUiDeviceType = nil
local throttledNuiCallbacks = {
    seekToTime = 250,
    seekBackward = 250,
    seekForward = 250,
    setVolume = 150,
    setRange = 400,
    setAttenuation = 400,
    setDiffRoomVolume = 400,
    setTransition = 400,
    setEqAnalyserActive = 250,
}
local nuiCallbackLastRunAt = {}

local function canRunNuiCallback(name, data)
    local throttleMs = throttledNuiCallbacks[name]
    if not throttleMs then
        return true
    end

    local now = GetGameTimer()
    local handle = type(data) == "table" and data.handle or "global"
    local key = name .. ":" .. tostring(handle or "global")
    local lastRunAt = nuiCallbackLastRunAt[key] or 0
    if now - lastRunAt < throttleMs then
        return false
    end

    nuiCallbackLastRunAt[key] = now
    return true
end

local function setBaseVolume(value)
    baseVolume = Clamp(value, 0, 100, 100)
    SetResourceKvp(baseVolumeKvpKey, tostring(baseVolume))
    return baseVolume
end

local function loadBaseVolume()
    local stored = GetResourceKvpString(baseVolumeKvpKey)
    if stored then
        baseVolume = Clamp(tonumber(stored), 0, 100, 100)
    end
end

loadBaseVolume()

local function shouldShowYoutubeProviderSelector()
    local resolver = type(Config.resolver) == "table" and Config.resolver or {}
    local browser = type(resolver.browserYoutube) == "table" and resolver.browserYoutube or {}
    return browser.hideProviderSelector == false
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

function IsUiOpen()
    return uiIsOpen
end

function GetBaseVolume()
    return baseVolume
end

function GetPermissions()
    return permissions
end

function GetSelectedUiHandle()
    return selectedUiHandle
end

function GetSelectedUiDeviceType()
    return selectedUiDeviceType
end

local function getQueueExpectedRevision(handle, payload)
    local explicit = tonumber(payload and (payload.queueRevision or payload.expectedRevision))
    if explicit then
        return explicit
    end

    local sessions = type(GetDeviceSessions) == "function" and GetDeviceSessions() or nil
    local session = sessions and (sessions[handle] or sessions[tostring(handle)])
    local revision = tonumber(session and session.queueRevision)
    if revision then
        return revision
    end

    local mediaPlayers = type(GetMediaPlayerStates) == "function" and GetMediaPlayerStates() or nil
    local state = mediaPlayers and (mediaPlayers[handle] or mediaPlayers[tostring(handle)])
    return tonumber(state and state.queueRevision) or tonumber(session and session.stateRevision) or tonumber(state and state.stateRevision)
end

local function isLocalEqProfileActive()
    return type(localEqProfile) == "table" and localEqProfile.enabled == true
end

function GetLocalEqProfile()
    return localEqProfile
end

function GetEffectiveEqProfileForDui(deviceProfile)
    if isLocalEqProfileActive() then
        return localEqProfile
    end
    if type(deviceProfile) == "table" then
        return deviceProfile
    end
    if type(localEqProfile) == "table" then
        return localEqProfile
    end
    return nil
end

function ApplyEffectiveEqProfileToBrowser(browser, deviceProfile)
    if browser and type(browser.sendMessage) == "function" then
        browser:sendMessage({ type = "applyEqProfile", profile = GetEffectiveEqProfileForDui(deviceProfile) })
    end
end

local function GetEntityFromDataHandle(handle)
    if handle and NetworkDoesEntityExistWithNetworkId(handle) then
        return NetworkGetEntityFromNetworkId(handle)
    end
    return nil
end

local function getVehiclePlateForHandle(handle)
    local entity = GetEntityFromDataHandle(handle)
    if entity and DoesEntityExist(entity) and IsEntityAVehicle(entity) then
        local plate = GetVehicleNumberPlateText(entity)
        if plate and plate ~= "" then
            return plate
        end
    end
    return nil
end

local function getModelNameFromHash(modelHash)
    for modelName in pairs(Config.models or {}) do
        if GetHashKey(modelName) == modelHash then
            return modelName
        end
    end
    return nil
end

local function buildDeviceAnchorPayload(handle)
    local entity = GetEntityFromDataHandle(handle)
    if not entity or not DoesEntityExist(entity) then
        return nil
    end

    local modelHash = GetEntityModel(entity)
    local modelName = getModelNameFromHash(modelHash)
    if not modelName then
        return nil
    end

    local coords = GetEntityCoords(entity)
    local rotation = GetEntityRotation(entity, 2)
    local modelConfig = GetModelConfig(modelHash) or GetModelConfig(modelName) or {}
    return {
        coords = { x = coords.x, y = coords.y, z = coords.z },
        propModel = modelName,
        label = modelConfig.label or modelName,
        heading = GetEntityHeading(entity),
        rotation = { x = rotation.x, y = rotation.y, z = rotation.z },
    }
end

function BuildDeviceProfilesForClient()
    local rows = {}
    for key, profile in pairs(Config.deviceProfiles or {}) do
        if type(profile) == "table" then
            rows[#rows + 1] = {
                key = key,
                label = profile.label or key,
                range = profile.range,
                volume = profile.volume,
                transitionSeconds = profile.transitionSeconds
            }
        end
    end
    table.sort(rows, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return rows
end

function BuildPropModelsForClient()
    local models = {}
    for key, data in pairs(Config.models or {}) do
        if type(data) == "table" and data.isPlaceable == true then
            local hash = type(key) == "number" and key or tonumber(key) or GetHashKey(key)
            if hash and IsModelInCdimage(hash) and IsModelValid(hash) then
                models[#models + 1] = {
                    model = key,
                    label = data.label or "Prop",
                    isTv  = data.renderTarget ~= nil,
                }
            end
        end
    end
    table.sort(models, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return models
end

function BuildSpeakerModelsForClient()
    local models = {}
    local speakerModels = Config.speakers and Config.speakers.models or nil
    if type(speakerModels) == "table" then
        for key, data in pairs(speakerModels) do
            local model = nil
            local label = nil
            local hidden = false

            if type(data) == "table" then
                model = data.model or (type(key) == "string" and key or nil)
                label = data.label or model
                hidden = data.isPlaceable == false
            elseif type(data) == "string" then
                model = data
                label = data
            end

            if model and model ~= "" and not hidden then
                models[#models + 1] = {
                    model = model,
                    label = label or model,
                    isTv = false,
                }
            end
        end
    end

    if #models == 0 and Config.speakers and type(Config.speakers.propModel) == "string" and Config.speakers.propModel ~= "" then
        models[#models + 1] = {
            model = Config.speakers.propModel,
            label = Config.speakers.propModel,
            isTv = false,
        }
    end

    table.sort(models, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return models
end

local adminDiscoveryRange = nil

RegisterNUICallback("setAdminDiscoveryRange", function(data, cb)
    local range = tonumber(data and data.range)
    adminDiscoveryRange = (range and range > 0) and range or nil
    if type(InvalidateEntityCache) == "function" then
        InvalidateEntityCache()
    end
    if type(InvalidateUiUpdateSignature) == "function" then
        InvalidateUiUpdateSignature()
    end
    cb(json.encode({}))
end)

function GetAdminDiscoveryRange()
    return adminDiscoveryRange
end


local function buildGlobalDeviceDefaults()
    return {
        volume = tonumber(Config.defaultVolume) or 100,
        attenuation = {
            sameRoom = tonumber(Config.defaultSameRoomAttenuation) or 4.0,
            diffRoom = tonumber(Config.defaultDiffRoomAttenuation) or 6.0,
        },
        diffRoomVolume = tonumber(Config.defaultDiffRoomVolume) or 0.25,
        range = tonumber(Config.defaultRange) or 30.0,
        transitionSeconds = tonumber(Config.defaultTransitionSeconds) or 5.0,
        isVehicle = Config.defaultVehicleMode == true,
    }
end

local function buildMediaPlayerDefaultsPayload(handle)
    local response = buildGlobalDeviceDefaults()
    local entity = GetEntityFromDataHandle(handle)

    if not entity or not DoesEntityExist(entity) then
        return response
    end

    local model = GetEntityModel(entity)
    local modelConfig = GetModelConfig(model)
    local coords = GetEntityCoords(entity)

    if modelConfig then
        response.label = modelConfig.label
        response.filter = modelConfig.filter
        response.volume = modelConfig.volume or response.volume
        response.attenuation = modelConfig.attenuation or response.attenuation
        response.diffRoomVolume = modelConfig.diffRoomVolume or response.diffRoomVolume
        response.range = modelConfig.range or response.range
        response.transitionSeconds = modelConfig.transitionSeconds or response.transitionSeconds
        response.isVehicle = modelConfig.isVehicle == true
        response.scaleform = modelConfig.scaleform and json.encode(modelConfig.scaleform) or nil
    end

    local defaultMp = GetDefaultMediaPlayer(Config.defaultMediaPlayers, coords)
    if defaultMp then
        for k, v in pairs(defaultMp) do
            if k ~= "position" and k ~= "url" then
                response[k] = v
            end
        end
        if defaultMp.scaleform then
            response.scaleform = json.encode(defaultMp.scaleform)
        end
    end

    return response
end

RegisterNUICallback("startup", function(_, cb)
    cb(json.encode({
        defaultSameRoomAttenuation = Config.defaultSameRoomAttenuation,
        defaultDiffRoomAttenuation = Config.defaultDiffRoomAttenuation,
        defaultDiffRoomVolume      = Config.defaultDiffRoomVolume,
        defaultRange               = Config.defaultRange,
        defaultVolume              = Config.defaultVolume,
        defaultVehicleMode         = Config.defaultVehicleMode,
        defaultTransitionSeconds   = Config.defaultTransitionSeconds,
        maxTransitionSeconds       = Config.maxTransitionSeconds,
        defaultSearchSource        = Config.defaultSearchSource or "youtube",
        maxRange                   = Config.maxRange,
        adminMaxRange              = Config.adminMaxRange or Config.maxRange,
        defaultScaleformName       = Config.defaultScaleformName,
        audioVisualizations        = Config.audioVisualizations,
        enableFilterByDefault      = Config.enableFilterByDefault,
        currentServerEndpoint      = GetCurrentServerEndpoint(),
        tooltipsEnabled            = tooltipsEnabled,
        searchSources              = Config.searchSources,
        searchMinimumBusyMs        = (Config.search and Config.search.minimumBusyMs) or 500,
        searchProxyThumbnails      = not (Config.search and Config.search.proxyThumbnails == false),
        showYoutubeProviderSelector = shouldShowYoutubeProviderSelector(),
        deviceDefaults             = buildGlobalDeviceDefaults(),
        baseVolume                 = GetBaseVolume(),
        debug                      = Config.debug,
        permissions                = permissions,
        deviceProfiles             = BuildDeviceProfilesForClient(),
        propModels                 = BuildPropModelsForClient(),
        speakerModels              = BuildSpeakerModelsForClient(),
        adminQuickActions          = Config.admin and Config.admin.quickActions or {},
        requestConfig              = Config.requests,
        speakerConfig              = Config.speakers,
        equalizerConfig            = Config.equalizer,
    }))
end)

RegisterNUICallback("closeUi", function(_, cb)
    HideUi()
    cb(json.encode({}))
end)

RegisterNUICallback("play", function(data, cb)
    PMMSDebug("nui", "NUI play callback", {
        handle = data and data.handle or nil,
        url = redactUrlForDebug(data and data.options and data.options.url or nil),
        title = data and data.options and data.options.title or nil,
        youtubeProvider = data and data.options and (data.options.youtubeProvider or data.options.resolverProvider) or nil,
    })
    if data.options and data.options.url and data.options.url ~= "" then
        data.options.vehiclePlate = data.options.vehiclePlate or getVehiclePlateForHandle(data.handle)
        TriggerServerEvent("pmms:start", data.handle, data.options)
    elseif data.handle then
        TriggerServerEvent("pmms:play", data.handle)
    end
    cb(json.encode({}))
end)

RegisterNUICallback("pause", function(data, cb)
    TriggerServerEvent("pmms:pause", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("stop", function(data, cb)
    PMMSDebug("nui", "NUI stop callback", {
        handle = data and data.handle or nil,
    })
    TriggerServerEvent("pmms:stop", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("playPlaylistTracks", function(data, cb)
    local trackCount = data and type(data.tracks) == "table" and #data.tracks or 0
    PMMSDebug("nui", "NUI playlist batch callback", {
        handle = data and data.handle or nil,
        playlistId = data and data.playlistId or nil,
        trackCount = trackCount,
    })
    if data and data.handle and type(data.tracks) == "table" and #data.tracks > 0 then
        TriggerServerEvent("pmms:playPlaylistTracks", data.handle, data.playlistId, data.tracks)
    end
    cb(json.encode({}))
end)

RegisterNUICallback("cancelStartup", function(data, cb)
    PMMSDebug("nui", "NUI cancel startup callback", {
        handle = data and data.handle or nil,
        attemptId = data and data.attemptId or nil,
        playbackToken = data and data.playbackToken or nil,
    })
    TriggerServerEvent("pmms:cancelStartup", data.handle, data.attemptId, data.playbackToken)
    cb(json.encode({}))
end)

RegisterNUICallback("lock", function(data, cb)
    TriggerServerEvent("pmms:lock", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("unlock", function(data, cb)
    TriggerServerEvent("pmms:unlock", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("enableVideo", function(data, cb)
    TriggerServerEvent("pmms:enableVideo", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("disableVideo", function(data, cb)
    TriggerServerEvent("pmms:disableVideo", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("mute", function(data, cb)
    TriggerServerEvent("pmms:mute", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("unmute", function(data, cb)
    TriggerServerEvent("pmms:unmute", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("copy", function(data, cb)
    TriggerServerEvent("pmms:copy", data.oldHandle, data.newHandle)
    cb(json.encode({}))
end)

RegisterNUICallback("setLoop", function(data, cb)
    TriggerServerEvent("pmms:setLoop", data.handle, data.loop)
    cb(json.encode({}))
end)

RegisterNUICallback("setLoopMode", function(data, cb)
    TriggerServerEvent("pmms:setLoopMode", data.handle, data.loopMode)
    cb(json.encode({}))
end)

RegisterNUICallback("lockSession", function(data, cb)
    TriggerServerEvent("pmms:lockSession", data.handle, data.pin)
    cb(json.encode({}))
end)

RegisterNUICallback("unlockSession", function(data, cb)
    TriggerServerEvent("pmms:unlockSession", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("setSessionPin", function(data, cb)
    TriggerServerEvent("pmms:setSessionPin", data.handle, data.pin)
    cb(json.encode({}))
end)

RegisterNUICallback("authorizeSessionPin", function(data, cb)
    TriggerServerEvent("pmms:authorizeSessionPin", data.handle, data.pin)
    cb(json.encode({}))
end)

RegisterNUICallback("seekToTime", function(data, cb)
    if canRunNuiCallback("seekToTime", data) then
        local mediaPlayers = GetMediaPlayerStates()
        local mp = mediaPlayers and mediaPlayers[data.handle]
        if mp and mp.duration then
            local offset = tonumber(data.offset) or 0
            TriggerServerEvent("pmms:seekToTime", data.handle, offset)
        end
    end
    cb(json.encode({}))
end)

RegisterNUICallback("seekBackward", function(data, cb)
    if canRunNuiCallback("seekBackward", data) then
        local mediaPlayers = GetMediaPlayerStates()
        local mp = mediaPlayers and mediaPlayers[data.handle]
        if mp then
            local offset = math.max(0, (tonumber(mp.offset) or 0) - 10)
            TriggerServerEvent("pmms:seekToTime", data.handle, offset)
        end
    end
    cb(json.encode({}))
end)

RegisterNUICallback("seekForward", function(data, cb)
    if canRunNuiCallback("seekForward", data) then
        local mediaPlayers = GetMediaPlayerStates()
        local mp = mediaPlayers and mediaPlayers[data.handle]
        if mp then
            local offset = (tonumber(mp.offset) or 0) + 10
            TriggerServerEvent("pmms:seekToTime", data.handle, offset)
        end
    end
    cb(json.encode({}))
end)

RegisterNUICallback("previous", function(data, cb)
    TriggerServerEvent("pmms:previous", data.handle, getQueueExpectedRevision(data.handle, data))
    cb(json.encode({}))
end)

RegisterNUICallback("next", function(data, cb)
    TriggerServerEvent("pmms:next", data.handle, getQueueExpectedRevision(data.handle, data))
    cb(json.encode({}))
end)

RegisterNUICallback("removeFromQueue", function(data, cb)
    TriggerServerEvent("pmms:removeFromQueue", data.handle, data.index, getQueueExpectedRevision(data.handle, data))
    cb(json.encode({}))
end)

RegisterNUICallback("setBaseVolume", function(data, cb)
    setBaseVolume(data and data.volume or baseVolume)
    cb(json.encode({}))
end)

LocalPlayerVolumes = {}

RegisterNUICallback("setVolume", function(data, cb)
    if data and data.handle and data.volume then
        local handle = tonumber(data.handle) or data.handle
        LocalPlayerVolumes[handle] = tonumber(data.volume)
    end
    cb(json.encode({}))
end)

RegisterNUICallback("setAudioTrack", function(data, cb)
    TriggerServerEvent("pmms:setAudioTrack", data.handle, data.audioTrack or data.track or data.index)
    cb(json.encode({}))
end)

RegisterNUICallback("setRange", function(data, cb)
    if canRunNuiCallback("setRange", data) then
        TriggerServerEvent("pmms:setRange", data.handle, data.range)
    end
    cb(json.encode({}))
end)

RegisterNUICallback("forceResetDevice", function(data, cb)
    TriggerServerEvent("pmms:forceResetDevice", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("adminApplyProfile", function(data, cb)
    TriggerServerEvent("pmms:adminApplyProfile", data.handle, data.profile)
    cb(json.encode({}))
end)

RegisterNUICallback("adminSetRequestMode", function(data, cb)
    TriggerServerEvent("pmms:adminSetRequestMode", data.handle, data.mode)
    cb(json.encode({}))
end)

RegisterNUICallback("adminSetLock", function(data, cb)
    TriggerServerEvent("pmms:adminSetLock", data.handle, data.lock, getVehiclePlateForHandle(data.handle))
    cb(json.encode({}))
end)

RegisterNUICallback("adminSetDeviceSettings", function(data, cb)
    TriggerServerEvent("pmms:adminSetDeviceSettings", data.handle, data.settings or {})
    cb(json.encode({}))
end)

RegisterNUICallback("adminRenameDevice", function(data, cb)
    TriggerServerEvent("pmms:adminRenameDevice", data.handle, data.name)
    cb(json.encode({}))
end)

RegisterNUICallback("adminApproveRequest", function(data, cb)
    TriggerServerEvent("pmms:adminApproveRequest", data.handle, data.requestId, data.playNext)
    cb(json.encode({}))
end)

RegisterNUICallback("adminRejectRequest", function(data, cb)
    TriggerServerEvent("pmms:adminRejectRequest", data.handle, data.requestId)
    cb(json.encode({}))
end)

RegisterNUICallback("adminClearRequests", function(data, cb)
    TriggerServerEvent("pmms:adminClearRequests", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("adminClearSessionLock", function(data, cb)
    TriggerServerEvent("pmms:adminClearSessionLock", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("addLinkedSpeakerHere", function(data, cb)
    HideUi()
    StartSpeakerPlacementMode(data.handle, data.persistent == true, data.propModel, buildDeviceAnchorPayload(data.handle))
    cb(json.encode({}))
end)

RegisterNUICallback("adminAddSpeaker", function(data, cb)
    HideUi()
    StartSpeakerPlacementMode(data.handle, false, data.propModel, buildDeviceAnchorPayload(data.handle))
    cb(json.encode({}))
end)

RegisterNUICallback("adminAddPersistentSpeaker", function(data, cb)
    HideUi()
    StartSpeakerPlacementMode(data.handle, true, data.propModel, buildDeviceAnchorPayload(data.handle))
    cb(json.encode({}))
end)

RegisterNUICallback("adminClearLinkedSpeakers", function(data, cb)
    TriggerServerEvent("pmms:adminClearLinkedSpeakers", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("removeLinkedSpeaker", function(data, cb)
    TriggerServerEvent("pmms:removeLinkedSpeaker", data.handle, data.speakerId)
    cb(json.encode({}))
end)

RegisterNUICallback("adminResetProfile", function(data, cb)
    TriggerServerEvent("pmms:adminResetProfile", data.handle)
    cb(json.encode({}))
end)


RegisterNUICallback("saveEqProfile", function(data, cb)
    localEqProfile = type(data) == "table" and data or nil
    TriggerServerEvent("pmms:saveEqProfile", data)
    if type(DuiBrowser) == "table" and type(DuiBrowser.pool) == "table" then
        local states = type(GetMediaPlayerStates) == "function" and GetMediaPlayerStates() or {}
        for handle, browser in pairs(DuiBrowser.pool) do
            local state = states[handle] or states[tostring(handle)]
            ApplyEffectiveEqProfileToBrowser(browser, state and state.equalizerProfile or nil)
        end
    end
    cb(json.encode({}))
end)

RegisterNUICallback("saveDeviceEqProfile", function(data, cb)
    data = type(data) == "table" and data or {}
    TriggerServerEvent("pmms:saveDeviceEqProfile", data.handle, data.profile or {})
    cb(json.encode({}))
end)

RegisterNUICallback("loadEqProfile", function(_, cb)
    TriggerServerEvent("pmms:loadEqProfile")
    cb(json.encode({}))
end)

RegisterNUICallback("loadDeviceEqProfile", function(data, cb)
    TriggerServerEvent("pmms:loadDeviceEqProfile", data and data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("setEqAnalyserActive", function(data, cb)
    if canRunNuiCallback("setEqAnalyserActive", data) then
        if type(DuiBrowser) == "table" and type(DuiBrowser.pool) == "table" then
            for _, browser in pairs(DuiBrowser.pool) do
                if type(browser.sendMessage) == "function" then
                    browser:sendMessage({ type = "setEqAnalyserActive", active = data.active == true })
                end
            end
        end
    end
    cb(json.encode({}))
end)

RegisterNUICallback("adminAddPersistentDevice", function(data, cb)
    HideUi()
    StartDevicePlacementMode(data)
    cb(json.encode({}))
end)

RegisterNUICallback("adminRemovePersistentDevice", function(data, cb)
    TriggerServerEvent("pmms:adminRemovePersistentDevice", data.handle)
    cb(json.encode({}))
end)

RegisterNUICallback("setAttenuation", function(data, cb)
    if canRunNuiCallback("setAttenuation", data) then
        TriggerServerEvent("pmms:setAttenuation", data.handle, data.sameRoom, data.diffRoom)
    end
    cb(json.encode({}))
end)

RegisterNUICallback("setDiffRoomVolume", function(data, cb)
    if canRunNuiCallback("setDiffRoomVolume", data) then
        TriggerServerEvent("pmms:setDiffRoomVolume", data.handle, data.diffRoomVolume)
    end
    cb(json.encode({}))
end)

RegisterNUICallback("setTransition", function(data, cb)
    if canRunNuiCallback("setTransition", data) then
        TriggerServerEvent("pmms:setTransition", data.handle, data.transitionSeconds)
    end
    cb(json.encode({}))
end)

RegisterNUICallback("setIsVehicle", function(data, cb)
    TriggerServerEvent("pmms:setIsVehicle", data.handle, data.isVehicle)
    cb(json.encode({}))
end)

RegisterNUICallback("setScaleform", function(data, cb)
    TriggerServerEvent("pmms:setScaleform", data.handle, data.scaleform)
    cb(json.encode({}))
end)

RegisterNUICallback("getMediaPlayerDefaults", function(data, cb)
    cb(json.encode(buildMediaPlayerDefaultsPayload(data and data.handle)))
end)

RegisterNUICallback("setMediaPlayerDefaults", function(data, cb)
    cb(json.encode(buildMediaPlayerDefaultsPayload(data and data.handle)))
end)

RegisterNUICallback("getScaleformSettingsFromMyPosition", function(_, cb)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local rot = GetEntityRotation(ped)
    cb(json.encode({
        position = { x = pos.x, y = pos.y, z = pos.z },
        rotation = { x = rot.x, y = rot.y, z = rot.z },
    }))
end)

RegisterNUICallback("getScaleformSettingsFromEntity", function(data, cb)
    local entity = GetEntityFromDataHandle(data.handle)
    if entity and DoesEntityExist(entity) then
        local pos = GetEntityCoords(entity)
        local rot = GetEntityRotation(entity)
        cb(json.encode({
            position = { x = pos.x, y = pos.y, z = pos.z },
            rotation = { x = rot.x, y = rot.y, z = rot.z },
        }))
    else
        cb(json.encode({}))
    end
end)

RegisterNUICallback("save", function(data, cb)
    local method = data.method
    if method == "server-model" or method == "new-model" then
        local model = data.model and GetHashKey(data.model) or nil
        if not model and data.handle then
            local entity = GetEntityFromDataHandle(data.handle)
            if entity and DoesEntityExist(entity) then
                model = GetEntityModel(entity)
            end
        end
        if model then
            TriggerServerEvent("pmms:saveModel", model, data)
        end
    elseif method == "server-entity" then
        local entity = GetEntityFromDataHandle(data.handle)
        if entity and DoesEntityExist(entity) then
            local coords = GetEntityCoords(entity)
            TriggerServerEvent("pmms:saveEntity", coords, data)
        end
    end
    cb(json.encode({}))
end)

RegisterNUICallback("delete", function(data, cb)
    local method = data.method
    if method == "server-model" then
        local entity = GetEntityFromDataHandle(data.handle)
        if entity and DoesEntityExist(entity) then
            TriggerServerEvent("pmms:deleteModel", GetEntityModel(entity))
        end
    elseif method == "server-entity" then
        local entity = GetEntityFromDataHandle(data.handle)
        if entity and DoesEntityExist(entity) then
            TriggerServerEvent("pmms:deleteEntity", GetEntityCoords(entity))
        end
    end
    cb(json.encode({}))
end)

RegisterNUICallback("notify", function(data, cb)
    ShowNotification(data.text)
    cb(json.encode({}))
end)

RegisterNUICallback("fix", function(_, cb)
    DestroyAllMediaPlayers()
    TriggerServerEvent("pmms:loadSettings")
    cb(json.encode({}))
end)

RegisterNUICallback("toggleStatus", function(_, cb)
    TriggerServerEvent("pmms:toggleStatus")
    cb(json.encode({}))
end)

RegisterNUICallback("toggleTips", function(data, cb)
    tooltipsEnabled = data.enabled
    cb(json.encode({}))
end)

RegisterNUICallback("selectDevice", function(data, cb)
    selectedUiHandle = data and data.handle or nil
    selectedUiDeviceType = data and data.deviceType or nil
    if type(InvalidateUiUpdateSignature) == "function" then
        InvalidateUiUpdateSignature()
    end
    cb(json.encode({}))
end)

RegisterNUICallback("increaseVideoSize", function(data, cb)
    TriggerServerEvent("pmms:setVideoSize", data.handle, (GetMediaPlayerStates()[data.handle] and GetMediaPlayerStates()[data.handle].videoSize or Config.defaultVideoSize) + 10)
    cb(json.encode({}))
end)

RegisterNUICallback("decreaseVideoSize", function(data, cb)
    TriggerServerEvent("pmms:setVideoSize", data.handle, (GetMediaPlayerStates()[data.handle] and GetMediaPlayerStates()[data.handle].videoSize or Config.defaultVideoSize) - 10)
    cb(json.encode({}))
end)

function ShowUi(selectedHandle, openView)
    uiIsOpen = true
    selectedUiHandle = selectedHandle
    selectedUiDeviceType = nil
    if type(InvalidateUiUpdateSignature) == "function" then
        InvalidateUiUpdateSignature()
    end
    if type(InvalidateEntityCache) == "function" then
        InvalidateEntityCache()
    end
    TriggerServerEvent("pmms:loadPermissions")
    SetNuiFocus(true, true)
    TriggerServerEvent("pmms:markMenuOpened")
    TriggerServerEvent("pmms:loadEqProfile")
    SendNUIMessage({
        type = "showUi",
        presets = Config.presets,
        searchSources = Config.searchSources,
        defaultSearchSource = Config.defaultSearchSource or "youtube",
        defaultTransitionSeconds = Config.defaultTransitionSeconds,
        maxTransitionSeconds = Config.maxTransitionSeconds,
        maxRange = Config.maxRange,
        adminMaxRange = Config.adminMaxRange or Config.maxRange,
        currentServerEndpoint = GetCurrentServerEndpoint(),
        searchMinimumBusyMs = (Config.search and Config.search.minimumBusyMs) or 500,
        searchProxyThumbnails = not (Config.search and Config.search.proxyThumbnails == false),
        showYoutubeProviderSelector = shouldShowYoutubeProviderSelector(),
        deviceDefaults = buildGlobalDeviceDefaults(),
        baseVolume = type(GetBaseVolume) == "function" and GetBaseVolume() or 100,
        debug = Config.debug,
        permissions = permissions,
        deviceProfiles = BuildDeviceProfilesForClient(),
        adminQuickActions = Config.admin and Config.admin.quickActions or {},
        requestConfig = Config.requests,
        speakerConfig = Config.speakers,
        selectedHandle = selectedHandle,
        propModels = BuildPropModelsForClient(),
        speakerModels = BuildSpeakerModelsForClient(),
        equalizerConfig = Config.equalizer,
        openView = openView,
    })
end

function HideUi()
    uiIsOpen = false
    adminDiscoveryRange = nil
    selectedUiHandle = nil
    selectedUiDeviceType = nil
    if type(InvalidateUiUpdateSignature) == "function" then
        InvalidateUiUpdateSignature()
    end
    if type(InvalidateEntityCache) == "function" then
        InvalidateEntityCache(250)
    end
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "hideUi" })
end

function ShowNotification(text, title, color, duration)
    SendNUIMessage({
        type = "showNotification",
        args = {
            text     = text,
            title    = title or "7-PMMS",
            color    = color,
            duration = duration or Config.notificationDuration,
        },
    })
end

function ShowPmmsError(payload)
    local errorPayload = type(BuildPmmsErrorPayload) == "function" and BuildPmmsErrorPayload(payload) or {
        code = "action_failed",
        title = "7-PMMS",
        message = tostring(payload or "The action failed. Please try again."),
        type = "error",
        duration = Config.notificationDuration or 6000,
    }
    SendNUIMessage({
        type = "pmmsError",
        payload = errorPayload,
    })
end

RegisterNetEvent("pmms:showControls", function()
    ShowUi()
end)

RegisterNetEvent("pmms:showUi", function(selectedHandle, openView)
    ShowUi(selectedHandle, openView)
end)

RegisterNetEvent("pmms:toggleStatus", function()
    SendNUIMessage({ type = "toggleStatus" })
end)

RegisterNetEvent("pmms:loadPermissions", function(perms)
    permissions = perms
    PMMSDebug("permissions", "permissions received on client", {
        manage = permissions and permissions.manage,
        overrideDevice = permissions and permissions.overrideDevice,
        staff = permissions and permissions.staff,
    })
    if IsUiOpen() then
        SendNUIMessage({
            type = "updateUi",
            permissions = permissions,
        })
    end
end)

RegisterNetEvent("pmms:refreshPermissions", function()
    TriggerServerEvent("pmms:loadPermissions")
end)

RegisterNetEvent("pmms:error", function(payload)
    ShowPmmsError(payload)
end)

RegisterNetEvent("pmms:notify", function(data)
    ShowNotification(data.text, data.title, data.color, data.duration)
end)

RegisterNetEvent("pmms:eqProfile", function(profile)
    localEqProfile = type(profile) == "table" and profile or nil
    SendNUIMessage({ type = "eqProfile", profile = profile })
    if type(DuiBrowser) == "table" and type(DuiBrowser.pool) == "table" then
        local states = type(GetMediaPlayerStates) == "function" and GetMediaPlayerStates() or {}
        for handle, browser in pairs(DuiBrowser.pool) do
            local state = states[handle] or states[tostring(handle)]
            ApplyEffectiveEqProfileToBrowser(browser, state and state.equalizerProfile or nil)
        end
    end
end)

RegisterNetEvent("pmms:eqDeviceProfile", function(handle, profile, allowed)
    SendNUIMessage({ type = "eqDeviceProfile", handle = handle, profile = profile, allowed = allowed ~= false })
    if allowed ~= false and type(DuiBrowser) == "table" and type(DuiBrowser.pool) == "table" then
        local browser = DuiBrowser.pool[handle] or DuiBrowser.pool[tostring(handle)]
        ApplyEffectiveEqProfileToBrowser(browser, profile)
    end
end)

RegisterNetEvent("pmms:listPresets", function()
    for key, preset in pairs(Config.presets) do
        print(("[7-pmms] %s - %s"):format(key, preset.title))
    end
end)

RegisterNetEvent("pmms:showBaseVolume", function()
    ShowNotification("Volume: " .. baseVolume .. "%")
end)

RegisterNetEvent("pmms:setBaseVolume", function(vol)
    setBaseVolume(vol)
    ShowNotification("Volume set to " .. baseVolume .. "%")
end)

RegisterNetEvent("pmms:reset", function()
    DestroyAllMediaPlayers()
    SendNUIMessage({ type = "reset" })
    ShowNotification("Media players have been reset")
end)

RegisterNUICallback("searchMedia", function(data, cb)
    TriggerServerEvent("pmms:clientSearch", { query = data.query, source = data.source, requestId = data.requestId })
    cb(json.encode({}))
end)

RegisterNUICallback("getPlaylists", function(data, cb)
    TriggerServerEvent("pmms:getPlaylists", data and data.requestId or nil)
    cb(json.encode({}))
end)

RegisterNUICallback("getSharedPlaylists", function(data, cb)
    TriggerServerEvent("pmms:getSharedPlaylists", data and data.requestId or nil)
    cb(json.encode({}))
end)

RegisterNUICallback("createPlaylist", function(data, cb)
    data = type(data) == "table" and data or {}
    TriggerServerEvent("pmms:createPlaylist", data.name, data.requestId)
    cb(json.encode({}))
end)

RegisterNUICallback("deletePlaylist", function(data, cb)
    TriggerServerEvent("pmms:deletePlaylist", data.playlistId)
    cb(json.encode({}))
end)

RegisterNUICallback("setPlaylistFavorite", function(data, cb)
    data = type(data) == "table" and data or {}
    PMMSDebug("favorites", "NUI favorite callback", {
        playlistId = data and data.playlistId or nil,
        favorite = data and data.favorite or nil,
        requestId = data and data.requestId or nil,
    })
    TriggerServerEvent("pmms:setPlaylistFavorite", data.playlistId, data.favorite, data.requestId)
    cb(json.encode({}))
end)

RegisterNUICallback("getPlaylistTracks", function(data, cb)
    TriggerServerEvent("pmms:getPlaylistTracks", data.playlistId)
    cb(json.encode({}))
end)

RegisterNUICallback("addTrack", function(data, cb)
    TriggerServerEvent("pmms:addTrack", data.playlistId, data.trackData)
    cb(json.encode({}))
end)

RegisterNUICallback("removeTrack", function(data, cb)
    TriggerServerEvent("pmms:removeTrack", data.playlistId, data.trackId)
    cb(json.encode({}))
end)

RegisterNUICallback("sharePlaylist", function(data, cb)
    TriggerServerEvent("pmms:sharePlaylist", data.playlistId, data.friendLicense)
    cb(json.encode({}))
end)

RegisterNUICallback("getFriends", function(_, cb)
    TriggerServerEvent("pmms:getFriends")
    cb(json.encode({}))
end)

RegisterNUICallback("getFriendRequests", function(_, cb)
    TriggerServerEvent("pmms:getFriendRequests")
    cb(json.encode({}))
end)

RegisterNUICallback("getPlayerSuggestions", function(data, cb)
    TriggerServerEvent("pmms:getPlayerSuggestions", data and data.query or "", data and data.requestId or nil)
    cb(json.encode({}))
end)

RegisterNUICallback("sendFriendRequest", function(data, cb)
    TriggerServerEvent("pmms:sendFriendRequest", data and data.targetSrc or nil, data and data.targetLicense or nil)
    cb(json.encode({}))
end)

RegisterNUICallback("acceptFriendRequest", function(data, cb)
    TriggerServerEvent("pmms:acceptFriendRequest", data.requestId)
    cb(json.encode({}))
end)

RegisterNUICallback("declineFriendRequest", function(data, cb)
    TriggerServerEvent("pmms:declineFriendRequest", data.requestId)
    cb(json.encode({}))
end)

RegisterNUICallback("removeFriend", function(data, cb)
    TriggerServerEvent("pmms:removeFriend", data.friendLicense)
    cb(json.encode({}))
end)

RegisterNetEvent("pmms:searchResults", function(payload)
    if type(payload) == "table" and payload.results then
        SendNUIMessage({ type = "searchResults", results = payload.results, requestId = payload.requestId })
        return
    end

    SendNUIMessage({ type = "searchResults", results = payload })
end)

RegisterNetEvent("pmms:searchError", function(data)
    SendNUIMessage({
        type = "searchError",
        requestId = data and data.requestId or nil,
        message = data and data.message or nil,
        state = data and data.state or nil,
        retryAfterMs = data and data.retryAfterMs or nil,
        cooldownUntil = data and data.cooldownUntil or nil,
    })
end)

RegisterNetEvent("pmms:setPlaylists", function(payload)
    if type(payload) == "table" and payload.playlists then
        SendNUIMessage({
            type = "setPlaylists",
            playlists = payload.playlists,
            requestId = payload.requestId,
            summary = payload.summary,
            libraryRevision = payload.libraryRevision,
        })
        return
    end

    SendNUIMessage({ type = "setPlaylists", playlists = payload })
end)

RegisterNetEvent("pmms:setSharedPlaylists", function(payload)
    if type(payload) == "table" and payload.playlists then
        SendNUIMessage({ type = "setSharedPlaylists", playlists = payload.playlists, requestId = payload.requestId })
        return
    end

    SendNUIMessage({ type = "setSharedPlaylists", playlists = payload })
end)

RegisterNetEvent("pmms:setPlaylistTracks", function(playlistId, tracks)
    SendNUIMessage({ type = "setPlaylistTracks", playlistId = playlistId, tracks = tracks })
end)

RegisterNetEvent("pmms:setFriends", function(friends)
    SendNUIMessage({ type = "setFriends", friends = friends })
end)

RegisterNetEvent("pmms:setFriendRequests", function(requests)
    SendNUIMessage({ type = "setFriendRequests", requests = requests })
end)

RegisterNetEvent("pmms:setPlayerSuggestions", function(payload)
    SendNUIMessage({
        type = "setPlayerSuggestions",
        requestId = payload and payload.requestId or nil,
        suggestions = payload and payload.suggestions or {},
    })
end)

RegisterNetEvent("pmms:refreshLibrary", function()
    SendNUIMessage({ type = "refreshLibrary" })
end)

RegisterNetEvent("pmms:playlistCreateResult", function(payload)
    SendNUIMessage({ type = "playlistCreateResult", payload = payload })
end)

RegisterNetEvent("pmms:refreshSocial", function()
    SendNUIMessage({ type = "refreshSocial" })
end)

RegisterNetEvent("pmms:refreshPlaylist", function(playlistId)
    SendNUIMessage({ type = "refreshPlaylist", playlistId = playlistId })
end)

local function debugPayloadField(payload, key)
    if payload == nil then
        return nil
    end
    return payload[key]
end

RegisterNetEvent("pmms:playlistFavoriteUpdated", function(payload)
    PMMSDebug("favorites", "favorite update forwarded to NUI", {
        playlistId = debugPayloadField(payload, "playlistId"),
        requestId = debugPayloadField(payload, "requestId"),
        mutationId = debugPayloadField(payload, "mutationId"),
        success = debugPayloadField(payload, "success"),
        isFavorite = debugPayloadField(payload, "isFavorite"),
        message = debugPayloadField(payload, "message"),
        libraryRevision = debugPayloadField(payload, "libraryRevision"),
    })
    SendNUIMessage({ type = "playlistFavoriteUpdated", payload = payload })
end)
