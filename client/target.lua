local targetRegistered = false
local registeredSystem = nil
local registeredModels = {}
local registeredZones = {}
local registeredDynamicEntities = {}
local TARGET_OPTION_NAME = "pmms_open_media"

local function getTargetConfig()
    local cfg = Config.targeting or {}
    return {
        system = tostring(cfg.system or "fallback"),
        label = tostring(cfg.label or "Open Media"),
        icon = tostring(cfg.icon or "fas fa-music"),
        distance = tonumber(cfg.distance) or 2.0,
    }
end

local function collectTargetModels()
    if type(GetModelTargetKeys) == "function" then
        local targetModels = GetModelTargetKeys()
        local models = {}
        for _, model in ipairs(targetModels or {}) do
            models[#models + 1] = model
        end
        return models
    end

    local models = {}
    for model in pairs(Config.models or {}) do
        models[#models + 1] = model
    end
    return models
end

local function getNetworkHandle(entity)
    if not entity or not DoesEntityExist(entity) then
        return nil
    end
    return getEntityNetworkId(entity)
end

local function getExistingNetworkHandle(entity)
    if not entity or not DoesEntityExist(entity) or not NetworkGetEntityIsNetworked(entity) then
        return nil
    end
    return NetworkGetNetworkIdFromEntity(entity)
end

local function isActiveMediaEntity(entity)
    local handle = getExistingNetworkHandle(entity)
    if not handle or type(GetMediaPlayerStates) ~= "function" then
        return false
    end
    local states = GetMediaPlayerStates() or {}
    return states[handle] ~= nil or states[tostring(handle)] ~= nil
end

local function isTargetableObject(entity)
    if not entity or not DoesEntityExist(entity) then
        return false
    end

    if IsEntityAVehicle(entity) then
        return Config.allowPlayingFromVehicles == true
    end

    local model = GetEntityModel(entity)
    return GetModelConfig(model) ~= nil or isActiveMediaEntity(entity)
end

local function resolveHandleFromTargetEntity(entity)
    if not isTargetableObject(entity) then
        return nil
    end
    return getNetworkHandle(entity)
end

local function openUiForHandle(handle)
    if not handle then
        ShowNotification("No media player in range", nil, "#ff4444")
        return
    end
    ShowUi(handle)
end

local function openUiForEntity(entity)
    openUiForHandle(resolveHandleFromTargetEntity(entity))
end

RegisterNetEvent("pmms:openUiForEntity", function(entity)
    openUiForEntity(entity)
end)

RegisterNetEvent("pmms:openUiForHandle", function(handle)
    openUiForHandle(handle)
end)

local function getDefaultMediaPlayerCoords(entry)
    if type(entry) ~= "table" or type(entry.position) ~= "table" then
        return nil
    end
    if tonumber(entry.position.x) == nil or tonumber(entry.position.y) == nil or tonumber(entry.position.z) == nil then
        return nil
    end
    return ToVector3(entry.position)
end

local function getDefaultMediaPlayerHandle(entry)
    local coords = getDefaultMediaPlayerCoords(entry)
    if not coords then
        return nil
    end
    return GetHandleFromCoords(coords), coords
end

local function buildQbOption(targetCfg, handler, canInteract)
    return {
        type = "client",
        icon = targetCfg.icon,
        label = targetCfg.label,
        action = handler,
        canInteract = canInteract or function(entity)
            return isTargetableObject(entity)
        end,
    }
end

local function setupQbTargetZones(targetCfg)
    for index, entry in ipairs(Config.defaultMediaPlayers or {}) do
        local handle, coords = getDefaultMediaPlayerHandle(entry)
        if handle and coords then
            local zoneName = ("pmms_default_%s_%d"):format(tostring(handle), index)
            exports["qb-target"]:AddCircleZone(zoneName, coords, targetCfg.distance, {
                name = zoneName,
                debugPoly = false,
                useZ = true,
            }, {
                options = {
                    {
                        type = "client",
                        icon = targetCfg.icon,
                        label = targetCfg.label,
                        action = function()
                            openUiForHandle(handle)
                        end,
                    },
                },
                distance = targetCfg.distance,
            })
            registeredZones[#registeredZones + 1] = { system = "qb-target", name = zoneName }
        end
    end
end

local function setupQbTarget()
    local targetCfg = getTargetConfig()
    local models = collectTargetModels()
    registeredModels = models

    if #models > 0 then
        exports["qb-target"]:AddTargetModel(models, {
            options = {
                buildQbOption(targetCfg, function(entity)
                    openUiForEntity(entity)
                end),
            },
            distance = targetCfg.distance,
        })
    end

    if Config.allowPlayingFromVehicles == true then
        exports["qb-target"]:AddGlobalVehicle({
            options = {
                buildQbOption(targetCfg, function(entity)
                    openUiForEntity(entity)
                end),
            },
            distance = targetCfg.distance,
        })
    end

    pcall(function()
        exports["qb-target"]:AddGlobalObject({
            options = {
                buildQbOption(targetCfg, function(entity)
                    openUiForEntity(entity)
                end, function(entity)
                    if not entity or not DoesEntityExist(entity) or IsEntityAVehicle(entity) then
                        return false
                    end
                    return GetModelConfig(GetEntityModel(entity)) == nil and isActiveMediaEntity(entity)
                end),
                {
                    type = "client",
                    icon = "fas fa-trash",
                    label = "Remove Speaker",
                    action = function(entity)
                        local handle, id = GetSpeakerPropHandleAndId(entity)
                        if handle and id then
                            TriggerServerEvent("pmms:removeLinkedSpeaker", handle, id)
                        end
                    end,
                    canInteract = function(entity)
                        local handle, id = GetSpeakerPropHandleAndId(entity)
                        return handle ~= nil and id ~= nil
                    end,
                }
            },
            distance = targetCfg.distance,
        })
    end)

    setupQbTargetZones(targetCfg)
end

local function buildOxOption(targetCfg, nameSuffix, handler, canInteract)
    return {
        name = nameSuffix and (TARGET_OPTION_NAME .. "_" .. tostring(nameSuffix)) or TARGET_OPTION_NAME,
        icon = targetCfg.icon,
        label = targetCfg.label,
        distance = targetCfg.distance,
        canInteract = canInteract or function(entity)
            return isTargetableObject(entity)
        end,
        onSelect = handler,
    }
end

local function setupOxTargetZones(targetCfg)
    for index, entry in ipairs(Config.defaultMediaPlayers or {}) do
        local handle, coords = getDefaultMediaPlayerHandle(entry)
        if handle and coords then
            local zoneName = ("pmms_default_%s_%d"):format(tostring(handle), index)
            local zoneId = exports.ox_target:addSphereZone({
                name = zoneName,
                coords = coords,
                radius = targetCfg.distance,
                debug = false,
                options = {
                    buildOxOption(targetCfg, handle, function()
                        openUiForHandle(handle)
                    end, function()
                        return true
                    end),
                },
            })
            registeredZones[#registeredZones + 1] = { system = "ox_target", id = zoneId or zoneName }
        end
    end
end

local function removeDynamicTarget(netId, entry)
    if not entry then
        return
    end

    if registeredSystem == "qb-target" and entry.entity and GetResourceState("qb-target") == "started" then
        pcall(function()
            exports["qb-target"]:RemoveTargetEntity(entry.entity)
        end)
    elseif registeredSystem == "ox_target" and GetResourceState("ox_target") == "started" then
        pcall(function()
            exports.ox_target:removeEntity(netId, TARGET_OPTION_NAME .. "_entity")
        end)
    end
end

local function registerDynamicTargetEntity(netId, entity)
    if registeredDynamicEntities[netId] or not entity or not DoesEntityExist(entity) then
        return
    end

    local targetCfg = getTargetConfig()
    if registeredSystem == "qb-target" and GetResourceState("qb-target") == "started" then
        exports["qb-target"]:AddTargetEntity(entity, {
            options = {
                buildQbOption(targetCfg, function(targetEntity)
                    openUiForEntity(targetEntity)
                end),
            },
            distance = targetCfg.distance,
        })
        registeredDynamicEntities[netId] = { entity = entity }
    elseif registeredSystem == "ox_target" and GetResourceState("ox_target") == "started" then
        exports.ox_target:addEntity(netId, {
            buildOxOption(targetCfg, "entity", function(data)
                openUiForEntity(data and data.entity or entity)
            end),
        })
        registeredDynamicEntities[netId] = { entity = entity }
    end
end

local function refreshDynamicTargets()
    if not targetRegistered then
        return
    end

    local desired = {}
    local states = type(GetMediaPlayerStates) == "function" and GetMediaPlayerStates() or {}
    for handle in pairs(states or {}) do
        local netId = tonumber(handle)
        if netId and NetworkDoesEntityExistWithNetworkId(netId) then
            local entity = NetworkGetEntityFromNetworkId(netId)
            if entity and DoesEntityExist(entity) and not IsEntityAVehicle(entity) and not GetModelConfig(GetEntityModel(entity)) then
                desired[netId] = true
                registerDynamicTargetEntity(netId, entity)
            end
        end
    end

    for netId, entry in pairs(registeredDynamicEntities) do
        if not desired[netId] or not entry.entity or not DoesEntityExist(entry.entity) then
            removeDynamicTarget(netId, entry)
            registeredDynamicEntities[netId] = nil
        end
    end
end

local function setupOxTarget()
    local targetCfg = getTargetConfig()
    local models = collectTargetModels()
    registeredModels = models

    if #models > 0 then
        exports.ox_target:addModel(models, {
            buildOxOption(targetCfg, nil, function(data)
                openUiForEntity(data and data.entity or nil)
            end),
        })
    end

    pcall(function()
        exports.ox_target:addGlobalObject({
            buildOxOption(targetCfg, "global_object", function(data)
                openUiForEntity(data and data.entity or nil)
            end, function(entity)
                if not entity or not DoesEntityExist(entity) or IsEntityAVehicle(entity) then
                    return false
                end
                return GetModelConfig(GetEntityModel(entity)) == nil and isActiveMediaEntity(entity)
            end),
            {
                name = TARGET_OPTION_NAME .. "_remove_speaker",
                icon = "fas fa-trash",
                label = "Remove Speaker",
                distance = targetCfg.distance,
                canInteract = function(entity)
                    local handle, id = GetSpeakerPropHandleAndId(entity)
                    return handle ~= nil and id ~= nil
                end,
                onSelect = function(data)
                    local entity = data and data.entity or nil
                    if entity then
                        local handle, id = GetSpeakerPropHandleAndId(entity)
                        if handle and id then
                            TriggerServerEvent("pmms:removeLinkedSpeaker", handle, id)
                        end
                    end
                end,
            }
        })
    end)

    if Config.allowPlayingFromVehicles == true then
        exports.ox_target:addGlobalVehicle({
            buildOxOption(targetCfg, "global_vehicle", function(data)
                openUiForEntity(data and data.entity or nil)
            end, function(entity)
                return entity and DoesEntityExist(entity) and IsEntityAVehicle(entity)
            end),
        })
    end

    setupOxTargetZones(targetCfg)
end

local function cleanupQbTarget()
    local targetCfg = getTargetConfig()
    if #registeredModels > 0 then
        pcall(function()
            exports["qb-target"]:RemoveTargetModel(registeredModels, targetCfg.label)
        end)
    end

    pcall(function()
        exports["qb-target"]:RemoveGlobalVehicle(targetCfg.label)
    end)
    pcall(function()
        exports["qb-target"]:RemoveGlobalObject(targetCfg.label)
    end)
end

local function cleanupOxTarget()
    if #registeredModels > 0 then
        pcall(function()
            exports.ox_target:removeModel(registeredModels, TARGET_OPTION_NAME)
        end)
    end

    pcall(function()
        exports.ox_target:removeGlobalObject({ TARGET_OPTION_NAME .. "_global_object" })
    end)
    pcall(function()
        exports.ox_target:removeGlobalVehicle({ TARGET_OPTION_NAME .. "_global_vehicle" })
    end)
end

function CleanupTargetIntegration()
    if not targetRegistered then
        return
    end

    if registeredSystem == "qb-target" and GetResourceState("qb-target") == "started" then
        cleanupQbTarget()
    elseif registeredSystem == "ox_target" and GetResourceState("ox_target") == "started" then
        cleanupOxTarget()
    end

    for _, zone in ipairs(registeredZones) do
        if zone.system == "qb-target" and GetResourceState("qb-target") == "started" then
            pcall(function()
                exports["qb-target"]:RemoveZone(zone.name)
            end)
        elseif zone.system == "ox_target" and GetResourceState("ox_target") == "started" then
            pcall(function()
                exports.ox_target:removeZone(zone.id, true)
            end)
        end
    end

    for netId, entry in pairs(registeredDynamicEntities) do
        removeDynamicTarget(netId, entry)
    end

    registeredZones = {}
    registeredModels = {}
    registeredDynamicEntities = {}
    registeredSystem = nil
    targetRegistered = false
end

function SetupTargetIntegration()
    if targetRegistered then
        return
    end

    local targetCfg = getTargetConfig()
    local systemName = targetCfg.system:lower()

    if systemName == "qb-target" then
        if GetResourceState("qb-target") == "started" then
            setupQbTarget()
            registeredSystem = "qb-target"
            targetRegistered = true
        else
            PMMSDebug("target", "qb-target configured but not started; fallback interaction remains active")
        end
        return
    end

    if systemName == "ox_target" then
        if GetResourceState("ox_target") == "started" then
            setupOxTarget()
            registeredSystem = "ox_target"
            targetRegistered = true
        else
            PMMSDebug("target", "ox_target configured but not started; fallback interaction remains active")
        end
    end
end

function RefreshTargetIntegration()
    CleanupTargetIntegration()
    SetupTargetIntegration()
end

RegisterNetEvent("pmms:loadSettings", function()
    SetTimeout(250, RefreshTargetIntegration)
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        CleanupTargetIntegration()
    elseif resourceName == registeredSystem then
        CleanupTargetIntegration()
    end
end)

AddEventHandler("onResourceStart", function(resourceName)
    local targetCfg = getTargetConfig()
    if resourceName == targetCfg.system then
        SetTimeout(1000, SetupTargetIntegration)
    end
end)

CreateThread(function()
    Wait(1500)
    SetupTargetIntegration()
end)

CreateThread(function()
    while true do
        refreshDynamicTargets()
        Wait(targetRegistered and 2500 or 5000)
    end
end)
