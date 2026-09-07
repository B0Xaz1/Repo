--!nonstrict
export type Registration = { Name: string, PluginModule: string, Description: string }
local REGISTRY: { [number]: Registration } = {
    -- Add one place OR universe entry here after verifying its manifest in your own test place:
    -- [123456789] = { Name = "Example Game", PluginModule = "src/Plugins/ExampleGame/Mechanics.luau", Description = "Opt-in test-place mechanics" },
}
return function(_services: any?): any
    local PluginRegistry = {}
    function PluginRegistry:Resolve(placeId: number, universeId: number): Registration?
        local registration = REGISTRY[placeId] or REGISTRY[universeId]
        return if registration then table.clone(registration) else nil
    end
    return PluginRegistry
end
