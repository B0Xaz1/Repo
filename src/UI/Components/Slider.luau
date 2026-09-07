--!nonstrict
return function(services: any): any
    local dom, theme, environment = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("Environment")
    local section = services:Get("Require")("src/UI/Components/Section.luau", services)
    local scope = services:Get("Disposer"):CreateChild("Slider capture")
    local input = game:GetService("UserInputService")
    local Slider = { _active = nil }
    local function update(event: InputObject)
        local active = Slider._active
        if not active or active.Handle.Scope:IsDisposed() then return end
        local position = environment:GetPointerLocation(event)
        local alpha = math.clamp((position.X - active.Track.AbsolutePosition.X) / math.max(active.Track.AbsoluteSize.X, 1), 0, 1)
        active.Handle:Set(active.Min + alpha * (active.Max - active.Min))
    end
    scope:Connect(input.InputChanged, function(event: InputObject)
        if event.UserInputType == Enum.UserInputType.MouseMovement or event.UserInputType == Enum.UserInputType.Touch then update(event) end
    end)
    scope:Connect(input.InputEnded, function(event: InputObject)
        if event.UserInputType == Enum.UserInputType.MouseButton1 or event.UserInputType == Enum.UserInputType.Touch then Slider._active = nil end
    end)
    function Slider:Create(parent: Instance, label: string, defaultOrPath: any, minimum: number, maximum: number, step: number?, suffix: string?, callback: any?): any
        assert(maximum > minimum, "Slider needs an increasing range")
        local increment = math.max(step or 1, 0.0001)
        local row, text, owner = section:Control(parent, label, 36)
        text.Size, text.Position = UDim2.new(0.62, 0, 0, 18), UDim2.fromOffset(0, 0)
        local valueLabel = dom:Create("TextLabel", { Parent = row, BackgroundTransparency = 1, Position = UDim2.new(0.62, 0, 0, 0), Size = UDim2.new(0.38, 0, 0, 18),
            TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = theme:GetToken("TextDim") })
        theme:BindToken(valueLabel, "TextColor3", "TextDim")
        local hit = dom:Create("TextButton", { Parent = row, BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 16) })
        local track = dom:Create("Frame", { Parent = hit, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 4) })
        theme:BindToken(track, "BackgroundColor3", "ToggleOff"); dom:Create("UICorner", { Parent = track, CornerRadius = UDim.new(1, 0) })
        local fill = dom:Create("Frame", { Parent = track, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) })
        theme:BindToken(fill, "BackgroundColor3", "Accent"); dom:Create("UICorner", { Parent = fill, CornerRadius = UDim.new(1, 0) })
        local handle = { Row = row, Label = text, Scope = owner, Normalize = function(value: any)
            local number = tonumber(value) or minimum
            return math.clamp(minimum + math.floor((number - minimum) / increment + 0.5) * increment, minimum, maximum)
        end }
        function handle:_Render(value: number)
            local alpha = (value - minimum) / (maximum - minimum)
            fill.Size = UDim2.fromScale(alpha, 1)
            local formatted = string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", "")
            valueLabel.Text, text.Text = formatted .. (suffix or ""), label
        end
        section:Bind(handle, defaultOrPath, callback)
        owner:Connect(hit.InputBegan, function(event: InputObject)
            if event.UserInputType ~= Enum.UserInputType.MouseButton1 and event.UserInputType ~= Enum.UserInputType.Touch then return end
            Slider._active = { Handle = handle, Track = track, Min = minimum, Max = maximum }
            update(event)
        end)
        owner:Add(function() if Slider._active and Slider._active.Handle == handle then Slider._active = nil end end)
        return handle
    end
    return setmetatable(Slider, { __call = function(_constructor: any, ...: any) return Slider:Create(...) end })
end
