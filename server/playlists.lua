local favoriteMutationState = {}
local libraryRevisionState = {}
local sortLibraryPlaylists

local function getPlaylistConfig()
    return Config.playlists or {}
end

local function getMaxPlaylists()
    return math.max(1, tonumber(getPlaylistConfig().maxCount) or 20)
end

local function getMaxFavoritePlaylists()
    return math.max(1, tonumber(getPlaylistConfig().maxFavorites) or 5)
end

local function normalizeFavoriteFlag(value)
    if value == true or value == 1 or value == "1" or value == "true" then
        return true
    end
    if value == false or value == 0 or value == "0" or value == "false" then
        return false
    end
    return nil
end

local function getFavoriteOwnerState(identifier)
    if not favoriteMutationState[identifier] then
        favoriteMutationState[identifier] = {
            busy = false,
            queue = {},
            mutationId = 0,
            snapshot = nil,
            snapshotRevision = nil,
            pendingFavoriteByPlaylist = {},
            activeFavoriteByPlaylist = {},
        }
    end
    return favoriteMutationState[identifier]
end

local function getLibraryRevision(identifier)
    return tonumber(libraryRevisionState[identifier]) or 0
end

local function bumpLibraryRevision(identifier)
    local nextRevision = getLibraryRevision(identifier) + 1
    libraryRevisionState[identifier] = nextRevision
    return nextRevision
end

local function nextFavoriteMutationId(identifier)
    local state = getFavoriteOwnerState(identifier)
    state.mutationId = state.mutationId + 1
    return state.mutationId
end

local function clonePlaylistRow(row)
    local copy = {}
    for key, value in pairs(row or {}) do
        copy[key] = value
    end

    local isFavorite = normalizeFavoriteFlag(copy.is_favorite) == true
    copy.is_favorite = isFavorite and 1 or 0
    copy.isFavorite = isFavorite
    return copy
end

local function clonePlaylistList(playlists)
    local copy = {}
    for index, playlist in ipairs(playlists or {}) do
        copy[index] = clonePlaylistRow(playlist)
    end
    return copy
end

local function cloneLibrarySnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return nil
    end

    return {
        libraryRevision = tonumber(snapshot.libraryRevision) or 0,
        playlists = clonePlaylistList(snapshot.playlists),
        summary = {
            playlistCount = snapshot.summary and snapshot.summary.playlistCount or 0,
            favoriteCount = snapshot.summary and snapshot.summary.favoriteCount or 0,
            maxPlaylists = snapshot.summary and snapshot.summary.maxPlaylists or getMaxPlaylists(),
            maxFavorites = snapshot.summary and snapshot.summary.maxFavorites or getMaxFavoritePlaylists(),
        },
    }
end

local function invalidateLibrarySnapshot(identifier)
    if not identifier then
        return
    end

    local state = getFavoriteOwnerState(identifier)
    state.snapshot = nil
    state.snapshotRevision = nil
end

local function runFavoriteMutation(identifier, executor)
    local state = getFavoriteOwnerState(identifier)
    state.queue[#state.queue + 1] = executor
    PMMSDebug("favorites", "favorite mutation queued", {
        identifier = identifier,
        queueLength = #state.queue,
        busy = state.busy,
    })

    if state.busy then
        return
    end

    local function drain()
        local current = table.remove(state.queue, 1)
        if not current then
            state.busy = false
            PMMSDebug("favorites", "favorite mutation queue drained", {
                identifier = identifier,
            })
            return
        end

        state.busy = true
        PMMSDebug("favorites", "favorite mutation started", {
            identifier = identifier,
            remaining = #state.queue,
        })
        current(function()
            PMMSDebug("favorites", "favorite mutation finished", {
                identifier = identifier,
                remaining = #state.queue,
            })
            drain()
        end)
    end

    drain()
end

local function buildLibrarySummaryFromPlaylists(playlists)
    local favoriteCount = 0

    for _, playlist in ipairs(playlists or {}) do
        if tonumber(playlist.is_favorite) == 1 then
            favoriteCount = favoriteCount + 1
        end
    end

    return {
        playlistCount = #(playlists or {}),
        favoriteCount = favoriteCount,
        maxPlaylists = getMaxPlaylists(),
        maxFavorites = getMaxFavoritePlaylists(),
    }
end

local function finalizeLibrarySnapshot(identifier, playlists, revision, callback)
    local normalizedPlaylists = clonePlaylistList(playlists)
    sortLibraryPlaylists(normalizedPlaylists)

    local snapshot = {
        libraryRevision = tonumber(revision) or getLibraryRevision(identifier),
        playlists = normalizedPlaylists,
        summary = buildLibrarySummaryFromPlaylists(normalizedPlaylists),
    }

    local ownerState = getFavoriteOwnerState(identifier)
    ownerState.snapshot = cloneLibrarySnapshot(snapshot)
    ownerState.snapshotRevision = snapshot.libraryRevision
    callback(cloneLibrarySnapshot(snapshot))
end

local function fetchLibrarySnapshot(identifier, callback, options)
    local fetchOptions = type(options) == "table" and options or {}
    local ownerState = getFavoriteOwnerState(identifier)
    if fetchOptions.force ~= true
        and ownerState.snapshot
        and tonumber(ownerState.snapshotRevision) == getLibraryRevision(identifier) then
        callback(cloneLibrarySnapshot(ownerState.snapshot))
        return
    end

    local snapshotAttempt = tonumber(fetchOptions.attempt) or 0
    local initialRevision = getLibraryRevision(identifier)

    MySQL.query('SELECT id, name, created_at, is_favorite FROM pmms_playlists WHERE owner_license = ? ORDER BY is_favorite DESC, created_at DESC', { identifier }, function(playlists)
        local currentRevision = getLibraryRevision(identifier)
        if currentRevision ~= initialRevision and snapshotAttempt < 5 then
            fetchLibrarySnapshot(identifier, callback, {
                force = true,
                attempt = snapshotAttempt + 1,
            })
            return
        end

        finalizeLibrarySnapshot(
            identifier,
            playlists,
            currentRevision == initialRevision and currentRevision or initialRevision,
            callback
        )
    end)
end

local function findPlaylistById(playlists, playlistId)
    local targetId = tonumber(playlistId)
    if not targetId then
        return nil
    end

    for _, playlist in ipairs(playlists or {}) do
        if tonumber(playlist.id) == targetId then
            return playlist
        end
    end

    return nil
end

sortLibraryPlaylists = function(playlists)
    table.sort(playlists, function(a, b)
        local aFavorite = tonumber(a and a.is_favorite) == 1 and 1 or 0
        local bFavorite = tonumber(b and b.is_favorite) == 1 and 1 or 0
        if aFavorite ~= bFavorite then
            return aFavorite > bFavorite
        end

        local aCreatedAt = tostring(a and a.created_at or "")
        local bCreatedAt = tostring(b and b.created_at or "")
        if aCreatedAt ~= bCreatedAt then
            return aCreatedAt > bCreatedAt
        end

        return tonumber(a and a.id or 0) > tonumber(b and b.id or 0)
    end)
end

local function emitPlaylists(src, identifier, requestId)
    local ownerState = getFavoriteOwnerState(identifier)
    local function sendSnapshot(done)
        fetchLibrarySnapshot(identifier, function(snapshot)
            TriggerClientEvent('pmms:setPlaylists', src, {
                requestId = requestId,
                libraryRevision = snapshot.libraryRevision,
                playlists = snapshot.playlists,
                summary = snapshot.summary,
            })

            if done then
                done()
            end
        end)
    end

    if ownerState.busy or #ownerState.queue > 0 then
        ownerState.queue[#ownerState.queue + 1] = function(done)
            sendSnapshot(done)
        end
        return
    end

    sendSnapshot()
end

local function emitSharedPlaylists(src, identifier, requestId)
    local query = [[
        SELECT p.id, p.name, p.owner_license, sp.shared_with_license
        FROM pmms_shared_playlists sp
        JOIN pmms_playlists p ON sp.playlist_id = p.id
        WHERE sp.shared_with_license = ?
    ]]

    MySQL.query(query, { identifier }, function(playlists)
        TriggerClientEvent('pmms:setSharedPlaylists', src, {
            requestId = requestId,
            playlists = playlists or {},
        })
    end)
end

local function payloadDebugField(payload, key)
    if payload == nil then
        return nil
    end
    return payload[key]
end

local function emitFavoriteUpdate(src, payload)
    PMMSDebug("favorites", "favorite update emitted", {
        src = src,
        playlistId = payloadDebugField(payload, "playlistId"),
        requestId = payloadDebugField(payload, "requestId"),
        mutationId = payloadDebugField(payload, "mutationId"),
        success = payloadDebugField(payload, "success"),
        isFavorite = payloadDebugField(payload, "isFavorite"),
        message = payloadDebugField(payload, "message"),
        libraryRevision = payloadDebugField(payload, "libraryRevision"),
        favoriteCount = payloadDebugField(payload, "favoriteCount"),
        maxFavorites = payloadDebugField(payload, "maxFavorites"),
    })
    TriggerClientEvent('pmms:playlistFavoriteUpdated', src, payload)
end

local function emitFavoriteResult(src, identifier, playlistId, mutationId, requestId, expectedFavorite, success, message, snapshotOverride)
    local function emitSnapshot(snapshot)
        local row = findPlaylistById(snapshot.playlists, playlistId)
        local actualFavorite = expectedFavorite == true
        local actualSuccess = success == true
        local actualMessage = message

        if row then
            actualFavorite = tonumber(row.is_favorite) == 1
            if actualSuccess and expectedFavorite ~= nil and actualFavorite ~= (expectedFavorite == true) then
                actualSuccess = false
                actualMessage = actualMessage or "Favorite state did not persist."
            end
        else
            actualSuccess = false
            actualFavorite = false
            actualMessage = actualMessage or "Playlist no longer exists."
        end

        emitFavoriteUpdate(src, {
            mutationId = mutationId,
            requestId = requestId,
            playlistId = tonumber(playlistId),
            playlist = row,
            is_favorite = actualFavorite and 1 or 0,
            isFavorite = actualFavorite,
            requestedFavorite = expectedFavorite,
            success = actualSuccess,
            favoriteCount = snapshot.summary.favoriteCount,
            maxFavorites = snapshot.summary.maxFavorites,
            playlistCount = snapshot.summary.playlistCount,
            maxPlaylists = snapshot.summary.maxPlaylists,
            message = actualMessage,
            libraryRevision = snapshot.libraryRevision,
            playlists = snapshot.playlists,
            summary = snapshot.summary,
        })
    end

    if type(snapshotOverride) == "table" then
        emitSnapshot(snapshotOverride)
        return
    end

    fetchLibrarySnapshot(identifier, function(snapshot)
        emitSnapshot(snapshot)
    end)
end

local function emitFavoriteFailure(src, identifier, playlistId, isFavorite, mutationId, requestId, message)
    emitFavoriteResult(src, identifier, playlistId, mutationId, requestId, isFavorite == true, false, message)
end

local function emitFavoriteSuccess(src, identifier, playlistId, isFavorite, mutationId, requestId, snapshot)
    emitFavoriteResult(src, identifier, playlistId, mutationId, requestId, isFavorite == true, true, nil, snapshot)
end

local function emitFavoriteToListeners(listeners, identifier, playlistId, actualFavorite, success, message, snapshot)
    for _, listener in ipairs(listeners or {}) do
        if success then
            emitFavoriteSuccess(
                listener.src,
                identifier,
                playlistId,
                actualFavorite == true,
                listener.mutationId,
                listener.requestId,
                snapshot
            )
        else
            emitFavoriteFailure(
                listener.src,
                identifier,
                playlistId,
                actualFavorite == true,
                listener.mutationId,
                listener.requestId,
                message
            )
        end
    end
end

local function processFavoriteMutationEntry(identifier, entry, done)
    local id = tonumber(entry and entry.playlistId)
    local targetFavorite = entry and entry.targetFavorite == true
    local listeners = entry and entry.listeners or {}

    local function finish()
        if done then
            done()
        end
    end

    fetchLibrarySnapshot(identifier, function(snapshot)
        local playlists = snapshot and snapshot.playlists or {}
        local row = findPlaylistById(playlists, id)

        if not row then
            PMMSDebug("favorites", "favorite request rejected: playlist not owned or missing", {
                identifier = identifier,
                playlistId = id,
                listenerCount = #listeners,
            })
            for _, listener in ipairs(listeners) do
                TriggerClientEvent('pmms:notify', listener.src, {
                    title = "Library",
                    text = "You can only favorite your own playlists.",
                })
            end
            emitFavoriteToListeners(listeners, identifier, id, false, false, "Playlist ownership mismatch.")
            finish()
            return
        end

        local currentlyFavorite = tonumber(row.is_favorite) == 1
        if currentlyFavorite == targetFavorite then
            PMMSDebug("favorites", "favorite request already persisted", {
                identifier = identifier,
                playlistId = id,
                favorite = currentlyFavorite,
                listenerCount = #listeners,
                libraryRevision = snapshot.libraryRevision,
            })
            emitFavoriteToListeners(listeners, identifier, id, currentlyFavorite, true, nil, snapshot)
            finish()
            return
        end

        if targetFavorite then
            local favoriteCount = 0
            for _, playlist in ipairs(playlists) do
                if tonumber(playlist.is_favorite) == 1 then
                    favoriteCount = favoriteCount + 1
                end
            end

            local maxFavorites = getMaxFavoritePlaylists()
            if favoriteCount >= maxFavorites then
                PMMSDebug("favorites", "favorite request rejected: favorite limit reached", {
                    identifier = identifier,
                    playlistId = id,
                    favoriteCount = favoriteCount,
                    maxFavorites = maxFavorites,
                    listenerCount = #listeners,
                })
                for _, listener in ipairs(listeners) do
                    TriggerClientEvent('pmms:notify', listener.src, {
                        title = "Library",
                        text = ("You can only pin %d playlists at once."):format(maxFavorites),
                    })
                end
                emitFavoriteToListeners(listeners, identifier, id, currentlyFavorite, false, "Favorite limit reached.")
                finish()
                return
            end
        end

        local targetValue = targetFavorite and 1 or 0
        MySQL.update('UPDATE pmms_playlists SET is_favorite = ? WHERE id = ? AND owner_license = ? AND is_favorite <> ?', {
            targetValue,
            id,
            identifier,
            targetValue,
        }, function(affectedRows)
            local changed = (tonumber(affectedRows) or 0) > 0
            if changed then
                bumpLibraryRevision(identifier)
            else
                invalidateLibrarySnapshot(identifier)
            end

            fetchLibrarySnapshot(identifier, function(nextSnapshot)
                local nextRow = findPlaylistById(nextSnapshot and nextSnapshot.playlists or {}, id)
                local persistedFavorite = nextRow and tonumber(nextRow.is_favorite) == 1 or false
                if persistedFavorite ~= targetFavorite then
                    PMMSDebug("favorites", "favorite verification failed: persisted value mismatch", {
                        identifier = identifier,
                        playlistId = id,
                        targetFavorite = targetFavorite,
                        persistedFavorite = persistedFavorite,
                        previousFavorite = currentlyFavorite,
                        affectedRows = affectedRows,
                    })
                    emitFavoriteToListeners(listeners, identifier, id, currentlyFavorite, false, "Favorite update was not saved.")
                    finish()
                    return
                end

                local actionLabel = targetFavorite and "pinned to favorites" or "removed from favorites"
                PMMSDebug("favorites", "favorite persisted and snapshot refreshed", {
                    identifier = identifier,
                    playlistId = id,
                    targetFavorite = targetFavorite,
                    affectedRows = affectedRows,
                    listenerCount = #listeners,
                    libraryRevision = nextSnapshot and nextSnapshot.libraryRevision or nil,
                    favoriteCount = nextSnapshot and nextSnapshot.summary and nextSnapshot.summary.favoriteCount or nil,
                })
                for _, listener in ipairs(listeners) do
                    TriggerClientEvent('pmms:notify', listener.src, {
                        title = "Library",
                        text = ("Playlist %s."):format(actionLabel),
                    })
                end
                emitFavoriteToListeners(listeners, identifier, id, targetFavorite, true, nil, nextSnapshot)
                finish()
            end, { force = true })
        end)
    end)
end

local function queueFavoriteMutation(identifier, playlistId, targetFavorite, listener)
    local ownerState = getFavoriteOwnerState(identifier)
    local key = tostring(playlistId)
    local active = ownerState.activeFavoriteByPlaylist[key]
    if active and active.targetFavorite == targetFavorite then
        active.listeners[#active.listeners + 1] = listener
        PMMSDebug("favorites", "favorite mutation coalesced with active request", {
            identifier = identifier,
            playlistId = playlistId,
            favorite = targetFavorite,
            listenerCount = #active.listeners,
        })
        return
    end

    local pending = ownerState.pendingFavoriteByPlaylist[key]
    if pending then
        pending.targetFavorite = targetFavorite
        pending.listeners[#pending.listeners + 1] = listener
        PMMSDebug("favorites", "favorite mutation coalesced with queued request", {
            identifier = identifier,
            playlistId = playlistId,
            favorite = targetFavorite,
            listenerCount = #pending.listeners,
        })
        return
    end

    local entry = {
        playlistId = playlistId,
        targetFavorite = targetFavorite == true,
        listeners = { listener },
    }
    ownerState.pendingFavoriteByPlaylist[key] = entry

    runFavoriteMutation(identifier, function(done)
        ownerState.pendingFavoriteByPlaylist[key] = nil
        ownerState.activeFavoriteByPlaylist[key] = entry
        processFavoriteMutationEntry(identifier, entry, function()
            ownerState.activeFavoriteByPlaylist[key] = nil
            done()
        end)
    end)
end

RegisterNetEvent('pmms:getPlaylists')
AddEventHandler('pmms:getPlaylists', function(requestId)
    local src = source
    local identifier = GetUserIdentifier(src)
    if not identifier then
        return
    end

    emitPlaylists(src, identifier, requestId)
end)

RegisterNetEvent('pmms:getSharedPlaylists')
AddEventHandler('pmms:getSharedPlaylists', function(requestId)
    local src = source
    local identifier = GetUserIdentifier(src)
    if not identifier then
        return
    end

    emitSharedPlaylists(src, identifier, requestId)
end)

RegisterNetEvent('pmms:createPlaylist')
AddEventHandler('pmms:createPlaylist', function(name)
    local src = source
    local identifier = GetUserIdentifier(src)
    if not identifier or type(name) ~= "string" or name:match("^%s*$") or #name > 50 then
        return
    end

    name = name:match("^%s*(.-)%s*$")

    MySQL.scalar('SELECT COUNT(*) FROM pmms_playlists WHERE owner_license = ?', { identifier }, function(count)
        local playlistCount = tonumber(count) or 0
        local maxPlaylists = getMaxPlaylists()
        if playlistCount >= maxPlaylists then
            TriggerClientEvent('pmms:notify', src, {
                title = "Library",
                text = ("You have reached the maximum of %d playlists."):format(maxPlaylists),
            })
            return
        end

        MySQL.insert('INSERT INTO pmms_playlists (owner_license, name) VALUES (?, ?)', { identifier, name }, function(id)
            if not id then
                return
            end

            bumpLibraryRevision(identifier)
            invalidateLibrarySnapshot(identifier)

            TriggerClientEvent('pmms:notify', src, {
                title = "Library",
                text = "Playlist '" .. name .. "' created!",
            })
            TriggerClientEvent('pmms:refreshLibrary', src)
        end)
    end)
end)

RegisterNetEvent('pmms:setPlaylistFavorite')
AddEventHandler('pmms:setPlaylistFavorite', function(playlistId, favorite, requestId)
    local src = source
    local identifier = GetUserIdentifier(src)
    local id = tonumber(playlistId)
    local targetFavorite = normalizeFavoriteFlag(favorite)

    PMMSDebug("favorites", "favorite request received", {
        src = src,
        identifier = identifier,
        playlistId = playlistId,
        normalizedPlaylistId = id,
        favorite = favorite,
        targetFavorite = targetFavorite,
        requestId = requestId,
    })

    if not identifier or not id or targetFavorite == nil then
        PMMSDebug("favorites", "favorite request rejected: invalid input", {
            src = src,
            identifier = identifier,
            playlistId = playlistId,
            favorite = favorite,
            requestId = requestId,
        })
        TriggerClientEvent('pmms:notify', src, {
            title = "Library",
            text = "Invalid favorite action.",
        })
        emitFavoriteUpdate(src, {
            playlistId = id,
            is_favorite = 0,
            isFavorite = false,
            success = false,
            mutationId = nextFavoriteMutationId(identifier or ("invalid:" .. tostring(src))),
            requestId = tonumber(requestId),
        })
        return
    end

    local mutationId = nextFavoriteMutationId(identifier)
    local favoriteRequestId = tonumber(requestId)
    queueFavoriteMutation(identifier, id, targetFavorite, {
        src = src,
        requestId = favoriteRequestId,
        mutationId = mutationId,
        requestedFavorite = targetFavorite,
    })
end)

RegisterNetEvent('pmms:deletePlaylist')
AddEventHandler('pmms:deletePlaylist', function(playlistId)
    local src = source
    local identifier = GetUserIdentifier(src)
    if not identifier or not playlistId then
        return
    end

    MySQL.scalar('SELECT owner_license FROM pmms_playlists WHERE id = ?', { playlistId }, function(owner)
        if owner ~= identifier then
            TriggerClientEvent('pmms:notify', src, {
                title = "Error",
                text = "You don't own this playlist.",
            })
            return
        end

        MySQL.update('DELETE FROM pmms_playlists WHERE id = ?', { playlistId }, function()
            bumpLibraryRevision(identifier)
            invalidateLibrarySnapshot(identifier)
            TriggerClientEvent('pmms:notify', src, {
                title = "Library",
                text = "Playlist deleted.",
            })
            TriggerClientEvent('pmms:refreshLibrary', src)
        end)
    end)
end)

RegisterNetEvent('pmms:getPlaylistTracks')
AddEventHandler('pmms:getPlaylistTracks', function(playlistId)
    local src = source
    local identifier = GetUserIdentifier(src)
    if not identifier or not playlistId then
        return
    end

    local query = [[
        SELECT p.owner_license,
               (SELECT COUNT(*) FROM pmms_shared_playlists sp WHERE sp.playlist_id = p.id AND sp.shared_with_license = ?) AS isShared
        FROM pmms_playlists p
        WHERE p.id = ?
    ]]

    MySQL.query(query, { identifier, playlistId }, function(result)
        if not result or not result[1] or (result[1].owner_license ~= identifier and tonumber(result[1].isShared) <= 0) then
            TriggerClientEvent('pmms:notify', src, {
                title = "Error",
                text = "Access restricted.",
            })
            return
        end

        MySQL.query('SELECT id, title, url, duration, metadata, added_at FROM pmms_playlist_tracks WHERE playlist_id = ? ORDER BY added_at ASC', { playlistId }, function(tracks)
            for _, track in ipairs(tracks or {}) do
                if type(track.metadata) == "string" and track.metadata ~= "" then
                    local ok, metadata = pcall(json.decode, track.metadata)
                    if ok and type(metadata) == "table" then
                        for key, value in pairs(metadata) do
                            if track[key] == nil then
                                track[key] = value
                            end
                        end
                    end
                end
                track.metadata = nil
            end
            TriggerClientEvent('pmms:setPlaylistTracks', src, playlistId, tracks or {})
        end)
    end)
end)

RegisterNetEvent('pmms:addTrack')
AddEventHandler('pmms:addTrack', function(playlistId, trackData)
    local src = source
    local identifier = GetUserIdentifier(src)
    if not identifier
        or type(playlistId) ~= "number"
        or type(trackData) ~= "table"
        or type(trackData.url) ~= "string"
        or type(trackData.title) ~= "string"
        or trackData.url == ""
        or trackData.title == "" then
        return
    end

    MySQL.scalar('SELECT owner_license FROM pmms_playlists WHERE id = ?', { playlistId }, function(owner)
        if owner ~= identifier then
            TriggerClientEvent('pmms:notify', src, {
                title = "Error",
                text = "You cannot add to this playlist.",
            })
            return
        end

        MySQL.scalar('SELECT COUNT(*) FROM pmms_playlist_tracks WHERE playlist_id = ?', { playlistId }, function(trackCount)
            if tonumber(trackCount) and tonumber(trackCount) >= 100 then
                TriggerClientEvent('pmms:notify', src, {
                    title = "Error",
                    text = "Playlist is full (max 100 tracks).",
                })
                return
            end

            local duration = tonumber(trackData.duration) or 0
            local title = string.sub(trackData.title, 1, 100)
            local url = string.sub(trackData.url, 1, 500)
            local metadata = {
                author = trackData.author,
                thumbnail = trackData.thumbnail,
                source = trackData.source,
                live = trackData.live == true,
                radio = trackData.radio == true,
                video = trackData.video ~= false,
            }

            MySQL.insert('INSERT INTO pmms_playlist_tracks (playlist_id, title, url, duration, metadata) VALUES (?, ?, ?, ?, ?)', {
                playlistId,
                title,
                url,
                duration,
                json.encode(metadata),
            }, function()
                TriggerClientEvent('pmms:notify', src, {
                    title = "Library",
                    text = "Song added to playlist!",
                })
                TriggerClientEvent('pmms:refreshPlaylist', src, playlistId)
            end)
        end)
    end)
end)

RegisterNetEvent('pmms:removeTrack')
AddEventHandler('pmms:removeTrack', function(playlistId, trackId)
    local src = source
    local identifier = GetUserIdentifier(src)
    if not identifier or not playlistId or not trackId then
        return
    end

    MySQL.scalar('SELECT owner_license FROM pmms_playlists WHERE id = ?', { playlistId }, function(owner)
        if owner ~= identifier then
            TriggerClientEvent('pmms:notify', src, {
                title = "Error",
                text = "You cannot edit this playlist.",
            })
            return
        end

        MySQL.update('DELETE FROM pmms_playlist_tracks WHERE id = ? AND playlist_id = ?', { trackId, playlistId }, function()
            TriggerClientEvent('pmms:notify', src, {
                title = "Library",
                text = "Song removed from playlist.",
            })
            TriggerClientEvent('pmms:refreshPlaylist', src, playlistId)
        end)
    end)
end)

RegisterNetEvent('pmms:sharePlaylist')
AddEventHandler('pmms:sharePlaylist', function(playlistId, friendLicense)
    local src = source
    local identifier = GetUserIdentifier(src)
    if not identifier or not playlistId or type(friendLicense) ~= "string" or friendLicense == "" then
        return
    end

    MySQL.scalar('SELECT owner_license FROM pmms_playlists WHERE id = ?', { playlistId }, function(owner)
        if owner ~= identifier then
            TriggerClientEvent('pmms:notify', src, {
                title = "Error",
                text = "You don't own this playlist.",
            })
            return
        end

        MySQL.insert('INSERT INTO pmms_shared_playlists (playlist_id, shared_with_license) VALUES (?, ?) ON DUPLICATE KEY UPDATE playlist_id=playlist_id', {
            playlistId,
            friendLicense,
        }, function()
            TriggerClientEvent('pmms:notify', src, {
                title = "Library",
                text = "Playlist shared!",
            })
            TriggerClientEvent('pmms:refreshLibrary', src)
        end)
    end)
end)
