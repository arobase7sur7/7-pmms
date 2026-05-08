local function parseOptions(args, requiredArguments, fn)
    local i = 1
    while i <= #args do
        local option, argument
        if args[i]:sub(1, 1) == "-" then
            option = args[i]:sub(2)
            if requiredArguments[option] then
                argument = args[i + 1]
                i = i + 1
            end
        else
            argument = args[i]
        end
        fn(option, argument)
        i = i + 1
    end
end

RegisterCommand(Config.commandPrefix, function(source)
    TriggerClientEvent("pmms:showControls", source)
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "play", function(source, args)
    if #args > 0 then
        local options = {}
        local requiredArguments = {
            offset = true, size = true, sra = true, dra = true,
            drv = true, range = true, visualization = true, volume = true,
        }

        parseOptions(args, requiredArguments, function(option, argument)
            if option == "filter" then options.filter = true
            elseif option == "nofilter" then options.filter = false
            elseif option == "loop" then
                options.loop = true
                options.loopMode = "track"
            elseif option == "offset" then options.offset = argument
            elseif option == "lock" then options.locked = true
            elseif option == "video" then options.video = true
            elseif option == "size" then options.videoSize = tonumber(argument)
            elseif option == "mute" then options.muted = true
            elseif option == "sra" then
                options.attenuation = options.attenuation or {}
                options.attenuation.sameRoom = tonumber(argument)
            elseif option == "dra" then
                options.attenuation = options.attenuation or {}
                options.attenuation.diffRoom = tonumber(argument)
            elseif option == "drv" then options.diffRoomVolume = tonumber(argument)
            elseif option == "range" then options.range = tonumber(argument)
            elseif option == "veh" then options.isVehicle = true
            elseif option == "notveh" then options.isVehicle = false
            elseif option == "visualization" then options.visualization = argument
            elseif option == "volume" then options.volume = tonumber(argument)
            elseif not option then options.url = argument
            end
        end)

        TriggerClientEvent("pmms:startClosestMediaPlayer", source, options)
    else
        TriggerClientEvent("pmms:pauseClosestMediaPlayer", source)
    end
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "pause", function(source)
    TriggerClientEvent("pmms:pauseClosestMediaPlayer", source)
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "stop", function(source)
    TriggerClientEvent("pmms:stopClosestMediaPlayer", source)
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "status", function(source)
    TriggerClientEvent("pmms:toggleStatus", source)
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "presets", function(source)
    TriggerClientEvent("pmms:listPresets", source)
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "vol", function(source, args)
    if #args < 1 then
        TriggerClientEvent("pmms:showBaseVolume", source)
    else
        local volume = tonumber(args[1])
        if volume then TriggerClientEvent("pmms:setBaseVolume", source, volume) end
    end
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "add", function(source, args)
    local model = args[1]
    local label = args[2]
    local renderTarget = args[3]
    AddModelPermanently(GetHashKey(model), { label = label, renderTarget = renderTarget })
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "fix", function(source)
    TriggerClientEvent("pmms:reset", source)
end, true)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "refresh_perms", function()
    TriggerClientEvent("pmms:refreshPermissions", -1)
end, true)

local function printProviderStats(source)
    if source ~= 0 and not IsPlayerAceAllowed(source, "pmms.manage") then
        TriggerClientEvent("pmms:error", source, "You do not have permission for this command")
        return
    end

    if type(GetResolverProviderStatsSummary) ~= "function" then
        local message = "[7-pmms] Provider stats are unavailable."
        if source == 0 then print(message) else TriggerClientEvent("pmms:notify", source, { title = "7-PMMS", text = "Provider stats are unavailable." }) end
        return
    end

    local summary = GetResolverProviderStatsSummary(10)
    local header = ("[7-pmms] Provider ranking: %d successful auto starts / %d attempts (threshold %d starts, %d samples/provider)"):format(
        summary.totalCompletedAutoPlays or 0,
        summary.totalAttempts or 0,
        summary.minCompletedPlays or 0,
        summary.minProviderSamples or 0
    )
    print(header)

    local lines = { header }
    for index, row in ipairs(summary.rows or {}) do
        local line = ("%d. %s score %.1f | %d/%d success (%.0f%%) | avg %.0fms%s"):format(
            index,
            row.provider,
            row.score or 0,
            row.successes or 0,
            row.attempts or 0,
            (row.successRate or 0) * 100,
            row.avgStartupMs or 0,
            row.adaptive and "" or " | warming up"
        )
        print("[7-pmms] " .. line)
        lines[#lines + 1] = line
    end

    if source ~= 0 then
        TriggerClientEvent("pmms:notify", source, {
            title = "Provider Ranking",
            text = table.concat(lines, "\n"),
            duration = 9000,
        })
    end
end

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "providers", function(source)
    printProviderStats(source)
end, false)

RegisterCommand("pmmsproviders", function(source)
    printProviderStats(source)
end, false)

RegisterCommand(Config.commandPrefix .. Config.commandSeparator .. "ctl", function(source, args)
    if #args < 1 then
        print("Usage:")
        print("  ctl list | lock | unlock | mute | unmute | loop | next | pause | stop <handle>")
        return
    end

    local cmd = args[1]
    local handle = tonumber(args[2])

    if cmd == "list" then
        for h, info in pairs(GetMediaPlayers()) do
            print(("[%d] %s %s vol:%d %d/%s %s %s"):format(
                h, info.title or "?", info.filter and "filter" or "nofilter",
                info.volume, info.offset, info.duration or "inf",
                info.locked and "locked" or "unlocked",
                (info.paused and "paused" or "playing") .. " mode:" .. (NormalizeLoopMode and NormalizeLoopMode(info.loopMode, info.loop) or (info.loop and "track" or "off"))
            ))
        end
    elseif cmd == "lock" and handle then
        local mp = GetMediaPlayer(handle) if mp then mp.locked = true MarkDirty() end
    elseif cmd == "unlock" and handle then
        local mp = GetMediaPlayer(handle) if mp then mp.locked = false MarkDirty() end
    elseif cmd == "mute" and handle then
        local mp = GetMediaPlayer(handle) if mp then mp.muted = true MarkDirty() end
    elseif cmd == "unmute" and handle then
        local mp = GetMediaPlayer(handle) if mp then mp.muted = false MarkDirty() end
    elseif cmd == "next" and handle then
        PlayNextInQueue(handle)
    elseif cmd == "pause" and handle then
        PauseMediaPlayer(handle)
    elseif cmd == "stop" and handle then
        RemoveMediaPlayer(handle)
    elseif cmd == "loop" and handle then
        local mp = GetMediaPlayer(handle)
        if mp then
            local desired = args[3] == "on" and "track" or "off"
            if NormalizeLoopMode then
                mp.loopMode = NormalizeLoopMode(desired, mp.loop)
            else
                mp.loopMode = desired
            end
            mp.loop = mp.loopMode == "track"
            MarkDirty()
        end
    end
end, true)
