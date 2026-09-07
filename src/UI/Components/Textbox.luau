--!nonstrict
return function(services: any): any
    local dom, theme, bus = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("EventBus")
    local section = services:Get("Require")("src/UI/Components/Section.luau", services)
    local Textbox = {}
    -- Exception to the shared string convention: text is literal initial text; use the explicit path argument to bind it.
    function Textbox:Create(parent: Instance, label: string, text: string?, callback: any?, path: string?): any
        local row, labelObject, owner = section:Control(parent, label, 46)
        labelObject.Size, labelObject.Position = UDim2.new(1, 0, 0, 16), UDim2.fromOffset(0, 0)
        local box = dom:Create("TextBox", { Parent = row, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 26),
            ClearTextOnFocus = false, PlaceholderText = label, Text = "", Font = Enum.Font.Gotham, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
        theme:BindToken(box, "BackgroundColor3", "Elem"); theme:BindToken(box, "TextColor3", "Text"); theme:BindToken(box, "PlaceholderColor3", "TextMuted")
        theme:BindToken(dom:CreateStroke(box, theme:GetToken("BorderDim")), "Color", "BorderDim")
        dom:Create("UICorner", { Parent = box, CornerRadius = UDim.new(0, 3) }); dom:CreatePadding(box, 0, 8)
        local handle = { Row = row, Label = labelObject, Box = box, Scope = owner, Normalize = function(value: any) return tostring(value or "") end }
        function handle:_Render(value: string)
            box.Text, labelObject.Text = value, label
        end
        section:Bind(handle, path or text or "", callback, path == nil)
        owner:Connect(box.FocusLost, function() if not handle:Set(box.Text) then box.Text = handle:Get() end end)
        return handle
    end
    function Textbox:CreateButton(parent: Instance, text: string, onClick: () -> ...any): any
        local row, label, owner = section:Control(parent, text, 30)
        label.Visible = false
        local button = dom:Create("TextButton", { Parent = row, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 26),
            Font = Enum.Font.GothamMedium, TextSize = 12, Text = text })
        section:StyleButton(button, owner)
        local handle = { Row = row, Label = label, Button = button, Scope = owner, _busy = false, Normalize = function(value: any) return tostring(value) end }
        function handle:_Render(value: string) button.Text = value end
        section:Bind(handle, text, nil, true)
        owner:Connect(button.Activated, function()
            if handle._busy then return end
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
