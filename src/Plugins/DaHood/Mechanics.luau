return function(services: any): any
    local StateStore = services:Get("StateStore")
    local EventBus = services:Get("EventBus")
    local manifest = services:Get("Require")("src/Plugins/DaHood/Manifest.luau", services)
    local scope = services:Get("Disposer"):CreateChild(`Plugin {manifest.Name}`)

    local DaHood = { Name = manifest.Name, Services = services, Manifest = manifest, Scope = scope }
    local Plugin = { Name = manifest.Name, Services = DaHood, _initialized = false }

    local DEFAULT_GAME_SETTINGS = {
        -- Intentionally left blank for future configuration.
    }

    function Plugin:Initialize(_container: any)
        if self._initialized then return end
        self._initialized = true

        for path, value in pairs(DEFAULT_GAME_SETTINGS) do
            if StateStore:Get(`Game.{path}`) == nil then StateStore:Set(`Game.{path}`, value) end
        end

        EventBus:Publish("Notify", manifest.Name, "Plugin loaded. Add your Da Hood features here.")
    end

    function Plugin:BuildUI(_tab: any)
        -- Reserved for later UI configuration.
    end

    function Plugin:Destroy()
        scope:Dispose()
    end

    return Plugin
end
