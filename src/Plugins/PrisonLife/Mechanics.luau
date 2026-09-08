--!nonstrict
-- Prison Life plugin orchestrator. Every subsystem lives in its own service module; this
-- file only wires them together, starts them, builds the Game tab, and tears everything
-- down in reverse order.
--
-- Service layout (see the design brief):
--   Manifest          frozen game data (roles, weapons, locations, routes, doors)
--   ContextService    role / team / alive / equipped / nearest tracking
--   LocationService   tag+name discovery, waypoints, favorites, route runner
--   ArmoryService     inventory, pickups, loadouts
--   WeaponMods        GunStates profiles with immediate restore
--   WorldPhase        doors / fences / gates phasing + glow
--   MeleeService      punch aura + burst punching behind an isolated remote
--   MacroService      weapon switch macro state machine
--   PlayerWatchService role-grouped players, threats, ESP/filter bridges
--   DiagnosticsService status, counters, restore-all
--   PrisonLifeUI      the ten Game tab sections
return function(services: any): any
    local load = services:Get("Require")
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local Environment = services:Get("Environment")
    local UserInputService = game:GetService("UserInputService")

    local manifest = load("src/Plugins/PrisonLife/Manifest.luau", services)
    local scope = services:Get("Disposer"):CreateChild("Plugin PrisonLife")

    -- Shared registry handed to every service factory. Cross-service references resolve
    -- lazily through this table, so construction order never matters.
    local Prison = { Name = manifest.Name, Services = services, Manifest = manifest, Scope = scope }
    local function use(name: string): any
        return load("src/Plugins/PrisonLife/" .. name .. ".luau", services, Prison)
    end

    Prison.Context = use("ContextService")
    Prison.Locations = use("LocationService")
    Prison.Armory = use("ArmoryService")
    Prison.WeaponMods = use("WeaponMods")
    Prison.WorldPhase = use("WorldPhase")
    Prison.Melee = use("MeleeService")
    Prison.Macro = use("MacroService")
    Prison.PlayerWatch = use("PlayerWatchService")
    Prison.Diagnostics = use("DiagnosticsService")
    Prison.UI = use("PrisonLifeUI")

    -- One panic key stops the macro, the route runner, and the melee loop at once.
    function Prison.StopAllAutomation(reason: string)
        if Prison.Macro then Prison.Macro:Stop(reason) end
        if Prison.Locations then Prison.Locations:StopRoute(reason) end
        if Prison.Melee then Prison.Melee:StopLoop() end
        EventBus:Publish("Notify", "Prison Life", "Automation stopped: " .. tostring(reason))
    end

    -- Services stays public so diagnostics and tooling can introspect the live registry.
    local Plugin = { Name = manifest.Name, Services = Prison, _initialized = false }

    function Plugin:Initialize(_container: any)
        if self._initialized then return end
        self._initialized = true

        -- Explicit defaults instead of values created only when a control is touched.
        local defaults: any = {
            WeaponProfile = "Default",
            NoSpread = false, FastFire = false, ForceAuto = false, ForceRange = false,
            FastFireDelay = 0.05, ForceRangeValue = 2500,
            DoorPhase = false, DoorGlow = false, PhaseTransparency = 0.65,
            DoorIncludeCells = true, DoorIncludeFences = false, DoorIncludeGates = false,
            DoorIncludeGlass = false, DoorIgnoreDecorative = true,
            FakeMacro = false, FakeMacroKey = Enum.KeyCode.X, FakeMacroMode = "Toggle", FakeMacroDelay = 0.06,
            PunchAura = false, PunchAuraRange = 15, SuperPunch = false, SuperPunchHits = 10,
            MeleeTargetRole = "Any", MeleePriority = "Nearest", MeleeMaxPerSecond = 10,
            MeleeTeamCheck = true, MeleeFriendCheck = true, MeleeWhitelistCheck = true,
            MeleeForceFieldCheck = true, MeleeLOS = false,
            RoleMode = "Auto", TargetRole = "Any", RoleAware = true, SessionOverlay = true,
            IgnoreSameRole = false, IgnoreGuards = false, IgnorePrisoners = false, IgnoreCriminals = false,
            RoleColoredESP = false, RoleColoredChams = false,
            NearestLocation = "Auto", SelectedRoute = "None", RouteDelay = 1.5,
            StopAutomationOnDeath = true, StopAutomationOnRespawn = true,
            WatchAlerts = false, FavoriteLocations = {}, PanicKey = Enum.KeyCode.Unknown,
        }
        for path, value in pairs(defaults) do
            if StateStore:Get("Game." .. path) == nil then StateStore:Set("Game." .. path, value) end
        end

        Prison.Context:Initialize()
        Prison.Locations:Initialize()
        Prison.Armory:Initialize()
        Prison.WorldPhase:Initialize()
        Prison.WeaponMods:Initialize()
        Prison.Melee:Initialize()
        Prison.Macro:Initialize()
        Prison.PlayerWatch:Initialize()
        Prison.Diagnostics:Initialize()

        scope:Add(scope:Connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
            if processed or UserInputService:GetFocusedTextBox() or StateStore:GetTransient("IsBindingKey") then return end
            if Environment:MatchesInput(input, StateStore:Get("Game.PanicKey")) then
                Prison.StopAllAutomation("panic key")
            end
        end))

        EventBus:Publish("Notify", "Prison Life", "Command center ready. Role, armory, routes, and diagnostics are live.")
    end

    function Plugin:BuildUI(tab: any)
        Prison.UI:Build(tab)
    end

    function Plugin:Destroy()
        -- Reverse of Initialize; every service restores everything it owns.
        Prison.Macro:Stop("plugin destroyed")
        Prison.PlayerWatch:Destroy()
        Prison.Melee:Destroy()
        Prison.WorldPhase:Destroy()
        Prison.WeaponMods:Destroy()
        Prison.Armory:Destroy()
        Prison.Locations:Destroy()
        Prison.Context:Destroy()
        Prison.Diagnostics:Destroy()
        Prison.UI:Destroy()
        StateStore:SetTransient("PrisonRole", nil)
        StateStore:SetTransient("PrisonTeamName", nil)
        scope:Dispose()
    end

    return Plugin
end
