--!strict

return function(services: any): any
    local load = services:Get("Require")
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local manifest = load("src/Plugins/ZombieAttack/Manifest.luau", services)
    local scope = services:Get("Disposer"):CreateChild(`Plugin {manifest.Name}`)
    local CONFIG = table.freeze({
        DEFAULT_GAME_SETTINGS = {
            ZombieAura = false,
            ZombieAuraRate = manifest.Aura.DefaultRate,
            ZombieAuraPart = manifest.Aim.Parts[1],
            ZombieAuraRange = manifest.Aura.DefaultRange,
        },
    })

    local Aura = { Name = manifest.Name, Services = services, Manifest = manifest, Scope = scope }
    local function use(name: string): any
        return load(`src/Plugins/ZombieAttack/{name}.luau`, services, Aura)
    end

    Aura.Targets = use("TargetService")
    Aura.KillAura = use("KillAuraService")
    Aura.UI = load("src/Plugins/ZombieAttack/ZombieAttackUI.luau", services, Aura)

    local Plugin = { Name = manifest.Name, Services = Aura, _initialized = false }

    function Plugin:Initialize(_container: any)
        if self._initialized then return end
        self._initialized = true

        for path, value in pairs(CONFIG.DEFAULT_GAME_SETTINGS) do
            if StateStore:Get(`Game.{path}`) == nil then StateStore:Set(`Game.{path}`, value) end
        end

        Aura.KillAura:Initialize()

        EventBus:Publish("Notify", manifest.Name, `Command center ready. Kill aura is off until you switch it on.`)
    end

    function Plugin:BuildUI(tab: any)
        Aura.UI:Build(tab)
    end

    function Plugin:Destroy()
        StateStore:Set("Game.ZombieAura", false)
        Aura.KillAura:Destroy()
        Aura.UI:Destroy()
        scope:Dispose()
    end

    return Plugin
end
