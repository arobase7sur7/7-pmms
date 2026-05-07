local entityCache = {}
local entityHandleIndex = {}
local entityCacheExpiry = 0
local CACHE_DURATION = 2000

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

                local netId = getEntityNetworkId(object)
                if netId then
                    handleIndex[netId] = entry
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

                local netId = getEntityNetworkId(vehicle)
                if netId then
                    handleIndex[netId] = entry
                end
            end
        end
    end

    entityCache = entities
    entityHandleIndex = handleIndex
    entityCacheExpiry = now + CACHE_DURATION
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
