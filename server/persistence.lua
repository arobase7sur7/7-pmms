local thisResource = GetCurrentResourceName()

local function syncSettings()
    if type(InvalidateModelConfigCache) == "function" then
        InvalidateModelConfigCache()
    end
    TriggerClientEvent("pmms:loadSettings", -1, Config.models, Config.defaultMediaPlayers)
end

function LoadPersistedSettings()
    local models = json.decode(LoadResourceFile(thisResource, "models.json"))
    if models then
        for key, info in pairs(models) do
            local model = tonumber(key)
            local existing = GetModelConfig(model)
            if existing then
                for k, v in pairs(info) do existing[k] = v end
            else
                Config.models[model] = info
                if type(InvalidateModelConfigCache) == "function" then
                    InvalidateModelConfigCache()
                end
            end
        end
    end

    local defaultMediaPlayers = json.decode(LoadResourceFile(thisResource, "defaultMediaPlayers.json"))
    if defaultMediaPlayers then
        for _, dmp in ipairs(defaultMediaPlayers) do
            dmp.position = ToVector3(dmp.position)
            if dmp.scaleform then
                dmp.scaleform.position = ToVector3(dmp.scaleform.position)
                dmp.scaleform.rotation = ToVector3(dmp.scaleform.rotation)
                dmp.scaleform.scale    = ToVector3(dmp.scaleform.scale)
            end

            local existing = GetDefaultMediaPlayer(Config.defaultMediaPlayers, dmp.position)
            if existing then
                for k, v in pairs(dmp) do existing[k] = v end
            else
                Config.defaultMediaPlayers[#Config.defaultMediaPlayers + 1] = dmp
            end
        end
    end

    syncSettings()
end

function AddModelPermanently(model, data)
    data.handle = nil
    data.method = nil
    data.model  = nil

    if data.renderTarget == "" then data.renderTarget = nil end
    if data.label == "" then data.label = nil end

    local existing = GetModelConfig(model)
    if existing then
        for k, v in pairs(data) do existing[k] = v end
    else
        Config.models[model] = data
        if type(InvalidateModelConfigCache) == "function" then
            InvalidateModelConfigCache()
        end
    end

    local models = json.decode(LoadResourceFile(thisResource, "models.json")) or {}
    models[tostring(model)] = data
    SaveResourceFile(thisResource, "models.json", json.encode(models), -1)

    syncSettings()
end

function AddEntityPermanently(coords, data)
    data.handle   = nil
    data.method   = nil
    data.position = coords

    local existing = GetDefaultMediaPlayer(Config.defaultMediaPlayers, coords)
    if existing then
        for k, v in pairs(data) do existing[k] = v end
    else
        Config.defaultMediaPlayers[#Config.defaultMediaPlayers + 1] = data
    end

    local defaultMediaPlayers = json.decode(LoadResourceFile(thisResource, "defaultMediaPlayers.json")) or {}
    for _, dmp in ipairs(defaultMediaPlayers) do
        dmp.position = ToVector3(dmp.position)
        if dmp.scaleform then
            dmp.scaleform.position = ToVector3(dmp.scaleform.position)
            dmp.scaleform.rotation = ToVector3(dmp.scaleform.rotation)
            dmp.scaleform.scale    = ToVector3(dmp.scaleform.scale)
        end
    end

    local found = false
    for _, dmp in ipairs(defaultMediaPlayers) do
        if IsSameEntity(coords, dmp.position) then
            for k, v in pairs(data) do dmp[k] = v end
            found = true
            break
        end
    end
    if not found then
        defaultMediaPlayers[#defaultMediaPlayers + 1] = data
    end

    SaveResourceFile(thisResource, "defaultMediaPlayers.json", json.encode(defaultMediaPlayers), -1)
    syncSettings()
end

function RemoveModelPermanently(model)
    local data = GetModelConfig(model)
    Config.models[model] = nil

    local models = json.decode(LoadResourceFile(thisResource, "models.json"))
    if models then
        models[tostring(model)] = nil
        SaveResourceFile(thisResource, "models.json", json.encode(models), -1)
    end

    syncSettings()
    return data
end

function RemoveEntityPermanently(coords)
    local data
    for i = 1, #Config.defaultMediaPlayers do
        if IsSameEntity(coords, Config.defaultMediaPlayers[i].position) then
            data = table.remove(Config.defaultMediaPlayers, i)
            break
        end
    end

    local defaultMediaPlayers = json.decode(LoadResourceFile(thisResource, "defaultMediaPlayers.json"))
    if defaultMediaPlayers then
        for i = 1, #defaultMediaPlayers do
            if IsSameEntity(coords, ToVector3(defaultMediaPlayers[i].position)) then
                table.remove(defaultMediaPlayers, i)
                break
            end
        end
        SaveResourceFile(thisResource, "defaultMediaPlayers.json", json.encode(defaultMediaPlayers), -1)
    end

    syncSettings()
    return data
end

RegisterNetEvent("pmms:saveModel", function(model, data)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to save model defaults")
        return
    end
    AddModelPermanently(model, data)
    TriggerClientEvent("pmms:notify", src, { text = 'Model "' .. (data.label or "?") .. '" saved' })
end)

RegisterNetEvent("pmms:saveEntity", function(coords, data)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to save entity defaults")
        return
    end
    AddEntityPermanently(coords, data)
    TriggerClientEvent("pmms:notify", src, { text = 'Entity "' .. (data.label or "?") .. '" saved' })
end)

RegisterNetEvent("pmms:deleteModel", function(model)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to delete model defaults")
        return
    end
    local data = RemoveModelPermanently(model)
    if data then
        TriggerClientEvent("pmms:notify", src, { text = 'Model "' .. (data.label or "?") .. '" deleted' })
    end
end)

RegisterNetEvent("pmms:deleteEntity", function(coords)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to delete entity defaults")
        return
    end
    local data = RemoveEntityPermanently(coords)
    if data then
        TriggerClientEvent("pmms:notify", src, { text = 'Entity "' .. (data.label or "?") .. '" deleted' })
    end
end)

exports("addModel", function(model, data) AddModelPermanently(model, data) end)
exports("addModelPermanently", AddModelPermanently)
exports("addEntity", function(coords, data) AddEntityPermanently(coords, data) end)
exports("addEntityPermanently", AddEntityPermanently)
exports("removeModel", function(model)
    Config.models[model] = nil
    syncSettings()
end)
exports("removeModelPermanently", RemoveModelPermanently)
exports("removeEntity", function(coords)
    for i = 1, #Config.defaultMediaPlayers do
        if IsSameEntity(coords, Config.defaultMediaPlayers[i].position) then
            table.remove(Config.defaultMediaPlayers, i)
            break
        end
    end
    syncSettings()
end)
exports("removeEntityPermanently", RemoveEntityPermanently)
