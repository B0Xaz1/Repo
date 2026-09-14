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
    -- Prison Fight is a Prison Life fan fork on the same map and models; its adapter
    -- deliberately exposes only door phasing and the weapon switch macro from that stack.
    [135787580685512] = {
        Name = "Prison Fight",
        PluginModule = "src/Plugins/PrisonFight/Mechanics.luau",
        Description = "Prison Fight adapter: door phasing and the weapon switch macro on the shared prison map",
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
    -- Lists every registered adapter for manual selection; each clone carries the id it
    -- resolved under so the picker can display and re-select stably.
    function PluginRegistry:GetRegistrations(): { Registration }
        local list = {}
        for id, registration in pairs(REGISTRY) do
            local entry = table.clone(registration)
            entry.Id = id
            table.insert(list, entry)
        end
        table.sort(list, function(a: any, b: any) return a.Name < b.Name end)
        return list
    end
    return PluginRegistry
end
