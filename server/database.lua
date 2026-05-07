local function ensureColumn(tableName, columnName, definition)
    MySQL.scalar([[
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = ?
          AND COLUMN_NAME = ?
    ]], { tableName, columnName }, function(exists)
        if tonumber(exists) and tonumber(exists) > 0 then
            return
        end

        MySQL.query(("ALTER TABLE `%s` ADD COLUMN `%s` %s"):format(tableName, columnName, definition), {}, function()
            print(("^2[7-pmms] Added missing column %s.%s.^7"):format(tableName, columnName))
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
    ensureColumn("pmms_playlists", "is_favorite", "TINYINT(1) NOT NULL DEFAULT 0")
    ensureTable("pmms_known_players", [[
        CREATE TABLE IF NOT EXISTS `pmms_known_players` (
          `license` varchar(64) NOT NULL,
          `display_name` varchar(255) DEFAULT NULL,
          `last_seen_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `last_menu_opened_at` timestamp NULL DEFAULT NULL,
          PRIMARY KEY (`license`)
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
