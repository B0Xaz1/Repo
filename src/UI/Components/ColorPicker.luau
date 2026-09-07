--!nonstrict
return function(services: any): any
    local dom, theme, environment = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("Environment")
    local input = game:GetService("UserInputService")
    local section = services:Get("Require")("src/UI/Components/Section.luau", services)
    local scope = services:Get("Disposer"):CreateChild("Color picker capture")
    local ColorPicker = { _active = nil }
    local function drag(event: InputObject)
        local active = ColorPicker._active
        if not active or active.Handle.Scope:IsDisposed() then return end
        local handle, field, position = active.Handle, active.Field, environment:GetPointerLocation(event)
        local x = math.clamp((position.X - field.AbsolutePosition.X) / math.max(field.AbsoluteSize.X, 1), 0, 1)
        local y = math.clamp((position.Y - field.AbsolutePosition.Y) / math.max(field.AbsoluteSize.Y, 1), 0, 1)
        if active.Mode == "Hue" then handle._hue = y else handle._saturation, handle._brightness = x, 1 - y end
        handle:Set(Color3.fromHSV(handle._hue, handle._saturation, handle._brightness))
    end
    scope:Connect(input.InputChanged, function(event: InputObject)
        if event.UserInputType == Enum.UserInputType.MouseMovement or event.UserInputType == Enum.UserInputType.Touch then drag(event) end
    end)
    scope:Connect(input.InputEnded, function(event: InputObject)
        if event.UserInputType == Enum.UserInputType.MouseButton1 or event.UserInputType == Enum.UserInputType.Touch then ColorPicker._active = nil end
    end)
    function ColorPicker:Create(parent: Instance, label: string, defaultOrPath: any, callback: any?): any
        local row, text, owner = section:Control(parent, label, 28)
        text.Size = UDim2.new(1, -120, 1, 0)
        local hex = dom:Create("TextBox", { Parent = row, BorderSizePixel = 0, ClearTextOnFocus = false, Size = UDim2.fromOffset(78, 22), Position = UDim2.new(1, -116, 0, 3),
            Text = "#FFFFFF", Font = Enum.Font.Code, TextSize = 11 })
        theme:BindToken(hex, "BackgroundColor3", "Elem"); theme:BindToken(hex, "TextColor3", "TextDim")
        dom:Create("UICorner", { Parent = hex, CornerRadius = UDim.new(0, 4) })
        local swatch = dom:Create("TextButton", { Parent = row, BorderSizePixel = 0, AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(28, 22), Position = UDim2.new(1, -28, 0, 3) })
        dom:Create("UICorner", { Parent = swatch, CornerRadius = UDim.new(0, 4) })
        local panel = dom:Create("Frame", { Parent = row, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 124), Visible = false })
        local square = dom:Create("TextButton", { Parent = panel, AutoButtonColor = false, Text = "", BorderSizePixel = 0, Size = UDim2.new(1, -25, 0, 112) })
        local white = dom:Create("Frame", { Parent = square, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) })
        dom:Create("UIGradient", { Parent = white, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) })
        local black = dom:Create("Frame", { Parent = square, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0) })
        dom:Create("UIGradient", { Parent = black, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }) })
        local marker = dom:Create("Frame", { Parent = square, Size = UDim2.fromOffset(6, 6), AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 5 })
        dom:Create("UICorner", { Parent = marker, CornerRadius = UDim.new(1, 0) }); dom:CreateStroke(marker, Color3.new(0, 0, 0))
        local hue = dom:Create("TextButton", { Parent = panel, Text = "", AutoButtonColor = false, BorderSizePixel = 0, Position = UDim2.new(1, -16, 0, 0), Size = UDim2.fromOffset(16, 112), BackgroundColor3 = Color3.new(1, 1, 1) })
        local stops = {}
        for index = 0, 6 do table.insert(stops, ColorSequenceKeypoint.new(index / 6, Color3.fromHSV(index / 6, 1, 1))) end
        dom:Create("UIGradient", { Parent = hue, Rotation = 90, Color = ColorSequence.new(stops) })
        local handle = { Row = row, Label = text, Scope = owner, _hue = 0, _saturation = 1, _brightness = 1,
            Normalize = function(value: any) return if typeof(value) == "Color3" then value else Color3.new(1, 1, 1) end }
        local function close() panel.Visible = false; row.Size = UDim2.new(1, 0, 0, 28); if ColorPicker._active and ColorPicker._active.Handle == handle then ColorPicker._active = nil end end
        function handle:_Render(value: Color3)
            local h, s, v = value:ToHSV()
            if s > 0 and v > 0 then self._hue = h end
            self._saturation, self._brightness = s, v
            square.BackgroundColor3, swatch.BackgroundColor3 = Color3.fromHSV(self._hue, 1, 1), value
            marker.Position = UDim2.fromScale(s, 1 - v)
            hex.Text, text.Text = string.format("#%02X%02X%02X", math.round(value.R * 255), math.round(value.G * 255), math.round(value.B * 255)), label
        end
        section:Bind(handle, defaultOrPath, callback)
        owner:Connect(swatch.Activated, function()
            if panel.Visible then close(); return end
            services:Get("UIEngine"):CloseAllDropdownsExcept(close)
            panel.Visible, row.Size = true, UDim2.new(1, 0, 0, 158)
        end)
        owner:Connect(hex.FocusLost, function()
            local value = hex.Text:gsub("^#", "")
            if #value == 6 and value:match("^%x+$") then
                handle:Set(Color3.fromRGB(tonumber(value:sub(1, 2), 16), tonumber(value:sub(3, 4), 16), tonumber(value:sub(5, 6), 16)))
            else services:Get("EventBus"):Publish("Notify", "Color", "Use a six-digit hexadecimal color, such as #889FFF") end
            handle:Set(handle:Get(), true)
        end)
        for field, mode in pairs({ [square] = "SV", [hue] = "Hue" }) do owner:Connect(field.InputBegan, function(event: InputObject)
            if event.UserInputType ~= Enum.UserInputType.MouseButton1 and event.UserInputType ~= Enum.UserInputType.Touch then return end
            ColorPicker._active = { Handle = handle, Field = field, Mode = mode }; drag(event)
        end) end
        owner:Add(services:Get("UIEngine"):RegisterDropdownClose(close)); owner:Add(close)
        return handle
    end
    return setmetatable(ColorPicker, { __call = function(_constructor: any, ...: any) return ColorPicker:Create(...) end })
end
