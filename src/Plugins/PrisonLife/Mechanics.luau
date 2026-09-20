local CONFIG = table.freeze({
    DEFAULT_GAME_SETTINGS = {
        NoSpread = false, FastFire = false, ForceAuto = false, ForceRange = false,
        FastFireDelay = 0.001, ForceRangeValue = 10000,
        DoorPhase = false, PhaseTransparency = 0.65,
        FakeMacro = false, FakeMacroKey = Enum.KeyCode.X, FakeMacroMode = "Toggle", FakeMacroDelay = 0.03,
        FavoriteLocations = {},
        StopAutomationOnRespawn = true,
    },
})

return function(services: any): any
    local load = services:Get("Require")
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local manifest = load("src/Plugins/PrisonLife/Manifest.luau", services)
    local scope = services:Get("Disposer"):CreateChild(`Plugin {manifest.Name}`)

    local Prison = { Name = manifest.Name, Services = services, Manifest = manifest, Scope = scope }
    local function use(name: string): any
        return load(`src/Plugins/PrisonLife/{name}.luau`, services, Prison)
    end

    Prison.Locations = use("LocationService")
    Prison.Armory = use("ArmoryService")
    Prison.WeaponMods = use("WeaponMods")
    Prison.WorldPhase = use("WorldPhase")
    Prison.Macro = use("MacroService")
    Prison.UI = use("PrisonLifeUI")

    local Plugin = { Name = manifest.Name, Services = Prison, _initialized = false }

    function Plugin:Initialize(_container: any)
        if self._initialized then return end
        self._initialized = true

        for path, value in pairs(CONFIG.DEFAULT_GAME_SETTINGS) do
            if StateStore:Get(`Game.{path}`) == nil then StateStore:Set(`Game.{path}`, value) end
        end

        Prison.Locations:Initialize()
        Prison.Armory:Initialize()
        Prison.WorldPhase:Initialize()
        Prison.WeaponMods:Initialize()
        Prison.Macro:Initialize()

        EventBus:Publish("Notify", manifest.Name, "Command center ready. Armory, doors, macro, and teleports are live.")
    end

    function Plugin:BuildUI(tab: any)
        Prison.UI:Build(tab)
    end

    function Plugin:Destroy()
        Prison.Macro:Stop("plugin destroyed")
        Prison.WorldPhase:Destroy()
        Prison.WeaponMods:Destroy()
        Prison.Armory:Destroy()
        Prison.Locations:Destroy()
        Prison.UI:Destroy()
        scope:Dispose()
    end

    return Plugin
end
