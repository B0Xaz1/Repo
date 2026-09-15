--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Stats = game:GetService("Stats")

local CONFIG = table.freeze({
    FOV_MAX = 1500,
    FOV_PULSE_DEPTH = 0.07,
    FOV_THICKNESS_MAX = 8,
    FOV_SIDES_MIN = 16,
    FOV_SIDES_MAX = 128,
    FOV_FILL_ALPHA = 0.15,
    FOV_RING_ALPHA = 0.85,
    WATERMARK_POSITION = Vector2.new(18, 18),
    WATERMARK_ROW_HEIGHT = 21,
    TELEMETRY_ROW_HEIGHT = 18,
    PING_INTERVAL = 1,
    FPS_SMOOTHING = 3,
    FALLBACK_ACCENT = Color3.fromRGB(140, 167, 255),
})

return function(services: any): any
    local state, pool, scheduler, environment = services:Get("StateStore"), services:Get("DrawingPool"), services:Get("TaskScheduler"), services:Get("Environment")
    local scope = services:Get("Disposer"):CreateChild("OverlayController")
    local OverlayController = { _objects = {}, _last = {}, _shown = {}, _time = 0, _fps = 60, _ping = 0, _pingElapsed = 0, _initialized = false, _idle = true }

    local function acquire(name: string, kind: string): any?
        local object = pool:Acquire(kind)
        OverlayController._objects[name] = object
        return object
    end

    local function paint(name: string, properties: any)
        local object = OverlayController._objects[name]
        if not object then return end
        local last = OverlayController._last[name]
        if not last then last = {}; OverlayController._last[name] = last end
        for property, value in pairs(properties) do
            if last[property] ~= value then object[property] = value; last[property] = value end
        end
        if last.Visible ~= true then object.Visible = true; last.Visible = true end
        OverlayController._shown[name] = true
    end

    local function concealUnused()
        for name, object in pairs(OverlayController._objects) do
            if object.Visible and not OverlayController._shown[name] then
                object.Visible = false
                local last = OverlayController._last[name]
                if last then last.Visible = false end
            end
        end
    end

    local function measurePing()
        local ok, value = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
        if not ok then ok, value = pcall(function() return Players.LocalPlayer:GetNetworkPing() * 1000 end) end
        if ok and type(value) == "number" then OverlayController._ping = value end
    end

    local function render(dt: number)
        OverlayController._time += dt
        local showFov = state:Peek("Aimbot.FOV.Show")
        local showWatermark = state:Peek("Settings.Watermark")
        local showFps = state:Peek("Settings.ShowFPS")
        local showPing = state:Peek("Settings.ShowPing")
        if not pool.Available or not (showFov or showWatermark or showFps or showPing) then
            if not OverlayController._idle then
                for _, object in pairs(OverlayController._objects) do if object.Visible then object.Visible = false end end
                OverlayController._idle = true
            end
            return
        end
        OverlayController._idle = false
        if showFps and dt > 0 then OverlayController._fps += (1 / dt - OverlayController._fps) * (1 - math.exp(-dt * CONFIG.FPS_SMOOTHING)) end
        table.clear(OverlayController._shown)
        local camera = Workspace.CurrentCamera
        if not camera then concealUnused(); return end
        local accent = if services:Has("ThemeEngine") then services:Get("ThemeEngine"):GetToken("Accent") else CONFIG.FALLBACK_ACCENT
        local time = OverlayController._time
        if showFov then
            local fov = state:Peek("Aimbot.FOV")
            paint("FOV", { Position = environment:GetAimPoint(camera),
                Radius = math.clamp(fov.Size, 1, CONFIG.FOV_MAX) * (if fov.Pulse then 1 + math.sin(time * 2) * CONFIG.FOV_PULSE_DEPTH else 1),
                Thickness = math.clamp(fov.Thickness, 1, CONFIG.FOV_THICKNESS_MAX), Filled = fov.Filled, Transparency = if fov.Filled then CONFIG.FOV_FILL_ALPHA else CONFIG.FOV_RING_ALPHA,
                NumSides = math.clamp(math.floor(fov.Sides), CONFIG.FOV_SIDES_MIN, CONFIG.FOV_SIDES_MAX), Color = if fov.Rainbow then Color3.fromHSV(time * 0.12 % 1, 0.7, 1) else accent })
        end
        local y = CONFIG.WATERMARK_POSITION.Y
        if showWatermark then
            paint("Watermark", { Text = `B0Xaz Universal  /  {services.Version}`,
                Position = Vector2.new(CONFIG.WATERMARK_POSITION.X, y), Center = false, Size = 14, Font = 2, Outline = true, Color = accent }); y += CONFIG.WATERMARK_ROW_HEIGHT
        end
        if showFps then
            paint("FPS", { Text = `{math.round(OverlayController._fps)} FPS`, Position = Vector2.new(CONFIG.WATERMARK_POSITION.X, y), Center = false, Size = 13, Outline = true, Color = Color3.new(1, 1, 1) }); y += CONFIG.TELEMETRY_ROW_HEIGHT
        end
        if showPing then
            OverlayController._pingElapsed += dt
            if OverlayController._pingElapsed >= CONFIG.PING_INTERVAL then
                OverlayController._pingElapsed = 0
                measurePing()
            end
            paint("Ping", { Text = `{math.round(OverlayController._ping)} ms`, Position = Vector2.new(CONFIG.WATERMARK_POSITION.X, y), Center = false, Size = 13, Outline = true, Color = Color3.new(1, 1, 1) })
        end
        concealUnused()
    end

    function OverlayController:GetTelemetry(): any return { FPS = self._fps, Ping = self._ping } end

    function OverlayController:Initialize()
        if self._initialized then return end
        self._initialized = true
        if pool.Available then
            acquire("FOV", "Circle"); acquire("Watermark", "Text"); acquire("FPS", "Text"); acquire("Ping", "Text")
        end
        scope:Add(scheduler:RegisterRender("Visuals.Overlays", 20, render))
    end

    function OverlayController:Destroy() scope:Dispose() end

    scope:Add(function() for _, object in pairs(OverlayController._objects) do pool:Release(object) end; table.clear(OverlayController._objects) end)
    return OverlayController
end
