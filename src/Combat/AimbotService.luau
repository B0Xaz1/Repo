local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CONFIG = table.freeze({
    UPDATE_INTERVAL = 1 / 120,
    FOV_MAX = 1500,
    SMOOTHING_REFERENCE_RATE = 60,
    SHAKE_MAX = 3,
    BREAK_PULL_CURSOR_EPSILON = 1,
    MIN_LOCK_RADIUS_FLOOR = 10,
    CAMERA_EPSILON = 0.001,
    SMOOTHNESS_MIN = 1,
    SMOOTHNESS_MAX = 100,
    -- Native pointer movement is consumed by Roblox on the next camera update. Limiting the
    -- feedback gain prevents a low-smoothness correction from overshooting and oscillating.
    MOUSE_MAX_ALPHA = 0.18,
    MOUSE_MAX_STEP = 28,
    MOUSE_DEADZONE = 1.5,
    HITPARTS = {
        Head = { "Head" }, Torso = { "UpperTorso", "Torso", "LowerTorso" },
        HumanoidRootPart = { "HumanoidRootPart" }, UpperTorso = { "UpperTorso", "Torso" }, LowerTorso = { "LowerTorso", "Torso" },
    },
})

return function(services: any): any
    local state, environment, tracker = services:Get("StateStore"), services:Get("Environment"), services:Get("PlayerTracker")
    local filter, scheduler = services:Get("TargetFilter"), services:Get("TaskScheduler")
    local bus = services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("AimbotService")
    local cameraChanges = scope:CreateChild("Aim camera")
    local AimbotService = { _target = nil, _preferredTarget = nil, _held = false, _toggled = false, _blocked = false,
        _remainder = Vector2.zero, _lastCursor = nil, _time = 0, _updateElapsed = 0, _camera = nil, _initialized = false, _warnedMouse = false }

    local function drop(block: boolean?)
        AimbotService._target = nil
        AimbotService._remainder = Vector2.zero
        if block then AimbotService._blocked = true; AimbotService._toggled = false end
        state:SetTransient("AimbotTarget", nil)
    end

    local function hitpart(player: Player, name: string): BasePart?
        local assets = tracker:GetPlayerAssets(player)
        if not assets then return nil end
        for _, partName in ipairs(CONFIG.HITPARTS[name] or CONFIG.HITPARTS.Head) do
            local part = assets.Character:FindFirstChild(partName)
            if part and part:IsA("BasePart") then return part end
        end
        return assets.Head or assets.RootPart
    end

    local function selectTarget(camera: Camera, point: Vector2, config: any): Player?
        -- A player explicitly selected from the Players workspace wins over proximity/FOV scoring.
        -- It remains transient (never saved to profiles) and uses the same filters as auto-targeting.
        local preferred = AimbotService._preferredTarget
        if preferred then
            if preferred.Parent ~= Players or preferred == Players.LocalPlayer or not tracker:IsAlive(preferred) then
                AimbotService._preferredTarget = nil
                state:SetTransient("AimbotPreferredTarget", nil)
            else
                local preferredPart = hitpart(preferred, config.Hitpart)
                if preferredPart and filter:ValidateTarget(preferred, preferredPart, config) then return preferred end
                -- Do not silently replace an explicit choice with the nearest player while it is
                -- merely occluded, outside a configured range, or excluded by a live filter.
                return nil
            end
        end
        local best, distanceSquared = nil, math.clamp(config.FOV.Size, 1, CONFIG.FOV_MAX) ^ 2
        for _, player in ipairs(Players:GetPlayers()) do
            if player == Players.LocalPlayer then continue end
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

    local function stableLookAt(eye: Vector3, target: Vector3, currentUp: Vector3?): CFrame?
        local offset = target - eye
        local dist = offset.Magnitude
        if dist <= CONFIG.CAMERA_EPSILON then return nil end
        local dir = offset / dist
        local up = currentUp or Vector3.new(0, 1, 0)
        -- When the look direction is almost colinear with the up vector, CFrame.lookAt becomes
        -- unstable and the camera can spin. Pick a fallback axis that is not colinear.
        if math.abs(dir:Dot(up)) > 0.9995 then
            up = Vector3.new(0, 0, 1)
            if math.abs(dir:Dot(up)) > 0.9995 then
                up = Vector3.new(1, 0, 0)
            end
        end
        return CFrame.lookAt(eye, target, up)
    end

    local function applyCameraCorrection(camera: Camera, goal: Vector3, alpha: number)
        local look = stableLookAt(camera.CFrame.Position, goal, camera.CFrame.UpVector)
        if look then cameraChanges:SetProperty(camera, "CFrame", camera.CFrame:Lerp(look, alpha), true) end
    end

    local function update(dt: number)
        AimbotService._updateElapsed += dt
        if AimbotService._updateElapsed < CONFIG.UPDATE_INTERVAL then return end
        dt, AimbotService._updateElapsed = AimbotService._updateElapsed, 0
        if not state:Peek("Aimbot.Enabled") then
            if AimbotService._target or AimbotService._camera then
                drop(); cameraChanges:ReleaseProperties(); AimbotService._camera = nil
            end
            return
        end
        local config = state:Peek("Aimbot")
        AimbotService._time += dt
        local localAssets = tracker:GetLocalAssets()
        if not localAssets or localAssets.Humanoid.Health <= 0 then drop(config.UnlockOnDeath); return end
        local engaged = environment:IsMobile() or (if config.LockMode == "Toggle" then AimbotService._toggled else AimbotService._held)
        if not engaged or AimbotService._blocked then
            drop()
            cameraChanges:ReleaseProperties()
            return
        end
        local camera = Workspace.CurrentCamera
        if not camera then drop(); return end
        if AimbotService._camera ~= camera then cameraChanges:ReleaseProperties(); AimbotService._camera = camera end
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
        if not assets or not assets.RootPart then drop(); return end
        local velocity = assets.RootPart.AssemblyLinearVelocity
        local prediction = config.Prediction
        local goal = part.Position + Vector3.new(velocity.X * math.clamp(prediction.Horizontal, 0, 1),
            velocity.Y * math.clamp(prediction.Vertical, 0, 1), velocity.Z * math.clamp(prediction.Horizontal, 0, 1))
        if config.ShakeIntensity > 0 then
            local shake = math.clamp(config.ShakeIntensity, 0, CONFIG.SHAKE_MAX)
            goal += Vector3.new(math.noise(AimbotService._time * 10, 5), math.noise(9, AimbotService._time * 10), 0) * shake
        end
        -- Prevent extreme close targets from causing CFrame.lookAt gimbal lock / spin.
        -- Lower hitparts (Torso/HRP) are more likely to end up directly under the camera when close.
        if (goal - camera.CFrame.Position).Magnitude < 2 then drop(); return end
        local projected, visible = camera:WorldToViewportPoint(goal)
        if not visible or projected.Z <= 0 then
            -- Retain the original target while it is off-screen. No replacement selection is made
            -- until the hold bind is released (or a Toggle lock is explicitly turned off).
            if config.StickyAim then return end
            drop()
            cameraChanges:ReleaseProperties()
            return
        end
        local screen = Vector2.new(projected.X, projected.Y)
        local nativeMouseAim = not config.UseCamera and environment.Capabilities.NativeMouseMove
        -- mousemoverel is delivered through the same input path as a player's physical movement.
        -- Treating that expected feedback as a manual pull makes native mouse aim repeatedly drop
        -- its target at low smoothness. Break On Mouse Pull remains available for camera aim.
        if config.BreakOnPull and not nativeMouseAim and AimbotService._lastCursor and not environment:IsMobile()
            and (point - AimbotService._lastCursor).Magnitude > CONFIG.BREAK_PULL_CURSOR_EPSILON
            and (screen - point).Magnitude > math.max(CONFIG.MIN_LOCK_RADIUS_FLOOR, config.MaxLockRadius) then
            AimbotService._lastCursor = point; drop(true); return
        end
        AimbotService._lastCursor = point
        local alpha = AimbotService:SmoothingAlpha(dt, config.Smoothness)
        if not nativeMouseAim then
            if not config.UseCamera and not AimbotService._warnedMouse then
                AimbotService._warnedMouse = true
                bus:Publish("Notify", "Mouse aim fallback", "Native relative mouse movement is unavailable; using camera correction")
            end
            applyCameraCorrection(camera, goal, alpha)
            AimbotService._remainder = Vector2.zero
        else
            cameraChanges:ReleaseProperties()
            local remaining = screen - point
            -- Native relative input reaches the camera on a later update, unlike the synchronous
            -- CFrame path. A capped feedback gain and bounded step keep low smoothness responsive
            -- without the over-correction loop that made mouse aim shake around a target.
            if remaining.Magnitude <= CONFIG.MOUSE_DEADZONE then
                AimbotService._remainder = Vector2.zero
                return
            end
            local delta = remaining * math.min(alpha, CONFIG.MOUSE_MAX_ALPHA)
            -- The executor receives relative pixels, so retain sub-pixel movement between frames.
            local remainder = AimbotService._remainder
            if remaining.X * remainder.X < 0 then remainder = Vector2.new(0, remainder.Y) end
            if remaining.Y * remainder.Y < 0 then remainder = Vector2.new(remainder.X, 0) end
            local total = delta + remainder
            local x = clampAxis(math.round(total.X), math.sign(remaining.X) * math.floor(math.abs(remaining.X)))
            local y = clampAxis(math.round(total.Y), math.sign(remaining.Y) * math.floor(math.abs(remaining.Y)))
            x = math.clamp(x, -CONFIG.MOUSE_MAX_STEP, CONFIG.MOUSE_MAX_STEP)
            y = math.clamp(y, -CONFIG.MOUSE_MAX_STEP, CONFIG.MOUSE_MAX_STEP)
            AimbotService._remainder = Vector2.new(math.clamp(total.X - x, -1, 1), math.clamp(total.Y - y, -1, 1))
            if x ~= 0 or y ~= 0 then
                local moved, reason = environment:MouseMove(x, y)
                if not moved then
                    if not AimbotService._warnedMouse then
                        AimbotService._warnedMouse = true
                        bus:Publish("Notify", "Mouse aim fallback", reason or "Native mouse movement failed; using camera correction")
                    end
                    applyCameraCorrection(camera, goal, alpha)
                    AimbotService._remainder = Vector2.zero
                end
            end
        end

    end

    function AimbotService:SmoothingAlpha(dt: number, smoothness: number): number
        return 1 - math.exp(-dt * (CONFIG.SMOOTHING_REFERENCE_RATE / math.clamp(smoothness, CONFIG.SMOOTHNESS_MIN, CONFIG.SMOOTHNESS_MAX)))
    end

    function AimbotService:GetTarget(): Player? return self._target end

    function AimbotService:GetPreferredTarget(): Player? return self._preferredTarget end

    function AimbotService:SetPreferredTarget(player: Player?): (boolean, string)
        if not player or player == Players.LocalPlayer or player.Parent ~= Players then
            return false, "Select another player who is still in the server"
        end
        self._preferredTarget = player
        -- Apply an intentional selection immediately when aim is already engaged. The next update
        -- still validates this player with the normal team/friend/visibility/range safeguards.
        self._target, self._remainder = player, Vector2.zero
        state:SetTransient("AimbotPreferredTarget", player)
        state:SetTransient("AimbotTarget", player)
        return true, `{player.Name} will take priority while eligible`
    end

    function AimbotService:ClearPreferredTarget(): (boolean, string)
        local previous = self._preferredTarget
        self._preferredTarget = nil
        state:SetTransient("AimbotPreferredTarget", nil)
        if self._target == previous then drop() end
        return true, if previous then "Manual target cleared" else "No manual target was selected"
    end

    function AimbotService:Unlock() self._held, self._toggled, self._blocked = false, false, false; drop() end

    function AimbotService:Initialize()
        if self._initialized then return end
        self._initialized = true
        scope:Connect(Players.PlayerRemoving, function(player: Player)
            if AimbotService._preferredTarget == player then AimbotService:ClearPreferredTarget() end
        end)
        -- The default RMB bind is often marked as processed by Roblox camera controls. It is still
        -- the player's explicit aim-lock input, so accept the configured bind rather than dropping
        -- it behind processed/UI state; output remains entirely client-side camera correction.
        scope:Connect(UIS.InputBegan, function(event: InputObject, _processed: boolean)
            if not environment:MatchesInput(event, state:Get("Aimbot.Keybind")) then return end
            AimbotService._held, AimbotService._blocked = true, false
            if state:Peek("Aimbot.LockMode") == "Toggle" then
                AimbotService._toggled = not AimbotService._toggled
                if not AimbotService._toggled then
                    drop()
                    cameraChanges:ReleaseProperties()
                end
            else
                AimbotService._toggled = false
            end
        end)
        scope:Connect(UIS.InputEnded, function(event: InputObject)
            if not environment:MatchesInput(event, state:Get("Aimbot.Keybind")) then return end
            AimbotService._held, AimbotService._blocked = false, false
            if state:Peek("Aimbot.LockMode") == "Hold" then
                drop()
                cameraChanges:ReleaseProperties()
            end
        end)
        local job = scheduler:RegisterCamera("Combat.Aimbot", 10, update)
        local function syncAimbot(value: boolean)
            job.Enabled = value == true
            if not value then AimbotService:Unlock(); cameraChanges:ReleaseProperties() end
        end
        scope:Add(state:Observe("Aimbot.Enabled", syncAimbot))
        syncAimbot(state:Peek("Aimbot.Enabled") == true)
    end

    function AimbotService:Destroy() self:Unlock(); scope:Dispose() end

    scope:Add(function() drop() end)
    return AimbotService
end
