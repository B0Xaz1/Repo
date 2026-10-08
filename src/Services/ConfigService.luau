local HttpService = game:GetService("HttpService")

local CONFIG = table.freeze({
    MAX_JSON_BYTES = 1024 * 1024,
    MAX_NESTING_DEPTH = 40,
    MAX_NAME_LENGTH = 64,
    AUTOSAVE_FILE = "Configs/_autoload.json",
    BACKUP_FILE = "Configs/_backup.json",
    GAME_PROFILES_FILE = "Configs/_game_profiles.json",
    MAX_GAME_PROFILES = 512,
    AUTOSAVE_INTERVAL = 1.5,
    BUILTIN_LABELS = { default = "Default", legit = "Legit", rage = "Rage" },
})

return function(services: any): any
    local environment, state = services:Get("Environment"), services:Get("StateStore")
    local bus, scope = services:Get("EventBus"), services:Get("Disposer"):CreateChild("ConfigService")
    local ConfigService = { Dirty = false, _isLoading = false, _initialized = false, _activeProfile = "Default", _applyingLaunch = false,
        _gameProfiles = nil, _gameProfilesLoaded = false, _gameProfilesError = nil, _activeGameProfileKey = nil,
        _gameProfileAutosaveEnabled = false, _gameProfileAutosavePending = false }

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
        if key == "legit" then
            snapshot.Aimbot.Enabled, snapshot.Aimbot.Smoothness, snapshot.Aimbot.UseCamera = false, 16, true
            snapshot.Aimbot.TeamCheck, snapshot.Aimbot.VisCheck, snapshot.Aimbot.FriendCheck = true, true, true
            snapshot.Aimbot.FOV.Size, snapshot.Aimbot.FOV.Show, snapshot.Aimbot.MaxLockRadius = 70, true, 120
            snapshot.Aimbot.Triggerbot.Enabled, snapshot.Aimbot.Triggerbot.Delay = false, 0.2
            snapshot.ESP.Enabled, snapshot.ESP.Box, snapshot.ESP.Name, snapshot.ESP.Health, snapshot.ESP.Distance = true, true, true, true, true
            snapshot.ESP.Tool, snapshot.ESP.Backpack, snapshot.ESP.Tracers, snapshot.ESP.Skeleton, snapshot.ESP.HeadDot, snapshot.ESP.LookDir = false, false, false, false, false, false
            snapshot.ESP.TeamCheck, snapshot.ESP.UseTeamColor, snapshot.ESP.Rainbow, snapshot.ESP.MaxDist = true, true, false, 800
            snapshot.Chams.Enabled, snapshot.Chams.UseTeamColor, snapshot.Chams.Rainbow = false, true, false
            snapshot.Movement.FlyEnabled, snapshot.Movement.CFrameSpeed, snapshot.Movement.TouchFling, snapshot.Movement.InfJump = false, false, false, false
            snapshot.Extras.Hitbox.Enabled, snapshot.Extras.SpinBot.Enabled = false, false
        elseif key == "rage" then
            snapshot.Aimbot.Enabled, snapshot.Aimbot.Smoothness, snapshot.Aimbot.UseCamera = true, 1.5, true
            snapshot.Aimbot.TeamCheck, snapshot.Aimbot.VisCheck, snapshot.Aimbot.FriendCheck, snapshot.Aimbot.WhitelistCheck = false, false, false, false
            snapshot.Aimbot.FOV.Size, snapshot.Aimbot.FOV.Show, snapshot.Aimbot.MaxLockRadius = 360, true, 800
            snapshot.Aimbot.Triggerbot.Enabled, snapshot.Aimbot.Triggerbot.Delay = true, 0.02
            snapshot.Aimbot.Triggerbot.TeamCheck, snapshot.Aimbot.Triggerbot.VisCheck = false, false
            snapshot.ESP.Enabled, snapshot.ESP.Box, snapshot.ESP.Name, snapshot.ESP.Health, snapshot.ESP.Distance = true, true, true, true, true
            snapshot.ESP.Tool, snapshot.ESP.Backpack, snapshot.ESP.Tracers, snapshot.ESP.Skeleton, snapshot.ESP.HeadDot, snapshot.ESP.LookDir = true, true, true, true, true, true
            snapshot.ESP.TeamCheck, snapshot.ESP.UseTeamColor, snapshot.ESP.Rainbow, snapshot.ESP.MaxDist = false, false, false, 10000
            snapshot.Chams.Enabled, snapshot.Chams.UseTeamColor, snapshot.Chams.Rainbow = true, false, false
            snapshot.Movement.FlyEnabled, snapshot.Movement.CFrameSpeed, snapshot.Movement.TouchFling = false, false, false
        end
        return snapshot
    end

    local function pathFor(name: string): (string?, string)
        name = sanitize(name)
        if name == "" or name:sub(1, 1) == "_" then return nil, "Choose a non-empty profile name that does not start with '_'" end
        if builtinKey(name) then return nil, `{CONFIG.BUILTIN_LABELS[builtinKey(name) :: string]} is a built-in preset` end
        return `Configs/{name}.json`, name
    end

    local function getProfileSnapshot(name: string): (any?, string?)
        local key = builtinKey(name)
        if key then
            local snapshot = buildBuiltin(key)
            if key ~= "default" then
                local current = state:GetSettingsSnapshot()
                snapshot.Settings, snapshot.Theme = current.Settings, current.Theme
            end
            return snapshot, CONFIG.BUILTIN_LABELS[key]
        end
        local path, clean = pathFor(name)
        if not path then return nil, clean end
        local raw, readError = environment:ReadFile(path)
        if not raw then return nil, readError or "Profile not found" end
        local ok, snapshot = pcall(decode, raw)
        if not ok then return nil, `Invalid profile: {tostring(snapshot)}` end
        return snapshot, clean
    end

    local function getGameIdentity(): (string?, string)
        local universeId = math.floor(tonumber(game.GameId) or 0)
        local placeId = math.floor(tonumber(game.PlaceId) or 0)
        if universeId > 0 then
            return `universe:{universeId}`, `Universe ID {universeId} / Place ID {placeId}`
        end
        if placeId > 0 then return `place:{placeId}`, `Place ID {placeId}` end
        return nil, "Current experience ID is unavailable"
    end

    local function validGameKey(key: string): boolean
        return key:match("^universe:[1-9]%d*$") ~= nil or key:match("^place:[1-9]%d*$") ~= nil
    end

    local function isMissingFileError(message: any): boolean
        local text = tostring(message or ""):lower()
        return text == "" or text:find("not found", 1, true) ~= nil or text:find("no such file", 1, true) ~= nil
            or text:find("does not exist", 1, true) ~= nil or text:find("cannot find", 1, true) ~= nil
    end

    local function gameSnapshotPath(key: string): string?
        if not validGameKey(key) then return nil end
        local kind, id = key:match("^([a-z]+):([1-9]%d*)$")
        return if kind and id then `Configs/_game_{kind}_{id}.json` else nil
    end

    local function readGameSnapshot(key: string): (any?, string?)
        if not environment.Capabilities.Files then return nil, nil end
        local path = gameSnapshotPath(key)
        if not path then return nil, "Invalid experience key" end
        local raw, readError = environment:ReadFile(path)
        if not raw then
            if isMissingFileError(readError) then return nil, nil end
            return nil, tostring(readError or "Could not read per-game snapshot")
        end
        if #raw > CONFIG.MAX_JSON_BYTES then return nil, "Per-game snapshot exceeds the 1 MiB safety limit" end
        local ok, snapshot = pcall(decode, raw)
        if not ok then return nil, `Invalid per-game snapshot: {tostring(snapshot)}` end
        return snapshot, nil
    end

    local function writeGameSnapshot(key: string, snapshot: any): (boolean, string?)
        if not environment.Capabilities.Files then return false, "File persistence is unavailable on this executor" end
        local path = gameSnapshotPath(key)
        if not path then return false, "Invalid experience key" end
        local ok, json = pcall(encode, snapshot)
        if not ok then return false, tostring(json) end
        if #json > CONFIG.MAX_JSON_BYTES then return false, "Per-game snapshot exceeds the 1 MiB safety limit" end
        return environment:WriteFile(path, json)
    end

    local function loadGameProfiles(): ({ [string]: string }?, string?)
        if ConfigService._gameProfilesLoaded then return ConfigService._gameProfiles, ConfigService._gameProfilesError end
        ConfigService._gameProfilesLoaded = true
        ConfigService._gameProfiles = {}
        ConfigService._gameProfilesError = nil
        if not environment.Capabilities.Files then return ConfigService._gameProfiles, nil end

        local raw, readError = environment:ReadFile(CONFIG.GAME_PROFILES_FILE)
        if not raw then
            if not isMissingFileError(readError) then
                ConfigService._gameProfilesError = tostring(readError or "Could not read game-profile registry")
                return nil, ConfigService._gameProfilesError
            end
            return ConfigService._gameProfiles, nil
        end

        if #raw > CONFIG.MAX_JSON_BYTES then
            ConfigService._gameProfilesError = "Game-profile registry exceeds the 1 MiB safety limit"
            return nil, ConfigService._gameProfilesError
        end
        local ok, document = pcall(function() return HttpService:JSONDecode(raw) end)
        if not ok or type(document) ~= "table" or document.Format ~= 1 or type(document.Profiles) ~= "table" then
            ConfigService._gameProfilesError = `Invalid game-profile registry: {tostring(document)}`
            return nil, ConfigService._gameProfilesError
        end

        local entryCount = 0
        for _ in pairs(document.Profiles) do
            entryCount += 1
            if entryCount > CONFIG.MAX_GAME_PROFILES then
                ConfigService._gameProfilesError = `Game-profile registry exceeds {CONFIG.MAX_GAME_PROFILES} entries`
                return nil, ConfigService._gameProfilesError
            end
        end
        local profiles: { [string]: string } = {}
        for key, name in pairs(document.Profiles) do
            if type(key) == "string" and validGameKey(key) and type(name) == "string"
                and name ~= "" and name:sub(1, 1) ~= "_" and sanitize(name) == name then
                profiles[key] = name
            end
        end
        ConfigService._gameProfiles = profiles
        return profiles, nil
    end

    local function writeGameProfiles(profiles: { [string]: string }): (boolean, string)
        if not environment.Capabilities.Files then return false, "File persistence is unavailable on this executor" end
        local count = 0
        for key, name in pairs(profiles) do
            count += 1
            if count > CONFIG.MAX_GAME_PROFILES then return false, `Game-profile registry is limited to {CONFIG.MAX_GAME_PROFILES} experiences` end
            if type(key) ~= "string" or not validGameKey(key) or type(name) ~= "string"
                or name == "" or name:sub(1, 1) == "_" or sanitize(name) ~= name then
                return false, "Invalid game-profile registry entry"
            end
        end

        local ok, json = pcall(function()
            return HttpService:JSONEncode({ Format = 1, Profiles = profiles })
        end)
        if not ok then return false, tostring(json) end
        if #json > CONFIG.MAX_JSON_BYTES then return false, "Game-profile registry exceeds the 1 MiB safety limit" end
        local written, message = environment:WriteFile(CONFIG.GAME_PROFILES_FILE, json)
        if not written then return false, message or "Could not save game-profile registry" end
        ConfigService._gameProfiles, ConfigService._gameProfilesLoaded, ConfigService._gameProfilesError = table.clone(profiles), true, nil
        bus:Publish("GameProfilesChanged")
        return true, "Game-profile auto-load updated"
    end

    local function hydrate(snapshot: any)
        ConfigService._isLoading = true
        local ok, err = pcall(function() state:LoadSettingsSnapshot(snapshot) end)
        ConfigService._isLoading = false
        if not ok then error(err) end
        ConfigService.Dirty = false
    end

    function ConfigService:SanitizeName(name: string): string return sanitize(name) end

    function ConfigService:GetPinnedGameProfile(): (string?, string?)
        local key = getGameIdentity()
        if not key then return nil, nil end
        local profiles, loadError = loadGameProfiles()
        if not profiles then return nil, loadError end
        return profiles[key], nil
    end

    function ConfigService:GetGameProfileStatus(): string
        local key, identity = getGameIdentity()
        if not key then return identity end
        if not environment.Capabilities.Files then
            return `{identity}\nFile persistence is unavailable; game-specific auto-load cannot be stored.`
        end
        local profiles, loadError = loadGameProfiles()
        if not profiles then return `{identity}\nCould not read game-profile registry: {tostring(loadError)}` end
        local profile = profiles[key]
        local restoreEnabled = state:Peek("Settings.RestoreOnLaunch") == true
        if profile then
            local gameSnapshot, snapshotError = readGameSnapshot(key)
            if gameSnapshot then
                local source = `per-game saved session (seed: {profile})`
                if restoreEnabled then return `{identity}\nAuto-load: {source}` end
                return `{identity}\n{source}; restore-on-launch is disabled.`
            end
            if snapshotError then
                if self:ProfileExists(profile) then
                    return `{identity}\nPer-game snapshot unavailable ({snapshotError}); pinned profile '{profile}' will be used.`
                end
                return `{identity}\nPer-game snapshot unavailable and pinned profile '{profile}' is missing; the global fallback will be used.`
            end
            if not self:ProfileExists(profile) then
                local fallback = if restoreEnabled then "; the global fallback will be used" else "; restore-on-launch is disabled"
                return `{identity}\nPinned profile '{profile}' is missing{fallback}.`
            end
            if restoreEnabled then return `{identity}\nAuto-load profile: {profile}` end
            return `{identity}\nProfile '{profile}' is pinned, but restore-on-launch is disabled.`
        end
        if not restoreEnabled then return `{identity}\nNo game profile pinned. Restore-on-launch is disabled.` end
        local startup = tostring(state:Peek("Settings.StartupProfile") or "")
        local fallback = if startup ~= "" then `global profile '{startup}'` else "global autosaved session"
        return `{identity}\nNo game profile pinned; falls back to {fallback}.`
    end

    function ConfigService:PinCurrentGameProfile(name: string, saveCurrent: boolean?): (boolean, string)
        local key, identity = getGameIdentity()
        if not key then return false, identity end
        if not environment.Capabilities.Files then return false, "File persistence is unavailable on this executor" end
        local clean = sanitize(name)
        if clean == "" or clean:sub(1, 1) == "_" then return false, "Choose a valid saved profile" end
        if not self:ProfileExists(clean) then return false, `Profile '{clean}' does not exist` end
        local profiles, loadError = loadGameProfiles()
        if not profiles then return false, `Could not update game profiles: {tostring(loadError)}` end

        local alreadyPinned = string.lower(tostring(profiles[key] or "")) == string.lower(clean)
        local existingSnapshot = if alreadyPinned and saveCurrent ~= true then readGameSnapshot(key) else nil
        local snapshot = existingSnapshot
        if not snapshot then
            if saveCurrent == true then
                snapshot = state:GetSettingsSnapshot()
            else
                local profileLabelOrError
                snapshot, profileLabelOrError = getProfileSnapshot(clean)
                if not snapshot then return false, profileLabelOrError or `Profile '{clean}' does not exist` end
            end
        end
        local current = state:GetSettingsSnapshot()
        if type(snapshot.Settings) ~= "table" then snapshot.Settings = {} end
        snapshot.Settings.RestoreOnLaunch = current.Settings.RestoreOnLaunch
        snapshot.Settings.StartupProfile = current.Settings.StartupProfile

        local snapshotSaved, snapshotError = writeGameSnapshot(key, snapshot)
        if not snapshotSaved then return false, snapshotError or "Could not save the per-game snapshot" end
        local updated = table.clone(profiles)
        updated[key] = clean
        local saved, message = writeGameProfiles(updated)
        if not saved then return false, message end

        self._activeGameProfileKey = key
        local restoreEnabled = state:Peek("Settings.RestoreOnLaunch") == true
        self._gameProfileAutosaveEnabled = saveCurrent == true or (restoreEnabled and existingSnapshot ~= nil)
        self._gameProfileAutosavePending = not self._gameProfileAutosaveEnabled
        if state:Peek("Settings.RestoreOnLaunch") ~= true then
            return true, `'{clean}' is pinned for {identity}; enable Restore settings on launch to apply it`
        end
        if self._gameProfileAutosaveEnabled then
            return true, `'{clean}' is pinned for {identity}; game settings will auto-save separately`
        end
        return true, `'{clean}' will auto-load for {identity} on the next launch; later edits save to a separate game session`
    end

    function ConfigService:ClearCurrentGameProfile(): (boolean, string)
        local key, identity = getGameIdentity()
        if not key then return false, identity end
        if not environment.Capabilities.Files then return false, "File persistence is unavailable on this executor" end
        local profiles, loadError = loadGameProfiles()
        if not profiles then return false, `Could not update game profiles: {tostring(loadError)}` end
        if profiles[key] == nil then return true, "No game-specific profile is pinned" end
        local updated = table.clone(profiles)
        updated[key] = nil
        local saved, message = writeGameProfiles(updated)
        if saved then
            self._activeGameProfileKey = key
            self._gameProfileAutosaveEnabled = false
            self._gameProfileAutosavePending = false
        end
        return saved, if saved then `Cleared the auto-load profile for {identity}` else message
    end

    function ConfigService:Save(name: string): (boolean, string)
        local path, clean = pathFor(name)
        if not path then return false, clean end
        local ok, json = pcall(encode, state:GetSettingsSnapshot())
        if not ok then return false, tostring(json) end
        local written, message = environment:WriteFile(path, json)
        if written then self._activeProfile = clean; bus:Publish("ProfilesChanged") end
        return written, message or `Saved {clean}`
    end

    function ConfigService:Load(name: string): (boolean, string)
        local key = builtinKey(name)
        if key then
            local snapshot = buildBuiltin(key)
            -- A builtin preset only changes gameplay settings; the user's UI settings and theme are kept
            if key ~= "default" then
                local current = state:GetSettingsSnapshot()
                snapshot.Settings, snapshot.Theme = current.Settings, current.Theme
            end
            hydrate(snapshot); self._activeProfile = CONFIG.BUILTIN_LABELS[key]
            self:PersistLoadedProfile()
            return true, `Loaded {CONFIG.BUILTIN_LABELS[key]}`
        end
        local path, clean = pathFor(name)
        if not path then return false, clean end
        local raw, readError = environment:ReadFile(path)
        if not raw then return false, readError or "Profile not found" end
        local ok, snapshot = pcall(decode, raw)
        if not ok then return false, `Invalid profile: {tostring(snapshot)}` end
        hydrate(snapshot); self._activeProfile = clean
        self:PersistLoadedProfile()
        return true, `Loaded {clean}`
    end

    function ConfigService:TurnEverythingOff(): (boolean, string)
        local snapshot = state:GetDefaultSettings()
        local function disableToggles(settings: any)
            for key, value in pairs(settings) do
                if type(value) == "boolean" then settings[key] = false
                elseif type(value) == "table" then disableToggles(value) end
            end
        end
        disableToggles(snapshot)
        -- Menu visibility is not a feature toggle; keep the controls reachable after the reset.
        snapshot.Settings.MenuVisible = true
        hydrate(snapshot)
        if services:Has("PlayerTracker") then services:Get("PlayerTracker"):StopSpectate() end
        if services:Has("LocomotionService") then services:Get("LocomotionService"):StopFling() end
        self._activeProfile = "All Off"
        self:PersistLoadedProfile()
        return true, "All toggles off; sliders and other values reset to defaults. Menu kept open; saved profiles unchanged."
    end

    function ConfigService:PersistLoadedProfile()
        if self._applyingLaunch then return end
        if self._activeGameProfileKey then
            self._gameProfileAutosaveEnabled = true
            self._gameProfileAutosavePending = false
        end
        self.Dirty = true
        self:Flush()
    end

    function ConfigService:Delete(name: string): (boolean, string)
        local path, clean = pathFor(name)
        if not path then return false, clean end
        local ok, message = environment:DeleteFile(path)
        if ok then
            local profiles = loadGameProfiles()
            if profiles then
                local updated, changed = table.clone(profiles), false
                for key, profile in pairs(updated) do
                    if string.lower(profile) == string.lower(clean) then updated[key] = nil; changed = true end
                end
                if changed then writeGameProfiles(updated) end
            end
            bus:Publish("ProfilesChanged")
        end
        return ok, message or `Deleted {clean}`
    end

    function ConfigService:ListProfiles(): { string }
        local names, seen = { "Default", "Legit", "Rage" }, { default = true, legit = true, rage = true }
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
        hydrate(snapshot); self._activeProfile = "Backup restore"
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
        hydrate(snapshot); self._activeProfile = "Imported"
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
        local gameSnapshotSaved, gameSnapshotError = true, nil
        if self._activeGameProfileKey and self._gameProfileAutosaveEnabled then
            gameSnapshotSaved, gameSnapshotError = writeGameSnapshot(self._activeGameProfileKey, state:GetSettingsSnapshot())
        end

        local snapshot = state:GetSettingsSnapshot()
        local isolateGlobalFallback = self._activeGameProfileKey ~= nil or state:Peek("Settings.RestoreOnLaunch") ~= true
        if isolateGlobalFallback then
            -- Keep the global autosave as the fallback for other experiences. Only launch
            -- preferences are shared while a game session is isolated or restore is disabled.
            snapshot = self:ReadRawAutoload() or state:GetDefaultSettings()
            if type(snapshot.Settings) ~= "table" then snapshot.Settings = {} end
            snapshot.Settings.RestoreOnLaunch = state:Peek("Settings.RestoreOnLaunch") == true
            snapshot.Settings.StartupProfile = tostring(state:Peek("Settings.StartupProfile") or "")
        end
        local ok, json = pcall(encode, snapshot)
        if not ok then return false, tostring(json) end
        local written, message = environment:WriteFile(CONFIG.AUTOSAVE_FILE, json)
        if written and gameSnapshotSaved then self.Dirty = false end
        if not gameSnapshotSaved then return false, gameSnapshotError or "Could not save per-game snapshot" end
        return written, message
    end

    function ConfigService:ApplyLaunchState(): string
        self._activeGameProfileKey = nil
        self._gameProfileAutosaveEnabled = false
        self._gameProfileAutosavePending = false
        local raw = self:ReadRawAutoload()
        local preferences = if type(raw) == "table" and type(raw.Settings) == "table" then raw.Settings else {}
        local startup = if type(preferences.StartupProfile) == "string" then preferences.StartupProfile else ""
        local gameKey = getGameIdentity()
        local gameProfile, registryError = self:GetPinnedGameProfile()
        if registryError and environment.Capabilities.Files then
            warn(`[B0Xaz] Could not read game-profile registry: {registryError}`)
        end
        if gameProfile and gameKey then self._activeGameProfileKey = gameKey end

        if preferences.RestoreOnLaunch == false then
            if self._activeGameProfileKey then self._gameProfileAutosavePending = true end
            local defaults = state:GetDefaultSettings()
            defaults.Settings.RestoreOnLaunch, defaults.Settings.StartupProfile = false, startup
            hydrate(defaults)
            self._activeProfile = "Default"
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
        local function activateGameAutosave()
            if self._activeGameProfileKey then
                self._gameProfileAutosaveEnabled = true
                self._gameProfileAutosavePending = false
            end
        end

        if gameProfile and gameKey then
            local gameSnapshot, snapshotError = readGameSnapshot(gameKey)
            if gameSnapshot then
                hydrate(gameSnapshot)
                self._activeProfile = `Game session ({gameProfile})`
                activateGameAutosave()
                preserveLaunchPreferences()
                return `game-session:{gameProfile}`
            elseif snapshotError then
                warn(`[B0Xaz] Per-game session for '{gameProfile}' could not be loaded: {snapshotError}`)
            end

            if self:ProfileExists(gameProfile) then
                local loaded, loadError = loadForLaunch(gameProfile)
                if loaded then
                    activateGameAutosave()
                    preserveLaunchPreferences()
                    return `game-profile:{gameProfile}`
                end
                warn(`[B0Xaz] Game profile '{gameProfile}' could not be loaded: {tostring(loadError)}`)
            else
                warn(`[B0Xaz] Pinned game profile '{gameProfile}' is missing; using the global fallback`)
            end
        end

        if startup ~= "" and self:ProfileExists(startup) then
            local loaded = loadForLaunch(startup)
            if loaded then
                activateGameAutosave()
                preserveLaunchPreferences()
                return `profile:{startup}`
            end
        end
        if raw then
            hydrate(raw)
            self._activeProfile = "Autosaved session"
            activateGameAutosave()
            return "autoload"
        end
        hydrate(state:GetDefaultSettings())
        activateGameAutosave()
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
                local isGlobalLaunchPreference = _path == "Settings.RestoreOnLaunch" or _path == "Settings.StartupProfile"
                if ConfigService._activeGameProfileKey and ConfigService._gameProfileAutosavePending and not isGlobalLaunchPreference then
                    ConfigService._gameProfileAutosaveEnabled = true
                    ConfigService._gameProfileAutosavePending = false
                end
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
