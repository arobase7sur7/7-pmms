-- ============================================================
--  PMMS Ghost Placement System
--  Provides interactive prop preview for speakers and devices
-- ============================================================

local activePlacement = nil

-- Controls (configurable)
local PLACEMENT_KEYS = {
    confirm    = 38,  -- E
    cancel     = 194, -- Backspace
    groundSnap = 74,  -- O
    rotLeft    = 174, -- Arrow Left
    rotRight   = 175, -- Arrow Right
    heightUp   = 172, -- Arrow Up
    heightDown = 173, -- Arrow Down
}

local ROTATION_SPEED = 3.0    -- degrees per tick
local HEIGHT_SPEED   = 0.05   -- metres per tick
local GHOST_ALPHA    = 120    -- 0-255

-- ── Helpers ──────────────────────────────────────────────────

local function getGroundZ(x, y, z)
    local found, gz = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
    if not found then
        found, gz = GetGroundZFor_3dCoord(x, y, z + 5.0, false)
    end
    return found and gz or z
end

local function deleteGhostProp(placement)
    if placement and placement.prop and DoesEntityExist(placement.prop) then
        DeleteEntity(placement.prop)
    end
end

local function spawnGhostProp(model, coords, heading)
    local hash = GetHashKey(model)
    if not IsModelValid(hash) then
        hash = GetHashKey("sf_prop_sf_speaker_l_01a")
    end

    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    if not HasModelLoaded(hash) then return nil end

    local prop = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityAlpha(prop, GHOST_ALPHA, false)
    SetEntityCollision(prop, false, false)
    FreezeEntityPosition(prop, true)
    SetEntityHeading(prop, heading)
    SetModelAsNoLongerNeeded(hash)
    return prop
end

local function getForwardOffset(ped, dist)
    local fwd = GetEntityForwardVector(ped)
    local pos = GetEntityCoords(ped)
    return vector3(pos.x + fwd.x * dist, pos.y + fwd.y * dist, pos.z)
end

local function drawHint(text)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextScale(0.0, 0.45)
    SetTextColour(255, 255, 255, 215)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(2, 0, 0, 0, 150)
    SetTextDropShadow()
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry("STRING")
    AddTextComponentSubstringPlayerName(text)
    DrawText(0.5, 0.92)
end

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if activePlacement and activePlacement.prop and DoesEntityExist(activePlacement.prop) then
        DeleteEntity(activePlacement.prop)
    end
end)

-- ── Core Placement Loop ──────────────────────────────────────

local function runPlacementLoop(ctx)
    local ped          = PlayerPedId()
    local heightOffset = 0.0
    local heading      = GetEntityHeading(ped)

    -- Spawn ghost
    local initPos = getForwardOffset(ped, 1.5)
    local groundZ = getGroundZ(initPos.x, initPos.y, initPos.z)
    local pos = vector3(initPos.x, initPos.y, groundZ)

    local prop = spawnGhostProp(ctx.propModel or "sf_prop_sf_speaker_l_01a", pos, heading)
    if not prop then
        TriggerEvent("pmms:placement:cancelled", ctx)
        return
    end
    ctx.prop = prop

    DisablePlayerFiring(ped, true)

    local hint = "~g~[E]~w~ Place  ~r~[Backspace]~w~ Cancel  ~b~[←/→]~w~ Rotate  ~b~[↑/↓]~w~ Height  ~b~[O]~w~ Ground"

    while activePlacement == ctx do
        Wait(0)
        ped = PlayerPedId()

        -- Update ghost position (follows player view, 1.5m ahead)
        local fwd = GetEntityForwardVector(ped)
        local ppos = GetEntityCoords(ped)
        local tx = ppos.x + fwd.x * 1.5
        local ty = ppos.y + fwd.y * 1.5
        local tz = getGroundZ(tx, ty, ppos.z) + heightOffset

        SetEntityCoordsNoOffset(prop, tx, ty, tz, false, false, false)
        SetEntityHeading(prop, heading)

        drawHint(hint)

        -- Rotation
        if IsDisabledControlPressed(0, PLACEMENT_KEYS.rotLeft) then
            heading = (heading + ROTATION_SPEED) % 360.0
        elseif IsDisabledControlPressed(0, PLACEMENT_KEYS.rotRight) then
            heading = (heading - ROTATION_SPEED + 360.0) % 360.0
        end

        -- Height
        if IsDisabledControlPressed(0, PLACEMENT_KEYS.heightUp) then
            heightOffset = heightOffset + HEIGHT_SPEED
        elseif IsDisabledControlPressed(0, PLACEMENT_KEYS.heightDown) then
            heightOffset = math.max(-1.5, heightOffset - HEIGHT_SPEED)
        end

        -- Ground snap
        if IsDisabledControlJustPressed(0, PLACEMENT_KEYS.groundSnap) then
            heightOffset = 0.0
        end

        -- Disable default actions for keys we're using
        DisableControlAction(0, PLACEMENT_KEYS.confirm, true)
        DisableControlAction(0, PLACEMENT_KEYS.cancel, true)
        DisableControlAction(0, PLACEMENT_KEYS.rotLeft, true)
        DisableControlAction(0, PLACEMENT_KEYS.rotRight, true)
        DisableControlAction(0, PLACEMENT_KEYS.heightUp, true)
        DisableControlAction(0, PLACEMENT_KEYS.heightDown, true)
        DisableControlAction(0, PLACEMENT_KEYS.groundSnap, true)

        -- Confirm
        if IsDisabledControlJustPressed(0, PLACEMENT_KEYS.confirm) then
            local finalPos = GetEntityCoords(prop)
            deleteGhostProp(ctx)
            activePlacement = nil
            DisablePlayerFiring(ped, false)
            TriggerEvent("pmms:placement:confirmed", ctx, {
                x = finalPos.x,
                y = finalPos.y,
                z = finalPos.z,
            }, heading)
            return
        end

        -- Cancel
        if IsDisabledControlJustPressed(0, PLACEMENT_KEYS.cancel) then
            deleteGhostProp(ctx)
            activePlacement = nil
            DisablePlayerFiring(ped, false)
            TriggerEvent("pmms:placement:cancelled", ctx)
            return
        end
    end

    -- Cleaned up externally
    deleteGhostProp(ctx)
    DisablePlayerFiring(PlayerPedId(), false)
end

-- ── Public API ───────────────────────────────────────────────

--- Start placement mode for a linked speaker
--- @param handle number  Device handle
--- @param persistent boolean  Whether to create a persistent speaker
--- @param propModel string  Optional override prop model
function StartSpeakerPlacementMode(handle, persistent, propModel)
    if activePlacement then return end

    local speakerModel = propModel
        or (Config.speakers and Config.speakers.propModel)
        or Config.defaultModel
        or "sf_prop_sf_speaker_l_01a"

    local ctx = {
        type      = "speaker",
        handle    = handle,
        persistent = persistent == true,
        propModel = speakerModel,
    }
    activePlacement = ctx

    CreateThread(function()
        runPlacementLoop(ctx)
    end)
end

--- Start placement mode for a persistent prop/interaction device
--- @param data table  NUI payload (mode, label, propModel, profile, etc.)
function StartDevicePlacementMode(data)
    if activePlacement then return end

    local mode = (data and data.mode) or "interaction"
    local model = (data and data.propModel)
        or Config.defaultModel
        or "sf_prop_sf_speaker_l_01a"

    -- For interaction points, use an invisible stand-in
    local ghostModel = mode == "prop" and model or "prop_boombox_01"

    local ctx = {
        type      = "device",
        mode      = mode,
        label     = data and data.label or nil,
        propModel = ghostModel,
        realModel = model,
        profile   = data and data.profile or nil,
        requestMode = data and data.requestMode or nil,
        adminLock = data and data.adminLock or nil,
    }
    activePlacement = ctx

    CreateThread(function()
        runPlacementLoop(ctx)
    end)
end

-- ── Result Handlers ──────────────────────────────────────────

AddEventHandler("pmms:placement:confirmed", function(ctx, coords, heading)
    if ctx.type == "speaker" then
        TriggerServerEvent("pmms:addLinkedSpeaker",
            ctx.handle,
            coords,
            heading,
            ctx.propModel,
            ctx.persistent
        )
        TriggerEvent("pmms:showUi")

    elseif ctx.type == "device" then
        local ped = PlayerPedId()
        local rot = GetEntityRotation(ped, 2)
        TriggerServerEvent("pmms:adminAddPersistentDevice", {
            coords   = coords,
            rotation = { x = rot.x, y = rot.y, z = rot.z },
            heading  = heading,
            mode     = ctx.mode,
            label    = ctx.label,
            propModel = ctx.mode == "prop" and ctx.realModel or nil,
            profile  = ctx.profile,
            requestMode = ctx.requestMode,
            adminLock = ctx.adminLock,
        })
        TriggerEvent("pmms:showUi")
    end
end)

AddEventHandler("pmms:placement:cancelled", function(ctx)
    -- Re-open UI after cancellation so the user isn't stranded
    if ctx and (ctx.handle or ctx.type) then
        Wait(100)
        TriggerEvent("pmms:showUi")
    end
end)
