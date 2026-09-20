return function(services: any): any
    local load = services:Get("Require")
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local manifest = load("src/Plugins/PrisonFight/Manifest.luau", services)
    local scope = services:Get("Disposer"):CreateChild(`Plugin {manifest.Name}`)
    local CONFIG = table.freeze({
        DEFAULT_GAME_SETTINGS = {
            DoorPhase = false, PhaseTransparency = 0.65,
            FakeMacro = false, FakeMacroKey = Enum.KeyCode.X, FakeMacroMode = "Toggle", FakeMacroDelay = 0.03,
            StopAutomationOnRespawn = true,
        },
    })

    local Prison = { Name = manifest.Name, Services = services, Manifest = manifest, Scope = scope }
    local function use(name: string): any
        return load(`src/Plugins/PrisonLife/{name}.luau`, services, Prison)
    end

    Prison.WorldPhase = use("WorldPhase")
    Prison.WeaponMods = use("WeaponMods")
    Prison.Macro = use("MacroService")
    Prison.UI = load("src/Plugins/PrisonFight/PrisonFightUI.luau", services, Prison)

    local Plugin = { Name = manifest.Name, Services = Prison, _initialized = false }

    function Plugin:Initialize(_container: any)
        if self._initialized then return end
        self._initialized = true

        for path, value in pairs(CONFIG.DEFAULT_GAME_SETTINGS) do
            if StateStore:Get(`Game.{path}`) == nil then StateStore:Set(`Game.{path}`, value) end
        end

        Prison.WorldPhase:Initialize()
        Prison.WeaponMods:Initialize()
        Prison.Macro:Initialize()

        EventBus:Publish("Notify", manifest.Name, "Command center ready. Door phasing and the weapon macro are live.")
    end

    function Plugin:BuildUI(tab: any)
        Prison.UI:Build(tab)
    end

    function Plugin:Destroy()
        Prison.Macro:Stop("plugin destroyed")
        Prison.WorldPhase:Destroy()
        Prison.WeaponMods:Destroy()
        Prison.UI:Destroy()
        scope:Dispose()
    end

    return Plugin
end
