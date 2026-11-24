local HttpService = game:GetService("HttpService")

local CONFIG = table.freeze({
    MAX_JSON_BYTES = 1024 * 1024,
    MAX_NESTING_DEPTH = 40,
    MAX_NAME_LENGTH = 64,
    AUTOSAVE_FILE = "Configs/_autoload.json",
    BACKUP_FILE = "Configs/_backup.json",
    AUTOSAVE_INTERVAL = 1.5,
    BUILTIN_ORDER = { "default", "closet", "legit", "rage" },
    BUILTIN_LABELS = { default = "Default", closet = "Closet", legit = "Legit", rage = "Rage" },
})

return function(services: any): any
    local environment, state = services:Get("Environment"), services:Get("StateStore")
    local bus, scope = services:Get("EventBus"), services:Get("Disposer"):CreateChild("ConfigService")
    local ConfigService = { Dirty = false, _isLoading = false, _initialized = false, _activeProfile = "Default", _applyingLaunch = false }

    local function setActiveProfile(name: string)
        ConfigService._activeProfile = name
        bus:Publish("ActiveProfileChanged", name)
    end

    local function serialize(value: any, depth: number?): any
        local level = depth or 0
        assert(level < CONFIG.MAX_NESTING_DEPTH)
        local kind = typeof(value)
        if kind == "Color3" then return { __type = "Color3", r = value.R, g = value.G, b = value.B } end
        if kind == "EnumItem" then return { __type = "EnumItem", enum = (tostring(value.EnumType):gsub("^Enum%.", "")), name = value.Name } end
        if type(value) ~= "table" then return value end
        local result = {}
        for key, child in pairs(value) do result[key] = serialize(child, level + 1) end
        return result
    end

    local function deserialize(value: any, depth: number?): any
        local level = depth or 0
        assert(level < CONFIG.MAX_NESTING_DEPTH)
        if type(value) ~= "table" then return value end
        if value.__type == "Color3" then
            for _, key in ipairs({ "r", "g", "b" }) do
                assert(type(value[key]) == "number" and value[key] == value[key] and math.abs(value[key]) < math.huge, "Invalid Color3")
            end
            return Color3.new(math.clamp(value.r, 0, 1), math.clamp(value.g, 0, 1), math.clamp(value.b, 0, 1))
        elseif value.__type == "EnumItem" then
            local name = (tostring(value.enum):gsub("^Enum%.", ""))
            local ok, item = pcall(function() return (Enum :: any)[name][value.name] end)
            assert(ok and typeof(item) == "EnumItem")
            return item
        end
        local result = {}
        for key, child in pairs(value) do result[key] = deserialize(child, level + 1) end
        return result
    end

    local function decode(json: string): any
        assert(#json <= CONFIG.MAX_JSON_BYTES, "Config exceeds the 1 MiB safety limit")
        local value = HttpService:JSONDecode(json)
        assert(type(value) == "table", "Config must be a JSON object")
        if value.Format == 1 then assert(type(value.Settings) == "table", "Config is missing Settings"); value = value.Settings end
        return deserialize(value)
    end

    local function encode(snapshot: any): string
        return HttpService:JSONEncode({ Format = 1, Version = services.Version, Settings = serialize(snapshot) })
    end

    local function sanitize(name: string): string
        return (tostring(name):gsub('[/\\%.:%*%?<>|"%z\1-\31\127]', ""):gsub("^%s+", ""):gsub("%s+$", "")):sub(1, CONFIG.MAX_NAME_LENGTH)
    end

    local function builtinKey(name: string): string?
        local key = string.lower(sanitize(name))
        return if CONFIG.BUILTIN_LABELS[key] then key else nil
    end

    local function buildBuiltin(key: string): any
        local snapshot = state:GetDefaultSettings()
        if key == "closet" then
            -- Stream-proof / replay-safe soft assist: tight invisible FOV, torso targeting, high
            -- smoothing with subtle micro-shake, break-on-pull, and occluded low-noise ESP.
            snapshot.Aimbot.Enabled, snapshot.Aimbot.UseCamera = true, true
            snapshot.Aimbot.LockMode, snapshot.Aimbot.Hitpart = "Hold", "UpperTorso"
            snapshot.Aimbot.Smoothness, snapshot.Aimbot.ShakeIntensity = 18, 0.12
            snapshot.Aimbot.StickyAim, snapshot.Aimbot.UnlockOnDeath = false, true
            snapshot.Aimbot.BreakOnPull, snapshot.Aimbot.MaxLockRadius = true, 65
            snapshot.Aimbot.Prediction = { Horizontal = 0.04, Vertical = 0.02 }
            snapshot.Aimbot.TeamCheck, snapshot.Aimbot.VisCheck = true, true
            snapshot.Aimbot.FriendCheck, snapshot.Aimbot.WhitelistCheck, snapshot.Aimbot.ForceFieldCheck = true, true, true
            snapshot.Aimbot.MaxDistance = 450
            snapshot.Aimbot.FOV.Size, snapshot.Aimbot.FOV.Show = 42, false
            snapshot.Aimbot.Triggerbot.Enabled, snapshot.Aimbot.Triggerbot.Delay = false, 0.18
            snapshot.Aimbot.Triggerbot.TeamCheck, snapshot.Aimbot.Triggerbot.VisCheck = true, true
            snapshot.Aimbot.Triggerbot.FriendCheck, snapshot.Aimbot.Triggerbot.WhitelistCheck, snapshot.Aimbot.Triggerbot.ForceFieldCheck = true, true, true
            snapshot.Aimbot.Triggerbot.MaxDistance = 350
            snapshot.ESP.Enabled, snapshot.ESP.Box, snapshot.ESP.BoxStyle = true, true, "Corner"
            snapshot.ESP.Name, snapshot.ESP.Distance, snapshot.ESP.Tool = true, true, false
            snapshot.ESP.Health, snapshot.ESP.HealthBar, snapshot.ESP.ActivityStatus = false, false, false
            snapshot.ESP.UseTeamColor, snapshot.ESP.DepthMode, snapshot.ESP.MaxDistance = true, "Occluded", 450
            snapshot.Chams.Enabled = false
            snapshot.Extras.AntiFling.Enabled, snapshot.Extras.AntiFling.SnapBack = true, true
        elseif key == "legit" then
            -- Natural competitive setup: responsive hold-to-aim tracking with a subtle FOV ring,
            -- full safety/visibility checks, human-reaction triggerbot settings, and clean info ESP.
            snapshot.Aimbot.Enabled, snapshot.Aimbot.UseCamera = true, true
            snapshot.Aimbot.LockMode, snapshot.Aimbot.Hitpart = "Hold", "Head"
            snapshot.Aimbot.Smoothness, snapshot.Aimbot.ShakeIntensity = 10, 0.08
            snapshot.Aimbot.StickyAim, snapshot.Aimbot.UnlockOnDeath = true, true
            snapshot.Aimbot.BreakOnPull, snapshot.Aimbot.MaxLockRadius = true, 120
            snapshot.Aimbot.Prediction = { Horizontal = 0.06, Vertical = 0.03 }
            snapshot.Aimbot.TeamCheck, snapshot.Aimbot.VisCheck = true, true
            snapshot.Aimbot.FriendCheck, snapshot.Aimbot.WhitelistCheck, snapshot.Aimbot.ForceFieldCheck = true, true, true
            snapshot.Aimbot.MaxDistance = 900
            snapshot.Aimbot.FOV.Size, snapshot.Aimbot.FOV.Show, snapshot.Aimbot.FOV.Thickness = 80, true, 1
            snapshot.Aimbot.Triggerbot.Enabled, snapshot.Aimbot.Triggerbot.Delay = false, 0.12
            snapshot.Aimbot.Triggerbot.TeamCheck, snapshot.Aimbot.Triggerbot.VisCheck = true, true
            snapshot.Aimbot.Triggerbot.FriendCheck, snapshot.Aimbot.Triggerbot.WhitelistCheck, snapshot.Aimbot.Triggerbot.ForceFieldCheck = true, true, true
            snapshot.Aimbot.Triggerbot.MaxDistance = 750
            snapshot.ESP.Enabled, snapshot.ESP.Box, snapshot.ESP.BoxStyle = true, true, "Corner"
            snapshot.ESP.Name, snapshot.ESP.Distance, snapshot.ESP.Tool = true, true, true
            snapshot.ESP.Health, snapshot.ESP.HealthBar, snapshot.ESP.ActivityStatus = true, false, false
            snapshot.ESP.UseTeamColor, snapshot.ESP.DepthMode, snapshot.ESP.MaxDistance = true, "AlwaysOnTop", 1200
            snapshot.Chams.Enabled = false
            snapshot.Extras.AntiFling.Enabled, snapshot.Extras.AntiFling.SnapBack = true, true
        elseif key == "rage" then
            -- Maximum combat aggression without Friendly-Fire / spawn-shield waste: instant head
            -- lock, wide FOV, sticky tracking, zero-delay triggerbot on visible live enemies,
            -- expanded hitboxes, full wall-penetrating ESP + chams, fullbright, and anti-fling.
            snapshot.Aimbot.Enabled, snapshot.Aimbot.UseCamera = true, true
            snapshot.Aimbot.LockMode, snapshot.Aimbot.Hitpart = "Hold", "Head"
            snapshot.Aimbot.Smoothness, snapshot.Aimbot.ShakeIntensity = 1, 0
            snapshot.Aimbot.StickyAim, snapshot.Aimbot.UnlockOnDeath = true, false
            snapshot.Aimbot.BreakOnPull, snapshot.Aimbot.MaxLockRadius = false, 1000
            snapshot.Aimbot.Prediction = { Horizontal = 0.12, Vertical = 0.08 }
            snapshot.Aimbot.TeamCheck, snapshot.Aimbot.VisCheck = true, false
            snapshot.Aimbot.FriendCheck, snapshot.Aimbot.WhitelistCheck, snapshot.Aimbot.ForceFieldCheck = false, true, true
            snapshot.Aimbot.MaxDistance = 10000
            snapshot.Aimbot.FOV.Size, snapshot.Aimbot.FOV.Show, snapshot.Aimbot.FOV.Thickness = 500, true, 1
            snapshot.Aimbot.Triggerbot.Enabled, snapshot.Aimbot.Triggerbot.Delay = true, 0
            snapshot.Aimbot.Triggerbot.TeamCheck, snapshot.Aimbot.Triggerbot.VisCheck = true, true
            snapshot.Aimbot.Triggerbot.FriendCheck, snapshot.Aimbot.Triggerbot.WhitelistCheck, snapshot.Aimbot.Triggerbot.ForceFieldCheck = false, true, true
            snapshot.Aimbot.Triggerbot.MaxDistance = 5000
            snapshot.ESP.Enabled, snapshot.ESP.Box, snapshot.ESP.BoxStyle = true, true, "Full"
            snapshot.ESP.Name, snapshot.ESP.Distance, snapshot.ESP.Tool = true, true, true
            snapshot.ESP.Health, snapshot.ESP.HealthBar, snapshot.ESP.ActivityStatus = true, true, true
            snapshot.ESP.UseTeamColor, snapshot.ESP.DepthMode, snapshot.ESP.MaxDistance = true, "AlwaysOnTop", 10000
            snapshot.Chams.Enabled = true
            snapshot.Visuals.Fullbright = true
            snapshot.Movement.InfJump = true
            snapshot.Extras.Hitbox.Enabled, snapshot.Extras.Hitbox.Size, snapshot.Extras.Hitbox.Transparency = true, 10, 0.75
            snapshot.Extras.AntiFling.Enabled, snapshot.Extras.AntiFling.SnapBack = true, true
        end
        return snapshot
    end

    local function pathFor(name: string): (string?, string)
        name = sanitize(name)
        if name == "" or name:sub(1, 1) == "_" then return nil, "Choose a non-empty profile name that does not start with '_'" end
        if builtinKey(name) then return nil, `{CONFIG.BUILTIN_LABELS[builtinKey(name) :: string]} is a built-in preset` end
        return `Configs/{name}.json`, name
    end

    local function hydrate(snapshot: any, label: string?)
        ConfigService._isLoading = true
        if label then bus:Publish("ConfigApplyStarted", label) end
        local ok, err = pcall(function() state:LoadSettingsSnapshot(snapshot) end)
        ConfigService._isLoading = false
        if not ok then
            if label then bus:Publish("ConfigApplyFinished", false, label, tostring(err)) end
            error(err)
        end
        ConfigService.Dirty = false
        if label then bus:Publish("ConfigApplyFinished", true, label) end
    end

    function ConfigService:SanitizeName(name: string): string return sanitize(name) end

    function ConfigService:Save(name: string): (boolean, string)
        local path, clean = pathFor(name)
        if not path then return false, clean end
        local ok, json = pcall(encode, state:GetSettingsSnapshot())
        if not ok then return false, tostring(json) end
        local written, message = environment:WriteFile(path, json)
        if written then setActiveProfile(clean); bus:Publish("ProfilesChanged") end
        return written, message or `Saved {clean}`
    end

    function ConfigService:Load(name: string): (boolean, string)
        local key = builtinKey(name)
        if key then
            local snapshot = buildBuiltin(key)
            -- A builtin preset only changes gameplay settings; the user's UI settings, hotkeys,
            -- whitelist, and theme are kept so loading a combat preset never wipes personal binds.
            if key ~= "default" then
                local current = state:GetSettingsSnapshot()
                snapshot.Settings, snapshot.Theme = current.Settings, current.Theme
                snapshot.Aimbot.Keybind = current.Aimbot.Keybind
                snapshot.Aimbot.Triggerbot.Keybind = current.Aimbot.Triggerbot.Keybind
                snapshot.Movement.FlyKeybind = current.Movement.FlyKeybind
                snapshot.Extras.Hitbox.Keybind = current.Extras.Hitbox.Keybind
            end
            hydrate(snapshot, `Loading {CONFIG.BUILTIN_LABELS[key]}`); setActiveProfile(CONFIG.BUILTIN_LABELS[key])
            self:PersistLoadedProfile()
            return true, `Loaded {CONFIG.BUILTIN_LABELS[key]}`
        end
        local path, clean = pathFor(name)
        if not path then return false, clean end
        local raw, readError = environment:ReadFile(path)
        if not raw then return false, readError or "Profile not found" end
        local ok, snapshot = pcall(decode, raw)
        if not ok then return false, `Invalid profile: {tostring(snapshot)}` end
        hydrate(snapshot, `Loading {clean}`); setActiveProfile(clean)
        self:PersistLoadedProfile()
        return true, `Loaded {clean}`
    end

    function ConfigService:PersistLoadedProfile()
        if self._applyingLaunch then return end
        self.Dirty = true
        self:Flush()
    end

    function ConfigService:ResetInterfacePreferences(): (boolean, string)
        local defaults = state:GetDefaultSettings()
        -- Apply values from the immutable defaults without replacing the user's profiles, binds, or favorites.
        state:Set("Settings.UIScale", defaults.Settings.UIScale)
        state:Set("Settings.CompactMenu", defaults.Settings.CompactMenu)
        state:Set("Settings.InterfaceDensity", defaults.Settings.InterfaceDensity)
        state:Set("Settings.ShowMenuIcon", defaults.Settings.ShowMenuIcon)
        state:Set("Settings.MotionMode", defaults.Settings.MotionMode)
        state:Set("Settings.MotionSpeed", defaults.Settings.MotionSpeed)
        self.Dirty = true
        self:Flush()
        return true, "Interface scale, density, and motion settings were restored"
    end

    function ConfigService:ResetTheme(): (boolean, string)
        state:Set("Theme.CustomTokens", {})
        state:Set("Theme.ActivePreset", "Midnight")
        self.Dirty = true
        self:Flush()
        return true, "Midnight theme restored"
    end

    function ConfigService:ResetAllSettings(): (boolean, string)
        hydrate(state:GetDefaultSettings(), "Restoring all defaults")
        setActiveProfile("Default")
        self:PersistLoadedProfile()
        return true, "All settings were restored to defaults"
    end

    function ConfigService:Delete(name: string): (boolean, string)
        local path, clean = pathFor(name)
        if not path then return false, clean end
        local ok, message = environment:DeleteFile(path)
        if ok then
            bus:Publish("ProfilesChanged")
        end
        return ok, message or `Deleted {clean}`
    end

    function ConfigService:ListProfiles(): { string }
        local names, seen = {}, {}
        for _, key in ipairs(CONFIG.BUILTIN_ORDER) do
            table.insert(names, CONFIG.BUILTIN_LABELS[key])
            seen[key] = true
        end
        local extras = {}
        for _, file in ipairs(environment:ListFiles("Configs")) do
            local name = file:match("([^/]+)%.json$")
            if name and name:sub(1, 1) ~= "_" and not seen[string.lower(name)] then
                table.insert(extras, name); seen[string.lower(name)] = true
            end
        end
        table.sort(extras, function(a: string, b: string) return a:lower() < b:lower() end)
        for _, name in ipairs(extras) do table.insert(names, name) end
        return names
    end

    function ConfigService:ProfileExists(name: string): boolean
        if builtinKey(name) then return true end
        local path = pathFor(name)
        return path ~= nil and environment:ReadFile(path) ~= nil
    end

    function ConfigService:Export(): (string?, string?)
        local ok, json = pcall(encode, state:GetSettingsSnapshot())
        if not ok then return nil, tostring(json) end
        local copied, message = environment:SetClipboard(json)
        return json, if copied then "Copied config JSON" else message
    end

    function ConfigService:Validate(json: string): (boolean, string?)
        local ok, result = pcall(decode, json)
        return ok, if ok then nil else `Invalid config JSON: {tostring(result)}`
    end

    function ConfigService:Backup(): (boolean, string)
        local ok, json = pcall(encode, state:GetSettingsSnapshot())
        if not ok then return false, tostring(json) end
        local written, message = environment:WriteFile(CONFIG.BACKUP_FILE, json)
        return written, message or "Backup created"
    end

    function ConfigService:RestoreBackup(): (boolean, string)
        local raw, readError = environment:ReadFile(CONFIG.BACKUP_FILE)
        if not raw then return false, readError or "No backup exists" end
        local valid, validationError = self:Validate(raw)
        if not valid then return false, validationError or "Backup validation failed" end
        local ok, snapshot = pcall(decode, raw)
        if not ok then return false, `Backup validation failed: {tostring(snapshot)}` end
        hydrate(snapshot, "Restoring backup"); setActiveProfile("Backup restore")
        self:PersistLoadedProfile()
        return true, "Backup restored"
    end

    function ConfigService:Import(json: string?): (boolean, string)
        if not json or json:match("^%s*$") then json = environment:GetClipboard() end
        if not json then return false, "Clipboard reading is unavailable; paste JSON into the editor" end
        local valid, validationError = self:Validate(json)
        if not valid then return false, validationError or "Invalid config JSON" end
        local ok, snapshot = pcall(decode, json)
        if not ok then return false, `Invalid config JSON: {tostring(snapshot)}` end
        hydrate(snapshot, "Importing config"); setActiveProfile("Imported")
        self:PersistLoadedProfile()
        return true, "Imported config"
    end

    function ConfigService:ReadRawAutoload(): any?
        local raw = environment:ReadFile(CONFIG.AUTOSAVE_FILE)
        if not raw then return nil end
        local ok, snapshot = pcall(decode, raw)
        return if ok then snapshot else nil
    end

    function ConfigService:Flush(): (boolean, string?)
        local snapshot = state:GetSettingsSnapshot()
        if state:Peek("Settings.RestoreOnLaunch") ~= true then
            snapshot = self:ReadRawAutoload() or state:GetDefaultSettings()
            if type(snapshot.Settings) ~= "table" then snapshot.Settings = {} end
            snapshot.Settings.RestoreOnLaunch = state:Peek("Settings.RestoreOnLaunch") == true
            snapshot.Settings.StartupProfile = tostring(state:Peek("Settings.StartupProfile") or "")
        end
        local ok, json = pcall(encode, snapshot)
        if not ok then return false, tostring(json) end
        local written, message = environment:WriteFile(CONFIG.AUTOSAVE_FILE, json)
        if written then self.Dirty = false end
        return written, message
    end

    function ConfigService:ApplyLaunchState(): string
        local raw = self:ReadRawAutoload()
        local preferences = if type(raw) == "table" and type(raw.Settings) == "table" then raw.Settings else {}
        local startup = if type(preferences.StartupProfile) == "string" then preferences.StartupProfile else ""

        if preferences.RestoreOnLaunch == false then
            local defaults = state:GetDefaultSettings()
            defaults.Settings.RestoreOnLaunch, defaults.Settings.StartupProfile = false, startup
            hydrate(defaults, "Restoring defaults")
            setActiveProfile("Default")
            self:Flush()
            return "disabled"
        end

        local function loadForLaunch(name: string): (boolean, string?)
            self._applyingLaunch = true
            local ok, loaded, message = pcall(function() return self:Load(name) end)
            self._applyingLaunch = false
            if not ok then return false, tostring(loaded) end
            return loaded == true, message
        end
        local function preserveLaunchPreferences()
            local current = state:GetSettingsSnapshot()
            current.Settings.RestoreOnLaunch, current.Settings.StartupProfile = true, startup
            hydrate(current)
        end
        if startup ~= "" and self:ProfileExists(startup) then
            local loaded = loadForLaunch(startup)
            if loaded then
                preserveLaunchPreferences()
                return `profile:{startup}`
            end
        end
        if raw then
            hydrate(raw, "Restoring session")
            setActiveProfile("Autosaved session")
            return "autoload"
        end
        hydrate(state:GetDefaultSettings(), "Preparing defaults")
        return "defaults"
    end

    function ConfigService:PinStartupProfile(name: string): (boolean, string)
        if not self:ProfileExists(name) then return false, "Save the profile before pinning it" end
        state:Set("Settings.StartupProfile", sanitize(name))
        self.Dirty = true
        self:Flush()
        return true, `Pinned {sanitize(name)} for launch`
    end

    function ConfigService:GetActiveProfile(): string return self._activeProfile end

    function ConfigService:Initialize()
        if self._initialized then return end
        self._initialized = true
        scope:Add(bus:Subscribe("StateChanged", function(_path: string, _new: any, _old: any, metadata: any)
            if not ConfigService._isLoading and not (metadata and metadata.Hydrating) then
                ConfigService.Dirty = true
            end
        end))
        scope:Spawn(function()
            while not scope:IsDisposed() do
                task.wait(CONFIG.AUTOSAVE_INTERVAL)
                if not scope:IsDisposed() and ConfigService.Dirty and not ConfigService._isLoading then ConfigService:Flush() end
            end
        end)
    end

    function ConfigService:Destroy() scope:Dispose() end

    scope:Add(function() if ConfigService.Dirty and ConfigService._initialized then ConfigService:Flush() end end)
    return ConfigService
end
