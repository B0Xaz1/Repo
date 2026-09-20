--!strict

return function(_services: any?): any
    local CONFIG = {
        Name = "Zombie Attack",

        -- Zombie Attack by Zombie Attack Official (group 3576655).
        -- 1240123653 is the root place; 1632210982 is the "Zombie Attack [Hardmode]" place
        -- in the same game. The universe id is not registered: Roblox's place-to-universe
        -- lookups require an authenticated call, so the id could not be confirmed here.
        PlaceIds = { 1240123653, 1632210982 },
        UniverseIds = {},
        TagPrefix = "B0XazZombieAttack",

        Enemies = {
            -- First name wins on an exact match, then a case-insensitive sweep.
            Containers = { "enemies", "Enemies", "zombies", "Zombies", "Zombie" },
            MaxScan = 240,
        },

        Aim = {
            -- Preferred hit part first; the rest are the fallback chain when a zombie
            -- rig does not carry it (R6 rigs have no UpperTorso, for example).
            Parts = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" },
        },

        Aura = {
            DefaultRate = 0.1,
            MinRate = 0.01,
            MaxRate = 1,
            RateStep = 0.01,
            -- 0 = no distance limit, matching the standalone script's behavior.
            DefaultRange = 0,
            MaxRange = 1000,
            RangeStep = 10,
        },

        Gun = {
            Remote = { "Gun" },
            -- Only consulted when the manifest path misses; a bounded named sweep.
            RemoteNames = { "Gun", "GunRemote", "GunFire", "Shoot", "Fire", "ShootGun" },
            RemoteScanDepth = 3,
            RemoteRetryDelay = 2,
            OriginHeight = 1.5,
            DirectionMagnitude = 1000,
            Normal = { 1, 0, 0 },
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
