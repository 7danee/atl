-- ESX is provided by @es_extended/imports.lua

local PHASE_IDLE = 'idle'
local PHASE_REGISTRATION = 'registration'
local PHASE_PREPARATION = 'preparation'
local PHASE_ACTIVE = 'active'
local PHASE_LOOT = 'loot'

local State
local deliverCooldown = {}

local function ResetState()
    State = {
        phase = PHASE_IDLE,
        phaseEnd = 0,
        moveDeadline = 0,
        allMoved = false,
        registrations = {}, -- [source] = job name
        participants = {},  -- [source] = team key
        teams = {},         -- team1 / team2
        winner = nil,
        stashId = nil,
    }
end

ResetState()

-- Helpers -------------------------------------------------------------------

local function Notify(src, message)
    TriggerClientEvent('esx:showNotification', src, message)
end

local function OtherTeam(teamKey)
    return teamKey == 'team1' and 'team2' or 'team1'
end

local function IsEligible(xPlayer)
    local jobConfig = Config.AllowedJobs[xPlayer.job.name]
    if not jobConfig then return false end

    local grade = tonumber(xPlayer.job.grade) or 0
    return grade >= jobConfig.minGrade and grade <= jobConfig.maxGrade
end

-- Only the allowed jobs are queried instead of iterating every player on the server
local function CountJobPlayersOnline()
    local count = 0
    for job in pairs(Config.AllowedJobs) do
        count = count + #ESX.GetExtendedPlayers('job', job)
    end
    return count
end

local function NotifyEligible(message)
    for job in pairs(Config.AllowedJobs) do
        for _, xPlayer in pairs(ESX.GetExtendedPlayers('job', job)) do
            if IsEligible(xPlayer) then
                Notify(xPlayer.source, message)
            end
        end
    end
end

-- Everybody who is involved in the current scenario (registered or drawn)
local function GetInvolvedPlayers()
    local players = {}
    for src in pairs(State.registrations) do players[src] = true end
    for src in pairs(State.participants) do players[src] = true end
    return players
end

local function NotifyInvolved(message)
    for src in pairs(GetInvolvedPlayers()) do
        Notify(src, message)
    end
end

local function TriggerParticipants(eventName, ...)
    for src in pairs(State.participants) do
        TriggerClientEvent(eventName, src, ...)
    end
end

local function NotifyParticipants(message)
    for src in pairs(State.participants) do
        Notify(src, message)
    end
end

local function CountRegistrations(job)
    local count = 0
    for _, registeredJob in pairs(State.registrations) do
        if registeredJob == job then
            count = count + 1
        end
    end
    return count
end

local function PickSpawnPoints()
    local first = math.random(#Config.SpawnPoints)
    local second = math.random(#Config.SpawnPoints - 1)
    if second >= first then
        second = second + 1
    end
    return Config.SpawnPoints[first], Config.SpawnPoints[second]
end

local function VehicleExists(team)
    return team.vehicle ~= nil and DoesEntityExist(team.vehicle)
end

-- A Pounder counts as lost when it is gone or has been a wreck for a few
-- consecutive ticks (an explosion sets the engine health to -4000)
local WRECK_CONFIRM_TICKS = 3

local function IsPounderLost(team)
    if not VehicleExists(team) then
        return true
    end

    if GetVehicleEngineHealth and GetVehicleEngineHealth(team.vehicle) <= Config.WreckEngineHealth then
        team.wreckTicks = (team.wreckTicks or 0) + 1
    else
        team.wreckTicks = 0
    end

    return team.wreckTicks >= WRECK_CONFIRM_TICKS
end

local function DeleteVehicles()
    for _, team in pairs(State.teams) do
        if VehicleExists(team) then
            DeleteEntity(team.vehicle)
        end
    end
end

local function ClearStash()
    if not State.stashId then return end

    local ok, err = pcall(function()
        exports.ox_inventory:ClearInventory(State.stashId)
    end)
    if not ok then
        print(('[ATL] Could not clear stash %s: %s'):format(State.stashId, err))
    end
end

-- Scenario flow -------------------------------------------------------------

local function EndScenario(reasonKey)
    if State.phase == PHASE_IDLE then return end

    print(('[ATL] Scenario ended (%s)'):format(reasonKey or 'finished'))

    if reasonKey then
        NotifyInvolved(_L(reasonKey))
    end
    NotifyInvolved(_L('scenario_ended'))
    TriggerParticipants('atl:client:cleanup')

    DeleteVehicles()
    ClearStash()
    ResetState()
end

local function StartDrop(force)
    if State.phase ~= PHASE_IDLE then
        return false
    end

    local playerCount = CountJobPlayersOnline()
    if not force and playerCount < Config.MinPlayers then
        return false
    end

    ResetState()
    State.phase = PHASE_REGISTRATION
    State.phaseEnd = os.time() + Config.RegistrationTime

    NotifyEligible(_L('atl_dropped', math.ceil(Config.RegistrationTime / 60)))
    print(('[ATL] Drop started (players in allowed jobs: %d)'):format(playerCount))
    return true
end

local function SelectTeams()
    -- Re-validate every registration: player still online, same job, still eligible
    local playersByJob = {}
    for src, job in pairs(State.registrations) do
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer and xPlayer.job.name == job and IsEligible(xPlayer) then
            playersByJob[job] = playersByJob[job] or {}
            table.insert(playersByJob[job], src)
        else
            State.registrations[src] = nil
        end
    end

    local jobs = {}
    for job, players in pairs(playersByJob) do
        if #players >= Config.MinPlayersPerTeam then
            table.insert(jobs, job)
        end
    end

    if #jobs < 2 then
        return false
    end

    local job1 = table.remove(jobs, math.random(#jobs))
    local job2 = jobs[math.random(#jobs)]
    local spawn1, spawn2 = PickSpawnPoints()

    local function BuildTeam(index, job, spawn)
        local jobConfig = Config.AllowedJobs[job]
        return {
            index = index,
            job = job,
            label = jobConfig.label or job,
            players = playersByJob[job],
            spawn = spawn,
            blipColor = jobConfig.blipColor,
            vehicleColor = jobConfig.vehicleColor,
            vehicle = nil,
            netId = nil,
            moved = false,
            lost = false,
        }
    end

    State.teams = {
        team1 = BuildTeam(1, job1, spawn1),
        team2 = BuildTeam(2, job2, spawn2),
    }

    for teamKey, team in pairs(State.teams) do
        for _, src in ipairs(team.players) do
            State.participants[src] = teamKey
        end
    end

    -- Registered players of factions that were not drawn
    for src, job in pairs(State.registrations) do
        if job ~= job1 and job ~= job2 then
            Notify(src, _L('not_selected'))
        end
    end
    State.registrations = {}

    NotifyParticipants(_L('teams_selected', State.teams.team1.label, State.teams.team2.label))
    print(('[ATL] Teams drawn: %s vs %s'):format(job1, job2))
    return true
end

local function StartPreparation()
    State.phase = PHASE_PREPARATION
    State.phaseEnd = os.time() + Config.PreparationTime

    -- Iterate participants (not team.players) so dropped players and reused ids are skipped
    for src, teamKey in pairs(State.participants) do
        local team = State.teams[teamKey]
        local enemy = State.teams[OtherTeam(teamKey)]
        TriggerClientEvent('atl:client:start', src, {
            teamKey = teamKey,
            ownBase = team.spawn.coords,
            enemyBase = enemy.spawn.coords,
            ownColor = team.blipColor,
            enemyColor = enemy.blipColor,
        })
    end

    NotifyParticipants(_L('preparation', math.ceil(Config.PreparationTime / 60)))
end

local function SpawnPounder(team)
    local coords = team.spawn.coords
    local vehicle = CreateVehicleServerSetter(GetHashKey(Config.PounderModel), 'automobile', coords.x, coords.y, coords.z, team.spawn.heading)

    local timeout = GetGameTimer() + 5000
    while not DoesEntityExist(vehicle) and GetGameTimer() < timeout do
        Wait(50)
    end

    if not DoesEntityExist(vehicle) then
        return false
    end

    -- Keep the entity alive when its owner leaves (newer server artifacts only)
    if SetEntityOrphanMode then
        SetEntityOrphanMode(vehicle, 2)
    end

    SetVehicleNumberPlateText(vehicle, ('ATL %d'):format(team.index))
    SetVehicleColours(vehicle, team.vehicleColor, team.vehicleColor)

    team.vehicle = vehicle
    team.netId = NetworkGetNetworkIdFromEntity(vehicle)
    return true
end

local function SpawnPounders()
    local scenario = State

    for _, team in pairs(scenario.teams) do
        local spawned = SpawnPounder(team)

        -- The scenario was stopped while waiting for the entity (e.g. /stopatl)
        if State ~= scenario then
            if VehicleExists(team) then
                DeleteEntity(team.vehicle)
            end
            return
        end

        if not spawned then
            print(('[ATL] Could not spawn Pounder for %s'):format(team.job))
            EndScenario('spawn_failed')
            return
        end
    end

    State.phase = PHASE_ACTIVE
    State.phaseEnd = os.time() + Config.MaxActiveTime
    State.moveDeadline = os.time() + Config.PounderMoveTime
    State.allMoved = false

    for src, teamKey in pairs(State.participants) do
        TriggerClientEvent('atl:client:pounders', src, State.teams[teamKey].netId)
    end

    NotifyParticipants(_L('pounder_spawned', Config.PounderMoveTime, ('%g'):format(Config.PounderMoveDistance)))
    NotifyParticipants(_L('deliver'))
end

local function StartLootPhase(teamKey)
    local team = State.teams[teamKey]

    State.phase = PHASE_LOOT
    State.phaseEnd = os.time() + Config.LootTime
    State.winner = teamKey

    FreezeEntityPosition(team.vehicle, true)
    SetVehicleDoorsLocked(team.vehicle, 2)

    local lootCoords = GetEntityCoords(team.vehicle)
    State.stashId = ('atl_loot_%d'):format(os.time())

    local ok, err = pcall(function()
        exports.ox_inventory:RegisterStash(State.stashId, _L('loot_label'), Config.LootSlots, Config.LootMaxWeight, nil, { [team.job] = 0 }, lootCoords)

        for _, entry in ipairs(Config.Loot) do
            if exports.ox_inventory:Items(entry.item) then
                local amount = math.random(entry.min, entry.max)
                exports.ox_inventory:AddItem(State.stashId, entry.item, amount)
            else
                print(('[ATL] Loot item "%s" does not exist in ox_inventory, skipped'):format(entry.item))
            end
        end
    end)

    if not ok then
        print(('[ATL] Could not create loot stash: %s'):format(err))
    end

    NotifyParticipants(_L('delivered', team.label))
    TriggerParticipants('atl:client:pounderDisabled', team.netId)

    for src, participantTeam in pairs(State.participants) do
        if participantTeam == teamKey then
            TriggerClientEvent('atl:client:lootReady', src, State.stashId, lootCoords)
            Notify(src, _L('loot_ready', math.ceil(Config.LootTime / 60)))
        end
    end

    print(('[ATL] %s delivered the Pounder'):format(team.job))
end

local function RemovePlayer(src)
    State.registrations[src] = nil
    State.participants[src] = nil
    deliverCooldown[src] = nil
end

-- Active phase checks, runs every second
local function TickActive(now)
    -- Destroyed (wrecked) or deleted Pounders
    local lostCount = 0
    for _, team in pairs(State.teams) do
        if not team.lost and IsPounderLost(team) then
            team.lost = true
            NotifyParticipants(_L('pounder_lost', team.label))
        end
        if team.lost then
            lostCount = lostCount + 1
        end
    end

    if lostCount >= 2 then
        EndScenario('all_lost')
        return
    end

    -- Movement check
    if not State.allMoved then
        local allMoved = true
        for _, team in pairs(State.teams) do
            if not team.moved and not team.lost then
                local distance = #(GetEntityCoords(team.vehicle) - team.spawn.coords)
                if distance >= Config.PounderMoveDistance then
                    team.moved = true
                else
                    allMoved = false
                end
            end
        end

        State.allMoved = allMoved

        if not allMoved and now >= State.moveDeadline then
            EndScenario('pounder_not_moved')
            return
        end
    end

    if now >= State.phaseEnd then
        EndScenario('timeout')
    end
end

local function SendPounderPositions()
    local positions = {}
    for teamKey, team in pairs(State.teams) do
        if VehicleExists(team) then
            positions[teamKey] = GetEntityCoords(team.vehicle)
        end
    end
    TriggerParticipants('atl:client:pounderPositions', positions)
end

-- Events --------------------------------------------------------------------

RegisterNetEvent('atl:server:deliver', function()
    local src = source
    if State.phase ~= PHASE_ACTIVE then return end

    local now = GetGameTimer()
    if deliverCooldown[src] and now - deliverCooldown[src] < 1000 then return end
    deliverCooldown[src] = now

    local teamKey = State.participants[src]
    if not teamKey then return end

    local team = State.teams[teamKey]
    if team.lost or not VehicleExists(team) then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or xPlayer.job.name ~= team.job then return end

    -- The sender must be the driver of their own team's Pounder ...
    if GetPedInVehicleSeat(team.vehicle, -1) ~= GetPlayerPed(src) then return end

    -- ... and the Pounder must be inside the enemy delivery zone
    local enemy = State.teams[OtherTeam(teamKey)]
    local distance = #(GetEntityCoords(team.vehicle) - enemy.spawn.coords)
    if distance > Config.DeliveryRadius + Config.DeliveryTolerance then return end

    StartLootPhase(teamKey)
end)

RegisterCommand('acceptatl', function(source)
    local src = source
    if src == 0 then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    if State.phase ~= PHASE_REGISTRATION then
        Notify(src, _L('no_atl'))
        return
    end

    if State.registrations[src] then
        Notify(src, _L('already_registered'))
        return
    end

    if not IsEligible(xPlayer) then
        Notify(src, _L('not_eligible'))
        return
    end

    local job = xPlayer.job.name
    if CountRegistrations(job) >= Config.MaxPlayersPerTeam then
        Notify(src, _L('team_full', Config.MaxPlayersPerTeam))
        return
    end

    State.registrations[src] = job
    Notify(src, _L('registered'))
end, false)

-- Admin commands, restricted via ACE: add_ace group.admin command.startatl allow
local function Reply(src, message)
    if src == 0 then
        print('[ATL] ' .. message)
    else
        Notify(src, message)
    end
end

RegisterCommand('startatl', function(source)
    if StartDrop(true) then
        Reply(source, _L('admin_started'))
    else
        Reply(source, _L('admin_running'))
    end
end, true)

RegisterCommand('stopatl', function(source)
    if State.phase == PHASE_IDLE then
        Reply(source, _L('admin_not_running'))
        return
    end
    EndScenario()
    Reply(source, _L('admin_stopped'))
end, true)

AddEventHandler('playerDropped', function()
    RemovePlayer(source)
end)

-- ESX Legacy: fired on the server whenever a player's job changes
AddEventHandler('esx:setJob', function(src, job, lastJob)
    if not job or not lastJob or job.name == lastJob.name then return end

    if State.participants[src] then
        TriggerClientEvent('atl:client:cleanup', src)
        Notify(src, _L('left_scenario'))
    end
    RemovePlayer(src)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    DeleteVehicles()
    ClearStash()
end)

-- Main loop -----------------------------------------------------------------
-- A single server thread drives every phase, the blip updates and the auto drop.

local function NextDropCheck()
    return os.time() + math.random(Config.DropCheckInterval.min, Config.DropCheckInterval.max) * 60
end

CreateThread(function()
    local nextDropCheck = NextDropCheck()
    local nextBlipUpdate = 0

    while true do
        Wait(1000)

        local now = os.time()
        local phase = State.phase

        if phase == PHASE_IDLE then
            if Config.AutoDrop and now >= nextDropCheck then
                nextDropCheck = NextDropCheck()
                if math.random(100) <= Config.DropChance then
                    StartDrop(false)
                end
            end
        elseif phase == PHASE_REGISTRATION and now >= State.phaseEnd then
            if SelectTeams() then
                StartPreparation()
            else
                EndScenario('cancelled_teams')
            end
        elseif phase == PHASE_PREPARATION and now >= State.phaseEnd then
            SpawnPounders()
        elseif phase == PHASE_ACTIVE then
            TickActive(now)
        elseif phase == PHASE_LOOT and now >= State.phaseEnd then
            EndScenario()
        end

        if (State.phase == PHASE_ACTIVE or State.phase == PHASE_LOOT) and GetGameTimer() >= nextBlipUpdate then
            nextBlipUpdate = GetGameTimer() + Config.BlipUpdateInterval
            SendPounderPositions()
        end
    end
end)

-- Startup checks ------------------------------------------------------------

CreateThread(function()
    if GetConvar('onesync', 'off') == 'off' then
        print('^1[ATL] OneSync is required. Enable it in your server.cfg (set onesync on).^0')
    end

    if #Config.SpawnPoints < 2 then
        print('^1[ATL] At least 2 entries in Config.SpawnPoints are required.^0')
    end

    if not Locales[Config.Locale] then
        print(('^3[ATL] Locale "%s" not found, falling back to "en".^0'):format(Config.Locale))
    end
end)
