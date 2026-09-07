--!nonstrict
return function(services: any, tab: any): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)
    local manager = services:Get("PluginManager")
    local scope = services:Get("Disposer"):CreateChild("Game tab")
    local info = section:Create(tab.LeftCol, "Game integration")
    local active = section:Info(info, "Active adapter: " .. manager:GetActivePluginName())
    section:Info(info, "Place " .. game.PlaceId .. "  ·  Universe " .. game.GameId)
    textbox:CreateButton(info, "Copy place ID", function()
        local ok, message = services:Get("Environment"):SetClipboard(tostring(game.PlaceId))
        return ok, message or "Place ID copied"
    end, 0)
    scope:Add(services:Get("EventBus"):Subscribe("PluginChanged", function(name: string) active:Set("Active adapter: " .. name) end))
    manager:MountUI(tab)
    return { Name = tab.Name }
end
