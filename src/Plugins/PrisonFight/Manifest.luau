--!nonstrict
-- Prison Fight (by @1mmxw) data manifest. The game is a Prison Life fan fork focused on
-- gun fighting on the shared prison map and models. This adapter intentionally exposes
-- only door phasing and the weapon switch macro; the manifest therefore carries just the
-- gun table the macro needs for detection plus the obstacle containers for phasing.
return function(_services: any?): any
    local manifest = {
        Name = "Prison Fight",
        PlaceIds = { 135787580685512 },
        UniverseIds = {},
        TagPrefix = "B0XazPrisonFight",

        -- IsGun marks real guns so the macro (via WeaponMods:IsGunTool) can detect them in
        -- the backpack or hands. No pickups or spawns: givers are not part of this adapter.
        Weapons = {
            { Id = "MP5", Name = "MP5", ToolNames = { "MP5" }, Category = "SMG", IsGun = true },
            { Id = "Remington870", Name = "Remington 870", ToolNames = { "Remington 870" }, Category = "Shotgun", IsGun = true },
            { Id = "AK47", Name = "AK-47", ToolNames = { "AK-47" }, Category = "Rifle", IsGun = true },
            { Id = "Taser", Name = "Taser", ToolNames = { "Taser" }, Category = "Special" },
        },

        -- Gun states live as a GunStates ModuleScript and/or instance attributes; the macro
        -- detector uses the module name to flag unknown-but-real guns from map updates.
        GunMods = {
            ModuleName = "GunStates",
            ModuleFields = { "Spread", "FireRate", "AutoFire", "Range" },
            Attributes = { "SpreadRadius", "FireRate", "AutoFire", "Range" },
        },

        -- Same obstacle containers as the source map; matched case-insensitively against
        -- workspace children. Everything inside them is phaseable.
        Doors = {
            Folders = { "doors", "glass", "celldoors", "prison_fences", "prison_gate" },
            NamePatterns = { "door", "gate", "cell", "fence", "glass" },
        },

        Macro = {
            MinGuns = 3, -- the macro cycles all three ranged public guns (MP5, Remington 870, AK-47)
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
