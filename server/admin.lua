local thisResource = GetCurrentResourceName()
local adminStateFile = "data/admin_state.json"
local adminState = {
    vehicleLocks = {},
}
-- adminLogs removed – replaced with no-op compatibility stub
local pendingRequests = {}
local pendingRequestSeq = 0

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

local function trim(value)
    if type(value) ~= "string" then
        return nil
    end
    local trimmed = value:match("^%s*(.-)%s*$")
    return trimmed ~= "" and trimmed or nil
end

local function normalizeHandle(handle)
    return tonumber(handle) or handle
end

local function normalizePlate(plate)
    local value = trim(plate)
    if not value then
        return nil
    end
    return value:upper():gsub("%s+", "")
end

local function coordsToPlain(coords)
    if type(coords) ~= "table" then
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

local function toVector(coords)
    local plain = coordsToPlain(coords)
    if not plain then
        return nil
    end
    return vector3(plain.x, plain.y, plain.z)
end


-- LogPmmsAdminEvent is kept as a no-op compatibility stub.
-- All previous callers still compile; the audit trail has been removed
-- in favour of server console output only where critical.
function LogPmmsAdminEvent(_eventName, _handle, _src, _data)
    -- no-op
end

local function loadAdminState()
    local raw = LoadResourceFile(thisResource, adminStateFile)
    if type(raw) ~= "string" or raw == "" then
        return
    end

    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == "table" then
        adminState.vehicleLocks = type(decoded.vehicleLocks) == "table" and decoded.vehicleLocks or {}
    end
end

local function saveAdminState()
    SaveResourceFile(thisResource, adminStateFile, json.encode(adminState), -1)
end

local function getPersistentEntryByHandle(handle)
    handle = normalizeHandle(handle)
    for _, entry in ipairs(Config.defaultMediaPlayers or {}) do
        if type(entry) == "table" and entry.position then
            local coords = toVector(entry.position)
            if coords and GetHandleFromCoords(coords) == handle then
                return entry, coords
            end
        end
    end
    return nil, nil
end

function GetPersistentPmmsDeviceEntry(handle)
    return getPersistentEntryByHandle(handle)
end

local function persistEntry(entry)
    if type(entry) ~= "table" or not entry.position or type(AddEntityPermanently) ~= "function" then
        return
    end

    local coords = toVector(entry.position)
    if coords then
        AddEntityPermanently(coords, cloneDeep(entry))
    end
end

local function normalizeProfileKey(profileKey)
    local key = trim(profileKey)
    if not key then
        return nil
    end
    key = key:lower():gsub("%s+", "_"):gsub("%-", "_")
    if Config.deviceProfiles and Config.deviceProfiles[key] then
        return key
    end
    return nil
end

function GetPmmsDeviceProfilesForClient()
    local rows = {}
    for key, profile in pairs(Config.deviceProfiles or {}) do
        if type(profile) == "table" then
            rows[#rows + 1] = {
                key = key,
                label = profile.label or key,
            }
        end
    end
    table.sort(rows, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return rows
end

local function applyProfileToTarget(target, profileKey)
    local key = normalizeProfileKey(profileKey)
    local profile = key and Config.deviceProfiles[key] or nil
    if type(target) ~= "table" or type(profile) ~= "table" then
        return false, "Unknown device profile."
    end

    target.profile = key
    if profile.label and (not target.label or target.label == "" or target.profileLabel == true) then
        target.label = profile.label
        target.profileLabel = true
    end
    if profile.range ~= nil then target.range = tonumber(profile.range) or target.range end
    if profile.volume ~= nil then target.volume = tonumber(profile.volume) or target.volume end
    if profile.maxVolume ~= nil then target.maxVolume = tonumber(profile.maxVolume) or target.maxVolume end
    if profile.transitionTime ~= nil then target.transitionSeconds = tonumber(profile.transitionTime) or target.transitionSeconds end
    if profile.transitionSeconds ~= nil then target.transitionSeconds = tonumber(profile.transitionSeconds) or target.transitionSeconds end
    if profile.loopMode ~= nil then target.loopMode = profile.loopMode end
    if profile.requestMode ~= nil then target.requestMode = profile.requestMode end
    if profile.adminLock ~= nil then target.adminLock = cloneDeep(profile.adminLock) end
    if profile.sourceRestrictions ~= nil then target.sourceRestrictions = cloneDeep(profile.sourceRestrictions) end
    if profile.speakerLimits ~= nil then target.speakerLimits = cloneDeep(profile.speakerLimits) end
    if profile.visualizerDefaults ~= nil then target.visualizerDefaults = cloneDeep(profile.visualizerDefaults) end
    if profile.videoOnly == true then target.videoOnly = true end
    if profile.isVehicle == true then target.isVehicle = true end
    return true, nil
end

function ApplyPmmsDeviceProfile(handle, profileKey, src)
    handle = normalizeHandle(handle)
    local changed = false
    local ok, message

    local mp = GetMediaPlayer(handle)
    if mp then
        ok, message = applyProfileToTarget(mp, profileKey)
        if not ok then return false, message end
        changed = true
    end

    local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
    if session then
        session.settings = session.settings or {}
        ok, message = applyProfileToTarget(session.settings, profileKey)
        if not ok then return false, message end
        if type(CommitDeviceSessionState) == "function" then
            CommitDeviceSessionState(handle)
        end
        changed = true
    end

    local persistent = getPersistentEntryByHandle(handle)
    if persistent then
        ok, message = applyProfileToTarget(persistent, profileKey)
        if not ok then return false, message end
        persistEntry(persistent)
        changed = true
    end

    if changed then
        MarkDirty()
        LogPmmsAdminEvent("profile_applied", handle, src, { profile = profileKey })
        return true, nil
    end

    return false, "This device is no longer known by the server."
end

local function getAdminLockForHandle(handle, plate)
    handle = normalizeHandle(handle)
    local mp = GetMediaPlayer(handle)
    if type(mp) == "table" and type(mp.adminLock) == "table" then
        return mp.adminLock
    end

    local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
    if type(session) == "table" and type(session.settings) == "table" and type(session.settings.adminLock) == "table" then
        return session.settings.adminLock
    end

    local persistent = getPersistentEntryByHandle(handle)
    if type(persistent) == "table" and type(persistent.adminLock) == "table" then
        return persistent.adminLock
    end

    local normalizedPlate = normalizePlate(plate or (type(mp) == "table" and mp.vehiclePlate or nil))
    if normalizedPlate and type(adminState.vehicleLocks[normalizedPlate]) == "table" then
        return adminState.vehicleLocks[normalizedPlate]
    end

    return nil
end

local function getGroupGrade(group)
    if type(group) ~= "table" then
        return nil
    end
    return tonumber(group.grade) or 0
end

local function gradeListContains(list, grade)
    if type(list) ~= "table" or grade == nil then
        return false
    end
    for _, value in ipairs(list) do
        if tonumber(value) == tonumber(grade) then
            return true
        end
    end
    return false
end

local function groupRuleAllows(rule, group)
    if type(rule) ~= "table" or type(group) ~= "table" then
        return false
    end
    if tostring(rule.name or rule.job or rule.gang or "") ~= tostring(group.name or "") then
        return false
    end

    local grade = getGroupGrade(group) or 0
    if rule.exactGrade ~= nil then
        return grade == tonumber(rule.exactGrade)
    end
    if type(rule.grades) == "table" then
        return gradeListContains(rule.grades, grade)
    end
    if rule.minGrade ~= nil then
        return grade >= (tonumber(rule.minGrade) or 0)
    end
    return true
end

function CanUsePmmsAdminLockedDevice(src, handle, plate)
    if HasPmmsPermission(src, "manage") then
        return true
    end

    local lock = getAdminLockForHandle(handle, plate)
    if type(lock) ~= "table" then
        return true
    end

    local mode = tostring(lock.mode or "public"):lower()
    if mode == "" or mode == "public" then
        return true
    end
    if mode == "admin" or mode == "admin_only" then
        return false
    end

    if mode == "job" or mode == "job_grade" or mode == "job_min_grade" or mode == "job_grades" then
        local groups = type(GetPmmsPlayerGroups) == "function" and GetPmmsPlayerGroups(src) or {}
        local rules = type(lock.jobs) == "table" and lock.jobs or {}
        if type(lock.job) == "string" then
            rules[#rules + 1] = {
                name = lock.job,
                exactGrade = lock.exactGrade,
                minGrade = lock.minGrade,
                grades = lock.grades,
            }
        end
        for _, rule in ipairs(rules) do
            if groupRuleAllows(rule, groups.job) then
                return true
            end
        end
        return false
    end

    return false
end

function SetPmmsDeviceAdminLock(handle, lock, src, plate)
    handle = normalizeHandle(handle)
    lock = type(lock) == "table" and cloneDeep(lock) or { mode = "public" }
    lock.mode = tostring(lock.mode or "public"):lower()
    if lock.mode == "job_grade" and lock.exactGrade == nil and lock.grade ~= nil then
        lock.exactGrade = tonumber(lock.grade)
        lock.grade = nil
    end
    if lock.mode == "job_min_grade" and lock.minGrade == nil and lock.grade ~= nil then
        lock.minGrade = tonumber(lock.grade)
        lock.grade = nil
    end

    local changed = false
    local mp = GetMediaPlayer(handle)
    if mp then
        mp.adminLock = lock
        if plate then
            mp.vehiclePlate = normalizePlate(plate)
        end
        changed = true
    end

    local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
    if session then
        session.settings = session.settings or {}
        session.settings.adminLock = cloneDeep(lock)
        if plate then session.settings.vehiclePlate = normalizePlate(plate) end
        if type(CommitDeviceSessionState) == "function" then
            CommitDeviceSessionState(handle)
        end
        changed = true
    end

    local persistent = getPersistentEntryByHandle(handle)
    if persistent then
        persistent.adminLock = cloneDeep(lock)
        persistEntry(persistent)
        changed = true
    end

    local normalizedPlate = normalizePlate(plate or (mp and mp.vehiclePlate) or (session and session.settings and session.settings.vehiclePlate))
    if normalizedPlate then
        adminState.vehicleLocks[normalizedPlate] = cloneDeep(lock)
        saveAdminState()
        changed = true
    end

    if changed then
        MarkDirty()
        LogPmmsAdminEvent("admin_lock_changed", handle, src, { mode = lock.mode, plate = normalizedPlate })
        return true, nil
    end

    return false, "This device is no longer known by the server."
end

local function getRequestModeForHandle(handle)
    handle = normalizeHandle(handle)
    local mp = GetMediaPlayer(handle)
    if type(mp) == "table" and type(mp.requestMode) == "string" then
        return mp.requestMode
    end

    local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
    if type(session) == "table" and type(session.settings) == "table" and type(session.settings.requestMode) == "string" then
        return session.settings.requestMode
    end

    local persistent = getPersistentEntryByHandle(handle)
    if type(persistent) == "table" and type(persistent.requestMode) == "string" then
        return persistent.requestMode
    end

    local cfg = Config.requests or {}
    return tostring(cfg.defaultMode or "queue")
end

function GetPmmsDeviceRequestMode(handle)
    local mode = tostring(getRequestModeForHandle(handle) or "queue"):lower()
    if mode ~= "queue" and mode ~= "pending" and mode ~= "disabled" then
        mode = "queue"
    end
    if not Config.requests or Config.requests.enabled == false then
        mode = "queue"
    end
    return mode
end

function SetPmmsDeviceRequestMode(handle, mode, src)
    handle = normalizeHandle(handle)
    mode = tostring(mode or "queue"):lower()
    if mode ~= "queue" and mode ~= "pending" and mode ~= "disabled" then
        return false, "Invalid request mode."
    end

    local changed = false
    local mp = GetMediaPlayer(handle)
    if mp then
        mp.requestMode = mode
        changed = true
    end

    local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
    if session then
        session.settings = session.settings or {}
        session.settings.requestMode = mode
        if type(CommitDeviceSessionState) == "function" then
            CommitDeviceSessionState(handle)
        end
        changed = true
    end

    local persistent = getPersistentEntryByHandle(handle)
    if persistent then
        persistent.requestMode = mode
        persistEntry(persistent)
        changed = true
    end

    if changed then
        MarkDirty()
        LogPmmsAdminEvent("request_mode_changed", handle, src, { requestMode = mode })
        return true, nil
    end
    return false, "This device is no longer known by the server."
end

local function clampNumber(value, minValue, maxValue, fallback)
    local numeric = tonumber(value)
    if not numeric then
        numeric = fallback
    end
    if minValue ~= nil and numeric < minValue then numeric = minValue end
    if maxValue ~= nil and numeric > maxValue then numeric = maxValue end
    return numeric
end

function SetPmmsAdminDeviceSettings(handle, settings, src)
    handle = normalizeHandle(handle)
    settings = type(settings) == "table" and settings or {}

    local changed = false
    local function apply(target)
        if type(target) ~= "table" then
            return
        end
        if settings.range ~= nil then
            target.range = clampNumber(settings.range, 0.0, Config.adminMaxRange or Config.maxRange or 200.0, Config.defaultRange or 30.0)
            changed = true
        end
        if settings.volume ~= nil then
            target.volume = clampNumber(settings.volume, 0, 100, Config.defaultVolume or 100)
            changed = true
        end
        if settings.maxVolume ~= nil then
            target.maxVolume = clampNumber(settings.maxVolume, 0, 100, 100)
            changed = true
        end
        if settings.transitionSeconds ~= nil then
            target.transitionSeconds = clampNumber(settings.transitionSeconds, 0.0, Config.maxTransitionSeconds or 15.0, Config.defaultTransitionSeconds or 5.0)
            changed = true
        end
        if settings.adminLock ~= nil then
            target.adminLock = cloneDeep(settings.adminLock)
            changed = true
        end
    end

    local mp = GetMediaPlayer(handle)
    apply(mp)

    local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
    if session then
        session.settings = session.settings or {}
        apply(session.settings)
        if type(CommitDeviceSessionState) == "function" then
            CommitDeviceSessionState(handle)
        end
    end

    local persistent = getPersistentEntryByHandle(handle)
    if persistent then
        apply(persistent)
        persistEntry(persistent)
    end

    if changed then
        MarkDirty()
        LogPmmsAdminEvent("device_settings_changed", handle, src, cloneDeep(settings))
        return true, nil
    end
    return false, "This device is no longer known by the server."
end

local function countPendingForPlayer(handle, identifier)
    local count = 0
    for _, request in ipairs(pendingRequests[handle] or {}) do
        if request.identifier == identifier then
            count = count + 1
        end
    end
    return count
end

function HandlePmmsDeviceRequestMode(src, handle, preparedOptions)
    handle = normalizeHandle(handle)
    local mode = GetPmmsDeviceRequestMode(handle)
    if HasPmmsPermission(src, "manage") then
        return true
    end

    if mode == "disabled" then
        TriggerClientEvent("pmms:error", src, "Requests are disabled on this device.")
        return false
    end

    if mode ~= "pending" then
        return true
    end

    local identifier = GetUserIdentifier(src)
    if not identifier then
        TriggerClientEvent("pmms:error", src, "Could not identify you for this request.")
        return false
    end

    local cfg = Config.requests or {}
    local maxPerPlayer = math.max(1, tonumber(cfg.maxPendingPerPlayer) or 3)
    if countPendingForPlayer(handle, identifier) >= maxPerPlayer then
        TriggerClientEvent("pmms:error", src, ("You already have %d pending request(s) on this device."):format(maxPerPlayer))
        return false
    end

    pendingRequestSeq = pendingRequestSeq + 1
    pendingRequests[handle] = pendingRequests[handle] or {}
    pendingRequests[handle][#pendingRequests[handle] + 1] = {
        id = pendingRequestSeq,
        handle = handle,
        source = src,
        identifier = identifier,
        requesterName = GetPlayerName(src) or ("Player " .. tostring(src)),
        options = cloneDeep(preparedOptions),
        createdAt = os.time(),
        expiresAt = os.time() + math.max(30, tonumber(cfg.pendingExpireSeconds) or 600),
    }

    MarkDirty()
    LogPmmsAdminEvent("pending_request_added", handle, src, {
        title = preparedOptions and preparedOptions.title,
    })
    TriggerClientEvent("pmms:notify", src, {
        title = "Request Pending",
        text = "Your media request is waiting for staff approval.",
    })
    return false
end

local function canApproveRequests(src, handle)
    if HasPmmsPermission(src, "manage") then
        return true
    end

    local cfg = Config.requests or {}
    if cfg.hostCanApprove == true then
        local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
        if session and tonumber(session.lastSource) == tonumber(src) then
            return true
        end
    end

    local groups = type(GetPmmsPlayerGroups) == "function" and GetPmmsPlayerGroups(src) or {}
    local jobs = type(cfg.approverJobs) == "table" and cfg.approverJobs or {}
    local job = groups.job
    if type(job) == "table" and jobs[job.name] ~= nil then
        local minGrade = tonumber(jobs[job.name]) or 0
        return (tonumber(job.grade) or 0) >= minGrade
    end
    return false
end

local function removePendingById(handle, requestId)
    local list = pendingRequests[handle]
    if type(list) ~= "table" then
        return nil
    end
    for index, request in ipairs(list) do
        if tonumber(request.id) == tonumber(requestId) then
            return table.remove(list, index)
        end
    end
    return nil
end

function GetPmmsPendingRequestsForHandle(handle)
    local now = os.time()
    handle = normalizeHandle(handle)
    local list = pendingRequests[handle] or {}
    local copy = {}
    local changed = false
    for index = #list, 1, -1 do
        local request = list[index]
        if request.expiresAt and request.expiresAt <= now then
            table.remove(list, index)
            changed = true
        end
    end
    for _, request in ipairs(list) do
        copy[#copy + 1] = {
            id = request.id,
            handle = handle,
            requesterName = request.requesterName,
            playerName = request.requesterName,
            source = request.source,
            options = cloneDeep(request.options or {}),
            title = request.options and request.options.title or request.options and request.options.url or "Request",
            url = request.options and request.options.originalUrl or request.options and request.options.url or nil,
            createdAt = request.createdAt,
            expiresAt = request.expiresAt,
        }
    end
    if changed then
        MarkDirty()
    end
    return copy
end

function ApprovePmmsPendingRequest(src, handle, requestId, playNext)
    handle = normalizeHandle(handle)
    if not canApproveRequests(src, handle) then
        return false, "You cannot approve requests on this device."
    end

    local request = removePendingById(handle, requestId)
    if not request then
        return false, "Pending request not found."
    end

    if playNext == true and type(PrependDeviceQueueEntry) == "function" then
        PrependDeviceQueueEntry(handle, request.source, request.options)
    else
        AddToQueue(handle, request.source, request.options)
    end
    MarkDirty()
    LogPmmsAdminEvent("pending_request_approved", handle, src, {
        requestId = request.id,
        requesterName = request.requesterName,
    })
    return true, nil
end

function RejectPmmsPendingRequest(src, handle, requestId)
    handle = normalizeHandle(handle)
    if not canApproveRequests(src, handle) then
        return false, "You cannot reject requests on this device."
    end

    local request = removePendingById(handle, requestId)
    if not request then
        return false, "Pending request not found."
    end

    MarkDirty()
    LogPmmsAdminEvent("pending_request_rejected", handle, src, {
        requestId = request.id,
        requesterName = request.requesterName,
    })
    return true, nil
end

function ClearPmmsPendingRequests(src, handle)
    handle = normalizeHandle(handle)
    if not canApproveRequests(src, handle) then
        return false, "You cannot clear requests on this device."
    end
    pendingRequests[handle] = {}
    MarkDirty()
    LogPmmsAdminEvent("pending_requests_cleared", handle, src, {})
    return true, nil
end

local function getSpeakerListForHandle(handle)
    local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
    if session and session.settings and type(session.settings.linkedSpeakers) == "table" then
        return session.settings.linkedSpeakers
    end

    local persistent = getPersistentEntryByHandle(handle)
    if persistent and type(persistent.linkedSpeakers) == "table" then
        return persistent.linkedSpeakers
    end

    return {}
end

function GetPmmsLinkedSpeakers(handle)
    return cloneDeep(getSpeakerListForHandle(normalizeHandle(handle)))
end

function AddPmmsLinkedSpeaker(src, handle, coords, heading, propModel, persistent)
    if not Config.speakers or Config.speakers.enabled == false then
        return false, "Linked speakers are disabled."
    end

    handle = normalizeHandle(handle)
    local speakerCoords = coordsToPlain(coords)
    if not speakerCoords then
        return false, "Invalid speaker position."
    end

    local isStaff = HasPmmsPermission(src, "staff")
    local limit = isStaff and tonumber(Config.speakers.staffLimit) or tonumber(Config.speakers.normalPlayerLimit)
    if limit == nil then limit = isStaff and -1 or 1 end

    local session = type(EnsureDeviceSession) == "function" and EnsureDeviceSession(handle, {}) or nil
    if not session then
        return false, "This device is no longer known by the server."
    end

    session.settings = session.settings or {}
    session.settings.linkedSpeakers = type(session.settings.linkedSpeakers) == "table" and session.settings.linkedSpeakers or {}
    local normalSpeakerCount = 0
    for _, speaker in ipairs(session.settings.linkedSpeakers) do
        if speaker.persistent ~= true then
            normalSpeakerCount = normalSpeakerCount + 1
        end
    end
    if limit >= 0 and not isStaff and normalSpeakerCount >= limit then
        return false, ("Normal players can link %d speaker(s) per session."):format(limit)
    end

    local function generateId()
        local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        local id = ""
        for i = 1, 8 do
            local rand = math.random(1, #chars)
            id = id .. chars:sub(rand, rand)
        end
        return id
    end

    session.settings.linkedSpeakers[#session.settings.linkedSpeakers + 1] = {
        id = generateId(),
        coords = speakerCoords,
        heading = tonumber(heading) or 0.0,
        propModel = type(propModel) == "string" and propModel ~= "" and propModel or (Config.speakers and Config.speakers.propModel or Config.defaultModel or "prop_boombox_01"),
        persistent = persistent == true and isStaff,
        createdBy = GetUserIdentifier(src),
        createdByName = GetPlayerName(src),
        createdAt = os.time(),
    }

    if type(CommitDeviceSessionState) == "function" then
        CommitDeviceSessionState(handle)
    end

    if persistent == true and isStaff and Config.speakers.persistentForStaffDevices ~= false then
        local entry = getPersistentEntryByHandle(handle)
        if entry then
            entry.linkedSpeakers = cloneDeep(session.settings.linkedSpeakers)
            persistEntry(entry)
        end
    end

    LogPmmsAdminEvent("linked_speaker_added", handle, src, { persistent = persistent == true and isStaff })
    return true, nil
end

function RemovePmmsLinkedSpeaker(src, handle, speakerId)
    handle = normalizeHandle(handle)
    local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
    if not session or not session.settings or type(session.settings.linkedSpeakers) ~= "table" then
        return false, "Device session or speakers not found."
    end
    
    local isStaff = HasPmmsPermission(src, "manage")
    local identifier = GetUserIdentifier(src)
    
    local foundIndex = -1
    for i, speaker in ipairs(session.settings.linkedSpeakers) do
        if speaker.id == speakerId then
            local adminLock = type(session.settings.adminLock) == "table" and session.settings.adminLock or { mode = "public" }
            local isPublic = adminLock.mode == "public"
            
            if not isStaff and speaker.createdBy ~= identifier and not isPublic then
                return false, "You do not have permission to remove this speaker."
            end
            foundIndex = i
            break
        end
    end
    
    if foundIndex > 0 then
        table.remove(session.settings.linkedSpeakers, foundIndex)
        if type(CommitDeviceSessionState) == "function" then
            CommitDeviceSessionState(handle)
        end
        
        local entry = getPersistentEntryByHandle(handle)
        if entry and type(entry.linkedSpeakers) == "table" then
            for i, speaker in ipairs(entry.linkedSpeakers) do
                if speaker.id == speakerId then
                    table.remove(entry.linkedSpeakers, i)
                    persistEntry(entry)
                    break
                end
            end
        end
        
        LogPmmsAdminEvent("linked_speaker_removed", handle, src, { speakerId = speakerId })
        return true, nil
    end
    
    return false, "Speaker not found."
end

function ClearPmmsLinkedSpeakers(src, handle)
    handle = normalizeHandle(handle)
    if not HasPmmsPermission(src, "manage") then
        return false, "Only staff can clear linked speakers."
    end

    local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
    if session and session.settings then
        session.settings.linkedSpeakers = {}
        if type(CommitDeviceSessionState) == "function" then
            CommitDeviceSessionState(handle)
        end
    end
    local entry = getPersistentEntryByHandle(handle)
    if entry then
        entry.linkedSpeakers = {}
        persistEntry(entry)
    end
    LogPmmsAdminEvent("linked_speakers_cleared", handle, src, {})
    return true, nil
end

local function buildAdminDeviceRow(handle, label, data)
    data = type(data) == "table" and data or {}
    local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
    local pending = GetPmmsPendingRequestsForHandle(handle)
    return {
        handle = handle,
        label = label or data.label or data.name or "Device",
        active = IsMediaPlayerActive(handle),
        persistent = data.persistent == true,
        type = data.type or (data.isVehicle == true and "vehicle" or "device"),
        coords = coordsToPlain(data.coords or data.position),
        requestMode = GetPmmsDeviceRequestMode(handle),
        profile = data.profile,
        adminLock = cloneDeep(data.adminLock or getAdminLockForHandle(handle) or { mode = "public" }),
        linkedSpeakers = GetPmmsLinkedSpeakers(handle),
        pendingRequests = pending,
        pendingCount = #pending,
        stateRevision = session and session.stateRevision or 0,
        settings = cloneDeep(session and session.settings or data),
    }
end

function BuildPmmsAdminSyncState(src)
    if not HasPmmsPermission(src, "manage") then
        return nil
    end

    local rows = {}
    local seen = {}

    for handle, info in pairs(GetMediaPlayers()) do
        rows[#rows + 1] = buildAdminDeviceRow(handle, info.label or info.title or "Active Device", {
            type = info.isVehicle == true and "vehicle" or "device",
            coords = info.coords,
            adminLock = info.adminLock,
            profile = info.profile,
        })
        seen[tostring(handle)] = true
    end

    if type(GetDeviceSessions) == "function" then
        for handle, session in pairs(GetDeviceSessions()) do
            local key = tostring(handle)
            if not seen[key] then
                rows[#rows + 1] = buildAdminDeviceRow(handle, session.settings and session.settings.label or "Session Device", {
                    type = session.settings and session.settings.isVehicle == true and "vehicle" or "device",
                    adminLock = session.settings and session.settings.adminLock,
                    profile = session.settings and session.settings.profile,
                })
                seen[key] = true
            end
        end
    end

    for _, entry in ipairs(Config.defaultMediaPlayers or {}) do
        local coords = toVector(entry.position)
        if coords then
            local handle = GetHandleFromCoords(coords)
            local key = tostring(handle)
            if not seen[key] then
                rows[#rows + 1] = buildAdminDeviceRow(handle, entry.label or entry.name or "Persistent Device", {
                    persistent = true,
                    type = entry.mode == "interaction" and "interaction" or (entry.propModel and "prop" or "device"),
                    position = entry.position,
                    adminLock = entry.adminLock,
                    profile = entry.profile,
                })
                seen[key] = true
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.active ~= b.active then
            return a.active == true
        end
        return tostring(a.label) < tostring(b.label)
    end)

    return {
        devices = rows,
        profiles = GetPmmsDeviceProfilesForClient(),
    }
end

local function notifyActionResult(src, ok, message, title)
    if ok then
        TriggerClientEvent("pmms:notify", src, { title = title or "Admin", text = message or "Updated." })
    else
        TriggerClientEvent("pmms:error", src, message or "Action failed.")
    end
end

RegisterNetEvent("pmms:adminApplyProfile", function(handle, profileKey)
    local src = source
    if not HasPmmsPermission(src, "staff") then
        TriggerClientEvent("pmms:error", src, "No permission to apply device profiles.")
        return
    end
    local ok, message = ApplyPmmsDeviceProfile(handle, profileKey, src)
    notifyActionResult(src, ok, ok and "Profile applied." or message)
end)

RegisterNetEvent("pmms:adminSetRequestMode", function(handle, mode)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to change request mode.")
        return
    end
    local ok, message = SetPmmsDeviceRequestMode(handle, mode, src)
    notifyActionResult(src, ok, ok and "Request mode updated." or message)
end)

RegisterNetEvent("pmms:adminSetLock", function(handle, lock, plate)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to change admin locks.")
        return
    end
    local ok, message = SetPmmsDeviceAdminLock(handle, lock, src, plate)
    notifyActionResult(src, ok, ok and "Admin lock updated." or message)
end)

RegisterNetEvent("pmms:adminSetDeviceSettings", function(handle, settings)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to change admin settings.")
        return
    end
    local ok, message = SetPmmsAdminDeviceSettings(handle, settings, src)
    notifyActionResult(src, ok, ok and "Device settings updated." or message)
end)

RegisterNetEvent("pmms:adminRenameDevice", function(handle, name)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to rename devices.")
        return
    end

    local label = trim(name)
    if not label or #label > 80 then
        TriggerClientEvent("pmms:error", src, "Device name must be 1-80 characters.")
        return
    end

    handle = normalizeHandle(handle)
    local changed = false
    local mp = GetMediaPlayer(handle)
    if mp then
        mp.label = label
        changed = true
    end
    local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
    if session then
        session.settings = session.settings or {}
        session.settings.label = label
        if type(CommitDeviceSessionState) == "function" then
            CommitDeviceSessionState(handle)
        end
        changed = true
    end
    local persistent = getPersistentEntryByHandle(handle)
    if persistent then
        persistent.label = label
        persistent.name = label
        persistEntry(persistent)
        changed = true
    end

    if changed then
        MarkDirty()
        LogPmmsAdminEvent("device_renamed", handle, src, { label = label })
        notifyActionResult(src, true, "Device renamed.")
    else
        notifyActionResult(src, false, "This device is no longer known by the server.")
    end
end)

RegisterNetEvent("pmms:adminAddPersistentDevice", function(data)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to add persistent devices.")
        return
    end

    data = type(data) == "table" and data or {}
    local coords = toVector(data.coords)
    if not coords then
        TriggerClientEvent("pmms:error", src, "Invalid persistent device position.")
        return
    end

    local entry = {
        position = coords,
        persistent = true,
        mode = data.mode == "prop" and "prop" or "interaction",
        label = trim(data.label) or "Persistent Device",
        name = trim(data.label) or "Persistent Device",
        range = tonumber(data.range) or Config.defaultRange,
        volume = tonumber(data.volume) or Config.defaultVolume,
        requestMode = data.requestMode or (Config.requests and Config.requests.defaultMode) or "queue",
        adminLock = type(data.adminLock) == "table" and cloneDeep(data.adminLock) or { mode = "public" },
    }

    if entry.mode == "prop" then
        entry.propModel = trim(data.propModel) or Config.defaultModel
        entry.rotation = coordsToPlain(data.rotation) or { x = 0.0, y = 0.0, z = tonumber(data.heading) or 0.0 }
    end

    local profileKey = normalizeProfileKey(data.profile)
    if profileKey then
        applyProfileToTarget(entry, profileKey)
    end

    AddEntityPermanently(coords, entry)
    LogPmmsAdminEvent("persistent_device_added", GetHandleFromCoords(coords), src, {
        label = entry.label,
        mode = entry.mode,
        profile = entry.profile,
    })
    TriggerClientEvent("pmms:notify", src, { title = "Admin", text = "Persistent device added." })
end)

RegisterNetEvent("pmms:adminRemovePersistentDevice", function(handle)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to remove persistent devices.")
        return
    end

    local entry, coords = getPersistentEntryByHandle(handle)
    if not entry or not coords then
        TriggerClientEvent("pmms:error", src, "Persistent device not found.")
        return
    end

    RemoveEntityPermanently(coords)
    LogPmmsAdminEvent("persistent_device_removed", handle, src, { label = entry.label or entry.name })
    TriggerClientEvent("pmms:notify", src, { title = "Admin", text = "Persistent device removed." })
end)

RegisterNetEvent("pmms:adminApproveRequest", function(handle, requestId, playNext)
    local src = source
    local ok, message = ApprovePmmsPendingRequest(src, handle, requestId, playNext == true)
    notifyActionResult(src, ok, ok and "Request approved." or message, "Requests")
end)

RegisterNetEvent("pmms:adminRejectRequest", function(handle, requestId)
    local src = source
    local ok, message = RejectPmmsPendingRequest(src, handle, requestId)
    notifyActionResult(src, ok, ok and "Request rejected." or message, "Requests")
end)

RegisterNetEvent("pmms:adminClearRequests", function(handle)
    local src = source
    local ok, message = ClearPmmsPendingRequests(src, handle)
    notifyActionResult(src, ok, ok and "Pending requests cleared." or message, "Requests")
end)

RegisterNetEvent("pmms:addLinkedSpeaker", function(handle, coords, heading, propModel, persistent)
    local src = source
    local ok, message = AddPmmsLinkedSpeaker(src, handle, coords, heading, propModel, persistent == true)
    notifyActionResult(src, ok, ok and "Speaker linked." or message, "Speakers")
end)

RegisterNetEvent("pmms:removeLinkedSpeaker", function(handle, speakerId)
    local src = source
    local ok, message = RemovePmmsLinkedSpeaker(src, handle, speakerId)
    notifyActionResult(src, ok, ok and "Speaker removed." or message, "Speakers")
end)

RegisterNetEvent("pmms:adminClearLinkedSpeakers", function(handle)
    local src = source
    local ok, message = ClearPmmsLinkedSpeakers(src, handle)
    notifyActionResult(src, ok, ok and "Linked speakers cleared." or message, "Speakers")
end)

RegisterNetEvent("pmms:adminClearSessionLock", function(handle)
    local src = source
    if not HasPmmsPermission(src, "staff") then
        TriggerClientEvent("pmms:error", src, "No permission to clear device locks.")
        return
    end
    if type(ForceClearSessionLock) == "function" then
        ForceClearSessionLock(handle)
        LogPmmsAdminEvent("session_lock_cleared", handle, src, {})
        TriggerClientEvent("pmms:notify", src, { title = "Admin", text = "Session lock cleared." })
    else
        TriggerClientEvent("pmms:error", src, "Session lock helper is unavailable.")
    end
end)

RegisterNetEvent("pmms:adminResetProfile", function(handle)
    local src = source
    if not HasPmmsPermission(src, "manage") then
        TriggerClientEvent("pmms:error", src, "No permission to reset device profile.")
        return
    end
    handle = normalizeHandle(handle)
    local mp = GetMediaPlayer(handle)
    if mp then
        mp.profile = nil
        mp.profileLabel = nil
    end
    local session = type(GetDeviceSession) == "function" and GetDeviceSession(handle) or nil
    if session and session.settings then
        session.settings.profile = nil
        session.settings.profileLabel = nil
        if type(CommitDeviceSessionState) == "function" then
            CommitDeviceSessionState(handle)
        end
    end
    local persistent = getPersistentEntryByHandle(handle)
    if persistent then
        persistent.profile = nil
        persistent.profileLabel = nil
        persistEntry(persistent)
    end
    MarkDirty()
    TriggerClientEvent("pmms:notify", src, { title = "Admin", text = "Device profile reset to default." })
end)

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName == thisResource then
        loadAdminState()
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    for handle, list in pairs(pendingRequests) do
        for index = #list, 1, -1 do
            if list[index].source == src then
                table.remove(list, index)
            end
        end
    end
end)
