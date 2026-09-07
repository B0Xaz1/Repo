--!nonstrict
return function(services: any, tab: any): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)
    local keybind = load("src/UI/Components/Keybind.luau", services)
    local color = load("src/UI/Components/ColorPicker.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)
    local state, config, theme, keys, environment = services:Get("StateStore"), services:Get("ConfigService"), services:Get("ThemeEngine"), services:Get("KeyService"), services:Get("Environment")
    local scope = services:Get("Disposer"):CreateChild("Settings tab")
    local profiles = section:Create(tab.LeftCol, "Config profiles")
    local selected = dropdown(profiles, "Profile", nil, config:ListProfiles())
    local name = textbox(profiles, "Save as", "My profile")
    textbox:CreateButton(profiles, "Save named profile", function() return config:Save(name.Box.Text) end, 0)
    textbox:CreateButton(profiles, "Load selected profile", function() return config:Load(selected:Get() or "Default") end, 0)
    textbox:CreateButton(profiles, "Overwrite selected profile", function() return config:Save(selected:Get() or "Default") end, 0)
    textbox:CreateButton(profiles, "Delete selected profile", function() return config:Delete(selected:Get() or "Default") end, 0)
    scope:Add(services:Get("EventBus"):Subscribe("ProfilesChanged", function() selected:Refresh(config:ListProfiles(), true) end))
    section:Info(profiles, if environment.Capabilities.Files then "Autosave flushes dirty state every 1.5 seconds. Default is a read-only reset profile."
        else "File persistence is unavailable. Settings work for this session; use the JSON editor to copy/paste profiles manually.")
    local launch = section:Create(tab.LeftCol, "Launch behavior")
    toggle(launch, "Restore settings on launch", "Settings.RestoreOnLaunch", nil, 0)
    textbox(launch, "Startup profile", "", nil, "Settings.StartupProfile", 0)
    textbox:CreateButton(launch, "Pin selected profile for launch", function() return config:PinStartupProfile(selected:Get() or "Default") end, 0)
    textbox:CreateButton(launch, "Clear pinned profile", function() state:Set("Settings.StartupProfile", ""); return true, "Launch will use the autosaved session" end, 0)
    section:Info(launch, "Restore off → no previous feature state. Otherwise: pinned profile → autosaved session → fresh defaults.")
    local share = section:Create(tab.LeftCol, "Import & export")
    textbox:CreateButton(share, "Open JSON share editor", function() load("src/UI/Modals/ConfigShareModal.luau", services):Show() end, 0)
    textbox:CreateButton(share, "Import from clipboard", function() return config:Import("") end, 0)
    local interface = section:Create(tab.LeftCol, "Interface & lifecycle")
    slider(interface, "UI scale", "Settings.UIScale", 0.6, 1.5, 0.05, "×", nil, 0)
    keybind(interface, "Menu hotkey", "Settings.MenuKeybind", nil, 0)
    keybind(interface, "Quick unload hotkey", "Settings.UnloadKeybind", nil, 0)
    section:Info(interface, "Click a bind to record. Escape cancels and unbinds. Hotkeys ignore focused textboxes. B0XazUnload() remains available in the console.")
    local hotkeys = section:Create(tab.RightCol, "Feature hotkeys")
    for _, target in ipairs(services:Get("HotkeyService"):GetBindTargets()) do
        if target.Key ~= "Menu" then keybind(hotkeys, target.Label, "Settings.Binds." .. target.Key, nil, 0) end
    end
    section:Info(hotkeys, "Bindings can be edited at any tier; a locked feature remains inert and explains its required tier.")
    local appearance = section:Create(tab.RightCol, "Theme palette")
    dropdown(appearance, "Theme preset", "Theme.ActivePreset", theme:GetPresetNames(), function(value: string) theme:SetPreset(value) end, 0)
    local pickers = {}
    for _, token in ipairs(theme:GetTokenNames()) do pickers[token] = color(appearance, token, theme:GetToken(token), function(value: Color3) theme:UpdateToken(token, value) end, 0) end
    scope:Add(services:Get("EventBus"):Subscribe("ThemeChanged", function()
        for token, picker in pairs(pickers) do picker:Set(theme:GetToken(token), true) end
    end))
    local license = section:Create(tab.RightCol, "License & session")
    local licenseInfo = section:Info(license, keys:GetTierName() .. "  ·  " .. keys:GetMaskedKey())
    scope:Add(services:Get("EventBus"):Subscribe("TierChanged", function() licenseInfo:Set(keys:GetTierName() .. "  ·  " .. keys:GetMaskedKey()) end))
    section:Info(license, "Build " .. services.Version .. "\nSource ref: " .. tostring(environment.Globals.B0XazRef or "custom URL"))
    textbox:CreateButton(license, "Log out & change license", function()
        local ok, message = keys:ClearKey()
        if not ok then services:Get("EventBus"):Publish("Notify", "Logged out for this session", "Could not erase the saved key: " .. tostring(message)) end
        load("src/UI/Modals/KeyAuthModal.luau", services):Show(function(tier: number) state:SetTier(tier) end)
    end, 0)
    textbox:CreateButton(license, "Relaunch this build", function() environment.Globals.B0XazRelaunch() end, 0)
    textbox:CreateButton(license, "Unload & restore everything", function() environment.Globals.B0XazUnload() end, 0)
    return { Name = tab.Name }
end
