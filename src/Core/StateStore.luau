--!strict
local function deepFreeze(value: any): any
    if type(value) ~= "table" then return value end
    for _, child in pairs(value) do deepFreeze(child) end
    return table.freeze(value)
end

local CONFIG = deepFreeze({
    MIN_TIER = 1,
    MAX_TIER = 3,
    DEFAULT_TIER = 3,
    DEFAULT_SETTINGS = {
        Aimbot = {
            Enabled = false, UseCamera = true, Keybind = Enum.UserInputType.MouseButton2,
            Hitpart = "Head", Smoothness = 8, MovementMode = "Linear", WindStrength = 2, WindDamping = 0.85,
            LockMode = "Hold", Prediction = { Horizontal = 0, Vertical = 0 }, TeamCheck = true,
            FriendCheck = false, WhitelistCheck = true, ForceFieldCheck = true, VisCheck = true,
            MaxDistance = 2000, ShakeIntensity = 0, UnlockOnDeath = true, BreakOnPull = true, MaxLockRadius = 250,
            Triggerbot = { Enabled = false, Delay = 0.15, TeamCheck = true, FriendCheck = false,
                WhitelistCheck = true, ForceFieldCheck = true, VisCheck = true, MaxDistance = 1000 },
            FOV = { Size = 120, Show = false, Filled = false, Thickness = 1, Sides = 64, Rainbow = false, Pulse = false },
        },
        Movement = {
            Speed = 0, JumpPower = 0, InfJump = false,
            FlyEnabled = false, FlySpeed = 50, FlyKeybind = Enum.KeyCode.F,
            MobileFlyUp = false, MobileFlyDown = false, SprintEnabled = false, SprintSpeed = 28,
            CFrameSpeed = false, CFrameSpeedValue = 10, WorldGravity = 0, Fling = false, TouchFling = false, TouchTeleportEnabled = false, NoClip = false,
            FreecamEnabled = false, FreecamSpeed = 32, WallWalkEnabled = false,
        },
        ESP = {
            Enabled = false, Box = true, Name = true, Health = true, Distance = true,
            Tool = false, Backpack = false, Tracers = false, Skeleton = false, HeadDot = false, LookDir = false,
            TeamCheck = false, UseTeamColor = false, Rainbow = false, MaxDist = 2500, Color = Color3.fromRGB(129, 167, 255),
            Font = "Plex", Outline = true, AutoScaling = true, DepthMode = "AlwaysOnTop",
        },
        Chams = { Enabled = false, UseTeamColor = false, Rainbow = false, DepthMode = "AlwaysOnTop",
            FillColor = Color3.fromRGB(117, 143, 255), OutlineColor = Color3.fromRGB(222, 230, 255) },
        Camera = { FOV = 0 }, Visuals = { Fullbright = false },
        Lighting = { Mode = "Off", TimeOfDay = 14, CycleDuration = 240, Paused = false,
            PresetBrightness = 1, Vignette = false, RemasterMaterials = false },
        Extras = { Hitbox = { Enabled = false, Size = 5 }, SpinBot = { Enabled = false, Speed = 180 },
            AntiFling = { Enabled = false, Threshold = 350, SnapBack = true } },
        Performance = { FpsCap = 0, NoTextures = false, LowMaterials = false, OptimizeTerrain = false,
            NoPostProcessing = false, NoShadows = false, NoParticles = false },
        Game = {
            NoSpread = false, FastFire = false, ForceAuto = false, ForceRange = false,
            FastFireDelay = 0.001, ForceRangeValue = 10000,
            DoorPhase = false, PhaseTransparency = 0.65,
            FakeMacro = false, FakeMacroKey = Enum.KeyCode.X, FakeMacroMode = "Toggle", FakeMacroDelay = 0.03,
            MvSEsp = false, MvSKnife = false, MvSKnifeCooldown = 0.45,
            MvSKnifeThrowSpeed = 0,
            MvSKnifeSpamThrow = false,
            MvSRevolver = false, MvSGunCooldown = 2.55,
            MvSGunAttributeCooldown = 0.0,
            MvSGunSpamShoot = false,
            MvSAutoEquip = false,
            MvSAutoQueue = false, MvSQueueMode = "1v1", MvSQueueDelay = 3.0,
            ZombieAura = false, ZombieAuraRate = 0.1, ZombieAuraPart = "Head", ZombieAuraRange = 0,
            FavoriteLocations = {},
            StopAutomationOnRespawn = true,
        },
        Settings = {
            UIScale = 1, MenuVisible = true, ShowMenuIcon = true, MenuKeybind = Enum.KeyCode.RightShift, UnloadKeybind = Enum.KeyCode.End,
            CompactMenu = false, PluginEnabled = true,
            ShowFPS = false, ShowPing = false, Watermark = true, AutoRejoin = false,
            Binds = { Fly = Enum.KeyCode.F, Freecam = Enum.KeyCode.Unknown, Panic = Enum.KeyCode.P, Fullbright = Enum.KeyCode.Unknown, ESP = Enum.KeyCode.Unknown,
                Chams = Enum.KeyCode.Unknown, Aimbot = Enum.KeyCode.Unknown,
                Menu = Enum.KeyCode.RightShift, Lighting = Enum.KeyCode.Unknown },
            RestoreOnLaunch = true, StartupProfile = "", AntiAfk = false, TpToMouse = false, Whitelist = {},
        },
        Theme = { ActivePreset = "Midnight", CustomTokens = {} },
    },
    ALIASES = {
        ["Movement.FlyKeybind"] = "Settings.Binds.Fly", ["Settings.Binds.Fly"] = "Movement.FlyKeybind",
        ["Settings.MenuKeybind"] = "Settings.Binds.Menu", ["Settings.Binds.Menu"] = "Settings.MenuKeybind",
        ["ESP.DepthMode"] = "Chams.DepthMode", ["Chams.DepthMode"] = "ESP.DepthMode",
    },
    GAME_BOOLEAN_FLAGS = {
        "Game.NoSpread", "Game.FastFire", "Game.ForceAuto", "Game.ForceRange",
        "Game.DoorPhase", "Game.FakeMacro",
        "Game.MvSEsp", "Game.MvSKnife", "Game.MvSKnifeSpamThrow", "Game.MvSRevolver", "Game.MvSGunSpamShoot", "Game.MvSAutoEquip", "Game.MvSAutoQueue",
        "Game.ZombieAura",
    },
})

local function clone(value: any): any
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

local function equal(a: any, b: any): boolean
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function read(root: any, path: string): any
    local node = root
    for segment in path:gmatch("[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[segment]
    end
    return node
end

local function write(root: any, path: string, value: any)
    local segments = string.split(path, ".")
    local node = root
    for index = 1, #segments - 1 do
        if type(node[segments[index]]) ~= "table" then node[segments[index]] = {} end
        node = node[segments[index]]
    end
    node[segments[#segments]] = value
end

local function compatible(value: any, default: any): boolean
    if default == nil then return true end
    if typeof(value) ~= typeof(default) then return false end
    return type(value) ~= "number" or (value == value and math.abs(value) < math.huge)
end

local function merge(defaults: any, incoming: any): any
    local result = clone(defaults)
    if type(incoming) ~= "table" then return result end
    for key, value in pairs(incoming) do
        if type(key) == "string" or type(key) == "number" then
            local default = defaults[key]
            if compatible(value, default) then
                result[key] = if type(value) == "table" and type(default) == "table" then merge(default, value) else clone(value)
            end
        end
    end
    return result
end

return function(eventBus: any, disposer: any): any
    local StateStore = { _settings = clone(CONFIG.DEFAULT_SETTINGS), _transient = {}, _revision = 0, _hydrating = false, _currentTier = CONFIG.DEFAULT_TIER }

    local function publishChanges(path: string, value: any, old: any)
        if equal(value, old) then return end
        StateStore._revision += 1
        local metadata = { Hydrating = StateStore._hydrating, Revision = StateStore._revision }
        eventBus:Publish(`StateChanged:{path}`, clone(value), clone(old), metadata)
        eventBus:Publish("StateChanged", path, clone(value), clone(old), metadata)
        if type(value) == "table" or type(old) == "table" then
            local keys = {}
            if type(value) == "table" then for key in pairs(value) do keys[key] = true end end
            if type(old) == "table" then for key in pairs(old) do keys[key] = true end end
            for key in pairs(keys) do
                publishChanges(`{path}.{tostring(key)}`, if type(value) == "table" then value[key] else nil,
                    if type(old) == "table" then old[key] else nil)
            end
        end
    end

    function StateStore:Get(path: string): any return clone(read(self._settings, path)) end

    function StateStore:Peek(path: string): any return read(self._settings, path) end

    function StateStore:Set(path: string, value: any): (boolean, string?)
        assert(type(path) == "string" and path ~= "" and not path:find("%.%.") and not path:match("^%.") and not path:match("%.$"), "Invalid state path")
        local default = read(CONFIG.DEFAULT_SETTINGS, path)
        if not compatible(value, default) then return false, `Invalid value for {path}` end
        local old = read(self._settings, path)
        if equal(old, value) then return true end
        local stored = clone(value)
        write(self._settings, path, stored)
        publishChanges(path, stored, old)
        local alias = CONFIG.ALIASES[path]
        if alias then
            local previous = read(self._settings, alias)
            write(self._settings, alias, clone(stored))
            publishChanges(alias, stored, previous)
        end
        return true
    end

    function StateStore:Observe(path: string, callback: (...any) -> ()): any
        return eventBus:Subscribe(`StateChanged:{path}`, callback)
    end

    function StateStore:GetTransient(key: string): any return self._transient[key] end

    function StateStore:SetTransient(key: string, value: any)
        local old = self._transient[key]
        if old == value then return end
        self._transient[key] = value
        eventBus:Publish(`TransientChanged:{key}`, value, old)
    end

    function StateStore:GetSettingsSnapshot(): any return clone(self._settings) end

    function StateStore:GetDefaultSettings(): any return clone(CONFIG.DEFAULT_SETTINGS) end

    function StateStore:Reset(path: string): (boolean, string?)
        local defaults = self:GetDefaultSettings()
        local value = read(defaults, path)
        if value == nil then return false, `Unknown settings path: {path}` end
        return self:Set(path, value)
    end

    function StateStore:ResetSection(path: string): (boolean, string?)
        local defaults = self:GetDefaultSettings()
        local value = read(defaults, path)
        if type(value) ~= "table" then return false, `Settings section is not a table: {path}` end
        local current = read(self._settings, path)
        if equal(current, value) then return true end
        write(self._settings, path, clone(value))
        publishChanges(path, value, current)
        for source, alias in pairs(CONFIG.ALIASES) do
            local sourceInSection = source == path or source:sub(1, #path + 1) == `{path}.`
            local aliasInSection = alias == path or alias:sub(1, #path + 1) == `{path}.`
            if sourceInSection then
                local sourceValue = read(self._settings, source)
                local oldAlias = read(self._settings, alias)
                write(self._settings, alias, clone(sourceValue))
                publishChanges(alias, sourceValue, oldAlias)
            elseif aliasInSection then
                local aliasValue = read(self._settings, alias)
                local oldSource = read(self._settings, source)
                write(self._settings, source, clone(aliasValue))
                publishChanges(source, aliasValue, oldSource)
            end
        end
        return true
    end

    function StateStore:GetTier(): number return self._currentTier end

    function StateStore:SetTier(tier: number)
        self._currentTier = math.clamp(math.floor(tonumber(tier) or CONFIG.DEFAULT_TIER), CONFIG.MIN_TIER, CONFIG.MAX_TIER)
        self:EnforcePermissions()
        eventBus:Publish("TierChanged", self._currentTier)
    end

    function StateStore:EnforcePermissions()
        if self._currentTier >= CONFIG.MAX_TIER then return end
        for _, path in ipairs(CONFIG.GAME_BOOLEAN_FLAGS) do
            if self:Peek(path) == true then self:Set(path, false) end
        end
    end

    function StateStore:LoadSettingsSnapshot(snapshot: any)
        assert(type(snapshot) == "table", "Settings snapshot must be a table")
        local old = self._settings
        self._hydrating = true
        self._settings = merge(CONFIG.DEFAULT_SETTINGS, snapshot)
        local incomingSettings = if type(snapshot.Settings) == "table" then snapshot.Settings else {}
        local incomingBinds = if type(incomingSettings.Binds) == "table" then incomingSettings.Binds else {}
        local incomingMovement = if type(snapshot.Movement) == "table" then snapshot.Movement else {}
        if incomingMovement.FlyKeybind ~= nil and incomingBinds.Fly == nil then
            self._settings.Settings.Binds.Fly = self._settings.Movement.FlyKeybind
        else
            self._settings.Movement.FlyKeybind = self._settings.Settings.Binds.Fly
        end
        if incomingSettings.MenuKeybind ~= nil and incomingBinds.Menu == nil then
            self._settings.Settings.Binds.Menu = self._settings.Settings.MenuKeybind
        else
            self._settings.Settings.MenuKeybind = self._settings.Settings.Binds.Menu
        end
        local incomingEsp = type(snapshot.ESP) == "table" and snapshot.ESP.DepthMode
        local incomingChams = type(snapshot.Chams) == "table" and snapshot.Chams.DepthMode
        if type(incomingEsp) == "string" then self._settings.ESP.DepthMode = incomingEsp
        elseif type(incomingChams) == "string" then self._settings.ESP.DepthMode = incomingChams end
        self._settings.Chams.DepthMode = self._settings.ESP.DepthMode
        for branch, value in pairs(self._settings) do publishChanges(branch, value, old[branch]) end
        self._hydrating = false
        self:EnforcePermissions()
        eventBus:Publish("SettingsHydrated")
    end

    disposer:Add(function() table.clear(StateStore._transient) end)
    return StateStore
end
