local resolverConfig = Config.resolver or {}

local resolveCache = {}
local resolveInflight = {}
local cancelledResolves = {}
local providerCooldowns = {}
local providerStats = nil
local providerStatsSavePending = false
local globalActiveResolves = 0
local globalResolveQueue = {}

local builtinInstances = {
	invidious = {
		"https://inv.nadeko.net",
		"https://inv.thepixora.com",
		"https://invidious.privacydev.net",
	},
	piped = {
		"https://api.piped.private.coffee",
		"https://pipedapi.kavin.rocks",
		"https://piped-api.privacy.com.de",
	},
}

local function nowMs()
	if type(GetGameTimer) == "function" then
		return GetGameTimer()
	end
	return math.floor((os.clock() or 0) * 1000)
end

local function cloneValue(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value) do
		copy[key] = cloneValue(item)
	end
	return copy
end

local function trim(value)
	if type(value) ~= "string" then
		return ""
	end
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function bool(value, fallback)
	if value == nil then
		return fallback
	end
	return value == true
end

local function normalizeBaseUrl(url)
	url = trim(url)
	if url == "" or not url:match("^https?://") then
		return nil
	end
	return (url:gsub("/+$", ""))
end

local function urlEncode(value)
	value = tostring(value or "")
	value = value:gsub("\n", "\r\n")
	value = value:gsub("([^%w%-%_%.%~])", function(char)
		return string.format("%%%02X", string.byte(char))
	end)
	return value
end

local function isYoutubeUrl(url)
	url = tostring(url or ""):lower()
	return url:find("youtube%.com", 1, false) ~= nil
		or url:find("youtu%.be", 1, false) ~= nil
		or url:find("youtube%-nocookie%.com", 1, false) ~= nil
end

local function extractYoutubeId(url)
	url = tostring(url or "")
	local id = url:match("[?&]v=([%w%-_]+)")
		or url:match("youtu%.be/([%w%-_]+)")
		or url:match("/shorts/([%w%-_]+)")
		or url:match("/embed/([%w%-_]+)")
	if type(id) == "string" then
		id = id:match("^([%w%-_]+)")
	end
	if id and #id >= 6 then
		return id
	end
	return nil
end

local function redactUrlForDebug(url)
	if type(url) ~= "string" then
		return url
	end
	local redacted = url:gsub("[?#].*$", "?<redacted>")
	if #redacted > 180 then
		return redacted:sub(1, 177) .. "..."
	end
	return redacted
end

local function getCacheTtlSeconds()
	return math.max(30, tonumber(resolverConfig.cacheTtlSeconds) or 3300)
end

local function makeHourlySlots()
	local slots = {}
	for hour = 1, 24 do
		slots[hour] = {
			successes = 0,
			failures = 0,
			fakeSuccesses = 0,
			totalMs = 0,
		}
	end
	return slots
end

local function currentHourSlot()
	return tonumber(os.date("!%H")) + 1
end

local function getProviderStatsConfig()
	local adaptive = type(resolverConfig.adaptiveProviderRanking) == "table" and resolverConfig.adaptiveProviderRanking or {}
	return {
		enabled = adaptive.enabled ~= false,
		dataFile = type(adaptive.dataFile) == "string" and adaptive.dataFile ~= "" and adaptive.dataFile or "data/provider_stats.json",
		saveDebounceMs = math.max(500, tonumber(adaptive.saveDebounceMs) or 5000),
	}
end

local function decodeJson(body)
	if type(body) ~= "string" or body == "" then
		return nil
	end
	local ok, decoded = pcall(json.decode, body)
	if ok and type(decoded) == "table" then
		return decoded
	end
	return nil
end

local function loadProviderStats()
	if providerStats then
		return providerStats
	end
	providerStats = {
		version = 2,
		totalAttempts = 0,
		totalCompletedAutoPlays = 0,
		providers = {},
	}
	local cfg = getProviderStatsConfig()
	local raw = LoadResourceFile(GetCurrentResourceName(), cfg.dataFile)
	local decoded = decodeJson(raw)
	if decoded then
		providerStats.totalAttempts = tonumber(decoded.totalAttempts) or 0
		providerStats.totalCompletedAutoPlays = tonumber(decoded.totalCompletedAutoPlays) or 0
		providerStats.providers = type(decoded.providers) == "table" and decoded.providers or {}
	end
	return providerStats
end

local function saveProviderStatsSoon()
	local cfg = getProviderStatsConfig()
	if cfg.enabled ~= true or providerStatsSavePending then
		return
	end
	providerStatsSavePending = true
	CreateThread(function()
		Wait(cfg.saveDebounceMs)
		providerStatsSavePending = false
		local ok, encoded = pcall(json.encode, loadProviderStats())
		if ok and type(encoded) == "string" then
			SaveResourceFile(GetCurrentResourceName(), cfg.dataFile, encoded, -1)
		end
	end)
end

local function getProviderStat(provider)
	local stats = loadProviderStats()
	local item = stats.providers[provider]
	if type(item) ~= "table" then
		item = {
			provider = provider,
			successes = 0,
			failures = 0,
			fakeSuccesses = 0,
			totalMs = 0,
			consecutiveFailures = 0,
			hours = makeHourlySlots(),
		}
		stats.providers[provider] = item
	end
	if type(item.hours) ~= "table" or #item.hours < 24 then
		item.hours = makeHourlySlots()
	end
	for hour = 1, 24 do
		if type(item.hours[hour]) ~= "table" then
			item.hours[hour] = {
				successes = 0,
				failures = 0,
				fakeSuccesses = 0,
				totalMs = 0,
			}
		end
	end
	return item
end

local function scoreProvider(provider)
	local item = getProviderStat(provider)
	local hour = currentHourSlot()
	local weights = {
		{ hour, 3 },
		{ ((hour + 22) % 24) + 1, 2 },
		{ (hour % 24) + 1, 2 },
		{ ((hour + 21) % 24) + 1, 1 },
		{ ((hour + 1) % 24) + 1, 1 },
	}
	local weightedSamples = 0
	local successWeight = 0
	local latencyWeight = 0
	for _, pair in ipairs(weights) do
		local slot = item.hours[pair[1]]
		local weight = pair[2]
		local successes = tonumber(slot.successes) or 0
		local failures = (tonumber(slot.failures) or 0) + (tonumber(slot.fakeSuccesses) or 0)
		local total = successes + failures
		if total > 0 then
			weightedSamples = weightedSamples + weight
			successWeight = successWeight + ((successes / total) * weight)
			local avgMs = successes > 0 and ((tonumber(slot.totalMs) or 0) / successes) or 15000
			latencyWeight = latencyWeight + (avgMs * weight)
		end
	end
	if weightedSamples == 0 then
		return 0.5
	end
	local successScore = successWeight / weightedSamples
	local latencyScore = math.max(0, 1 - ((latencyWeight / weightedSamples) / 12000))
	return (successScore * 0.7) + (latencyScore * 0.3)
end

local function getProviderTimeoutMs(provider)
	local extractor = type(resolverConfig.extractor) == "table" and resolverConfig.extractor or {}
	local providers = type(extractor.providers) == "table" and extractor.providers or {}
	local providerConfig = type(providers[provider]) == "table" and providers[provider] or {}
	local seconds = tonumber(providerConfig.timeoutSeconds)
	if seconds and seconds > 0 then
		return math.floor(seconds * 1000)
	end
	return math.max(2500, tonumber(resolverConfig.timeoutMs) or 5500)
end

local function getAbsoluteTimeoutMs()
	local extractor = type(resolverConfig.extractor) == "table" and resolverConfig.extractor or {}
	local seconds = tonumber(extractor.absoluteTimeoutSeconds) or 12
	return math.max(4000, math.floor(seconds * 1000))
end

local function getGlobalLimit()
	local extractor = type(resolverConfig.extractor) == "table" and resolverConfig.extractor or {}
	return math.max(1, math.floor(tonumber(extractor.maxGlobalConcurrent) or tonumber(resolverConfig.maxGlobalConcurrent) or 10))
end

local function acquireGlobalSlot(callback)
	if globalActiveResolves < getGlobalLimit() then
		globalActiveResolves = globalActiveResolves + 1
		callback()
		return
	end
	globalResolveQueue[#globalResolveQueue + 1] = callback
end

local function releaseGlobalSlot()
	globalActiveResolves = math.max(0, globalActiveResolves - 1)
	local nextCallback = table.remove(globalResolveQueue, 1)
	if nextCallback then
		globalActiveResolves = globalActiveResolves + 1
		CreateThread(function()
			nextCallback()
		end)
	end
end

local function cleanupCancelledResolves()
	local now = nowMs()
	for key, state in pairs(cancelledResolves) do
		if (tonumber(state.expiresAt) or 0) <= now then
			cancelledResolves[key] = nil
		end
	end
end

local function isResolveCancelled(cancelKey)
	if type(cancelKey) ~= "string" or cancelKey == "" then
		return false
	end
	local state = cancelledResolves[cancelKey]
	if not state then
		return false
	end
	if (tonumber(state.expiresAt) or 0) <= nowMs() then
		cancelledResolves[cancelKey] = nil
		return false
	end
	return true, state.reason or "cancelled"
end

function CancelResolverRequest(cancelKey, reason)
	if type(cancelKey) ~= "string" or cancelKey == "" then
		return false
	end
	cleanupCancelledResolves()
	cancelledResolves[cancelKey] = {
		reason = reason or "cancelled",
		expiresAt = nowMs() + 60000,
	}
	return true
end

local function emitResolverProgress(resolverOptions, progress)
	if type(resolverOptions) == "table" and type(resolverOptions.emitProgress) == "function" then
		pcall(resolverOptions.emitProgress, cloneValue(progress or {}))
	end
end

local function shouldContinueResolve(resolverOptions)
	if type(resolverOptions) == "table" and type(resolverOptions.shouldContinue) == "function" then
		local ok, keepGoing = pcall(resolverOptions.shouldContinue)
		return ok and keepGoing == true
	end
	if type(resolverOptions) == "table" and type(resolverOptions.cancelKey) == "string" then
		return not isResolveCancelled(resolverOptions.cancelKey)
	end
	return true
end

local function makeTraceEntry(provider, status, reason, extra)
	local entry = {
		provider = provider,
		status = status,
		reason = reason,
		at = os.time(),
	}
	if type(extra) == "table" then
		for key, value in pairs(extra) do
			entry[key] = value
		end
	end
	return entry
end

local function summarizeTrace(trace)
	local parts = {}
	for _, entry in ipairs(trace or {}) do
		parts[#parts + 1] = ("%s:%s:%s"):format(tostring(entry.provider), tostring(entry.status), tostring(entry.reason))
	end
	return table.concat(parts, " | ")
end

local function performRequest(url, method, body, headers, timeoutMs, callback)
	local done = false
	local timer = tonumber(timeoutMs) or 6000
	SetTimeout(timer, function()
		if done then
			return
		end
		done = true
		callback(0, nil, {}, "timeout")
	end)
	PerformHttpRequest(url, function(statusCode, responseBody, responseHeaders)
		if done then
			return
		end
		done = true
		callback(tonumber(statusCode) or 0, responseBody, responseHeaders or {}, nil)
	end, method or "GET", body or "", headers or {})
end

local function contentTypeIsPlayable(headers)
	local contentType = ""
	for key, value in pairs(headers or {}) do
		if tostring(key):lower() == "content-type" then
			contentType = tostring(value):lower()
			break
		end
	end
	return contentType:find("audio", 1, true)
		or contentType:find("video", 1, true)
		or contentType:find("mpegurl", 1, true)
		or contentType:find("octet%-stream")
		or contentType:find("ogg", 1, true)
end

local function probePlayableUrl(url, callback)
	if type(url) ~= "string" or not url:match("^https?://") then
		callback(false, "invalid_url")
		return
	end
	performRequest(url, "HEAD", "", {}, tonumber(Config.directLinks and Config.directLinks.probeTimeoutMs) or 3500, function(status, _, headers)
		if status >= 200 and status < 400 and contentTypeIsPlayable(headers) then
			callback(true)
			return
		end
		performRequest(url, "GET", "", { Range = "bytes=0-0" }, tonumber(Config.directLinks and Config.directLinks.probeTimeoutMs) or 3500, function(getStatus, __, getHeaders)
			if getStatus >= 200 and getStatus < 400 and contentTypeIsPlayable(getHeaders) then
				callback(true)
				return
			end
			callback(false, "probe_failed")
		end)
	end)
end

local function extensionLooksPlayable(url)
	url = tostring(url or ""):lower()
	return url:match("%.mp3[%?#]?$")
		or url:match("%.m4a[%?#]?$")
		or url:match("%.aac[%?#]?$")
		or url:match("%.mp4[%?#]?$")
		or url:match("%.webm[%?#]?$")
		or url:match("%.ogg[%?#]?$")
		or url:match("%.wav[%?#]?$")
		or url:match("%.m3u8[%?#]?$")
		or url:match("%.mpd[%?#]?$")
		or url:match("%.mp3[?&]")
		or url:match("%.mp4[?&]")
		or url:match("%.m3u8[?&]")
		or url:match("%.mpd[?&]")
end

local function normalizeRemoteAssetUrl(url)
	if type(url) ~= "string" or url == "" then
		return nil
	end
	if url:match("^//") then
		return "https:" .. url
	end
	if url:match("^https?://") then
		return url
	end
	return nil
end

local function collectInstances(provider)
	local seen = {}
	local list = {}
	local configured = resolverConfig.instances
	local source = type(configured) == "table" and configured[provider] or nil
	local function add(url)
		local normalized = normalizeBaseUrl(url)
		if normalized and not seen[normalized] then
			seen[normalized] = true
			list[#list + 1] = normalized
		end
	end
	if type(source) == "table" then
		for _, url in ipairs(source) do
			add(url)
		end
	end
	for _, url in ipairs(builtinInstances[provider] or {}) do
		add(url)
	end
	return list
end

local function collectCobaltEndpoints()
	local cobaltConfig = type(resolverConfig.cobalt) == "table" and resolverConfig.cobalt or {}
	if cobaltConfig.enabled == false then
		return {}
	end
	local seen = {}
	local endpoints = {}
	local function add(url)
		local normalized = normalizeBaseUrl(url)
		if normalized and not seen[normalized] then
			seen[normalized] = true
			endpoints[#endpoints + 1] = normalized
		end
	end
	if type(cobaltConfig.endpoints) == "table" then
		for _, url in ipairs(cobaltConfig.endpoints) do
			add(url)
		end
	end
	add(cobaltConfig.endpoint)
	return endpoints
end

local function isProviderCoolingDown(provider, instance)
	local key = tostring(provider) .. ":" .. tostring(instance or "")
	local state = providerCooldowns[key]
	if not state then
		return false
	end
	if nowMs() >= (tonumber(state.untilMs) or 0) then
		providerCooldowns[key] = nil
		return false
	end
	return true
end

local function setProviderCooldown(provider, instance, reason)
	local extractor = type(resolverConfig.extractor) == "table" and resolverConfig.extractor or {}
	local cooldownMs = math.max(30000, (tonumber(extractor.cooldownSeconds) or tonumber(resolverConfig.instanceFailureCooldownSeconds) or 300) * 1000)
	providerCooldowns[tostring(provider) .. ":" .. tostring(instance or "")] = {
		untilMs = nowMs() + cooldownMs,
		reason = reason or "failed",
	}
end

local function recordProviderAttempt(provider, ok, elapsedMs, reason, fakeSuccess)
	if type(provider) ~= "string" or provider == "" then
		return
	end
	local stats = loadProviderStats()
	local item = getProviderStat(provider)
	local slot = item.hours[currentHourSlot()]
	stats.totalAttempts = (tonumber(stats.totalAttempts) or 0) + 1
	item.lastReason = reason
	item.totalMs = (tonumber(item.totalMs) or 0) + math.max(0, tonumber(elapsedMs) or 0)
	if ok then
		item.successes = (tonumber(item.successes) or 0) + 1
		item.consecutiveFailures = 0
		slot.successes = (tonumber(slot.successes) or 0) + 1
		slot.totalMs = (tonumber(slot.totalMs) or 0) + math.max(0, tonumber(elapsedMs) or 0)
	else
		item.failures = (tonumber(item.failures) or 0) + 1
		item.consecutiveFailures = (tonumber(item.consecutiveFailures) or 0) + 1
		slot.failures = (tonumber(slot.failures) or 0) + 1
		if fakeSuccess then
			item.fakeSuccesses = (tonumber(item.fakeSuccesses) or 0) + 1
			slot.fakeSuccesses = (tonumber(slot.fakeSuccesses) or 0) + 1
		end
		if item.consecutiveFailures >= 3 then
			setProviderCooldown(provider, "provider", reason or "circuit_breaker")
		end
	end
	saveProviderStatsSoon()
end

function SuppressResolverInstance(provider, baseUrl, reason)
	if type(provider) ~= "string" or provider == "" then
		return false
	end
	setProviderCooldown(provider, baseUrl or "", reason or "suppressed")
	return true
end

local function chooseBestFormat(formats, wantVideo, avoidResolvedUrl)
	local best = nil
	local bestScore = -1
	for _, format in ipairs(formats or {}) do
		local url = format.url or format.playbackUrl
		local mime = tostring(format.type or format.mimeType or ""):lower()
		if type(url) == "string"
			and url ~= ""
			and url ~= avoidResolvedUrl
			and (wantVideo or mime:find("audio/", 1, true))
			and (not wantVideo or mime:find("video/", 1, true) or mime:find("audio/", 1, true)) then
			local score = tonumber(format.bitrate) or tonumber(format.averageBitrate) or 0
			if wantVideo and mime:find("mp4", 1, true) then
				score = score + 500000
			end
			if not wantVideo and mime:find("audio/", 1, true) then
				score = score + 1000000
			end
			if score > bestScore then
				best = format
				bestScore = score
			end
		end
	end
	return best
end

local function choosePipedFormat(payload, wantVideo, avoidResolvedUrl)
	local formats = {}
	for _, stream in ipairs(payload.audioStreams or {}) do
		formats[#formats + 1] = stream
	end
	for _, stream in ipairs(payload.videoStreams or {}) do
		if stream.videoOnly ~= true then
			formats[#formats + 1] = stream
		end
	end
	return chooseBestFormat(formats, wantVideo, avoidResolvedUrl)
end

local function makePayload(provider, instance, playableUrl, options, extra)
	local payload = {
		ok = true,
		provider = provider,
		instance = instance,
		status = "resolved",
		reason = "resolved_" .. provider,
		playableUrl = playableUrl,
		resolvedUrl = playableUrl,
		video = options and options.video ~= false,
	}
	if type(extra) == "table" then
		for key, value in pairs(extra) do
			payload[key] = value
		end
	end
	return payload
end

local function resolveDirect(url, options, resolverOptions, callback)
	if not extensionLooksPlayable(url) then
		callback(nil, "not_direct_media")
		return
	end
	probePlayableUrl(url, function(ok, reason)
		if ok then
			callback(makePayload("direct", "passthrough", url, options, { reason = "direct_passthrough" }))
			return
		end
		callback(nil, reason or "direct_probe_failed")
	end)
end

local function canUseHostedProvider(options)
	local playerConfig = type(Config.player) == "table" and Config.player or {}
	local duiConfig = type(Config.dui) == "table" and Config.dui or {}
	local urls = type(duiConfig.urls) == "table" and duiConfig.urls or {}
	local hostedUrl = urls.https
	if type(hostedUrl) ~= "string" or hostedUrl == "" then
		hostedUrl = playerConfig.hostedPlayerUrl
	end
	local url = options and options.url
	return type(url) == "string"
		and url:match("^https?://") ~= nil
		and playerConfig.useHostedPlayer ~= false
		and type(hostedUrl) == "string"
		and hostedUrl:match("^https://") ~= nil
end

local function getHostedDuiUrl()
	local playerConfig = type(Config.player) == "table" and Config.player or {}
	local duiConfig = type(Config.dui) == "table" and Config.dui or {}
	local urls = type(duiConfig.urls) == "table" and duiConfig.urls or {}
	local hostedUrl = urls.https
	if type(hostedUrl) ~= "string" or hostedUrl == "" then
		hostedUrl = playerConfig.hostedPlayerUrl
	end
	return hostedUrl
end

local function buildHostedResult(options)
	local resolved = cloneValue(options)
	local hostedUrl = getHostedDuiUrl()
	resolved.originalUrl = resolved.originalUrl or options.url
	resolved.resolvedUrl = options.url
	resolved.hostedPlayer = true
	resolved.resolver = {
		status = "browser",
		reason = "hosted_player",
		provider = "hosted_player",
		instance = hostedUrl or "hosted",
		resolvedAt = os.time(),
		trace = { makeTraceEntry("hosted_player", "success", "browser") },
	}
	return resolved
end

local function buildBrowserYoutubeResult(options, provider)
	local resolved = cloneValue(options)
	resolved.originalUrl = resolved.originalUrl or options.url
	resolved.resolvedUrl = options.url
	resolved.resolver = {
		status = "browser",
		reason = provider,
		provider = provider,
		instance = "client_browser",
		resolvedAt = os.time(),
		trace = { makeTraceEntry(provider, "success", "browser") },
	}
	return resolved
end

local function resolveHosted(url, options, resolverOptions, callback)
	if resolverOptions.avoidProvider == "hosted_player" or not canUseHostedProvider(options) then
		callback(nil, "hosted_unavailable")
		return
	end
	callback(makePayload("hosted_player", getHostedDuiUrl() or "hosted", url, options, {
		status = "browser",
		reason = "hosted_player",
		hostedPlayer = true,
	}))
end

local function resolveBrowserPage(url, options, resolverOptions, callback)
	if resolverOptions.avoidProvider == "browser" then
		callback(nil, "browser_avoided")
		return
	end
	if type(url) ~= "string" or url:match("^https?://") == nil then
		callback(nil, "browser_invalid_url")
		return
	end
	if isYoutubeUrl(url) then
		callback(nil, "use_youtube_browser")
		return
	end
	callback(makePayload("browser", "client_browser", url, options, {
		status = "browser",
		reason = "client_browser",
	}))
end

local function resolveBrowserYoutube(url, options, resolverOptions, callback)
	if not isYoutubeUrl(url) then
		callback(nil, "not_youtube")
		return
	end
	local provider = resolverOptions.forceProvider or "chromium_youtube"
	callback(makePayload(provider, "client_browser", url, options, {
		status = "browser",
		reason = provider,
	}))
end

local function resolveInvidious(url, options, resolverOptions, callback)
	local videoId = extractYoutubeId(url)
	if not videoId then
		callback(nil, "invalid_youtube_url")
		return
	end
	local wantVideo = not (options and options.video == false)
	local instances = collectInstances("invidious")
	local index = 0
	local function nextInstance(lastReason)
		index = index + 1
		local baseUrl = instances[index]
		if not baseUrl then
			callback(nil, lastReason or "invidious_unavailable")
			return
		end
		if isProviderCoolingDown("invidious", baseUrl) then
			nextInstance(lastReason)
			return
		end
		local requestUrl = ("%s/api/v1/videos/%s"):format(baseUrl, urlEncode(videoId))
		performRequest(requestUrl, "GET", "", {}, getProviderTimeoutMs("invidious"), function(status, body)
			if status < 200 or status >= 300 then
				setProviderCooldown("invidious", baseUrl, "http_" .. tostring(status))
				nextInstance("invidious_http_" .. tostring(status))
				return
			end
			local payload = decodeJson(body)
			local format = payload and chooseBestFormat(payload.adaptiveFormats or payload.formatStreams or {}, wantVideo, resolverOptions.avoidResolvedUrl)
			if not format or not format.url then
				nextInstance("invidious_no_stream")
				return
			end
			probePlayableUrl(format.url, function(ok, reason)
				if not ok then
					nextInstance(reason or "invidious_probe_failed")
					return
				end
				callback(makePayload("invidious", baseUrl, format.url, options, {
					title = payload.title,
					author = payload.author,
					duration = tonumber(payload.lengthSeconds),
					thumbnail = normalizeRemoteAssetUrl(payload.videoThumbnails and payload.videoThumbnails[1] and payload.videoThumbnails[1].url),
				}))
			end)
		end)
	end
	nextInstance()
end

local function resolvePiped(url, options, resolverOptions, callback)
	local videoId = extractYoutubeId(url)
	if not videoId then
		callback(nil, "invalid_youtube_url")
		return
	end
	local wantVideo = not (options and options.video == false)
	local instances = collectInstances("piped")
	local index = 0
	local function nextInstance(lastReason)
		index = index + 1
		local baseUrl = instances[index]
		if not baseUrl then
			callback(nil, lastReason or "piped_unavailable")
			return
		end
		if isProviderCoolingDown("piped", baseUrl) then
			nextInstance(lastReason)
			return
		end
		local requestUrl = ("%s/streams/%s"):format(baseUrl, urlEncode(videoId))
		performRequest(requestUrl, "GET", "", {}, getProviderTimeoutMs("piped"), function(status, body)
			if status < 200 or status >= 300 then
				setProviderCooldown("piped", baseUrl, "http_" .. tostring(status))
				nextInstance("piped_http_" .. tostring(status))
				return
			end
			local payload = decodeJson(body)
			if not payload or payload.error then
				nextInstance(payload and payload.error or "piped_invalid_response")
				return
			end
			local format = choosePipedFormat(payload, wantVideo, resolverOptions.avoidResolvedUrl)
			if not format or not format.url then
				nextInstance("piped_no_stream")
				return
			end
			probePlayableUrl(format.url, function(ok, reason)
				if not ok then
					nextInstance(reason or "piped_probe_failed")
					return
				end
				callback(makePayload("piped", baseUrl, format.url, options, {
					title = payload.title,
					author = payload.uploader,
					duration = tonumber(payload.duration),
					thumbnail = normalizeRemoteAssetUrl(payload.thumbnailUrl),
				}))
			end)
		end)
	end
	nextInstance()
end

local function resolveCobalt(url, options, resolverOptions, callback)
	local endpoints = collectCobaltEndpoints()
	local index = 0
	local cobaltConfig = type(resolverConfig.cobalt) == "table" and resolverConfig.cobalt or {}
	local function nextEndpoint(lastReason)
		index = index + 1
		local endpoint = endpoints[index]
		if not endpoint then
			callback(nil, lastReason or "cobalt_unavailable")
			return
		end
		if isProviderCoolingDown("cobalt", endpoint) then
			nextEndpoint(lastReason)
			return
		end
		local requestBody = json.encode({
			url = url,
			downloadMode = options and options.video == false and "audio" or "auto",
			disableMetadata = true,
			alwaysProxy = cobaltConfig.alwaysProxy ~= false,
			videoQuality = tostring(cobaltConfig.videoQuality or "720"),
			audioFormat = tostring(cobaltConfig.audioFormat or "mp3"),
			audioBitrate = tostring(cobaltConfig.audioBitrate or "128"),
		})
		performRequest(endpoint .. "/", "POST", requestBody, {
			["Content-Type"] = "application/json",
			Accept = "application/json",
		}, getProviderTimeoutMs("cobalt"), function(status, body)
			local payload = decodeJson(body)
			if status < 200 or status >= 300 then
				setProviderCooldown("cobalt", endpoint, payload and payload.error and payload.error.code or "http_" .. tostring(status))
				nextEndpoint(payload and payload.error and payload.error.code or "cobalt_http_" .. tostring(status))
				return
			end
			local playableUrl = payload and (payload.url or payload.tunnel or payload.redirect)
			if not playableUrl or not tostring(playableUrl):match("^https?://") then
				nextEndpoint(payload and payload.status or "cobalt_no_stream")
				return
			end
			probePlayableUrl(playableUrl, function(ok, reason)
				if not ok then
					nextEndpoint(reason or "cobalt_probe_failed")
					return
				end
				callback(makePayload("cobalt", endpoint, playableUrl, options))
			end)
		end)
	end
	nextEndpoint()
end

local function extractInitialPlayerResponse(html)
	local markerStart = html and html:find("ytInitialPlayerResponse", 1, true)
	if not markerStart then
		return nil
	end
	local objectStart = html:find("{", markerStart, true)
	if not objectStart then
		return nil
	end
	local depth = 0
	local inString = false
	local escaped = false
	for index = objectStart, #html do
		local char = html:sub(index, index)
		if inString then
			if escaped then
				escaped = false
			elseif char == "\\" then
				escaped = true
			elseif char == '"' then
				inString = false
			end
		elseif char == '"' then
			inString = true
		elseif char == "{" then
			depth = depth + 1
		elseif char == "}" then
			depth = depth - 1
			if depth == 0 then
				return html:sub(objectStart, index)
			end
		end
	end
	return nil
end

local function resolvePageScrape(url, options, resolverOptions, callback)
	local videoId = extractYoutubeId(url)
	if not videoId then
		callback(nil, "invalid_youtube_url")
		return
	end
	local requestUrl = "https://www.youtube.com/watch?v=" .. urlEncode(videoId)
	performRequest(requestUrl, "GET", "", {
		["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
		["Accept-Language"] = "en-US",
	}, getProviderTimeoutMs("page_scrape"), function(status, body)
		if status < 200 or status >= 300 then
			callback(nil, "page_http_" .. tostring(status))
			return
		end
		local playerResponse = decodeJson(extractInitialPlayerResponse(body))
		local statusText = playerResponse and playerResponse.playabilityStatus and playerResponse.playabilityStatus.status
		if statusText and statusText ~= "OK" then
			callback(nil, "youtube_" .. tostring(statusText):lower())
			return
		end
		local streamingData = playerResponse and playerResponse.streamingData or {}
		local formats = {}
		for _, format in ipairs(streamingData.adaptiveFormats or {}) do
			formats[#formats + 1] = format
		end
		for _, format in ipairs(streamingData.formats or {}) do
			formats[#formats + 1] = format
		end
		local chosen = chooseBestFormat(formats, not (options and options.video == false), resolverOptions.avoidResolvedUrl)
		if not chosen or not chosen.url then
			callback(nil, "page_no_direct_stream")
			return
		end
		probePlayableUrl(chosen.url, function(ok, reason)
			if not ok then
				callback(nil, reason or "page_probe_failed")
				return
			end
			callback(makePayload("page_scrape", "youtube", chosen.url, options, {
				title = playerResponse.videoDetails and playerResponse.videoDetails.title,
				author = playerResponse.videoDetails and playerResponse.videoDetails.author,
				duration = tonumber(playerResponse.videoDetails and playerResponse.videoDetails.lengthSeconds),
				thumbnail = normalizeRemoteAssetUrl(playerResponse.videoDetails and playerResponse.videoDetails.thumbnail and playerResponse.videoDetails.thumbnail.thumbnails and playerResponse.videoDetails.thumbnail.thumbnails[1] and playerResponse.videoDetails.thumbnail.thumbnails[1].url),
			}))
		end)
	end)
end

local function resolveCdpnYoutube(url, options, resolverOptions, callback)
	local videoId = extractYoutubeId(url)
	if not videoId then
		callback(nil, "not_youtube")
		return
	end
	callback(makePayload("cdpn_youtube", "cdpn", "https://cdpn.io/pen/debug/oNPzxKo?v=" .. urlEncode(videoId), options, {
		status = "browser",
		reason = "cdpn_youtube",
	}))
end

local providerFunctions = {
	direct = resolveDirect,
	hosted_player = resolveHosted,
	cdpn_youtube = resolveCdpnYoutube,
	browser = resolveBrowserPage,
	chromium_youtube = resolveBrowserYoutube,
	embed = resolveBrowserYoutube,
	cobalt = resolveCobalt,
	invidious = resolveInvidious,
	piped = resolvePiped,
	page_scrape = resolvePageScrape,
}

local function providerOrder(resolverOptions, url)
	local forced = type(resolverOptions.forceProvider) == "string" and resolverOptions.forceProvider or nil
	if forced and providerFunctions[forced] then
		return { forced }
	end
	local configured = resolverConfig.providerOrder
	if type(configured) ~= "table" then
		local extractor = type(resolverConfig.extractor) == "table" and resolverConfig.extractor or {}
		configured = extractor.providerOrder
	end
	if type(configured) ~= "table" then
		configured = isYoutubeUrl(url)
			and { "hosted_player", "cdpn_youtube", "chromium_youtube", "browser", "invidious", "piped", "page_scrape", "cobalt" }
			or { "hosted_player", "browser", "direct" }
	end
	local order = {}
	local orderRank = {}
	for _, provider in ipairs(configured) do
		if providerFunctions[provider] and provider ~= resolverOptions.avoidProvider and not isProviderCoolingDown(provider, "provider") then
			order[#order + 1] = provider
			orderRank[provider] = #order
		end
	end
	if not isYoutubeUrl(url) and resolverOptions.avoidProvider ~= "direct" then
		table.insert(order, 1, "direct")
		orderRank.direct = 0
	end
	table.sort(order, function(left, right)
		local leftScore = scoreProvider(left)
		local rightScore = scoreProvider(right)
		if math.abs(leftScore - rightScore) < 0.0001 then
			return (orderRank[left] or 9999) < (orderRank[right] or 9999)
		end
		return leftScore > rightScore
	end)
	return order
end

local function shouldUseHosted(options, resolverOptions)
	return resolverOptions.forceProvider == "hosted_player" and canUseHostedProvider(options)
end

local function buildResolvedOptions(options, payload)
	local resolved = cloneValue(options)
	resolved.url = payload.playableUrl or options.url
	resolved.originalUrl = options.url
	resolved.resolvedUrl = payload.resolvedUrl or payload.playableUrl or options.url
	resolved.resolver = {
		status = payload.status or "resolved",
		reason = payload.reason or "resolved",
		provider = payload.provider,
		instance = payload.instance,
		warning = payload.warning,
		trace = payload.trace or {},
		resolvedAt = os.time(),
	}
	resolved.title = resolved.title or payload.title
	resolved.author = resolved.author or payload.author
	resolved.thumbnail = resolved.thumbnail or payload.thumbnail
	resolved.duration = resolved.duration or payload.duration
	if payload.video == false then
		resolved.video = false
	end
	if payload.hostedPlayer == true then
		resolved.hostedPlayer = true
	end
	return resolved
end

local function resolveWithProviders(options, resolverOptions, callback)
	local url = options.url
	local order = providerOrder(resolverOptions, url)
	local trace = {}
	local finished = false
	local active = 0
	local index = 0
	local maxParallel = math.max(1, math.min(3, tonumber(resolverOptions.parallelProviders) or tonumber(resolverConfig.parallelProviders) or 2))
	local lastReason = "resolver_unavailable"

	local function finish(ok, payload, warning)
		if finished then
			return
		end
		finished = true
		callback(ok, payload, warning)
	end

	SetTimeout(getAbsoluteTimeoutMs(), function()
		if not finished then
			trace[#trace + 1] = makeTraceEntry("resolver", "failed", "timeout")
			finish(false, nil, "Resolver timed out.")
		end
	end)

	local launchNext
	launchNext = function()
		if finished or not shouldContinueResolve(resolverOptions) then
			if not finished then
				finish(false, nil, "Resolver cancelled.")
			end
			return
		end
		while active < maxParallel and index < #order do
			index = index + 1
				local provider = order[index]
				local resolver = providerFunctions[provider]
				if resolver then
					active = active + 1
					local providerStartedAt = nowMs()
					emitResolverProgress(resolverOptions, {
					status = "trying",
					provider = provider,
					index = index,
					total = #order,
				})
				resolver(url, options, resolverOptions, function(payload, reason)
					active = math.max(0, active - 1)
					if finished then
						return
					end
					if payload then
						recordProviderAttempt(provider, true, nowMs() - providerStartedAt, "resolved", false)
						payload.trace = cloneValue(trace)
						payload.trace[#payload.trace + 1] = makeTraceEntry(provider, "success", "resolved", { instance = payload.instance })
						finish(true, payload)
						return
					end
					lastReason = reason or lastReason
					recordProviderAttempt(provider, false, nowMs() - providerStartedAt, lastReason, tostring(lastReason):find("probe", 1, true) ~= nil)
					trace[#trace + 1] = makeTraceEntry(provider, "failed", lastReason)
					launchNext()
					if active == 0 and index >= #order and not finished then
						local allowEmbed = bool(resolverConfig.allowEmbedFallback, false)
						if allowEmbed and isYoutubeUrl(url) and resolverOptions.avoidProvider ~= "embed" then
							local fallback = makePayload("embed", "youtube_embed", url, options, {
								status = "fallback",
								reason = lastReason,
								warning = "Using embedded YouTube as final fallback.",
								trace = trace,
							})
							finish(true, fallback, fallback.warning)
							return
						end
						finish(false, nil, "No fallback provider returned a playable stream. " .. summarizeTrace(trace))
					end
				end)
			end
		end
		if index >= #order and active == 0 and not finished then
			finish(false, nil, "No fallback provider is available.")
		end
	end

	acquireGlobalSlot(function()
		local released = false
		local function releaseOnce()
			if released then
				return
			end
			released = true
			releaseGlobalSlot()
		end
		local originalCallback = callback
		callback = function(ok, payload, warning)
			releaseOnce()
			originalCallback(ok, payload, warning)
		end
		if finished then
			releaseOnce()
			return
		end
		launchNext()
	end)
end

local function buildInflightKey(options, resolverOptions)
	return table.concat({
		tostring(options and options.url or ""),
		tostring(options and options.video ~= false),
		tostring(resolverOptions and resolverOptions.forceProvider or ""),
		tostring(resolverOptions and resolverOptions.avoidProvider or ""),
		tostring(resolverOptions and resolverOptions.avoidResolvedUrl or ""),
	}, "|")
end

function ResolvePlaybackOptions(options, resolverOptions, callback)
	resolverOptions = type(resolverOptions) == "table" and resolverOptions or {}
	if type(options) ~= "table" or type(options.url) ~= "string" or options.url == "" then
		callback(false, nil, "Invalid playback URL.")
		return
	end

	cleanupCancelledResolves()

	if shouldUseHosted(options, resolverOptions) then
		callback(true, buildHostedResult(options), nil)
		return
	end

	local cacheKey = buildInflightKey(options, resolverOptions)
	local now = os.time()
	local cached = resolveCache[cacheKey]
	if resolverOptions.forceRefresh ~= true and cached and cached.expiresAt > now then
		emitResolverProgress(resolverOptions, { status = "cache_hit", provider = cached.provider or "resolver" })
		callback(true, cloneValue(cached.resolved), cached.warning)
		return
	end

	local listener = {
		callback = callback,
		onProgress = type(resolverOptions.onProgress) == "function" and resolverOptions.onProgress or nil,
		cancelKey = type(resolverOptions.cancelKey) == "string" and resolverOptions.cancelKey or nil,
	}

	local inflight = resolveInflight[cacheKey]
	if inflight then
		inflight.listeners[#inflight.listeners + 1] = listener
		if listener.onProgress then
			pcall(listener.onProgress, { status = "joined", provider = "resolver" })
		end
		return
	end

	resolveInflight[cacheKey] = { listeners = { listener } }

	resolverOptions.emitProgress = function(progress)
		local state = resolveInflight[cacheKey]
		if not state then
			return
		end
		for _, item in ipairs(state.listeners or {}) do
			if item.onProgress and (not item.cancelKey or not isResolveCancelled(item.cancelKey)) then
				pcall(item.onProgress, cloneValue(progress or {}))
			end
		end
	end

	resolverOptions.shouldContinue = function()
		local state = resolveInflight[cacheKey]
		if not state then
			return false
		end
		for _, item in ipairs(state.listeners or {}) do
			if not item.cancelKey or not isResolveCancelled(item.cancelKey) then
				return true
			end
		end
		return false
	end

	emitResolverProgress(resolverOptions, { status = "started", provider = "resolver" })

	resolveWithProviders(options, resolverOptions, function(ok, payload, warning)
		local resolved = nil
		if ok and payload then
			resolved = buildResolvedOptions(options, payload)
			if payload.status == "resolved" then
				resolveCache[cacheKey] = {
					expiresAt = os.time() + getCacheTtlSeconds(),
					resolved = cloneValue(resolved),
					warning = warning,
					provider = payload.provider,
				}
			end
		end

		local state = resolveInflight[cacheKey]
		resolveInflight[cacheKey] = nil
		for _, item in ipairs(state and state.listeners or {}) do
			if (not item.cancelKey or not isResolveCancelled(item.cancelKey)) and type(item.callback) == "function" then
				item.callback(ok == true and resolved ~= nil, resolved and cloneValue(resolved) or nil, warning or (not ok and "Resolver failed." or nil))
			end
		end
	end)
end

function RecordResolverProviderPlayback(provider, instance, outcome, startupMs, reason)
	if type(provider) ~= "string" or provider == "" then
		return
	end
	local stats = loadProviderStats()
	if outcome == "success" then
		stats.totalCompletedAutoPlays = (tonumber(stats.totalCompletedAutoPlays) or 0) + 1
	end
	recordProviderAttempt(provider, outcome == "success", startupMs, reason, reason == "fake_success")
end

function GetResolverProviderStatsSummary(limit)
	local stats = loadProviderStats()
	local rows = {}
	for _, item in pairs(stats.providers or {}) do
		local copy = cloneValue(item)
		copy.score = scoreProvider(copy.provider)
		rows[#rows + 1] = copy
	end
	table.sort(rows, function(left, right)
		return (tonumber(left.score) or 0) > (tonumber(right.score) or 0)
	end)
	local capped = {}
	for index = 1, math.min(#rows, tonumber(limit) or #rows) do
		capped[#capped + 1] = rows[index]
	end
	return {
		totalAttempts = stats.totalAttempts or 0,
		totalCompletedAutoPlays = stats.totalCompletedAutoPlays or 0,
		providers = capped,
	}
end

exports("resolvePlaybackOptions", ResolvePlaybackOptions)
