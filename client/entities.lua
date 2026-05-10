local entityCache = {}
local entityHandleIndex = {}
local entityCacheExpiry = 0
local persistentPropEntities = {}
local speakerPropEntities = {}
local CACHE_DURATION = 2000
local entityCacheStats = {
    objectCount = 0,
    vehicleCount = 0,
    networkedCount = 0,
    lastScanMs = 0,
}

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
    ) + 10.0
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
    entityCacheExpiry = now + CACHE_DURATION
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

function InvalidateEntityCache()
    entityCacheExpiry = 0
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
        cacheExpiresInMs = math.max(0, entityCacheExpiry - GetGameTimer()),
    }
end

local function deletePersistentProp(handle)
    local entity = persistentPropEntities[handle]
    if entity then
        SetEntityAsMissionEntity(entity, false, true)
        DeleteObject(entity)
    end
    persistentPropEntities[handle] = nil
end

local function deleteSpeakerProp(id)
    local data = speakerPropEntities[id]
    if data and data.entity then
        SetEntityAsMissionEntity(data.entity, false, true)
        DeleteObject(data.entity)
    end
    speakerPropEntities[id] = nil
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

local function getPersistentPropCoords(entry)
    if type(entry) ~= "table" or type(entry.position) ~= "table" then
        return nil
    end
    local x = tonumber(entry.position.x)
    local y = tonumber(entry.position.y)
    local z = tonumber(entry.position.z)
    if not x or not y or not z then
        return nil
    end
    return vector3(x, y, z)
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

local function deleteSpeakerProp(id)
    if speakerPropEntities[id] and speakerPropEntities[id].entity then
        if DoesEntityExist(speakerPropEntities[id].entity) then
            DeleteObject(speakerPropEntities[id].entity)
        end
        speakerPropEntities[id] = nil
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
        if speaker.heading then
            SetEntityHeading(entity, tonumber(speaker.heading) or 0.0)
        end
        FreezeEntityPosition(entity, true)
        SetEntityAsMissionEntity(entity, true, true)
        speakerPropEntities[id] = { entity = entity, handle = speaker.handle }
    end

    SetModelAsNoLongerNeeded(model)
end

RegisterNetEvent("pmms:sync", function(payload)
    local deviceSessions = {}
    if type(payload) == "table" and payload.deviceSessions then
        deviceSessions = payload.deviceSessions
    end

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


    for id in pairs(speakerPropEntities) do
        if not desiredSpeakers[id] then
            deleteSpeakerProp(id)
        end
    end
end)

RegisterNetEvent("pmms:loadSettings", function()
    SetTimeout(250, refreshPersistentProps)
end)

CreateThread(function()
    while true do
        Wait(30000)
        refreshPersistentProps()
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
