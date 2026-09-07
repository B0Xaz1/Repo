--!nonstrict
return function(services: any): any
    local dom, theme, environment, config = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("Environment"), services:Get("ConfigService")
    local scope = services:Get("Disposer"):CreateChild("ConfigShareModal")
    local ConfigShareModal = { _view = nil }
    function ConfigShareModal:Hide()
        local owner = self._view; self._view = nil
        if owner then owner:Dispose() end
    end
    function ConfigShareModal:Show(initialJson: string?)
        self:Hide()
        local owner = scope:CreateChild("Share editor")
        self._view = owner
        local root = dom:Create("ScreenGui", { Parent = assert(environment:GetSafeGuiParent(), "No GUI parent for config editor"), Name = dom:RandomName(),
            ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1150, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
        theme:RegisterRoot(root)
        owner:Add(function() dom:DestroyInstance(root) end)
        dom:Create("Frame", { Parent = root, BorderSizePixel = 0, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4, Size = UDim2.fromScale(1, 1), Active = true })
        local screen = if game:GetService("Workspace").CurrentCamera then game:GetService("Workspace").CurrentCamera.ViewportSize else Vector2.new(800, 600)
        local window = dom:Create("Frame", { Parent = root, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(math.min(660, screen.X - 28), math.min(560, screen.Y - 32)), Active = true })
        theme:BindToken(window, "BackgroundColor3", "Bg"); dom:Create("UICorner", { Parent = window, CornerRadius = UDim.new(0, 8) })
        theme:BindToken(dom:CreateStroke(window, theme:GetToken("Border")), "Color", "Border")
        local title = dom:Create("TextLabel", { Parent = window, BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 39),
            Text = "CONFIG  /  JSON EDITOR", Font = Enum.Font.GothamSemibold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, Active = true })
        theme:BindToken(title, "TextColor3", "Accent")
        owner:Add(services:Get("UIEngine"):MakeDraggable(window, title))
        local scroll = dom:Create("ScrollingFrame", { Parent = window, BorderSizePixel = 0, Position = UDim2.fromOffset(18, 61), Size = UDim2.new(1, -36, 1, -211),
            CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3 })
        theme:BindToken(scroll, "BackgroundColor3", "Panel"); theme:BindToken(scroll, "ScrollBarImageColor3", "Accent")
        dom:CreatePadding(scroll, 10)
        local json, exportMessage = initialJson, nil
        if json == nil then json, exportMessage = config:Export() end
        local editor = dom:Create("TextBox", { Parent = scroll, BackgroundTransparency = 1, Size = UDim2.new(1, -4, 0, 180), AutomaticSize = Enum.AutomaticSize.Y,
            Text = json or "", TextWrapped = true, MultiLine = true, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            Font = Enum.Font.Code, TextSize = 12 })
        theme:BindToken(editor, "TextColor3", "Text")
        local footer = dom:Create("Frame", { Parent = window, BackgroundTransparency = 1, Position = UDim2.new(0, 18, 1, -137), Size = UDim2.new(1, -36, 0, 121) })
        dom:Create("UIListLayout", { Parent = footer, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder })
        local section = services:Get("Require")("src/UI/Components/Section.luau", services)
        local textbox = services:Get("Require")("src/UI/Components/Textbox.luau", services)
        local status = section:Info(footer, exportMessage or "Edit, copy or paste a complete profile. Import validates before applying it.")
        local actions = dom:Create("Frame", { Parent = footer, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 80), LayoutOrder = 99 })
        dom:Create("UIGridLayout", { Parent = actions, CellSize = UDim2.new(0.5, -4, 0, 37), CellPadding = UDim2.fromOffset(8, 3), SortOrder = Enum.SortOrder.LayoutOrder })
        textbox:CreateButton(actions, "Copy JSON", function()
            local ok, message = environment:SetClipboard(editor.Text)
            status:Set(message or "JSON copied to clipboard")
            return ok, message or "JSON copied"
        end, 0)
        textbox:CreateButton(actions, "Paste clipboard", function()
            local clipboard = environment:GetClipboard()
            if not clipboard then status:Set("Clipboard unavailable. Paste manually into the editor."); return end
            editor.Text = clipboard; status:Set("Clipboard pasted. Review it, then apply.")
        end, 0)
        textbox:CreateButton(actions, "Apply JSON", function()
            local ok, message = config:Import(editor.Text)
            status:Set(message)
            return ok, message
        end, 0)
        textbox:CreateButton(actions, "Close editor", function() ConfigShareModal:Hide() end, 0)
    end
    function ConfigShareModal:Destroy() self:Hide(); scope:Dispose() end
    scope:Add(function() ConfigShareModal:Hide() end)
    return ConfigShareModal
end
