local thisResource = GetCurrentResourceName()
local eqProfilesFile = "data/equalizer_profiles.json"
local profiles = nil

local function cloneDeep(source, seen)
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
        copy[cloneDeep(key, seen)] = cloneDeep(value, seen)
    end
    return copy
end

local function clampNumber(value, lo, hi)
    local n = tonumber(value)
    if not n then return nil end
    return math.max(lo, math.min(hi, n))
end

local function getLicense(src)
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and id:sub(1, 8) == "license:" then
            return id
        end
    end
    return nil
end

local function loadProfiles()
    if profiles then return profiles end
    profiles = {}
    local raw = LoadResourceFile(thisResource, eqProfilesFile)
    if type(raw) == "string" and raw ~= "" then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == "table" then
            profiles = decoded
        end
    end
    return profiles
end

local savePending = false

local function scheduleProfileSave()
    if savePending then return end
    savePending = true
    CreateThread(function()
        Wait(2000)
        savePending = false
        local ok, encoded = pcall(json.encode, loadProfiles())
        if ok and type(encoded) == "string" then
            SaveResourceFile(thisResource, eqProfilesFile, encoded, -1)
        end
    end)
end

local eqCfg = Config.equalizer or {}

local function getBandCount()
    return type(eqCfg.bands) == "table" and #eqCfg.bands > 0 and #eqCfg.bands or 10
end

local function makeDefaultProfile()
    local defaultBands = {}
    local count = getBandCount()
    for i = 1, count do
        defaultBands[i] = tonumber(eqCfg.defaultBands and eqCfg.defaultBands[i]) or 0
    end
    return {
        enabled = eqCfg.defaultEnabled == true,
        preampDb = tonumber(eqCfg.defaultPreampDb) or 0.0,
        highpassEnabled = eqCfg.defaultHighpass == true,
        compressorEnabled = eqCfg.defaultCompressor == true,
        bands = defaultBands,
        customPresets = {},
    }
end

local function sanitizeProfile(data, includeCustomPresets)
    if type(data) ~= "table" then
        return nil, "Invalid EQ profile data."
    end

    local bandMinDb = tonumber(eqCfg.bandMinDb) or -12
    local bandMaxDb = tonumber(eqCfg.bandMaxDb) or 12
    local preampMinDb = tonumber(eqCfg.preampMinDb) or -12
    local preampMaxDb = tonumber(eqCfg.preampMaxDb) or 12
    local maxCustom = math.max(0, tonumber(eqCfg.maxCustomPresets) or 5)
    local count = getBandCount()
    local bands = {}
    local rawBands = type(data.bands) == "table" and data.bands or {}

    for i = 1, count do
        bands[i] = clampNumber(rawBands[i], bandMinDb, bandMaxDb) or 0
    end

    local profile = {
        enabled = data.enabled == true,
        preampDb = clampNumber(data.preampDb, preampMinDb, preampMaxDb) or 0.0,
        highpassEnabled = data.highpassEnabled == true,
        compressorEnabled = data.compressorEnabled == true,
        bands = bands,
        customPresets = {},
    }

    if includeCustomPresets ~= false and type(data.customPresets) == "table" then
        for _, preset in ipairs(data.customPresets) do
            if #profile.customPresets >= maxCustom then break end
            if type(preset) == "table" and type(preset.label) == "string" and preset.label ~= "" then
                local presetBands = {}
                local rawPresetBands = type(preset.bands) == "table" and preset.bands or {}
                for i = 1, count do
                    presetBands[i] = clampNumber(rawPresetBands[i], bandMinDb, bandMaxDb) or 0
                end
                profile.customPresets[#profile.customPresets + 1] = {
                    id = tostring(preset.id or ("custom_" .. tostring(#profile.customPresets + 1))),
                    label = preset.label:sub(1, 40),
                    preampDb = clampNumber(preset.preampDb, preampMinDb, preampMaxDb) or 0.0,
                    highpassEnabled = preset.highpassEnabled == true,
                    compressorEnabled = preset.compressorEnabled == true,
                    bands = presetBands,
                }
            end
        end
    end

    return profile, nil
end

local function normalizeHandle(handle)
    return tonumber(handle) or handle
end

local function getPersistentEntry(handle)
    if type(GetPersistentPmmsDeviceEntry) ~= "function" then
        return nil
    end
    local entry = GetPersistentPmmsDeviceEntry(handle)
    return entry
end

local function persistEntry(handle, entry)
    if type(entry) ~= "table" or type(AddEntityPermanently) ~= "function" then
        return
    end
    local position = ToVector3(entry.position)
    if not position then
        return
    end
    AddEntityPermanently(position, cloneDeep(entry))
end

local function canEditDeviceEq(src, handle)
    if not HasPmmsPermission(src, "interact") then
        return false, "You do not have permission for this action."
    end

    if type(CanUsePmmsAdminLockedDevice) == "function" and not CanUsePmmsAdminLockedDevice(src, handle) then
        return false, "This device is restricted by staff."
    end

    if type(CanAccessSessionLock) == "function" then
        local allowed = CanAccessSessionLock(src, handle, true)
        if allowed == false then
            return false, "This media session is locked."
        end
    end

    return true, nil
end

local function isKnownDevice(handle)
    if type(GetMediaPlayer) == "function" and GetMediaPlayer(handle) then
        return true
    end
    if type(GetDeviceSession) == "function" and GetDeviceSession(handle) then
        return true
    end
    if getPersistentEntry(handle) then
        return true
    end
    return false
end

function GetPlayerEqProfile(src)
    local license = getLicense(src)
    if not license then return makeDefaultProfile() end
    local p = loadProfiles()
    return type(p[license]) == "table" and cloneDeep(p[license]) or makeDefaultProfile()
end

function SavePlayerEqProfile(src, data)
    local profile, err = sanitizeProfile(data, true)
    if not profile then return false, err end

    local license = getLicense(src)
    if not license then return false, "Could not identify player." end

    local p = loadProfiles()
    p[license] = profile
    scheduleProfileSave()
    return true, nil
end

function GetDeviceEqProfile(handle)
    handle = normalizeHandle(handle)
    local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
    if type(session) == "table" and type(session.settings) == "table" and type(session.settings.equalizerProfile) == "table" then
        return cloneDeep(session.settings.equalizerProfile)
    end

    local mp = type(GetMediaPlayer) == "function" and GetMediaPlayer(handle) or nil
    if type(mp) == "table" and type(mp.equalizerProfile) == "table" then
        return cloneDeep(mp.equalizerProfile)
    end

    local persistent = getPersistentEntry(handle)
    if type(persistent) == "table" and type(persistent.equalizerProfile) == "table" then
        return cloneDeep(persistent.equalizerProfile)
    end

    return nil
end

function SaveDeviceEqProfile(src, handle, data)
    handle = normalizeHandle(handle)
    if not isKnownDevice(handle) then
        return false, "This device is no longer known by the server."
    end

    local allowed, message = canEditDeviceEq(src, handle)
    if not allowed then
        return false, message
    end

    local profile, err = sanitizeProfile(data, false)
    if not profile then return false, err end

    local changed = false
    local session = type(EnsureDeviceSession) == "function" and EnsureDeviceSession(handle, {}) or nil
    if session then
        session.settings = session.settings or {}
        session.settings.equalizerProfile = cloneDeep(profile)
        if type(CommitDeviceSessionState) == "function" then
            CommitDeviceSessionState(handle)
        end
        changed = true
    end

    local mp = type(GetMediaPlayer) == "function" and GetMediaPlayer(handle) or nil
    if mp then
        mp.equalizerProfile = cloneDeep(profile)
        changed = true
    end

    local persistent = getPersistentEntry(handle)
    if persistent then
        persistent.equalizerProfile = cloneDeep(profile)
        persistEntry(handle, persistent)
        changed = true
    end

    if not changed then
        return false, "This device is no longer known by the server."
    end

    if type(MarkDirty) == "function" then
        MarkDirty()
    end

    TriggerClientEvent("pmms:eqDeviceProfile", -1, handle, profile)
    return true, nil
end

RegisterNetEvent("pmms:saveEqProfile", function(data)
    local src = source
    local ok, err = SavePlayerEqProfile(src, data)
    if not ok then
        TriggerClientEvent("pmms:error", src, err or "Failed to save EQ profile.")
    end
end)

RegisterNetEvent("pmms:loadEqProfile", function()
    local src = source
    TriggerClientEvent("pmms:eqProfile", src, GetPlayerEqProfile(src))
end)

RegisterNetEvent("pmms:saveDeviceEqProfile", function(handle, data)
    local src = source
    local ok, err = SaveDeviceEqProfile(src, handle, data)
    if not ok then
        TriggerClientEvent("pmms:error", src, err or "Failed to save linked EQ profile.")
        return
    end
    TriggerClientEvent("pmms:notify", src, { title = "Equalizer", text = "Linked equalizer updated." })
end)

RegisterNetEvent("pmms:loadDeviceEqProfile", function(handle)
    local src = source
    handle = normalizeHandle(handle)
    local allowed, message = canEditDeviceEq(src, handle)
    if not allowed then
        TriggerClientEvent("pmms:error", src, message or "This device is restricted.")
        TriggerClientEvent("pmms:eqDeviceProfile", src, handle, nil, false)
        return
    end
    TriggerClientEvent("pmms:eqDeviceProfile", src, handle, GetDeviceEqProfile(handle) or makeDefaultProfile(), true)
end)
