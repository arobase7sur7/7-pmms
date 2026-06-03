local cachedInvidiousInstances = {}
local cachedPipedInstances = {}
local instanceCacheExpiry = 0
local instanceCacheTtl = 1800
local instanceDiscoveryInFlight = false
local searchCooldowns = {}
local maxQueryLength = 200
local searchCacheTtl = 120
local failedSearchCacheTtl = 12
local searchResultCache = {}
local searchInflight = {}
local searchInstanceFailures = {
    invidious = {},
    piped = {},
}
local searchInstanceSuccesses = {
    invidious = {},
    piped = {},
}
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

local function performDiscoveryGet(url, callback, timeoutOverrideMs)
    local resolverConfig = type(Config.resolver) == "table" and Config.resolver or {}
    local timeoutMs = math.max(800, tonumber(timeoutOverrideMs) or tonumber(resolverConfig.timeoutMs) or 6000)
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

local function extractYoutubeVideoId(url)
    local value = trimText(url)
    if not value then
        return nil
    end

    local patterns = {
        "[?&]v=([%w_-]+)",
        "youtu%.be/([%w_-]+)",
        "/shorts/([%w_-]+)",
        "/embed/([%w_-]+)",
        "/watch/([%w_-]+)",
    }

    for _, pattern in ipairs(patterns) do
        local videoId = value:match(pattern)
        if videoId and #videoId >= 6 then
            return videoId
        end
    end

    return nil
end

local function youtubeThumbnailUrl(videoId)
    if type(videoId) ~= "string" or videoId == "" then
        return nil
    end
    return ("https://i.ytimg.com/vi/%s/hqdefault.jpg"):format(videoId)
end

local TWITCH_GQL_CLIENT_ID = "kimne78kx3ncx6brgo4mv6wki5h1ko"

local function normalizeTwitchChannel(query)
    local value = trimText(query)
    if not value then
        return nil
    end

    value = value:gsub("^@", "")

    local parsed = value:match("[?&]channel=([%w_]+)")
        or value:match("twitch%.tv/([%w_]+)")
        or value:match("^([%w_]+)$")

    if not parsed then
        return nil
    end

    parsed = parsed:gsub("^@", ""):lower()
    if not parsed:match("^[%w_]+$") or #parsed < 2 or #parsed > 32 then
        return nil
    end

    return parsed
end

local function getTwitchClientId()
    local twitch = type(Config.searchSources) == "table" and Config.searchSources["twitch"] or nil
    local configured = type(twitch) == "table" and trimText(twitch.clientId) or nil
    if configured and configured ~= "" then
        return configured
    end
    return TWITCH_GQL_CLIENT_ID
end

local function performTwitchGqlRequest(body, callback)
    local clientId = getTwitchClientId()
    PerformHttpRequest(
        "https://gql.twitch.tv/gql",
        function(status, responseBody)
            callback(status, responseBody)
        end,
        "POST",
        body,
        {
            ["Client-ID"] = clientId,
            ["Content-Type"] = "application/json",
        }
    )
end

local function buildTwitchResult(login, displayName, title, game, viewers, isLive, thumb)
    local channelLogin = tostring(login or ""):lower()
    local channelLabel = tostring(displayName or login or "")
    local streamTitle = type(title) == "string" and title ~= "" and title or (channelLabel .. " (Twitch)")
    local gameName = type(game) == "string" and game ~= "" and game or nil
    local viewerText = isLive and (type(viewers) == "number" and viewers > 0 and tostring(viewers) .. " viewers" or "Live") or "Offline"
    local author = gameName and (viewerText .. " · " .. gameName) or viewerText
    local defaultThumb = "https://static-cdn.jtvnw.net/previews-ttv/live_user_" .. channelLogin .. "-320x180.jpg"
    local fallbackThumb = "https://static-cdn.jtvnw.net/ttv-boxart/Twitch-285x380.jpg"
    local resolvedThumb = normalizeRemoteAssetUrl(thumb) or (isLive and defaultThumb or fallbackThumb)
    return {
        title = streamTitle,
        url = "https://www.twitch.tv/" .. channelLogin,
        duration = 0,
        author = author,
        thumbnail = resolvedThumb,
        thumbnailCandidates = { resolvedThumb, isLive and defaultThumb or fallbackThumb },
        source = "twitch",
        live = isLive == true,
        twitchOffline = isLive ~= true,
    }
end

local GQL_QUERY_USER = "query GetUser($login:String!)"
    .. "{user(login:$login){"
    .. "login displayName profileImageURL(width:300)"
    .. " stream{title viewersCount game{name}"
    .. " previewImageURL(width:320,height:180)}}}"

local GQL_QUERY_SEARCH = "query SearchChannels($query:String!,$first:Int!)"
    .. "{searchChannels(query:$query,first:$first)"
    .. "{nodes{login displayName profileImageURL(width:300)"
    .. " stream{title viewersCount game{name}"
    .. " previewImageURL(width:320,height:180)}}}}"

local function searchTwitchGql(query, maxResults, callback)
    local isExactChannel = normalizeTwitchChannel(query) ~= nil
    local gqlBody

    if isExactChannel then
        local channel = normalizeTwitchChannel(query)
        gqlBody = json.encode({
            { query = GQL_QUERY_USER, variables = { login = channel } }
        })
    else
        gqlBody = json.encode({
            {
                query = GQL_QUERY_SEARCH,
                variables = { query = query, first = math.max(1, math.min(maxResults, 20)) },
            }
        })
    end

    performTwitchGqlRequest(gqlBody, function(status, body)
        if status ~= 200 or not body then
            callback(false, "Twitch search is unavailable. Try again later.")
            return
        end

        local ok, decoded = pcall(json.decode, body)
        if not ok or type(decoded) ~= "table" or not decoded[1] then
            callback(false, "Twitch search returned an unexpected response.")
            return
        end

        local data = type(decoded[1]) == "table" and decoded[1].data or nil
        local results = {}

        if isExactChannel then
            local user = data and data.user
            if not user or type(user) ~= "table" then
                callback(false, "Channel not found on Twitch.")
                return
            end
            local stream = type(user.stream) == "table" and user.stream or nil
            local isLive = stream ~= nil
            local result = buildTwitchResult(
                user.login,
                user.displayName,
                stream and stream.title,
                stream and type(stream.game) == "table" and stream.game.name or nil,
                stream and stream.viewersCount,
                isLive,
                (isLive and stream.previewImageURL) or user.profileImageURL
            )
            results[1] = result
        else
            local nodes = data and data.searchChannels and data.searchChannels.nodes
            if type(nodes) ~= "table" or #nodes == 0 then
                callback(false, "No Twitch channels found for that query.")
                return
            end
            for _, node in ipairs(nodes) do
                if type(node) == "table" and type(node.login) == "string" then
                    local stream = type(node.stream) == "table" and node.stream or nil
                    local isLive = stream ~= nil
                    results[#results + 1] = buildTwitchResult(
                        node.login,
                        node.displayName,
                        stream and stream.title,
                        stream and type(stream.game) == "table" and stream.game.name or nil,
                        stream and stream.viewersCount,
                        isLive,
                        (isLive and stream.previewImageURL) or node.profileImageURL
                    )
                end
            end
            if #results == 0 then
                callback(false, "No Twitch channels found for that query.")
                return
            end
        end

        callback(true, results)
    end)
end

local function normalizeSearchThumbnailUrl(instance, rawUrl, videoId)
    local normalized = normalizeRemoteAssetUrl(rawUrl)
    if normalized then
        return normalized
    end

    local trimmed = trimText(rawUrl)
    if trimmed then
        if trimmed:match("^/vi/") or trimmed:match("^/vi_webp/") then
            return "https://i.ytimg.com" .. trimmed
        end
        if trimmed:sub(1, 1) == "/" and type(instance) == "string" and instance ~= "" then
            return instance:gsub("/$", "") .. trimmed
        end
    end

    return youtubeThumbnailUrl(videoId)
end

local buildSearchThumbnailCandidates

local function appendSearchThumbnailCandidate(target, seen, instance, rawUrl, videoId)
    local normalized = normalizeSearchThumbnailUrl(instance, rawUrl, videoId)
    if type(normalized) ~= "string" or normalized == "" then
        return
    end

    local key = normalized:lower()
    if seen[key] then
        return
    end

    seen[key] = true
    target[#target + 1] = normalized
end

buildSearchThumbnailCandidates = function(instance, thumbnails, videoId)
    local candidates = {}
    local seen = {}

    if type(thumbnails) == "table" then
        local ranked = {}
        for index, thumb in ipairs(thumbnails) do
            if type(thumb) == "table" and type(thumb.url) == "string" then
                ranked[#ranked + 1] = {
                    url = thumb.url,
                    area = (tonumber(thumb.width) or 0) * (tonumber(thumb.height) or 0),
                    index = index,
                }
            elseif type(thumb) == "string" then
                ranked[#ranked + 1] = {
                    url = thumb,
                    area = 0,
                    index = index,
                }
            end
        end

        table.sort(ranked, function(a, b)
            if a.area == b.area then
                return a.index < b.index
            end
            return a.area > b.area
        end)

        for _, thumb in ipairs(ranked) do
            appendSearchThumbnailCandidate(candidates, seen, instance, thumb.url, videoId)
        end
    elseif type(thumbnails) == "string" then
        appendSearchThumbnailCandidate(candidates, seen, instance, thumbnails, videoId)
    end

    appendSearchThumbnailCandidate(candidates, seen, nil, youtubeThumbnailUrl(videoId), videoId)
    return candidates
end

local function shuffleTable(values)
    for index = #values, 2, -1 do
        local swapIndex = math.random(index)
        values[index], values[swapIndex] = values[swapIndex], values[index]
    end
    return values
end

local function getSearchMaxInstances()
    local searchConfig = type(Config.search) == "table" and Config.search or {}
    local resolverConfig = type(Config.resolver) == "table" and Config.resolver or {}
    local configured = tonumber(searchConfig.maxInstances) or tonumber(resolverConfig.maxInstances) or 8
    return math.max(1, math.min(16, math.floor(configured)))
end

local function getSearchRequestTimeoutMs()
    local searchConfig = type(Config.search) == "table" and Config.search or {}
    local resolverConfig = type(Config.resolver) == "table" and Config.resolver or {}
    local configured = tonumber(searchConfig.requestTimeoutMs) or tonumber(resolverConfig.searchTimeoutMs) or 2500
    return math.max(800, math.min(3500, math.floor(configured)))
end

local function getSearchBudgetMs()
    local searchConfig = type(Config.search) == "table" and Config.search or {}
    local configured = tonumber(searchConfig.absoluteBudgetMs) or tonumber(searchConfig.timeoutMs) or 4500
    return math.max(1500, math.min(8000, math.floor(configured)))
end

local function getSearchParallelInstances()
    local searchConfig = type(Config.search) == "table" and Config.search or {}
    local resolverConfig = type(Config.resolver) == "table" and Config.resolver or {}
    local configured = tonumber(searchConfig.parallelInstancesPerProvider)
        or tonumber(resolverConfig.parallelInstancesPerProvider)
        or 2
    return math.max(1, math.min(4, math.floor(configured)))
end

local function getSearchFailureCooldownSeconds()
    local searchConfig = type(Config.search) == "table" and Config.search or {}
    local resolverConfig = type(Config.resolver) == "table" and Config.resolver or {}
    local configured = tonumber(searchConfig.instanceFailureCooldownSeconds)
        or tonumber(resolverConfig.instanceFailureCooldownSeconds)
        or 600
    return math.max(30, math.min(3600, math.floor(configured)))
end

local function isSearchInstanceCoolingDown(provider, instance)
    local providerFailures = searchInstanceFailures[provider]
    if type(providerFailures) ~= "table" then
        return false
    end

    local retryAt = providerFailures[instance]
    if not retryAt then
        return false
    end

    if retryAt <= os.time() then
        providerFailures[instance] = nil
        return false
    end

    return true
end

local function markSearchInstanceFailure(provider, instance)
    if type(instance) ~= "string" or instance == "" then
        return
    end

    searchInstanceFailures[provider] = searchInstanceFailures[provider] or {}
    searchInstanceFailures[provider][instance] = os.time() + getSearchFailureCooldownSeconds()
end

local function markSearchInstanceSuccess(provider, instance)
    if searchInstanceFailures[provider] then
        searchInstanceFailures[provider][instance] = nil
    end

    if type(instance) == "string" and instance ~= "" then
        searchInstanceSuccesses[provider] = searchInstanceSuccesses[provider] or {}
        local row = searchInstanceSuccesses[provider][instance] or { count = 0 }
        row.count = (tonumber(row.count) or 0) + 1
        row.lastSuccess = os.time()
        searchInstanceSuccesses[provider][instance] = row
    end
end

local function rankSearchInstances(provider, instances)
    local ranked = {}
    local seen = {}

    for _, instance in ipairs(instances or {}) do
        if type(instance) == "string" and instance ~= "" then
            local normalized = instance:gsub("/$", "")
            if not seen[normalized] and not isSearchInstanceCoolingDown(provider, normalized) then
                seen[normalized] = true
                local success = searchInstanceSuccesses[provider] and searchInstanceSuccesses[provider][normalized] or nil
                ranked[#ranked + 1] = {
                    url = normalized,
                    lastSuccess = tonumber(success and success.lastSuccess) or 0,
                    count = tonumber(success and success.count) or 0,
                    order = #ranked + 1,
                }
            end
        end
    end

    table.sort(ranked, function(a, b)
        if a.lastSuccess ~= b.lastSuccess then
            return a.lastSuccess > b.lastSuccess
        end
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.order < b.order
    end)

    local maxInstances = getSearchMaxInstances()
    local ordered = {}
    for index, entry in ipairs(ranked) do
        if index > maxInstances then
            break
        end
        ordered[#ordered + 1] = entry.url
    end
    return ordered
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

local function mapInvidiousSearchResults(instance, response, maxResults)
    local ok, data = pcall(json.decode, response or "")
    if not ok or type(data) ~= "table" or #data <= 0 then
        return nil
    end

    local results = {}
    for _, item in ipairs(data) do
        if item.type == "video" and item.videoId and #results < maxResults then
            local videoId = item.videoId
            local thumbnailCandidates = buildSearchThumbnailCandidates(instance, item.videoThumbnails, videoId)
            results[#results + 1] = {
                title = item.title,
                videoId = videoId,
                url = "https://www.youtube.com/watch?v=" .. videoId,
                duration = item.lengthSeconds,
                author = item.author,
                thumbnail = thumbnailCandidates[1] or "",
                thumbnailCandidates = thumbnailCandidates,
                source = "youtube",
            }
        end
    end

    return #results > 0 and results or nil
end

local function mapPipedSearchResults(instance, response, maxResults)
    local ok, data = pcall(json.decode, response or "")
    if not ok or type(data) ~= "table" then
        return nil
    end

    local items = data.items or data
    if type(items) ~= "table" or #items <= 0 then
        return nil
    end

    local results = {}
    for _, item in ipairs(items) do
        if #results >= maxResults then
            break
        end

        local videoUrl = item.url or ""
        if videoUrl:sub(1, 1) == "/" then
            videoUrl = "https://www.youtube.com" .. videoUrl
        end
        local videoId = item.videoId or extractYoutubeVideoId(videoUrl)
        local thumbnailCandidates = buildSearchThumbnailCandidates(instance, item.thumbnail, videoId)

        results[#results + 1] = {
            title = item.title or "Untitled",
            videoId = videoId,
            url = videoUrl,
            duration = item.duration or 0,
            author = item.uploaderName or item.uploader or "Unknown",
            thumbnail = thumbnailCandidates[1] or "",
            thumbnailCandidates = thumbnailCandidates,
            source = "youtube",
        }
    end

    return #results > 0 and results or nil
end

local function searchProviderBatched(provider, query, maxResults, instances, makeUrl, mapResults, callback)
    local candidates = rankSearchInstances(provider, instances)
    if #candidates <= 0 then
        callback(false, "No healthy " .. provider .. " search instances available.")
        return
    end

    local parallelLimit = math.min(getSearchParallelInstances(), #candidates)
    local nextIndex = 1
    local active = 0
    local finished = false
    local attempts = 0
    local maxAttempts = math.min(#candidates, getSearchMaxInstances())
    local lastMessage = "No results found. Try a different query."

    local function finish(success, payload)
        if finished then
            return
        end
        finished = true
        callback(success, payload)
    end

    SetTimeout(getSearchBudgetMs(), function()
        finish(false, "Search timed out before a healthy " .. provider .. " instance responded.")
    end)

    local function maybeFinish()
        if finished or active > 0 or (nextIndex <= #candidates and attempts < maxAttempts) then
            return
        end
        finish(false, lastMessage)
    end

    local function launchNext()
        if finished then
            return
        end

        while active < parallelLimit and nextIndex <= #candidates and attempts < maxAttempts do
            local instance = candidates[nextIndex]
            nextIndex = nextIndex + 1
            attempts = attempts + 1
            active = active + 1

            performDiscoveryGet(makeUrl(instance, query), function(statusCode, response)
                active = active - 1
                if finished then
                    return
                end

                local results = nil
                if statusCode == 200 and response then
                    results = mapResults(instance, response, maxResults)
                end

                if type(results) == "table" and #results > 0 then
                    markSearchInstanceSuccess(provider, instance)
                    finish(true, results)
                    return
                end

                markSearchInstanceFailure(provider, instance)
                lastMessage = "No results found. Try a different query."
                launchNext()
                maybeFinish()
            end, getSearchRequestTimeoutMs())
        end

        maybeFinish()
    end

    launchNext()
end

local function searchInvidious(query, maxResults, instances, callback)
    searchProviderBatched(
        "invidious",
        query,
        maxResults,
        instances,
        function(instance, value)
            return instance .. "/api/v1/search?q=" .. EncodeUrlString(value) .. "&type=video"
        end,
        mapInvidiousSearchResults,
        callback
    )
end

local function searchPiped(query, maxResults, instances, callback)
    searchProviderBatched(
        "piped",
        query,
        maxResults,
        instances,
        function(instance, value)
            return instance .. "/search?q=" .. EncodeUrlString(value) .. "&filter=videos"
        end,
        mapPipedSearchResults,
        callback
    )
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
            searchInvidious(query, maxResults, invidiousInstances, complete)
        end

        if #pipedInstances > 0 then
            pending = pending + 1
            searchPiped(query, maxResults, pipedInstances, complete)
        end
    end)
end

local function searchRadio(query, maxResults, callback)
    maxResults = math.max(1, math.min(50, tonumber(maxResults) or 20))
    if type(query) == "string" and query:match("^https?://") then
        callback(true, {
            {
                title = query,
                url = query,
                duration = 0,
                live = true,
                author = "Radio stream",
                thumbnail = "",
                source = "radio",
                direct = true,
                radio = true,
                video = false,
            },
        })
        return
    end

    local function mapStation(station)
        if type(station) ~= "table" then
            return nil
        end
        local streamUrl = normalizeRemoteAssetUrl(station.url_resolved or station.url)
        if not streamUrl then
            return nil
        end
        local meta = {}
        if station.countrycode and station.countrycode ~= "" then meta[#meta + 1] = station.countrycode end
        if station.language and station.language ~= "" then meta[#meta + 1] = station.language end
        if station.tags and station.tags ~= "" then meta[#meta + 1] = station.tags end
        local bitrate = tonumber(station.bitrate)
        if bitrate and bitrate > 0 then meta[#meta + 1] = tostring(bitrate) .. "kbps" end

        return {
            title = station.name or streamUrl,
            url = streamUrl,
            originalUrl = station.url or streamUrl,
            duration = 0,
            live = true,
            author = #meta > 0 and table.concat(meta, " | ") or "Radio station",
            thumbnail = normalizeRemoteAssetUrl(station.favicon) or "",
            source = "radio",
            radio = true,
            direct = true,
            video = false,
            stationUuid = station.stationuuid,
            codec = station.codec,
            bitrate = station.bitrate,
            country = station.country,
            countrycode = station.countrycode,
            language = station.language,
            tags = station.tags,
        }
    end

    local base = "https://all.api.radio-browser.info/json/stations/search?"
    local encoded = EncodeUrlString(query)
    local suffix = "&limit=" .. tostring(maxResults) .. "&hidebroken=true&order=clickcount&reverse=true"
    local urls = {
        base .. "name=" .. encoded .. suffix,
        base .. "country=" .. encoded .. suffix,
        base .. "language=" .. encoded .. suffix,
        base .. "tag=" .. encoded .. suffix,
    }
    local pending = #urls
    local results = {}
    local seen = {}
    local hadHttpFailure = false

    local function finish()
        if pending > 0 then
            return
        end
        if #results > 0 then
            callback(true, results)
        elseif hadHttpFailure then
            callback(false, "Radio station search is unavailable right now.")
        else
            callback(false, "No radio stations found. Try a station name, country, language, or genre.")
        end
    end

    for _, url in ipairs(urls) do
        performDiscoveryGet(url, function(statusCode, response)
            pending = pending - 1
            if statusCode ~= 200 or not response then
                hadHttpFailure = true
                finish()
                return
            end

            local ok, data = pcall(json.decode, response)
            if not ok or type(data) ~= "table" then
                finish()
                return
            end

        for _, station in ipairs(data) do
            if #results >= maxResults then
                break
            end

            local mapped = mapStation(station)
            local key = mapped and (mapped.stationUuid or mapped.url)
            if mapped and key and not seen[key] then
                seen[key] = true
                results[#results + 1] = mapped
            end
        end

            finish()
        end)
    end
end

function SearchMedia(query, searchSource, maxResults, callback)
    if searchSource == "direct" then
        if type(query) == "string" and query:match("^https?://") then
            callback(true, {
                {
                    title = query,
                    url = query,
                    duration = 0,
                    author = "Direct link",
                    thumbnail = "",
                    source = "direct",
                    direct = true,
                },
            })
        else
            callback(false, "Paste a direct http(s) media URL.")
        end
        return
    end

    if searchSource == "twitch" then
        if not query or trimText(query) == nil then
            callback(false, "Enter a Twitch channel name or search term.")
            return
        end
        searchTwitchGql(trimText(query), maxResults, callback)
        return
    end

    if searchSource == "radio" then
        searchRadio(query, maxResults, callback)
        return
    end

    if searchSource == "soundcloud" then
        local value = trimText(query)
        if type(value) == "string" and value:match("^https?://") and value:find("soundcloud%.com", 1, false) then
            callback(true, {
                {
                    title = value,
                    url = value,
                    duration = 0,
                    author = "SoundCloud",
                    thumbnail = "",
                    source = "soundcloud",
                    direct = false,
                },
            })
        else
            callback(false, "Paste a SoundCloud track or playlist URL (soundcloud.com/...).")
        end
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
        startedAt = os.clock(),
    }

    SearchMedia(query, searchSource, maxResults, function(success, results)
        local inflight = searchInflight[cacheKey]
        local listeners = inflight and inflight.listeners or {}
        local durationMs = inflight and math.floor(math.max(0, (os.clock() - (inflight.startedAt or os.clock())) * 1000)) or nil
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
            PMMSDebug("search", "search completed", {
                source = searchSource,
                queryLength = #query,
                results = #payload,
                durationMs = durationMs,
                listeners = #listeners,
            })
            return
        end

        local message = type(results) == "string" and results or "No results found. Try a different query."
        searchResultCache[cacheKey] = {
            success = false,
            message = message,
            expiresAt = os.time() + failedSearchCacheTtl,
        }

        for _, listener in ipairs(listeners) do
            if listener and listener.src then
                emitSearchError(listener.src, listener.requestId, message)
            end
        end
        PMMSDebug("search", "search failed", {
            source = searchSource,
            queryLength = #query,
            message = message,
            durationMs = durationMs,
            listeners = #listeners,
        })
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
