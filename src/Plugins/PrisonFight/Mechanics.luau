--!nonstrict
-- Prison Fight plugin orchestrator. The game is a Prison Life fan fork on the same map and
-- models, so the plugin reuses the manifest-driven Prison Life services directly: every
-- subsystem reads its data from the Prison table's manifest, keeping construction order
-- irrelevant and behavior identical in shape to the Prison Life command center.
--
-- Service layout (modules shared from the Prison Life adapter):
--   Manifest           frozen game data (weapons, locations, obstacle folders) - this plugin
--   LocationService    tag+name discovery, waypoints, favorites, teleports
--   ArmoryService      inventory and the game's pickup flow
--   WeaponMods         gun stat tuning (attributes + GunStates) with immediate restore
--   WorldPhase         obstacle phasing (doors, glass, cells, fences, gates)
--   MacroService       gun switch macro state machine
--   PrisonLifeUI       the Game tab sections
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

    Prison.Locations = use("LocationService")
    Prison.Armory = use("ArmoryService")
    Prison.WeaponMods = use("WeaponMods")
    Prison.WorldPhase = use("WorldPhase")
    Prison.Macro = use("MacroService")
    Prison.UI = use("PrisonLifeUI")

    -- Services stays public so tooling can introspect the live registry.
    local Plugin = { Name = manifest.Name, Services = Prison, _initialized = false }

    function Plugin:Initialize(_container: any)
        if self._initialized then return end
        self._initialized = true

        -- Explicit defaults instead of values created only when a control is touched.
        local defaults: any = {
            NoSpread = false, FastFire = false, ForceAuto = false, ForceRange = false,
            FastFireDelay = 0.001, ForceRangeValue = 10000,
            DoorPhase = false, PhaseTransparency = 0.65,
            FakeMacro = false, FakeMacroKey = Enum.KeyCode.X, FakeMacroMode = "Toggle", FakeMacroDelay = 0.03,
            FavoriteLocations = {},
            StopAutomationOnRespawn = true,
        }
        for path, value in pairs(defaults) do
            if StateStore:Get("Game." .. path) == nil then StateStore:Set("Game." .. path, value) end
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
        -- Reverse of Initialize; every service restores everything it owns.
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
