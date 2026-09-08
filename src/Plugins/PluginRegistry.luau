--!nonstrict
export type Registration = { Name: string, PluginModule: string, Description: string }
local REGISTRY: { [number]: Registration } = {
    -- Keyed by place id OR universe id. Prison Life (by Aesthetical) resolves by its place id;
    -- add its universe id here as a second key if extra places should share the adapter.
    [155615604] = {
        Name = "Prison Life",
        PluginModule = "src/Plugins/PrisonLife/Mechanics.luau",
        Description = "Prison Life command center: roles, armory, routes, doors, macros, and diagnostics",
    },
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
