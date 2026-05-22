local entityCache = {}
local entityHandleIndex = {}
local persistentPropEntities = {}
local speakerPropEntities = {}
local CACHE_DURATION_IDLE = 2400
local CACHE_DURATION_ACTIVE = 1200
local CACHE_DURATION_UI = 850
local CACHE_DURATION_SELECTED = 450
local CACHE_DURATION_ADMIN = 650
local DISCOVERY_JOIN_JITTER_MS = 900
local entityCacheStats = {
    objectCount = 0,
    vehicleCount = 0,
    networkedCount = 0,
    lastScanMs = 0,
    cacheDurationMs = CACHE_DURATION_IDLE,
}

local function getInitialDiscoveryJitterMs()
    local now = type(GetGameTimer) == "function" and GetGameTimer() or 0
    local serverId = 0
    if type(PlayerId) == "function" and type(GetPlayerServerId) == "function" then
        serverId = tonumber(GetPlayerServerId(PlayerId())) or 0
    end
    return math.floor((now + (serverId * 131)) % DISCOVERY_JOIN_JITTER_MS)
end

local discoveryJoinJitterMs = getInitialDiscoveryJitterMs()
local entityCacheExpiry = (type(GetGameTimer) == "function" and GetGameTimer() or 0) + discoveryJoinJitterMs

function GetDiscoveryJoinJitterMs()
    return discoveryJoinJitterMs
end

local function hasActiveMediaPlayers()
    local players = type(GetActivePlayers) == "function" and GetActivePlayers() or nil
    if type(players) ~= "table" then
        return false
    end
    return next(players) ~= nil
end

local function getAdaptiveEntityCacheDuration()
    local duration = CACHE_DURATION_IDLE

    if hasActiveMediaPlayers() then
        duration = math.min(duration, CACHE_DURATION_ACTIVE)
    end

    if type(IsUiOpen) == "function" and IsUiOpen() then
        duration = math.min(duration, CACHE_DURATION_UI)
    end

    if type(GetSelectedUiHandle) == "function" and GetSelectedUiHandle() ~= nil then
        duration = math.min(duration, CACHE_DURATION_SELECTED)
    end

    if type(GetAdminDiscoveryRange) == "function" and GetAdminDiscoveryRange() ~= nil then
        duration = math.min(duration, CACHE_DURATION_ADMIN)
    end

    return duration
end

function GetMediaPlayerEntities()
    local now = GetGameTimer()
    if now < entityCacheExpiry then
        return entityCache
    end

    local entities = {}
    local handleIndex = {}
    local playerCoords = GetEntityCoords(PlayerPedId())
    local scanDistance = math.max(
        tonumber(Config.maxDiscoveryDistance) or 30.0,
        tonumber(Config.maxRange) or 60.0
    )
    local permissions = type(GetPermissions) == "function" and GetPermissions() or {}
    local adminRange = type(GetAdminDiscoveryRange) == "function" and GetAdminDiscoveryRange() or nil
    if (permissions.manage == true or permissions.overrideDevice == true) and tonumber(adminRange) then
        scanDistance = math.max(scanDistance, tonumber(adminRange) or scanDistance)
    end
    scanDistance = scanDistance + 10.0
    entityCacheStats.networkedCount = 0

    for _, object in ipairs(GetGamePool("CObject")) do
        local model = GetEntityModel(object)
        if GetModelConfig(model) then
            local objectCoords = GetEntityCoords(object)
            local withinScanRange = #(objectCoords - playerCoords) <= scanDistance
            if withinScanRange then
                local entry = {
                    entity = object,
                    model  = model,
                    type   = "object",
                }
                entities[#entities + 1] = entry

                local netId = getExistingEntityNetworkId(object)
                if netId then
                    handleIndex[netId] = entry
                    entityCacheStats.networkedCount = entityCacheStats.networkedCount + 1
                end
            end
        end
    end

    if Config.allowPlayingFromVehicles then
        for _, vehicle in ipairs(GetGamePool("CVehicle")) do
            if #(GetEntityCoords(vehicle) - playerCoords) < 50.0 then
                local entry = {
                    entity = vehicle,
                    model  = GetEntityModel(vehicle),
                    type   = "vehicle",
                }
                entities[#entities + 1] = entry

                local netId = getExistingEntityNetworkId(vehicle)
                if netId then
                    handleIndex[netId] = entry
                    entityCacheStats.networkedCount = entityCacheStats.networkedCount + 1
                end
            end
        end
    end

    entityCache = entities
    entityHandleIndex = handleIndex
    entityCacheStats.cacheDurationMs = getAdaptiveEntityCacheDuration()
    entityCacheExpiry = now + entityCacheStats.cacheDurationMs
    entityCacheStats.objectCount = 0
    entityCacheStats.vehicleCount = 0
    for _, entry in ipairs(entities) do
        if entry.type == "vehicle" then
            entityCacheStats.vehicleCount = entityCacheStats.vehicleCount + 1
        else
            entityCacheStats.objectCount = entityCacheStats.objectCount + 1
        end
    end
    entityCacheStats.lastScanMs = GetGameTimer() - now
    return entities
end

function InvalidateEntityCache(delayMs)
    local delay = math.max(0, tonumber(delayMs) or 0)
    entityCacheExpiry = GetGameTimer() + delay
    entityHandleIndex = {}
end

function GetEntityEntryByNetworkId(handle)
    GetMediaPlayerEntities()
    return entityHandleIndex[tonumber(handle) or handle]
end

function GetEntityDistanceSorted(playerPos)
    local entities = GetMediaPlayerEntities()
    local sorted = {}

    for _, entry in ipairs(entities) do
        local pos = GetEntityCoords(entry.entity)
        local dist = #(playerPos - pos)
        sorted[#sorted + 1] = {
            entity   = entry.entity,
            model    = entry.model,
            type     = entry.type,
            coords   = pos,
            distance = dist,
        }
    end

    table.sort(sorted, function(a, b) return a.distance < b.distance end)
    return sorted
end

function GetClosestEntity(playerPos, maxDistance)
    local entities = GetEntityDistanceSorted(playerPos)

    for _, entry in ipairs(entities) do
        if entry.distance <= (maxDistance or Config.maxDiscoveryDistance) then
            return entry
        end
    end
end

function GetEntityCacheStats()
    return {
        cached = #entityCache,
        objectCount = entityCacheStats.objectCount,
        vehicleCount = entityCacheStats.vehicleCount,
        networkedCount = entityCacheStats.networkedCount,
        lastScanMs = entityCacheStats.lastScanMs,
        cacheDurationMs = entityCacheStats.cacheDurationMs,
        discoveryJoinJitterMs = discoveryJoinJitterMs,
        cacheExpiresInMs = math.max(0, entityCacheExpiry - GetGameTimer()),
    }
end

local function deletePersistentProp(handle)
    local key = handle
    local entity = persistentPropEntities[key]
    if not entity then
        key = tostring(handle)
        entity = persistentPropEntities[key]
    end
    if not entity then
        key = tonumber(handle)
        entity = key and persistentPropEntities[key] or nil
    end
    if entity then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteObject(entity)
        if DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end
    if key ~= nil then
        persistentPropEntities[key] = nil
    end
end

function GetPersistentPropEntity(handle)
    local entity = persistentPropEntities[handle] or persistentPropEntities[tonumber(handle)]
    if entity and DoesEntityExist(entity) then
        return entity, GetEntityModel(entity), "object"
    end
    return nil, nil, nil
end

local function deleteSpeakerProp(id)
    local key = id
    local data = speakerPropEntities[key]
    if not data then
        key = tostring(id)
        data = speakerPropEntities[key]
    end
    if not data then
        key = tonumber(id)
        data = key and speakerPropEntities[key] or nil
    end
    if data and data.entity then
        SetEntityAsMissionEntity(data.entity, true, true)
        DeleteObject(data.entity)
        if DoesEntityExist(data.entity) then
            DeleteEntity(data.entity)
        end
    end
    if key ~= nil then
        speakerPropEntities[key] = nil
    end
end

function GetSpeakerPropHandleAndId(entity)
    if not entity or not DoesEntityExist(entity) then
        return nil, nil
    end
    for id, data in pairs(speakerPropEntities) do
        if data.entity == entity then
            return data.handle, id
        end
    end
    return nil, nil
end

function GetSpeakerPropData(entity)
    if not entity or not DoesEntityExist(entity) then
        return nil
    end
    for id, data in pairs(speakerPropEntities) do
        if data.entity == entity then
            local copy = {}
            for key, value in pairs(data) do
                copy[key] = value
            end
            copy.id = id
            return copy
        end
    end
    return nil
end

local function getPersistentPropCoords(entry)
    if type(entry) ~= "table" then
        return nil
    end

    return ToVector3(entry.position)
end

local function spawnPersistentProp(entry)
    if type(entry) ~= "table" or entry.mode ~= "prop" or type(entry.propModel) ~= "string" or entry.propModel == "" then
        return
    end

    local coords = getPersistentPropCoords(entry)
    if not coords then
        return
    end

    local handle = GetHandleFromCoords(coords)
    if persistentPropEntities[handle] and DoesEntityExist(persistentPropEntities[handle]) then
        return
    end

    local model = GetHashKey(entry.propModel)
    if not IsModelInCdimage(model) then
        ShowNotification(("Unknown prop model: %s"):format(entry.propModel), "7-PMMS", "#ff4444")
        return
    end

    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do
        Wait(0)
    end

    if not HasModelLoaded(model) then
        ShowNotification(("Could not load prop model: %s"):format(entry.propModel), "7-PMMS", "#ff4444")
        return
    end

    local entity = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    if entity and DoesEntityExist(entity) then
        SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, false, false, false)
        local rotation = entry.rotation
        if type(rotation) == "table" then
            SetEntityRotation(entity, tonumber(rotation.x) or 0.0, tonumber(rotation.y) or 0.0, tonumber(rotation.z) or 0.0, 2, true)
        end
        if entry.heading then
            SetEntityHeading(entity, tonumber(entry.heading) or 0.0)
        end
        FreezeEntityPosition(entity, true)
        SetEntityAsMissionEntity(entity, true, true)
        persistentPropEntities[handle] = entity
    end

    SetModelAsNoLongerNeeded(model)
end

local function refreshPersistentProps()
    local desired = {}
    for _, entry in ipairs(Config.defaultMediaPlayers or {}) do
        local coords = getPersistentPropCoords(entry)
        if coords and entry.mode == "prop" and entry.propModel then
            local handle = GetHandleFromCoords(coords)
            desired[handle] = true
            spawnPersistentProp(entry)
        end
    end

    for handle in pairs(persistentPropEntities) do
        if not desired[handle] then
            deletePersistentProp(handle)
        end
    end
end

local function spawnSpeakerProp(speaker)
    if type(speaker) ~= "table" or not speaker.id or not speaker.coords or not speaker.propModel then
        return
    end

    local id = speaker.id
    if speakerPropEntities[id] and speakerPropEntities[id].entity and DoesEntityExist(speakerPropEntities[id].entity) then
        return
    end

    local model = GetHashKey(speaker.propModel)
    if not IsModelInCdimage(model) then
        return
    end

    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do
        Wait(0)
    end

    if not HasModelLoaded(model) then
        return
    end

    local coords = speaker.coords
    local entity = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    if entity and DoesEntityExist(entity) then
        SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, false, false, false)
        if speaker.heading then
            SetEntityHeading(entity, tonumber(speaker.heading) or 0.0)
        end
        FreezeEntityPosition(entity, true)
        SetEntityAsMissionEntity(entity, true, true)
        speakerPropEntities[id] = {
            entity = entity,
            handle = speaker.handle,
            persistent = speaker.persistent == true,
            createdBy = speaker.createdBy,
            propModel = speaker.propModel,
        }
    end

    SetModelAsNoLongerNeeded(model)
end

local function refreshPersistentSpeakers()
    local desiredSpeakers = {}
    for _, entry in ipairs(Config.defaultMediaPlayers or {}) do
        if type(entry) == "table" and type(entry.linkedSpeakers) == "table" then
            local coords = ToVector3(entry.position)
            if coords then
                local handle = GetHandleFromCoords(coords)
                for _, speaker in ipairs(entry.linkedSpeakers) do
                    if type(speaker) == "table" and speaker.id then
                        speaker.handle = handle
                        speaker.persistent = speaker.persistent ~= false
                        desiredSpeakers[speaker.id] = true
                        spawnSpeakerProp(speaker)
                    end
                end
            end
        end
    end

    for id, data in pairs(speakerPropEntities) do
        if data and data.persistent == true and not desiredSpeakers[id] then
            deleteSpeakerProp(id)
        end
    end
end

local function refreshLinkedSpeakerProps(deviceSessions)
    deviceSessions = type(deviceSessions) == "table" and deviceSessions or {}

    local desiredSpeakers = {}
    for handle, session in pairs(deviceSessions) do
        if type(session.linkedSpeakers) == "table" then
            for _, speaker in ipairs(session.linkedSpeakers) do
                if speaker.id then
                    speaker.handle = handle
                    desiredSpeakers[speaker.id] = true
                    spawnSpeakerProp(speaker)
                end
            end
        end
    end

    for _, entry in ipairs(Config.defaultMediaPlayers or {}) do
        if type(entry) == "table" and type(entry.linkedSpeakers) == "table" then
            local coords = ToVector3(entry.position)
            if coords then
                local handle = GetHandleFromCoords(coords)
                for _, speaker in ipairs(entry.linkedSpeakers) do
                    if type(speaker) == "table" and speaker.id then
                        speaker.handle = handle
                        speaker.persistent = speaker.persistent ~= false
                        desiredSpeakers[speaker.id] = true
                        spawnSpeakerProp(speaker)
                    end
                end
            end
        end
    end


    for id in pairs(speakerPropEntities) do
        if not desiredSpeakers[id] then
            deleteSpeakerProp(id)
        end
    end
end

RegisterNetEvent("pmms:sync", function(payload)
    local deviceSessions = {}
    if type(payload) == "table" and payload.deviceSessions then
        deviceSessions = payload.deviceSessions
    end

    refreshLinkedSpeakerProps(deviceSessions)
end)

RegisterNetEvent("pmms:syncDelta", function()
    SetTimeout(0, function()
        local deviceSessions = type(GetDeviceSessions) == "function" and GetDeviceSessions() or {}
        refreshLinkedSpeakerProps(deviceSessions)
    end)
end)

RegisterNetEvent("pmms:speakerRemoved", function(speakerId)
    if speakerId ~= nil then
        deleteSpeakerProp(speakerId)
    end
end)

RegisterNetEvent("pmms:speakersCleared", function(handle)
    local targetHandle = handle and tostring(handle) or nil
    for id, data in pairs(speakerPropEntities) do
        if not targetHandle or tostring(data and data.handle or "") == targetHandle then
            deleteSpeakerProp(id)
        end
    end
end)

local function refreshPersistentEntities()
    refreshPersistentProps()
    refreshPersistentSpeakers()
end

RegisterNetEvent("pmms:refreshPersistentEntities", function()
    SetTimeout(50, refreshPersistentEntities)
end)

RegisterNetEvent("pmms:loadSettings", function()
    SetTimeout(250, function()
        refreshPersistentEntities()
    end)
end)

CreateThread(function()
    while true do
        Wait(30000)
        refreshPersistentEntities()
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    for handle in pairs(persistentPropEntities) do
        deletePersistentProp(handle)
    end
    for id in pairs(speakerPropEntities) do
        deleteSpeakerProp(id)
    end
end)
