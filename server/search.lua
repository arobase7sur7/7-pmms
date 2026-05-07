local cachedInvidiousInstances = {}
local cachedPipedInstances = {}
local instanceCacheExpiry = 0
local instanceCacheTtl = 1800
local instanceDiscoveryInFlight = false
local searchCooldowns = {}
local maxQueryLength = 200
local searchCacheTtl = 20
local searchResultCache = {}
local searchInflight = {}
local builtinSearchInstances = {
    invidious = {
        "https://inv.nadeko.net",
        "https://yewtu.be",
        "https://invidious.nerdvpn.de",
        "https://inv.us.projectsegfau.lt",
        "https://invidious.fdn.fr",
        "https://iv.ggtyler.dev",
    },
    piped = {
        "https://api.piped.private.coffee",
        "https://pipedapi.kavin.rocks",
        "https://api-piped.mha.fi",
        "https://pipedapi.adminforge.de",
        "https://piped-api.hostux.net",
        "https://pipedapi.qdi.fi",
    },
}

function EncodeUrlString(str)
    if str then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w %-%_%.%~])", function(char)
            return string.format("%%%02X", string.byte(char))
        end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

local function copyList(values)
    local copy = {}
    for index, value in ipairs(values or {}) do
        copy[index] = value
    end
    return copy
end

local function appendUniqueUrl(target, seen, value)
    if type(value) ~= "string" or value == "" then
        return
    end

    local normalized = value:gsub("/$", "")
    if seen[normalized] then
        return
    end

    seen[normalized] = true
    target[#target + 1] = normalized
end

local function collectConfiguredInstances()
    local configured = type(Config.resolver) == "table" and Config.resolver.instances or {}
    local combinedInvidious = {}
    local combinedPiped = {}
    local seen = {}

    local function appendUnique(target, values)
        for _, value in ipairs(values or {}) do
            appendUniqueUrl(target, seen, value)
        end
    end

    appendUnique(combinedInvidious, builtinSearchInstances.invidious)
    appendUnique(combinedInvidious, type(configured) == "table" and configured.invidious or {})

    seen = {}
    appendUnique(combinedPiped, builtinSearchInstances.piped)
    appendUnique(combinedPiped, type(configured) == "table" and configured.piped or {})

    return combinedInvidious, combinedPiped
end

local function performDiscoveryGet(url, callback)
    local resolverConfig = type(Config.resolver) == "table" and Config.resolver or {}
    local timeoutMs = math.max(2000, tonumber(resolverConfig.timeoutMs) or 6000)
    PerformHttpRequest(url, function(status, body)
        callback(status, body)
    end, "GET", "", {
        ["User-Agent"] = "7-PMMS-Server",
    }, {
        timeout = math.floor(timeoutMs),
    })
end

local function trimText(value)
    if type(value) ~= "string" then
        return nil
    end

    local trimmed = value:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end

    return trimmed
end

local function normalizeRemoteAssetUrl(url)
    local trimmed = trimText(url)
    if not trimmed then
        return nil
    end

    if trimmed:sub(1, 2) == "//" then
        return "https:" .. trimmed
    end

    if trimmed:match("^http://") then
        return "https://" .. trimmed:sub(8)
    end

    if trimmed:match("^https://") then
        return trimmed
    end

    return nil
end

local function shuffleTable(values)
    for index = #values, 2, -1 do
        local swapIndex = math.random(index)
        values[index], values[swapIndex] = values[swapIndex], values[index]
    end
    return values
end

local function discoverInstances(callback)
    local now = os.time()
    if now < instanceCacheExpiry and (#cachedInvidiousInstances > 0 or #cachedPipedInstances > 0) then
        callback(cachedInvidiousInstances, cachedPipedInstances)
        return
    end

    local configuredInvidious, configuredPiped = collectConfiguredInstances()
    local nextInvidious = #cachedInvidiousInstances > 0 and copyList(cachedInvidiousInstances) or copyList(configuredInvidious)
    local nextPiped = #cachedPipedInstances > 0 and copyList(cachedPipedInstances) or copyList(configuredPiped)
    callback(nextInvidious, nextPiped)

    if instanceDiscoveryInFlight then
        return
    end

    instanceDiscoveryInFlight = true
    nextInvidious = copyList(configuredInvidious)
    nextPiped = copyList(configuredPiped)
    local seenInvidious = {}
    local seenPiped = {}
    for _, url in ipairs(nextInvidious) do
        seenInvidious[url] = true
    end
    for _, url in ipairs(nextPiped) do
        seenPiped[url] = true
    end
    local pending = 2
    local finished = false

    local function finalize()
        if finished then
            return
        end

        finished = true
        instanceDiscoveryInFlight = false

        if #nextInvidious > 0 then
            shuffleTable(nextInvidious)
            cachedInvidiousInstances = nextInvidious
        end
        if #nextPiped > 0 then
            shuffleTable(nextPiped)
            cachedPipedInstances = nextPiped
        end

        instanceCacheExpiry = os.time() + instanceCacheTtl
    end

    local function finishOne()
        pending = pending - 1
        if pending <= 0 then
            finalize()
        end
    end

    SetTimeout(math.max(2500, math.max(2000, tonumber((Config.resolver or {}).timeoutMs) or 6000) + 500), function()
        finalize()
    end)

    performDiscoveryGet("https://api.invidious.io/instances.json", function(status, body)
        if not finished and status == 200 and body then
            local ok, data = pcall(json.decode, body)
            if ok and type(data) == "table" then
                for _, entry in ipairs(data) do
                    local info = type(entry) == "table" and entry[2] or nil
                    if type(info) == "table" and info.api and info.type == "https" and info.uri then
                        appendUniqueUrl(nextInvidious, seenInvidious, info.uri)
                    end
                end
            end
        end

        finishOne()
    end)

    performDiscoveryGet("https://piped-instances.kavin.rocks/", function(status, body)
        if not finished and status == 200 and body then
            local ok, data = pcall(json.decode, body)
            if ok and type(data) == "table" then
                for _, instance in ipairs(data) do
                    if type(instance) == "table" and instance.api_url then
                        appendUniqueUrl(nextPiped, seenPiped, instance.api_url)
                    end
                end
            end
        end

        finishOne()
    end)
end

local function searchInvidious(query, maxResults, instances, index, callback)
    index = index or 1
    if index > #instances or index > 5 then
        callback(false, nil)
        return
    end

    local apiUrl = instances[index] .. "/api/v1/search?q=" .. EncodeUrlString(query) .. "&type=video"
    performDiscoveryGet(apiUrl, function(statusCode, response)
        if statusCode == 200 and response then
            local ok, data = pcall(json.decode, response)
            if ok and type(data) == "table" and #data > 0 then
                local results = {}
                for _, item in ipairs(data) do
                    if item.type == "video" and #results < maxResults then
                        results[#results + 1] = {
                            title = item.title,
                            videoId = item.videoId,
                            url = "https://www.youtube.com/watch?v=" .. item.videoId,
                            duration = item.lengthSeconds,
                            author = item.author,
                            thumbnail = normalizeRemoteAssetUrl(item.videoThumbnails and item.videoThumbnails[1] and item.videoThumbnails[1].url or nil),
                            source = "youtube",
                        }
                    end
                end

                if #results > 0 then
                    callback(true, results)
                    return
                end
            end
        end

        searchInvidious(query, maxResults, instances, index + 1, callback)
    end)
end

local function searchPiped(query, maxResults, instances, index, callback)
    index = index or 1
    if index > #instances or index > 5 then
        callback(false, nil)
        return
    end

    local apiUrl = instances[index] .. "/search?q=" .. EncodeUrlString(query) .. "&filter=videos"
    performDiscoveryGet(apiUrl, function(statusCode, response)
        if statusCode == 200 and response then
            local ok, data = pcall(json.decode, response)
            if ok and data then
                local items = data.items or data
                if type(items) == "table" and #items > 0 then
                    local results = {}
                    for _, item in ipairs(items) do
                        if #results >= maxResults then
                            break
                        end

                        local videoUrl = item.url or ""
                        if videoUrl:sub(1, 1) == "/" then
                            videoUrl = "https://www.youtube.com" .. videoUrl
                        end

                        results[#results + 1] = {
                            title = item.title or "Untitled",
                            url = videoUrl,
                            duration = item.duration or 0,
                            author = item.uploaderName or item.uploader or "Unknown",
                            thumbnail = normalizeRemoteAssetUrl(item.thumbnail),
                            source = "youtube",
                        }
                    end

                    if #results > 0 then
                        callback(true, results)
                        return
                    end
                end
            end
        end

        searchPiped(query, maxResults, instances, index + 1, callback)
    end)
end

local function searchYoutube(query, maxResults, callback)
    discoverInstances(function(invidiousInstances, pipedInstances)
        if #invidiousInstances == 0 and #pipedInstances == 0 then
            callback(false, "No search instances available. Try again later.")
            return
        end

        local finished = false
        local pending = 0
        local lastMessage = "No results found. Try a different query."

        local function complete(success, payload)
            if finished then
                return
            end

            if success then
                finished = true
                callback(true, payload)
                return
            end

            lastMessage = payload or lastMessage
            pending = pending - 1
            if pending <= 0 then
                callback(false, lastMessage)
            end
        end

        if #invidiousInstances > 0 then
            pending = pending + 1
            searchInvidious(query, maxResults, invidiousInstances, 1, complete)
        end

        if #pipedInstances > 0 then
            pending = pending + 1
            searchPiped(query, maxResults, pipedInstances, 1, complete)
        end
    end)
end

function SearchMedia(query, searchSource, maxResults, callback)
    if searchSource == "twitch" then
        callback(true, {
            {
                title = query .. " (Twitch Stream)",
                url = "https://www.twitch.tv/" .. query:gsub(" ", ""),
                duration = 0,
                author = query,
                thumbnail = "https://static-cdn.jtvnw.net/ttv-boxart/Twitch.jpg",
                source = "twitch",
            },
        })
        return
    end

    if searchSource == "soundcloud" then
        searchYoutube(query .. " soundcloud", maxResults, function(success, results)
            if success and type(results) == "table" then
                for _, row in ipairs(results) do
                    row.source = "soundcloud"
                end
            end
            callback(success, results)
        end)
        return
    end

    searchYoutube(query, maxResults, callback)
end

local function buildSearchCacheKey(sourceName, query, maxResults)
    return ("%s|%s|%d"):format(
        tostring(sourceName or "youtube"):lower(),
        tostring(query or ""):lower(),
        tonumber(maxResults) or 10
    )
end

local function emitSearchResults(src, requestId, results)
    TriggerClientEvent("pmms:searchResults", src, {
        requestId = requestId,
        results = results or {},
    })
end

local function emitSearchError(src, requestId, message, state, retryAfterMs, cooldownUntil)
    TriggerClientEvent("pmms:searchError", src, {
        requestId = requestId,
        message = message or "Search failed.",
        state = state,
        retryAfterMs = retryAfterMs,
        cooldownUntil = cooldownUntil,
    })
end

exports('SearchYouTube', function(query, callback)
    searchYoutube(query, 10, callback)
end)
exports('SearchMedia', SearchMedia)

RegisterNetEvent("pmms:clientSearch", function(data)
    local src = source
    if type(data) ~= "table" then
        return
    end

    local query = trimText(data.query)
    local searchSource = data.source or "youtube"
    local requestId = data.requestId
    local sourceConfig = Config.searchSources[searchSource] or Config.searchSources["youtube"]
    local maxResults = sourceConfig.maxResults or 10
    local cooldown = sourceConfig.cooldown or 2

    if not query then
        emitSearchError(src, requestId, "Please type something to search.")
        return
    end

    if #query > maxQueryLength then
        emitSearchError(src, requestId, "Query is too long.")
        return
    end

    local cacheKey = buildSearchCacheKey(searchSource, query, maxResults)
    local now = os.time()
    local cached = searchResultCache[cacheKey]
    if cached and cached.expiresAt and cached.expiresAt >= now then
        if cached.success then
            emitSearchResults(src, requestId, cached.results)
        else
            emitSearchError(src, requestId, cached.message)
        end
        return
    end

    if searchInflight[cacheKey] then
        local listeners = searchInflight[cacheKey].listeners
        listeners[#listeners + 1] = { src = src, requestId = requestId }
        return
    end

    if searchCooldowns[src] and now < searchCooldowns[src] then
        emitSearchError(
            src,
            requestId,
            "Search is cooling down.",
            "cooldown",
            math.max(100, (searchCooldowns[src] - now) * 1000),
            searchCooldowns[src]
        )
        return
    end

    searchCooldowns[src] = now + cooldown
    searchInflight[cacheKey] = {
        listeners = {
            { src = src, requestId = requestId },
        },
    }

    SearchMedia(query, searchSource, maxResults, function(success, results)
        local listeners = searchInflight[cacheKey] and searchInflight[cacheKey].listeners or {}
        searchInflight[cacheKey] = nil

        if success then
            local payload = type(results) == "table" and results or {}
            searchResultCache[cacheKey] = {
                success = true,
                results = payload,
                expiresAt = os.time() + searchCacheTtl,
            }

            for _, listener in ipairs(listeners) do
                if listener and listener.src then
                    emitSearchResults(listener.src, listener.requestId, payload)
                end
            end
            return
        end

        local message = type(results) == "string" and results or "No results found. Try a different query."
        searchResultCache[cacheKey] = {
            success = false,
            message = message,
            expiresAt = os.time() + searchCacheTtl,
        }

        for _, listener in ipairs(listeners) do
            if listener and listener.src then
                emitSearchError(listener.src, listener.requestId, message)
            end
        end
    end)
end)

AddEventHandler("playerDropped", function()
    searchCooldowns[source] = nil
end)

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    discoverInstances(function(invidiousInstances, pipedInstances)
        print(("[7-pmms] Search ready: %d Invidious, %d Piped instances cached"):format(#invidiousInstances, #pipedInstances))
    end)
end)
