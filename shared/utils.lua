function GetHandleFromCoords(coords)
    local plain = ToPlainCoords(coords)
    if not plain then
        return nil
    end

    return GetHashKey(string.format("%d_%d_%d", math.floor(plain.x * 10), math.floor(plain.y * 10), math.floor(plain.z * 10)))
end

function Clamp(val, min, max, def)
    if not val then return def end
    if val < min then return min end
    if val > max then return max end
    return val
end

function ToPlainCoords(coords)
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

function ToVector3(coords)
    if type(coords) == "vector3" then
        return coords
    end

    local plain = ToPlainCoords(coords)
    if not plain then
        return nil
    end

    return vector3(plain.x, plain.y, plain.z)
end

function IsSameEntity(coords1, coords2)
    local first = ToVector3(coords1)
    local second = ToVector3(coords2)
    if not first or not second then
        return false
    end

    return #(first - second) < 0.001
end

function GetDefaultMediaPlayer(list, coords)
    local target = ToVector3(coords)
    if not target then
        return nil
    end

    for _, mediaPlayer in ipairs(list or {}) do
        if mediaPlayer and mediaPlayer.position and IsSameEntity(target, mediaPlayer.position) then
            return mediaPlayer
        end
    end
end

local debugCategoryAliases = {
    favorite = "favorites",
    playlist = "favorites",
    playback = "player",
    startup = "player",
    dui_browser = "dui",
}

local function debugValue(value, depth, seen)
    local valueType = type(value)
    if valueType ~= "table" then
        if valueType == "string" then
            return value
        end
        return tostring(value)
    end

    depth = depth or 0
    if depth >= 2 then
        return "{...}"
    end

    seen = seen or {}
    if seen[value] then
        return "{cycle}"
    end
    seen[value] = true

    local parts = {}
    local count = 0
    for key, entry in pairs(value) do
        count = count + 1
        if count > 12 then
            parts[#parts + 1] = "..."
            break
        end
        parts[#parts + 1] = ("%s=%s"):format(tostring(key), debugValue(entry, depth + 1, seen))
    end

    seen[value] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

function PMMSDebugEnabled(category)
    local cfg = Config and Config.debug
    if cfg == true then
        return true
    end
    if type(cfg) ~= "table" or cfg.enabled ~= true then
        return false
    end
    if cfg.all == true then
        return true
    end

    local normalized = tostring(category or "general")
    return cfg[normalized] == true or cfg[debugCategoryAliases[normalized] or ""] == true
end

function PMMSDebug(category, message, data)
    if not PMMSDebugEnabled(category) then
        return
    end

    local normalized = tostring(category or "general")
    local suffix = data ~= nil and (" | " .. debugValue(data)) or ""
    print(("^3[7-pmms][debug:%s] %s%s^7"):format(normalized, tostring(message or ""), suffix))
end

local modelConfigCache = nil

local function addModelIndexEntry(index, targetModels, seenTargets, key, data)
    if key == nil or data == nil then
        return
    end

    index[key] = data

    local numericKey = tonumber(key)
    if type(key) == "number" then
        numericKey = key
    elseif type(key) == "string" and not numericKey and type(GetHashKey) == "function" then
        numericKey = GetHashKey(key)
    end

    if numericKey then
        index[numericKey] = data
        local targetKey = tostring(numericKey)
        if not seenTargets[targetKey] then
            targetModels[#targetModels + 1] = numericKey
            seenTargets[targetKey] = true
        end
    end

    if type(key) == "string" and key ~= "" and not tonumber(key) and not seenTargets[key] then
        targetModels[#targetModels + 1] = key
        seenTargets[key] = true
    end
end

function InvalidateModelConfigCache()
    modelConfigCache = nil
end

function GetModelConfigIndex()
    local models = Config and Config.models or nil
    if type(models) ~= "table" then
        return {}, {}
    end

    if modelConfigCache and modelConfigCache.source == models then
        return modelConfigCache.index, modelConfigCache.targetModels
    end

    local index = {}
    local targetModels = {}
    local seenTargets = {}

    for key, data in pairs(models) do
        addModelIndexEntry(index, targetModels, seenTargets, key, data)
    end

    modelConfigCache = {
        source = models,
        index = index,
        targetModels = targetModels,
    }

    return index, targetModels
end

function GetModelConfig(model)
    if model == nil then
        return nil
    end

    local models = Config and Config.models or nil
    if type(models) ~= "table" then
        return nil
    end

    if models[model] then
        return models[model]
    end

    local index = GetModelConfigIndex()
    return index[model] or index[tonumber(model)]
end

function GetModelTargetKeys()
    local _, targetModels = GetModelConfigIndex()
    return targetModels
end

function getEntityNetworkId(entity)
    if not DoesEntityExist(entity) then return nil end
    if not NetworkGetEntityIsNetworked(entity) then
        NetworkRegisterEntityAsNetworked(entity)
    end
    return NetworkGetNetworkIdFromEntity(entity)
end

function getExistingEntityNetworkId(entity)
    if not DoesEntityExist(entity) or not NetworkGetEntityIsNetworked(entity) then return nil end
    return NetworkGetNetworkIdFromEntity(entity)
end

local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
function Base64Encode(data)
    return ((data:gsub('.', function(x) 
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end
