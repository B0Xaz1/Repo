return function(services: any): any
    local dom, theme = services:Get("DOM"), services:Get("ThemeEngine")
    local section = services:Get("Require")("src/UI/Components/Section.luau", services)
    local motion = services:Get("Motion")
    local Toggle = {}
    function Toggle:Create(parent: Instance, label: string, defaultOrPath: any, callback: any?): any
        local row, text, owner = section:Control(parent, label, 20)
        text.Position, text.Size = UDim2.fromOffset(20, 0), UDim2.new(1, -20, 1, 0)
        local box = dom:Create("TextButton", { Parent = row, Text = "", AutoButtonColor = false, BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 4), Size = UDim2.fromOffset(12, 12) })
        dom:Create("UICorner", { Parent = box, CornerRadius = UDim.new(0, 2) })
        local stroke = dom:CreateStroke(box, theme:GetToken("Border"), 1)
        theme:BindToken(stroke, "Color", "Border")
        local mark = dom:Create("Frame", { Parent = box, Name = "Check", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(6, 6), Rotation = -12 })
        local short = dom:Create("Frame", { Parent = mark, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.25, 0.62), Size = UDim2.new(0.38, 0, 0, 1.5), Rotation = 45, BackgroundTransparency = 1 })
        local long = dom:Create("Frame", { Parent = mark, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.62, 0.43), Size = UDim2.new(0.73, 0, 0, 1.5), Rotation = -45, BackgroundTransparency = 1 })
        theme:BindToken(short, "BackgroundColor3", "Bg"); theme:BindToken(long, "BackgroundColor3", "Bg")
        local handle = { Kind = "Toggle", Row = row, Label = text, Scope = owner, Normalize = function(value: any) return value == true end }
        function handle:_Render(value: boolean)
            if self._painted and self._shown == value then return end
            local duration = if self._painted then motion:Duration(row, motion.Times.Hover) else 0
            self._shown = value
            theme:BindToken(box, "BackgroundColor3", if value then "ToggleOn" else "ToggleOff")
            motion:Tween(stroke, "Toggle", { Transparency = if value then 1 else 0 }, duration)
            motion:Tween(mark, "Toggle", { Size = UDim2.fromOffset(if value then 8 else 6, if value then 8 else 6), Rotation = if value then 0 else -12 }, duration)
            motion:Tween(short, "Toggle", { BackgroundTransparency = if value then 0 else 1 }, duration)
            motion:Tween(long, "Toggle", { BackgroundTransparency = if value then 0 else 1 }, duration)
            self._painted = true
        end
        section:Bind(handle, defaultOrPath, callback)
        owner:Connect(box.Activated, function() handle:Set(not handle:Get()) end)
        return handle
    end
    return setmetatable(Toggle, { __call = function(_constructor: any, ...: any) return Toggle:Create(...) end })
end
