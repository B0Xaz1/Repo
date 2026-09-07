--!nonstrict
return function(services: any): any
    local dom, theme, state = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("StateStore")
    local section = services:Get("Require")("src/UI/Components/Section.luau", services)
    local Dropdown = {}
    function Dropdown:Create(parent: Instance, label: string, defaultOrPath: any, options: { any }, callback: any?, requiredTier: number?): any
        local row, text, owner = section:Control(parent, label, 38)
        text.Size = UDim2.new(0.47, -5, 0, 38)
        local button = dom:Create("TextButton", { Parent = row, BorderSizePixel = 0, Position = UDim2.new(0.47, 0, 0, 4), Size = UDim2.new(0.53, 0, 0, 30),
            Text = "", TextTruncate = Enum.TextTruncate.AtEnd, Font = Enum.Font.Gotham, TextSize = 11 })
        section:StyleButton(button, owner)
        local menu = dom:Create("ScrollingFrame", { Parent = row, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 0),
            Visible = false, ScrollBarThickness = 3, CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y })
        theme:BindToken(menu, "BackgroundColor3", "Elem")
        dom:Create("UICorner", { Parent = menu, CornerRadius = UDim.new(0, 6) })
        dom:CreatePadding(menu, 4)
        dom:Create("UIListLayout", { Parent = menu, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
        local handle: any = { Row = row, Label = text, Scope = owner, _options = table.clone(options), _open = false }
        handle.Normalize = function(value: any): any return if table.find(handle._options, value) then value else handle._options[1] end
        local function close() handle._open = false; menu.Visible = false; row.Size = UDim2.new(1, 0, 0, 38) end
        function handle:_Render(value: any, locked: boolean)
            text.Text = label .. (if locked then "  [locked]" else "")
            button.Text = tostring(value or "No options") .. "  ▾"
        end
        function handle:Refresh(nextOptions: { any }, preserveSelection: boolean?)
            close()
            self._options = table.clone(nextOptions)
            owner:Unbind("Options")
            for _, child in ipairs(menu:GetChildren()) do if child:IsA("GuiObject") then dom:DestroyInstance(child) end end
            local optionScope = owner:CreateChild("Options")
            owner:Bind("Options", optionScope)
            for index, option in ipairs(self._options) do
                local choice = dom:Create("TextButton", { Parent = menu, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = index,
                    Text = tostring(option), TextSize = 11, Font = Enum.Font.Gotham })
                section:StyleButton(choice, optionScope)
                optionScope:Connect(choice.Activated, function() if handle:Set(option) then close() end end)
            end
            menu.Size = UDim2.new(1, 0, 0, math.min(7, #self._options) * 28 + 8)
            local selection = if preserveSelection then self:Get() else nil
            local nextValue = self.Normalize(selection)
            if nextValue ~= nil then
                if self.Path then self:Set(nextValue, not state:HasPermission(self.Path)) else self:Set(nextValue, true) end
            else self:Set(nil, true) end
        end
        section:Bind(handle, defaultOrPath, callback, requiredTier)
        handle:Refresh(options, true)
        if handle.Path then owner:Add(state:Observe(handle.Path, function(value: any)
            if not table.find(handle._options, value) and handle._options[1] ~= nil and state:HasPermission(handle.Path) then handle:Set(handle._options[1]) end
        end)) end
        owner:Connect(button.Activated, function()
            if handle._open then close(); return end
            services:Get("UIEngine"):CloseAllDropdownsExcept(close)
            handle._open, menu.Visible = true, true
            row.Size = UDim2.new(1, 0, 0, 40 + menu.Size.Y.Offset + 4)
        end)
        owner:Add(services:Get("UIEngine"):RegisterDropdownClose(close))
        return handle
    end
    return setmetatable(Dropdown, { __call = function(_constructor: any, ...: any) return Dropdown:Create(...) end })
end
