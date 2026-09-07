--!nonstrict
return function(services: any): any
    local dom, theme = services:Get("DOM"), services:Get("ThemeEngine")
    local section = services:Get("Require")("src/UI/Components/Section.luau", services)
    local Toggle = {}
    function Toggle:Create(parent: Instance, label: string, defaultOrPath: any, callback: any?): any
        local row, text, owner = section:Control(parent, label, 24)
        text.Position, text.Size = UDim2.fromOffset(22, 0), UDim2.new(1, -22, 1, 0)
        local box = dom:Create("TextButton", { Parent = row, Text = "", AutoButtonColor = false, BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 5), Size = UDim2.fromOffset(14, 14) })
        dom:Create("UICorner", { Parent = box, CornerRadius = UDim.new(0, 2) })
        local stroke = dom:CreateStroke(box, theme:GetToken("Border"), 1)
        theme:BindToken(stroke, "Color", "Border")
        local handle = { Row = row, Label = text, Scope = owner, Normalize = function(value: any) return value == true end }
        function handle:_Render(value: boolean)
            text.Text = label
            theme:BindToken(box, "BackgroundColor3", if value then "ToggleOn" else "ToggleOff")
            stroke.Thickness, stroke.Transparency = 1, if value then 1 else 0
        end
        section:Bind(handle, defaultOrPath, callback)
        owner:Connect(box.Activated, function() handle:Set(not handle:Get()) end)
        return handle
    end
    return setmetatable(Toggle, { __call = function(_constructor: any, ...: any) return Toggle:Create(...) end })
end
