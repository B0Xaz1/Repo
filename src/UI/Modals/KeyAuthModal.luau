--!nonstrict
return function(services: any): any
    local dom, theme, environment = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("Environment")
    local load, keys = services:Get("Require"), services:Get("KeyService")
    local scope = services:Get("Disposer"):CreateChild("KeyAuthModal")
    local KeyAuthModal = { _modalScope = nil, _generation = 0, _busy = false }
    function KeyAuthModal:Hide()
        self._generation += 1
        local owner = self._modalScope
        self._modalScope, self._busy = nil, false
        if owner then owner:Dispose() end
    end
    function KeyAuthModal:Show(onSuccess: (number) -> (), initialError: string?)
        self:Hide()
        local generation = self._generation
        local owner = scope:CreateChild("Auth view")
        self._modalScope = owner
        local root = dom:Create("ScreenGui", { Parent = assert(environment:GetSafeGuiParent(), "No GUI parent for authentication"), Name = dom:RandomName(),
            ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1200, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
        owner:Add(function() dom:DestroyInstance(root) end)
        theme:RegisterRoot(root)
        dom:Create("Frame", { Parent = root, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Active = true })
        local screen = if game:GetService("Workspace").CurrentCamera then game:GetService("Workspace").CurrentCamera.ViewportSize else Vector2.new(800, 600)
        local window = dom:Create("Frame", { Parent = root, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(math.min(470, screen.X - 28), math.min(510, screen.Y - 32)), BackgroundColor3 = theme:GetToken("Bg"), Active = true })
        theme:BindToken(window, "BackgroundColor3", "Bg")
        dom:Create("UICorner", { Parent = window, CornerRadius = UDim.new(0, 12) })
        theme:BindToken(dom:CreateStroke(window, theme:GetToken("Border")), "Color", "Border")
        local title = dom:Create("TextLabel", { Parent = window, BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -40, 0, 42),
            Text = "B0Xaz  /  ACCESS", Font = Enum.Font.GothamBold, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, Active = true })
        theme:BindToken(title, "TextColor3", "Accent")
        owner:Add(services:Get("UIEngine"):MakeDraggable(window, title))
        local body = dom:Create("ScrollingFrame", { Parent = window, BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(18, 65), Size = UDim2.new(1, -36, 1, -81),
            CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3 })
        theme:BindToken(body, "ScrollBarImageColor3", "Accent")
        dom:CreatePadding(body, 2, 5, 8, 2)
        dom:Create("UIListLayout", { Parent = body, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder })
        local section = load("src/UI/Components/Section.luau", services)
        local textbox = load("src/UI/Components/Textbox.luau", services)
        local form = section:Create(body, "Verify your license")
        section:Info(form, "One verification, one session. Your license tier unlocks the relevant tools; settings remain available after logout.")
        local key = textbox(form, "License key", "")
        local status = section:Info(form, initialError or "Enter your key to continue. Your unload shortcut is already active.")
        theme:BindToken(status.Label, "TextColor3", if initialError then "Warning" else "TextDim")
        local category = section:Info(form, "Entry  /  Normal  /  Full")
        local verify: any = nil
        local function authenticate()
            if KeyAuthModal._busy or owner:IsDisposed() then return end
            KeyAuthModal._busy = true
            local raw = key.Box.Text
            verify:Set("Verifying…", true)
            status:Set("Contacting the license service…")
            owner:Spawn(function()
                local result = table.pack(pcall(function() return keys:AuthenticateKey(raw) end))
                if owner:IsDisposed() or generation ~= KeyAuthModal._generation then return end
                KeyAuthModal._busy = false
                verify:Set("Verify license", true)
                if not result[1] then
                    status:Set(tostring(result[2])); category:Set("Verification could not complete. You can retry or unload.")
                    return
                end
                local verified, tier, message, kind = result[2], result[3], result[4], result[5]
                if verified then
                    KeyAuthModal:Hide()
                    onSuccess(tier)
                else
                    -- Server text is shown literally (RichText is off); never rewrite a transient error as an invalid key.
                    status:Set(message or "Verification failed")
                    category:Set(if kind == "transient" then "Temporary service failure · your key was not rejected"
                        else if kind == "unconfigured" then "Deployment setup is required before authentication can work"
                        else "Access not granted · check the server's message above")
                    theme:BindToken(status.Label, "TextColor3", if kind == "transient" then "Warning" else "Danger")
                end
            end)
        end
        verify = textbox:CreateButton(form, "Verify license", authenticate, 0)
        owner:Connect(key.Box.FocusLost, function(enterPressed: boolean) if enterPressed then authenticate() end end)
        textbox:CreateButton(form, "Unload this session", function() environment.Globals.B0XazUnload() end, 0)
        local privacy = section:Create(body, "Before you continue")
        section:Info(privacy, "The configured license server receives your key and device ID over HTTPS. Local key storage is obfuscated, not encrypted. No license endpoint is invented by this build.")
    end
    function KeyAuthModal:Destroy() self:Hide(); scope:Dispose() end
    scope:Add(function() KeyAuthModal:Hide() end)
    return KeyAuthModal
end
