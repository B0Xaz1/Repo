return function(_services: any?): any
    local CONFIG = {
        Name = "Zombie Attack",

        -- Root place plus the Hardmode place for Zombie Attack (group 3576655); no universe id
        -- is registered because place-to-universe lookups need an authenticated call
        PlaceIds = { 1240123653, 1632210982 },
        UniverseIds = {},
        TagPrefix = "B0XazZombieAttack",

        Enemies = {
            -- First name wins on an exact match, then a case-insensitive sweep
            Containers = { "enemies", "Enemies", "zombies", "Zombies", "Zombie" },
            MaxScan = 240,
        },

        Aim = {
            -- Preferred hit part first, then the fallbacks for rigs that lack it (R6 has no UpperTorso)
            Parts = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" },
        },

        Aura = {
            DefaultRate = 0.1,
            MinRate = 0.01,
            MaxRate = 1,
            RateStep = 0.01,
            -- 0 disables the distance gate, matching the standalone script
            DefaultRange = 0,
            MaxRange = 1000,
            RangeStep = 10,
        },

        Gun = {
            Remote = { "Gun" },
            -- Only consulted when the manifest path misses; a bounded named sweep
            RemoteNames = { "Gun", "GunRemote", "GunFire", "Shoot", "Fire", "ShootGun" },
            RemoteScanDepth = 3,
            RemoteRetryDelay = 2,
            OriginHeight = 1.5,
            DirectionMagnitude = 1000,
            Normal = { 1, 0, 0 },
        },

        Farm = {
            -- Stands the player off the zombie's own facing, matching the suite's engage offsets
            UpOffset = 7,
            BackOffset = 7,
        },

        Weapons = {
            -- A Tool carrying one of these is a gun; the controller is a script in this game
            GunControllers = { "GunController" },
            -- Counted and reported but never equipped, so the knife assumption stays checkable at runtime
            KnifeControllers = { "KnifeController" },
        },
    }

    local function freezeDeep(value: any): any
        if type(value) == "table" then
            for _, child in pairs(value) do freezeDeep(child) end
            table.freeze(value)
        end
        return value
    end
    return freezeDeep(CONFIG)
end
