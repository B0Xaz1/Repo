--!nonstrict
return function(services: any): any
    local dom, theme, state = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("StateStore")
    local section = services:Get("Require")("src/UI/Components/Section.luau", services)
    local Dropdown = {}
    function Dropdown:Create(parent: Instance, label: string, defaultOrPath: any, options: { any }, callback: any?): any
        local row, text, owner = section:Control(parent, label, 46)
        text.Size, text.Position = UDim2.new(1, 0, 0, 16), UDim2.fromOffset(0, 0)
        local button = dom:Create("TextButton", { Parent = row, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 26),
            Text = "", TextTruncate = Enum.TextTruncate.AtEnd, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left })
        section:StyleButton(button, owner)
        dom:CreatePadding(button, 0, 0, 0, 10)
        local chevron = dom:Create("TextLabel", { Parent = button, BackgroundTransparency = 1, Position = UDim2.new(1, -18, 0, 0), Size = UDim2.fromOffset(16, 26),
            Text = "▾", Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center })
        theme:BindToken(chevron, "TextColor3", "TextMuted")
        local menu = dom:Create("ScrollingFrame", { Parent = row, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 0),
            Visible = false, ScrollBarThickness = 3, CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y })
        theme:BindToken(menu, "BackgroundColor3", "Elem")
        theme:BindToken(menu, "ScrollBarImageColor3", "Accent")
        dom:Create("UICorner", { Parent = menu, CornerRadius = UDim.new(0, 4) })
        dom:CreatePadding(menu, 4)
        dom:Create("UIListLayout", { Parent = menu, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
        local handle: any = { Row = row, Label = text, Scope = owner, _options = table.clone(options), _open = false }
        handle.Normalize = function(value: any): any return if table.find(handle._options, value) then value else handle._options[1] end
        local function close() handle._open = false; menu.Visible = false; row.Size = UDim2.new(1, 0, 0, 46) end
        function handle:_Render(value: any)
            text.Text = label
            button.Text = tostring(value or "No options")
        end
        function handle:Refresh(nextOptions: { any }, preserveSelection: boolean?)
            close()
            self._options = table.clone(nextOptions)
            owner:Unbind("Options")
            for _, child in ipairs(menu:GetChildren()) do if child:IsA("GuiObject") then dom:DestroyInstance(child) end end
            local optionScope = owner:CreateChild("Options")
            owner:Bind("Options", optionScope)
            for index, option in ipairs(self._options) do
                local choice = dom:Create("TextButton", { Parent = menu, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = index,
                    Text = tostring(option), TextSize = 12, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left })
                section:StyleButton(choice, optionScope)
                optionScope:Connect(choice.Activated, function() if handle:Set(option) then close() end end)
            end
            menu.Size = UDim2.new(1, 0, 0, math.min(7, #self._options) * 26 + 8)
            local selection = if preserveSelection then self:Get() else nil
            local nextValue = self.Normalize(selection)
            if nextValue ~= nil then
                if self.Path then self:Set(nextValue) else self:Set(nextValue, true) end
            else self:Set(nil, true) end
        end
        section:Bind(handle, defaultOrPath, callback)
        handle:Refresh(options, true)
        if handle.Path then owner:Add(state:Observe(handle.Path, function(value: any)
            if not table.find(handle._options, value) and handle._options[1] ~= nil then handle:Set(handle._options[1]) end
        end)) end
        owner:Connect(button.Activated, function()
            if handle._open then close(); return end
            services:Get("UIEngine"):CloseAllDropdownsExcept(close)
            handle._open, menu.Visible = true, true
            row.Size = UDim2.new(1, 0, 0, 48 + menu.Size.Y.Offset + 4)
        end)
        owner:Add(services:Get("UIEngine"):RegisterDropdownClose(close))
        return handle
    end
    return setmetatable(Dropdown, { __call = function(_constructor: any, ...: any) return Dropdown:Create(...) end })
end
