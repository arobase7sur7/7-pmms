-- server/equalizer.lua
-- Global per-player EQ profile persistence.
-- Profiles are stored in data/equalizer_profiles.json, keyed by license identifier.

local thisResource   = GetCurrentResourceName()
local eqProfilesFile = "data/equalizer_profiles.json"
local profiles       = nil   -- lazy-loaded table

-- ─── helpers ────────────────────────────────────────────────────────────────

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

-- ─── load / save ────────────────────────────────────────────────────────────

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

-- ─── public API ─────────────────────────────────────────────────────────────

local eqCfg = Config.equalizer or {}

local function makeDefaultProfile()
    local defaultBands = {}
    for i = 1, 10 do
        defaultBands[i] = 0
    end
    return {
        enabled           = eqCfg.defaultEnabled == true,
        preampDb          = tonumber(eqCfg.defaultPreampDb) or 0.0,
        highpassEnabled   = eqCfg.defaultHighpass == true,
        compressorEnabled = eqCfg.defaultCompressor == true,
        bands             = defaultBands,
        customPresets     = {},
    }
end

function GetPlayerEqProfile(src)
    local license = getLicense(src)
    if not license then return makeDefaultProfile() end
    local p = loadProfiles()
    return type(p[license]) == "table" and p[license] or makeDefaultProfile()
end

function SavePlayerEqProfile(src, data)
    if type(data) ~= "table" then return false, "Invalid EQ profile data." end

    local license = getLicense(src)
    if not license then return false, "Could not identify player." end

    local bandMinDb   = tonumber(eqCfg.bandMinDb)   or -12
    local bandMaxDb   = tonumber(eqCfg.bandMaxDb)   or  12
    local preampMinDb = tonumber(eqCfg.preampMinDb) or -12
    local preampMaxDb = tonumber(eqCfg.preampMaxDb) or  12
    local maxCustom   = math.max(0, tonumber(eqCfg.maxCustomPresets) or 5)

    -- Sanitise bands
    local bands = {}
    local rawBands = type(data.bands) == "table" and data.bands or {}
    for i = 1, 10 do
        bands[i] = clampNumber(rawBands[i], bandMinDb, bandMaxDb) or 0
    end

    -- Sanitise custom presets
    local customPresets = {}
    if type(data.customPresets) == "table" then
        for _, preset in ipairs(data.customPresets) do
            if #customPresets >= maxCustom then break end
            if type(preset) == "table" and type(preset.label) == "string" and preset.label ~= "" then
                local pb = {}
                local rawPb = type(preset.bands) == "table" and preset.bands or {}
                for i = 1, 10 do
                    pb[i] = clampNumber(rawPb[i], bandMinDb, bandMaxDb) or 0
                end
                customPresets[#customPresets + 1] = {
                    id    = tostring(preset.id or ("custom_" .. #customPresets + 1)),
                    label = preset.label:sub(1, 40),
                    bands = pb,
                }
            end
        end
    end

    local p = loadProfiles()
    p[license] = {
        enabled           = data.enabled == true,
        preampDb          = clampNumber(data.preampDb, preampMinDb, preampMaxDb) or 0.0,
        highpassEnabled   = data.highpassEnabled == true,
        compressorEnabled = data.compressorEnabled == true,
        bands             = bands,
        customPresets     = customPresets,
    }

    scheduleProfileSave()
    return true, nil
end

-- ─── net events ─────────────────────────────────────────────────────────────

RegisterNetEvent("pmms:saveEqProfile", function(data)
    local src = source
    local ok, err = SavePlayerEqProfile(src, data)
    if not ok then
        TriggerClientEvent("pmms:error", src, err or "Failed to save EQ profile.")
    end
end)

RegisterNetEvent("pmms:loadEqProfile", function()
    local src = source
    local profile = GetPlayerEqProfile(src)
    TriggerClientEvent("pmms:eqProfile", src, profile)
end)
