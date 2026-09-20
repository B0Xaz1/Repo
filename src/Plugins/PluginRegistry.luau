export type Registration = {
    Name: string,
    PluginModule: string,
    Description: string,
    PlaceIds: { number },
    UniverseIds: { number },
}

local CONFIG = table.freeze({
    REGISTRATIONS = {
        {
            Name = "Prison Life",
            PluginModule = "src/Plugins/PrisonLife/Mechanics.luau",
            Description = "Prison Life command center: roles, armory, routes, doors, macros, and diagnostics",
            PlaceIds = { 155615604 }, UniverseIds = {},
        },
        {
            Name = "Prison Fight",
            PluginModule = "src/Plugins/PrisonFight/Mechanics.luau",
            Description = "Prison Fight adapter: door phasing and the weapon switch macro on the shared prison map",
            PlaceIds = { 135787580685512 }, UniverseIds = {},
        },
        {
            Name = "Murderers VS Sheriffs DUELS",
            PluginModule = "src/Plugins/MurderersVsSheriffs/Mechanics.luau",
            Description = "Match-scoped enemy ESP plus knife killer and fast aim revolver drivers",
            PlaceIds = { 12355337193 }, UniverseIds = { 4348829796 },
        },
        {
            -- Root and Hardmode place ids; no universe id, since it could not be confirmed
            -- without an authenticated call
            Name = "Zombie Attack",
            PluginModule = "src/Plugins/ZombieAttack/Mechanics.luau",
            Description = "Zombie Attack kill aura: rate-gated shots at the nearest live zombie through the game's own gun remote",
            PlaceIds = { 1240123653, 1632210982 }, UniverseIds = {},
        },
    },
})

local function contains(ids: { number }, value: number): boolean
    return table.find(ids, value) ~= nil
end

return function(_services: any?): any
    local PluginRegistry = {}

    function PluginRegistry:Resolve(placeId: number, universeId: number): Registration?
        for _, registration in ipairs(CONFIG.REGISTRATIONS) do
            if contains(registration.PlaceIds, placeId) or contains(registration.UniverseIds, universeId) then
                return table.clone(registration)
            end
        end
        return nil
    end

    function PluginRegistry:GetRegistrations(): { Registration }
        local list = {}
        for _, registration in ipairs(CONFIG.REGISTRATIONS) do
            table.insert(list, table.clone(registration))
        end
        table.sort(list, function(a: Registration, b: Registration): boolean return a.Name < b.Name end)
        return list
    end

    return PluginRegistry
end
