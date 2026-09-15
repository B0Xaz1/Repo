--!nonstrict
-- Murderers VS Sheriffs DUELS plugin orchestrator. Ported from the reference "gamesense"
-- script: match-scoped enemy targeting shared by a pooled ESP overlay and two remote
-- combat drivers (knife killer, fast aim revolver). The standalone script's own window is
-- not recreated; controls live in the suite Game tab, and the Insert hotkey / standalone
-- state attributes are unnecessary because the suite owns display and state.
--
-- Service layout:
--   Manifest        frozen game data (match scope, remotes, timings) - this plugin
--   TargetService   enemy filtering and the nearest-first engagement list
--   EspService      pooled 2D box / health bar / name overlay
--   AttackService   knife and revolver remote drivers
--   MvSUI           the Game tab sections
return function(services: any): any
    local load = services:Get("Require")
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")

    local manifest = load("src/Plugins/MurderersVsSheriffs/Manifest.luau", services)
    local scope = services:Get("Disposer"):CreateChild("Plugin " .. manifest.Name)

    -- Shared registry handed to every service factory. Cross-service references resolve
    -- lazily through this table, so construction order never matters.
    local Duel = { Name = manifest.Name, Services = services, Manifest = manifest, Scope = scope }
    local function use(name: string): any
        return load("src/Plugins/MurderersVsSheriffs/" .. name .. ".luau", services, Duel)
    end

    Duel.Targets = use("TargetService")
    Duel.Esp = use("EspService")
    Duel.Attack = use("AttackService")
    Duel.UI = load("src/Plugins/MurderersVsSheriffs/MvSUI.luau", services, Duel)

    -- Services stays public so tooling can introspect the live registry.
    local Plugin = { Name = manifest.Name, Services = Duel, _initialized = false }

    function Plugin:Initialize(_container: any)
        if self._initialized then return end
        self._initialized = true

        -- Everything starts off; the user flips drivers on from the Game tab.
        local defaults: any = {
            MvSEsp = false,
            MvSKnife = false, MvSKnifeCooldown = manifest.Knife.DefaultCooldown,
            MvSRevolver = false, MvSGunCooldown = manifest.Gun.DefaultCooldown,
        }
        for path, value in pairs(defaults) do
            if StateStore:Get("Game." .. path) == nil then StateStore:Set("Game." .. path, value) end
        end

        Duel.Esp:Initialize()
        Duel.Attack:Initialize()

        EventBus:Publish("Notify", manifest.Name, "Command center ready. ESP and combat drivers are off until you enable them.")
    end

    function Plugin:BuildUI(tab: any)
        Duel.UI:Build(tab)
    end

    function Plugin:Destroy()
        -- Reverse of Initialize; every service restores everything it owns.
        Duel.Attack:Destroy()
        Duel.Esp:Destroy()
        Duel.UI:Destroy()
        scope:Dispose()
    end

    return Plugin
end
