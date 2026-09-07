--!nonstrict
return function(services: any): any
    local dom, theme, state, bus = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("StateStore"), services:Get("EventBus")
    local disposer = services:Get("Disposer")
    local orders = setmetatable({}, { __mode = "k" })
    local Section = {}

    function Section:Create(parent: Instance, title: string): Frame
        orders[parent] = (orders[parent] or 0) + 1
        local frame = dom:Create("Frame", { Parent = parent, Name = "Section", BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = orders[parent], BackgroundColor3 = theme:GetToken("Panel") })
        frame:SetAttribute("B0XazSection", title)
        dom:Create("UICorner", { Parent = frame, CornerRadius = UDim.new(0, 3) })
        theme:BindToken(frame, "BackgroundColor3", "Panel")
        theme:BindToken(dom:CreateStroke(frame, theme:GetToken("Accent")), "Color", "Accent")
        dom:CreatePadding(frame, 10, 12, 10, 12)
        dom:Create("UIListLayout", { Parent = frame, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })
        local header = dom:Create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 0,
            Text = title, Font = Enum.Font.GothamMedium, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = theme:GetToken("Accent") })
        theme:BindToken(header, "TextColor3", "Accent")
        local content = dom:Create("Frame", { Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
        dom:Create("UIListLayout", { Parent = content, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })
        return content
    end
    function Section:Control(parent: Instance, label: string, height: number?): (Frame, TextLabel, any)
        orders[parent] = (orders[parent] or 0) + 1
        local row = dom:Create("Frame", { Parent = parent, Name = "Control", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height or 26), LayoutOrder = orders[parent] })
        local text = dom:Create("TextLabel", { Parent = row, BackgroundTransparency = 1, Size = UDim2.new(0.56, -8, 1, 0),
            Text = label, TextSize = 12, Font = Enum.Font.Gotham, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = theme:GetToken("Text") })
        theme:BindToken(text, "TextColor3", "Text")
        local owner = disposer:CreateChild("Control " .. label)
        owner:Connect(row.Destroying, function() owner:Dispose() end)
        row:SetAttribute("B0XazLabel", label)
        if services:Has("UIEngine") then owner:Add(services:Get("UIEngine"):RegisterControl(row, label)) end
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
        function handle:Set(value: any, _silent: boolean?) text.Text = tostring(value) end
        return handle
    end
    function Section:StyleButton(button: TextButton, owner: any, token: string?)
        local normal = token or "Elem"
        button.AutoButtonColor = false
        theme:BindToken(button, "BackgroundColor3", normal)
        theme:BindToken(button, "TextColor3", "Text")
        theme:BindToken(dom:CreateStroke(button, theme:GetToken("BorderDim")), "Color", "BorderDim")
        dom:Create("UICorner", { Parent = button, CornerRadius = UDim.new(0, 3) })
        owner:Connect(button.MouseEnter, function() theme:BindToken(button, "BackgroundColor3", "ElemHover") end)
        owner:Connect(button.MouseLeave, function() theme:BindToken(button, "BackgroundColor3", normal) end)
    end
    function Section:Bind(handle: any, defaultOrPath: any, callback: any?, literal: boolean?): any
        local path = if type(defaultOrPath) == "string" and not literal then defaultOrPath else nil
        handle.Path = path
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
