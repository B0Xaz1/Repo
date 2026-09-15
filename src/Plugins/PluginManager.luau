--!nonstrict
export type IGamePlugin = {
    Name: string, Initialize: (IGamePlugin, any) -> (), BuildUI: (IGamePlugin, any) -> (), Destroy: (IGamePlugin) -> (),
}
return function(services: any): any
    local load = services:Get("Require")
    local bus = services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("PluginManager")
    local registry = load("src/Plugins/PluginRegistry.luau", services)
    local PluginManager = { _match = nil, _manual = nil, _active = nil, _activeOwner = nil, _mount = nil, _lastError = nil, _initialized = false }

    -- Automatic resolution reads the live place; a manual selection from the Game tab
    -- overrides it for the rest of the session until reset to automatic.
    local function resolvedMatch(): any
        return PluginManager._manual or registry:Resolve(game.PlaceId, game.GameId)
    end

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
        if not PluginManager._active then
            local section = load("src/UI/Components/Section.luau", services)
            local dropdown = load("src/UI/Components/Dropdown.luau", services)
            local textbox = load("src/UI/Components/Textbox.luau", services)
            local panel = section:Create(tab.LeftCol, "Universal mode")
            section:Info(panel, if resolvedMatch() then "The matching game plugin is available for this place or universe." else "No plugin is registered for this place or universe. Universal tools remain available.")
            if PluginManager._lastError then
                section:Info(panel, "Last adapter error: " .. PluginManager._lastError)
            end
            -- Manual override: any registered adapter can be force-mounted onto this game.
            local registrations = registry:GetRegistrations()
            if #registrations > 0 then
                local names, byName = {}, {}
                for index, registration in ipairs(registrations) do
                    names[index] = registration.Name
                    byName[registration.Name] = registration
                end
                local picker = dropdown(panel, "Force plugin", nil, names)
                textbox:CreateButton(panel, "Use selected plugin", function()
                    return PluginManager:SelectPlugin(byName[picker:Get()])
                end)
                section:Info(panel, "Runs the chosen adapter against this game even without a registered id. Map data may not line up; verify features before relying on them.")
            end
            return
        end
        if PluginManager._manual then
            local section = load("src/UI/Components/Section.luau", services)
            local textbox = load("src/UI/Components/Textbox.luau", services)
            local panel = section:Create(tab.LeftCol, "Plugin override")
            section:Info(panel, "Force-mounted adapter: " .. PluginManager._manual.Name .. " (manual selection overrides automatic resolution)")
            textbox:CreateButton(panel, "Return to automatic", function()
                return PluginManager:SelectPlugin(nil)
            end)
        end
        -- A plugin UI failure must never take the whole suite down; surface it instead.
        local ok, err = pcall(function() PluginManager._active:BuildUI(tab) end)
        if ok then
            PluginManager._lastError = nil
            return
        end
        PluginManager._lastError = tostring(err)
        warn("[B0Xaz][PluginManager] UI mount failed: " .. PluginManager._lastError)
        bus:Publish("PluginError", PluginManager._active.Name, PluginManager._lastError)
        bus:Publish("Notify", "Plugin UI failed", PluginManager._lastError)
        local section = load("src/UI/Components/Section.luau", services)
        local panel = section:Create(tab.LeftCol, "Plugin error")
        section:Info(panel, PluginManager._active.Name .. " could not build its Game tab: " .. PluginManager._lastError)
    end
    local function deactivate()
        local owner = PluginManager._activeOwner
        PluginManager._active, PluginManager._activeOwner = nil, nil
        if owner then owner:Dispose() end
    end
    local function activate()
        if scope:IsDisposed() or PluginManager._active then return end
        local match = resolvedMatch()
        if not match then return end
        local owner = scope:CreateChild("Active plugin")
        PluginManager._activeOwner = owner
        local pluginServices = setmetatable({ Version = services.Version }, { __index = services })
        function pluginServices:Get(name: string): any
            return if name == "Disposer" then owner else services:Get(name)
        end
        local ok, plugin = pcall(function()
            -- The factory stays cached while each activation receives an isolated instance and disposer.
            local factory = load(match.PluginModule)
            local instance = factory(pluginServices)
            assert(type(instance) == "table" and type(instance.Initialize) == "function" and type(instance.Destroy) == "function", "Invalid plugin contract")
            PluginManager._active = instance
            owner:Bind("Plugin", instance, "Destroy")
            instance:Initialize(pluginServices)
            return instance
        end)
        -- The owner exists before the factory runs, so even a half-constructed plugin is reversible.
        if not ok then
            PluginManager._lastError = tostring(plugin)
            deactivate()
            bus:Publish("PluginError", if match then match.Name else "Plugin", PluginManager._lastError)
            bus:Publish("Notify", "Plugin failed", PluginManager._lastError)
        end
    end
    function PluginManager:IsGameSupported(): boolean return resolvedMatch() ~= nil end
    function PluginManager:IsManualOverride(): boolean return self._manual ~= nil end
    function PluginManager:GetActivePluginName(): string
        local match = resolvedMatch()
        return if self._active then self._active.Name else if match then match.Name else "Universal Mode"
    end
    -- Diagnostics surfaces the last activation or mount error instead of swallowing it.
    function PluginManager:GetLastError(): string? return self._lastError end
    function PluginManager:ListPlugins(): { any } return registry:GetRegistrations() end
    -- Nil registration drops the manual override and falls back to automatic resolution.
    function PluginManager:SelectPlugin(registration: any): (boolean, string)
        self._manual = registration
        self._lastError = nil
        deactivate()
        PluginManager._match = resolvedMatch()
        activate()
        refreshMount()
        bus:Publish("PluginChanged", PluginManager:GetActivePluginName())
        if self._active then
            return true, (if registration then "Force-mounted " else "Activated ") .. self._active.Name
        end
        return false, self._lastError or "No adapter is active"
    end
    function PluginManager:MountUI(tab: any): (boolean, string?)
        local dom = services:Get("DOM")
        self._mount = table.clone(tab)
        for _, side in ipairs({ "LeftCol", "RightCol" }) do
            local column = dom:Create("Frame", { Parent = tab[side], BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 50 })
            dom:Create("UIListLayout", { Parent = column, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder })
            self._mount[side] = column
        end
        refreshMount()
        return self._lastError == nil, self._lastError
    end
    function PluginManager:Initialize()
        if self._initialized then return end
        self._initialized = true
        PluginManager._match = resolvedMatch()
        activate()
        bus:Publish("PluginChanged", PluginManager:GetActivePluginName())
    end
    function PluginManager:Destroy() scope:Dispose() end
    scope:Add(deactivate)
    return PluginManager
end
