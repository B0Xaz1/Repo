--!nonstrict
return function(services: any): any
    local dom, theme = services:Get("DOM"), services:Get("ThemeEngine")
    local section = services:Get("Require")("src/UI/Components/Section.luau", services)
    local Toggle = {}
    function Toggle:Create(parent: Instance, label: string, defaultOrPath: any, callback: any?, requiredTier: number?): any
        local row, text, owner = section:Control(parent, label, 36)
        text.Size = UDim2.new(1, -58, 1, 0)
        local track = dom:Create("TextButton", { Parent = row, Text = "", AutoButtonColor = false, BorderSizePixel = 0,
            Position = UDim2.new(1, -40, 0.5, -10), Size = UDim2.fromOffset(38, 20) })
        dom:Create("UICorner", { Parent = track, CornerRadius = UDim.new(1, 0) })
        local knob = dom:Create("Frame", { Parent = track, Size = UDim2.fromOffset(14, 14), BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(245, 247, 255) })
        dom:Create("UICorner", { Parent = knob, CornerRadius = UDim.new(1, 0) })
        local handle = { Row = row, Label = text, Scope = owner, Normalize = function(value: any) return value == true end }
        function handle:_Render(value: boolean, locked: boolean)
            text.Text = label .. (if locked then "  [locked]" else "")
            theme:BindToken(track, "BackgroundColor3", if value and not locked then "ToggleOn" else "ToggleOff")
            knob.Position = UDim2.fromOffset(if value then 21 else 3, 3)
            knob.BackgroundTransparency = if locked then 0.5 else 0
        end
        section:Bind(handle, defaultOrPath, callback, requiredTier)
        owner:Connect(track.Activated, function() handle:Set(not handle:Get()) end)
        return handle
    end
    return setmetatable(Toggle, { __call = function(_constructor: any, ...: any) return Toggle:Create(...) end })
end
