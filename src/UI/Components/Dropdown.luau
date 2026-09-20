local CONFIG = table.freeze({
    CLOSED_HEIGHT = 38,
    MAX_VISIBLE_OPTIONS = 7,
    OPTION_ROW_HEIGHT = 26,
    MENU_PADDING = 8,
    OPEN_TOP_OFFSET = 40,
    OPEN_BOTTOM_OFFSET = 4,
})

return function(services: any): any
    local dom, theme, state = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("StateStore")
    local section = services:Get("Require")("src/UI/Components/Section.luau", services)
    local Dropdown = {}
    function Dropdown:Create(parent: Instance, label: string, defaultOrPath: any, options: { any }, callback: any?): any
        local row, text, owner = section:Control(parent, label, CONFIG.CLOSED_HEIGHT)
        text.Size, text.Position = UDim2.new(1, 0, 0, 14), UDim2.fromOffset(0, 0)
        local button = dom:Create("TextButton", { Parent = row, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 20),
            Text = "", TextTruncate = Enum.TextTruncate.AtEnd, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left })
        section:StyleButton(button, owner)
        dom:CreatePadding(button, 0, 0, 0, 8)
        local chevron = dom:Create("TextLabel", { Parent = button, BackgroundTransparency = 1, Position = UDim2.new(1, -16, 0, 0), Size = UDim2.fromOffset(14, 20),
            Text = "v", Font = Enum.Font.Gotham, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center })
        theme:BindToken(chevron, "TextColor3", "TextMuted")
        local menu = dom:Create("ScrollingFrame", { Parent = row, BorderSizePixel = 0, Position = UDim2.fromOffset(0, CONFIG.CLOSED_HEIGHT), Size = UDim2.new(1, 0, 0, 0),
            Visible = false, ScrollBarThickness = 3, CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y })
        theme:BindToken(menu, "BackgroundColor3", "Elem")
        theme:BindToken(menu, "ScrollBarImageColor3", "Accent")
        theme:BindToken(dom:CreateStroke(menu, theme:GetToken("BorderDim")), "Color", "BorderDim")
        dom:Create("UICorner", { Parent = menu, CornerRadius = UDim.new(0, 3) })
        dom:CreatePadding(menu, 4)
        dom:Create("UIListLayout", { Parent = menu, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
        local handle: any = { Row = row, Label = text, Scope = owner, _options = table.clone(options), _open = false, _signature = nil, _built = false, _dirty = true }
        handle.Normalize = function(value: any): any return if table.find(handle._options, value) then value else handle._options[1] end
        local function close() handle._open = false; menu.Visible = false; row.Size = UDim2.new(1, 0, 0, CONFIG.CLOSED_HEIGHT) end
        local function buildOptions()
            handle._built, handle._dirty = true, false
            owner:Unbind("Options")
            for _, child in ipairs(menu:GetChildren()) do if child:IsA("GuiObject") then dom:DestroyInstance(child) end end
            local optionScope = owner:CreateChild("Options")
            owner:Bind("Options", optionScope)
            for index, option in ipairs(handle._options) do
                local choice = dom:Create("TextButton", { Parent = menu, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = index,
                    Text = tostring(option), TextSize = 12, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left })
                section:StyleButton(choice, optionScope)
                optionScope:Connect(choice.Activated, function() if handle:Set(option) then close() end end)
            end
        end
        local function reconcileSelection(preserveSelection: boolean?)
            local selection = if preserveSelection then handle:Get() else nil
            local nextValue = handle.Normalize(selection)
            if nextValue ~= nil then
                if handle.Path then handle:Set(nextValue) else handle:Set(nextValue, true) end
            else handle:Set(nil, true) end
        end
        local function sizeFor(count: number): number return math.min(CONFIG.MAX_VISIBLE_OPTIONS, count) * CONFIG.OPTION_ROW_HEIGHT + CONFIG.MENU_PADDING end
        function handle:_Render(value: any)
            local nextText = tostring(value or "No options")
            if button.Text ~= nextText then button.Text = nextText end
        end
        -- The option buttons are rebuilt only when the list itself changed; the joined signature
        -- is the cheap way to detect that without comparing tables
        function handle:Refresh(nextOptions: { any }, preserveSelection: boolean?)
            local parts = table.create(#nextOptions)
            for index, option in ipairs(nextOptions) do parts[index] = tostring(option) end
            local signature = table.concat(parts, "\0")
            if signature == self._signature then
                reconcileSelection(preserveSelection)
                return
            end
            self._signature = signature
            close()
            self._options = table.clone(nextOptions)
            menu.Size = UDim2.new(1, 0, 0, sizeFor(#self._options))
            if self._built then buildOptions() else self._dirty = true end
            reconcileSelection(preserveSelection)
        end
        section:Bind(handle, defaultOrPath, callback)
        handle:Refresh(options, true)
        if handle.Path then owner:Add(state:Observe(handle.Path, function(value: any)
            if not table.find(handle._options, value) and handle._options[1] ~= nil then handle:Set(handle._options[1]) end
        end)) end
        owner:Connect(button.Activated, function()
            if handle._open then close(); return end
            if not handle._built or handle._dirty then buildOptions() end
            services:Get("UIEngine"):CloseAllDropdownsExcept(close)
            handle._open, menu.Visible = true, true
            row.Size = UDim2.new(1, 0, 0, CONFIG.OPEN_TOP_OFFSET + menu.Size.Y.Offset + CONFIG.OPEN_BOTTOM_OFFSET)
        end)
        owner:Add(services:Get("UIEngine"):RegisterDropdownClose(close))
        return handle
    end
    return setmetatable(Dropdown, { __call = function(_constructor: any, ...: any) return Dropdown:Create(...) end })
end
