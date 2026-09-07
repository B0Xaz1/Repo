--!nonstrict
local HITPARTS: { [string]: { string } } = {
    Head = { "Head" }, Torso = { "UpperTorso", "Torso", "LowerTorso" },
    HumanoidRootPart = { "HumanoidRootPart" }, UpperTorso = { "UpperTorso", "Torso" }, LowerTorso = { "LowerTorso", "Torso" },
}

return function(services: any): any
    local state, environment, tracker = services:Get("StateStore"), services:Get("Environment"), services:Get("PlayerTracker")
    local filter, scheduler = services:Get("TargetFilter"), services:Get("TaskScheduler")
    local scope = services:Get("Disposer"):CreateChild("AimbotService")
    local cameraChanges = scope:CreateChild("Aim camera")
    local input, workspace, players = game:GetService("UserInputService"), game:GetService("Workspace"), game:GetService("Players")
    local AimbotService = { _target = nil, _held = false, _toggled = false, _blocked = false, _wind = Vector2.zero,
        _remainder = Vector2.zero, _lastCursor = nil, _time = 0, _camera = nil, _initialized = false, _warnedMouse = false }

    local function drop(block: boolean?)
        AimbotService._target = nil
        AimbotService._wind, AimbotService._remainder = Vector2.zero, Vector2.zero
        if block then AimbotService._blocked = true; AimbotService._toggled = false end
        state:SetTransient("AimbotTarget", nil)
    end
    local function hitpart(player: Player, name: string): BasePart?
        local assets = tracker:GetPlayerAssets(player)
        if not assets then return nil end
        for _, partName in ipairs(HITPARTS[name] or HITPARTS.Head) do
            local part = assets.Character:FindFirstChild(partName)
            if part and part:IsA("BasePart") then return part end
        end
        return assets.Head or assets.RootPart
    end
    local function selectTarget(camera: Camera, point: Vector2, config: any): Player?
        local best, distanceSquared = nil, math.clamp(config.FOV.Size, 1, 1500) ^ 2
        for _, player in ipairs(players:GetPlayers()) do
            if player == players.LocalPlayer then continue end
            local part = hitpart(player, config.Hitpart)
            if part and filter:ValidateTarget(player, part, config) then
                local projected, visible = camera:WorldToViewportPoint(part.Position)
                if visible and projected.Z > 0 then
                    local dx, dy = projected.X - point.X, projected.Y - point.Y
                    local squared = dx * dx + dy * dy
                    if squared < distanceSquared then best, distanceSquared = player, squared end
                end
            end
        end
        return best
    end
    local function clampAxis(step: number, remaining: number): number
        if step * remaining <= 0 then return 0 end
        return math.sign(remaining) * math.min(math.abs(step), math.abs(remaining))
    end
    local function correction(errorPixels: Vector2, alpha: number, dt: number, config: any): Vector2
        local delta = errorPixels * alpha
        if config.MovementMode == "WindMouse" then
            local damping = math.clamp(config.WindDamping, 0, 0.99) ^ (dt * 60)
            local noise = Vector2.new(math.noise(AimbotService._time * 7, 11), math.noise(27, AimbotService._time * 7)) * math.clamp(config.WindStrength, 0, 30)
            AimbotService._wind = AimbotService._wind * damping + noise * (1 - damping)
            delta += AimbotService._wind * alpha
        else AimbotService._wind = Vector2.zero end
        return Vector2.new(clampAxis(delta.X, errorPixels.X), clampAxis(delta.Y, errorPixels.Y))
    end
    local function update(dt: number)
        local config = state:Get("Aimbot")
        AimbotService._time += dt
        if not config.Enabled or not state:HasPermission("Aimbot.Enabled") then
            drop(); cameraChanges:RestoreProperties(); AimbotService._camera = nil; return
        end
        if input:GetFocusedTextBox() or state:GetTransient("IsBindingKey") then drop(); return end
        local localAssets = tracker:GetLocalAssets()
        if not localAssets or localAssets.Humanoid.Health <= 0 then drop(config.UnlockOnDeath); return end
        local engaged = environment:IsMobile() or (if config.LockMode == "Toggle" then AimbotService._toggled else AimbotService._held)
        if not engaged or AimbotService._blocked then drop(); return end
        local camera = workspace.CurrentCamera
        if not camera then drop(); return end
        if AimbotService._camera ~= camera then cameraChanges:RestoreProperties(); AimbotService._camera = camera end
        local point = environment:GetAimPoint(camera)
        local target = AimbotService._target
        local part = target and hitpart(target, config.Hitpart)
        if target and (not part or not filter:ValidateTarget(target, part, config)) then
            local dead = not tracker:IsAlive(target)
            drop(dead and config.UnlockOnDeath)
            return
        end
        if not target then
            target = selectTarget(camera, point, config)
            AimbotService._target = target
            part = target and hitpart(target, config.Hitpart)
            state:SetTransient("AimbotTarget", target)
        end
        if not target or not part then AimbotService._lastCursor = point; return end
        local assets = tracker:GetPlayerAssets(target)
        local velocity = assets.RootPart.AssemblyLinearVelocity
        local prediction = config.Prediction
        local goal = part.Position + Vector3.new(velocity.X * math.clamp(prediction.Horizontal, 0, 1),
            velocity.Y * math.clamp(prediction.Vertical, 0, 1), velocity.Z * math.clamp(prediction.Horizontal, 0, 1))
        if config.ShakeIntensity > 0 then
            local shake = math.clamp(config.ShakeIntensity, 0, 3)
            goal += Vector3.new(math.noise(AimbotService._time * 10, 5), math.noise(9, AimbotService._time * 10), 0) * shake
        end
        local projected, visible = camera:WorldToViewportPoint(goal)
        if not visible or projected.Z <= 0 then drop(); return end
        local screen = Vector2.new(projected.X, projected.Y)
        if config.BreakOnPull and AimbotService._lastCursor and not environment:IsMobile()
            and (point - AimbotService._lastCursor).Magnitude > 1
            and (screen - point).Magnitude > math.max(10, config.MaxLockRadius) then
            AimbotService._lastCursor = point; drop(true); return
        end
        AimbotService._lastCursor = point
        local alpha = AimbotService:SmoothingAlpha(dt, config.Smoothness)
        if not config.UseCamera and not environment.Capabilities.MouseMove then
            if not AimbotService._warnedMouse then
                AimbotService._warnedMouse = true
                services:Get("EventBus"):Publish("Notify", "Aimbot", "Relative mouse input is unavailable; using camera correction")
            end
            state:Set("Aimbot.UseCamera", true); config.UseCamera = true
        end
        if config.UseCamera then
            local desired = goal
            if config.MovementMode == "WindMouse" and alpha > 0 then
                local centre = camera.ViewportSize / 2
                local delta = correction(screen - centre, alpha, dt, config)
                local ray = camera:ViewportPointToRay(centre.X + delta.X / alpha, centre.Y + delta.Y / alpha)
                desired = camera.CFrame.Position + ray.Direction * 1000
            end
            if (desired - camera.CFrame.Position).Magnitude > 0.001 then
                cameraChanges:SetProperty(camera, "CFrame", camera.CFrame:Lerp(CFrame.lookAt(camera.CFrame.Position, desired), alpha), true)
            end
            AimbotService._remainder = Vector2.zero
        else
            cameraChanges:RestoreProperties()
            local remaining = screen - point
            local delta = correction(remaining, alpha, dt, config)
            local remainder = AimbotService._remainder
            if remaining.X * remainder.X < 0 then remainder = Vector2.new(0, remainder.Y) end
            if remaining.Y * remainder.Y < 0 then remainder = Vector2.new(remainder.X, 0) end
            local total = delta + remainder
            local x = clampAxis(math.round(total.X), math.sign(remaining.X) * math.floor(math.abs(remaining.X)))
            local y = clampAxis(math.round(total.Y), math.sign(remaining.Y) * math.floor(math.abs(remaining.Y)))
            -- Carry fractional work into later frames instead of losing it to integer executor input.
            AimbotService._remainder = Vector2.new(math.clamp(total.X - x, -1, 1), math.clamp(total.Y - y, -1, 1))
            if (x ~= 0 or y ~= 0) and not environment:MouseMove(x, y) then
                state:Set("Aimbot.UseCamera", true)
                services:Get("EventBus"):Publish("Notify", "Aimbot", "The executor rejected mouse input; using camera correction")
            end
        end
    end
    function AimbotService:SmoothingAlpha(dt: number, smoothness: number): number
        return 1 - math.exp(-dt * (60 / math.clamp(smoothness, 1, 100)))
    end
    function AimbotService:GetTarget(): Player? return self._target end
    function AimbotService:Unlock() self._held, self._toggled, self._blocked = false, false, false; drop() end
    function AimbotService:Initialize()
        if self._initialized then return end
        self._initialized = true
        scope:Connect(input.InputBegan, function(event: InputObject, processed: boolean)
            if processed or input:GetFocusedTextBox() or state:GetTransient("IsBindingKey") then return end
            if environment:MatchesInput(event, state:Get("Aimbot.Keybind")) then
                AimbotService._held, AimbotService._blocked = true, false
                AimbotService._toggled = not AimbotService._toggled
            end
        end)
        scope:Connect(input.InputEnded, function(event: InputObject)
            if environment:MatchesInput(event, state:Get("Aimbot.Keybind")) then AimbotService._held, AimbotService._blocked = false, false end
        end)
        scope:Add(state:Observe("Aimbot.Enabled", function(value: boolean) if not value then AimbotService:Unlock(); cameraChanges:RestoreProperties() end end))
        scope:Add(scheduler:RegisterCamera("Combat.Aimbot", 10, update))
    end
    function AimbotService:Destroy() self:Unlock(); scope:Dispose() end
    scope:Add(function() drop() end)
    return AimbotService
end
