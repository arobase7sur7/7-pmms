local mediaPlayers = {}
local restrictedHandles = {}
local restrictedTimestamps = {}
local syncQueue = {}
local dirty = false

function GetMediaPlayers()
    return mediaPlayers
end

function SetMediaPlayers(players)
    mediaPlayers = players
end

function GetMediaPlayer(handle)
    return mediaPlayers[handle]
end

function SetMediaPlayer(handle, data)
    mediaPlayers[handle] = data
    dirty = true
end

function RemoveMediaPlayerEntry(handle)
    mediaPlayers[handle] = nil
    dirty = true
end

function IsMediaPlayerActive(handle)
    return mediaPlayers[handle] ~= nil
end

function GetRestrictedHandles()
    return restrictedHandles
end

function SetRestricted(handle, src)
    restrictedHandles[handle] = src
    restrictedTimestamps[handle] = os.time()
end

function ClearRestricted(handle)
    restrictedHandles[handle] = nil
    restrictedTimestamps[handle] = nil
end

function EnqueueSync(cb)
    syncQueue[#syncQueue + 1] = cb
    dirty = true
end

function MarkDirty()
    dirty = true
end

local function cleanupRestrictedHandles()
    local now = os.time()
    for handle, timestamp in pairs(restrictedTimestamps) do
        if now - timestamp > 10 then
            restrictedHandles[handle] = nil
            restrictedTimestamps[handle] = nil
        end
    end
end

AddEventHandler("playerDropped", function()
    local src = source
    for handle, restrictedSrc in pairs(restrictedHandles) do
        if restrictedSrc == src then
            restrictedHandles[handle] = nil
            restrictedTimestamps[handle] = nil
        end
    end
end)

local lastBroadcast = 0

local function resolveLoopMode(info)
    if type(NormalizeLoopMode) == "function" then
        return NormalizeLoopMode(info and info.loopMode, info and info.loop)
    end

    if info and info.loop then
        return "track"
    end

    return "off"
end

local function syncMediaPlayers()
    local now = os.time()
    for handle, info in pairs(mediaPlayers) do
        if not info.paused then
            info.offset = math.max(0, now - (info.startTime or now))

            if info.duration and info.duration > 0 and info.offset >= info.duration then
                local loopMode = resolveLoopMode(info)
                local shouldAdvanceQueue = (info.queue and #info.queue > 0)
                    or loopMode == "queue"
                    or loopMode == "shuffle_loop"

                if loopMode == "track" then
                    info.offset = 0
                    info.startTime = now
                    dirty = true
                elseif shouldAdvanceQueue then
                    PlayNextInQueue(handle, { reason = "ended" })
                else
                    RemoveMediaPlayer(handle)
                end
            end
        end
    end

    if CleanupPendingStarts then
        CleanupPendingStarts(now)
    end
    if CleanupDeviceSessions then
        CleanupDeviceSessions(now)
    end
    if CleanupSessionLocks then
        CleanupSessionLocks(now)
    end

    cleanupRestrictedHandles()

    while #syncQueue > 0 do
        local cb = table.remove(syncQueue, 1)
        if cb then cb() end
    end

    if dirty or (now - lastBroadcast > 10) then
        local players = GetPlayers()
        for _, playerId in ipairs(players) do
            local target = tonumber(playerId) or playerId
            local payload = mediaPlayers
            if type(BuildMediaPlayersSyncStateForPlayer) == "function" then
                payload = BuildMediaPlayersSyncStateForPlayer(target)
            end
            TriggerClientEvent("pmms:sync", target, payload)
        end
        dirty = false
        lastBroadcast = now
    end
end

local thisResource = GetCurrentResourceName()

local contentTypes = {
    html = "text/html",
    css  = "text/css",
    js   = "application/javascript",
    mjs  = "application/javascript",
    json = "application/json",
    svg  = "image/svg+xml",
    png  = "image/png",
    jpg  = "image/jpeg",
    jpeg = "image/jpeg",
    gif  = "image/gif",
    ico  = "image/x-icon",
    webp = "image/webp",
    txt  = "text/plain",
}

local function getContentType(path)
    path = tostring(path or ""):gsub("[?#].*$", "")
    local ext = path:match("%.(%w+)$")
    return contentTypes[ext] or "application/octet-stream"
end

SetHttpHandler(function(req, res)
    local path = req.path or "/"
    path = path:gsub("[?#].*$", "")
    if path == "" then
        path = "/"
    end

    if path:find("..", 1, true) then
        res.writeHead(403, { ["Content-Type"] = "text/plain" })
        res.send("Forbidden")
        return
    end

    local filePath = nil
    local isDuiRequest = false

    local duiRuntimeOverrides = {
        ["index.html"] = "http/dui_runtime/index.html",
        ["style.css"] = "http/dui_runtime/style.css",
        ["script.js"] = "http/dui_runtime/script.js",
        ["hls.min.js"] = "http/dui_runtime/hls.min.js",
    }

    if path == "/dui" or path == "/dui/" then
        filePath = duiRuntimeOverrides["index.html"]
        isDuiRequest = true
    elseif path:sub(1, 5) == "/dui/" then
        local relativePath = path:sub(6)
        if relativePath == "" then
            relativePath = "index.html"
        end
        filePath = duiRuntimeOverrides[relativePath] or ("http/dui_runtime/" .. relativePath)
        isDuiRequest = true
    elseif path:sub(1, 7) == "/media/" then
        local relativePath = path:sub(8)
        if relativePath ~= "" then
            filePath = "http/media/" .. relativePath
        end
    end

    if not filePath then
        res.writeHead(404, { ["Content-Type"] = "text/plain" })
        res.send("Not Found")
        return
    end

    local content = LoadResourceFile(thisResource, filePath)

    if content then
        local headers = { ["Content-Type"] = getContentType(filePath) }
        if isDuiRequest then
            if Config.dui and Config.dui.cacheRuntimeAssets == false then
                headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
                headers["Pragma"] = "no-cache"
                headers["Expires"] = "0"
            else
                headers["Cache-Control"] = "public, max-age=3600"
            end
        end
        res.writeHead(200, headers)
        res.send(content)
    else
        res.writeHead(404, { ["Content-Type"] = "text/plain" })
        res.send("Not Found")
    end
end)

Citizen.CreateThread(function()
    LoadPersistedSettings(function()
        StartDefaultMediaPlayers()
    end)

    while true do
        Citizen.Wait(250)
        syncMediaPlayers()
    end
end)
