local function ensureColumn(tableName, columnName, definition, done)
    MySQL.scalar([[
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = ?
          AND COLUMN_NAME = ?
    ]], { tableName, columnName }, function(exists)
        if tonumber(exists) and tonumber(exists) > 0 then
            if done then
                done()
            end
            return
        end

        MySQL.query(("ALTER TABLE `%s` ADD COLUMN `%s` %s"):format(tableName, columnName, definition), {}, function()
            print(("^2[7-pmms] Added missing column %s.%s.^7"):format(tableName, columnName))
            if done then
                done()
            end
        end)
    end)
end

local function ensureIndex(tableName, indexName, definition, done)
    MySQL.scalar([[
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = ?
          AND INDEX_NAME = ?
    ]], { tableName, indexName }, function(exists)
        if tonumber(exists) and tonumber(exists) > 0 then
            if done then
                done()
            end
            return
        end

        MySQL.query(("ALTER TABLE `%s` ADD %s"):format(tableName, definition), {}, function()
            print(("^2[7-pmms] Added missing index %s.%s.^7"):format(tableName, indexName))
            if done then
                done()
            end
        end)
    end)
end

local function ensureTable(tableName, createSql)
    MySQL.scalar([[
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = ?
    ]], { tableName }, function(exists)
        if tonumber(exists) and tonumber(exists) > 0 then
            return
        end

        MySQL.query(createSql, {}, function()
            print(("^2[7-pmms] Added missing table %s.^7"):format(tableName))
        end)
    end)
end

local function ensureSchemas()
    ensureColumn("pmms_playlists", "is_favorite", "TINYINT(1) NOT NULL DEFAULT 0", function()
        ensureIndex("pmms_playlists", "unique_pmms_playlist_owner_id", "UNIQUE KEY `unique_pmms_playlist_owner_id` (`owner_license`, `id`)", function()
            ensureIndex("pmms_playlists", "idx_pmms_playlists_owner_favorite", "INDEX `idx_pmms_playlists_owner_favorite` (`owner_license`, `is_favorite`, `created_at`)")
        end)
    end)
    ensureColumn("pmms_playlist_tracks", "metadata", "LONGTEXT DEFAULT NULL", function()
        ensureIndex("pmms_playlist_tracks", "idx_pmms_playlist_tracks_playlist_added", "INDEX `idx_pmms_playlist_tracks_playlist_added` (`playlist_id`, `added_at`, `id`)")
    end)
    ensureIndex("pmms_friends", "idx_pmms_friends_recipient_status", "INDEX `idx_pmms_friends_recipient_status` (`friend_license`, `status`, `created_at`)")
    ensureIndex("pmms_shared_playlists", "idx_pmms_shared_playlists_recipient", "INDEX `idx_pmms_shared_playlists_recipient` (`shared_with_license`, `playlist_id`)")
    ensureTable("pmms_known_players", [[
        CREATE TABLE IF NOT EXISTS `pmms_known_players` (
          `license` varchar(64) NOT NULL,
          `display_name` varchar(255) DEFAULT NULL,
          `last_seen_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `last_menu_opened_at` timestamp NULL DEFAULT NULL,
          PRIMARY KEY (`license`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    ensureTable("pmms_persistent_devices", [[
        CREATE TABLE IF NOT EXISTS `pmms_persistent_devices` (
          `handle` varchar(32) NOT NULL,
          `x` double NOT NULL,
          `y` double NOT NULL,
          `z` double NOT NULL,
          `data` longtext NOT NULL,
          `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`handle`),
          KEY `idx_pmms_persistent_devices_coords` (`x`, `y`, `z`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    ensureTable("pmms_persistence_meta", [[
        CREATE TABLE IF NOT EXISTS `pmms_persistence_meta` (
          `name` varchar(64) NOT NULL,
          `value` varchar(255) NOT NULL,
          `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

local function initDatabase()
    local sql = LoadResourceFile(GetCurrentResourceName(), "pmms.sql")
    if not sql then
        print("^1[7-pmms] Error: pmms.sql file not found. Database features will not work.^7")
        return
    end

    local statements = {}
    for statement in string.gmatch(sql, "([^;]+);") do
        local cleaned = statement:gsub("^%s+", ""):gsub("%s+$", "")
        if cleaned ~= "" then
            statements[#statements + 1] = cleaned
        end
    end

    MySQL.ready(function()
        local executed = 0
        for _, statement in ipairs(statements) do
            MySQL.query(statement, {}, function()
                executed = executed + 1
                if executed == #statements then
                    print("^2[7-pmms] Successfully verified and initialized database tables.^7")
                    ensureSchemas()
                end
            end)
        end
    end)
end

CreateThread(function()
    initDatabase()
end)

function GetUserIdentifier(source)
    local identifiers = GetPlayerIdentifiers(source)
    for _, identifier in ipairs(identifiers) do
        if string.match(identifier, "license:") then
            return identifier
        end
    end
    return identifiers[1]
end

function GetLivePlayerSourceByLicense(license)
    if type(license) ~= "string" or license == "" then
        return nil
    end

    for _, playerId in ipairs(GetPlayers()) do
        local numericPlayerId = tonumber(playerId) or playerId
        if GetUserIdentifier(numericPlayerId) == license then
            return numericPlayerId
        end
    end

    return nil
end

function UpsertKnownPlayer(source, openedMenu)
    local identifier = GetUserIdentifier(source)
    local displayName = GetPlayerName(source)
    if not identifier or not displayName or displayName == "" then
        return
    end

    if openedMenu == true then
        MySQL.query([[
            INSERT INTO pmms_known_players (license, display_name, last_seen_at, last_menu_opened_at)
            VALUES (?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON DUPLICATE KEY UPDATE
                display_name = VALUES(display_name),
                last_seen_at = CURRENT_TIMESTAMP,
                last_menu_opened_at = CURRENT_TIMESTAMP
        ]], { identifier, displayName })
        return
    end

    MySQL.query([[
        INSERT INTO pmms_known_players (license, display_name, last_seen_at)
        VALUES (?, ?, CURRENT_TIMESTAMP)
        ON DUPLICATE KEY UPDATE
            display_name = VALUES(display_name),
            last_seen_at = CURRENT_TIMESTAMP
    ]], { identifier, displayName })
end

function GetKnownPlayerDisplayName(license, callback)
    local liveSource = GetLivePlayerSourceByLicense(license)
    if liveSource then
        callback(GetPlayerName(liveSource), liveSource)
        return
    end

    MySQL.scalar("SELECT display_name FROM pmms_known_players WHERE license = ?", { license }, function(displayName)
        callback(displayName, nil)
    end)
end
