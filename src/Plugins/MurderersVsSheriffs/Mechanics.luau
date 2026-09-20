return function(services: any): any
    local load = services:Get("Require")
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local manifest = load("src/Plugins/MurderersVsSheriffs/Manifest.luau", services)
    local scope = services:Get("Disposer"):CreateChild(`Plugin {manifest.Name}`)
    local CONFIG = table.freeze({
        DEFAULT_GAME_SETTINGS = {
            MvSEsp = false,
            MvSKnife = false, MvSKnifeCooldown = manifest.Knife.DefaultCooldown,
            MvSKnifeThrowSpeed = 0,
            MvSKnifeSpamThrow = false,
            MvSRevolver = false, MvSGunCooldown = manifest.Gun.DefaultCooldown,
            MvSGunAttributeCooldown = 0.0,
            MvSGunSpamShoot = false,
            MvSAutoEquip = false,
            MvSAutoQueue = false, MvSQueueMode = manifest.Queue and manifest.Queue.DefaultMode or "1v1",
            MvSQueueDelay = manifest.Queue and manifest.Queue.DefaultDelay or 3.0,
        },
    })

    local Duel = { Name = manifest.Name, Services = services, Manifest = manifest, Scope = scope }
    local function use(name: string): any
        return load(`src/Plugins/MurderersVsSheriffs/{name}.luau`, services, Duel)
    end

    Duel.Targets = use("TargetService")
    Duel.Esp = use("EspService")
    Duel.Attack = use("AttackService")
    Duel.AutoQueue = use("AutoQueueService")
    Duel.UI = load("src/Plugins/MurderersVsSheriffs/MvSUI.luau", services, Duel)

    local Plugin = { Name = manifest.Name, Services = Duel, _initialized = false }

    function Plugin:Initialize(_container: any)
        if self._initialized then return end
        self._initialized = true

        for path, value in pairs(CONFIG.DEFAULT_GAME_SETTINGS) do
            if StateStore:Get(`Game.{path}`) == nil then StateStore:Set(`Game.{path}`, value) end
        end

        Duel.Esp:Initialize()
        Duel.Attack:Initialize()
        Duel.AutoQueue:Initialize()

        EventBus:Publish("Notify", manifest.Name, "Command center ready. ESP, combat drivers, and auto-queue are ready.")
    end

    function Plugin:BuildUI(tab: any)
        Duel.UI:Build(tab)
    end

    function Plugin:Destroy()
        Duel.AutoQueue:Destroy()
        Duel.Attack:Destroy()
        Duel.Esp:Destroy()
        Duel.UI:Destroy()
        scope:Dispose()
    end

    return Plugin
end
