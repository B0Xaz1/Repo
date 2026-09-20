return function(_services: any?): any
    local CONFIG = {
        Name = "Prison Life",

        PlaceIds = { 155615604 },
        UniverseIds = {},

        TagPrefix = "B0XazPrisonLife",

        Weapons = {
            {
                Id = "MP5", Name = "MP5", ToolNames = { "MP5" }, Category = "SMG", IsGun = true,
                Spawn = Vector3.new(813.72, 102.50, 2229.37), Pickup = "MP5",
            },
            {
                Id = "Remington870", Name = "Remington 870", ToolNames = { "Remington 870" }, Category = "Shotgun", IsGun = true,
                Spawn = Vector3.new(820.27, 102.50, 2229.31), Pickup = "Remington 870",
            },
            {
                Id = "AK47", Name = "AK-47", ToolNames = { "AK-47" }, Category = "Rifle", IsGun = true,
                Spawn = Vector3.new(-932.00, 100.74, 2039.50), Pickup = "AK-47",
            },
            {
                Id = "Taser", Name = "Taser", ToolNames = { "Taser" }, Category = "Special",
                Spawn = Vector3.new(813.00, 102.50, 2229.30),
            },
        },

        GunMods = {
            ModuleName = "GunStates",
            ModuleFields = { "Spread", "FireRate", "AutoFire", "Range" },
            Attributes = { "SpreadRadius", "FireRate", "AutoFire", "Range" },
        },

        Items = {
            RemoteFolder = "Remote", RemoteName = "ItemHandler",
            GiverRoot = "Prison_ITEMS", GiverFolders = { "giver", "single" }, PickupChild = "ITEMPICKUP",
        },

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

        Doors = {
            Folders = { "doors", "glass", "celldoors", "prison_fences", "prison_gate" },

            NamePatterns = { "door", "gate", "cell", "fence", "glass" },
        },

        Macro = {
            MinGuns = 3,
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
