--!strict

return function(_services: any?): any
    local CONFIG = {
        Name = "Prison Fight",
        PlaceIds = { 135787580685512 },
        UniverseIds = {},
        TagPrefix = "B0XazPrisonFight",

        Weapons = {
            { Id = "MP5", Name = "MP5", ToolNames = { "MP5" }, Category = "SMG", IsGun = true },
            { Id = "Remington870", Name = "Remington 870", ToolNames = { "Remington 870" }, Category = "Shotgun", IsGun = true },
            { Id = "AK47", Name = "AK-47", ToolNames = { "AK-47" }, Category = "Rifle", IsGun = true },
            { Id = "Taser", Name = "Taser", ToolNames = { "Taser" }, Category = "Special" },
        },

        GunMods = {
            ModuleName = "GunStates",
            ModuleFields = { "Spread", "FireRate", "AutoFire", "Range" },
            Attributes = { "SpreadRadius", "FireRate", "AutoFire", "Range" },
        },

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
