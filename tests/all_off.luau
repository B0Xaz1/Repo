-- Exercise the real state/config services; only engine datatypes and storage are mocked.
local allOffStart = checks
local originalType = mock.type
mock.type = function(value)
    if type(value) == "table" and (rawget(value, "_type") == "EnumItem" or rawget(value, "_type") == "Color3") then return "userdata" end
    return type(value)
end
local resetOwner = Disposer.new("All Off tests")
local resetBus = factory("src/Core/EventBus.luau")(resetOwner)
local resetState = factory("src/Core/StateStore.luau")(resetBus, resetOwner)
local defaults = resetState:GetDefaultSettings()
local files, encoded, writes = {}, {}, {}
local sequence = 0
local oldEncode, oldDecode = gameServices.HttpService.JSONEncode, gameServices.HttpService.JSONDecode
function gameServices.HttpService:JSONEncode(value)
    sequence += 1
    local token = `json:{sequence}`
    encoded[token] = value
    return token
end
function gameServices.HttpService:JSONDecode(token) return assert(encoded[token], "Unknown test JSON") end
local failWrites = false
local env = { Capabilities = { Files = true }, Globals = {} }
function env:ReadFile(path) return files[path], if files[path] then nil else "Not found" end
function env:WriteFile(path, content)
    if failWrites then return false, "Test storage unavailable" end
    files[path] = content; table.insert(writes, path); return true
end
function env:ListFiles() return { "Configs/Keep.json" } end
local stoppedSpectate, stoppedFling = 0, 0
local resetServices = {
    Version = "test", Disposer = resetOwner, EventBus = resetBus, StateStore = resetState, Environment = env,
    PlayerTracker = { StopSpectate = function() stoppedSpectate += 1 end },
    LocomotionService = { StopFling = function() stoppedFling += 1 end },
}
function resetServices:Get(name) return assert(self[name], name) end
function resetServices:Has(name) return self[name] ~= nil end
local config = factory("src/Services/ConfigService.luau")(resetServices)
resetServices.ConfigService = config
local function enableAndChange(settings)
    for key, value in pairs(settings) do
        if typeof(value) == "boolean" then settings[key] = true
        elseif typeof(value) == "number" then settings[key] = value + 17
        elseif typeof(value) == "table" then enableAndChange(value) end
    end
end
local changed = resetState:GetDefaultSettings()
enableAndChange(changed)
changed.Settings.MenuVisible = false
changed.Settings.StartupProfile = "Keep"
changed.Theme.ActivePreset = "Paper"
changed.Theme.CustomTokens.Accent = Color3.new(1, 0, 0)
changed.Settings.Whitelist = { "ExamplePlayer" }
resetState:LoadSettingsSnapshot(changed)
files["Configs/Keep.json"], files["Configs/_backup.json"], files["Configs/_game_profiles.json"] = "named profile", "backup", "assignments"
local snapshotsSeen, sawAtomicSnapshot = 0, true
local hydrationConnection = resetBus:Subscribe("StateChanged", function(_path, _value, _old, metadata)
    if metadata and metadata.Hydrating then
        snapshotsSeen += 1
        sawAtomicSnapshot = sawAtomicSnapshot and resetState:Peek("Aimbot.Enabled") == false and resetState:Peek("Settings.PluginEnabled") == false
    end
end)
resetOwner:Add(hydrationConnection)
local function verifyDisabled(settings, original, prefix)
    for key, value in pairs(settings) do
        local path = if prefix == "" then key else `{prefix}.{key}`
        if typeof(value) == "boolean" then
            check(value == (path == "Settings.MenuVisible"), `All Off boolean: {path}`)
        elseif typeof(value) == "table" then
            verifyDisabled(value, original[key], path)
        else
            check(value == original[key], `All Off default value: {path}`)
        end
    end
end
local ok, message = config:TurnEverythingOff()
check(ok and message:find("toggles off", 1, true) ~= nil, "all-off action reports success")
verifyDisabled(resetState:GetSettingsSnapshot(), defaults, "")
check(snapshotsSeen > 0 and sawAtomicSnapshot, "all-off hydration notifies observers with the final disabled snapshot")
check(resetState:Peek("Lighting.Mode") == "Off" and resetState:Peek("Camera.FOV") == 0, "non-boolean overrides also turn off")
check(resetState:Peek("Settings.MenuKeybind") == Enum.KeyCode.RightShift and resetState:Peek("Settings.UnloadKeybind") == Enum.KeyCode.End, "menu remains accessible with default hotkeys")
check(next(resetState:Peek("Settings.Whitelist")) == nil and next(resetState:Peek("Theme.CustomTokens")) == nil, "all-off reset clears custom setting collections")
check(stoppedSpectate == 1 and stoppedFling == 1, "manual spectating and fling stop too")
check(config:GetActiveProfile() == "All Off", "session is labeled All Off")
check(files["Configs/Keep.json"] == "named profile" and files["Configs/_backup.json"] == "backup" and files["Configs/_game_profiles.json"] == "assignments", "named profiles, backup, and game assignments are untouched")
check(#writes == 1 and writes[1] == "Configs/_autoload.json", "global reset uses existing session persistence only")
check(resetState:GetDefaultSettings().ESP.Box and resetState:GetDefaultSettings().Settings.PluginEnabled, "built-in defaults were not mutated")
local notificationsBefore = snapshotsSeen
ok = config:TurnEverythingOff()
check(ok and snapshotsSeen == notificationsBefore, "repeated reset is idempotent without redundant state changes")
hydrationConnection:Disconnect()
config:Load("Default")
check(resetState:Peek("ESP.Box") == true and resetState:Peek("Settings.PluginEnabled") == true, "Default preset behavior is unchanged")
resetState:Set("ESP.Enabled", true)
config._activeGameProfileKey = "universe:42"
config._gameProfileAutosaveEnabled = true
local namedBefore = files["Configs/Keep.json"]
config:TurnEverythingOff()
check(files["Configs/_game_universe_42.json"] ~= nil and files["Configs/Keep.json"] == namedBefore, "assigned experience saves reset to its session without overwriting named profile")
local sessionJson = encoded[files["Configs/_game_universe_42.json"]]
check(sessionJson.Settings.ESP.Enabled == false and sessionJson.Settings.Settings.RestoreOnLaunch == false, "per-game snapshot reflects all-off state")
failWrites = true; env.Capabilities.Files = false
resetState:Set("Movement.Speed", 123)
ok = config:TurnEverythingOff()
check(ok and resetState:Peek("Movement.Speed") == 0 and config.Dirty, "reset still works in memory without file support and leaves persistence pending")

-- Preference persistence and read-only profile comparison use real normalization/serialization.
do
    failWrites = false; env.Capabilities.Files = true
    resetState:LoadSettingsSnapshot(defaults)
    resetState:Set("Settings.Favorites", { ["Combat|aim"] = true, ["Visuals|esp"] = true })
    resetState:Set("Settings.MotionMode", "Subtle"); resetState:Set("Settings.MotionSpeed", 1.5)
    resetState:Set("Settings.Tooltips", false)
    check(config:Save("Preferences"), "new preferences save through ordinary named profiles")
    resetState:LoadSettingsSnapshot(defaults)
    check(config:Load("Preferences"), "new preferences restore through profile loading")
    check(resetState:Peek("Settings.Favorites")["Combat|aim"] and resetState:Peek("Settings.Favorites")["Visuals|esp"], "per-tab favorite identities round-trip through JSON")
    check(resetState:Peek("Settings.MotionMode") == "Subtle" and resetState:Peek("Settings.MotionSpeed") == 1.5 and not resetState:Peek("Settings.Tooltips"), "motion and tooltip preferences round-trip")
    local normalized = resetState:NormalizeSettingsSnapshot({ Settings = { MotionMode = "Unknown", MotionSpeed = 99,
        Favorites = { Valid = true, Invalid = false, [8] = true, TooLong = "true", [string.rep("x", 513)] = true } } })
    check(normalized.Settings.MotionMode == "Full" and normalized.Settings.MotionSpeed == 2, "import normalizes unknown motion mode and clamps speed")
    check(normalized.Settings.Favorites.Valid and next(normalized.Settings.Favorites, "Valid") == nil, "import ignores malformed favorite entries")
    normalized = resetState:NormalizeSettingsSnapshot({ Settings = { MotionSpeed = -20 } })
    check(normalized.Settings.MotionSpeed == 0.5, "import clamps motion speed minimum")
    normalized = resetState:NormalizeSettingsSnapshot({ Settings = { MotionSpeed = 0 / 0, Favorites = "bad" } })
    check(normalized.Settings.MotionSpeed == 1 and next(normalized.Settings.Favorites) == nil, "nonfinite motion speeds and wrong favorite types use safe defaults")
    normalized = resetState:NormalizeSettingsSnapshot({})
    check(normalized.Settings.MotionMode == "Full" and normalized.Settings.MotionSpeed == 1 and normalized.Settings.Tooltips, "legacy profiles gain safe preference defaults")
    local revision, events = resetState._revision, 0
    local observed = resetBus:Subscribe("StateChanged", function() events += 1 end)
    local writesBefore, activeBefore, dirtyBefore = #writes, config:GetActiveProfile(), config.Dirty
    local same = config:CompareProfiles(nil, "Preferences")
    check(same and #same.Changes == 0, "current versus saved identical profile has no differences")
    same = config:CompareProfiles("Preferences", "Preferences")
    check(#same.Changes == 0, "same named profile comparison is empty")
    same = config:CompareProfiles("Default", "Default")
    check(#same.Changes == 0, "same built-in comparison is empty")
    same = config:CompareProfiles(nil, nil)
    check(#same.Changes == 0 and same.Left == "Current session", "current-session sentinel works on both sides")
    local result = config:CompareProfiles("Default", "Rage")
    check(#result.Changes > 8 and result.Left == "Default" and result.Right == "Rage", "built-in preset comparison reports labeled differences")
    local foundEnable = false
    for index, change in ipairs(result.Changes) do
        if index > 1 then check(result.Changes[index - 1].Path < change.Path, "comparison paths are stable and sorted") end
        if change.Path == "Aimbot.Enabled" then foundEnable = change.Before == false and change.After == true end
    end
    check(foundEnable, "comparison retains typed before and after values")
    local legit = config:CompareProfiles(nil, "Legit")
    local preferencesPreserved = true
    for _, change in ipairs(legit.Changes) do
        if change.Path:match("^Settings%.") or change.Path:match("^Theme%.") then preferencesPreserved = false end
    end
    check(preferencesPreserved, "Legit comparison preserves current interface and theme as actual loading does")
    local noResult, compareError = config:CompareProfiles("Missing", "Default")
    check(not noResult and compareError, "missing comparison profile returns error")
    files["Configs/Bad.json"] = "invalid JSON"
    noResult, compareError = config:CompareProfiles("Default", "Bad")
    check(not noResult and compareError:find("Invalid profile", 1, true), "malformed comparison profile returns parse error")
    files["Configs/Legacy.json"] = gameServices.HttpService:JSONEncode({ Settings = { MotionMode = "bad", MotionSpeed = -1 }, Chams = { DepthMode = "Occluded" } })
    result = config:CompareProfiles("Default", "Legacy")
    local foundSpeed, foundAlias = false, false
    for _, change in ipairs(result.Changes) do
        if change.Path == "Settings.MotionSpeed" then foundSpeed = change.After == 0.5 end
        if change.Path == "ESP.DepthMode" then foundAlias = change.After == "Occluded" end
    end
    check(foundSpeed and foundAlias, "comparison shares load-time clamping and legacy alias normalization")
    check(resetState._revision == revision and events == 0, "all comparisons and normalization are read-only with no state notifications")
    check(#writes == writesBefore and config:GetActiveProfile() == activeBefore and config.Dirty == dirtyBefore, "comparison never saves, changes active profile, or dirties autosave")
    check(resetState:Peek("Settings.Favorites")["Combat|aim"] and not resetState:Peek("Settings.Tooltips"), "comparison preserves current preferences")
    observed:Disconnect()
    check(config:FormatComparisonValue(true) == "On" and config:FormatComparisonValue(false) == "Off", "comparison formats booleans legibly")
    check(config:FormatComparisonValue(Color3.new(1, 0, 0)) == "#FF0000" and config:FormatComparisonValue(Enum.KeyCode.F) == "F", "comparison formats colors and keybinds")
    check(config:FormatComparisonValue(nil) == "Not set" and #config:FormatComparisonValue(string.rep("x", 200)) == 100, "comparison handles missing and long values")
    env.Capabilities.Files = false
    check(config:CompareProfiles("Default", "Rage") ~= nil, "built-in comparisons work without file support")
    local checker = factory("src/Services/CompatibilityService.luau")(resetServices)
    local first = checker:GetReport()
    check(first.Detected == 0 and first.Total >= 10 and #first.Checks == first.Total, "checker reports missing optional capabilities with fallbacks")
    check(first.Notice:find("restricted at runtime", 1, true), "checker does not equate API detection with permission")
    env.Capabilities = { Files = true, Drawing = true, FpsCap = true }
    local nextReport = checker:GetReport()
    check(nextReport.Detected == 3 and first.Detected == 0, "manual compatibility refresh returns a fresh report")
    resetServices.PluginManager = { IsGameSupported = function() return true end, GetActivePluginName = function() return "Example" end }
    nextReport = checker:GetReport()
    check(nextReport.Game:find("Example", 1, true), "checker includes matching game controls without promising functionality")
    resetServices.PluginManager = nil
    check(#writes == writesBefore and resetState._revision == revision, "compatibility checker performs no storage or state side effects")
    failWrites = true; env.Capabilities.Files = false
end

-- Verify the actual Settings tab exposes the action with the profile controls.
local buttons, buttonParents, dropdowns, infoRows, infoParents = {}, {}, {}, {}, {}
local textbox = setmetatable({ CreateButton = function(_, parent, label, callback)
    buttons[label], buttonParents[label] = callback, parent
end }, { __call = function() return { Box = { Text = "Keep" } } end })
local controls = {
    ["Section"] = { Create = function(_, _parent, title) return title end, Info = function(_, parent, text)
        local row = { Text = text, Set = function(self, value) self.Text = value end }
        table.insert(infoRows, row); infoParents[row] = parent; return row
    end },
    ["Textbox"] = textbox,
    ["Dropdown"] = function(_parent, label, _default, options, callback)
        local control = { Value = options[1], Options = options }
        function control:Get() return self.Value end
        function control:Set(value, silent) self.Value = value; if callback and not silent then callback(value) end end
        function control:Refresh(values, preserve) self.Options = values; if not preserve or not table.find(values, self.Value) then self:Set(values[1]) end end
        dropdowns[label] = control; return control
    end,
    ["Toggle"] = function() end, ["Slider"] = function() end, ["Keybind"] = function() end, ["ColorPicker"] = function() end,
}
resetServices.Require = function(path) return assert(controls[path:match("/([^/]+)%.luau$")], path) end
resetServices.HotkeyService = { GetBindTargets = function() return {} end }
resetServices.CompatibilityService = factory("src/Services/CompatibilityService.luau")(resetServices)
resetServices.ThemeEngine = { GetPresetNames = function() return { "Midnight" } end, GetTokenNames = function() return {} end }
factory("src/UI/Tabs/SettingsTab.luau")(resetServices, { Name = "Settings", LeftCol = {}, RightCol = {} })
check(buttons["Turn everything off"] ~= nil and buttonParents["Turn everything off"] == "Config profiles", "reset action is in Settings config profiles")
resetState:Set("ESP.Enabled", true); resetState:Set("Movement.FlySpeed", 123)
local resetOK = buttons["Turn everything off"]()
check(resetOK and resetState:Peek("ESP.Enabled") == false and resetState:Peek("Movement.FlySpeed") == defaults.Movement.FlySpeed, "Settings action invokes the real reset")
do
    local function comparisonText()
        local texts = {}
        for _, row in ipairs(infoRows) do if infoParents[row] == "Profile comparison" then table.insert(texts, row.Text) end end
        return table.concat(texts, "\n")
    end
    local revision, writesBefore = resetState._revision, #writes
    check(dropdowns["Compare A"]:Get() == "Current session" and dropdowns["Compare B"]:Get() == "Profile: Default", "comparison UI starts with current session versus Default")
    buttons["Compare profiles"]()
    local firstPage = comparisonText()
    check(firstPage:find("A: Current session", 1, true) and firstPage:find("B: Profile: Default", 1, true), "Settings comparison displays both selected sources")
    buttons["Next comparison page"]()
    check(comparisonText() ~= firstPage and comparisonText():find("Page 2/", 1, true), "comparison UI paginates differences")
    buttons["Previous comparison page"]()
    check(comparisonText() == firstPage, "comparison previous page restores stable results")
    buttons["Previous comparison page"]()
    check(comparisonText() == firstPage, "comparison pagination clamps at beginning")
    check(resetState._revision == revision and #writes == writesBefore, "comparison UI and pagination never apply or save settings")
    dropdowns["Compare B"]:Set("Profile: Rage")
    check(comparisonText():find("compare again", 1, true), "changing comparison source marks displayed snapshot stale")
    buttons["Compare profiles"]()
    check(not comparisonText():find("compare again", 1, true), "new comparison clears stale status")
    resetState:Set("Movement.Speed", 88)
    check(comparisonText():find("compare again", 1, true), "current state changes mark comparison stale once")
    dropdowns["Compare B"]:Set("Profile: Missing")
    buttons["Compare profiles"]()
    check(comparisonText():find("Comparison unavailable", 1, true) and not comparisonText():find("A: Current session", 1, true), "comparison failure clears previous result instead of showing stale data")
    dropdowns["Compare A"]:Set("Current session"); dropdowns["Compare B"]:Set("Current session")
    buttons["Compare profiles"]()
    check(comparisonText():find("No differences", 1, true), "UI handles identical selections clearly")
    resetBus:Publish("ProfilesChanged")
    check(table.find(dropdowns["Compare B"].Options, "Profile: Keep") and comparisonText():find("compare again", 1, true), "profile list events refresh comparison selectors and mark snapshots stale")
    check(buttons["Refresh compatibility check"] and buttonParents["Refresh compatibility check"] == "Compatibility checker", "compatibility report and manual refresh are in Settings")
    revision, writesBefore = resetState._revision, #writes
    buttons["Refresh compatibility check"]()
    check(resetState._revision == revision and #writes == writesBefore, "compatibility UI refresh has no state or storage side effects")
    resetState:Set("Settings.Favorites", { test = true }); buttons["Clear all favorites"]()
    check(next(resetState:Peek("Settings.Favorites")) == nil, "Settings clears favorites through persistent state")
    check(dropdowns["Animation style"] ~= nil, "motion style is exposed in existing interface settings")
end
resetOwner:Dispose()
mock.type = originalType
gameServices.HttpService.JSONEncode, gameServices.HttpService.JSONDecode = oldEncode, oldDecode
check(connectionCount() == 0 and next(waiting) == nil, "reset tests leave no callbacks or scheduled work")
print(`PASS: {checks - allOffStart} state/config/settings assertions ({checks} total)`)
