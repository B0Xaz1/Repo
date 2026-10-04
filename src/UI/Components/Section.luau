return function(services: any): any
    local dom, theme, state, bus = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("StateStore"), services:Get("EventBus")
    local disposer = services:Get("Disposer")
    local orders = setmetatable({}, { __mode = "k" })
    local Section = {}
    local details = setmetatable({}, { __mode = "k" })

    function Section:Create(parent: Instance, title: string, resetPath: string?): Frame
        orders[parent] = (orders[parent] or 0) + 1
        local frame = dom:Create("Frame", { Parent = parent, Name = "Section", BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = orders[parent], BackgroundColor3 = theme:GetToken("Panel") })
        frame:SetAttribute("B0XazSection", title)
        dom:Create("UICorner", { Parent = frame, CornerRadius = UDim.new(0, 6) })
        theme:BindToken(frame, "BackgroundColor3", "Panel")
        theme:BindToken(dom:CreateStroke(frame, theme:GetToken("Border")), "Color", "Border")
        dom:CreatePadding(frame, 8, 10, 8, 10)
        dom:Create("UIListLayout", { Parent = frame, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder })
        local header = dom:Create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 0,
            Text = title, Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = theme:GetToken("Accent") })
        theme:BindToken(header, "TextColor3", "Accent")
        local content = dom:Create("Frame", { Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
        dom:Create("UIListLayout", { Parent = content, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
        if resetPath then
            local reset = dom:Create("TextButton", { Parent = content, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 20),
                Text = "Reset section", Font = Enum.Font.Gotham, TextSize = 10, AutoButtonColor = false, LayoutOrder = 999 })
            local owner = disposer:CreateChild(`Reset action {title}`)
            self:StyleButton(reset, owner)
            owner:Connect(reset.Activated, function()
                local ok, message = state:ResetSection(resetPath)
                bus:Publish("Notify", if ok then "Section reset" else "Reset failed", message or `{title} restored to defaults`)
            end)
            owner:Connect(frame.Destroying, function() owner:Dispose() end)
        end
        return content
    end
    function Section:Control(parent: Instance, label: string, height: number?): (Frame, TextLabel, any)
        orders[parent] = (orders[parent] or 0) + 1
        local original = parent
        local slot, pin
        local decorated = height ~= 0
        if decorated then
            slot = dom:Create("Frame", { Parent = parent, Name = "ControlSlot", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = orders[parent] })
            parent = dom:Create("Frame", { Parent = slot, BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
        end
        local row = dom:Create("Frame", { Parent = parent, Name = "Control", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height or 22), LayoutOrder = orders[original] })
        local text = dom:Create("TextLabel", { Parent = row, BackgroundTransparency = 1, Size = UDim2.new(0.56, -8, 1, 0),
            Text = label, TextSize = 12, Font = Enum.Font.Gotham, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = theme:GetToken("Text") })
        theme:BindToken(text, "TextColor3", "Text")
        local owner = disposer:CreateChild(`Control {label}`)
        local destroying = false
        owner:ConnectImmediate(row.Destroying, function() destroying = true; owner:Dispose() end)
        owner:Add(function() if not destroying then dom:DestroyInstance(slot or row) end end)
        row:SetAttribute("B0XazLabel", label)
        local item = { Slot = slot or row, Content = parent, Label = label }
        details[row] = item
        owner:Add(function() details[row] = nil end)
        -- Pinned/search results retain their original section's lifetime.
        owner:ConnectImmediate(original.Destroying, function() dom:DestroyInstance(slot or row) end)
        if decorated then
            pin = dom:Create("TextButton", { Parent = slot, Name = "Favorite", BackgroundTransparency = 1, BorderSizePixel = 0,
                Position = UDim2.new(1, -20, 0, 0), Size = UDim2.fromOffset(20, 22), Text = "☆", TextSize = 17, Font = Enum.Font.Gotham, AutoButtonColor = false })
            theme:BindToken(pin, "TextColor3", "TextMuted")
            item.Pin = pin
        end
        if services:Has("UIEngine") then owner:Add(services:Get("UIEngine"):RegisterControl(slot or row, label, pin, owner)) end
        return row, text, owner
    end
    function Section:Info(parent: Instance, message: string): any
        local row, text, owner = self:Control(parent, message, 0)
        row.AutomaticSize = Enum.AutomaticSize.Y
        text.Size, text.AutomaticSize = UDim2.new(1, 0, 0, 0), Enum.AutomaticSize.Y
        text.TextSize, text.LineHeight = 11, 1.25
        theme:BindToken(text, "TextColor3", "TextMuted")
        dom:CreatePadding(row, 2, 0, 4, 0)
        local handle = { Row = row, Label = text, Scope = owner }
        function handle:Set(value: any, _silent: boolean?)
            local nextText = tostring(value)
            if text.Text ~= nextText then text.Text = nextText end
        end
        return handle
    end
    function Section:StyleButton(button: TextButton, owner: any, token: string?, borderless: boolean?)
        local normal = token or "Elem"
        if borderless then button:SetAttribute("B0XazBorderless", true) end
        button.AutoButtonColor = false
        theme:BindToken(button, "BackgroundColor3", normal)
        theme:BindToken(button, "TextColor3", "Text")
        if not borderless then theme:BindToken(dom:CreateStroke(button, theme:GetToken("BorderDim")), "Color", "BorderDim") end
        dom:Create("UICorner", { Parent = button, CornerRadius = UDim.new(0, 5) })
    end
    function Section:Bind(handle: any, defaultOrPath: any, callback: any?, literal: boolean?): any
        -- A string argument names a state path unless the caller marks it as a literal value
        local path = if type(defaultOrPath) == "string" and not literal then defaultOrPath else nil
        handle.Path = path
        local item = details[handle.Row]
        if item then
            item.Path, item.Kind, item.Range = path, handle.Kind, handle.Range
            item.Slot:SetAttribute("StatePath", path)
            if item.Pin and not item.Help and services:Has("Tooltips") then
                local tips = services:Get("Tooltips")
                local description = tips:Describe(item.Label, path, handle.Kind, handle.Range)
                if description then
                    item.Content.Size = UDim2.new(1, -44, 0, 0)
                    item.Pin.Position = UDim2.new(1, -42, 0, 0)
                    local help = dom:Create("TextButton", { Parent = item.Slot, Name = "Help", BackgroundTransparency = 1, BorderSizePixel = 0,
                        Position = UDim2.new(1, -20, 0, 0), Size = UDim2.fromOffset(20, 22), Text = "?", TextSize = 12, Font = Enum.Font.Gotham, AutoButtonColor = false })
                    item.Help = help
                    theme:BindToken(help, "TextColor3", "TextMuted")
                    tips:Attach(item.Slot, help, function() return description end, handle.Scope)
                end
            end
        end
        handle.Row:SetAttribute("StatePath", path)
        function handle:Get(): any return self._value end
        function handle:Set(value: any, silent: boolean?): boolean
            if self.Scope:IsDisposed() then return false end
            if self.Normalize then value = self.Normalize(value) end
            if not silent and self.Path then
                local ok, message = state:Set(self.Path, value)
                if not ok then bus:Publish("Notify", "Control", tostring(message)); return false end
            end
            self._value = value
            if self._Render then self:_Render(value) end
            if not silent and callback then callback(value) end
            return true
        end
        if path then handle.Scope:Add(state:Observe(path, function(value: any) handle:Set(value, true) end)) end
        handle:Set(if path then state:Get(path) else defaultOrPath, true)
        return handle
    end
    return Section
end
