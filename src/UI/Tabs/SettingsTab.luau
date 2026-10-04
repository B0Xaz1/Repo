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
    local profileNames = config:ListProfiles()
    local selected = dropdown(profiles, "Profile", nil, profileNames)
    local name = textbox(profiles, "Save as", "My profile")
    textbox:CreateButton(profiles, "Save named profile", function() return config:Save(name.Box.Text) end)
    textbox:CreateButton(profiles, "Load selected profile", function() return config:Load(selected:Get() or "Default") end)
    textbox:CreateButton(profiles, "Overwrite selected profile", function() return config:Save(selected:Get() or "Default") end)
    textbox:CreateButton(profiles, "Delete selected profile", function() return config:Delete(selected:Get() or "Default") end)
    textbox:CreateButton(profiles, "Load Default preset", function() return config:Load("Default") end)
    textbox:CreateButton(profiles, "Turn everything off", function() return config:TurnEverythingOff() end)
    section:Info(profiles, "Turn everything off resets values to defaults and disables every toggle, including game plugins and restore-on-launch. The menu stays open; saved profiles are kept.")
    textbox:CreateButton(profiles, "Load Legit preset", function() return config:Load("Legit") end)
    textbox:CreateButton(profiles, "Load Rage preset", function() return config:Load("Rage") end)
    textbox:CreateButton(profiles, "Create validated backup", function() return config:Backup() end)
    textbox:CreateButton(profiles, "Restore validated backup", function() return config:RestoreBackup() end)
    if not environment.Capabilities.Files then
        section:Info(profiles, "File persistence is unavailable; use JSON to save profiles.")
    end
    local comparison = section:Create(tab.LeftCol, "Profile comparison")
    local function comparisonChoices()
        local choices = { "Current session" }
        for _, profile in ipairs(profileNames) do table.insert(choices, `Profile: {profile}`) end
        return choices
    end
    local report, page, stale = nil, 1, false
    local status, rows
    local function renderComparison()
        if not status then return end
        if not report then status:Set("Choose A and B, then compare. Nothing is loaded or saved."); return end
        local pages = math.max(1, math.ceil(#report.Changes / 8))
        page = math.clamp(page, 1, pages)
        status:Set(`A: {report.LeftChoice}\nB: {report.RightChoice}\n{#report.Changes} differences · Page {page}/{pages}{if stale then "\nSettings or profiles changed; compare again to refresh." else ""}`)
        local lines = {}
        for index = (page - 1) * 8 + 1, math.min(page * 8, #report.Changes) do
            local change = report.Changes[index]
            table.insert(lines, `{change.Path}\nA: {config:FormatComparisonValue(change.Before)}\nB: {config:FormatComparisonValue(change.After)}`)
        end
        rows:Set(if #lines == 0 then "No differences." else table.concat(lines, "\n\n"))
    end
    local function markStale()
        if report and not stale then stale = true; renderComparison() end
    end
    local compareA = dropdown(comparison, "Compare A", nil, comparisonChoices(), markStale)
    local compareB = dropdown(comparison, "Compare B", nil, comparisonChoices(), markStale)
    compareB:Set("Profile: Default", true)
    status = section:Info(comparison, "Choose A and B, then compare. Nothing is loaded or saved.")
    rows = section:Info(comparison, "Differences will appear here.")
    textbox:CreateButton(comparison, "Compare profiles", function()
        local function selectedProfile(control)
            local choice = control:Get()
            return if choice == "Current session" then nil else tostring(choice):sub(10)
        end
        local leftChoice, rightChoice = compareA:Get(), compareB:Get()
        local result, message = config:CompareProfiles(selectedProfile(compareA), selectedProfile(compareB))
        if not result then
            report, stale = nil, false
            status:Set(`Comparison unavailable: {message or "Select two profiles."}`)
            rows:Set("No comparison to display.")
            return false, message or "Select two profiles."
        end
        report, page, stale = result, 1, false
        report.LeftChoice, report.RightChoice = leftChoice, rightChoice
        renderComparison()
    end)
    textbox:CreateButton(comparison, "Previous comparison page", function() page -= 1; renderComparison() end)
    textbox:CreateButton(comparison, "Next comparison page", function() page += 1; renderComparison() end)
    section:Info(comparison, "Read-only snapshots. Built-in presets use the same defaults as loading. Legit and Rage keep your current interface and theme preferences. Access restrictions are still enforced when loading.")
    scope:Add(services:Get("EventBus"):Subscribe("ProfilesChanged", function()
        profileNames = config:ListProfiles(); selected:Refresh(profileNames, true)
        compareA:Refresh(comparisonChoices(), true); compareB:Refresh(comparisonChoices(), true); markStale()
    end))
    scope:Add(services:Get("EventBus"):Subscribe("StateChanged", markStale))

    local launch = section:Create(tab.LeftCol, "Launch behavior", "Settings")
    toggle(launch, "Restore settings on launch", "Settings.RestoreOnLaunch")
    textbox(launch, "Startup profile", "", nil, "Settings.StartupProfile")
    textbox:CreateButton(launch, "Pin selected profile for launch", function() return config:PinStartupProfile(selected:Get() or "Default") end)
    textbox:CreateButton(launch, "Clear pinned profile", function() state:Set("Settings.StartupProfile", ""); return true, "Launch will use the autosaved session" end)

    local gameAutoLoad = section:Create(tab.LeftCol, "Per-game auto-load", "Settings")
    local gameProfileStatus = section:Info(gameAutoLoad, config:GetGameProfileStatus())
    textbox:CreateButton(gameAutoLoad, "Save current settings to this game", function()
        if not config:ProfileExists(name.Box.Text) then
            local saved, saveMessage = config:Save(name.Box.Text)
            if not saved then return false, saveMessage end
        end
        local pinned, pinMessage = config:PinCurrentGameProfile(name.Box.Text, true)
        gameProfileStatus:Set(config:GetGameProfileStatus())
        return pinned, pinMessage
    end)
    textbox:CreateButton(gameAutoLoad, "Pin selected profile for this game", function()
        local ok, message = config:PinCurrentGameProfile(selected:Get() or "")
        gameProfileStatus:Set(config:GetGameProfileStatus())
        return ok, message
    end)
    textbox:CreateButton(gameAutoLoad, "Clear this game's profile", function()
        local ok, message = config:ClearCurrentGameProfile()
        gameProfileStatus:Set(config:GetGameProfileStatus())
        return ok, message
    end)
    section:Info(gameAutoLoad, "Save current settings to this game using the Save as name, or pin a saved profile selected above. This action creates a named seed only when missing and leaves an existing profile untouched. The game's saved session loads first on launch, then its pinned profile, then the global startup profile and autosaved session. Later edits stay in this experience's separate session and do not affect other games. Matching uses Universe ID (all places in that experience). Restore settings on launch must be enabled for auto-load.")
    local bus = services:Get("EventBus")
    scope:Add(bus:Subscribe("GameProfilesChanged", function() gameProfileStatus:Set(config:GetGameProfileStatus()) end))
    scope:Add(state:Observe("Settings.StartupProfile", function() gameProfileStatus:Set(config:GetGameProfileStatus()) end))
    scope:Add(state:Observe("Settings.RestoreOnLaunch", function() gameProfileStatus:Set(config:GetGameProfileStatus()) end))

    local share = section:Create(tab.LeftCol, "Import & export")
    textbox:CreateButton(share, "Open JSON share editor", function() load("src/UI/Modals/ConfigShareModal.luau", services):Show() end)
    textbox:CreateButton(share, "Import from clipboard", function() return config:Import("") end)
    local interface = section:Create(tab.LeftCol, "Interface & lifecycle", "Settings")
    slider(interface, "UI scale", "Settings.UIScale", 0.6, 1.5, 0.05, "x")
    dropdown(interface, "Animation style", "Settings.MotionMode", { "Off", "Subtle", "Full" })
    slider(interface, "Animation speed", "Settings.MotionSpeed", 0.5, 2, 0.1, "x")
    toggle(interface, "Show tooltips", "Settings.Tooltips")
    section:Info(interface, "Help appears only for advanced options and important actions. Hover a control marked ? or tap ? for details. Use ☆ to pin a control above the sections in its own tab. Favorites are saved with your configuration.")
    textbox:CreateButton(interface, "Clear all favorites", function() state:Set("Settings.Favorites", {}); return true, "All controls returned to their sections" end)
    toggle(interface, "Compact menu mode", "Settings.CompactMenu")
    toggle(interface, "Show menu button", "Settings.ShowMenuIcon")
    keybind(interface, "Menu hotkey", "Settings.MenuKeybind")
    keybind(interface, "Quick unload hotkey", "Settings.UnloadKeybind")
    section:Info(interface, "Click to bind. Press Escape to clear; hiding the menu cancels recording.")
    local hotkeys = section:Create(tab.RightCol, "Feature hotkeys", "Settings")
    for _, target in ipairs(services:Get("HotkeyService"):GetBindTargets()) do
        if target.Key ~= "Menu" then keybind(hotkeys, target.Label, `Settings.Binds.{target.Key}`) end
    end
    textbox:CreateButton(hotkeys, "Reset all hotkeys", function()
        local defaults = state:GetDefaultSettings().Settings.Binds
        for key, value in pairs(defaults) do state:Set(`Settings.Binds.{key}`, value) end
        state:Set("Settings.MenuKeybind", state:GetDefaultSettings().Settings.MenuKeybind)
        state:Set("Settings.UnloadKeybind", state:GetDefaultSettings().Settings.UnloadKeybind)
        return true, "All hotkeys reset"
    end)
    local appearance = section:Create(tab.RightCol, "Theme palette", "Theme")
    dropdown(appearance, "Theme preset", "Theme.ActivePreset", theme:GetPresetNames(), function(value: string) theme:SetPreset(value) end)
    local pickers = {}
    for _, token in ipairs(theme:GetTokenNames()) do pickers[token] = color(appearance, token, theme:GetToken(token), function(value: Color3) theme:UpdateToken(token, value) end) end
    scope:Add(services:Get("EventBus"):Subscribe("ThemeChanged", function()
        for token, picker in pairs(pickers) do picker:Set(theme:GetToken(token), true) end
    end))
    local compatibility = section:Create(tab.RightCol, "Compatibility checker")
    local compatibilityResult = section:Info(compatibility, "")
    local function refreshCompatibility()
        local result = services:Get("CompatibilityService"):GetReport()
        local lines = { `{result.Detected}/{result.Total} optional capabilities detected.`, result.Game, result.Notice }
        for _, entry in ipairs(result.Checks) do
            table.insert(lines, `{if entry.Available then "Detected" else "Unavailable"} · {entry.Name}\n{entry.Detail}`)
        end
        compatibilityResult:Set(table.concat(lines, "\n\n"))
    end
    textbox:CreateButton(compatibility, "Refresh compatibility check", refreshCompatibility)
    refreshCompatibility()
    local session = section:Create(tab.RightCol, "Session")
    section:Info(session, `Build {services.Version}`)
    textbox:CreateButton(session, "Relaunch this build", function() environment.Globals.B0XazRelaunch() end)
    textbox:CreateButton(session, "Unload & restore everything", function() environment.Globals.B0XazUnload() end)
    return { Name = tab.Name }
end
