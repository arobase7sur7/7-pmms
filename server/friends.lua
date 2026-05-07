local function getSocialConfig()
    return Config.social or {}
end

local function getRecentPlayerExpiryDays()
    return math.max(1, tonumber(getSocialConfig().recentPlayerExpiryDays) or 30)
end

local function getMaxSuggestions()
    return math.max(3, tonumber(getSocialConfig().maxSuggestions) or 10)
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

local function getDisplayNameFromLicense(license, callback)
    GetKnownPlayerDisplayName(license, function(displayName, liveSource)
        callback(displayName or license, liveSource)
    end)
end

local function emitFriends(src, identifier)
    local query = [[
        SELECT
            id,
            IF(user_license = ?, friend_license, user_license) AS friend_license,
            COALESCE(kp.display_name, friend_name, IF(user_license = ?, friend_license, user_license)) AS friend_name
        FROM pmms_friends
        LEFT JOIN pmms_known_players kp
            ON kp.license = IF(user_license = ?, friend_license, user_license)
        WHERE (user_license = ? OR friend_license = ?)
          AND status = 'accepted'
        ORDER BY friend_name ASC
    ]]

    MySQL.query(query, { identifier, identifier, identifier, identifier, identifier }, function(friends)
        TriggerClientEvent('pmms:setFriends', src, friends or {})
    end)
end

local function emitFriendRequests(src, identifier)
    local query = [[
        SELECT
            f.id,
            f.user_license,
            COALESCE(kp.display_name, f.friend_name, f.user_license) AS requester_name
        FROM pmms_friends f
        LEFT JOIN pmms_known_players kp ON kp.license = f.user_license
        WHERE f.friend_license = ?
          AND f.status = 'pending'
        ORDER BY requester_name ASC
    ]]

    MySQL.query(query, { identifier }, function(requests)
        TriggerClientEvent('pmms:setFriendRequests', src, requests or {})
    end)
end

local function normalizeSuggestionQuery(query)
    local trimmed = trimText(query)
    if not trimmed then
        return ""
    end
    return string.sub(trimmed, 1, 64)
end

local function buildSuggestionEntry(license, displayName, isOnline, sourceId, score)
    return {
        license = license,
        displayName = displayName or license,
        online = isOnline == true,
        targetSrc = sourceId,
        score = score or 0,
    }
end

local function getOnlineSuggestions(requesterLicense, query)
    local normalizedQuery = string.lower(normalizeSuggestionQuery(query))
    local suggestions = {}
    local seen = {}

    for _, playerId in ipairs(GetPlayers()) do
        local numericPlayerId = tonumber(playerId) or playerId
        local license = GetUserIdentifier(numericPlayerId)
        local displayName = GetPlayerName(numericPlayerId)
        if license and displayName and license ~= requesterLicense then
            local haystackName = string.lower(displayName)
            local haystackLicense = string.lower(license)
            if normalizedQuery == ""
                or haystackName:find(normalizedQuery, 1, true)
                or haystackLicense:find(normalizedQuery, 1, true) then
                suggestions[#suggestions + 1] = buildSuggestionEntry(license, displayName, true, numericPlayerId, 1000)
                seen[license] = true
            end
        end
    end

    table.sort(suggestions, function(a, b)
        return string.lower(a.displayName) < string.lower(b.displayName)
    end)

    return suggestions, seen
end

local function emitSuggestions(src, identifier, query, requestId)
    local limit = getMaxSuggestions()
    local suggestions, seen = getOnlineSuggestions(identifier, query)
    local normalizedQuery = normalizeSuggestionQuery(query)
    local sqlQuery = [[
        SELECT
            license,
            display_name,
            UNIX_TIMESTAMP(COALESCE(last_menu_opened_at, last_seen_at)) AS activity_at
        FROM pmms_known_players
        WHERE license != ?
          AND last_seen_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
          AND (? = '' OR display_name LIKE ? OR license LIKE ?)
        ORDER BY COALESCE(last_menu_opened_at, last_seen_at) DESC
        LIMIT ?
    ]]
    local queryLike = "%" .. normalizedQuery .. "%"

    MySQL.query(sqlQuery, {
        identifier,
        getRecentPlayerExpiryDays(),
        normalizedQuery,
        queryLike,
        queryLike,
        limit * 2,
    }, function(rows)
        for _, row in ipairs(rows or {}) do
            if #suggestions >= limit then
                break
            end

            if row.license and not seen[row.license] then
                suggestions[#suggestions + 1] = buildSuggestionEntry(row.license, row.display_name or row.license, false, nil, tonumber(row.activity_at) or 0)
                seen[row.license] = true
            end
        end

        TriggerClientEvent('pmms:setPlayerSuggestions', src, {
            requestId = requestId,
            suggestions = suggestions,
        })
    end)
end

RegisterNetEvent('pmms:markMenuOpened')
AddEventHandler('pmms:markMenuOpened', function()
    UpsertKnownPlayer(source, true)
end)

RegisterNetEvent('pmms:getFriends')
AddEventHandler('pmms:getFriends', function()
    local src = source
    local identifier = GetUserIdentifier(src)
    if not identifier then
        return
    end

    UpsertKnownPlayer(src, false)
    emitFriends(src, identifier)
end)

RegisterNetEvent('pmms:getFriendRequests')
AddEventHandler('pmms:getFriendRequests', function()
    local src = source
    local identifier = GetUserIdentifier(src)
    if not identifier then
        return
    end

    UpsertKnownPlayer(src, false)
    emitFriendRequests(src, identifier)
end)

RegisterNetEvent('pmms:getPlayerSuggestions')
AddEventHandler('pmms:getPlayerSuggestions', function(query, requestId)
    local src = source
    local identifier = GetUserIdentifier(src)
    if not identifier then
        return
    end

    emitSuggestions(src, identifier, query, requestId)
end)

RegisterNetEvent('pmms:sendFriendRequest')
AddEventHandler('pmms:sendFriendRequest', function(targetSrc, targetLicense)
    local src = source
    local identifier = GetUserIdentifier(src)
    if not identifier then
        return
    end

    local resolvedTargetSrc = tonumber(targetSrc)
    local resolvedTargetLicense = trimText(targetLicense)

    if resolvedTargetSrc and resolvedTargetSrc > 0 and GetPlayerName(resolvedTargetSrc) then
        resolvedTargetLicense = GetUserIdentifier(resolvedTargetSrc)
    end

    if not resolvedTargetLicense or resolvedTargetLicense == identifier then
        TriggerClientEvent('pmms:notify', src, {
            title = "Friends",
            text = "Select a valid player.",
        })
        return
    end

    UpsertKnownPlayer(src, false)

    MySQL.scalar('SELECT license FROM pmms_known_players WHERE license = ?', { resolvedTargetLicense }, function(knownLicense)
        if not knownLicense and not resolvedTargetSrc then
            TriggerClientEvent('pmms:notify', src, {
                title = "Friends",
                text = "Player not found.",
            })
            return
        end

        local myName = GetPlayerName(src) or identifier
        local existingQuery = [[
            SELECT id
            FROM pmms_friends
            WHERE (user_license = ? AND friend_license = ?)
               OR (user_license = ? AND friend_license = ?)
        ]]

        MySQL.scalar(existingQuery, {
            identifier,
            resolvedTargetLicense,
            resolvedTargetLicense,
            identifier,
        }, function(existingId)
            if existingId then
                TriggerClientEvent('pmms:notify', src, {
                    title = "Friends",
                    text = "You are already friends or have a pending request.",
                })
                return
            end

            MySQL.insert('INSERT INTO pmms_friends (user_license, friend_license, friend_name, status) VALUES (?, ?, ?, ?)', {
                identifier,
                resolvedTargetLicense,
                myName,
                'pending',
            }, function()
                getDisplayNameFromLicense(resolvedTargetLicense, function(displayName, liveSource)
                    TriggerClientEvent('pmms:notify', src, {
                        title = "Friends",
                        text = "Friend request sent to " .. (displayName or resolvedTargetLicense),
                    })

                    if liveSource then
                        TriggerClientEvent('pmms:notify', liveSource, {
                            title = "Friend Request",
                            text = myName .. " sent you a friend request!",
                        })
                        TriggerClientEvent('pmms:refreshSocial', liveSource)
                    end
                end)
            end)
        end)
    end)
end)

RegisterNetEvent('pmms:acceptFriendRequest')
AddEventHandler('pmms:acceptFriendRequest', function(requestId)
    local src = source
    local identifier = GetUserIdentifier(src)
    if not identifier then
        return
    end

    UpsertKnownPlayer(src, false)

    MySQL.update('UPDATE pmms_friends SET status = ? WHERE id = ? AND friend_license = ?', {
        'accepted',
        requestId,
        identifier,
    }, function(affectedRows)
        if tonumber(affectedRows) <= 0 then
            return
        end

        TriggerClientEvent('pmms:notify', src, {
            title = "Friends",
            text = "Friend request accepted.",
        })
        TriggerClientEvent('pmms:refreshSocial', src)

        MySQL.scalar('SELECT user_license FROM pmms_friends WHERE id = ?', { requestId }, function(senderLicense)
            local senderSource = senderLicense and GetLivePlayerSourceByLicense(senderLicense) or nil
            if not senderSource then
                return
            end

            TriggerClientEvent('pmms:notify', senderSource, {
                title = "Friends",
                text = (GetPlayerName(src) or "A player") .. " accepted your friend request!",
            })
            TriggerClientEvent('pmms:refreshSocial', senderSource)
        end)
    end)
end)

RegisterNetEvent('pmms:removeFriend')
AddEventHandler('pmms:removeFriend', function(friendLicense)
    local src = source
    local identifier = GetUserIdentifier(src)
    local normalizedLicense = trimText(friendLicense)
    if not identifier or not normalizedLicense then
        return
    end

    MySQL.update('DELETE FROM pmms_friends WHERE (user_license = ? AND friend_license = ?) OR (user_license = ? AND friend_license = ?)', {
        identifier,
        normalizedLicense,
        normalizedLicense,
        identifier,
    }, function(affectedRows)
        if tonumber(affectedRows) <= 0 then
            return
        end

        TriggerClientEvent('pmms:notify', src, {
            title = "Friends",
            text = "Friend removed.",
        })
        TriggerClientEvent('pmms:refreshSocial', src)

        local friendSource = GetLivePlayerSourceByLicense(normalizedLicense)
        if friendSource then
            TriggerClientEvent('pmms:refreshSocial', friendSource)
        end
    end)
end)
