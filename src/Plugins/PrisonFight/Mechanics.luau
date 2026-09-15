--!nonstrict
-- Prison Fight plugin orchestrator. The game is a Prison Life fan fork on the same map and
-- models; this adapter intentionally exposes only two Prison Life subsystems: door phasing
-- (WorldPhase) and the weapon switch macro (MacroService). WeaponMods stays loaded solely
-- for its IsGunTool detection, which the macro relies on.
--
-- Service layout (modules shared from the Prison Life adapter):
--   Manifest        frozen game data (guns for detection, obstacle containers) - this plugin
--   WorldPhase      obstacle phasing (doors, glass, cells, fences, gates)
--   WeaponMods      gun detection only; no tuning controls are mounted here
--   MacroService    gun switch macro state machine
--   PrisonFightUI   the Game tab sections
return function(services: any): any
    local load = services:Get("Require")
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")

    local manifest = load("src/Plugins/PrisonFight/Manifest.luau", services)
    local scope = services:Get("Disposer"):CreateChild("Plugin " .. manifest.Name)

    -- Shared registry handed to every service factory. Cross-service references resolve
    -- lazily through this table, so construction order never matters.
    local Prison = { Name = manifest.Name, Services = services, Manifest = manifest, Scope = scope }
    local function use(name: string): any
        return load("src/Plugins/PrisonLife/" .. name .. ".luau", services, Prison)
    end

    Prison.WorldPhase = use("WorldPhase")
    Prison.WeaponMods = use("WeaponMods")
    Prison.Macro = use("MacroService")
    Prison.UI = load("src/Plugins/PrisonFight/PrisonFightUI.luau", services, Prison)

    -- Services stays public so tooling can introspect the live registry.
    local Plugin = { Name = manifest.Name, Services = Prison, _initialized = false }

    function Plugin:Initialize(_container: any)
        if self._initialized then return end
        self._initialized = true

        -- Only what this adapter drives: phasing and the macro.
        local defaults: any = {
            DoorPhase = false, PhaseTransparency = 0.65,
            FakeMacro = false, FakeMacroKey = Enum.KeyCode.X, FakeMacroMode = "Toggle", FakeMacroDelay = 0.03,
            StopAutomationOnRespawn = true,
        }
        for path, value in pairs(defaults) do
            if StateStore:Get("Game." .. path) == nil then StateStore:Set("Game." .. path, value) end
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
        -- Reverse of Initialize; every service restores everything it owns.
        Prison.Macro:Stop("plugin destroyed")
        Prison.WorldPhase:Destroy()
        Prison.WeaponMods:Destroy()
        Prison.UI:Destroy()
        scope:Dispose()
    end

    return Plugin
end
