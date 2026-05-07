local resolverConfig = Config.resolver or {}

local instanceCache = {
    invidious = {},
    piped = {},
    expiresAt = 0,
}
local instanceDiscoveryInFlight = false

local resolveCache = {}
local resolveInflight = {}
local instanceFailures = {
    invidious = {},
    piped = {},
    extractor_http = {},
    cobalt = {},
}
local builtinResolverInstances = {
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

local normalizeDuration
local codecScore
local shouldAvoidUrl
local markInstanceFailure
local markInstanceHealthy
local isInstanceSuppressed

local function cloneTable(source)
    local copy = {}
    for k, v in pairs(source or {}) do
        copy[k] = v
    end
    return copy
end

local function bool(value, defaultValue)
    if value == nil then
        return defaultValue
    end
    return value == true
end

local function getCacheTtl()
    return math.max(30, tonumber(resolverConfig.cacheTtlSeconds) or 1800)
end

local function getMaxInstances()
    return math.max(1, tonumber(resolverConfig.maxInstances) or 6)
end

local function getParallelInstancesPerProvider()
    return math.max(1, tonumber(resolverConfig.parallelInstancesPerProvider) or 2)
end

local function getExtractorConfig()
    local extractor = resolverConfig.extractor
    if type(extractor) ~= "table" then
        return {}
    end
    return extractor
end

local function getCobaltConfig()
    local cobalt = resolverConfig.cobalt
    if type(cobalt) ~= "table" then
        return {}
    end
    return cobalt
end

local function isExtractorEnabled()
    local extractorConfig = getExtractorConfig()
    return bool(extractorConfig.enabled, true)
end

local function isCobaltEnabled()
    local cobaltConfig = getCobaltConfig()
    return bool(cobaltConfig.enabled, true)
end

local function getExtractorTimeoutMs()
    local extractorConfig = getExtractorConfig()
    local timeout = tonumber(extractorConfig.timeoutMs)
    if timeout and timeout > 0 then
        return math.floor(timeout)
    end
    return math.max(2000, tonumber(resolverConfig.timeoutMs) or 6000)
end

local function getCobaltTimeoutMs()
    local cobaltConfig = getCobaltConfig()
    local timeout = tonumber(cobaltConfig.timeoutMs)
    if timeout and timeout > 0 then
        return math.floor(timeout)
    end
    return math.max(getExtractorTimeoutMs(), 12000)
end

local function getExtractorCooldownSeconds()
    local extractorConfig = getExtractorConfig()
    return math.max(30, tonumber(extractorConfig.cooldownSeconds) or 300)
end

local function getExtractorMaxAttempts()
    local extractorConfig = getExtractorConfig()
    return math.max(1, tonumber(extractorConfig.maxAttemptsPerProvider) or 2)
end

local ytDlpProbeState = {
    checkedAt = 0,
    available = false,
    command = nil,
    message = nil,
}
local providerCooldowns = {
    yt_dlp_local = { untilTs = 0, reason = nil },
}

local function getInstanceFailureCooldownSeconds()
    return math.max(60, tonumber(resolverConfig.instanceFailureCooldownSeconds) or 600)
end

local function getUserAgent()
    return "7-PMMS-Resolver"
end

local function isResolverEnabled()
    return bool(resolverConfig.enabled, true)
end

local function isAudioFallbackAllowed(resolverOptions)
    if resolverOptions and resolverOptions.allowAudioFallback == false then
        return false
    end
    return bool(resolverConfig.allowAudioFallback, true)
end

local function isEmbedFallbackAllowed(resolverOptions)
    if resolverOptions and resolverOptions.allowFallback == false then
        return false
    end
    if resolverOptions and resolverOptions.allowEmbedFallback ~= nil then
        return resolverOptions.allowEmbedFallback == true
    end
    return bool(resolverConfig.allowEmbedFallback, false) and bool(resolverConfig.fallbackOnFailure, true)
end

local function performGet(url, callback)
    local timeout = tonumber(resolverConfig.timeoutMs)
    local requestOptions = nil
    if timeout and timeout > 0 then
        requestOptions = { timeout = math.floor(timeout) }
    end

    PerformHttpRequest(url, function(statusCode, body)
        callback(statusCode, body)
    end, "GET", "", {
        ["User-Agent"] = getUserAgent(),
        ["Accept"] = "application/json",
    }, requestOptions)
end

local function performPost(url, payload, timeoutMs, callback, extraHeaders)
    local requestOptions = nil
    local timeout = tonumber(timeoutMs)
    if timeout and timeout > 0 then
        requestOptions = { timeout = math.floor(timeout) }
    end

    local encodedPayload = ""
    if payload ~= nil then
        local ok, encoded = pcall(json.encode, payload)
        if ok and type(encoded) == "string" then
            encodedPayload = encoded
        end
    end

    local headers = {
        ["User-Agent"] = getUserAgent(),
        ["Accept"] = "application/json",
        ["Content-Type"] = "application/json",
    }

    if type(extraHeaders) == "table" then
        for key, value in pairs(extraHeaders) do
            if type(key) == "string" and key ~= "" and value ~= nil and value ~= "" then
                headers[key] = tostring(value)
            end
        end
    end

    PerformHttpRequest(url, function(statusCode, body)
        callback(statusCode, body)
    end, "POST", encodedPayload, headers, requestOptions)
end

local function trimTrailingSlash(url)
    if type(url) ~= "string" then
        return nil
    end
    return (url:gsub("/+$", ""))
end

local function pushUnique(target, seen, url)
    local normalized = trimTrailingSlash(url)
    if not normalized or normalized == "" then
        return
    end

    local key = normalized:lower()
    if seen[key] then
        return
    end

    seen[key] = true
    target[#target + 1] = normalized
end

local function shuffleCopy(list)
    local copy = {}
    for i, value in ipairs(list or {}) do
        copy[i] = value
    end

    for index = #copy, 2, -1 do
        local swapIndex = math.random(index)
        copy[index], copy[swapIndex] = copy[swapIndex], copy[index]
    end

    return copy
end

local function markProviderCooldown(provider, reason)
    if type(provider) ~= "string" or provider == "" then
        return
    end
    providerCooldowns[provider] = {
        untilTs = os.time() + getExtractorCooldownSeconds(),
        reason = reason or "provider_error",
    }
end

local function clearProviderCooldown(provider)
    if providerCooldowns[provider] then
        providerCooldowns[provider] = { untilTs = 0, reason = nil }
    end
end

local function getProviderCooldown(provider, now)
    local state = providerCooldowns[provider]
    if not state then
        return nil
    end
    now = now or os.time()
    if (tonumber(state.untilTs) or 0) > now then
        return state
    end
    return nil
end

local function trimString(value)
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
    local trimmed = trimString(url)
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

local function buildResolveInflightKey(options, resolverOptions)
    local mode = options and options.video == false and "audio" or "video"
    local sourceUrl = options and options.url or ""
    local avoidResolvedUrl = resolverOptions and resolverOptions.avoidResolvedUrl or ""
    local avoidProvider = resolverOptions and resolverOptions.avoidProvider or ""
    local avoidInstance = resolverOptions and resolverOptions.avoidInstance or ""
    local allowFallback = resolverOptions and resolverOptions.allowFallback == false and "0" or "1"
    local allowAudioFallback = isAudioFallbackAllowed(resolverOptions) and "1" or "0"
    local allowEmbedFallback = isEmbedFallbackAllowed(resolverOptions) and "1" or "0"
    local forceRefresh = resolverOptions and resolverOptions.forceRefresh == true and "1" or "0"
    local audioFallbackAttempted = resolverOptions and resolverOptions.audioFallbackAttempted == true and "1" or "0"
    return table.concat({
        tostring(sourceUrl),
        mode,
        tostring(forceRefresh),
        tostring(allowFallback),
        tostring(allowAudioFallback),
        tostring(allowEmbedFallback),
        tostring(audioFallbackAttempted),
        tostring(avoidProvider),
        tostring(avoidInstance),
        tostring(avoidResolvedUrl),
    }, "|")
end

local function addCommandCandidate(target, seen, candidate)
    local normalized = trimString(candidate)
    if not normalized then
        return
    end

    local key = normalized:lower()
    if seen[key] then
        return
    end

    seen[key] = true
    target[#target + 1] = normalized
end

local function getYtDlpCommandCandidates()
    local extractorConfig = getExtractorConfig()
    local commands = {}
    local seen = {}

    if type(extractorConfig.ytDlpCommand) == "table" then
        for _, candidate in ipairs(extractorConfig.ytDlpCommand) do
            addCommandCandidate(commands, seen, candidate)
        end
    else
        addCommandCandidate(commands, seen, extractorConfig.ytDlpCommand)
    end

    addCommandCandidate(commands, seen, "yt-dlp")
    addCommandCandidate(commands, seen, "python -m yt_dlp")
    addCommandCandidate(commands, seen, "py -m yt_dlp")

    return commands
end

local function resolveYtDlpCommand()
    if ytDlpProbeState.available == true and ytDlpProbeState.command then
        return ytDlpProbeState.command
    end

    local commands = getYtDlpCommandCandidates()
    return commands[1] or "yt-dlp"
end

local function isWindowsRuntime()
    return package and package.config and package.config:sub(1, 1) == "\\"
end

local function shellQuote(value)
    value = tostring(value or "")
    if isWindowsRuntime() then
        return '"' .. value:gsub('"', '\\"') .. '"'
    end
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function runCommand(command)
    if type(io) ~= "table" or type(io.popen) ~= "function" then
        return false, nil, "io_popen_unavailable"
    end

    local ok, handle = pcall(io.popen, command)
    if not ok or not handle then
        return false, nil, "spawn_failed"
    end

    local readOk, output = pcall(handle.read, handle, "*a")
    if not readOk then
        pcall(handle.close, handle)
        return false, nil, "read_failed"
    end

    local closeOk, closeA, closeB, closeC = pcall(handle.close, handle)
    if not closeOk then
        return false, output or "", "close_failed"
    end

    local exitCode = nil
    if type(closeA) == "number" then
        exitCode = closeA
    elseif type(closeA) == "boolean" then
        if closeA then
            exitCode = 0
        elseif type(closeC) == "number" then
            exitCode = closeC
        elseif type(closeB) == "number" then
            exitCode = closeB
        else
            exitCode = 1
        end
    elseif closeA == nil and type(closeC) == "number" then
        exitCode = closeC
    end

    if type(exitCode) == "number" and exitCode ~= 0 then
        return false, output or "", ("exit_code_%d"):format(exitCode)
    end

    return true, output or "", nil
end

local function detectYtDlpProbeError(output, reason)
    local reasonText = tostring(reason or "")
    local combined = (tostring(output or "") .. "\n" .. reasonText):lower()

    if combined:find("no module named yt_dlp", 1, true) then
        return "python_module_missing"
    end

    if combined:find("not recognized", 1, true)
        or combined:find("command not found", 1, true)
        or combined:find("is not recognized", 1, true)
        or combined:find("not found", 1, true)
        or combined:find("no se reconoce", 1, true)
        or combined:find("n'est pas reconnu", 1, true) then
        return "command_not_found"
    end

    if reasonText ~= "" then
        return reasonText
    end

    local trimmed = trimString(output)
    if not trimmed then
        return "empty_probe_output"
    end

    return nil
end

local function classifyHttpFailure(statusCode)
    local numeric = tonumber(statusCode)
    if not numeric or numeric <= 0 then
        return "network_error"
    end
    if numeric == 401 or numeric == 403 then
        return "access_denied"
    end
    if numeric == 404 then
        return "not_found"
    end
    if numeric == 429 then
        return "rate_limited"
    end
    if numeric >= 500 then
        return "upstream_5xx"
    end
    return ("http_%d"):format(numeric)
end

local function bodyLooksLikeJson(body)
    if type(body) ~= "string" then
        return false
    end

    local trimmed = body:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return false
    end

    local first = trimmed:sub(1, 1)
    return first == "{" or first == "["
end

local function extractJsonPayload(body)
    if type(body) ~= "string" then
        return nil
    end

    if bodyLooksLikeJson(body) then
        return body
    end

    local firstCurly = body:find("{", 1, true)
    if not firstCurly then
        return nil
    end

    local lastCurly = nil
    for pos in body:gmatch("()}") do
        lastCurly = pos
    end

    if not lastCurly or (lastCurly + 1) < firstCurly then
        return nil
    end

    local sliced = body:sub(firstCurly, lastCurly + 1)
    if bodyLooksLikeJson(sliced) then
        return sliced
    end

    return nil
end

local function classifyUpstreamError(decoded)
    if type(decoded) ~= "table" then
        return nil
    end

    local message = nil
    if type(decoded.error) == "string" and decoded.error ~= "" then
        message = decoded.error
    elseif type(decoded.message) == "string" and decoded.message ~= "" then
        message = decoded.message
    end

    if not message then
        return nil
    end

    local lower = message:lower()
    if lower:find("sign in", 1, true)
        or lower:find("not a bot", 1, true)
        or lower:find("captcha", 1, true)
        or lower:find("challenge", 1, true)
        or lower:find("login_required", 1, true) then
        return "upstream_challenge"
    end

    if lower:find("rate", 1, true) and lower:find("limit", 1, true) then
        return "rate_limited"
    end

    return "upstream_error"
end

local function makeTraceEntry(provider, status, reason, details)
    local entry = {
        provider = provider,
        status = status,
        reason = reason,
        at = os.time(),
    }
    if type(details) == "table" then
        for key, value in pairs(details) do
            entry[key] = value
        end
    end
    return entry
end

local function summarizeTrace(trace)
    if type(trace) ~= "table" or #trace == 0 then
        return "no resolver attempts were recorded"
    end

    local parts = {}
    for _, entry in ipairs(trace) do
        local provider = entry.provider or "unknown"
        local status = entry.status or "unknown"
        local reason = entry.reason or "unknown"
        parts[#parts + 1] = ("%s:%s(%s)"):format(provider, status, reason)
    end

    return table.concat(parts, " -> ")
end

local function getConfiguredProviderOrder()
    local defaultOrder = { "yt_dlp_local", "extractor_http", "cobalt", "invidious", "piped" }
    local extractorConfig = getExtractorConfig()
    if type(extractorConfig.providerOrder) ~= "table" then
        return defaultOrder
    end

    local allowed = {
        yt_dlp_local = true,
        extractor_http = true,
        cobalt = true,
        invidious = true,
        piped = true,
        embed = true,
    }

    local normalized = {}
    local seen = {}
    for _, value in ipairs(extractorConfig.providerOrder) do
        if type(value) == "string" then
            local provider = value:lower()
            if allowed[provider] and not seen[provider] then
                seen[provider] = true
                normalized[#normalized + 1] = provider
            end
        end
    end

    if #normalized == 0 then
        return defaultOrder
    end

    return normalized
end

local function getYtDlpProbeCommand(command)
    return ("%s --version 2>&1"):format(command)
end

local function ensureYtDlpAvailability(now)
    now = now or os.time()
    local cooldown = getProviderCooldown("yt_dlp_local", now)
    if cooldown then
        return false, cooldown.reason or "cooldown_active"
    end

    if (now - (ytDlpProbeState.checkedAt or 0)) < 60 and ytDlpProbeState.command then
        return ytDlpProbeState.available == true, ytDlpProbeState.message
    end

    local candidates = getYtDlpCommandCandidates()
    local attemptedReasons = {}
    ytDlpProbeState.checkedAt = now

    for _, command in ipairs(candidates) do
        local ok, output, errReason = runCommand(getYtDlpProbeCommand(command))
        local probeError = detectYtDlpProbeError(output, not ok and errReason or nil)

        if ok and not probeError then
            local version = trimString(output)
            if version then
                ytDlpProbeState.available = true
                ytDlpProbeState.command = command
                ytDlpProbeState.message = nil
                clearProviderCooldown("yt_dlp_local")
                return true, nil
            end
            probeError = "empty_version_output"
        end

        attemptedReasons[#attemptedReasons + 1] = ("%s:%s"):format(command, probeError or errReason or "probe_failed")
    end

    ytDlpProbeState.available = false
    ytDlpProbeState.command = candidates[1] or "yt-dlp"
    ytDlpProbeState.message = table.concat(attemptedReasons, ", ")
    markProviderCooldown("yt_dlp_local", ytDlpProbeState.message or "probe_failed")
    return false, ytDlpProbeState.message
end

local function preferMetadataValue(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
    if type(value) == "number" and value > 0 then
        return value
    end
    return nil
end

local function scoreYtDlpFormat(format)
    if type(format) ~= "table" then
        return -999999
    end

    local ext = tostring(format.ext or "")
    local vcodec = tostring(format.vcodec or "")
    local acodec = tostring(format.acodec or "")
    local protocol = tostring(format.protocol or "")
    local mime = ("%s %s %s"):format(ext, vcodec, acodec)

    local score = codecScore(mime)
    local height = tonumber(format.height) or 0
    local bitrate = tonumber(format.tbr) or tonumber(format.abr) or tonumber(format.vbr) or 0

    score = score + (height / 15) + (bitrate / 100)

    if protocol:find("m3u8", 1, true) then
        score = score - 120
    end
    if protocol:find("dash", 1, true) then
        score = score - 220
    end

    return score
end

local function chooseYtDlpFormat(info, wantVideo, avoidResolvedUrl)
    if type(info) ~= "table" or type(info.formats) ~= "table" then
        return nil
    end

    local bestFormat = nil
    local bestScore = -999999

    for _, format in ipairs(info.formats) do
        if type(format) == "table" and type(format.url) == "string" then
            if shouldAvoidUrl(format.url, avoidResolvedUrl) then
                goto continue_format
            end

            local vcodec = tostring(format.vcodec or "")
            local acodec = tostring(format.acodec or "")
            local hasVideo = vcodec ~= "" and vcodec ~= "none"
            local hasAudio = acodec ~= "" and acodec ~= "none"

            if wantVideo then
                if not (hasVideo and hasAudio) then
                    goto continue_format
                end
            else
                if not hasAudio then
                    goto continue_format
                end
                if hasVideo then
                    local formatScore = scoreYtDlpFormat(format) - 150
                    if formatScore > bestScore then
                        bestScore = formatScore
                        bestFormat = format
                    end
                    goto continue_format
                end
            end

            local formatScore = scoreYtDlpFormat(format)
            if formatScore > bestScore then
                bestScore = formatScore
                bestFormat = format
            end
        end
        ::continue_format::
    end

    return bestFormat
end

local function buildYtDlpCommand(url)
    local timeoutSeconds = math.max(3, math.floor(getExtractorTimeoutMs() / 1000))
    return ("%s --no-playlist --no-warnings --skip-download --dump-single-json --socket-timeout %d -- %s 2>&1")
        :format(resolveYtDlpCommand(), timeoutSeconds, shellQuote(url))
end

local function resolveFromYtDlp(url, wantVideo, avoidResolvedUrl, callback)
    if not isExtractorEnabled() then
        callback(nil, "extractor_disabled", makeTraceEntry("yt_dlp_local", "skipped", "extractor_disabled"))
        return
    end

    local available, availabilityReason = ensureYtDlpAvailability(os.time())
    if not available then
        callback(nil, availabilityReason or "yt_dlp_unavailable", makeTraceEntry("yt_dlp_local", "failed", availabilityReason or "yt_dlp_unavailable"))
        return
    end

    local ok, output, commandReason = runCommand(buildYtDlpCommand(url))
    if not ok then
        markProviderCooldown("yt_dlp_local", commandReason or "command_failed")
        callback(nil, commandReason or "command_failed", makeTraceEntry("yt_dlp_local", "failed", commandReason or "command_failed"))
        return
    end

    local jsonPayload = extractJsonPayload(output)
    if not jsonPayload then
        markProviderCooldown("yt_dlp_local", "non_json_output")
        callback(nil, "non_json_output", makeTraceEntry("yt_dlp_local", "failed", "non_json_output"))
        return
    end

    local decodeOk, decoded = pcall(json.decode, jsonPayload)
    if not decodeOk or type(decoded) ~= "table" then
        markProviderCooldown("yt_dlp_local", "decode_failed")
        callback(nil, "decode_failed", makeTraceEntry("yt_dlp_local", "failed", "decode_failed"))
        return
    end

    local chosen = chooseYtDlpFormat(decoded, wantVideo, avoidResolvedUrl)
    if not chosen or type(chosen.url) ~= "string" or chosen.url == "" then
        callback(nil, "no_compatible_stream", makeTraceEntry("yt_dlp_local", "failed", "no_compatible_stream"))
        return
    end

    clearProviderCooldown("yt_dlp_local")
    callback({
        playableUrl = chosen.url,
        title = preferMetadataValue(decoded.title),
        author = preferMetadataValue(decoded.uploader) or preferMetadataValue(decoded.channel),
        duration = normalizeDuration(preferMetadataValue(decoded.duration)),
        thumbnail = normalizeRemoteAssetUrl(preferMetadataValue(decoded.thumbnail)),
        provider = "yt_dlp_local",
        instance = resolveYtDlpCommand(),
    }, nil, makeTraceEntry("yt_dlp_local", "success", "resolved"))
end

local function collectConfiguredExtractorEndpoints()
    local extractorConfig = getExtractorConfig()
    local endpoints = {}
    local seen = {}
    if type(extractorConfig.httpEndpoints) == "table" then
        for _, endpoint in ipairs(extractorConfig.httpEndpoints) do
            pushUnique(endpoints, seen, endpoint)
        end
    end
    return endpoints
end

local function normalizeHttpExtractorPayload(decoded)
    if type(decoded) ~= "table" then
        return nil
    end

    local payload = decoded
    if type(decoded.result) == "table" then
        payload = decoded.result
    elseif type(decoded.data) == "table" then
        payload = decoded.data
    end

    local playableUrl = payload.playableUrl or payload.url or payload.streamUrl
    if type(playableUrl) ~= "string" or playableUrl == "" then
        return nil
    end

    return {
        playableUrl = playableUrl,
        title = payload.title,
        author = payload.author or payload.uploader,
        duration = normalizeDuration(payload.duration),
        thumbnail = normalizeRemoteAssetUrl(payload.thumbnail),
        provider = "extractor_http",
    }
end

local function resolveFromHttpExtractor(url, wantVideo, avoidResolvedUrl, callback)
    if not isExtractorEnabled() then
        callback(nil, "extractor_disabled", makeTraceEntry("extractor_http", "skipped", "extractor_disabled"))
        return
    end

    local endpoints = collectConfiguredExtractorEndpoints()
    if #endpoints == 0 then
        callback(nil, "no_http_endpoints", makeTraceEntry("extractor_http", "skipped", "no_http_endpoints"))
        return
    end

    local mode = wantVideo and "video" or "audio"
    local now = os.time()
    local filtered = {}
    for _, endpoint in ipairs(endpoints) do
        if not isInstanceSuppressed("extractor_http", endpoint, now) then
            filtered[#filtered + 1] = endpoint
        end
    end
    if #filtered == 0 then
        filtered = shuffleCopy(endpoints)
    else
        filtered = shuffleCopy(filtered)
    end

    local maxAttempts = math.min(#filtered, getExtractorMaxAttempts())
    local function tryEndpoint(index)
        if index > maxAttempts then
            callback(nil, "http_extractor_unavailable", makeTraceEntry("extractor_http", "failed", "http_extractor_unavailable"))
            return
        end

        local endpoint = trimTrailingSlash(filtered[index])
        if not endpoint then
            tryEndpoint(index + 1)
            return
        end

        performPost(endpoint, {
            url = url,
            mode = mode,
            avoidResolvedUrl = avoidResolvedUrl,
            source = "7-pmms",
        }, getExtractorTimeoutMs(), function(statusCode, body)
            if statusCode ~= 200 or not body then
                markInstanceFailure("extractor_http", endpoint, classifyHttpFailure(statusCode))
                tryEndpoint(index + 1)
                return
            end

            local jsonPayload = extractJsonPayload(body)
            if not jsonPayload then
                markInstanceFailure("extractor_http", endpoint, "non_json_response")
                tryEndpoint(index + 1)
                return
            end

            local ok, decoded = pcall(json.decode, jsonPayload)
            if not ok or type(decoded) ~= "table" then
                markInstanceFailure("extractor_http", endpoint, "decode_failed")
                tryEndpoint(index + 1)
                return
            end

            local upstreamError = classifyUpstreamError(decoded)
            if upstreamError then
                markInstanceFailure("extractor_http", endpoint, upstreamError)
                tryEndpoint(index + 1)
                return
            end

            local normalized = normalizeHttpExtractorPayload(decoded)
            if not normalized or shouldAvoidUrl(normalized.playableUrl, avoidResolvedUrl) then
                markInstanceFailure("extractor_http", endpoint, "invalid_payload")
                tryEndpoint(index + 1)
                return
            end

            markInstanceHealthy("extractor_http", endpoint)
            normalized.instance = endpoint
            callback(normalized, nil, makeTraceEntry("extractor_http", "success", "resolved", { instance = endpoint }))
        end)
    end

    tryEndpoint(1)
end

local function collectConfiguredCobaltEndpoints()
    local cobaltConfig = getCobaltConfig()
    local endpoints = {}
    local seen = {}

    if type(cobaltConfig.endpoints) == "table" then
        for _, endpoint in ipairs(cobaltConfig.endpoints) do
            pushUnique(endpoints, seen, endpoint)
        end
    else
        pushUnique(endpoints, seen, cobaltConfig.endpoint)
    end

    return endpoints
end

local function buildCobaltHeaders()
    local cobaltConfig = getCobaltConfig()
    local apiKey = trimString(cobaltConfig.apiKey)
    if not apiKey then
        return nil
    end

    local headerName = trimString(cobaltConfig.apiKeyHeader) or "Authorization"
    local prefix = trimString(cobaltConfig.apiKeyPrefix)
    local headerValue = apiKey
    if prefix then
        headerValue = ("%s %s"):format(prefix, apiKey)
    end

    return {
        [headerName] = headerValue,
    }
end

local function buildCobaltRequestPayload(url, wantVideo)
    local cobaltConfig = getCobaltConfig()
    local payload = {
        url = url,
        filenameStyle = trimString(cobaltConfig.filenameStyle) or "basic",
        alwaysProxy = cobaltConfig.alwaysProxy ~= false,
    }

    if wantVideo then
        payload.downloadMode = trimString(cobaltConfig.downloadMode) or "auto"
        payload.videoQuality = tostring(cobaltConfig.videoQuality or "720")
        payload.youtubeVideoCodec = trimString(cobaltConfig.youtubeVideoCodec) or "h264"
        payload.youtubeVideoContainer = trimString(cobaltConfig.youtubeVideoContainer) or "mp4"
    else
        payload.downloadMode = "audio"
        payload.audioFormat = trimString(cobaltConfig.audioFormat) or "mp3"
        payload.audioBitrate = tostring(cobaltConfig.audioBitrate or "128")
    end

    if cobaltConfig.disableMetadata == true then
        payload.disableMetadata = true
    end

    return payload
end

local function normalizeCobaltPayload(decoded, wantVideo, avoidResolvedUrl)
    if type(decoded) ~= "table" then
        return nil, "invalid_payload"
    end

    if decoded.status == "error" then
        local errorCode = "cobalt_error"
        if type(decoded.error) == "table" and type(decoded.error.code) == "string" then
            errorCode = decoded.error.code
        elseif type(decoded.text) == "string" then
            errorCode = decoded.text
        end
        return nil, errorCode
    end

    local streamUrl = nil
    if type(decoded.url) == "string" and decoded.url ~= "" then
        streamUrl = decoded.url
    elseif type(decoded.picker) == "table" then
        for _, item in ipairs(decoded.picker) do
            if type(item) == "table" and type(item.url) == "string" and item.url ~= "" then
                streamUrl = item.url
                break
            end
        end
    end

    if type(streamUrl) ~= "string" or streamUrl == "" then
        return nil, "missing_stream_url"
    end
    if shouldAvoidUrl(streamUrl, avoidResolvedUrl) then
        return nil, "avoided_stream_url"
    end

    return {
        playableUrl = streamUrl,
        title = trimString(decoded.title) or trimString(decoded.filename),
        duration = normalizeDuration(decoded.duration),
        thumbnail = normalizeRemoteAssetUrl(decoded.thumbnail),
        provider = "cobalt",
        video = wantVideo ~= false,
    }, nil
end

local function resolveFromCobalt(url, wantVideo, avoidResolvedUrl, avoidInstance, callback)
    if not isCobaltEnabled() then
        callback(nil, "cobalt_disabled", makeTraceEntry("cobalt", "skipped", "cobalt_disabled"))
        return
    end

    local endpoints = collectConfiguredCobaltEndpoints()
    if #endpoints == 0 then
        callback(nil, "no_cobalt_endpoints", makeTraceEntry("cobalt", "skipped", "no_cobalt_endpoints"))
        return
    end

    local now = os.time()
    local normalizedAvoid = type(avoidInstance) == "string" and trimTrailingSlash(avoidInstance) or nil
    local filtered = {}
    for _, endpoint in ipairs(endpoints) do
        if endpoint ~= normalizedAvoid and not isInstanceSuppressed("cobalt", endpoint, now) then
            filtered[#filtered + 1] = endpoint
        end
    end
    if #filtered == 0 then
        filtered = shuffleCopy(endpoints)
    else
        filtered = shuffleCopy(filtered)
    end

    local maxAttempts = math.min(#filtered, getExtractorMaxAttempts())
    local requestPayload = buildCobaltRequestPayload(url, wantVideo)
    local headers = buildCobaltHeaders()

    local function tryEndpoint(index)
        if index > maxAttempts then
            callback(nil, "cobalt_unavailable", makeTraceEntry("cobalt", "failed", "cobalt_unavailable"))
            return
        end

        local endpoint = trimTrailingSlash(filtered[index])
        if not endpoint then
            tryEndpoint(index + 1)
            return
        end

        performPost(endpoint .. "/", requestPayload, getCobaltTimeoutMs(), function(statusCode, body)
            if statusCode ~= 200 or not body then
                local reason = classifyHttpFailure(statusCode)
                PMMSDebug("resolver", "cobalt endpoint failed", {
                    endpoint = endpoint,
                    statusCode = statusCode,
                    reason = reason,
                })
                markInstanceFailure("cobalt", endpoint, reason)
                tryEndpoint(index + 1)
                return
            end

            local jsonPayload = extractJsonPayload(body)
            if not jsonPayload then
                PMMSDebug("resolver", "cobalt endpoint returned non-json response", {
                    endpoint = endpoint,
                })
                markInstanceFailure("cobalt", endpoint, "non_json_response")
                tryEndpoint(index + 1)
                return
            end

            local ok, decoded = pcall(json.decode, jsonPayload)
            if not ok or type(decoded) ~= "table" then
                PMMSDebug("resolver", "cobalt endpoint response decode failed", {
                    endpoint = endpoint,
                })
                markInstanceFailure("cobalt", endpoint, "decode_failed")
                tryEndpoint(index + 1)
                return
            end

            local normalized, reason = normalizeCobaltPayload(decoded, wantVideo, avoidResolvedUrl)
            if not normalized then
                PMMSDebug("resolver", "cobalt endpoint did not return playable media", {
                    endpoint = endpoint,
                    status = decoded.status,
                    reason = reason or "invalid_payload",
                })
                markInstanceFailure("cobalt", endpoint, reason or "invalid_payload")
                tryEndpoint(index + 1)
                return
            end

            markInstanceHealthy("cobalt", endpoint)
            normalized.instance = endpoint
            PMMSDebug("resolver", "cobalt endpoint resolved media", {
                endpoint = endpoint,
                playableUrl = normalized.playableUrl,
                video = normalized.video,
            })
            callback(normalized, nil, makeTraceEntry("cobalt", "success", "resolved", { instance = endpoint }))
        end, headers)
    end

    tryEndpoint(1)
end

markInstanceFailure = function(provider, baseUrl, reason)
    if type(provider) ~= "string" or type(baseUrl) ~= "string" or baseUrl == "" then
        return
    end

    local providerFailures = instanceFailures[provider]
    if not providerFailures then
        return
    end

    providerFailures[baseUrl] = {
        reason = reason or "resolver_error",
        untilTs = os.time() + getInstanceFailureCooldownSeconds(),
    }
end

markInstanceHealthy = function(provider, baseUrl)
    if type(provider) ~= "string" or type(baseUrl) ~= "string" or baseUrl == "" then
        return
    end

    local providerFailures = instanceFailures[provider]
    if providerFailures then
        providerFailures[baseUrl] = nil
    end
end

isInstanceSuppressed = function(provider, baseUrl, now)
    local providerFailures = instanceFailures[provider]
    if not providerFailures then
        return false
    end

    local failure = providerFailures[baseUrl]
    if not failure then
        return false
    end

    now = now or os.time()
    if failure.untilTs and failure.untilTs > now then
        return true
    end

    providerFailures[baseUrl] = nil
    return false
end

local function collectConfiguredInstances()
    local configured = resolverConfig.instances or {}
    local invidious = {}
    local piped = {}
    local seenInvidious = {}
    local seenPiped = {}

    if type(configured.invidious) == "table" then
        for _, url in ipairs(configured.invidious) do
            pushUnique(invidious, seenInvidious, url)
        end
    end

    if type(configured.piped) == "table" then
        for _, url in ipairs(configured.piped) do
            pushUnique(piped, seenPiped, url)
        end
    end

    for _, url in ipairs(builtinResolverInstances.invidious) do
        pushUnique(invidious, seenInvidious, url)
    end

    for _, url in ipairs(builtinResolverInstances.piped) do
        pushUnique(piped, seenPiped, url)
    end

    return invidious, piped
end

local function isYoutubeUrl(url)
    if type(url) ~= "string" then
        return false
    end
    local lower = url:lower()
    return lower:find("youtube%.com", 1, false) ~= nil
        or lower:find("youtu%.be", 1, false) ~= nil
end

local function extractYoutubeId(url)
    if type(url) ~= "string" then
        return nil
    end

    local id = url:match("[?&]v=([%w_-]+)")
    if id then return id end

    id = url:match("youtu%.be/([%w_-]+)")
    if id then return id end

    id = url:match("/shorts/([%w_-]+)")
    if id then return id end

    id = url:match("/embed/([%w_-]+)")
    if id then return id end

    id = url:match("/live/([%w_-]+)")
    if id then return id end

    return nil
end

local function pickBestThumbnail(thumbnails)
    if type(thumbnails) ~= "table" then
        return nil
    end

    local best = nil
    local bestArea = -1

    for _, thumb in ipairs(thumbnails) do
        if type(thumb) == "table" and type(thumb.url) == "string" then
            local width = tonumber(thumb.width) or 0
            local height = tonumber(thumb.height) or 0
            local area = width * height

            if area > bestArea then
                best = thumb.url
                bestArea = area
            end
        end
    end

    return normalizeRemoteAssetUrl(best)
end

normalizeDuration = function(value)
    local duration = tonumber(value)
    if duration and duration > 0 then
        return math.floor(duration)
    end
    return nil
end

local function buildFallbackResult(url, reason, warning)
    return {
        ok = bool(resolverConfig.fallbackOnFailure, true),
        playableUrl = url,
        originalUrl = url,
        resolvedUrl = nil,
        status = "fallback",
        reason = reason or "resolver_unavailable",
        warning = warning,
        provider = nil,
    }
end

codecScore = function(mime)
    local score = 0
    local lowerMime = tostring(mime or ""):lower()

    if lowerMime:find("mp4", 1, true) then score = score + 500 end
    if lowerMime:find("avc1", 1, true) or lowerMime:find("h264", 1, true) then score = score + 450 end
    if lowerMime:find("m4a", 1, true) then score = score + 120 end
    if lowerMime:find("webm", 1, true) then score = score - 200 end
    if lowerMime:find("vp9", 1, true) or lowerMime:find("av01", 1, true) or lowerMime:find("av1", 1, true) then
        score = score - 350
    end

    return score
end

shouldAvoidUrl = function(streamUrl, avoidResolvedUrl)
    return type(avoidResolvedUrl) == "string"
        and avoidResolvedUrl ~= ""
        and type(streamUrl) == "string"
        and streamUrl == avoidResolvedUrl
end

local function chooseInvidiousStream(data, wantVideo, avoidResolvedUrl)
    if type(data) ~= "table" then
        return nil
    end

    if wantVideo and type(data.formatStreams) == "table" then
        local best
        local bestQuality = -999999
        for _, stream in ipairs(data.formatStreams) do
            if type(stream) == "table" and type(stream.url) == "string" then
                local mime = stream.type or stream.mimeType
                if shouldAvoidUrl(stream.url, avoidResolvedUrl) then
                    goto continue_format_stream
                end

                local quality = codecScore(mime)
                    + (tonumber(stream.bitrate) or tonumber(stream.qualityLabel and stream.qualityLabel:match("(%d+)")) or 0) / 1000
                if tostring(mime):lower():find("audio", 1, true) and tostring(mime):lower():find("video", 1, true) then
                    quality = quality + 120
                end
                if quality > bestQuality then
                    bestQuality = quality
                    best = stream.url
                end
            end
            ::continue_format_stream::
        end
        if best then return best end
    end

    if wantVideo and type(data.hlsUrl) == "string" and data.hlsUrl ~= "" then
        if not shouldAvoidUrl(data.hlsUrl, avoidResolvedUrl) then
            return data.hlsUrl
        end
    end

    if type(data.adaptiveFormats) == "table" then
        local best
        local bestScore = -999999
        for _, stream in ipairs(data.adaptiveFormats) do
            if type(stream) == "table" and type(stream.url) == "string" then
                local mime = tostring(stream.type or "")
                local isVideo = mime:find("video/", 1, true) ~= nil
                local isAudio = mime:find("audio/", 1, true) ~= nil
                if shouldAvoidUrl(stream.url, avoidResolvedUrl) then
                    goto continue_adaptive
                end

                if (not wantVideo and isAudio) or (wantVideo and isVideo and isAudio) then
                    local score = codecScore(mime) + (tonumber(stream.bitrate) or tonumber(stream.audioSampleRate) or 0) / 1000
                    if score > bestScore then
                        best = stream.url
                        bestScore = score
                    end
                end
            end
            ::continue_adaptive::
        end
        if best then return best end
    end

    return nil
end

local function choosePipedStream(data, wantVideo, avoidResolvedUrl)
    if type(data) ~= "table" then
        return nil
    end

    if wantVideo then
        if type(data.videoStreams) == "table" then
            local best
            local bestScore = -999999
            for _, stream in ipairs(data.videoStreams) do
                if type(stream) == "table" and type(stream.url) == "string" and stream.videoOnly ~= true then
                    if shouldAvoidUrl(stream.url, avoidResolvedUrl) then
                        goto continue_video_stream
                    end

                    local mime = stream.mimeType or stream.format or stream.codec
                    local score = codecScore(mime)
                        + (tonumber(stream.bitrate) or tonumber(stream.quality and tostring(stream.quality):match("(%d+)")) or 0) / 1000
                    if score > bestScore then
                        best = stream.url
                        bestScore = score
                    end
                end
                ::continue_video_stream::
            end
            if best then return best end
        end

        if type(data.hls) == "string" and data.hls ~= "" then
            if not shouldAvoidUrl(data.hls, avoidResolvedUrl) then
                return data.hls
            end
        end

        return nil
    end

    if type(data.audioStreams) == "table" then
        local best
        local bestScore = -999999
        for _, stream in ipairs(data.audioStreams) do
            if type(stream) == "table" and type(stream.url) == "string" then
                if shouldAvoidUrl(stream.url, avoidResolvedUrl) then
                    goto continue_audio_stream
                end

                local mime = stream.mimeType or stream.format or stream.codec
                local score = codecScore(mime) + (tonumber(stream.bitrate) or 0) / 1000
                if score > bestScore then
                    best = stream.url
                    bestScore = score
                end
            end
            ::continue_audio_stream::
        end
        if best then return best end
    end

    return nil
end

local function discoverInstances(forceRefresh, callback)
    if type(forceRefresh) == "function" then
        callback = forceRefresh
        forceRefresh = false
    end

    local now = os.time()
    if not forceRefresh and now < instanceCache.expiresAt and (#instanceCache.invidious > 0 or #instanceCache.piped > 0) then
        callback(instanceCache.invidious, instanceCache.piped)
        return
    end

    local configuredInvidious, configuredPiped = collectConfiguredInstances()
    local discoveredInvidious = {}
    local discoveredPiped = {}
    local seenInvidious = {}
    local seenPiped = {}

    for _, url in ipairs(configuredInvidious) do
        pushUnique(discoveredInvidious, seenInvidious, url)
    end
    for _, url in ipairs(configuredPiped) do
        pushUnique(discoveredPiped, seenPiped, url)
    end

    local immediateInvidious = #instanceCache.invidious > 0 and cloneTable(instanceCache.invidious) or cloneTable(discoveredInvidious)
    local immediatePiped = #instanceCache.piped > 0 and cloneTable(instanceCache.piped) or cloneTable(discoveredPiped)
    callback(immediateInvidious, immediatePiped)

    if instanceDiscoveryInFlight and forceRefresh ~= true then
        return
    end

    instanceDiscoveryInFlight = true
    local pending = 2
    local finished = false

    local function finalize()
        if finished then
            return
        end

        finished = true
        instanceDiscoveryInFlight = false

        if #discoveredInvidious > 0 then
            instanceCache.invidious = discoveredInvidious
        elseif #configuredInvidious > 0 then
            instanceCache.invidious = cloneTable(configuredInvidious)
        end

        if #discoveredPiped > 0 then
            instanceCache.piped = discoveredPiped
        elseif #configuredPiped > 0 then
            instanceCache.piped = cloneTable(configuredPiped)
        end

        instanceCache.expiresAt = os.time() + getCacheTtl()
    end

    local function finishOne()
        pending = pending - 1
        if pending <= 0 then
            finalize()
        end
    end

    SetTimeout(math.max(2500, getRequestTimeoutMs() + 500), function()
        finalize()
    end)

    performGet("https://api.invidious.io/instances.json", function(statusCode, body)
        if not finished and statusCode == 200 and body then
            local ok, decoded = pcall(json.decode, body)
            if ok and type(decoded) == "table" then
                for _, entry in ipairs(decoded) do
                    local info = type(entry) == "table" and entry[2] or nil
                    if type(info) == "table" and info.type == "https" and type(info.uri) == "string" then
                        local isDown = type(info.monitor) == "table" and info.monitor.down == true
                        if not isDown then
                            pushUnique(discoveredInvidious, seenInvidious, info.uri)
                        end
                    end
                end
            end
        end

        finishOne()
    end)

    performGet("https://piped-instances.kavin.rocks/", function(statusCode, body)
        if not finished and statusCode == 200 and body then
            local ok, decoded = pcall(json.decode, body)
            if ok and type(decoded) == "table" then
                for _, entry in ipairs(decoded) do
                    local apiUrl = type(entry) == "table" and entry.api_url or nil
                    if type(apiUrl) == "string" and apiUrl ~= "" then
                        pushUnique(discoveredPiped, seenPiped, apiUrl)
                    end
                end
            end
        end

        finishOne()
    end)
end

local function filterInstances(provider, instances, avoidInstance)
    if type(instances) ~= "table" then
        return {}
    end

    local normalizedAvoid = type(avoidInstance) == "string" and trimTrailingSlash(avoidInstance) or nil
    local now = os.time()
    local filtered = {}
    local fallback = {}
    for _, instance in ipairs(instances) do
        local normalized = trimTrailingSlash(instance)
        if normalized and normalized ~= "" and (not normalizedAvoid or normalized ~= normalizedAvoid) then
            local failure = instanceFailures[provider] and instanceFailures[provider][normalized] or nil
            local rank = failure and tonumber(failure.untilTs) or 0
            local order = #fallback + 1
            fallback[#fallback + 1] = {
                url = normalized,
                rank = rank,
                order = order,
            }
            if not isInstanceSuppressed(provider, normalized, now) then
                filtered[#filtered + 1] = {
                    url = normalized,
                    rank = rank,
                    order = order,
                }
            end
        end
    end

    local function sortRanked(list)
        table.sort(list, function(a, b)
            if (a.rank or 0) == (b.rank or 0) then
                return (a.order or 0) < (b.order or 0)
            end
            return (a.rank or 0) < (b.rank or 0)
        end)

        local ordered = {}
        for _, entry in ipairs(list) do
            ordered[#ordered + 1] = entry.url
        end
        return ordered
    end

    if #filtered == 0 then
        return sortRanked(fallback)
    end

    return sortRanked(filtered)
end

local function resolveInvidiousInstance(baseUrl, videoId, wantVideo, avoidResolvedUrl, callback)
    performGet(("%s/api/v1/videos/%s"):format(baseUrl, videoId), function(statusCode, body)
        if statusCode ~= 200 or not body then
            local reason = classifyHttpFailure(statusCode)
            PMMSDebug("resolver", "invidious instance failed", {
                instance = baseUrl,
                videoId = videoId,
                statusCode = statusCode,
                reason = reason,
            })
            markInstanceFailure("invidious", baseUrl, reason)
            callback(nil, reason)
            return
        end

        if not bodyLooksLikeJson(body) then
            PMMSDebug("resolver", "invidious instance returned non-json response", {
                instance = baseUrl,
                videoId = videoId,
            })
            markInstanceFailure("invidious", baseUrl, "non_json_response")
            callback(nil, "non_json_response")
            return
        end

        local ok, decoded = pcall(json.decode, body)
        if not ok or type(decoded) ~= "table" then
            PMMSDebug("resolver", "invidious response decode failed", {
                instance = baseUrl,
                videoId = videoId,
            })
            markInstanceFailure("invidious", baseUrl, "decode_failed")
            callback(nil, "decode_failed")
            return
        end

        local upstreamError = classifyUpstreamError(decoded)
        if upstreamError then
            PMMSDebug("resolver", "invidious upstream error", {
                instance = baseUrl,
                videoId = videoId,
                reason = upstreamError,
            })
            markInstanceFailure("invidious", baseUrl, upstreamError)
            callback(nil, upstreamError)
            return
        end

        local streamUrl = chooseInvidiousStream(decoded, wantVideo, avoidResolvedUrl)
        if type(streamUrl) == "string" and streamUrl ~= "" then
            markInstanceHealthy("invidious", baseUrl)
            PMMSDebug("resolver", "invidious instance resolved media", {
                instance = baseUrl,
                videoId = videoId,
                wantVideo = wantVideo,
                streamUrl = streamUrl,
            })
            callback({
                playableUrl = streamUrl,
                title = decoded.title,
                author = decoded.author,
                duration = normalizeDuration(decoded.lengthSeconds),
                thumbnail = pickBestThumbnail(decoded.videoThumbnails),
                provider = "invidious",
                instance = baseUrl,
            }, nil)
            return
        end

        PMMSDebug("resolver", "invidious instance had no compatible stream", {
            instance = baseUrl,
            videoId = videoId,
            wantVideo = wantVideo,
        })
        callback(nil, wantVideo and "no_compatible_video_stream" or "no_compatible_stream")
    end)
end

local function resolvePipedInstance(baseUrl, videoId, wantVideo, avoidResolvedUrl, callback)
    performGet(("%s/streams/%s"):format(baseUrl, videoId), function(statusCode, body)
        if statusCode ~= 200 or not body then
            local reason = classifyHttpFailure(statusCode)
            PMMSDebug("resolver", "piped instance failed", {
                instance = baseUrl,
                videoId = videoId,
                statusCode = statusCode,
                reason = reason,
            })
            markInstanceFailure("piped", baseUrl, reason)
            callback(nil, reason)
            return
        end

        if not bodyLooksLikeJson(body) then
            PMMSDebug("resolver", "piped instance returned non-json response", {
                instance = baseUrl,
                videoId = videoId,
            })
            markInstanceFailure("piped", baseUrl, "non_json_response")
            callback(nil, "non_json_response")
            return
        end

        local ok, decoded = pcall(json.decode, body)
        if not ok or type(decoded) ~= "table" then
            PMMSDebug("resolver", "piped response decode failed", {
                instance = baseUrl,
                videoId = videoId,
            })
            markInstanceFailure("piped", baseUrl, "decode_failed")
            callback(nil, "decode_failed")
            return
        end

        local upstreamError = classifyUpstreamError(decoded)
        if upstreamError then
            PMMSDebug("resolver", "piped upstream error", {
                instance = baseUrl,
                videoId = videoId,
                reason = upstreamError,
            })
            markInstanceFailure("piped", baseUrl, upstreamError)
            callback(nil, upstreamError)
            return
        end

        local streamUrl = choosePipedStream(decoded, wantVideo, avoidResolvedUrl)
        if type(streamUrl) == "string" and streamUrl ~= "" then
            markInstanceHealthy("piped", baseUrl)
            PMMSDebug("resolver", "piped instance resolved media", {
                instance = baseUrl,
                videoId = videoId,
                wantVideo = wantVideo,
                streamUrl = streamUrl,
            })
            callback({
                playableUrl = streamUrl,
                title = decoded.title,
                author = decoded.uploader or decoded.uploaderName,
                duration = normalizeDuration(decoded.duration),
                thumbnail = normalizeRemoteAssetUrl(decoded.thumbnailUrl),
                provider = "piped",
                instance = baseUrl,
            }, nil)
            return
        end

        PMMSDebug("resolver", "piped instance had no compatible stream", {
            instance = baseUrl,
            videoId = videoId,
            wantVideo = wantVideo,
        })
        callback(nil, wantVideo and "no_compatible_video_stream" or "no_compatible_stream")
    end)
end

local function resolveAcrossInstances(instances, maxInstances, wantVideo, resolveInstance, callback)
    local total = math.min(#instances, math.max(1, maxInstances))
    if total <= 0 then
        callback(nil, nil)
        return
    end

    local nextIndex = 1
    local active = 0
    local finished = false
    local sawNoCompatibleStream = false
    local parallelLimit = math.min(getParallelInstancesPerProvider(), total)

    local function maybeFinish()
        if finished or active > 0 or nextIndex <= total then
            return
        end

        finished = true
        if wantVideo and sawNoCompatibleStream then
            callback(nil, "no_compatible_video_stream")
            return
        end

        callback(nil, nil)
    end

    local function launchNext()
        if finished then
            return
        end

        while active < parallelLimit and nextIndex <= total do
            local instanceIndex = nextIndex
            local baseUrl = trimTrailingSlash(instances[instanceIndex])
            nextIndex = nextIndex + 1

            if not baseUrl then
                maybeFinish()
            else
                active = active + 1
                resolveInstance(baseUrl, function(payload, reason)
                    active = active - 1
                    if finished then
                        return
                    end

                    if payload then
                        finished = true
                        callback(payload, nil)
                        return
                    end

                    if wantVideo and reason == "no_compatible_video_stream" then
                        sawNoCompatibleStream = true
                    end

                    launchNext()
                    maybeFinish()
                end)
            end
        end

        maybeFinish()
    end

    launchNext()
end

local function hasProvider(order, providerName)
    for _, provider in ipairs(order or {}) do
        if provider == providerName then
            return true
        end
    end
    return false
end

local function getProviderOrder(avoidProvider, allowEmbedFallback)
    local configured = getConfiguredProviderOrder()
    if allowEmbedFallback == true and not hasProvider(configured, "embed") then
        configured[#configured + 1] = "embed"
    end

    if type(avoidProvider) ~= "string" or avoidProvider == "" then
        return configured
    end

    local preferred = {}
    local deferred = {}
    for _, provider in ipairs(configured) do
        if provider == avoidProvider then
            deferred[#deferred + 1] = provider
        else
            preferred[#preferred + 1] = provider
        end
    end

    for _, provider in ipairs(deferred) do
        preferred[#preferred + 1] = provider
    end

    return preferred
end

local function resolveYoutubeStream(url, options, resolverOptions, callback)
    resolverOptions = resolverOptions or {}

    local videoId = extractYoutubeId(url)
    if not videoId then
        PMMSDebug("resolver", "invalid YouTube URL", {
            url = url,
        })
        callback({
            ok = false,
            reason = "invalid_youtube_url",
            warning = "Could not parse YouTube URL.",
            trace = { makeTraceEntry("youtube", "failed", "invalid_youtube_url") },
        })
        return
    end

    local wantVideo = not (options and options.video == false)
    local allowAudioFallback = isAudioFallbackAllowed(resolverOptions)
    local allowEmbedFallback = isEmbedFallbackAllowed(resolverOptions)
    local forceRefresh = resolverOptions.forceRefresh == true
    local cacheKey = ("v5:%s:%s"):format(videoId, wantVideo and "video" or "audio")
    local now = os.time()
    local cached = resolveCache[cacheKey]
    if not forceRefresh and cached and cached.expiresAt > now then
        local cachedPayload = cached.payload or {}
        local cachedProvider = cachedPayload.provider
        local cachedInstance = cachedPayload.instance
        local cachedResolvedUrl = cachedPayload.resolvedUrl or cachedPayload.playableUrl
        local shouldBypassCached = false

        if type(cachedProvider) == "string"
            and type(cachedInstance) == "string"
            and isInstanceSuppressed(cachedProvider, cachedInstance, now) then
            shouldBypassCached = true
        end

        if allowEmbedFallback == false and (cachedPayload.status == "fallback" or cachedProvider == "embed") then
            shouldBypassCached = true
            PMMSDebug("resolver", "cached embed fallback ignored because embed fallback is disabled", {
                url = url,
                provider = cachedProvider,
                instance = cachedInstance,
                status = cachedPayload.status,
            })
        end

        if type(resolverOptions.avoidResolvedUrl) == "string"
            and resolverOptions.avoidResolvedUrl ~= ""
            and cachedResolvedUrl == resolverOptions.avoidResolvedUrl then
            shouldBypassCached = true
        end

        if type(resolverOptions.avoidProvider) == "string"
            and resolverOptions.avoidProvider ~= ""
            and cachedProvider == resolverOptions.avoidProvider then
            shouldBypassCached = true
        end

        if type(resolverOptions.avoidInstance) == "string"
            and resolverOptions.avoidInstance ~= ""
            and cachedInstance == resolverOptions.avoidInstance then
            shouldBypassCached = true
        end

        if not shouldBypassCached then
            PMMSDebug("resolver", "using cached resolver result", {
                url = url,
                provider = cachedProvider,
                instance = cachedInstance,
                status = cachedPayload.status,
                resolvedUrl = cachedResolvedUrl,
            })
            callback(cloneTable(cached.payload))
            return
        end
        PMMSDebug("resolver", "resolver cache bypassed", {
            url = url,
            provider = cachedProvider,
            instance = cachedInstance,
            status = cachedPayload.status,
            avoidProvider = resolverOptions.avoidProvider,
            avoidInstance = resolverOptions.avoidInstance,
            avoidResolvedUrl = resolverOptions.avoidResolvedUrl,
        })
    end

    local trace = {}
    local function addTrace(entry)
        if type(entry) == "table" then
            trace[#trace + 1] = entry
        end
    end

    discoverInstances(forceRefresh, function(invidiousInstances, pipedInstances)
        local maxInstances = math.max(1, tonumber(resolverOptions.maxInstances) or getMaxInstances())
        local avoidResolvedUrl = resolverOptions.avoidResolvedUrl
        local order = getProviderOrder(resolverOptions.avoidProvider, allowEmbedFallback)
        local filteredInvidious = filterInstances("invidious", invidiousInstances, resolverOptions.avoidInstance)
        local filteredPiped = filterInstances("piped", pipedInstances, resolverOptions.avoidInstance)
        local cobaltEndpoints = collectConfiguredCobaltEndpoints()
        local finalFailureReason = nil

        PMMSDebug("resolver", "provider order selected", {
            url = url,
            videoId = videoId,
            wantVideo = wantVideo,
            allowAudioFallback = allowAudioFallback,
            allowEmbedFallback = allowEmbedFallback,
            forceRefresh = forceRefresh,
            avoidProvider = resolverOptions.avoidProvider,
            avoidInstance = resolverOptions.avoidInstance,
            providerOrder = table.concat(order, " > "),
            cobaltCount = #cobaltEndpoints,
            invidiousCount = #filteredInvidious,
            pipedCount = #filteredPiped,
        })

        local function onResolved(payload, resolveReason)
            if payload then
                payload.ok = true
                payload.originalUrl = url
                payload.resolvedUrl = payload.playableUrl
                payload.status = payload.status or "resolved"
                payload.reason = payload.reason or resolveReason or "resolved_stream"
                payload.trace = type(payload.trace) == "table" and payload.trace or trace

                if payload.status == "resolved" then
                    resolveCache[cacheKey] = {
                        expiresAt = now + getCacheTtl(),
                        payload = cloneTable(payload),
                    }
                end

                PMMSDebug("resolver", "provider resolved playable source", {
                    url = url,
                    status = payload.status,
                    reason = payload.reason,
                    provider = payload.provider,
                    instance = payload.instance,
                    resolvedUrl = payload.resolvedUrl or payload.playableUrl,
                    video = payload.video,
                    warning = payload.warning,
                })
                callback(payload)
                return
            end

            if wantVideo
                and resolverOptions.audioFallbackAttempted ~= true
                and allowAudioFallback then
                PMMSDebug("resolver", "video providers failed, trying audio-only fallback", {
                    url = url,
                    reason = finalFailureReason,
                    trace = summarizeTrace(trace),
                })
                local audioOptions = cloneTable(options)
                audioOptions.video = false

                local audioResolverOptions = cloneTable(resolverOptions)
                audioResolverOptions.allowFallback = false
                audioResolverOptions.allowEmbedFallback = false
                audioResolverOptions.forceRefresh = true
                audioResolverOptions.audioFallbackAttempted = true
                audioResolverOptions.allowAudioFallback = false

                resolveYoutubeStream(url, audioOptions, audioResolverOptions, function(audioResult)
                    if audioResult and audioResult.ok then
                        local mergedTrace = {}
                        for _, entry in ipairs(trace) do
                            mergedTrace[#mergedTrace + 1] = entry
                        end
                        mergedTrace[#mergedTrace + 1] = makeTraceEntry("audio_fallback", "success", "video_unavailable")
                        if type(audioResult.trace) == "table" then
                            for _, entry in ipairs(audioResult.trace) do
                                mergedTrace[#mergedTrace + 1] = entry
                            end
                        end

                        audioResult.video = false
                        audioResult.reason = "audio_only_fallback"
                        audioResult.trace = mergedTrace
                        audioResult.warning = "Video stream unavailable. Switched to audio-only fallback. " .. summarizeTrace(mergedTrace)
                        PMMSDebug("resolver", "audio-only fallback resolved", {
                            url = url,
                            provider = audioResult.provider,
                            instance = audioResult.instance,
                            resolvedUrl = audioResult.resolvedUrl or audioResult.playableUrl,
                        })
                        onResolved(audioResult, "resolved_audio_fallback")
                        return
                    end

                    addTrace(makeTraceEntry("audio_fallback", "failed", "audio_resolve_failed"))
                    if allowEmbedFallback then
                        PMMSDebug("resolver", "audio fallback failed, selecting embed fallback because it is enabled", {
                            url = url,
                        })
                        addTrace(makeTraceEntry("embed", "fallback", "embed_selected"))
                        local embedPayload = buildFallbackResult(url, "embed_fallback", "Using embedded YouTube as final fallback.")
                        embedPayload.provider = "embed"
                        embedPayload.instance = "youtube_embed"
                        onResolved(embedPayload, "embed_fallback")
                        return
                    end

                    local warning = "No ad-free playable source found. " .. summarizeTrace(trace)
                    PMMSDebug("resolver", "all ad-free providers failed", {
                        url = url,
                        reason = finalFailureReason or "no_ad_free_source",
                        warning = warning,
                    })
                    print(("[7-pmms] Resolver failure: %s | %s"):format(url, warning))
                    callback({
                        ok = false,
                        reason = finalFailureReason or "no_ad_free_source",
                        warning = warning,
                        trace = trace,
                    })
                end)
                return
            end

            if not allowEmbedFallback then
                local warning = "No ad-free playable source found. " .. summarizeTrace(trace)
                PMMSDebug("resolver", "embed fallback disabled, failing cleanly", {
                    url = url,
                    reason = resolveReason or finalFailureReason or "no_ad_free_source",
                    warning = warning,
                })
                print(("[7-pmms] Resolver failure: %s | %s"):format(url, warning))
                callback({
                    ok = false,
                    reason = resolveReason or finalFailureReason or "no_ad_free_source",
                    warning = warning,
                    trace = trace,
                })
                return
            end

            local reason = resolveReason or finalFailureReason or "resolver_unavailable"
            local warning = "YouTube resolver unavailable. Falling back to embedded YouTube playback (some videos may fail). " .. summarizeTrace(trace)
            if reason == "no_compatible_video_stream" then
                warning = "No compatible ad-free video stream was found. Falling back to embedded YouTube playback. " .. summarizeTrace(trace)
            end

            local fallback = buildFallbackResult(url, reason, warning)
            fallback.provider = "embed"
            fallback.instance = "youtube_embed"
            fallback.trace = trace
            PMMSDebug("resolver", "embed fallback selected", {
                url = url,
                reason = reason,
                warning = warning,
            })
            callback(fallback)
        end

        local function tryProvider(index)
            if index > #order then
                PMMSDebug("resolver", "provider chain exhausted", {
                    url = url,
                    reason = finalFailureReason or "resolver_unavailable",
                })
                onResolved(nil, finalFailureReason or "resolver_unavailable")
                return
            end

            local provider = order[index]
            PMMSDebug("resolver", "trying provider", {
                url = url,
                provider = provider,
                index = index,
                total = #order,
            })
            if provider == "yt_dlp_local" then
                resolveFromYtDlp(url, wantVideo, avoidResolvedUrl, function(payload, reason, traceEntry)
                    addTrace(traceEntry or makeTraceEntry("yt_dlp_local", payload and "success" or "failed", reason or "unknown"))
                    if payload then
                        onResolved(payload, "resolved_yt_dlp_local")
                        return
                    end
                    PMMSDebug("resolver", "provider failed", {
                        url = url,
                        provider = "yt_dlp_local",
                        reason = reason or "unknown",
                    })
                    finalFailureReason = reason or finalFailureReason
                    tryProvider(index + 1)
                end)
            elseif provider == "extractor_http" then
                resolveFromHttpExtractor(url, wantVideo, avoidResolvedUrl, function(payload, reason, traceEntry)
                    addTrace(traceEntry or makeTraceEntry("extractor_http", payload and "success" or "failed", reason or "unknown"))
                    if payload then
                        onResolved(payload, "resolved_extractor_http")
                        return
                    end
                    PMMSDebug("resolver", "provider failed", {
                        url = url,
                        provider = "extractor_http",
                        reason = reason or "unknown",
                    })
                    finalFailureReason = reason or finalFailureReason
                    tryProvider(index + 1)
                end)
            elseif provider == "cobalt" then
                resolveFromCobalt(url, wantVideo, avoidResolvedUrl, resolverOptions.avoidInstance, function(payload, reason, traceEntry)
                    addTrace(traceEntry or makeTraceEntry("cobalt", payload and "success" or "failed", reason or "unknown"))
                    if payload then
                        onResolved(payload, "resolved_cobalt")
                        return
                    end
                    PMMSDebug("resolver", "provider failed", {
                        url = url,
                        provider = "cobalt",
                        reason = reason or "unknown",
                    })
                    finalFailureReason = reason or finalFailureReason
                    tryProvider(index + 1)
                end)
            elseif provider == "invidious" then
                resolveAcrossInstances(filteredInvidious, maxInstances, wantVideo, function(baseUrl, done)
                    resolveInvidiousInstance(baseUrl, videoId, wantVideo, avoidResolvedUrl, done)
                end, function(payload, reason)
                    if payload then
                        addTrace(makeTraceEntry("invidious", "success", "resolved", { instance = payload.instance }))
                        onResolved(payload, "resolved_invidious")
                        return
                    end
                    addTrace(makeTraceEntry("invidious", "failed", reason or "resolver_unavailable"))
                    PMMSDebug("resolver", "provider failed", {
                        url = url,
                        provider = "invidious",
                        reason = reason or "resolver_unavailable",
                    })
                    finalFailureReason = reason or finalFailureReason
                    tryProvider(index + 1)
                end)
            elseif provider == "piped" then
                resolveAcrossInstances(filteredPiped, maxInstances, wantVideo, function(baseUrl, done)
                    resolvePipedInstance(baseUrl, videoId, wantVideo, avoidResolvedUrl, done)
                end, function(payload, reason)
                    if payload then
                        addTrace(makeTraceEntry("piped", "success", "resolved", { instance = payload.instance }))
                        onResolved(payload, "resolved_piped")
                        return
                    end
                    addTrace(makeTraceEntry("piped", "failed", reason or "resolver_unavailable"))
                    PMMSDebug("resolver", "provider failed", {
                        url = url,
                        provider = "piped",
                        reason = reason or "resolver_unavailable",
                    })
                    finalFailureReason = reason or finalFailureReason
                    tryProvider(index + 1)
                end)
            elseif provider == "embed" then
                if allowEmbedFallback then
                    PMMSDebug("resolver", "embed fallback provider reached", {
                        url = url,
                    })
                    addTrace(makeTraceEntry("embed", "fallback", "embed_selected"))
                    local embedPayload = buildFallbackResult(url, "embed_fallback", "Using embedded YouTube as final fallback.")
                    embedPayload.provider = "embed"
                    embedPayload.instance = "youtube_embed"
                    onResolved(embedPayload, "embed_fallback")
                    return
                end
                addTrace(makeTraceEntry("embed", "skipped", "fallback_disabled"))
                PMMSDebug("resolver", "embed provider skipped because fallback is disabled", {
                    url = url,
                })
                tryProvider(index + 1)
            else
                addTrace(makeTraceEntry(provider, "skipped", "unknown_provider"))
                PMMSDebug("resolver", "unknown provider skipped", {
                    url = url,
                    provider = provider,
                })
                tryProvider(index + 1)
            end
        end

        tryProvider(1)
    end)
end

function ResolvePlaybackOptions(options, resolverOptions, callback)
    resolverOptions = resolverOptions or {}

    local sourceUrl = options and options.url or nil
    if type(sourceUrl) ~= "string" or sourceUrl == "" then
        callback(false, nil, "Invalid playback URL.")
        return
    end

    local inflightKey = buildResolveInflightKey(options, resolverOptions)
    local inflight = resolverOptions.forceRefresh ~= true and resolveInflight[inflightKey] or nil
    if inflight then
        PMMSDebug("resolver", "joining in-flight resolve", {
            url = sourceUrl,
            inflightKey = inflightKey,
            listeners = #inflight,
        })
        inflight[#inflight + 1] = callback
        return
    end

    if resolverOptions.forceRefresh ~= true then
        resolveInflight[inflightKey] = { callback }
    end

    local function finalize(ok, resolvedOptions, warning)
        local listeners = resolveInflight[inflightKey]
        if listeners then
            resolveInflight[inflightKey] = nil
            for _, listener in ipairs(listeners) do
                listener(ok, resolvedOptions and cloneTable(resolvedOptions) or nil, warning)
            end
            return
        end

        callback(ok, resolvedOptions, warning)
    end

    local resolved = cloneTable(options)
    resolved.originalUrl = resolved.originalUrl or sourceUrl
    resolved.resolvedUrl = resolved.resolvedUrl
    resolved.resolver = resolved.resolver or {}

    if not isResolverEnabled() or not isYoutubeUrl(sourceUrl) then
        resolved.resolvedUrl = resolved.resolvedUrl or sourceUrl
        resolved.resolver.status = "bypass"
        resolved.resolver.reason = "bypass"
        PMMSDebug("resolver", "resolver bypassed", {
            url = sourceUrl,
            enabled = isResolverEnabled(),
            youtube = isYoutubeUrl(sourceUrl),
        })
        finalize(true, resolved, nil)
        return
    end

    resolveYoutubeStream(sourceUrl, options, resolverOptions, function(result)
        if not result or not result.ok then
            if result and type(result.trace) == "table" then
                local traceEncoded = "[]"
                local okTrace, encodedTrace = pcall(json.encode, result.trace)
                if okTrace and type(encodedTrace) == "string" then
                    traceEncoded = encodedTrace
                end
                print(("[7-pmms] Resolver failed for %s: %s | trace=%s"):format(
                    sourceUrl,
                    result.reason or "resolver_unavailable",
                    traceEncoded
                ))
            end
            PMMSDebug("resolver", "resolve finished as failure", {
                url = sourceUrl,
                reason = result and result.reason or "resolver_unavailable",
                warning = result and result.warning or "Resolver failed.",
            })
            finalize(false, nil, result and result.warning or "Resolver failed.")
            return
        end

        resolved.url = result.playableUrl or sourceUrl
        resolved.originalUrl = sourceUrl
        resolved.resolvedUrl = result.resolvedUrl
        resolved.resolver = {
            status = result.status,
            reason = result.reason,
            provider = result.provider,
            instance = result.instance,
            warning = result.warning,
            trace = result.trace or {},
            resolvedAt = os.time(),
        }

        if (not resolved.title or resolved.title == "" or resolved.title == sourceUrl) and type(result.title) == "string" and result.title ~= "" then
            resolved.title = result.title
        end

        if (not resolved.author or resolved.author == "") and type(result.author) == "string" then
            resolved.author = result.author
        end

        if (not resolved.thumbnail or resolved.thumbnail == "") and type(result.thumbnail) == "string" then
            resolved.thumbnail = normalizeRemoteAssetUrl(result.thumbnail) or resolved.thumbnail
        end

        if not resolved.duration then
            resolved.duration = normalizeDuration(result.duration)
        end

        if result.video == false then
            resolved.video = false
        end

        finalize(true, resolved, result.warning)
    end)
end

Citizen.CreateThread(function()
    Citizen.Wait(1500)
    if not isResolverEnabled() then
        PMMSDebug("resolver", "resolver preflight skipped because resolver is disabled")
        return
    end

    local cobaltEndpoints = collectConfiguredCobaltEndpoints()
    local ytDlpAvailable, ytDlpReason = ensureYtDlpAvailability(os.time())
    local configuredInvidious, configuredPiped = collectConfiguredInstances()

    PMMSDebug("resolver", "resolver preflight", {
        ytDlpAvailable = ytDlpAvailable,
        ytDlpReason = ytDlpReason,
        cobaltEndpoints = #cobaltEndpoints,
        invidiousConfigured = #configuredInvidious,
        pipedConfigured = #configuredPiped,
        allowAudioFallback = isAudioFallbackAllowed({}),
        allowEmbedFallback = isEmbedFallbackAllowed({}),
    })

    if not ytDlpAvailable and #cobaltEndpoints == 0 and not isEmbedFallbackAllowed({}) then
        print(("[7-pmms] Resolver preflight: yt-dlp is unavailable (%s) and no Cobalt endpoint is configured. YouTube playback will depend on public Invidious/Piped instances and may fail."):format(tostring(ytDlpReason or "unknown")))
    end
end)

exports("resolvePlaybackOptions", ResolvePlaybackOptions)
