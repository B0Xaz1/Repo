--!nonstrict
-- Zero-valued overrides mean "leave the game's value alone"; boot must not impose Roblox's usual defaults.
local DEFAULT_SETTINGS: any = {
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
        CFrameSpeed = false, CFrameSpeedValue = 10, WorldGravity = 0, Fling = false,
    },
    ESP = {
        Enabled = false, Box = true, Name = true, Health = true, Distance = true,
        Tool = false, Backpack = false, Tracers = false, Skeleton = false, HeadDot = false, LookDir = false,
        TeamCheck = false, MaxDist = 2500, Color = Color3.fromRGB(129, 167, 255),
        Font = "Plex", Outline = true, AutoScaling = true, DepthMode = "AlwaysOnTop",
    },
    Chams = { Enabled = false, UseTeamColor = false, DepthMode = "AlwaysOnTop",
        FillColor = Color3.fromRGB(117, 143, 255), OutlineColor = Color3.fromRGB(222, 230, 255) },
    Camera = { FOV = 0 }, Visuals = { Fullbright = false },
    Lighting = { Mode = "Off", TimeOfDay = 14, CycleDuration = 240, Paused = false,
        PresetBrightness = 1, Vignette = false, RemasterMaterials = false },
    Extras = { Hitbox = { Enabled = false, Size = 5 }, SpinBot = { Enabled = false, Speed = 180 },
        SpeedLines = false, AntiFling = { Enabled = false, Threshold = 350, SnapBack = true } },
    Performance = { FpsCap = 0, NoTextures = false, LowMaterials = false, OptimizeTerrain = false,
        NoPostProcessing = false, NoShadows = false, NoParticles = false },
    Game = {},
    Settings = {
        UIScale = 1, MenuVisible = true, MenuKeybind = Enum.KeyCode.RightShift, UnloadKeybind = Enum.KeyCode.End,
        ShowFPS = false, ShowPing = false, Watermark = true, AutoRejoin = false,
        Binds = { Fly = Enum.KeyCode.F, Fullbright = Enum.KeyCode.Unknown, ESP = Enum.KeyCode.Unknown,
            Chams = Enum.KeyCode.Unknown, Aimbot = Enum.KeyCode.Unknown, SpeedLines = Enum.KeyCode.Unknown,
            Menu = Enum.KeyCode.RightShift, Lighting = Enum.KeyCode.Unknown },
        RestoreOnLaunch = true, StartupProfile = "", AntiAfk = false, TpToMouse = false, Whitelist = {},
    },
    Theme = { ActivePreset = "Midnight", CustomTokens = {} },
}

local ALIASES: { [string]: string } = {
    ["Movement.FlyKeybind"] = "Settings.Binds.Fly", ["Settings.Binds.Fly"] = "Movement.FlyKeybind",
    ["Settings.MenuKeybind"] = "Settings.Binds.Menu", ["Settings.Binds.Menu"] = "Settings.MenuKeybind",
}

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
    local StateStore = { _settings = clone(DEFAULT_SETTINGS), _transient = {}, _revision = 0, _hydrating = false }

    local function publishChanges(path: string, value: any, old: any)
        if equal(value, old) then return end
        StateStore._revision += 1
        local metadata = { Hydrating = StateStore._hydrating, Revision = StateStore._revision }
        eventBus:Publish("StateChanged:" .. path, clone(value), clone(old), metadata)
        eventBus:Publish("StateChanged", path, clone(value), clone(old), metadata)
        -- Parent-table writes still reach leaf observers (profile loading and whitelist editing both use them).
        if type(value) == "table" or type(old) == "table" then
            local keys = {}
            if type(value) == "table" then for key in pairs(value) do keys[key] = true end end
            if type(old) == "table" then for key in pairs(old) do keys[key] = true end end
            for key in pairs(keys) do
                publishChanges(path .. "." .. tostring(key), if type(value) == "table" then value[key] else nil,
                    if type(old) == "table" then old[key] else nil)
            end
        end
    end

    function StateStore:Get(path: string): any return clone(read(self._settings, path)) end
    function StateStore:Set(path: string, value: any, _bypass: boolean?): (boolean, string?)
        assert(type(path) == "string" and path ~= "" and not path:find("%.%.") and not path:match("^%.") and not path:match("%.$"), "Invalid state path")
        local default = read(DEFAULT_SETTINGS, path)
        if not compatible(value, default) then return false, "Invalid value for " .. path end
        local old = read(self._settings, path)
        if equal(old, value) then return true end
        local stored = clone(value)
        write(self._settings, path, stored)
        publishChanges(path, stored, old)
        local alias = ALIASES[path]
        if alias then
            local previous = read(self._settings, alias)
            write(self._settings, alias, clone(stored))
            publishChanges(alias, stored, previous)
        end
        return true
    end
    function StateStore:Observe(path: string, callback: (...any) -> ()): any
        return eventBus:Subscribe("StateChanged:" .. path, callback)
    end
    function StateStore:GetTransient(key: string): any return self._transient[key] end
    function StateStore:SetTransient(key: string, value: any)
        local old = self._transient[key]
        if old == value then return end
        self._transient[key] = value
        eventBus:Publish("TransientChanged:" .. key, value, old)
    end
    function StateStore:GetSettingsSnapshot(): any return clone(self._settings) end
    function StateStore:GetDefaultSettings(): any return clone(DEFAULT_SETTINGS) end
    function StateStore:LoadSettingsSnapshot(snapshot: any)
        assert(type(snapshot) == "table", "Settings snapshot must be a table")
        local old = self._settings
        self._hydrating = true
        self._settings = merge(DEFAULT_SETTINGS, snapshot)
        -- Keep legacy/current bind fields in lockstep after a profile supplies either representation.
        self._settings.Movement.FlyKeybind = self._settings.Settings.Binds.Fly
        self._settings.Settings.Binds.Menu = self._settings.Settings.MenuKeybind
        -- Older profiles only stored chams depth; keep ESP drawings on the same mode.
        local incomingEsp = type(snapshot.ESP) == "table" and snapshot.ESP.DepthMode
        local incomingChams = type(snapshot.Chams) == "table" and snapshot.Chams.DepthMode
        if type(incomingEsp) == "string" then self._settings.ESP.DepthMode = incomingEsp
        elseif type(incomingChams) == "string" then self._settings.ESP.DepthMode = incomingChams end
        self._settings.Chams.DepthMode = self._settings.ESP.DepthMode
        for branch, value in pairs(self._settings) do publishChanges(branch, value, old[branch]) end
        self._hydrating = false
        eventBus:Publish("SettingsHydrated")
    end
    disposer:Add(function() table.clear(StateStore._transient) end)
    return StateStore
end
