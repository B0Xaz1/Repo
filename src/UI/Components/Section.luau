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
        dom:Create("UICorner", { Parent = frame, CornerRadius = UDim.new(0, 10) })
        theme:BindToken(frame, "BackgroundColor3", "Panel")
        theme:BindToken(dom:CreateStroke(frame, theme:GetToken("BorderDim")), "Color", "BorderDim")
        dom:CreatePadding(frame, 14)
        dom:Create("UIListLayout", { Parent = frame, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder })
        local header = dom:Create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 0,
            Text = title, Font = Enum.Font.GothamSemibold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = theme:GetToken("Text") })
        theme:BindToken(header, "TextColor3", "Text")
        local content = dom:Create("Frame", { Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
        dom:Create("UIListLayout", { Parent = content, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
        return content
    end
    function Section:Control(parent: Instance, label: string, height: number?): (Frame, TextLabel, any)
        orders[parent] = (orders[parent] or 0) + 1
        local row = dom:Create("Frame", { Parent = parent, Name = "Control", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height or 38), LayoutOrder = orders[parent] })
        local text = dom:Create("TextLabel", { Parent = row, BackgroundTransparency = 1, Size = UDim2.new(0.56, -8, 1, 0),
            Text = label, TextSize = 12, Font = Enum.Font.Gotham, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = theme:GetToken("TextDim") })
        theme:BindToken(text, "TextColor3", "TextDim")
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
        text.TextSize, text.LineHeight = 12, 1.25
        theme:BindToken(text, "TextColor3", "TextMuted")
        dom:CreatePadding(row, 3, 0, 7, 0)
        local handle = { Row = row, Label = text, Scope = owner }
        function handle:Set(value: any, _silent: boolean?) text.Text = tostring(value) end
        return handle
    end
    function Section:StyleButton(button: TextButton, owner: any, token: string?)
        local normal = token or "Elem"
        button.AutoButtonColor = false
        theme:BindToken(button, "BackgroundColor3", normal)
        theme:BindToken(button, "TextColor3", "Text")
        dom:Create("UICorner", { Parent = button, CornerRadius = UDim.new(0, 6) })
        owner:Connect(button.MouseEnter, function() theme:BindToken(button, "BackgroundColor3", "ElemHover") end)
        owner:Connect(button.MouseLeave, function() theme:BindToken(button, "BackgroundColor3", normal) end)
    end
    function Section:NotifyLocked(required: number)
        local names = { "Entry", "Normal", "Full" }
        bus:Publish("Notify", "Tier locked", "This control requires " .. (names[required] or tostring(required)) .. " access")
    end
    function Section:Bind(handle: any, defaultOrPath: any, callback: any?, requiredTier: number?, literal: boolean?): any
        local path = if type(defaultOrPath) == "string" and not literal then defaultOrPath else nil
        local mapped = if path then state:GetRequiredTier(path) else 0
        if path and requiredTier ~= nil then assert(requiredTier == mapped, "UI tier mismatch for " .. path) end
        handle.Path, handle.RequiredTier = path, requiredTier or mapped
        handle.Row:SetAttribute("RequiredTier", handle.RequiredTier)
        handle.Row:SetAttribute("StatePath", path)
        function handle:Get(): any return self._value end
        function handle:Set(value: any, silent: boolean?): boolean
            if self.Scope:IsDisposed() then return false end
            if self.Normalize then value = self.Normalize(value) end
            if not silent and state:GetTier() < self.RequiredTier and value ~= false then Section:NotifyLocked(self.RequiredTier); return false end
            if not silent and self.Path then
                local ok, message = state:Set(self.Path, value)
                if not ok then bus:Publish("Notify", "Control", tostring(message)); return false end
            end
            self._value, self.Locked = value, state:GetTier() < self.RequiredTier
            if self._Render then self:_Render(value, self.Locked) end
            if not silent and callback then callback(value) end
            return true
        end
        if path then handle.Scope:Add(state:Observe(path, function(value: any) handle:Set(value, true) end)) end
        handle.Scope:Add(bus:Subscribe("TierChanged", function() handle:Set(if path then state:Get(path) else handle._value, true) end))
        handle:Set(if path then state:Get(path) else defaultOrPath, true)
        return handle
    end
    return Section
end
