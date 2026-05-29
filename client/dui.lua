local Class = {}

setmetatable(Class, {
    __call = function(self)
        self.__call = getmetatable(self).__call
        self.__index = self
        return setmetatable({}, self)
    end
})

function Class:new()
    return self()
end

DuiBrowser = Class()

DuiBrowser.initQueue = {}
DuiBrowser.pool = {}
DuiBrowser.renderTargets = {}
DuiBrowser.scaleforms = {}
local duiWarningTimestamps = {}
local duiRenderStats = {
    total = 0,
    renderable = 0,
    rendered = 0,
    lastFrameMs = 0,
    lastTickAt = 0,
}

local function getConfiguredDuiFps(key, fallback, minValue, maxValue)
    local value = tonumber(Config.dui and Config.dui[key]) or fallback
    value = math.floor(value)
    if value < minValue then
        value = minValue
    elseif value > maxValue then
        value = maxValue
    end
    return value
end

local function countDuiBrowsers()
    local count = 0
    for _ in pairs(DuiBrowser.pool) do
        count = count + 1
    end
    return count
end

function GetDuiBrowserPerfStats()
    return {
        total = duiRenderStats.total,
        renderable = duiRenderStats.renderable,
        rendered = duiRenderStats.rendered,
        lastFrameMs = duiRenderStats.lastFrameMs,
        lastTickAt = duiRenderStats.lastTickAt,
    }
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

local function printDuiWarning(key, message, cooldownMs)
    local now = GetGameTimer()
    local cooldown = tonumber(cooldownMs) or 10000
    if (now - (duiWarningTimestamps[key] or 0)) < cooldown then
        return
    end
    duiWarningTimestamps[key] = now
    print(message)
end

function DuiBrowser:createNamedRendertargetForModel(model, name)
    local handle = 0
    if not IsNamedRendertargetRegistered(name) then
        RegisterNamedRendertarget(name, 0)
    end
    if not IsNamedRendertargetLinked(model) then
        LinkNamedRendertarget(model)
    end
    if IsNamedRendertargetRegistered(name) then
        handle = GetNamedRendertargetRenderId(name)
    end
    return handle
end

function DuiBrowser:waitForConnection()
    self.initDone = false
    DuiBrowser.initQueue[self.mediaPlayerHandle] = self
    local timeout = GetGameTimer() + (self.timeout or Config.dui.timeout or 30000)

    while not DuiBrowser.initQueue[self.mediaPlayerHandle].initDone and GetGameTimer() < timeout do
        self:sendMessage({type = "DuiBrowser:init", handle = self.mediaPlayerHandle})
        Citizen.Wait(500)
    end

    DuiBrowser.initQueue[self.mediaPlayerHandle] = nil
    if self.initDone then
        return true
    else
        printDuiWarning(
            "init_timeout:" .. tostring(self.mediaPlayerHandle),
            ("^1[7-pmms] Failed to initialize DUI browser for handle %s within timeout^7"):format(tostring(self.mediaPlayerHandle)),
            10000
        )
        return false
    end
end

function DuiBrowser:createTexture()
    if self.txdName then return end
    self.txdName = "pmms_txd_" .. tostring(self.mediaPlayerHandle)
    self.txnName = "video"
    self.txd = CreateRuntimeTxd(self.txdName)
    self.txn = CreateRuntimeTextureFromDuiHandle(self.txd, self.txnName, self.duiHandle)
end

function DuiBrowser:new(mediaPlayerHandle, model, renderTarget, scaleform, url, options, w, h, timeout)
    local self = Class.new(self)

    if DuiBrowser.initQueue[mediaPlayerHandle] then
        return DuiBrowser.initQueue[mediaPlayerHandle]
    end

    self.mediaPlayerHandle = mediaPlayerHandle
    self.model = model
    self.renderTarget = renderTarget
    self.scaleform = scaleform
    self.duiUrl = url
    self.options = options
    self.w = w or Config.dui.screenWidth
    self.h = h or Config.dui.screenHeight
    self.timeout = timeout

    local thisResource = GetCurrentResourceName()
    local fullUrl = self.duiUrl
    local version = GetResourceMetadata(thisResource, "version", 0) or "dev"
    local cacheBuster = tostring(version)
    if Config.dui and Config.dui.cacheRuntimeAssets == false then
        cacheBuster = cacheBuster .. "-" .. tostring(GetGameTimer())
    end
    if not string.find(fullUrl, "[?]") then
        fullUrl = fullUrl .. "?resourceName=" .. thisResource .. "&duiVersion=" .. cacheBuster
    else
        fullUrl = fullUrl .. "&resourceName=" .. thisResource .. "&duiVersion=" .. cacheBuster
    end

    self.duiObject = CreateDui(fullUrl, math.floor(self.w), math.floor(self.h))
    self.duiHandle = GetDuiHandle(self.duiObject)

    if self.renderTarget or self.scaleform then
        self:createTexture()
    end

    if self:waitForConnection() then
        DuiBrowser.pool[self.mediaPlayerHandle] = self
        return self
    else
        if self.duiObject then
            DestroyDui(self.duiObject)
        end
        return nil
    end
end

function DuiBrowser:enableRenderTarget(entity, name)
    self.renderTarget = name
    self.entity = entity
    if not self.txdName then
        self:createTexture()
    end
    if not DuiBrowser.renderTargets[name] then
        DuiBrowser.renderTargets[name] = { browsers = {} }
    end
    DuiBrowser.renderTargets[name].browsers[self] = true
    self.renderTargetHandle = self:createNamedRendertargetForModel(GetEntityModel(entity), name)
end

function DuiBrowser:disableRenderTarget()
    if self.renderTarget then
        local entry = DuiBrowser.renderTargets[self.renderTarget]
        if entry then
            entry.browsers[self] = nil
            if not next(entry.browsers) then
                DuiBrowser.renderTargets[self.renderTarget] = nil
            end
        end
        self.renderTarget = nil
        self.renderTargetHandle = nil
    end
end

function DuiBrowser:enableScaleform(name, entity)
    self.sfName = name
    self.entity = entity
    if not self.txdName then
        self:createTexture()
    end
    self.sfHandle = RequestScaleformMovie(name)
    if not DuiBrowser.scaleforms[name] then
        DuiBrowser.scaleforms[name] = { browsers = {} }
    end
    DuiBrowser.scaleforms[name].browsers[self] = true
end

function DuiBrowser:disableScaleform()
    if self.sfName then
        local entry = DuiBrowser.scaleforms[self.sfName]
        if entry then
            entry.browsers[self] = nil
            if not next(entry.browsers) then
                DuiBrowser.scaleforms[self.sfName] = nil
            end
        end
        SetScaleformMovieAsNoLongerNeeded(self.sfHandle)
        self.sfName = nil
        self.sfHandle = nil
    end
end

function DuiBrowser:setRenderState(active)
    self.renderActive = active == true
end

function DuiBrowser:shouldRender()
    if not self.renderActive then
        return false
    end

    if self.renderTarget and self.renderTargetHandle then
        return true
    end

    return self.sfHandle ~= nil
end

function DuiBrowser:renderFrame(drawSprite)
    if self.renderTarget and self.renderTargetHandle then
        SetTextRenderId(self.renderTargetHandle)
        Set_2dLayer(4)
        SetScriptGfxDrawBehindPausemenu(1)
        if drawSprite and self.txdName then
            DrawSprite(self.txdName, self.txnName, 0.5, 0.5, 1.0, 1.0, 0.0, 255, 255, 255, 255)
        else
            DrawRect(0.5, 0.5, 1.0, 1.0, 0, 0, 0, 255)
        end
        SetTextRenderId(GetDefaultScriptRendertargetRenderId())
        SetScriptGfxDrawBehindPausemenu(0)
    elseif self.sfHandle and HasScaleformMovieLoaded(self.sfHandle) then
        if drawSprite and self.txdName then
            BeginScaleformMovieMethod(self.sfHandle, "SET_TEXTURE")
            ScaleformMovieMethodAddParamTextureNameString(self.txdName)
            ScaleformMovieMethodAddParamTextureNameString(self.txnName)
            ScaleformMovieMethodAddParamInt(0)
            ScaleformMovieMethodAddParamInt(0)
            ScaleformMovieMethodAddParamInt(math.floor(self.w))
            ScaleformMovieMethodAddParamInt(math.floor(self.h))
            EndScaleformMovieMethod()
        end

        local pos = self.scaleform and (self.scaleform.finalPosition or self.scaleform.position) or nil
        local rot = self.scaleform and (self.scaleform.finalRotation or self.scaleform.rotation) or nil
        local scl = self.scaleform and self.scaleform.scale or vector3(1.0, 1.0, 1.0)

        if pos and rot and scl then
            DrawScaleformMovie_3dSolid(self.sfHandle, pos, rot, 2.0, 2.0, 1.0, scl, 2)
        end
    end
end

function DuiBrowser:sendMessage(data)
    if self.duiObject then
        SendDuiMessage(self.duiObject, json.encode(data))
    end
end

function DuiBrowser:destroy()
    DuiBrowser.initQueue[self.mediaPlayerHandle] = nil
    self:disableRenderTarget()
    self:disableScaleform()
    DuiBrowser.pool[self.mediaPlayerHandle] = nil
    self.renderActive = false
    if self.duiObject then
        DestroyDui(self.duiObject)
        self.duiObject = nil
    end
end

Citizen.CreateThread(function()
    local nextRenderAt = 0

    while true do
        local wait = 500
        if next(DuiBrowser.pool) then
            local now = GetGameTimer()
            local renderable = {}
            for _, browser in pairs(DuiBrowser.pool) do
                if browser:shouldRender() then
                    renderable[#renderable + 1] = browser
                end
            end

            duiRenderStats.total = countDuiBrowsers()
            duiRenderStats.renderable = #renderable
            duiRenderStats.lastTickAt = now

            local fps = #renderable > 0
                and getConfiguredDuiFps("renderMaxFps", 30, 5, 30)
                or getConfiguredDuiFps("renderIdleFps", 5, 1, 15)
            local interval = math.floor(1000 / fps)
            local drawEveryFrame = #renderable > 0 and fps >= 55

            if #renderable > 0 and (drawEveryFrame or now >= nextRenderAt) then
                local frameStart = GetGameTimer()
                for _, browser in ipairs(renderable) do
                    browser:renderFrame(true)
                end
                duiRenderStats.rendered = #renderable
                duiRenderStats.lastFrameMs = GetGameTimer() - frameStart
                nextRenderAt = drawEveryFrame and now or (now + interval)
                wait = drawEveryFrame and 0 or interval
            else
                duiRenderStats.rendered = 0
                wait = math.max(0, math.min(250, nextRenderAt - now))
                if #renderable <= 0 then
                    wait = interval
                    nextRenderAt = now + interval
                end
            end
        end
        Citizen.Wait(wait)
    end
end)

RegisterNUICallback("DuiBrowser:initDone", function(data, cb)
    if DuiBrowser.initQueue[data.handle] then
        DuiBrowser.initQueue[data.handle].initDone = true
    end
    PMMSDebug("dui", "DUI browser init completed", {
        handle = data and data.handle or nil,
    })
    cb({})
end)

RegisterNUICallback("duiStartup", function(data, cb)
    PMMSDebug("dui", "DUI startup config requested", {
        handle = data and data.handle or nil,
    })
    cb({
        audioVisualizations = Config.audioVisualizations or {},
        currentServerEndpoint = GetCurrentServerEndpoint(),
        defaultTransitionSeconds = tonumber(Config.defaultTransitionSeconds) or 5.0,
        maxTransitionSeconds = tonumber(Config.maxTransitionSeconds) or 15.0,
        rangeCurveExponent = tonumber(Config.rangeCurveExponent) or 1.6,
        startupTimeoutMs = math.max(8000, math.min(30000, tonumber(Config.dui.timeout) or 30000)),
        hlsCanvasDownscale = Config.dui.hlsCanvasDownscale ~= false,
        hlsCanvasMaxWidth = math.max(320, tonumber(Config.dui.hlsCanvasMaxWidth) or 1920),
        hlsCanvasMaxHeight = math.max(180, tonumber(Config.dui.hlsCanvasMaxHeight) or 1080),
        hlsCanvasMaxFps = math.max(1, math.min(60, tonumber(Config.dui.hlsCanvasMaxFps) or 30)),
        audioLanguagePriority = Config.resolver and Config.resolver.audioLanguagePriority or { "original", "en", "en-US", "und" },
        player = Config.player or {},
        youtube = Config.dui and Config.dui.youtube or nil,
        debug = Config.debug,
    })
end)

RegisterNUICallback("pmmsDuiStartupReady", function(data, cb)
    PMMSDebug("dui", "DUI startup ready callback", {
        handle = data and data.handle or nil,
        attemptId = data and data.attemptId or nil,
        playbackToken = data and data.playbackToken or nil,
        title = data and data.metadata and data.metadata.title or nil,
        duration = data and data.metadata and data.metadata.duration or nil,
    })
    if data and data.handle and data.attemptId then
        TriggerServerEvent("pmms:startupReady", data.handle, data.attemptId, data.metadata or {}, data.playbackToken)
    end
    cb({})
end)

RegisterNUICallback("pmmsDuiMetadata", function(data, cb)
    PMMSDebug("dui", "DUI playback metadata callback", {
        handle = data and data.handle or nil,
        playbackToken = data and data.playbackToken or nil,
        duration = data and data.metadata and data.metadata.duration or nil,
        live = data and data.metadata and data.metadata.live or nil,
        audioTrackCount = data and data.metadata and data.metadata.audioTracks and #data.metadata.audioTracks or nil,
    })
    if data and data.handle and data.metadata then
        TriggerServerEvent("pmms:updatePlaybackMetadata", data.handle, data.metadata or {}, data.playbackToken)
    end
    cb({})
end)

RegisterNUICallback("pmmsDuiEnded", function(data, cb)
    PMMSDebug("dui", "DUI playback ended callback", {
        handle = data and data.handle or nil,
        playbackToken = data and data.playbackToken or nil,
        duration = data and data.metadata and data.metadata.duration or nil,
        currentTime = data and data.metadata and data.metadata.currentTime or nil,
    })
    if data and data.handle then
        TriggerServerEvent("pmms:ended", data.handle, data.metadata or {}, data.playbackToken)
    end
    cb({})
end)

RegisterNUICallback("pmmsDuiStartupError", function(data, cb)
    if data and data.handle and data.attemptId then
        local handled = HandleLocalMediaPlayerError(data.handle, data.attemptId, data.message, data.url, data.playbackToken)
        PMMSDebug("dui", "DUI startup error callback", {
            handle = data and data.handle or nil,
            attemptId = data and data.attemptId or nil,
            playbackToken = data and data.playbackToken or nil,
            url = redactUrlForDebug(data and data.url or nil),
            message = data and data.message or nil,
            handled = handled,
        })
        if handled ~= false then
            printDuiWarning(
                "startup_error:" .. tostring(data and data.handle or "?") .. ":" .. tostring(data and data.message or "?"),
                "^1[7-pmms] DUI Startup Error for handle " .. tostring(data and data.handle or "?") .. ": " .. tostring(data and data.message or "?") .. "^7",
                10000
            )
            TriggerServerEvent("pmms:startupError", data.handle, data.attemptId, data.url, data.message, data.playbackToken)
        end
    end
    cb({})
end)

RegisterNUICallback("pmmsDuiLocalError", function(data, cb)
    if data and data.handle then
        local handled = HandleLocalMediaPlayerError(data.handle, nil, data.message, data.url, data.playbackToken)
        PMMSDebug("dui", "DUI local playback error callback", {
            handle = data and data.handle or nil,
            playbackToken = data and data.playbackToken or nil,
            url = redactUrlForDebug(data and data.url or nil),
            message = data and data.message or nil,
            handled = handled,
        })
        if handled ~= false then
            printDuiWarning(
                "local_error:" .. tostring(data.handle) .. ":" .. tostring(data.message or "?"),
                "^1[7-pmms] DUI Local Playback Error for handle " .. tostring(data.handle) .. ": " .. tostring(data.message or "?") .. "^7",
                10000
            )
            TriggerServerEvent("pmms:localPlaybackError", data.handle, data.url, data.message, data.playbackToken)
        end
    end
    cb({})
end)
