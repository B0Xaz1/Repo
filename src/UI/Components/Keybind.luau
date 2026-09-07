--!nonstrict
return function(services: any): any
    local load, state, dom = services:Get("Require"), services:Get("StateStore"), services:Get("DOM")
    local environment = services:Get("Environment")
    local section = load("src/UI/Components/Section.luau", services)
    local scope = services:Get("Disposer"):CreateChild("Keybind capture")
    local Keybind = { _active = nil }
    local function finishCapture(value: EnumItem?)
        local handle = Keybind._active
        Keybind._active = nil
        if handle then
            if value then handle:Set(value) else handle:Set(handle:Get(), true) end
        end
        -- Keep the guard through the current input dispatch, so later spawned hotkey handlers cannot see it cleared.
        scope:Delay(0.05, function() if not Keybind._active then state:SetTransient("IsBindingKey", false) end end)
    end
    scope:Connect(game:GetService("UserInputService").InputBegan, function(event: InputObject)
        if not Keybind._active then return end
        local value = if event.KeyCode ~= Enum.KeyCode.Unknown then event.KeyCode else event.UserInputType
        if value == Enum.KeyCode.Escape then finishCapture(Enum.KeyCode.Unknown); return end
        if value == Enum.UserInputType.MouseMovement or value == Enum.UserInputType.Touch then return end
        finishCapture(environment:ParseKeybind(value))
    end)
    function Keybind:Create(parent: Instance, label: string, defaultOrPath: any, callback: any?): any
        local row, text, owner = section:Control(parent, label, 22)
        text.Size = UDim2.new(1, -70, 1, 0)
        local button = dom:Create("TextButton", { Parent = row, BorderSizePixel = 0, Position = UDim2.new(1, -64, 0, 1), Size = UDim2.fromOffset(64, 20),
            Font = Enum.Font.Gotham, TextSize = 11, Text = "Unbound" })
        section:StyleButton(button, owner)
        local handle = { Row = row, Label = text, Scope = owner, Normalize = function(value: any) return environment:ParseKeybind(value) or Enum.KeyCode.Unknown end }
        function handle:_Render(value: any)
            text.Text = label
            button.Text = if Keybind._active == handle then "Press a key..." else environment:FormatKeybindName(value)
        end
        section:Bind(handle, defaultOrPath, callback)
        owner:Connect(button.Activated, function()
            if Keybind._active then finishCapture(nil) end
            Keybind._active = handle
            state:SetTransient("IsBindingKey", true)
            handle:Set(handle:Get(), true)
        end)
        owner:Add(function() if Keybind._active == handle then Keybind._active = nil; state:SetTransient("IsBindingKey", false) end end)
        return handle
    end
    scope:Add(function() Keybind._active = nil; state:SetTransient("IsBindingKey", false) end)
    return setmetatable(Keybind, { __call = function(_constructor: any, ...: any) return Keybind:Create(...) end })
end
