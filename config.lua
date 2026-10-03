Config = {}
Locales = {}

-- Language of all notifications ('de' or 'en', see locales/)
Config.Locale = 'de'

-- Minimum number of online players in the allowed jobs (all grades) for a drop
Config.MinPlayers = 50

-- Automatic drops: checked every 30-60 minutes, then rolled with this chance
Config.AutoDrop = true
Config.DropCheckInterval = { min = 30, max = 60 } -- minutes
Config.DropChance = 30 -- percent

-- Team size limits (per faction)
Config.MaxPlayersPerTeam = 17
Config.MinPlayersPerTeam = 1 -- factions with fewer registrations are not drawn

-- Allowed jobs
--   minGrade / maxGrade : grades that may register with /acceptatl
--   blipColor           : GTA blip colour id (docs.fivem.net/docs/game-references/blips/#blip-colors)
--   vehicleColor        : GTA vehicle colour id for the Pounder (primary + secondary)
Config.AllowedJobs = {
    ['vagos'] = {
        label = 'Vagos',
        minGrade = 9,
        maxGrade = 12,
        blipColor = 46,     -- yellow
        vehicleColor = 89   -- race yellow
    },
    ['ballas'] = {
        label = 'Ballas',
        minGrade = 9,
        maxGrade = 12,
        blipColor = 27,     -- purple
        vehicleColor = 145  -- purple
    },
    ['grove'] = {
        label = 'Grove Street',
        minGrade = 9,
        maxGrade = 12,
        blipColor = 2,      -- green
        vehicleColor = 53   -- green
    }
}

-- Times (seconds)
Config.RegistrationTime = 600 -- registration phase
Config.PreparationTime = 300  -- until the Pounders spawn
Config.PounderMoveTime = 60   -- time to move the Pounder after spawn
Config.MaxActiveTime = 1800   -- scenario ends without a winner after this time
Config.LootTime = 600         -- time for the winners to empty the trunk

-- Distances (metres)
Config.PounderMoveDistance = 5.0 -- minimum distance the Pounder has to be moved
Config.DeliveryRadius = 10.0     -- delivery zone around the enemy base
Config.DeliveryTolerance = 3.0   -- extra server-side tolerance for position sync lag
Config.LootDistance = 5.0        -- distance to the Pounder to open the trunk

-- How often Pounder positions are pushed to the participants' map (milliseconds, min. 1000)
Config.BlipUpdateInterval = 2000

-- Base spawn points ("castles"), two are picked at random per scenario
Config.SpawnPoints = {
    { coords = vector3(331.23, -2039.85, 20.94), heading = 140.0 },  -- La Mesa
    { coords = vector3(1397.49, 1141.91, 114.33), heading = 0.0 },   -- Vinewood Hills
    { coords = vector3(-1542.43, -85.37, 54.93), heading = 230.0 },  -- Rockford Hills
    { coords = vector3(2436.52, 4964.18, 46.81), heading = 45.0 },   -- Grapeseed
    { coords = vector3(1698.30, 3589.16, 35.62), heading = 210.0 },  -- Sandy Shores
    { coords = vector3(-22.16, -1433.13, 30.65), heading = 180.0 },  -- Vespucci
    { coords = vector3(85.74, -1959.50, 20.85), heading = 320.0 },   -- Davis
    { coords = vector3(-1105.86, -1690.03, 4.37), heading = 125.0 }, -- Vespucci Beach
}

Config.PounderModel = 'pounder'

-- Loot (ox_inventory item names). Items that do not exist in ox_inventory are skipped with a warning.
Config.Loot = {
    { item = 'WEAPON_REVOLVER', min = 2, max = 3 },
    { item = 'WEAPON_SPECIALCARBINE', min = 4, max = 7 },
    { item = 'military_kevlar', min = 50, max = 175 },
    { item = 'WEAPON_PISTOL', min = 1, max = 3 },
    { item = 'WEAPON_COMBATPISTOL', min = 1, max = 2 },
    { item = 'WEAPON_HEAVYPISTOL', min = 1, max = 2 },
    { item = 'ammo-9', min = 50, max = 150 },
    { item = 'ammo-rifle', min = 100, max = 300 },
}
Config.LootSlots = 50
Config.LootMaxWeight = 1000000

-- Blips
Config.Blips = {
    base = { sprite = 473, scale = 1.2 },
    pounder = { sprite = 67, scale = 1.0 },
    deliveryZoneAlpha = 100 -- 0 disables the delivery radius on the map
}

function _L(key, ...)
    local locale = Locales[Config.Locale] or Locales['en'] or {}
    local text = locale[key] or key
    if select('#', ...) > 0 then
        return text:format(...)
    end
    return text
end
