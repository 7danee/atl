-- ESX is provided by @es_extended/imports.lua

local active = false
local myTeam = nil
local ownBase, enemyBase = nil, nil
local ownColor, enemyColor = 0, 0
local ownNetId = nil
local loot = nil -- { stashId = string, coords = vector3 }
local lastDeliverAttempt = 0
local loopSession = 0 -- bumped per scenario, so an old interaction loop always exits
local StartInteractionLoop

local blips = {
    bases = {},
    pounders = {},
}

-- Blips ---------------------------------------------------------------------

local function SetBlipLabel(blip, label)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
end

local function CreateBaseBlip(coords, color, label)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, Config.Blips.base.sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, Config.Blips.base.scale)
    SetBlipColour(blip, color)
    SetBlipAsShortRange(blip, false)
    SetBlipLabel(blip, label)
    table.insert(blips.bases, blip)
end

local function CreateZoneBlip(coords, color)
    if Config.Blips.deliveryZoneAlpha <= 0 then return end

    local blip = AddBlipForRadius(coords.x, coords.y, coords.z, Config.DeliveryRadius)
    SetBlipColour(blip, color)
    SetBlipAlpha(blip, Config.Blips.deliveryZoneAlpha)
    table.insert(blips.bases, blip)
end

local function UpdatePounderBlip(teamKey, coords)
    local blip = blips.pounders[teamKey]

    if not blip then
        local isOwn = teamKey == myTeam
        blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, Config.Blips.pounder.sprite)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, Config.Blips.pounder.scale)
        SetBlipColour(blip, isOwn and ownColor or enemyColor)
        SetBlipAsShortRange(blip, false)
        SetBlipLabel(blip, isOwn and _L('blip_own_pounder') or _L('blip_enemy_pounder'))
        blips.pounders[teamKey] = blip
    else
        SetBlipCoords(blip, coords.x, coords.y, coords.z)
    end
end

local function RemoveAllBlips()
    for _, blip in ipairs(blips.bases) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    for _, blip in pairs(blips.pounders) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    blips.bases = {}
    blips.pounders = {}
end

local function Cleanup()
    RemoveAllBlips()
    active = false
    myTeam = nil
    ownBase, enemyBase = nil, nil
    ownNetId = nil
    loot = nil
end

-- Events --------------------------------------------------------------------

RegisterNetEvent('atl:client:start', function(data)
    Cleanup()

    active = true
    myTeam = data.teamKey
    ownBase = data.ownBase
    enemyBase = data.enemyBase
    ownColor = data.ownColor
    enemyColor = data.enemyColor

    CreateBaseBlip(ownBase, ownColor, _L('blip_own_base'))
    CreateBaseBlip(enemyBase, enemyColor, _L('blip_enemy_base'))
    CreateZoneBlip(enemyBase, enemyColor)

    StartInteractionLoop()
end)

RegisterNetEvent('atl:client:pounders', function(ownId)
    ownNetId = ownId
end)

RegisterNetEvent('atl:client:pounderPositions', function(positions)
    if not active then return end

    for teamKey, blip in pairs(blips.pounders) do
        if not positions[teamKey] then
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            blips.pounders[teamKey] = nil
        end
    end

    for teamKey, coords in pairs(positions) do
        UpdatePounderBlip(teamKey, coords)
    end
end)

RegisterNetEvent('atl:client:pounderDisabled', function(netId)
    if not NetworkDoesNetworkIdExist(netId) then return end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(vehicle) then
        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleUndriveable(vehicle, true)
    end
end)

RegisterNetEvent('atl:client:lootReady', function(stashId, coords)
    if not active then return end
    loot = { stashId = stashId, coords = coords }
end)

RegisterNetEvent('atl:client:cleanup', Cleanup)

-- Interaction loop ----------------------------------------------------------

local function GetOwnPounderDriven(ped)
    if not ownNetId then return nil end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return nil end
    if not NetworkGetEntityIsNetworked(vehicle) then return nil end
    if NetworkGetNetworkIdFromEntity(vehicle) ~= ownNetId then return nil end

    return vehicle
end

-- Runs only while this player takes part in a scenario
StartInteractionLoop = function()
    loopSession = loopSession + 1
    local session = loopSession

    CreateThread(function()
        while active and session == loopSession do
            local sleep = 1000
            local ped = PlayerPedId()

            if loot then
                -- Winners: open the trunk (ox_inventory checks job and distance server-side)
                if not IsPedInAnyVehicle(ped, false) then
                    local distance = #(GetEntityCoords(ped) - loot.coords)
                    if distance <= Config.LootDistance then
                        sleep = 0
                        ESX.ShowHelpNotification(_L('loot_help'))
                        if IsControlJustPressed(0, 38) then
                            exports.ox_inventory:openInventory('stash', loot.stashId)
                        end
                    elseif distance <= 50.0 then
                        sleep = 250
                    end
                end
            elseif enemyBase then
                -- Driver of the own Pounder inside the enemy delivery zone
                local vehicle = GetOwnPounderDriven(ped)
                if vehicle then
                    sleep = 250
                    local distance = #(GetEntityCoords(vehicle) - enemyBase)
                    if distance <= Config.DeliveryRadius then
                        sleep = 0
                        ESX.ShowHelpNotification(_L('deliver_help'))
                        if IsControlJustPressed(0, 38) and GetGameTimer() - lastDeliverAttempt > 2000 then
                            lastDeliverAttempt = GetGameTimer()
                            StartVehicleHorn(vehicle, 1000, GetHashKey('HELDDOWN'), false)
                            TriggerServerEvent('atl:server:deliver')
                        end
                    end
                end
            end

            Wait(sleep)
        end
    end)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    RemoveAllBlips()
end)
