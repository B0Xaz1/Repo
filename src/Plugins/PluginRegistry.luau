--!strict
export type Registration = { Name: string, PluginModule: string, Description: string }

local CONFIG = table.freeze({
    REGISTRY = {
    [155615604] = {
        Name = "Prison Life",
        PluginModule = "src/Plugins/PrisonLife/Mechanics.luau",
        Description = "Prison Life command center: roles, armory, routes, doors, macros, and diagnostics",
    },
    [135787580685512] = {
        Name = "Prison Fight",
        PluginModule = "src/Plugins/PrisonFight/Mechanics.luau",
        Description = "Prison Fight adapter: door phasing and the weapon switch macro on the shared prison map",
    },
    [12355337193] = {
        Name = "Murderers VS Sheriffs DUELS",
        PluginModule = "src/Plugins/MurderersVsSheriffs/Mechanics.luau",
        Description = "Match-scoped enemy ESP plus knife killer and fast aim revolver drivers",
    },
    [4348829796] = {
        Name = "Murderers VS Sheriffs DUELS",
        PluginModule = "src/Plugins/MurderersVsSheriffs/Mechanics.luau",
        Description = "Match-scoped enemy ESP plus knife killer and fast aim revolver drivers",
    },
    },
})

return function(_services: any?): any
    local PluginRegistry = {}
    function PluginRegistry:Resolve(placeId: number, universeId: number): Registration?
        local registration = CONFIG.REGISTRY[placeId] or CONFIG.REGISTRY[universeId]
        return if registration then table.clone(registration) else nil
    end
    function PluginRegistry:GetRegistrations(): { Registration }
        local list = {}
        for id, registration in pairs(CONFIG.REGISTRY) do
            local entry = table.clone(registration)
            entry.Id = id
            table.insert(list, entry)
        end
        table.sort(list, function(a: any, b: any) return a.Name < b.Name end)
        return list
    end
    return PluginRegistry
end
