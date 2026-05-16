
local activePlacement = nil

local PLACEMENT_KEYS = {
    confirm    = 38,
    cancel     = 194,
    groundSnap = 74,
    rotLeft    = 174,
    rotRight   = 175,
    heightUp   = 172,
    heightDown = 173,
}

local ROTATION_SPEED = 3.0
local HEIGHT_SPEED   = 0.05
local GHOST_ALPHA    = 120


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
    SetEntityCoordsNoOffset(prop, coords.x, coords.y, coords.z, false, false, false)
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


local function runPlacementLoop(ctx)
    local ped          = PlayerPedId()
    local heightOffset = 0.0
    local heading      = GetEntityHeading(ped)

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

    local hint = "~g~[E]~w~ Place  ~r~[Backspace]~w~ Cancel  ~b~[Left/Right]~w~ Rotate  ~b~[Up/Down]~w~ Height  ~b~[O]~w~ Ground"

    while activePlacement == ctx do
        Wait(0)
        ped = PlayerPedId()

        local fwd = GetEntityForwardVector(ped)
        local ppos = GetEntityCoords(ped)
        local tx = ppos.x + fwd.x * 1.5
        local ty = ppos.y + fwd.y * 1.5
        local tz = getGroundZ(tx, ty, ppos.z) + heightOffset

        SetEntityCoordsNoOffset(prop, tx, ty, tz, false, false, false)
        SetEntityHeading(prop, heading)

        drawHint(hint)

        if IsDisabledControlPressed(0, PLACEMENT_KEYS.rotLeft) then
            heading = (heading + ROTATION_SPEED) % 360.0
        elseif IsDisabledControlPressed(0, PLACEMENT_KEYS.rotRight) then
            heading = (heading - ROTATION_SPEED + 360.0) % 360.0
        end

        if IsDisabledControlPressed(0, PLACEMENT_KEYS.heightUp) then
            heightOffset = heightOffset + HEIGHT_SPEED
        elseif IsDisabledControlPressed(0, PLACEMENT_KEYS.heightDown) then
            heightOffset = math.max(-1.5, heightOffset - HEIGHT_SPEED)
        end

        if IsDisabledControlJustPressed(0, PLACEMENT_KEYS.groundSnap) then
            heightOffset = 0.0
        end

        DisableControlAction(0, PLACEMENT_KEYS.confirm, true)
        DisableControlAction(0, PLACEMENT_KEYS.cancel, true)
        DisableControlAction(0, PLACEMENT_KEYS.rotLeft, true)
        DisableControlAction(0, PLACEMENT_KEYS.rotRight, true)
        DisableControlAction(0, PLACEMENT_KEYS.heightUp, true)
        DisableControlAction(0, PLACEMENT_KEYS.heightDown, true)
        DisableControlAction(0, PLACEMENT_KEYS.groundSnap, true)

        if IsDisabledControlJustPressed(0, PLACEMENT_KEYS.confirm) or IsControlJustPressed(0, PLACEMENT_KEYS.confirm) then
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

        if IsDisabledControlJustPressed(0, PLACEMENT_KEYS.cancel) or IsControlJustPressed(0, PLACEMENT_KEYS.cancel) then
            deleteGhostProp(ctx)
            activePlacement = nil
            DisablePlayerFiring(ped, false)
            TriggerEvent("pmms:placement:cancelled", ctx)
            return
        end
    end

    deleteGhostProp(ctx)
    DisablePlayerFiring(PlayerPedId(), false)
end


function StartSpeakerPlacementMode(handle, persistent, propModel, anchor)
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
        anchor    = anchor,
    }
    activePlacement = ctx

    CreateThread(function()
        runPlacementLoop(ctx)
    end)
end

function StartDevicePlacementMode(data)
    if activePlacement then return end

    local mode = (data and data.mode) or "interaction"
    local model = (data and data.propModel)
        or Config.defaultModel
        or "sf_prop_sf_speaker_l_01a"

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


AddEventHandler("pmms:placement:confirmed", function(ctx, coords, heading)
    if ctx.type == "speaker" then
        TriggerServerEvent("pmms:addLinkedSpeaker",
            ctx.handle,
            coords,
            heading,
            ctx.propModel,
            ctx.persistent,
            ctx.anchor
        )
        TriggerEvent("pmms:showUi", nil, ctx.persistent and "view-admin" or "view-home")

    elseif ctx.type == "device" then
        TriggerServerEvent("pmms:adminAddPersistentDevice", {
            coords   = coords,
            rotation = { x = 0.0, y = 0.0, z = heading },
            heading  = heading,
            mode     = ctx.mode,
            label    = ctx.label,
            propModel = ctx.mode == "prop" and ctx.realModel or nil,
            profile  = ctx.profile,
            requestMode = ctx.requestMode,
            adminLock = ctx.adminLock,
        })
    end
end)

RegisterNetEvent("pmms:persistentDeviceAddResult", function(result)
    result = type(result) == "table" and result or {}
    if result.ok == true then
        SetTimeout(250, function()
            TriggerEvent("pmms:showUi", result.handle, "view-admin")
        end)
        return
    end

    SetTimeout(250, function()
        TriggerEvent("pmms:showUi", nil, "view-admin")
    end)
end)

AddEventHandler("pmms:placement:cancelled", function(ctx)
    if ctx and (ctx.handle or ctx.type) then
        Wait(100)
        TriggerEvent("pmms:showUi", nil, (ctx.type == "device" or ctx.persistent == true) and "view-admin" or "view-home")
    end
end)
