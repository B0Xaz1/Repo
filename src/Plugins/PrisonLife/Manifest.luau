--!nonstrict
-- Prison Life (by Aesthetical) data manifest.
-- Coordinates, gun names, and obstacle folders come from the legacy plugin that ran
-- against the live map. Runtime resolution still prefers tagged map objects, named map
-- objects, and live folders over these fallbacks so a map update cannot break the plugin.
return function(_services: any?): any
    local manifest = {
        Name = "Prison Life",
        -- Place 155615604 is the live Prison Life place. Add a universe id to the second
        -- table if the experience grows extra places that should share this adapter.
        PlaceIds = { 155615604 },
        UniverseIds = {},
        -- CollectionService tags of the form "<TagPrefix>:<Id>" override manifest fallbacks at runtime.
        TagPrefix = "B0XazPrisonLife",

        -- Ordered on purpose: buttons and dropdowns keep a stable order.
        -- IsGun marks real guns (cycled by the macro, tuned by weapon mods); the remaining
        -- entries are items the game also hands out. The seven guns match the legacy set.
        Weapons = {
            {
                Id = "M9", Name = "M9", ToolNames = { "M9" }, Category = "Sidearm", IsGun = true,
                Spawn = Vector3.new(816.65, 102.50, 2229.37), Pickup = "M9",
            },
            {
                Id = "Remington870", Name = "Remington 870", ToolNames = { "Remington 870" }, Category = "Shotgun", IsGun = true,
                Spawn = Vector3.new(820.27, 102.50, 2229.31), Pickup = "Remington 870",
            },
            {
                Id = "MP5", Name = "MP5", ToolNames = { "MP5" }, Category = "SMG", IsGun = true,
                Spawn = Vector3.new(813.72, 102.50, 2229.37), Pickup = "MP5",
            },
            {
                Id = "AK47", Name = "AK-47", ToolNames = { "AK-47" }, Category = "Rifle", IsGun = true,
                Spawn = Vector3.new(-932.00, 100.74, 2039.50), Pickup = "AK-47",
            },
            {
                Id = "M4A1", Name = "M4A1", ToolNames = { "M4A1" }, Category = "Rifle", IsGun = true,
                Pickup = "M4A1",
            },
            {
                Id = "M700", Name = "M700", ToolNames = { "M700" }, Category = "Sniper", IsGun = true,
                Pickup = "M700",
            },
            {
                Id = "Revolver", Name = "Revolver", ToolNames = { "Revolver" }, Category = "Sidearm", IsGun = true,
                Pickup = "Revolver",
            },
            {
                Id = "Taser", Name = "Taser", ToolNames = { "Taser" }, Category = "Special",
                Spawn = Vector3.new(813.00, 102.50, 2229.30),
            },
            {
                Id = "Hammer", Name = "Hammer", ToolNames = { "Hammer" }, Category = "Item", Pickup = "Hammer",
            },
            {
                Id = "Keycard", Name = "Keycard", ToolNames = { "Keycard" }, Category = "Item",
            },
        },

        -- Prison Life guns have carried their stats in two forms across updates: a
        -- GunStates ModuleScript table (Spread/FireRate/AutoFire/Range) and instance
        -- attributes (SpreadRadius/FireRate/AutoFire/Range) on the tool or its children.
        -- Weapon mods honor whichever a tool carries and back both up.
        GunMods = {
            ModuleName = "GunStates",
            ModuleFields = { "Spread", "FireRate", "AutoFire", "Range" },
            Attributes = { "SpreadRadius", "FireRate", "AutoFire", "Range" },
        },
        -- Armory pickup flow: workspace.Remote.ItemHandler:InvokeServer(workspace.Prison_ITEMS.giver.<name>.ITEMPICKUP)
        Items = {
            RemoteFolder = "Remote", RemoteName = "ItemHandler",
            GiverRoot = "Prison_ITEMS", GiverFolders = { "giver", "single" }, PickupChild = "ITEMPICKUP",
        },

        -- Ordered locations. CFrame values are legacy fallbacks; resolution prefers
        -- CollectionService tags ("B0XazPrisonLife:<Id>"), then map objects whose name
        -- matches a Keyword, then these coordinates.
        Locations = {
            {
                Id = "PrisonCells", Name = "Prison Cells", Category = "Prison", CFrame = CFrame.new(920, 98, 2436),
                Keywords = { "cells", "cellblock", "jailblock", "jail" },
            },
            {
                Id = "Cafeteria", Name = "Cafeteria", Category = "Prison", CFrame = CFrame.new(920, 98, 2290),
                Keywords = { "cafeteria", "canteen" },
            },
            {
                Id = "PrisonYard", Name = "Prison Yard", Category = "Prison", CFrame = CFrame.new(779, 98, 2463),
                Keywords = { "yard", "courtyard" },
            },
            {
                Id = "PoliceArmory", Name = "Police Armory", Category = "Armory", CFrame = CFrame.new(831, 98, 2284),
                Keywords = { "armory", "armoury" },
            },
            {
                Id = "BreakRoom", Name = "Break Room", Category = "Police", CFrame = CFrame.new(800.09, 99.99, 2266.72),
                Keywords = { "breakroom", "lounge" },
            },
            {
                Id = "SurveillanceRoom", Name = "Surveillance Room", Category = "Police", CFrame = CFrame.new(795.25, 99.99, 2327.72),
                Keywords = { "surveillance", "cameraroom", "securityroom" },
            },
            {
                Id = "ParkingLot", Name = "Parking Lot", Category = "Police", CFrame = CFrame.new(745, 98, 2148),
                Keywords = { "parking", "policecars" },
            },
            {
                Id = "PrisonEntrance", Name = "Prison Entrance", Category = "Police", CFrame = CFrame.new(710, 100, 2300),
                Keywords = { "entrance" },
            },
            {
                Id = "Kitchen", Name = "Kitchen", Category = "Interior", CFrame = CFrame.new(906.64, 99.99, 2237.67),
                Keywords = { "kitchen" },
            },
            {
                Id = "Roof", Name = "Roof", Category = "Interior", CFrame = CFrame.new(845, 130, 2235),
                Keywords = { "roof" },
            },
            {
                Id = "Tunnels", Name = "Tunnels", Category = "Escape", CFrame = CFrame.new(918, 80, 2284),
                Keywords = { "tunnel", "tunnels", "sewer" },
            },
            {
                Id = "OutsidePrison", Name = "Outside Prison", Category = "Escape", CFrame = CFrame.new(451.67, 98.04, 2216.34),
                Keywords = { "outside" },
            },
            {
                Id = "PrisonWalkway", Name = "Prison Walkway", Category = "Escape", CFrame = CFrame.new(505, 125, 2330),
                Keywords = { "walkway" },
            },
            {
                Id = "CriminalBase", Name = "Criminal Base", Category = "Criminal", CFrame = CFrame.new(-943, 95, 2058),
                Keywords = { "criminalbase", "crimbase" },
            },
            {
                Id = "SecretRoom", Name = "Secret Room", Category = "Interior", CFrame = CFrame.new(674, 98, 2384),
                Keywords = { "secret" },
            },
        },
        LocationCategories = { "Prison", "Armory", "Police", "Interior", "Escape", "Criminal", "Custom" },

        -- Legacy obstacle containers, matched case-insensitively against workspace
        -- children. Everything inside them is phaseable.
        Doors = {
            Folders = { "doors", "glass", "celldoors", "prison_fences", "prison_gate" },
            -- Heuristic fallback if a map update renames every known container.
            NamePatterns = { "door", "gate", "cell", "fence", "glass" },
        },

        Macro = {
            MinGuns = 2, -- the macro needs at least two guns to cycle
        },
    }

    local function freezeDeep(value: any): any
        if type(value) == "table" then
            for _, child in pairs(value) do freezeDeep(child) end
            table.freeze(value)
        end
        return value
    end
    return freezeDeep(manifest)
end
