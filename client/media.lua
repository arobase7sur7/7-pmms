local activePlayers = {}
local creatingPlayers = {}

local function normalizeUrl(url)
    if type(url) ~= "string" or url == "" then
        return nil
    end
    if url:sub(-1) ~= "/" then
        url = url .. "/"
    end
    return url
end

local function getLocalDuiUrl()
    return normalizeUrl(("http://%s/%s/dui/"):format(GetCurrentServerEndpoint(), GetCurrentResourceName()))
end

local function isHttpsUrl(url)
    return type(url) == "string" and url:match("^https://") ~= nil
end

local function getHostedDuiUrl()
    local dui = type(Config.dui) == "table" and Config.dui or {}
    local urls = type(dui.urls) == "table" and dui.urls or {}
    local url = urls.https
    if not isHttpsUrl(url) then
        local player = type(Config.player) == "table" and Config.player or {}
        url = player.hostedPlayerUrl
    end
    if not isHttpsUrl(url) then
        return nil
    end
    return normalizeUrl(url)
end

local function isHostedResolver(options)
    if type(options) ~= "table" then
        return false
    end
    if options.hostedPlayer == true then
        return true
    end
    local resolver = type(options.resolver) == "table" and options.resolver or {}
    return resolver.provider == "hosted_player"
end

local function getDuiUrl(options)
    if isHostedResolver(options) then
        return getHostedDuiUrl() or getLocalDuiUrl()
    end
    return getLocalDuiUrl()
end

local function resolvePlayerDimensions(model)
    local width = Config.dui.screenWidth
    local height = Config.dui.screenHeight

    local modelSettings = GetModelConfig(model)
    if modelSettings then
        if modelSettings.width and modelSettings.height then
            width = modelSettings.width
            height = modelSettings.height
        end
    end

    return width, height
end

local function resolveRenderTarget(model)
    local modelSettings = GetModelConfig(model)
    if modelSettings then
        return modelSettings.renderTarget
    end
    return nil
end

local function resolveStartupEntity(handle)
    if type(GetEntityEntryByNetworkId) == "function" then
        local entry = GetEntityEntryByNetworkId(handle)
        if entry then
            return entry.entity, entry.model, entry.type
        end
    end

    local numericHandle = tonumber(handle)
    if numericHandle and NetworkDoesEntityExistWithNetworkId(numericHandle) then
        local entity = NetworkGetEntityFromNetworkId(numericHandle)
        if entity and DoesEntityExist(entity) then
            local model = GetEntityModel(entity)
            local entityType = IsEntityAVehicle(entity) and "vehicle" or "object"
            return entity, model, entityType
        end
    end

    return nil, nil, nil
end

local function createBrowser(handle, options, model)
    local width, height = resolvePlayerDimensions(model)
    local renderTarget = resolveRenderTarget(model)

    return DuiBrowser:new(
        handle,
        model,
        renderTarget,
        options.scaleform,
        getDuiUrl(options),
        options,
        width,
        height,
        tonumber(Config.dui.timeout) or 30000
    )
end

function GetActivePlayers()
    return activePlayers
end

function GetActivePlayer(handle)
    return activePlayers[handle]
end

local function getPlayerPlaybackToken(player, options, playbackToken)
    if type(playbackToken) == "string" and playbackToken ~= "" then
        return playbackToken
    end

    local optionToken = options and options.playbackToken or nil
    if type(optionToken) == "string" and optionToken ~= "" then
        return optionToken
    end

    local currentToken = player and player.playbackToken or nil
    if type(currentToken) == "string" and currentToken ~= "" then
        return currentToken
    end

    return nil
end

function InitMediaPlayer(handle, options, entity, model, entityType, startupAttemptId, playbackToken, startupTimeoutMs)
    local existing = activePlayers[handle]
    if existing then
        if not startupAttemptId then
            return existing
        end
        if existing.pendingStart
            and tostring(existing.startupAttemptId) == tostring(startupAttemptId)
            and tostring(existing.playbackToken or "") == tostring(getPlayerPlaybackToken(existing, options, playbackToken) or "") then
            return existing
        end
        DestroyMediaPlayer(handle)
    end

    if creatingPlayers[handle] then
        return nil
    end
    creatingPlayers[handle] = true

    if not options or not options.url then
        creatingPlayers[handle] = nil
        return nil
    end

    local browser = createBrowser(handle, options, model)
    if not browser then
        local resolvedPlaybackToken = getPlayerPlaybackToken(nil, options, playbackToken)
        MarkMediaPlayerFailed(handle, "DUI browser could not be created.", {
            playbackToken = resolvedPlaybackToken,
            stateRevision = options and options.stateRevision or nil,
            url = options and (options.originalUrl or options.url) or nil,
        })
        if startupAttemptId then
            TriggerServerEvent(
                "pmms:startupError",
                handle,
                startupAttemptId,
                options and options.url or nil,
                "DUI browser could not be created.",
                resolvedPlaybackToken
            )
        end
        creatingPlayers[handle] = nil
        return nil
    end

    local resolvedPlaybackToken = getPlayerPlaybackToken(nil, options, playbackToken)
    activePlayers[handle] = {
        browser = browser,
        options = options,
        entity = entity,
        entityType = entityType,
        model = model,
        pendingStart = startupAttemptId ~= nil,
        startupAttemptId = startupAttemptId,
        playbackToken = resolvedPlaybackToken,
        startupTimeoutMs = startupTimeoutMs,
    }

    if entity then
        LinkEntityToMediaPlayer(handle, entity, model, entityType)
    end

    if startupAttemptId then
        browser:sendMessage({
            type = "startup",
            handle = handle,
            attemptId = startupAttemptId,
            playbackToken = resolvedPlaybackToken,
            startupTimeoutMs = startupTimeoutMs,
            options = options,
        })
    end

    if type(ApplyEffectiveEqProfileToBrowser) == "function" then
        ApplyEffectiveEqProfileToBrowser(browser, options.equalizerProfile)
    elseif type(options.equalizerProfile) == "table" then
        browser:sendMessage({ type = "applyEqProfile", profile = options.equalizerProfile })
    end

    creatingPlayers[handle] = nil
    return activePlayers[handle]
end

function StartMediaPlayerStartupAttempt(handle, attemptId, options, playbackToken, startupTimeoutMs)
    local entity, model, entityType = resolveStartupEntity(handle)
    return InitMediaPlayer(handle, options, entity, model, entityType, attemptId, playbackToken, startupTimeoutMs)
end

function MarkStartupAttemptReady(handle, attemptId, options, playbackToken)
    local player = activePlayers[handle]
    if not player then
        return false
    end

    if player.pendingStart and tostring(player.startupAttemptId) ~= tostring(attemptId) then
        return false
    end

    if playbackToken and tostring(player.playbackToken or "") ~= tostring(playbackToken) then
        return false
    end

    player.pendingStart = false
    player.startupAttemptId = nil
    player.startupTimeoutMs = nil
    player.playbackToken = getPlayerPlaybackToken(player, options, playbackToken)
    if options then
        player.options = options
    end

    return true
end

function StopMediaPlayerStartupAttempt(handle, attemptId, playbackToken)
    local player = activePlayers[handle]
    if not player or not player.pendingStart then
        return false
    end

    if attemptId and tostring(player.startupAttemptId) ~= tostring(attemptId) then
        return false
    end

    if playbackToken and tostring(player.playbackToken or "") ~= tostring(playbackToken) then
        return false
    end

    DestroyMediaPlayer(handle)
    return true
end

function HandleLocalMediaPlayerError(handle, attemptId, message, url, playbackToken)
    local player = activePlayers[handle]
    local failureOptions = player and player.options or nil
    local failureToken = getPlayerPlaybackToken(player, failureOptions, playbackToken)

    if attemptId then
        if not player or not player.pendingStart or tostring(player.startupAttemptId) ~= tostring(attemptId) then
            return false
        end
        if playbackToken and tostring(player.playbackToken or "") ~= tostring(playbackToken) then
            return false
        end
        StopMediaPlayerStartupAttempt(handle, attemptId, playbackToken)
    else
        if not player then
            return false
        end
        if playbackToken and tostring(player.playbackToken or "") ~= tostring(playbackToken) then
            return false
        end
        if type(url) == "string" and url ~= "" then
            local currentUrl = player.options and player.options.url or nil
            if type(currentUrl) == "string" and currentUrl ~= url then
                return false
            end
        end
        DestroyMediaPlayer(handle)
    end

    MarkMediaPlayerFailed(handle, message, {
        playbackToken = failureToken,
        stateRevision = failureOptions and failureOptions.stateRevision or nil,
        url = failureOptions and (failureOptions.originalUrl or failureOptions.url) or url,
    })
    return true
end

function DestroyMediaPlayer(handle)
    local player = activePlayers[handle]
    if not player then
        return
    end

    player.browser:destroy()
    activePlayers[handle] = nil
    creatingPlayers[handle] = nil
end

function DestroyAllMediaPlayers()
    for handle in pairs(activePlayers) do
        DestroyMediaPlayer(handle)
    end
end

function GetNearbyActiveMediaPlayers(playerPos, mediaPlayerStates)
    local nearby = {}

    for handle, info in pairs(mediaPlayerStates) do
        local player = activePlayers[handle]
        local distance = -1

        if info.coords then
            local coords = ToVector3(info.coords)
            if coords then
                distance = #(playerPos - coords)
            end
        elseif player and player.entity and DoesEntityExist(player.entity) then
            distance = #(playerPos - GetEntityCoords(player.entity))
        end

        nearby[#nearby + 1] = {
            handle = handle,
            info = info,
            distance = distance,
            player = player,
        }
    end

    table.sort(nearby, function(a, b)
        return a.distance < b.distance
    end)

    return nearby
end

function LinkEntityToMediaPlayer(handle, entity, model, entityType)
    local player = activePlayers[handle]
    if not player then
        return
    end

    player.entity = entity
    player.model = model
    player.entityType = entityType

    local modelConfig = GetModelConfig(model)
    if modelConfig and modelConfig.renderTarget then
        player.browser:enableRenderTarget(entity, modelConfig.renderTarget)
    end
end

function UnlinkEntityFromMediaPlayer(handle)
    local player = activePlayers[handle]
    if not player then
        return
    end

    player.browser:disableRenderTarget()
    player.entity = nil
    player.model = nil
    player.entityType = nil
end

function SetupScaleformForMediaPlayer(handle, scaleform, entity)
    local player = activePlayers[handle]
    if not player then
        return
    end

    player.browser:enableScaleform(scaleform.name, entity, scaleform.attached)
    player.scaleform = scaleform
end

function RemoveScaleformFromMediaPlayer(handle)
    local player = activePlayers[handle]
    if not player then
        return
    end

    player.browser:disableScaleform()
    player.scaleform = nil
end
