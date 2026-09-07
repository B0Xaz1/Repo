--!nonstrict
export type IGamePlugin = {
    Name: string, Initialize: (IGamePlugin, any) -> (), BuildUI: (IGamePlugin, any) -> (), Destroy: (IGamePlugin) -> (),
}
return function(services: any): any
    local load = services:Get("Require")
    local state, bus = services:Get("StateStore"), services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("PluginManager")
    local registry = load("src/Plugins/PluginRegistry.luau", services)
    local match = registry:Resolve(game.PlaceId, game.GameId)
    local PluginManager = { _match = match, _active = nil, _activeOwner = nil, _mount = nil, _initialized = false }

    local function clearMount()
        if not PluginManager._mount then return end
        local dom = services:Get("DOM")
        for _, column in ipairs({ PluginManager._mount.LeftCol, PluginManager._mount.RightCol }) do
            for _, child in ipairs(column:GetChildren()) do if child:IsA("GuiObject") then dom:DestroyInstance(child) end end
        end
    end
    local function refreshMount()
        local tab = PluginManager._mount
        if not tab then return end
        if services:Has("UIEngine") then services:Get("UIEngine"):ClearSearch() end
        clearMount()
        if PluginManager._active then PluginManager._active:BuildUI(tab) else
            local section = load("src/UI/Components/Section.luau", services)
            local panel = section:Create(tab.LeftCol, "Universal mode")
            section:Info(panel, if match then "The matching game plugin requires Full access." else "No plugin is registered for this place or universe. Universal tools remain available.")
        end
    end
    local function deactivate()
        local owner = PluginManager._activeOwner
        PluginManager._active, PluginManager._activeOwner = nil, nil
        if owner then owner:Dispose() end
    end
    local function activate()
        if scope:IsDisposed() or not match or state:GetTier() < 3 or PluginManager._active then return end
        local owner = scope:CreateChild("Active plugin")
        PluginManager._activeOwner = owner
        local pluginServices = setmetatable({ Version = services.Version }, { __index = services })
        function pluginServices:Get(name: string): any
            return if name == "Disposer" then owner else services:Get(name)
        end
        local ok, plugin = pcall(function()
            -- A tier re-upgrade gets a fresh plugin instance, while its source and compiled factory stay cached.
            local factory = load(match.PluginModule)
            local instance = factory(pluginServices)
            assert(type(instance) == "table" and type(instance.Initialize) == "function" and type(instance.Destroy) == "function", "Invalid plugin contract")
            PluginManager._active = instance
            owner:Bind("Plugin", instance, "Destroy")
            instance:Initialize(pluginServices)
            return instance
        end)
        -- The owner exists before the factory runs, so even a half-constructed plugin is reversible.
        if not ok then deactivate(); bus:Publish("Notify", "Plugin failed", tostring(plugin)) end
    end
    function PluginManager:IsGameSupported(): boolean return self._match ~= nil end
    function PluginManager:GetActivePluginName(): string return if self._active then self._active.Name else if self._match then self._match.Name else "Universal Mode" end
    function PluginManager:MountUI(tab: any)
        local dom = services:Get("DOM")
        self._mount = table.clone(tab)
        for _, side in ipairs({ "LeftCol", "RightCol" }) do
            local column = dom:Create("Frame", { Parent = tab[side], BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 50 })
            dom:Create("UIListLayout", { Parent = column, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder })
            self._mount[side] = column
        end
        refreshMount()
    end
    function PluginManager:Initialize()
        if self._initialized then return end
        self._initialized = true
        activate()
        scope:Add(bus:Subscribe("TierChanged", function()
            if state:GetTier() < 3 then deactivate() else activate() end
            refreshMount()
            bus:Publish("PluginChanged", PluginManager:GetActivePluginName())
        end))
    end
    function PluginManager:Destroy() scope:Dispose() end
    scope:Add(deactivate)
    return PluginManager
end
