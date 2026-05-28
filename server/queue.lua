local function cloneTable(source, seen)
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
        copy[cloneTable(key, seen)] = cloneTable(value, seen)
    end

    return copy
end

local function getLoopMode(mp)
    if type(NormalizeLoopMode) == "function" then
        return NormalizeLoopMode(mp and mp.loopMode, mp and mp.loop)
    end
    return mp and mp.loop and "track" or "off"
end

local function getQueueLookaheadCount()
    local queueConfig = Config.queue or {}
    return math.max(0, tonumber(queueConfig.lookaheadCount) or 1)
end

local queueLocks = {}
local queueLockQueues = {}

local function getQueueLockKey(handle)
    return tostring(tonumber(handle) or handle or "")
end

local function runQueueLocked(key, fn)
    local ok, err = pcall(fn)
    if not ok then
        print("[7-pmms] Queue mutation error: " .. tostring(err))
    end

    local queue = queueLockQueues[key]
    local nextRun = queue and table.remove(queue, 1) or nil
    if nextRun then
        Citizen.CreateThread(nextRun)
        return
    end

    queueLocks[key] = nil
    queueLockQueues[key] = nil
end

local function withQueueLock(handle, fn)
    local key = getQueueLockKey(handle)
    local function run()
        runQueueLocked(key, fn)
    end

    if queueLocks[key] then
        queueLockQueues[key] = queueLockQueues[key] or {}
        queueLockQueues[key][#queueLockQueues[key] + 1] = run
        return false
    end

    queueLocks[key] = true
    run()
    return true
end

local function getSessionForHandle(handle, seedOptions)
    if type(GetDeviceSession) ~= "function" then
        return nil
    end

    local session = GetDeviceSession(handle)
    if not session and type(EnsureDeviceSession) == "function" and seedOptions then
        session = EnsureDeviceSession(handle, seedOptions)
    end

    if session and type(session.queue) ~= "table" then
        session.queue = {}
    end

    return session
end

local function requestQueueResync(sourceId)
    if not sourceId then
        return
    end

    TriggerClientEvent("pmms:error", sourceId, "Queue changed. Please try again.")

    if type(SendPmmsFullSync) == "function" then
        SendPmmsFullSync(sourceId)
    elseif type(RequestPmmsSync) == "function" then
        RequestPmmsSync(sourceId, { full = true })
    end
end

local function rejectStaleQueueMutation(handle, sourceId, expectedRevision)
    local expected = tonumber(expectedRevision)
    if not expected then
        return false
    end

    local session = getSessionForHandle(handle)
    local current = tonumber(session and session.queueRevision) or 0
    if expected == current then
        return false
    end

    local legacyStateRevision = tonumber(session and session.stateRevision)
    if legacyStateRevision and expected == legacyStateRevision then
        PMMSDebug("player", "legacy queue mutation revision accepted", {
            handle = handle,
            expectedRevision = expected,
            queueRevision = current,
            stateRevision = legacyStateRevision,
        })
        return false
    end

    requestQueueResync(sourceId)
    return true
end

local function ensureSessionQueueMetadata(session)
    if type(session) ~= "table" then
        return
    end

    session.queue = type(session.queue) == "table" and session.queue or {}
    session.shufflePreviewIds = type(session.shufflePreviewIds) == "table" and session.shufflePreviewIds or {}
    session.nextQueueEntryId = tonumber(session.nextQueueEntryId) or 0

    for _, entry in ipairs(session.queue) do
        local queueId = tonumber(entry and entry.queueId)
        if queueId and queueId > session.nextQueueEntryId then
            session.nextQueueEntryId = queueId
        end
    end

    for _, entry in ipairs(session.queue) do
        if type(entry) == "table" and not tonumber(entry.queueId) then
            session.nextQueueEntryId = session.nextQueueEntryId + 1
            entry.queueId = session.nextQueueEntryId
        end
    end
end

local function findQueueEntry(session, entry)
    if type(session) ~= "table" or type(session.queue) ~= "table" or type(entry) ~= "table" then
        return nil, nil
    end

    for index, candidate in ipairs(session.queue) do
        if candidate == entry then
            return index, candidate
        end
    end

    local queueId = tonumber(entry.queueId)
    if queueId then
        for index, candidate in ipairs(session.queue) do
            if tonumber(candidate and candidate.queueId) == queueId then
                return index, candidate
            end
        end
    end

    return nil, nil
end

local function resolveQueueIndex(session, index)
    if type(session) ~= "table" or type(session.queue) ~= "table" then
        return nil
    end

    ensureSessionQueueMetadata(session)

    local parsedIndex = tonumber(index)
    if not parsedIndex then
        return nil
    end

    parsedIndex = math.floor(parsedIndex)
    if parsedIndex >= 1 and parsedIndex <= #session.queue then
        return parsedIndex
    end

    for queueIndex, entry in ipairs(session.queue) do
        if tonumber(entry and entry.queueId) == parsedIndex then
            return queueIndex
        end
    end

    return nil
end

local function shuffleList(values)
    for index = #values, 2, -1 do
        local swapIndex = math.random(index)
        values[index], values[swapIndex] = values[swapIndex], values[index]
    end
end

local function syncShufflePreviewState(session, mode)
    ensureSessionQueueMetadata(session)
    if type(session) ~= "table" then
        return
    end

    if mode ~= "shuffle_once" and mode ~= "shuffle_loop" then
        session.shufflePreviewIds = {}
        return
    end

    local queue = session.queue or {}
    local present = {}
    local ordered = {}

    for _, entry in ipairs(queue) do
        local queueId = tonumber(entry and entry.queueId)
        if queueId then
            present[queueId] = entry
        end
    end

    for _, queueId in ipairs(session.shufflePreviewIds or {}) do
        if present[queueId] then
            ordered[#ordered + 1] = queueId
            present[queueId] = nil
        end
    end

    local missing = {}
    for _, entry in ipairs(queue) do
        local queueId = tonumber(entry and entry.queueId)
        if queueId and present[queueId] then
            missing[#missing + 1] = queueId
            present[queueId] = nil
        end
    end

    if #missing > 0 then
        shuffleList(missing)
        for _, queueId in ipairs(missing) do
            ordered[#ordered + 1] = queueId
        end
    end

    session.shufflePreviewIds = ordered
end

local function clonePreviewEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end

    return {
        queueId = tonumber(entry.queueId) or nil,
        source = entry.source,
        name = entry.name,
        options = cloneTable(entry.options),
    }
end

function BuildPlaybackPreview(handle, mp, providedSession)
    local session = providedSession or getSessionForHandle(handle)
    if not session then
        return {}
    end

    ensureSessionQueueMetadata(session)

    local queue = session.queue or {}
    local mode = getLoopMode(mp or {
        loopMode = session.settings and session.settings.loopMode,
        loop = session.settings and session.settings.loopMode == "track",
    })
    local preview = {}

    if mode == "track" then
        local currentTrack = session.currentTrack
        if type(currentTrack) == "table" and type(currentTrack.url) == "string" and currentTrack.url ~= "" then
            preview[1] = {
                source = session.lastSource,
                name = session.lastSource and GetPlayerName(session.lastSource) or nil,
                options = cloneTable(currentTrack),
            }
        end
        return preview
    end

    if mode == "shuffle_once" or mode == "shuffle_loop" then
        syncShufflePreviewState(session, mode)
        local indexById = {}
        for _, entry in ipairs(queue) do
            local queueId = tonumber(entry and entry.queueId)
            if queueId then
                indexById[queueId] = entry
            end
        end

        for _, queueId in ipairs(session.shufflePreviewIds or {}) do
            local entry = indexById[queueId]
            if entry then
                local cloned = clonePreviewEntry(entry)
                if cloned then
                    preview[#preview + 1] = cloned
                end
            end
        end

        return preview
    end

    for _, entry in ipairs(queue) do
        local cloned = clonePreviewEntry(entry)
        if cloned then
            preview[#preview + 1] = cloned
        end
    end

    return preview
end

local function commitQueueState(handle, mp, queueRevisionReason)
    local session = getSessionForHandle(handle)
    if session and queueRevisionReason and type(BumpDeviceQueueRevision) == "function" then
        BumpDeviceQueueRevision(handle, queueRevisionReason)
    end
    if session and type(CommitDeviceSessionState) == "function" then
        CommitDeviceSessionState(handle)
    else
        MarkDirty()
    end

    if mp and session then
        mp.queue = session.queue
        mp.queueRevision = tonumber(session.queueRevision) or 0
    end
end

local function captureCurrentTrackOptions(mp)
    if not mp or type(mp.url) ~= "string" or mp.url == "" then
        return nil
    end

    local baseUrl = (type(mp.originalUrl) == "string" and mp.originalUrl ~= "" and mp.originalUrl) or mp.url

    return {
        url = baseUrl,
        title = mp.title or baseUrl,
        duration = mp.duration,
        author = mp.author,
        thumbnail = mp.thumbnail,
        thumbnailCandidates = cloneTable(mp.thumbnailCandidates),
        live = mp.live == true,
        volume = mp.volume,
        offset = 0,
        filter = mp.filter,
        video = mp.video,
        visualization = mp.visualization,
        originalUrl = mp.originalUrl,
        resolvedUrl = mp.resolvedUrl,
        resolver = cloneTable(mp.resolver),
        directLink = cloneTable(mp.directLink),
        audioTracks = cloneTable(mp.audioTracks),
        audioTrack = cloneTable(mp.audioTrack or mp.selectedAudioTrack),
        selectedAudioTrack = cloneTable(mp.selectedAudioTrack or mp.audioTrack),
    }
end

local function resolveClientFromQueueEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local source = tonumber(entry.source)
    if source and GetPlayerName(source) then
        return source
    end

    for _, pid in ipairs(GetPlayers()) do
        local parsed = tonumber(pid) or pid
        if parsed and GetPlayerName(parsed) then
            return parsed
        end
    end

    return nil
end

local function pickQueueIndex(session, mode)
    local queue = session and session.queue or {}
    local queueLength = #queue
    if queueLength <= 0 then
        return nil
    end

    if mode == "shuffle_once" or mode == "shuffle_loop" then
        syncShufflePreviewState(session, mode)
        local nextQueueId = session.shufflePreviewIds and session.shufflePreviewIds[1] or nil
        if nextQueueId then
            for index, entry in ipairs(queue) do
                if tonumber(entry and entry.queueId) == tonumber(nextQueueId) then
                    return index
                end
            end
        end

        return 1
    end

    return 1
end

local function isYoutubeLikeUrl(url)
    if type(url) ~= "string" then
        return false
    end

    local lower = url:lower()
    return lower:find("youtube%.com", 1, false) ~= nil
        or lower:find("youtu%.be", 1, false) ~= nil
end

local function getQueueEntrySignature(entry)
    local options = entry and entry.options or {}
    return table.concat({
        tostring(entry and entry.source or ""),
        tostring(options.originalUrl or options.url or ""),
        options.video == false and "audio" or "video",
    }, "|")
end

local function mergeResolvedIntoOptions(target, resolved)
    if type(target) ~= "table" or type(resolved) ~= "table" then
        return
    end

    target.originalUrl = resolved.originalUrl or target.originalUrl or target.url
    target.resolvedUrl = resolved.resolvedUrl or resolved.url or target.resolvedUrl
    target.resolver = resolved.resolver or target.resolver
    target.directLink = resolved.directLink or target.directLink

    if (not target.title or target.title == target.url) and resolved.title then
        target.title = resolved.title
    end
    if (not target.author or target.author == "") and resolved.author then
        target.author = resolved.author
    end
    if (not target.thumbnail or target.thumbnail == "") and resolved.thumbnail then
        target.thumbnail = resolved.thumbnail
    end
    if not target.duration and resolved.duration then
        target.duration = resolved.duration
    end
    if resolved.live == true or resolved.live == false then
        target.live = resolved.live == true
    end
    if type(resolved.audioTracks) == "table" then
        target.audioTracks = cloneTable(resolved.audioTracks)
    end
    if type(resolved.audioTrack) == "table" or type(resolved.selectedAudioTrack) == "table" then
        target.audioTrack = cloneTable(resolved.audioTrack or resolved.selectedAudioTrack)
        target.selectedAudioTrack = cloneTable(resolved.selectedAudioTrack or resolved.audioTrack)
    end
    if resolved.video == false then
        target.video = false
    elseif resolved.video == true then
        target.video = true
    end
end

local function clearPreparedNext(mp)
    if not mp then
        return
    end

    mp.preparedNext = nil
    mp.preparedNextSignature = nil
end

local function storePreparedNext(mp, entry, preparedOptions)
    if not mp or type(entry) ~= "table" or type(preparedOptions) ~= "table" then
        return
    end

    mp.preparedNext = cloneTable(preparedOptions)
    mp.preparedNextSignature = getQueueEntrySignature(entry)
end

local function canPlayQueuedOptionsImmediately(queued)
    if type(queued) ~= "table" or type(queued.url) ~= "string" or queued.url == "" then
        return false
    end

    if type(queued.resolvedUrl) == "string" and queued.resolvedUrl ~= "" then
        return true
    end

    local resolver = queued.resolver
    if type(resolver) == "table" then
        local status = resolver.status
        if status == "fallback" or status == "bypass" then
            return true
        end
    end

    if type(queued.directLink) == "table" and queued.directLink.validated == true then
        return true
    end

    return not isYoutubeLikeUrl(queued.originalUrl or queued.url)
end

local function prepareNextEntry(handle, mp, entry)
    if not mp or type(entry) ~= "table" then
        return
    end

    local signature = getQueueEntrySignature(entry)
    if mp.preparedNextSignature == signature and type(mp.preparedNext) == "table" then
        return
    end

    clearPreparedNext(mp)

    local queuedOptions = entry.options
    if type(queuedOptions) ~= "table" then
        MarkDirty()
        return
    end

    if canPlayQueuedOptionsImmediately(queuedOptions) or type(ResolvePlaybackOptions) ~= "function" then
        storePreparedNext(mp, entry, queuedOptions)
        MarkDirty()
        return
    end

    if entry.resolving == true then
        MarkDirty()
        return
    end

    MarkDirty()

    local resolveIntent = cloneTable(queuedOptions)
    entry.resolving = true
    ResolvePlaybackOptions(resolveIntent, {
        notifyOnFailure = false,
    }, function(ok, resolved)
        withQueueLock(handle, function()
            entry.resolving = false
            if not ok or type(resolved) ~= "table" then
                entry.resolveFailedAt = os.time()
                return
            end

            local liveSession = getSessionForHandle(handle)
            local liveQueue = liveSession and liveSession.queue or nil
            if type(liveQueue) ~= "table" or not liveQueue[1] then
                return
            end

            local liveEntry = liveQueue[1]
            if getQueueEntrySignature(liveEntry) ~= signature then
                return
            end

            mergeResolvedIntoOptions(liveEntry.options or {}, resolved)
            liveEntry.resolvedAt = os.time()

            local liveMp = GetMediaPlayer(handle)
            if liveMp then
                storePreparedNext(liveMp, liveEntry, liveEntry.options)
            end

            commitQueueState(handle, liveMp)
        end)
    end)
end

function SchedulePreparedQueueForHandle(handle)
    local mp = GetMediaPlayer(handle)
    if not mp then
        return
    end

    if getQueueLookaheadCount() <= 0 then
        clearPreparedNext(mp)
        MarkDirty()
        return
    end

    local session = getSessionForHandle(handle, mp)
    local queue = session and session.queue or {}
    local mode = getLoopMode(mp)
    if #queue <= 0 or mode == "shuffle_once" or mode == "shuffle_loop" then
        clearPreparedNext(mp)
        MarkDirty()
        return
    end

    prepareNextEntry(handle, mp, queue[1])
end

local function buildPlaybackOptions(handle, mp, session, queued, context)
    if type(queued) ~= "table" or type(queued.url) ~= "string" or queued.url == "" then
        return nil
    end

    local options = {}
    local base = session and session.playerTemplate or mp or {}

    for key, value in pairs(base) do
        options[key] = cloneTable(value)
    end

    if session and session.settings then
        options.volume = session.settings.volume
        options.attenuation = cloneTable(session.settings.attenuation)
        options.diffRoomVolume = session.settings.diffRoomVolume
        options.range = session.settings.range
        options.transitionSeconds = session.settings.transitionSeconds
        options.isVehicle = session.settings.isVehicle == true
        options.loopMode = session.settings.loopMode
        options.loop = NormalizeLoopMode(options.loopMode, options.loop) == "track"
    end

    options.queue = session and session.queue or {}
    options.url = queued.url
    options.title = queued.title or queued.url
    options.duration = queued.duration
    options.live = queued.live == true
    options.author = queued.author
    options.thumbnail = queued.thumbnail
    options.thumbnailCandidates = cloneTable(queued.thumbnailCandidates)
    options.offset = queued.offset or 0
    options.filter = queued.filter
    options.video = queued.video
    options.visualization = queued.visualization
    options.originalUrl = queued.originalUrl
    options.resolvedUrl = queued.resolvedUrl
    options.resolver = cloneTable(queued.resolver)
    options.directLink = cloneTable(queued.directLink)
    options.audioTracks = cloneTable(queued.audioTracks)
    options.audioTrack = cloneTable(queued.audioTrack or queued.selectedAudioTrack)
    options.selectedAudioTrack = cloneTable(queued.selectedAudioTrack or queued.audioTrack)
    options.lastSource = tonumber(context and context.sourceId) or tonumber(options.lastSource) or nil

    local immediate = context and context.immediate == true or false
    options.transitionState = {
        active = false,
        duration = immediate and 0 or (tonumber(options.transitionSeconds) or tonumber(Config.defaultTransitionSeconds) or 5.0),
        startedAt = os.time(),
        reason = context and context.reason or nil,
        fromUrl = mp and (mp.originalUrl or mp.url) or nil,
        toUrl = queued.originalUrl or queued.url,
        usedPrepared = canPlayQueuedOptionsImmediately(queued),
        immediate = immediate,
    }

    clearPreparedNext(options)
    return options
end

local function addToQueueUnlocked(handle, source, options, expectedRevision)
    if rejectStaleQueueMutation(handle, source, expectedRevision) then
        return false
    end

    local mp = GetMediaPlayer(handle)
    local session = getSessionForHandle(handle, mp or options)
    if not session then
        return false
    end

    ensureSessionQueueMetadata(session)
    local queue = session.queue or {}
    local queuedOptions = cloneTable(options)
    local queueEntry = {
        source = source,
        name = GetPlayerName(source),
        options = queuedOptions,
    }

    queue[#queue + 1] = queueEntry
    session.queue = queue
    ensureSessionQueueMetadata(session)
    syncShufflePreviewState(session, getLoopMode(mp or {
        loopMode = session.settings and session.settings.loopMode,
        loop = session.settings and session.settings.loopMode == "track",
    }))
    if mp then
        mp.queue = queue
    end

    if type(ResolvePlaybackOptions) == "function"
        and type(queuedOptions.url) == "string"
        and queuedOptions.url ~= "" then
        local resolveIntent = cloneTable(queuedOptions)
        queueEntry.resolving = true
        ResolvePlaybackOptions(resolveIntent, {
            notifyOnFailure = false,
        }, function(ok, resolved)
            withQueueLock(handle, function()
                local liveSession = getSessionForHandle(handle)
                local _, liveEntry = findQueueEntry(liveSession, queueEntry)
                if not liveEntry then
                    return
                end

                liveEntry.resolving = false
                if not ok or type(resolved) ~= "table" or not liveEntry.options then
                    liveEntry.resolveFailedAt = os.time()
                    return
                end

                mergeResolvedIntoOptions(liveEntry.options, resolved)
                liveEntry.resolvedAt = os.time()

                local liveMp = GetMediaPlayer(handle)
                local liveQueue = liveSession and liveSession.queue or nil
                if liveMp and type(liveQueue) == "table" and liveQueue[1] == liveEntry then
                    storePreparedNext(liveMp, liveEntry, liveEntry.options)
                end

                commitQueueState(handle, liveMp)
            end)
        end)
    end

    if type(SchedulePreparedQueueForHandle) == "function" then
        SchedulePreparedQueueForHandle(handle)
    end

    commitQueueState(handle, mp, "queue_add")
    return true
end

function AddToQueue(handle, source, options, expectedRevision)
    local result
    withQueueLock(handle, function()
        result = addToQueueUnlocked(handle, source, options, expectedRevision)
    end)
    return result
end

local function removeFromQueueUnlocked(handle, index, expectedRevision, sourceId)
    if rejectStaleQueueMutation(handle, sourceId, expectedRevision) then
        return false
    end

    local session = getSessionForHandle(handle)
    if not session then
        return false
    end

    ensureSessionQueueMetadata(session)
    local parsedIndex = resolveQueueIndex(session, index)
    if not parsedIndex then
        return false
    end

    table.remove(session.queue, parsedIndex)
    syncShufflePreviewState(session, getLoopMode(GetMediaPlayer(handle) or {
        loopMode = session.settings and session.settings.loopMode,
        loop = session.settings and session.settings.loopMode == "track",
    }))

    local mp = GetMediaPlayer(handle)
    if mp then
        mp.queue = session.queue
        if type(SchedulePreparedQueueForHandle) == "function" then
            SchedulePreparedQueueForHandle(handle)
        end
    end

    commitQueueState(handle, mp, "queue_remove")
    return true
end

function RemoveFromQueue(handle, index, expectedRevision, sourceId)
    local result
    withQueueLock(handle, function()
        result = removeFromQueueUnlocked(handle, index, expectedRevision, sourceId)
    end)
    return result
end

local function playNextInQueueUnlocked(handle, context)
    context = context or {}
    if rejectStaleQueueMutation(handle, context.source, context.expectedRevision) then
        return false
    end

    local mp = GetMediaPlayer(handle)
    if not mp then
        return false
    end

    local session = getSessionForHandle(handle, mp)
    if not session then
        return false
    end

    ensureSessionQueueMetadata(session)
    local mode = getLoopMode(mp)
    local queue = session.queue or {}
    local queueChanged = false

    local function startPlaybackForOptions(client, queued, sourceId)
        if not client then
            return false
        end

        local options = buildPlaybackOptions(handle, mp, session, queued, {
            immediate = context.immediate == true,
            reason = context.reason or (context.manual and "manual_next" or nil),
            sourceId = sourceId or client,
        })
        if not options then
            return false
        end

        SetRestricted(handle, client)

        EnqueueSync(function()
            StartMediaPlayerForClient(handle, client, options, {
                forceRefresh = not canPlayQueuedOptionsImmediately(queued),
                avoidProvider = mp.resolver and mp.resolver.provider or nil,
                avoidInstance = mp.resolver and mp.resolver.instance or nil,
                avoidResolvedUrl = mp.resolvedUrl,
            })
        end)

        return true
    end

    if mode == "track" then
        local currentTrack = captureCurrentTrackOptions(mp)
        local preferredSource = tonumber(context.source) or tonumber(mp.lastSource) or tonumber(session.lastSource) or nil
        local client = resolveClientFromQueueEntry({ source = preferredSource })
        if currentTrack and client then
            RemoveMediaPlayer(handle, true)
            if startPlaybackForOptions(client, currentTrack, preferredSource) then
                return true
            end
        end
    end

    local shouldRecycleCurrent = (mode == "queue" or mode == "shuffle_loop") and context.skipRecycle ~= true
    if shouldRecycleCurrent then
        local currentTrack = captureCurrentTrackOptions(mp)
        if currentTrack and currentTrack.url then
            local quarantined = type(IsPmmsSourceQuarantined) == "function" and IsPmmsSourceQuarantined(currentTrack)
            if quarantined then
                PMMSDebug("player", "queue recycle skipped for quarantined source", {
                    handle = handle,
                    url = currentTrack.originalUrl or currentTrack.url,
                })
            else
                queue[#queue + 1] = {
                    source = mp.lastSource or context.source,
                    name = mp.lastSource and GetPlayerName(mp.lastSource) or nil,
                    options = currentTrack,
                }
                queueChanged = true
            end
        end
    end

    syncShufflePreviewState(session, mode)

    if #queue <= 0 then
        RemoveMediaPlayer(handle)
        return true
    end

    while #queue > 0 do
        local queueIndex = pickQueueIndex(session, mode)
        if not queueIndex then
            break
        end

        local nextEntry = table.remove(queue, queueIndex)
        queueChanged = true
        local client = resolveClientFromQueueEntry(nextEntry)
        local queued = nextEntry and nextEntry.options or nil
        local signature = getQueueEntrySignature(nextEntry)
        local quarantined = type(IsPmmsSourceQuarantined) == "function"
            and not context.manual
            and IsPmmsSourceQuarantined(queued)

        if quarantined then
            PMMSDebug("player", "queue entry skipped for quarantined source", {
                handle = handle,
                url = queued and (queued.originalUrl or queued.url) or nil,
            })
            syncShufflePreviewState(session, mode)
        else

            if mp.preparedNextSignature == signature and type(mp.preparedNext) == "table" then
                mergeResolvedIntoOptions(queued, mp.preparedNext)
            end

            clearPreparedNext(mp)
            syncShufflePreviewState(session, mode)

            if queueChanged then
                commitQueueState(handle, mp, "queue_next")
                queueChanged = false
            end
            RemoveMediaPlayer(handle, true)
            if startPlaybackForOptions(client, queued, nextEntry and nextEntry.source) then
                return true
            end
        end
    end

    if queueChanged then
        commitQueueState(handle, mp, "queue_next")
    end
    RemoveMediaPlayer(handle)
    return true
end

function PlayNextInQueue(handle, context)
    local result
    withQueueLock(handle, function()
        result = playNextInQueueUnlocked(handle, context)
    end)
    return result
end

local function playPreviousFromHistoryUnlocked(handle, context)
    context = context or {}
    if rejectStaleQueueMutation(handle, context.source, context.expectedRevision) then
        return false
    end

    local mp = GetMediaPlayer(handle)
    local session = getSessionForHandle(handle, mp)
    if not session then
        return false
    end

    local previousTrack = type(PopDeviceHistoryEntry) == "function" and PopDeviceHistoryEntry(handle) or nil
    if not previousTrack then
        return false
    end

    local currentTrack = mp and captureCurrentTrackOptions(mp) or nil
    local currentSource = mp and mp.lastSource or context.source or session.lastSource
    if currentTrack and currentTrack.url and type(PrependDeviceQueueEntry) == "function" then
        PrependDeviceQueueEntry(handle, currentSource, currentTrack)
        session = getSessionForHandle(handle, mp)
    end

    local client = resolveClientFromQueueEntry({ source = currentSource })
    if not client then
        local liveSession = getSessionForHandle(handle, previousTrack)
        if liveSession then
            liveSession.history = liveSession.history or {}
            liveSession.history[#liveSession.history + 1] = previousTrack
            commitQueueState(handle, mp)
        end
        return false
    end

    local options = buildPlaybackOptions(handle, mp, session, previousTrack, {
        immediate = true,
        reason = "manual_previous",
        sourceId = currentSource or client,
    })
    if not options then
        return false
    end

    if mp then
        clearPreparedNext(mp)
        RemoveMediaPlayer(handle, true, { archiveCurrent = false })
    end

    SetRestricted(handle, client)
    EnqueueSync(function()
        StartMediaPlayerForClient(handle, client, options, {
            forceRefresh = not canPlayQueuedOptionsImmediately(previousTrack),
            avoidProvider = mp and mp.resolver and mp.resolver.provider or nil,
            avoidInstance = mp and mp.resolver and mp.resolver.instance or nil,
            avoidResolvedUrl = mp and mp.resolvedUrl or nil,
        })
    end)
    return true
end

function PlayPreviousFromHistory(handle, context)
    local result
    withQueueLock(handle, function()
        result = playPreviousFromHistoryUnlocked(handle, context)
    end)
    return result
end
