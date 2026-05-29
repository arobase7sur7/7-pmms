local mediaPlayers = {}
local restrictedHandles = {}
local restrictedTimestamps = {}
local syncQueue = {}
local dirty = false
local pendingSyncTargets = {}
local syncAllRequested = false
local fullSyncAllRequested = false
local lastBroadcast = 0
local lastFullBroadcast = 0
local syncStateByTarget = {}

local SYNC_THROTTLE_MS = 1000
local PERIODIC_FULL_SYNC_MS = 10000
local LARGE_SYNC_THRESHOLD_BYTES = 800
local NORMAL_SYNC_BPS = 131072
local FULL_SYNC_BPS = 524288

local function cloneDeepTable(source, seen)
    if type(source) ~= "table" then
        return source
    end

    seen = seen or {}
    if seen[source] then
        return seen[source]
    end

    local copy = {}
    seen[source] = copy

    for key, value in pairs(source) do
        copy[cloneDeepTable(key, seen)] = cloneDeepTable(value, seen)
    end

    return copy
end

local function deepEqual(left, right, seen)
    if left == right then
        return true
    end

    if type(left) ~= type(right) then
        return false
    end

    if type(left) ~= "table" then
        return false
    end

    seen = seen or {}
    if seen[left] == right then
        return true
    end
    seen[left] = right

    for key, value in pairs(left) do
        if not deepEqual(value, right[key], seen) then
            return false
        end
    end

    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end

    return true
end

local function cloneMediaPlayerForDiff(info)
    local copy = cloneDeepTable(info)
    if type(copy) == "table" and copy.paused ~= true then
        copy.offset = nil
    end
    return copy
end

local function syncValueEqual(section, current, previous)
    if section == "mediaPlayers" then
        return deepEqual(cloneMediaPlayerForDiff(current), cloneMediaPlayerForDiff(previous))
    end
    return deepEqual(current, previous)
end

local function normalizeSyncTarget(target)
    if target == nil then
        return nil
    end
    return tonumber(target) or target
end

local function getSyncTargetKey(target)
    local resolved = normalizeSyncTarget(target)
    return resolved ~= nil and tostring(resolved) or nil
end

local function queueSyncTarget(target, full)
    local resolved = normalizeSyncTarget(target)
    local key = getSyncTargetKey(resolved)
    if not key then
        return
    end

    local pending = pendingSyncTargets[key]
    pendingSyncTargets[key] = {
        target = resolved,
        full = full == true or (pending and pending.full == true) or false,
    }
end

local function hasPendingSyncTargets()
    for _ in pairs(pendingSyncTargets) do
        return true
    end
    return false
end

local function getPayloadSize(payload)
    local ok, encoded = pcall(json.encode, payload)
    if ok and type(encoded) == "string" then
        return #encoded
    end
    return LARGE_SYNC_THRESHOLD_BYTES + 1
end

local function triggerSizedClientEvent(eventName, target, payload, latentBps)
    if getPayloadSize(payload) > LARGE_SYNC_THRESHOLD_BYTES then
        TriggerLatentClientEvent(eventName, target, latentBps, payload)
    else
        TriggerClientEvent(eventName, target, payload)
    end
end

local function buildSyncPayloadForTarget(target)
    if type(BuildMediaPlayersSyncStateForPlayer) == "function" then
        return BuildMediaPlayersSyncStateForPlayer(target)
    end
    return cloneDeepTable(mediaPlayers)
end

local function getEstimatedOneWayLatencyMs(target)
    if type(GetPlayerPing) ~= "function" then
        return 0
    end

    local ping = tonumber(GetPlayerPing(target)) or 0
    if ping < 0 then
        ping = 0
    end
    if ping > 5000 then
        ping = 5000
    end

    return math.floor(ping / 2)
end

local function stampSyncPayload(payload, target)
    if type(payload) ~= "table" then
        return payload
    end

    payload._sentAt = GetGameTimer()
    payload._latencyMs = getEstimatedOneWayLatencyMs(target)
    return payload
end

local function buildSectionDelta(section, current, previous)
    local updates = {}
    local removed = {}
    local changed = false

    current = type(current) == "table" and current or {}
    previous = type(previous) == "table" and previous or {}

    for key, value in pairs(current) do
        if previous[key] == nil or not syncValueEqual(section, value, previous[key]) then
            updates[key] = value
            changed = true
        end
    end

    for key in pairs(previous) do
        if current[key] == nil then
            removed[#removed + 1] = key
            changed = true
        end
    end

    return updates, removed, changed
end

local function buildSyncDelta(current, previous)
    if type(current) ~= "table" or type(previous) ~= "table" or current.mediaPlayers == nil then
        return nil, false
    end

    local delta = {
        removed = {},
    }
    local hasChanges = false

    for _, section in ipairs({ "mediaPlayers", "startupStates", "deviceSessions" }) do
        local updates, removed, changed = buildSectionDelta(section, current[section], previous[section])
        if changed then
            if next(updates) ~= nil then
                delta[section] = updates
            end
            if #removed > 0 then
                delta.removed[section] = removed
            end
            hasChanges = true
        end
    end

    if not deepEqual(current.admin, previous.admin) then
        if current.admin == nil then
            delta.adminRemoved = true
        else
            delta.admin = current.admin
        end
        hasChanges = true
    end

    if next(delta.removed) == nil then
        delta.removed = nil
    end

    return delta, hasChanges
end

local function sendSyncToTarget(target, full)
    local resolved = normalizeSyncTarget(target)
    local key = getSyncTargetKey(resolved)
    if not key then
        return false
    end

    local payload = stampSyncPayload(buildSyncPayloadForTarget(resolved), resolved)
    local previous = syncStateByTarget[key]
    local shouldSendFull = full == true or previous == nil or type(payload) ~= "table" or payload.mediaPlayers == nil

    if shouldSendFull then
        triggerSizedClientEvent("pmms:sync", resolved, payload, FULL_SYNC_BPS)
        syncStateByTarget[key] = cloneDeepTable(payload)
        return true
    end

    local delta, hasChanges = buildSyncDelta(payload, previous)
    if hasChanges then
        delta._sentAt = payload._sentAt
        delta._latencyMs = payload._latencyMs
        triggerSizedClientEvent("pmms:syncDelta", resolved, delta, NORMAL_SYNC_BPS)
        syncStateByTarget[key] = cloneDeepTable(payload)
        return true
    end

    return false
end

function RequestPmmsSync(target, options)
    options = type(options) == "table" and options or {}
    dirty = true

    if target ~= nil then
        queueSyncTarget(target, options.full == true)
        return
    end

    syncAllRequested = true
    if options.full == true then
        fullSyncAllRequested = true
    end
end

function SendPmmsFullSync(target)
    return sendSyncToTarget(target, true)
end

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
    local key = getSyncTargetKey(src)
    if key then
        syncStateByTarget[key] = nil
        pendingSyncTargets[key] = nil
    end

    for handle, restrictedSrc in pairs(restrictedHandles) do
        if restrictedSrc == src then
            restrictedHandles[handle] = nil
            restrictedTimestamps[handle] = nil
        end
    end
end)

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
    local nowMs = GetGameTimer()
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

    local fullSyncDue = (nowMs - lastFullBroadcast) >= PERIODIC_FULL_SYNC_MS
    local shouldFlush = fullSyncDue
        or fullSyncAllRequested
        or (dirty and (nowMs - lastBroadcast) >= SYNC_THROTTLE_MS)
        or (hasPendingSyncTargets() and (nowMs - lastBroadcast) >= SYNC_THROTTLE_MS)

    if shouldFlush then
        local players = GetPlayers()
        local sendFull = fullSyncDue or fullSyncAllRequested

        if dirty or syncAllRequested or sendFull then
            for _, playerId in ipairs(players) do
                local target = tonumber(playerId) or playerId
                sendSyncToTarget(target, sendFull)
            end
        end

        for key, pending in pairs(pendingSyncTargets) do
            if pending and pending.target ~= nil then
                sendSyncToTarget(pending.target, pending.full == true or sendFull)
            end
            pendingSyncTargets[key] = nil
        end

        syncAllRequested = false
        fullSyncAllRequested = false
        dirty = false
        lastBroadcast = nowMs
        if sendFull then
            lastFullBroadcast = nowMs
        end
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

local function normalizeHttpHost(url)
    if type(url) ~= "string" then
        return nil
    end

    local host = url:match("^https://([^/%?#]+)")
    if not host or host:find("@", 1, true) then
        return nil
    end

    host = host:lower():gsub(":%d+$", "")
    if host == "" or host:find("[%c%s]") then
        return nil
    end
    return host
end

local function hostMatchesSuffix(host, suffix)
    if host == suffix then
        return true
    end
    return host:sub(-#suffix - 1) == "." .. suffix
end

local function collectConfiguredThumbnailHosts()
    local hosts = {
        ["i.ytimg.com"] = true,
        ["img.youtube.com"] = true,
        ["static-cdn.jtvnw.net"] = true,
    }
    local instances = type(Config.resolver) == "table" and Config.resolver.instances or {}

    local function addHost(url)
        local host = normalizeHttpHost(url)
        if not host then
            return
        end
        hosts[host] = true
        if host:sub(1, 4) == "api." then
            hosts[host:sub(5)] = true
        end
    end

    if type(instances) == "table" then
        for _, url in ipairs(instances.invidious or {}) do
            addHost(url)
        end
        for _, url in ipairs(instances.piped or {}) do
            addHost(url)
        end
    end

    return hosts
end

local function isAllowedThumbnailHost(host)
    if type(host) ~= "string" or host == "" then
        return false
    end

    if hostMatchesSuffix(host, "ytimg.com") or host == "img.youtube.com" then
        return true
    end

    if host == "static-cdn.jtvnw.net" then
        return true
    end

    local hosts = collectConfiguredThumbnailHosts()
    for allowedHost in pairs(hosts) do
        if host == allowedHost or hostMatchesSuffix(host, allowedHost) then
            return true
        end
    end

    return false
end

local thumbnailProxyLogThrottle = {}

local function logThumbnailProxyFailure(reason, data)
    local now = os.time()
    local key = tostring(reason or "unknown") .. ":" .. tostring(data and data.host or "")
    if thumbnailProxyLogThrottle[key] and thumbnailProxyLogThrottle[key] > now then
        return
    end
    thumbnailProxyLogThrottle[key] = now + 30
    PMMSDebug("search", "thumbnail proxy failed", {
        reason = reason,
        host = data and data.host or nil,
        statusCode = data and data.statusCode or nil,
        contentType = data and data.contentType or nil,
        size = data and data.size or nil,
    })
end

local function getHeaderValue(headers, name)
    if type(headers) ~= "table" then
        return nil
    end

    local needle = name:lower()
    for key, value in pairs(headers) do
        if type(key) == "string" and key:lower() == needle then
            if type(value) == "table" then
                return value[1]
            end
            return value
        end
    end

    return nil
end

local function sendThumbnailProxy(reqPath, res)
    local searchConfig = type(Config.search) == "table" and Config.search or {}
    if searchConfig.proxyThumbnails == false then
        res.writeHead(404, { ["Content-Type"] = "text/plain" })
        res.send("Not Found")
        return
    end

    local encoded = reqPath:sub(8)
    if encoded == "" or not encoded:match("^[A-Za-z0-9_%-=]+$") then
        logThumbnailProxyFailure("invalid_encoded_url")
        res.writeHead(400, { ["Content-Type"] = "text/plain" })
        res.send("Invalid thumbnail URL.")
        return
    end

    local url = type(Base64Decode) == "function" and Base64Decode(encoded) or nil
    if type(url) ~= "string"
        or not url:match("^https://")
        or url:find("[%c<>\"'`]", 1, false)
        or url:find("^https://[^/]-@", 1, false) then
        logThumbnailProxyFailure("invalid_url")
        res.writeHead(400, { ["Content-Type"] = "text/plain" })
        res.send("Invalid thumbnail URL.")
        return
    end

    local host = normalizeHttpHost(url)
    if not isAllowedThumbnailHost(host) then
        logThumbnailProxyFailure("host_not_allowed", { host = host })
        res.writeHead(403, { ["Content-Type"] = "text/plain" })
        res.send("Thumbnail host is not allowed.")
        return
    end

    local timeoutMs = math.max(500, tonumber(searchConfig.thumbnailProxyTimeoutMs) or 1500)
    local maxBytes = 512 * 1024
    PerformHttpRequest(url, function(statusCode, body, headers)
        if statusCode ~= 200 or type(body) ~= "string" or body == "" then
            logThumbnailProxyFailure("fetch_failed", {
                host = host,
                statusCode = statusCode,
                size = type(body) == "string" and #body or 0,
            })
            res.writeHead(502, { ["Content-Type"] = "text/plain" })
            res.send("Thumbnail fetch failed.")
            return
        end

        if #body > maxBytes then
            logThumbnailProxyFailure("too_large", { host = host, size = #body })
            res.writeHead(413, { ["Content-Type"] = "text/plain" })
            res.send("Thumbnail is too large.")
            return
        end

        local contentType = getHeaderValue(headers, "content-type") or ""
        contentType = tostring(contentType):match("^%s*([^;]+)") or ""
        contentType = contentType:lower()
        if not contentType:match("^image/") then
            logThumbnailProxyFailure("invalid_content_type", {
                host = host,
                contentType = contentType,
                size = #body,
            })
            res.writeHead(415, { ["Content-Type"] = "text/plain" })
            res.send("Thumbnail response is not an image.")
            return
        end

        res.writeHead(200, {
            ["Content-Type"] = contentType,
            ["Cache-Control"] = "public, max-age=86400",
            ["Access-Control-Allow-Origin"] = "*",
        })
        res.send(body)
    end, "GET", "", {
        ["User-Agent"] = "7-PMMS-ThumbnailProxy",
        ["Accept"] = "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
    }, {
        timeout = math.floor(timeoutMs),
    })
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

    if path:sub(1, 7) == "/thumb/" then
        sendThumbnailProxy(path, res)
        return
    elseif path == "/dui" or path == "/dui/" then
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
