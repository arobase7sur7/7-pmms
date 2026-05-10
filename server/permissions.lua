local permissionCache = {}
local cacheTtlMs = 1500

local permissionNames = {
    "interact",
    "anyEntity",
    "customUrl",
    "anyUrl",
    "manage",
    "overrideDevice",
    "staff",
}

local getGradeLevel

local function nowMs()
    return GetGameTimer and GetGameTimer() or 0
end

local function getPermissionConfig()
    return type(Config.permissions) == "table" and Config.permissions or {}
end

local function getQbConfig()
    local permissions = getPermissionConfig()
    return type(permissions.qbcore) == "table" and permissions.qbcore or {}
end

local function getMode()
    local permissions = getPermissionConfig()
    local qbcore = getQbConfig()
    local mode = tostring(permissions.mode or "ace"):lower()

    if mode ~= "qbcore" and mode ~= "hybrid" and mode ~= "ace" then
        mode = qbcore.enabled == true and "hybrid" or "ace"
    end

    if mode == "ace" and qbcore.enabled == true then
        mode = "hybrid"
    end

    return mode
end

local function getAceName(permission)
    permission = tostring(permission or "")
    if permission:find("^pmms%.") then
        return permission
    end
    return "pmms." .. permission
end

local function getIdentifierPrincipals(src)
    local principals = {}
    if tonumber(src) == 0 then
        return principals
    end

    principals[#principals + 1] = "player." .. tostring(src)

    for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
        if type(identifier) == "string" and identifier ~= "" then
            principals[#principals + 1] = "identifier." .. identifier
        end
    end

    return principals
end

local function hasConfigPermission(src, permission)
    if tonumber(src) == 0 then
        return true
    end
    
    local config = getPermissionConfig()
    local adminIdentifiers = type(config.adminIdentifiers) == "table" and config.adminIdentifiers or {}
    local staffIdentifiers = type(config.staffIdentifiers) == "table" and config.staffIdentifiers or {}
    
    local isStaffPerm = permission == "overrideDevice" or permission == "staff" or permission == "anyEntity" or permission == "customUrl" or permission == "anyUrl"
    
    local playerIdentifiers = GetPlayerIdentifiers(tostring(src)) or {}
    
    -- Diagnostic print (always visible if this is called)
    if permission == "manage" then
        print(("^4[7-pmms] Checking 'manage' permission for %s (%s)^7"):format(GetPlayerName(src), src))
    end
    
    for _, identifier in ipairs(playerIdentifiers) do
        local cleanId = tostring(identifier):lower()
        if cleanId ~= "" then
            for _, adminId in ipairs(adminIdentifiers) do
                local cleanAdminId = tostring(adminId):lower()
                if cleanId == cleanAdminId or cleanId:find(cleanAdminId, 1, true) or cleanAdminId:find(cleanId, 1, true) then
                    print(("^2[7-pmms] PERMISSION GRANTED (Admin Config): %s matched %s^7"):format(GetPlayerName(src), adminId))
                    return true
                end
            end
            
            if isStaffPerm then
                for _, staffId in ipairs(staffIdentifiers) do
                    local cleanStaffId = tostring(staffId):lower()
                    if cleanId == cleanStaffId or cleanId:find(cleanStaffId, 1, true) or cleanStaffId:find(cleanId, 1, true) then
                        print(("^2[7-pmms] PERMISSION GRANTED (Staff Config): %s matched %s^7"):format(GetPlayerName(src), staffId))
                        return true
                    end
                end
            end
        end
    end
    
    return false
end



local function isSourceAceAllowed(src, aceName)
    local ok, allowed = pcall(function()
        return IsPlayerAceAllowed(tostring(src), aceName)
    end)
    if ok and allowed == true then
        return true
    end

    ok, allowed = pcall(function()
        return IsPlayerAceAllowed(src, aceName)
    end)
    if ok and allowed == true then
        return true
    end

    if type(IsPrincipalAceAllowed) == "function" then
        for _, principal in ipairs(getIdentifierPrincipals(src)) do
            ok, allowed = pcall(function()
                return IsPrincipalAceAllowed(principal, aceName)
            end)
            if ok and allowed == true then
                return true
            end
        end
    end

    return false
end

local function permissionCanUseAdminAceFallback(permission)
    permission = tostring(permission or ""):gsub("^pmms%.", "")
    return permission == "manage"
        or permission == "overrideDevice"
        or permission == "anyEntity"
        or permission == "customUrl"
        or permission == "anyUrl"
end

local function getAdminAceFallbacks()
    local permissions = getPermissionConfig()
    if type(permissions.adminAceFallbacks) == "table" then
        return permissions.adminAceFallbacks
    end
    return { "command", "god", "admin", "qbcore.god", "qbcore.admin", "command.tpm", "command.addpermission" }
end

local function getAllowedAdminAceFallback(src, permission)
    if not permissionCanUseAdminAceFallback(permission) then
        return nil
    end

    for _, aceName in ipairs(getAdminAceFallbacks()) do
        if type(aceName) == "string" and aceName ~= "" and isSourceAceAllowed(src, aceName) then
            return aceName
        end
    end

    return nil
end

local function hasAcePermission(src, permission)
    if tonumber(src) == 0 then
        return true
    end
    if isSourceAceAllowed(src, getAceName(permission)) then
        return true
    end
    return getAllowedAdminAceFallback(src, permission) ~= nil
end

local function getQBCore()
    local qbcore = getQbConfig()
    local resourceName = qbcore.resource or "qb-core"

    if GetResourceState(resourceName) ~= "started" then
        return nil
    end

    local ok, core = pcall(function()
        return exports[resourceName]:GetCoreObject()
    end)

    if ok and core and core.Functions then
        return core
    end

    return nil
end

local function getPlayerIdentifiersForDebug(src)
    local identifiers = {}
    if tonumber(src) == 0 then
        return identifiers
    end

    for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
        identifiers[#identifiers + 1] = identifier
    end

    table.sort(identifiers)
    return identifiers
end

local function hasQbFrameworkPermission(core, src, permissionName)
    if not core or not core.Functions then
        return false
    end

    local permissionText = tostring(permissionName or ""):lower()
    if permissionText == "" then
        return false
    end

    local permissionCandidates = { permissionText }
    if not permissionText:find("^qbcore%.") then
        permissionCandidates[#permissionCandidates + 1] = "qbcore." .. permissionText
    end

    for _, sourceValue in ipairs({ src, tostring(src) }) do
        for _, candidate in ipairs(permissionCandidates) do
            if type(core.Functions.HasPermission) == "function" then
                local ok, allowed = pcall(function()
                    return core.Functions.HasPermission(sourceValue, candidate)
                end)

                if ok and allowed == true then
                    return true
                end
            end

            if isSourceAceAllowed(sourceValue, candidate) then
                return true
            end
        end
    end

    return false
end

local function getPlayerData(core, src)
    if not core or not core.Functions or type(core.Functions.GetPlayer) ~= "function" then
        return nil
    end

    local ok, player = pcall(function()
        return core.Functions.GetPlayer(src)
    end)

    if ok and player and type(player.PlayerData) == "table" then
        return player.PlayerData
    end

    return nil
end

local function normalizeGroupData(group)
    if type(group) ~= "table" then
        return nil
    end

    return {
        name = group.name,
        label = group.label,
        grade = getGradeLevel(group),
    }
end

getGradeLevel = function(group)
    if type(group) ~= "table" then
        return 0
    end

    local grade = group.grade
    if type(grade) == "table" then
        return tonumber(grade.level or grade.grade or grade.value) or 0
    end

    return tonumber(grade) or 0
end

local function normalizeRule(rule)
    if rule == true then
        return true, 0
    end

    if type(rule) == "number" then
        return true, rule
    end

    if type(rule) == "table" then
        local minGrade = tonumber(rule.minGrade or rule.grade or rule.level) or 0
        return true, minGrade
    end

    return false, 0
end

local function matchesGroupRule(rulesByPermission, permission, group)
    if type(rulesByPermission) ~= "table" or type(group) ~= "table" then
        return false
    end

    local permissionRules = rulesByPermission[permission]
    if type(permissionRules) ~= "table" then
        return false
    end

    local groupName = group.name
    if not groupName then
        return false
    end

    local enabled, minGrade = normalizeRule(permissionRules[groupName])
    if not enabled then
        return false
    end

    return getGradeLevel(group) >= minGrade
end

local function getPermissionQbNames(permission)
    local qbcore = getQbConfig()
    local map = type(qbcore.permissionMap) == "table" and qbcore.permissionMap or {}
    local names = map[permission]

    if type(names) == "string" then
        return { names }
    end

    if type(names) == "table" then
        return names
    end

    if permission == "manage" or permission == "overrideDevice" then
        return qbcore.adminPermissions or { "god", "admin" }
    end

    return {}
end

local function hasQbPermission(src, permission)
    if tonumber(src) == 0 then
        return true
    end

    local core = getQBCore()
    if not core then
        return false
    end

    for _, permissionName in ipairs(getQbConfig().adminPermissions or { "god", "admin" }) do
        if hasQbFrameworkPermission(core, src, permissionName) then
            return true
        end
    end

    for _, permissionName in ipairs(getPermissionQbNames(permission)) do
        if hasQbFrameworkPermission(core, src, permissionName) then
            return true
        end
    end

    local playerData = getPlayerData(core, src)
    local qbcore = getQbConfig()
    if matchesGroupRule(qbcore.jobs, permission, playerData and playerData.job or nil) then
        return true
    end

    if matchesGroupRule(qbcore.gangs, permission, playerData and playerData.gang or nil) then
        return true
    end

    return false
end

function HasPmmsPermission(src, permission)
    if not src or tonumber(src) == 0 then return true end

    -- 1. CONFIG IDENTIFIERS
    local config = type(Config.permissions) == "table" and Config.permissions or {}
    local adminIds = type(config.adminIdentifiers) == "table" and config.adminIdentifiers or {}
    local staffIds = type(config.staffIdentifiers) == "table" and config.staffIdentifiers or {}
    local playerIds = GetPlayerIdentifiers(tostring(src)) or {}

    for _, pid in ipairs(playerIds) do
        local lowerPid = pid:lower()
        for _, aid in ipairs(adminIds) do
            if lowerPid == aid:lower() then return true end
        end
        if permission ~= "manage" then
            for _, sid in ipairs(staffIds) do
                if lowerPid == sid:lower() then return true end
            end
        end
    end

    -- 2. QBCORE
    local core = getQBCore()
    if core and type(core.Functions) == "table" and type(core.Functions.HasPermission) == "function" then
        if core.Functions.HasPermission(src, "admin") or core.Functions.HasPermission(src, "god") then
            return true
        end
    end

    -- 3. ACE
    if IsPlayerAceAllowed(src, "admin") or IsPlayerAceAllowed(src, "pmms.manage") or IsPlayerAceAllowed(src, "command.tpm") then
        return true
    end

    -- 4. DEFAULT
    if permission == "interact" then
        return true
    end

    if permission == "staff" then
        return HasPmmsPermission(src, "manage") or HasPmmsPermission(src, "overrideDevice")
    end

    return false
end


function IsPmmsStaff(src)
    return HasPmmsPermission(src, "staff")
end

function GetPmmsPlayerGroups(src)
    local groups = {
        job = nil,
        gang = nil,
    }

    local core = getQBCore()
    if not core then
        return groups
    end

    local playerData = getPlayerData(core, src)
    if type(playerData) ~= "table" then
        return groups
    end

    groups.job = normalizeGroupData(playerData.job)
    groups.gang = normalizeGroupData(playerData.gang)
    return groups
end

function GetPmmsPermissions(src)
    local permissions = {}
    for _, permission in ipairs(permissionNames) do
        permissions[permission] = HasPmmsPermission(src, permission)
    end
    return permissions
end

function GetPmmsPermissionDiagnostic(src)
    src = tonumber(src) or 0

    local qbcore = getQbConfig()
    local core = getQBCore()
    local mode = getMode()
    local diagnostics = {
        source = src,
        name = src ~= 0 and GetPlayerName(src) or "server",
        mode = mode,
        qbcore = {
            enabled = qbcore.enabled == true,
            resource = qbcore.resource or "qb-core",
            state = GetResourceState(qbcore.resource or "qb-core"),
            available = core ~= nil,
            aceFallback = qbcore.aceFallback == true,
            adminPermissions = qbcore.adminPermissions or { "god", "admin" },
            adminResults = {},
        },
        identifiers = getPlayerIdentifiersForDebug(src),
        groups = GetPmmsPlayerGroups(src),
        permissions = {},
    }

    for _, permissionName in ipairs(diagnostics.qbcore.adminPermissions) do
        diagnostics.qbcore.adminResults[tostring(permissionName)] =
            core ~= nil and hasQbFrameworkPermission(core, src, permissionName) or false
    end

    for _, permission in ipairs(permissionNames) do
        diagnostics.permissions[permission] = {
            final = HasPmmsPermission(src, permission),
            ace = hasAcePermission(src, permission),
            aceFallback = getAllowedAdminAceFallback(src, permission),
            qbcore = core ~= nil and hasQbPermission(src, permission) or false,
            aceName = getAceName(permission),
            qbcoreNames = getPermissionQbNames(permission),
        }
    end

    return diagnostics
end

local function boolText(value)
    return value and "true" or "false"
end

local function listText(list)
    if type(list) ~= "table" or #list == 0 then
        return "-"
    end
    return table.concat(list, ", ")
end

function PrintPmmsPermissionDiagnostic(requestSource, targetSource)
    targetSource = tonumber(targetSource or requestSource) or 0
    if targetSource ~= 0 and not GetPlayerName(targetSource) then
        local message = ("[7-pmms] Permission diagnostic failed: player %s is not online."):format(tostring(targetSource))
        print(message)
        if tonumber(requestSource) ~= 0 then
            TriggerClientEvent("pmms:notify", requestSource, { title = "PMMS Permissions", text = message })
        end
        return
    end

    local diagnostic = GetPmmsPermissionDiagnostic(targetSource)
    local header = ("[7-pmms] Permission diagnostic for %s (%s): mode=%s qbcore=%s/%s/%s"):format(
        diagnostic.name or "?",
        tostring(targetSource),
        diagnostic.mode,
        diagnostic.qbcore.resource,
        diagnostic.qbcore.state,
        diagnostic.qbcore.available and "available" or "unavailable"
    )
    print(header)
    print("[7-pmms] identifiers: " .. listText(diagnostic.identifiers))
    print(("[7-pmms] qbcore admin checks: %s"):format(json.encode(diagnostic.qbcore.adminResults)))

    local notifyLines = { header }
    for _, permission in ipairs(permissionNames) do
        local row = diagnostic.permissions[permission]
        local line = ("%s final=%s ace=%s qbcore=%s fallback=%s aceName=%s qbNames=%s"):format(
            permission,
            boolText(row.final),
            boolText(row.ace),
            boolText(row.qbcore),
            tostring(row.aceFallback or "-"),
            tostring(row.aceName),
            listText(row.qbcoreNames)
        )
        print("[7-pmms] " .. line)
        if permission == "manage" or permission == "overrideDevice" or permission == "staff" then
            notifyLines[#notifyLines + 1] = line
        end
    end

    if tonumber(requestSource) ~= 0 then
        TriggerClientEvent("pmms:notify", requestSource, {
            title = "PMMS Permissions",
            text = table.concat(notifyLines, "\n"),
            duration = 12000,
        })
    end
end

function ClearPmmsPermissionCache(src)
    if not src then
        permissionCache = {}
        return
    end

    local prefix = tostring(src) .. ":"
    for key in pairs(permissionCache) do
        if key:sub(1, #prefix) == prefix then
            permissionCache[key] = nil
        end
    end
end

AddEventHandler("playerDropped", function()
    ClearPmmsPermissionCache(source)
end)

RegisterCommand("pmmsdebug", function(source, args, rawCommand)
    local src = source
    if src == 0 then
        print("This command must be run by a player.")
        return
    end
    
    local name = GetPlayerName(src)
    local identifiers = GetPlayerIdentifiers(src)
    local permissions = GetPmmsPermissions(src)
    local mode = getMode()
    
    print("^2[7-pmms] Debug for " .. name .. " (" .. src .. ")^7")
    print("Mode: " .. mode)
    print("Permissions: " .. json.encode(permissions))
    print("Identifiers: " .. json.encode(identifiers))
    
    TriggerClientEvent("chat:addMessage", src, {
        color = { 0, 255, 0 },
        multiline = true,
        args = { "PMMS Debug", "Check server console for detailed info. Manage: " .. tostring(permissions.manage) }
    })
end, false)

