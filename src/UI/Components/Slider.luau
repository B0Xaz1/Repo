--!nonstrict
return function(services: any): any
    local dom, theme = services:Get("DOM"), services:Get("ThemeEngine")
    local section = services:Get("Require")("src/UI/Components/Section.luau", services)
    local scope = services:Get("Disposer"):CreateChild("Slider capture")
    local input = game:GetService("UserInputService")
    local Slider = { _active = nil }
    local function update(position: Vector3)
        local active = Slider._active
        if not active or active.Handle.Scope:IsDisposed() then return end
        local alpha = math.clamp((position.X - active.Track.AbsolutePosition.X) / math.max(active.Track.AbsoluteSize.X, 1), 0, 1)
        active.Handle:Set(active.Min + alpha * (active.Max - active.Min))
    end
    scope:Connect(input.InputChanged, function(event: InputObject)
        if event.UserInputType == Enum.UserInputType.MouseMovement or event.UserInputType == Enum.UserInputType.Touch then update(event.Position) end
    end)
    scope:Connect(input.InputEnded, function(event: InputObject)
        if event.UserInputType == Enum.UserInputType.MouseButton1 or event.UserInputType == Enum.UserInputType.Touch then Slider._active = nil end
    end)
    function Slider:Create(parent: Instance, label: string, defaultOrPath: any, minimum: number, maximum: number, step: number?, suffix: string?, callback: any?, requiredTier: number?): any
        assert(maximum > minimum, "Slider needs an increasing range")
        local increment = math.max(step or 1, 0.0001)
        local row, text, owner = section:Control(parent, label, 59)
        text.Size, text.Position = UDim2.new(0.7, 0, 0, 28), UDim2.fromOffset(0, 0)
        local valueLabel = dom:Create("TextLabel", { Parent = row, BackgroundTransparency = 1, Position = UDim2.new(0.7, 0, 0, 0), Size = UDim2.new(0.3, 0, 0, 28),
            TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.Code, TextSize = 12, TextColor3 = theme:GetToken("Accent") })
        theme:BindToken(valueLabel, "TextColor3", "Accent")
        local hit = dom:Create("TextButton", { Parent = row, BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 24) })
        local track = dom:Create("Frame", { Parent = hit, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 4) })
        theme:BindToken(track, "BackgroundColor3", "ToggleOff"); dom:Create("UICorner", { Parent = track, CornerRadius = UDim.new(1, 0) })
        local fill = dom:Create("Frame", { Parent = track, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) })
        theme:BindToken(fill, "BackgroundColor3", "Accent"); dom:Create("UICorner", { Parent = fill, CornerRadius = UDim.new(1, 0) })
        local knob = dom:Create("Frame", { Parent = track, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(10, 10), BorderSizePixel = 0 })
        theme:BindToken(knob, "BackgroundColor3", "Accent"); dom:Create("UICorner", { Parent = knob, CornerRadius = UDim.new(1, 0) })
        local handle = { Row = row, Label = text, Scope = owner, Normalize = function(value: any)
            local number = tonumber(value) or minimum
            return math.clamp(minimum + math.floor((number - minimum) / increment + 0.5) * increment, minimum, maximum)
        end }
        function handle:_Render(value: number, locked: boolean)
            local alpha = (value - minimum) / (maximum - minimum)
            fill.Size, knob.Position = UDim2.fromScale(alpha, 1), UDim2.fromScale(alpha, 0.5)
            local formatted = string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", "")
            valueLabel.Text = formatted .. (suffix or "")
            text.Text = label .. (if locked then "  [locked]" else "")
        end
        section:Bind(handle, defaultOrPath, callback, requiredTier)
        owner:Connect(hit.InputBegan, function(event: InputObject)
            if event.UserInputType ~= Enum.UserInputType.MouseButton1 and event.UserInputType ~= Enum.UserInputType.Touch then return end
            if handle.Locked then section:NotifyLocked(handle.RequiredTier); return end
            Slider._active = { Handle = handle, Track = track, Min = minimum, Max = maximum }
            update(event.Position)
        end)
        owner:Add(function() if Slider._active and Slider._active.Handle == handle then Slider._active = nil end end)
        return handle
    end
    return setmetatable(Slider, { __call = function(_constructor: any, ...: any) return Slider:Create(...) end })
end
