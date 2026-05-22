local thisResource = GetCurrentResourceName()
local persistentDeviceTableReady = false
local persistentDeviceTableCallbacks = {}
local persistentDeviceTableCreateSql = [[
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
]]
local persistentMetaTableCreateSql = [[
    CREATE TABLE IF NOT EXISTS `pmms_persistence_meta` (
      `name` varchar(64) NOT NULL,
      `value` varchar(255) NOT NULL,
      `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]
local buildDefaultMediaPlayersForClient
local persistentDeviceRowsCache = nil

local function syncSettings(target)
    if type(InvalidateModelConfigCache) == "function" then
        InvalidateModelConfigCache()
    end
    if type(MarkDirty) == "function" then
        MarkDirty()
    end
    TriggerClientEvent("pmms:loadSettings", target or -1, Config.models, buildDefaultMediaPlayersForClient and buildDefaultMediaPlayersForClient() or Config.defaultMediaPlayers)
end

local function decodeJson(raw)
    if type(raw) ~= "string" or raw == "" then
        return nil
    end
    local ok, decoded = pcall(json.decode, raw)
    if ok then
        return decoded
    end
    return nil
end

local function toPlainCoords(coords)
    if type(coords) ~= "table" and type(coords) ~= "vector3" then
        return nil
    end
    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)
    if not x or not y or not z then
        return nil
    end
    return { x = x, y = y, z = z }
end

local function toVectorCoords(coords)
    local plain = toPlainCoords(coords)
    if not plain then
        return nil
    end
    return vector3(plain.x, plain.y, plain.z)
end

local function cloneForStorage(value, seen)
    local valueType = type(value)
    if valueType == "vector3" then
        return toPlainCoords(value)
    end
    if valueType ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, entry in pairs(value) do
        copy[key] = cloneForStorage(entry, seen)
    end
    return copy
end

local function clonePersistentDeviceRows(rows)
    local copy = {}
    if type(rows) ~= "table" then
        return copy
    end

    for index, row in ipairs(rows) do
        copy[index] = {
            handle = row.handle,
            x = row.x,
            y = row.y,
            z = row.z,
            data = row.data,
        }
    end

    return copy
end

local function setPersistentDeviceRowsCache(rows)
    persistentDeviceRowsCache = clonePersistentDeviceRows(rows)
end

local function upsertPersistentDeviceRowsCache(handle, plain, encoded)
    if type(persistentDeviceRowsCache) ~= "table" then
        return
    end

    local row = {
        handle = handle,
        x = plain.x,
        y = plain.y,
        z = plain.z,
        data = encoded,
    }

    for index, existing in ipairs(persistentDeviceRowsCache) do
        if tostring(existing.handle or "") == tostring(handle) then
            persistentDeviceRowsCache[index] = row
            return
        end
    end

    persistentDeviceRowsCache[#persistentDeviceRowsCache + 1] = row
end

local function removePersistentDeviceRowsCache(handle)
    if type(persistentDeviceRowsCache) ~= "table" then
        return
    end

    for index = #persistentDeviceRowsCache, 1, -1 do
        if tostring(persistentDeviceRowsCache[index].handle or "") == tostring(handle) then
            table.remove(persistentDeviceRowsCache, index)
        end
    end
end

buildDefaultMediaPlayersForClient = function()
    local rows = {}
    for index, entry in ipairs(Config.defaultMediaPlayers or {}) do
        rows[index] = cloneForStorage(entry)
    end
    return rows
end

function GetDefaultMediaPlayersForClient()
    return buildDefaultMediaPlayersForClient()
end

function SyncPmmsPersistentSettings(target)
    syncSettings(target)
end

local function normalizePersistentEntry(data, coords)
    local entry = cloneForStorage(data or {})
    local plain = toPlainCoords(coords or entry.position or entry.coords)
    if plain then
        entry.position = plain
    end
    entry.persistent = true
    entry.handle = nil
    entry.method = nil
    return entry
end

local function normalizeLoadedPersistentEntry(data, fallbackCoords)
    local entry = cloneForStorage(data or {})
    local plain = toPlainCoords(entry.position or fallbackCoords)
    if not plain then
        return nil
    end
    entry.position = vector3(plain.x, plain.y, plain.z)
    entry.persistent = true
    if entry.scaleform then
        if entry.scaleform.position then entry.scaleform.position = toVectorCoords(entry.scaleform.position) end
        if entry.scaleform.rotation then entry.scaleform.rotation = toVectorCoords(entry.scaleform.rotation) end
        if entry.scaleform.scale then entry.scaleform.scale = toVectorCoords(entry.scaleform.scale) end
    end
    return entry
end

local function ensurePersistentDeviceTable(done)
    if type(MySQL) ~= "table" then
        if done then done(false) end
        return
    end

    if persistentDeviceTableReady then
        if done then done(true) end
        return
    end

    persistentDeviceTableCallbacks[#persistentDeviceTableCallbacks + 1] = done
    if #persistentDeviceTableCallbacks > 1 then
        return
    end

    MySQL.ready(function()
        MySQL.query(persistentDeviceTableCreateSql, {}, function()
            MySQL.query(persistentMetaTableCreateSql, {}, function()
                persistentDeviceTableReady = true
                local callbacks = persistentDeviceTableCallbacks
                persistentDeviceTableCallbacks = {}
                for _, callback in ipairs(callbacks) do
                    if callback then callback(true) end
                end
            end)
        end)
    end)
end

local function markFileMigrationDone()
    ensurePersistentDeviceTable(function(ready)
        if ready ~= true then
            return
        end
        MySQL.update([[
            INSERT INTO pmms_persistence_meta (`name`, `value`)
            VALUES ('default_media_players_migrated', '1')
            ON DUPLICATE KEY UPDATE `value` = VALUES(`value`), `updated_at` = CURRENT_TIMESTAMP
        ]], {})
    end)
end

local function mergeDefaultMediaPlayer(entry)
    entry = normalizeLoadedPersistentEntry(entry)
    if not entry then
        return nil
    end

    local existing = GetDefaultMediaPlayer(Config.defaultMediaPlayers, entry.position)
    if existing then
        for key, value in pairs(entry) do
            existing[key] = value
        end
        return existing
    end

    Config.defaultMediaPlayers[#Config.defaultMediaPlayers + 1] = entry
    return entry
end

local function savePersistentDeviceToDatabase(coords, data)
    local plain = toPlainCoords(coords)
    if not plain then
        return
    end

    local storage = normalizePersistentEntry(data, plain)
    local handle = tostring(GetHandleFromCoords(vector3(plain.x, plain.y, plain.z)))
    local encoded = json.encode(storage)

    ensurePersistentDeviceTable(function(ready)
        if ready ~= true then
            return
        end
        MySQL.update([[
            INSERT INTO pmms_persistent_devices (`handle`, `x`, `y`, `z`, `data`)
            VALUES (?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                `x` = VALUES(`x`),
                `y` = VALUES(`y`),
                `z` = VALUES(`z`),
                `data` = VALUES(`data`),
                `updated_at` = CURRENT_TIMESTAMP
        ]], { handle, plain.x, plain.y, plain.z, encoded })
        upsertPersistentDeviceRowsCache(handle, plain, encoded)
        markFileMigrationDone()
    end)
end

local function deletePersistentDeviceFromDatabase(coords)
    local plain = toPlainCoords(coords)
    if not plain then
        return
    end

    local handle = tostring(GetHandleFromCoords(vector3(plain.x, plain.y, plain.z)))
    ensurePersistentDeviceTable(function(ready)
        if ready ~= true then
            return
        end
        MySQL.update("DELETE FROM pmms_persistent_devices WHERE `handle` = ?", { handle })
        removePersistentDeviceRowsCache(handle)
    end)
end

local function loadFileModels()
    local models = decodeJson(LoadResourceFile(thisResource, "models.json"))
    if not models then
        return
    end

    for key, info in pairs(models) do
        local model = tonumber(key) or key
        local existing = GetModelConfig(model)
        if existing then
            for k, v in pairs(info) do existing[k] = v end
        else
            Config.models[model] = info
            if type(InvalidateModelConfigCache) == "function" then
                InvalidateModelConfigCache()
            end
        end
    end
end

local function loadFileDefaultMediaPlayers()
    local defaultMediaPlayers = decodeJson(LoadResourceFile(thisResource, "defaultMediaPlayers.json"))
    if type(defaultMediaPlayers) ~= "table" then
        return 0
    end

    local count = 0
    for _, data in ipairs(defaultMediaPlayers) do
        local entry = mergeDefaultMediaPlayer(data)
        if entry and entry.position then
            count = count + 1
            savePersistentDeviceToDatabase(entry.position, entry)
        end
    end
    return count
end

local function applyDatabaseDefaultMediaPlayersRows(rows, done)
    local count = 0
    if type(rows) == "table" then
        for _, row in ipairs(rows) do
            local decoded = decodeJson(row.data)
            if type(decoded) == "table" then
                local entry = normalizeLoadedPersistentEntry(decoded, { x = row.x, y = row.y, z = row.z })
                if entry then
                    mergeDefaultMediaPlayer(entry)
                    count = count + 1
                end
            end
        end
    end

    if count == 0 then
        MySQL.scalar("SELECT `value` FROM pmms_persistence_meta WHERE `name` = 'default_media_players_migrated'", {}, function(value)
            if not value then
                if loadFileDefaultMediaPlayers() > 0 then
                    markFileMigrationDone()
                end
            end
            syncSettings()
            if done then done() end
        end)
        return
    end

    syncSettings()
    if done then done() end
end

local function loadDatabaseDefaultMediaPlayers(done)
    ensurePersistentDeviceTable(function(ready)
        if ready ~= true then
            loadFileDefaultMediaPlayers()
            syncSettings()
            if done then done() end
            return
        end

        if type(persistentDeviceRowsCache) == "table" then
            applyDatabaseDefaultMediaPlayersRows(persistentDeviceRowsCache, done)
            return
        end

        MySQL.query("SELECT `handle`, `x`, `y`, `z`, `data` FROM pmms_persistent_devices ORDER BY `updated_at` ASC", {}, function(rows)
            setPersistentDeviceRowsCache(rows)
            applyDatabaseDefaultMediaPlayersRows(persistentDeviceRowsCache, done)
        end)
    end)
end

function LoadPersistedSettings(done)
    loadFileModels()
    loadDatabaseDefaultMediaPlayers(done)
end

function AddModelPermanently(model, data)
    data.handle = nil
    data.method = nil
    data.model  = nil

    if data.renderTarget == "" then data.renderTarget = nil end
    if data.label == "" then data.label = nil end

    local existing = GetModelConfig(model)
    if existing then
        for k, v in pairs(data) do existing[k] = v end
    else
        Config.models[model] = data
        if type(InvalidateModelConfigCache) == "function" then
            InvalidateModelConfigCache()
        end
    end

    local models = decodeJson(LoadResourceFile(thisResource, "models.json")) or {}
    models[tostring(model)] = data
    SaveResourceFile(thisResource, "models.json", json.encode(models), -1)

    syncSettings()
end

function AddEntityPermanently(coords, data)
    local plain = toPlainCoords(coords)
    if not plain then
        return false, nil, nil
    end

    local storage = normalizePersistentEntry(data, plain)
    local runtime = normalizeLoadedPersistentEntry(storage, plain)
    if not runtime then
        return false, nil, nil
    end

    local entry = mergeDefaultMediaPlayer(runtime)
    savePersistentDeviceToDatabase(runtime.position, runtime)
    syncSettings()
    return true, GetHandleFromCoords(runtime.position), entry or runtime
end

function RemoveModelPermanently(model)
    local data = GetModelConfig(model)
    Config.models[model] = nil

    local models = decodeJson(LoadResourceFile(thisResource, "models.json"))
    if models then
        models[tostring(model)] = nil
        SaveResourceFile(thisResource, "models.json", json.encode(models), -1)
    end

    syncSettings()
    return data
end

function RemoveEntityPermanently(coords)
    local vectorCoords = toVectorCoords(coords)
    if not vectorCoords then
        return nil
    end

    local data
    for i = #Config.defaultMediaPlayers, 1, -1 do
        local entryCoords = toVectorCoords(Config.defaultMediaPlayers[i].position)
        if entryCoords and IsSameEntity(vectorCoords, entryCoords) then
            data = table.remove(Config.defaultMediaPlayers, i)
            break
        end
    end

    deletePersistentDeviceFromDatabase(vectorCoords)
    syncSettings()
    return data
end

RegisterNetEvent("pmms:saveModel", function(model, data)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to save model defaults")
        return
    end
    AddModelPermanently(model, data)
    TriggerClientEvent("pmms:notify", src, { text = 'Model "' .. (data.label or "?") .. '" saved' })
end)

RegisterNetEvent("pmms:saveEntity", function(coords, data)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to save entity defaults")
        return
    end
    AddEntityPermanently(coords, data)
    TriggerClientEvent("pmms:notify", src, { text = 'Entity "' .. (data.label or "?") .. '" saved' })
end)

RegisterNetEvent("pmms:deleteModel", function(model)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to delete model defaults")
        return
    end
    local data = RemoveModelPermanently(model)
    if data then
        TriggerClientEvent("pmms:notify", src, { text = 'Model "' .. (data.label or "?") .. '" deleted' })
    end
end)

RegisterNetEvent("pmms:deleteEntity", function(coords)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to delete entity defaults")
        return
    end
    local data = RemoveEntityPermanently(coords)
    if data then
        TriggerClientEvent("pmms:notify", src, { text = 'Entity "' .. (data.label or "?") .. '" deleted' })
    end
end)

exports("addModel", function(model, data) AddModelPermanently(model, data) end)
exports("addModelPermanently", AddModelPermanently)
exports("addEntity", function(coords, data) AddEntityPermanently(coords, data) end)
exports("addEntityPermanently", AddEntityPermanently)
exports("removeModel", function(model)
    Config.models[model] = nil
    syncSettings()
end)
exports("removeModelPermanently", RemoveModelPermanently)
exports("removeEntity", function(coords)
    local vectorCoords = toVectorCoords(coords)
    if vectorCoords then
        for i = #Config.defaultMediaPlayers, 1, -1 do
            local entryCoords = toVectorCoords(Config.defaultMediaPlayers[i].position)
            if entryCoords and IsSameEntity(vectorCoords, entryCoords) then
                table.remove(Config.defaultMediaPlayers, i)
                break
            end
        end
    end
    syncSettings()
end)
exports("removeEntityPermanently", RemoveEntityPermanently)
