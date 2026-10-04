local Workspace = game:GetService("Workspace")

local HELP = table.freeze({
    ["Aimbot.Enabled"] = "Enable aim assistance. Target filters and activation binding still apply.",
    ["Aimbot.UseCamera"] = "Choose camera-based aiming instead of mouse movement. Mouse mode requires compatible input support.",
    ["Aimbot.Smoothness"] = "Higher values make aim adjustments more gradual; lower values respond more directly.",
    ["Aimbot.LockMode"] = "Hold requires the activation input to stay pressed; Toggle keeps the lock until pressed again.",
    ["Aimbot.FOV.Size"] = "Set the screen-space radius used to select targets around the cursor.",
    ["Aimbot.FOV.Show"] = "Show the targeting radius. This does not enable aim assistance.",
    ["Aimbot.Triggerbot.Enabled"] = "Automatically click at eligible targets. Input support and target filters affect availability.",
    ["Movement.Speed"] = "Override walking speed. Zero leaves the experience's speed unchanged.",
    ["Movement.JumpPower"] = "Override jump power. Zero leaves the experience's value unchanged.",
    ["Movement.WorldGravity"] = "Override gravity. Zero leaves the experience's gravity unchanged.",
    ["Movement.FlySpeed"] = "Set flight movement speed; flight must be enabled separately.",
    ["Movement.FreecamEnabled"] = "Move the camera independently of your character. Disable to return to normal camera control.",
    ["Movement.NoClip"] = "Allow client-side movement through obstacles where the experience permits it.",
    ["Camera.FOV"] = "Override camera field of view. Zero leaves the experience's value unchanged.",
    ["ESP.Enabled"] = "Enable player overlays. Choose which details to display with the other visual controls.",
    ["ESP.DepthMode"] = "Choose whether overlays remain visible through obstacles or respect occlusion.",
    ["Lighting.Mode"] = "Off restores normal lighting; the other modes choose fixed or changing lighting.",
    ["Performance.FpsCap"] = "Request an FPS limit. Zero removes the suite's cap; actual FPS depends on your device and environment.",
    ["Settings.PluginEnabled"] = "Enable the current experience's extra controls. Turning this off stops its active features.",
    ["Settings.RestoreOnLaunch"] = "Restore your saved settings when starting. Turn off to start from defaults.",
    ["Settings.StartupProfile"] = "Choose the named profile used at startup when restoration is enabled.",
    ["Settings.UIScale"] = "Resize the interface without changing gameplay settings.",
    ["Settings.MotionMode"] = "Off applies changes immediately. Subtle reduces motion. Full uses the complete animation treatment.",
    ["Settings.MotionSpeed"] = "Animation playback speed: 0.5x is slower, 1x is standard, and 2x is faster. Off ignores this setting.",
    ["Settings.Tooltips"] = "Show delayed hover help and tap-to-open question-mark help. Turn off to hide tooltips.",
    ["Settings.AutoRejoin"] = "Attempt to rejoin after a disconnect. Teleport support and server availability still apply.",
    ["Settings.TpToMouse"] = "Use Ctrl + click to teleport, or a world tap on touch devices, where permitted.",
    ["Game.ZombieFarm"] = "Follow and engage zombies automatically. Stopping leaves you at your current location; anti-fling is unavailable while active.",
})
local ACTIONS = table.freeze({
    ["Turn everything off"] = "Reset sliders and other values, disable every feature toggle, and keep the menu open. Saved profiles are not deleted.",
    ["Compare profiles"] = "Show a read-only comparison. This does not load either configuration or change your current settings.",
    ["Refresh compatibility check"] = "Refresh detected capabilities and fallback guidance without sending requests or changing your experience.",
    ["Clear all favorites"] = "Unpin controls from every tab. Their settings and actions are unchanged.",
    ["Load selected profile"] = "Replace current settings with the selected saved profile. Compare first to preview the differences.",
    ["Save named profile"] = "Save the current settings using the name in Save as. An existing profile with that name is overwritten.",
    ["Delete selected profile"] = "Delete the selected named profile. Built-in presets cannot be deleted.",
    ["Overwrite selected profile"] = "Replace the selected named profile with your current settings.",
    ["Create validated backup"] = "Save a backup of the current configuration for later recovery.",
    ["Restore validated backup"] = "Replace current settings with the last saved backup.",
})

return function(services: any): any
    local dom, theme, state = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("StateStore")
    local scope = services:Get("Disposer"):CreateChild("Tooltips")
    local defaults = state:GetDefaultSettings()
    local Tooltips = { _root = nil, _card = nil, _text = nil, _anchor = nil, _sticky = false }

    function Tooltips:Describe(label: string, path: string?, kind: string?, range: any?): string
        local text = (path and HELP[path]) or ACTIONS[label]
        if not text and path then
            if path:find("TeamCheck", 1, true) then text = "Exclude players on your team from targeting."
            elseif path:find("FriendCheck", 1, true) then text = "Exclude friends from targeting."
            elseif path:find("WhitelistCheck", 1, true) then text = "Exclude players in your whitelist from targeting."
            elseif path:find("VisCheck", 1, true) then text = "Require a clear line of sight to the target."
            elseif path:find("Rainbow", 1, true) then text = "Animate the display color. Disabling this uses the selected fixed or team color."
            elseif path:find("Prediction", 1, true) then text = "Adjust how far aiming anticipates target movement. Zero disables prediction on this axis." end
        end
        if not text then
            if kind == "Action" then text = `Run the {label} action. Review any confirmation or result shown afterward.`
            elseif kind == "Slider" then text = `Adjust {label} by dragging the track. Changes take effect immediately.`
            elseif kind == "Dropdown" then text = `Choose the {label} option from the list.`
            elseif kind == "Keybind" then text = "Record a keyboard or mouse shortcut. Escape clears the bind; hiding the menu cancels recording."
            elseif kind == "Color" then text = "Choose a color with the swatch or enter a six-digit hexadecimal color."
            elseif kind == "Textbox" then text = `Enter {label}. The value is applied when you finish editing.`
            else text = `Turn {label} on or off. Related feature controls may need to be enabled separately.` end
        end
        if range then text ..= `\nRange: {range.Min} to {range.Max}. Step: {range.Step}.` end
        if path then
            local default = defaults
            for part in path:gmatch("[^.]+") do default = if type(default) == "table" then default[part] else nil end
            if default ~= nil then
                local display = if typeof(default) == "EnumItem" then default.Name elseif type(default) == "boolean" then (if default then "On" else "Off") else tostring(default)
                if type(default) ~= "table" then text ..= `\nDefault: {display}` end
            end
        end
        return `{label}\n{text}`
    end

    function Tooltips:Hide()
        scope:Unbind("Hover")
        scope:Unbind("Anchor position"); scope:Unbind("Anchor size"); scope:Unbind("Viewport")
        self._anchor, self._hoverAnchor, self._sticky = nil, nil, false
        if self._card then self._card.Visible = false end
    end
    local function position()
        local anchor, card = Tooltips._anchor, Tooltips._card
        if not anchor or not anchor.Parent or not card then return end
        local screen = if Workspace.CurrentCamera then Workspace.CurrentCamera.ViewportSize else Vector2.new(1280, 720)
        local width = math.max(120, math.min(330, screen.X - 20))
        card.Size = UDim2.fromOffset(width, 0)
        local x = math.clamp(anchor.AbsolutePosition.X, 8, math.max(8, screen.X - width - 8))
        local y = anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y + 6
        if y + card.AbsoluteSize.Y > screen.Y - 8 then y = anchor.AbsolutePosition.Y - card.AbsoluteSize.Y - 6 end
        card.Position = UDim2.fromOffset(x, math.max(8, y))
    end
    function Tooltips:Show(anchor: GuiObject, text: string, sticky: boolean?)
        self:Hide()
        if scope:IsDisposed() or state:Peek("Settings.Tooltips") == false or state:Peek("Settings.MenuVisible") == false or not anchor.Parent then return end
        if not self._root then
            local root = dom:Create("ScreenGui", { Parent = services:Get("Environment"):GetSafeGuiParent(), Name = dom:RandomName(), DisplayOrder = 1200,
                ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
            theme:RegisterRoot(root)
            self._root = root
            local card = dom:Create("Frame", { Parent = root, BorderSizePixel = 0, Size = UDim2.fromOffset(330, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false })
            theme:BindToken(card, "BackgroundColor3", "Panel")
            theme:BindToken(dom:CreateStroke(card, theme:GetToken("Border")), "Color", "Border")
            dom:Create("UICorner", { Parent = card, CornerRadius = UDim.new(0, 6) }); dom:CreatePadding(card, 10)
            self._card = card
            self._text = dom:Create("TextLabel", { Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                TextWrapped = true, RichText = false, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left })
            theme:BindToken(self._text, "TextColor3", "Text")
            scope:ConnectImmediate(card:GetPropertyChangedSignal("AbsoluteSize"), position)
        end
        self._anchor, self._sticky = anchor, sticky == true
        self._text.Text = tostring(text)
        self._card.Visible = true
        position()
        scope:Bind("Anchor position", anchor:GetPropertyChangedSignal("AbsolutePosition"):Connect(position))
        scope:Bind("Anchor size", anchor:GetPropertyChangedSignal("AbsoluteSize"):Connect(position))
        if Workspace.CurrentCamera then scope:Bind("Viewport", Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(position)) end
    end
    function Tooltips:Attach(anchor: GuiObject, helpButton: GuiButton?, describe: () -> string, owner: any)
        owner:ConnectImmediate(anchor.MouseEnter, function()
            if Tooltips._sticky or state:Peek("Settings.Tooltips") == false or state:Peek("Settings.MenuVisible") == false then return end
            Tooltips._hoverAnchor = anchor
            scope:Unbind("Hover")
            scope:Bind("Hover", task.delay(0.45, function()
                scope:Unbind("Hover")
                if not scope:IsDisposed() and not owner:IsDisposed() then Tooltips:Show(anchor, describe()) end
            end))
        end)
        owner:ConnectImmediate(anchor.MouseLeave, function()
            if not Tooltips._sticky then Tooltips:Hide() end
        end)
        if helpButton then
            owner:ConnectImmediate(helpButton.Activated, function()
                if Tooltips._anchor == anchor and Tooltips._sticky then Tooltips:Hide()
                else Tooltips:Show(anchor, describe(), true) end
            end)
            owner:ConnectImmediate(helpButton.SelectionGained, function() Tooltips:Show(anchor, describe()) end)
            owner:ConnectImmediate(helpButton.SelectionLost, function() if not Tooltips._sticky then Tooltips:Hide() end end)
        end
        owner:Add(function() if Tooltips._anchor == anchor or Tooltips._hoverAnchor == anchor then Tooltips:Hide() end end)
    end
    scope:Add(state:Observe("Settings.Tooltips", function(value: boolean) if not value then Tooltips:Hide() end end))
    scope:Add(state:Observe("Settings.MenuVisible", function(value: boolean) if not value then Tooltips:Hide() end end))
    scope:Add(services:Get("EventBus"):Subscribe("TabSelected", function() Tooltips:Hide() end))
    scope:Add(function()
        Tooltips:Hide()
        if Tooltips._root then dom:DestroyInstance(Tooltips._root) end
        Tooltips._root, Tooltips._card, Tooltips._text, Tooltips._anchor = nil, nil, nil, nil
    end)
    function Tooltips:Destroy() scope:Dispose() end
    return Tooltips
end
