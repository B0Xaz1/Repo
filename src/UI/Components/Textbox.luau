--!nonstrict
return function(services: any): any
    local dom, theme, state, bus = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("StateStore"), services:Get("EventBus")
    local section = services:Get("Require")("src/UI/Components/Section.luau", services)
    local Textbox = {}
    -- Exception to the shared string convention: text is literal initial text; use the explicit path argument to bind it.
    function Textbox:Create(parent: Instance, label: string, text: string?, callback: any?, path: string?, requiredTier: number?): any
        local row, labelObject, owner = section:Control(parent, label, 42)
        local box = dom:Create("TextBox", { Parent = row, BorderSizePixel = 0, Position = UDim2.new(0.47, 0, 0, 5), Size = UDim2.new(0.53, 0, 0, 32),
            ClearTextOnFocus = false, PlaceholderText = label, Text = "", Font = Enum.Font.Gotham, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd })
        theme:BindToken(box, "BackgroundColor3", "Elem"); theme:BindToken(box, "TextColor3", "Text"); theme:BindToken(box, "PlaceholderColor3", "TextMuted")
        dom:Create("UICorner", { Parent = box, CornerRadius = UDim.new(0, 6) }); dom:CreatePadding(box, 4, 8)
        local handle = { Row = row, Label = labelObject, Box = box, Scope = owner, Normalize = function(value: any) return tostring(value or "") end }
        function handle:_Render(value: string, locked: boolean)
            box.Text = value
            labelObject.Text = label .. (if locked then "  [locked]" else "")
        end
        section:Bind(handle, path or text or "", callback, requiredTier, path == nil)
        owner:Connect(box.FocusLost, function() if not handle:Set(box.Text) then box.Text = handle:Get() end end)
        return handle
    end
    function Textbox:CreateButton(parent: Instance, text: string, onClick: () -> ...any, requiredTier: number?): any
        local row, label, owner = section:Control(parent, text, 39)
        label.Visible = false
        local button = dom:Create("TextButton", { Parent = row, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, 0, 0, 33),
            Font = Enum.Font.GothamMedium, TextSize = 12, Text = text })
        section:StyleButton(button, owner)
        local handle = { Row = row, Label = label, Button = button, Scope = owner, _busy = false, Normalize = function(value: any) return tostring(value) end }
        function handle:_Render(value: string, locked: boolean) button.Text = value .. (if locked then "  [locked]" else "") end
        section:Bind(handle, text, nil, requiredTier, true)
        owner:Connect(button.Activated, function()
            if handle._busy then return end
            if state:GetTier() < handle.RequiredTier then section:NotifyLocked(handle.RequiredTier); return end
            handle._busy = true
            local results = table.pack(pcall(onClick))
            handle._busy = false
            if not results[1] then bus:Publish("Notify", "Action failed", tostring(results[2]))
            elseif type(results[2]) == "boolean" and type(results[3]) == "string" then bus:Publish("Notify", if results[2] then text else "Unavailable", results[3]) end
        end)
        return handle
    end
    return setmetatable(Textbox, { __call = function(_constructor: any, ...: any) return Textbox:Create(...) end })
end
