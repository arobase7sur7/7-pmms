local targetRegistered = false

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

local function resolveHandleFromTargetEntity(entity)
    if not entity or not DoesEntityExist(entity) then
        return nil
    end

    local model = GetEntityModel(entity)
    if not GetModelConfig(model) then
        return nil
    end

    return getEntityNetworkId(entity)
end

local function openUiForHandle(handle)
    if not handle then
        ShowNotification("No media player in range", nil, "#ff4444")
        return
    end

    ShowUi(handle)
end

RegisterNetEvent("pmms:openUiForEntity", function(entity)
    local handle = resolveHandleFromTargetEntity(entity)
    openUiForHandle(handle)
end)

local function setupQbTarget()
    local targetCfg = getTargetConfig()
    local models = collectTargetModels()
    if #models == 0 then
        return
    end

    exports["qb-target"]:AddTargetModel(models, {
        options = {
            {
                icon = targetCfg.icon,
                label = targetCfg.label,
                action = function(entity)
                    TriggerEvent("pmms:openUiForEntity", entity)
                end,
            }
        },
        distance = targetCfg.distance,
    })
end

local function setupOxTarget()
    local targetCfg = getTargetConfig()
    local models = collectTargetModels()
    if #models == 0 then
        return
    end

    exports.ox_target:addModel(models, {
        {
            name = "pmms_open_media",
            icon = targetCfg.icon,
            label = targetCfg.label,
            distance = targetCfg.distance,
            onSelect = function(data)
                TriggerEvent("pmms:openUiForEntity", data and data.entity or nil)
            end,
        }
    })
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
            targetRegistered = true
        else
            print("[7-pmms] qb-target is configured but not started; using fallback mode.")
        end
        return
    end

    if systemName == "ox_target" then
        if GetResourceState("ox_target") == "started" then
            setupOxTarget()
            targetRegistered = true
        else
            print("[7-pmms] ox_target is configured but not started; using fallback mode.")
        end
        return
    end
end

CreateThread(function()
    Wait(1500)
    SetupTargetIntegration()
end)
