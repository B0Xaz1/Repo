--!nonstrict
local SPEED_LINE_COUNT: number = 36
return function(services: any): any
    local state, pool, scheduler, environment = services:Get("StateStore"), services:Get("DrawingPool"), services:Get("TaskScheduler"), services:Get("Environment")
    local scope = services:Get("Disposer"):CreateChild("OverlayController")
    local workspace = game:GetService("Workspace")
    local random = Random.new()
    local OverlayController = { _objects = {}, _lines = {}, _last = {}, _shown = {}, _time = 0, _fps = 60, _ping = 0, _pingElapsed = 0, _initialized = false, _idle = true }

    local function acquire(name: string, kind: string): any?
        local object = pool:Acquire(kind)
        OverlayController._objects[name] = object
        return object
    end
    local function ensureSpeedLines()
        if OverlayController._lines[1] or not pool.Available then return end
        for index = 1, SPEED_LINE_COUNT do
            acquire("Speed" .. index, "Line")
            local angle = random:NextNumber(0, math.pi * 2)
            table.insert(OverlayController._lines, { Direction = Vector2.new(math.cos(angle), math.sin(angle)), Progress = random:NextNumber(0.18, 1), Speed = random:NextNumber(0.4, 1) })
        end
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
    local function render(dt: number)
        OverlayController._time += dt
        local showFov = state:Peek("Aimbot.FOV.Show")
        local showWatermark = state:Peek("Settings.Watermark")
        local showFps = state:Peek("Settings.ShowFPS")
        local showPing = state:Peek("Settings.ShowPing")
        local showLines = state:Peek("Extras.SpeedLines")
        if not pool.Available or not (showFov or showWatermark or showFps or showPing or showLines) then
            if not OverlayController._idle then
                for _, object in pairs(OverlayController._objects) do if object.Visible then object.Visible = false end end
                OverlayController._idle = true
            end
            return
        end
        OverlayController._idle = false
        if showFps and dt > 0 then OverlayController._fps += (1 / dt - OverlayController._fps) * (1 - math.exp(-dt * 3)) end
        table.clear(OverlayController._shown)
        local camera = workspace.CurrentCamera
        if not camera then concealUnused(); return end
        local accent = if services:Has("ThemeEngine") then services:Get("ThemeEngine"):GetToken("Accent") else Color3.fromRGB(140, 167, 255)
        local time = OverlayController._time
        if showFov then
            local fov = state:Peek("Aimbot.FOV")
            paint("FOV", { Position = environment:GetAimPoint(camera),
                Radius = math.clamp(fov.Size, 1, 1500) * (if fov.Pulse then 1 + math.sin(time * 2) * 0.07 else 1),
                Thickness = math.clamp(fov.Thickness, 1, 8), Filled = fov.Filled, Transparency = if fov.Filled then 0.15 else 0.85,
                NumSides = math.clamp(math.floor(fov.Sides), 16, 128), Color = if fov.Rainbow then Color3.fromHSV(time * 0.12 % 1, 0.7, 1) else accent })
        end
        local y = 18
        if showWatermark then
            paint("Watermark", { Text = "B0Xaz Universal  /  " .. services.Version,
                Position = Vector2.new(18, y), Center = false, Size = 14, Font = 2, Outline = true, Color = accent }); y += 21
        end
        if showFps then
            paint("FPS", { Text = math.round(OverlayController._fps) .. " FPS", Position = Vector2.new(18, y), Center = false, Size = 13, Outline = true, Color = Color3.new(1, 1, 1) }); y += 18
        end
        if showPing then
            OverlayController._pingElapsed += dt
            if OverlayController._pingElapsed >= 1 then
                OverlayController._pingElapsed = 0
                local ok, value = pcall(function() return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() end)
                if not ok then ok, value = pcall(function() return game:GetService("Players").LocalPlayer:GetNetworkPing() * 1000 end) end
                if ok and type(value) == "number" then OverlayController._ping = value end
            end
            paint("Ping", { Text = math.round(OverlayController._ping) .. " ms", Position = Vector2.new(18, y), Center = false, Size = 13, Outline = true, Color = Color3.new(1, 1, 1) })
        end
        if showLines then
            ensureSpeedLines()
            local assets = services:Get("PlayerTracker"):GetLocalAssets()
            local speed = if assets then assets.RootPart.AssemblyLinearVelocity.Magnitude else 0
            if speed > 5 then
                local centre = camera.ViewportSize / 2
                local radius = camera.ViewportSize.Magnitude / 2
                for index, line in ipairs(OverlayController._lines) do
                    line.Progress += dt * line.Speed * math.clamp(speed / 70, 0.1, 3)
                    if line.Progress > 1 then line.Progress = 0.18 end
                    local start = centre + line.Direction * radius * line.Progress
                    paint("Speed" .. index, { From = start, To = start + line.Direction * math.clamp(speed, 15, 100), Thickness = 1,
                        Color = accent, Transparency = math.clamp((line.Progress - 0.15) * 0.7, 0, 0.5) })
                end
            end
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
    scope:Add(function() for _, object in pairs(OverlayController._objects) do pool:Release(object) end; table.clear(OverlayController._objects); table.clear(OverlayController._lines) end)
    return OverlayController
end
