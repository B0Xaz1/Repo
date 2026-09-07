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
    local state, config, theme, environment = services:Get("StateStore"), services:Get("ConfigService"), services:Get("ThemeEngine"), services:Get("Environment")
    local scope = services:Get("Disposer"):CreateChild("Settings tab")
    local profiles = section:Create(tab.LeftCol, "Config profiles")
    local selected = dropdown(profiles, "Profile", nil, config:ListProfiles())
    local name = textbox(profiles, "Save as", "My profile")
    textbox:CreateButton(profiles, "Save named profile", function() return config:Save(name.Box.Text) end)
    textbox:CreateButton(profiles, "Load selected profile", function() return config:Load(selected:Get() or "Default") end)
    textbox:CreateButton(profiles, "Overwrite selected profile", function() return config:Save(selected:Get() or "Default") end)
    textbox:CreateButton(profiles, "Delete selected profile", function() return config:Delete(selected:Get() or "Default") end)
    textbox:CreateButton(profiles, "Load Default preset", function() return config:Load("Default") end)
    textbox:CreateButton(profiles, "Load Legit preset", function() return config:Load("Legit") end)
    textbox:CreateButton(profiles, "Load Rage preset", function() return config:Load("Rage") end)
    scope:Add(services:Get("EventBus"):Subscribe("ProfilesChanged", function() selected:Refresh(config:ListProfiles(), true) end))
    section:Info(profiles, if environment.Capabilities.Files then "Autosave flushes dirty state every 1.5 seconds. Default, Legit, and Rage are built-in. Default resets everything; Legit/Rage keep your theme and hotkeys."
        else "File persistence is unavailable. Built-in Default/Legit/Rage still load. Use the JSON editor to copy/paste other profiles.")
    local launch = section:Create(tab.LeftCol, "Launch behavior")
    toggle(launch, "Restore settings on launch", "Settings.RestoreOnLaunch")
    textbox(launch, "Startup profile", "", nil, "Settings.StartupProfile")
    textbox:CreateButton(launch, "Pin selected profile for launch", function() return config:PinStartupProfile(selected:Get() or "Default") end)
    textbox:CreateButton(launch, "Clear pinned profile", function() state:Set("Settings.StartupProfile", ""); return true, "Launch will use the autosaved session" end)
    section:Info(launch, "Restore off -> no previous feature state. Otherwise: pinned profile -> autosaved session -> fresh defaults.")
    local share = section:Create(tab.LeftCol, "Import & export")
    textbox:CreateButton(share, "Open JSON share editor", function() load("src/UI/Modals/ConfigShareModal.luau", services):Show() end)
    textbox:CreateButton(share, "Import from clipboard", function() return config:Import("") end)
    local interface = section:Create(tab.LeftCol, "Interface & lifecycle")
    slider(interface, "UI scale", "Settings.UIScale", 0.6, 1.5, 0.05, "x")
    keybind(interface, "Menu hotkey", "Settings.MenuKeybind")
    keybind(interface, "Quick unload hotkey", "Settings.UnloadKeybind")
    section:Info(interface, "Click a bind to record. Escape cancels and unbinds. Hotkeys ignore focused textboxes. B0XazUnload() remains available in the console.")
    local hotkeys = section:Create(tab.RightCol, "Feature hotkeys")
    for _, target in ipairs(services:Get("HotkeyService"):GetBindTargets()) do
        if target.Key ~= "Menu" then keybind(hotkeys, target.Label, "Settings.Binds." .. target.Key) end
    end
    section:Info(hotkeys, "All feature bindings are available immediately and ignore focused textboxes while recording.")
    local appearance = section:Create(tab.RightCol, "Theme palette")
    dropdown(appearance, "Theme preset", "Theme.ActivePreset", theme:GetPresetNames(), function(value: string) theme:SetPreset(value) end)
    local pickers = {}
    for _, token in ipairs(theme:GetTokenNames()) do pickers[token] = color(appearance, token, theme:GetToken(token), function(value: Color3) theme:UpdateToken(token, value) end) end
    scope:Add(services:Get("EventBus"):Subscribe("ThemeChanged", function()
        for token, picker in pairs(pickers) do picker:Set(theme:GetToken(token), true) end
    end))
    local session = section:Create(tab.RightCol, "Session")
    section:Info(session, "Build " .. services.Version .. "\nSource ref: " .. tostring(environment.Globals.B0XazRef or "custom URL"))
    section:Info(session, "All controls are available in this build. There is no key entry, account check, device identifier, or gated feature level.")
    textbox:CreateButton(session, "Relaunch this build", function() environment.Globals.B0XazRelaunch() end)
    textbox:CreateButton(session, "Unload & restore everything", function() environment.Globals.B0XazUnload() end)
    return { Name = tab.Name }
end
