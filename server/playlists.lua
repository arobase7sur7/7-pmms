local favoriteMutationState = {}
local libraryRevisionState = {}

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
    local normalizedPlaylists = playlists or {}
    callback({
        libraryRevision = tonumber(revision) or getLibraryRevision(identifier),
        playlists = normalizedPlaylists,
        summary = buildLibrarySummaryFromPlaylists(normalizedPlaylists),
    })
end

local function fetchLibrarySnapshot(identifier, callback, attempt)
    local snapshotAttempt = tonumber(attempt) or 0
    local initialRevision = getLibraryRevision(identifier)

    MySQL.query('SELECT id, name, created_at, is_favorite FROM pmms_playlists WHERE owner_license = ? ORDER BY is_favorite DESC, created_at DESC', { identifier }, function(playlists)
        local currentRevision = getLibraryRevision(identifier)
        if currentRevision ~= initialRevision and snapshotAttempt < 5 then
            fetchLibrarySnapshot(identifier, callback, snapshotAttempt + 1)
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

local function sortLibraryPlaylists(playlists)
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
    runFavoriteMutation(identifier, function(done)
        fetchLibrarySnapshot(identifier, function(snapshot)
            local playlists = snapshot and snapshot.playlists or {}
            local row = findPlaylistById(playlists, id)

            if not row then
                PMMSDebug("favorites", "favorite request rejected: playlist not owned or missing", {
                    src = src,
                    identifier = identifier,
                    playlistId = id,
                    requestId = favoriteRequestId,
                    mutationId = mutationId,
                })
                TriggerClientEvent('pmms:notify', src, {
                    title = "Library",
                    text = "You can only favorite your own playlists.",
                })
                emitFavoriteFailure(src, identifier, id, false, mutationId, favoriteRequestId, "Playlist ownership mismatch.")
                done()
                return
            end

            local currentlyFavorite = tonumber(row.is_favorite) == 1
            if currentlyFavorite == targetFavorite then
                PMMSDebug("favorites", "favorite request already persisted", {
                    src = src,
                    identifier = identifier,
                    playlistId = id,
                    requestId = favoriteRequestId,
                    mutationId = mutationId,
                    favorite = currentlyFavorite,
                    libraryRevision = snapshot.libraryRevision,
                })
                emitFavoriteSuccess(src, identifier, id, currentlyFavorite, mutationId, favoriteRequestId, snapshot)
                done()
                return
            end

            local function finalizeFavorite()
                MySQL.update('UPDATE pmms_playlists SET is_favorite = ? WHERE id = ? AND owner_license = ?', {
                    targetFavorite and 1 or 0,
                    id,
                    identifier,
                }, function()
                    PMMSDebug("favorites", "favorite update written, verifying persisted row", {
                        src = src,
                        identifier = identifier,
                        playlistId = id,
                        requestId = favoriteRequestId,
                        mutationId = mutationId,
                        targetFavorite = targetFavorite,
                    })
                    MySQL.scalar('SELECT is_favorite FROM pmms_playlists WHERE id = ? AND owner_license = ?', {
                        id,
                        identifier,
                    }, function(savedFavorite)
                        local persistedFavorite = normalizeFavoriteFlag(savedFavorite)
                        if persistedFavorite ~= targetFavorite then
                            PMMSDebug("favorites", "favorite verification failed: persisted value mismatch", {
                                src = src,
                                identifier = identifier,
                                playlistId = id,
                                requestId = favoriteRequestId,
                                mutationId = mutationId,
                                targetFavorite = targetFavorite,
                                savedFavorite = savedFavorite,
                                persistedFavorite = persistedFavorite,
                                previousFavorite = currentlyFavorite,
                            })
                            emitFavoriteFailure(src, identifier, id, currentlyFavorite, mutationId, favoriteRequestId, "Favorite update was not saved.")
                            done()
                            return
                        end

                        local actionLabel = targetFavorite and "pinned to favorites" or "removed from favorites"
                        bumpLibraryRevision(identifier)
                        fetchLibrarySnapshot(identifier, function(nextSnapshot)
                            PMMSDebug("favorites", "favorite verified and snapshot refreshed", {
                                src = src,
                                identifier = identifier,
                                playlistId = id,
                                requestId = favoriteRequestId,
                                mutationId = mutationId,
                                targetFavorite = targetFavorite,
                                libraryRevision = nextSnapshot and nextSnapshot.libraryRevision or nil,
                                favoriteCount = nextSnapshot and nextSnapshot.summary and nextSnapshot.summary.favoriteCount or nil,
                            })
                            TriggerClientEvent('pmms:notify', src, {
                                title = "Library",
                                text = ("Playlist %s."):format(actionLabel),
                            })
                            emitFavoriteSuccess(src, identifier, id, targetFavorite, mutationId, favoriteRequestId, nextSnapshot)
                            done()
                        end)
                    end)
                end)
            end

            if not targetFavorite then
                finalizeFavorite()
                return
            end

            local favoriteCount = 0
            for _, playlist in ipairs(playlists) do
                if tonumber(playlist.is_favorite) == 1 then
                    favoriteCount = favoriteCount + 1
                end
            end

            local maxFavorites = getMaxFavoritePlaylists()
            if favoriteCount >= maxFavorites then
                PMMSDebug("favorites", "favorite request rejected: favorite limit reached", {
                    src = src,
                    identifier = identifier,
                    playlistId = id,
                    requestId = favoriteRequestId,
                    mutationId = mutationId,
                    favoriteCount = favoriteCount,
                    maxFavorites = maxFavorites,
                })
                TriggerClientEvent('pmms:notify', src, {
                    title = "Library",
                    text = ("You can only pin %d playlists at once."):format(maxFavorites),
                })
                emitFavoriteFailure(src, identifier, id, currentlyFavorite, mutationId, favoriteRequestId, "Favorite limit reached.")
                done()
                return
            end

            finalizeFavorite()
        end)
    end)
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

        MySQL.query('SELECT id, title, url, duration, added_at FROM pmms_playlist_tracks WHERE playlist_id = ? ORDER BY added_at ASC', { playlistId }, function(tracks)
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

            MySQL.insert('INSERT INTO pmms_playlist_tracks (playlist_id, title, url, duration) VALUES (?, ?, ?, ?)', {
                playlistId,
                title,
                url,
                duration,
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
