local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CONFIG = table.freeze({
    PUSH_RATE = 4, -- stronger camera-forward ground acceleration, still additive for drifting
    FACING_RESPONSE = 18, -- smooth yaw toward camera without snapping or moving the root
    MAX_STEP = 0.05, -- avoid an oversized impulse after a delayed frame
    MIN_PUSH_FACTOR = 0.35, -- geometry never stalls the glide completely while the engine reports ground contact
    STEEP_NORMAL_Y = 0.5, -- roughly 60 degrees: below this the slope scaling bottoms out at MIN_PUSH_FACTOR
    FULL_BOOST_NORMAL_Y = 0.9, -- roughly 25 degrees: full boost on anything flatter
    GROUND_CHECK_EXTRA = 1.5,
    GROUND_CHECK_LIFT = 1, -- probe from above the root so a clipped stance or an edge still finds the floor
    FACING_EPSILON = 0.002, -- skip a facing write too small to see
    NOTICE_COOLDOWN = 5,
})

-- Why a hold ended. Only interruptions the player did not ask for may resume on their own: a hold
-- that survived chat, a keybind re-record, or a one-frame asset hiccup used to stay dead until the
-- activation key was released and pressed again, which read as the macro randomly breaking.
local RESUMABLE = table.freeze({ typing = true, binding = true, focus = true, unresolved = true })

return function(services: any, manifest: any): any
    local state = services:Get("StateStore")
    local tracker = services:Get("PlayerTracker")
    local bus = services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("DaHood.SpeedMacro")
    local facingOwner = scope:CreateChild("Camera-facing glide")
    local groundRay = RaycastParams.new()
    groundRay.FilterType = Enum.RaycastFilterType.Exclude
    groundRay.IgnoreWater = true
    local Macro = {
        _armed = false, _humanoid = nil, _root = nil, _character = nil, _initialized = false,
        _resume = false, _windowFocused = true, _rayCharacter = nil, _stoppedCharacter = nil,
        _block = "", _speed = 0, _target = 0, _error = nil, _lastNotice = nil, _lastNoticeAt = -math.huge,
    }

    local function boundKey(): EnumItem?
        local key = state:Peek("Game.DaHoodMacroKey")
        if typeof(key) ~= "EnumItem" then return nil end
        -- S is the required movement input; binding activation to S would bypass V + S.
        if key.EnumType == Enum.KeyCode and key ~= Enum.KeyCode.Unknown and key ~= Enum.KeyCode.S then return key end
        if key == Enum.UserInputType.MouseButton1 or key == Enum.UserInputType.MouseButton2
            or key == Enum.UserInputType.MouseButton3 then return key end
        return nil
    end

    local function activationMode(): string
        return if state:Peek("Game.DaHoodMacroMode") == "Toggle" then "Toggle" else "Hold"
    end

    local function matches(input: InputObject, key: EnumItem): boolean
        return input.KeyCode == key or input.UserInputType == key
    end

    local function isDown(key: EnumItem): boolean
        return if key.EnumType == Enum.KeyCode then UIS:IsKeyDown(key) else UIS:IsMouseButtonPressed(key)
    end

    -- One report per reason per cooldown, so a repeated frame-level problem is visible without
    -- filling the notification stack
    function Macro:Report(message: string)
        if message == "" then return end
        local now = os.clock()
        if self._lastNotice == message and now - self._lastNoticeAt < CONFIG.NOTICE_COOLDOWN then return end
        self._lastNotice, self._lastNoticeAt = message, now
        bus:Publish("Notify", "Da Hood macro", message)
    end

    function Macro:Stop(reason: string?)
        self._armed = false
        self._resume = reason ~= nil and RESUMABLE[reason] == true
        self._stoppedCharacter = self._character
        self._humanoid, self._root, self._character = nil, nil, nil
        facingOwner:RestoreProperties() -- return AutoRotate to its previous owner/value
        -- Never zero or restore velocity: existing momentum (especially in the air) is physical.
    end

    local function cameraForward(): Vector3?
        local camera = Workspace.CurrentCamera
        if not camera then return nil end
        local look = camera.CFrame.LookVector
        local horizontal = Vector3.new(look.X, 0, look.Z)
        return if horizontal.Magnitude >= 0.05 then horizontal.Unit else nil
    end

    -- The engine's own contact report. Freefall, jump, flight, and swim keep the whole velocity
    -- vector untouched, and a stale FloorMaterial is caught by the motion state.
    local function onFloor(humanoid: any): boolean
        if humanoid.FloorMaterial == Enum.Material.Air then return false end
        local motionState = humanoid:GetState()
        return motionState ~= Enum.HumanoidStateType.Freefall and motionState ~= Enum.HumanoidStateType.Jumping
            and motionState ~= Enum.HumanoidStateType.Flying and motionState ~= Enum.HumanoidStateType.Swimming
    end

    -- Slope scaling for the push. A probe that misses (a floor that is not queryable, a ledge, a
    -- stance clipped into geometry) used to cancel the glide outright; ground contact is already
    -- established by onFloor, so a miss now means "push at full strength" and steep geometry means
    -- "push gently" instead of stalling.
    local function groundFactor(humanoid: any, root: any, character: any): number
        if Macro._rayCharacter ~= character then
            Macro._rayCharacter = character
            groundRay.FilterDescendantsInstances = { character }
        end
        local lift = CONFIG.GROUND_CHECK_LIFT
        local distance = math.max(3, humanoid.HipHeight + root.Size.Y / 2 + CONFIG.GROUND_CHECK_EXTRA) + lift
        local hit = Workspace:Raycast(root.Position + Vector3.new(0, lift, 0), Vector3.new(0, -distance, 0), groundRay)
        if not hit then return 1 end
        local scaled = math.clamp((hit.Normal.Y - CONFIG.STEEP_NORMAL_Y)
            / (CONFIG.FULL_BOOST_NORMAL_Y - CONFIG.STEEP_NORMAL_Y), 0, 1)
        return math.max(scaled, CONFIG.MIN_PUSH_FACTOR)
    end

    local function face(dt: number)
        if not Macro._armed or not UIS:IsKeyDown(Enum.KeyCode.S) or UIS:GetFocusedTextBox()
            or state:GetTransient("IsBindingKey") then
            facingOwner:RestoreProperties()
            return
        end
        local key = boundKey()
        if not key then Macro:Stop("unbound"); return end
        if state:Peek("Game.DaHoodMacroEnabled") ~= true then Macro:Stop("disabled"); return end
        if activationMode() == "Hold" and not isDown(key) then Macro:Stop("released"); return end
        local assets = tracker:GetLocalAssets()
        if not assets then Macro:Stop("unresolved"); return end
        if assets.Humanoid ~= Macro._humanoid or assets.RootPart ~= Macro._root
            or assets.Character ~= Macro._character or assets.Humanoid.Health <= 0 then
            Macro:Stop("character")
            return
        end
        local humanoid, root = assets.Humanoid, assets.RootPart
        if humanoid.Sit or humanoid.PlatformStand then facingOwner:RestoreProperties(); return end
        local forward = cameraForward()
        if not forward then facingOwner:RestoreProperties(); return end
        facingOwner:SetProperty(humanoid, "AutoRotate", false, true)
        -- Keep the character facing where S propels it, not where normal S walking points.
        -- Only rotate on the ground; airborne momentum and orientation are left alone.
        if not onFloor(humanoid) then return end
        local currentLook = root.CFrame.LookVector
        local yaw = math.atan2(-currentLook.X, -currentLook.Z)
        local targetYaw = math.atan2(-forward.X, -forward.Z)
        local gap = (targetYaw - yaw + math.pi) % (2 * math.pi) - math.pi
        if math.abs(gap) < CONFIG.FACING_EPSILON then return end
        local alpha = 1 - math.exp(-CONFIG.FACING_RESPONSE * math.clamp(dt, 0, CONFIG.MAX_STEP))
        -- Turning the root is a teleport, and a teleport can cost the assembly its velocity. Hand
        -- the momentum straight back so facing the glide can never cancel the glide itself.
        local velocity = root.AssemblyLinearVelocity
        root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw + gap * alpha, 0)
        root.AssemblyLinearVelocity = velocity
    end

    local function apply(dt: number)
        if not Macro._armed then return end
        local assets = tracker:GetLocalAssets()
        if not assets or not assets.RootPart.Parent or not assets.Humanoid.Parent then
            Macro:Stop("unresolved")
            return
        end
        -- A hold belongs to the character it began on. Never transfer it to a respawn.
        if assets.Humanoid ~= Macro._humanoid or assets.RootPart ~= Macro._root
            or assets.Character ~= Macro._character or assets.Humanoid.Health <= 0 then
            Macro:Stop("character")
            return
        end

        local humanoid, root = assets.Humanoid, assets.RootPart
        local speed = math.clamp(tonumber(state:Peek("Game.DaHoodMacroSpeed")) or manifest.Macro.DefaultSpeed,
            manifest.Macro.MinSpeed, manifest.Macro.MaxSpeed)
        local current = root.AssemblyLinearVelocity
        local horizontal = Vector3.new(current.X, 0, current.Z)
        Macro._target, Macro._speed = speed, horizontal.Magnitude

        -- Activation only arms the macro. S is required for every velocity write in both modes.
        if not UIS:IsKeyDown(Enum.KeyCode.S) then Macro._block = "S is not held"; return end
        -- In freefall / flight / swimming, do not write velocity at all: preserve the whole vector.
        if humanoid.Sit or humanoid.PlatformStand or not onFloor(humanoid) then
            Macro._block = if humanoid.Sit then "sitting" elseif humanoid.PlatformStand then "platform stand" else "airborne"
            return
        end
        local forward = cameraForward()
        if not forward then Macro._block = "camera is vertical"; return end
        -- S normally moves backward. The macro instead pushes forward along the camera;
        -- side input can bend the glide without changing its forward direction.
        local movement = humanoid.MoveDirection
        local planarMovement = Vector3.new(movement.X, 0, movement.Z)
        local sideways = planarMovement - forward * planarMovement:Dot(forward)
        local glideDirection = (forward + sideways * 0.35).Unit

        local incline = groundFactor(humanoid, root, assets.Character)
        -- Counter only ordinary S walking speed so the first grounded frame can move forward,
        -- but let larger existing backward momentum bleed off over time rather than snapping.
        local backward = math.max(0, -horizontal:Dot(forward))
        local walkCorrection = math.min(backward, math.max(0, humanoid.WalkSpeed))
        local impulse = forward * walkCorrection
            + glideDirection * (speed * CONFIG.PUSH_RATE * math.clamp(dt, 0, CONFIG.MAX_STEP) * incline)
        local boosted = horizontal + impulse
        if boosted.X ~= boosted.X or boosted.Z ~= boosted.Z then
            -- A NaN write would be rejected by the engine and, repeated, would trip the scheduler's
            -- circuit breaker and silently end the macro for the rest of the session
            Macro._block = "velocity is not a number"
            return
        end
        -- The slider caps the push, but it is never a reason to go silent: above the cap the glide
        -- keeps steering at the speed the player already has instead of stopping dead.
        local ceiling = math.max(speed, horizontal.Magnitude)
        if boosted.Magnitude > ceiling then boosted = boosted.Unit * ceiling end
        -- Ground-only horizontal push. No braking or velocity writes on release or in the air.
        root.AssemblyLinearVelocity = Vector3.new(boosted.X, current.Y, boosted.Z)
        Macro._block, Macro._error = "", nil
    end

    -- Re-arms a hold that an interruption ended while the player is still holding everything down.
    -- An explicit release, a respawn, a rebind, or a mode change never resumes on its own.
    function Macro:Resume()
        if not self._resume then return end
        if not self._windowFocused then return end
        if state:Peek("Game.DaHoodMacroEnabled") ~= true then self._resume = false; return end
        local key = boundKey()
        if not key then self._resume = false; return end
        if activationMode() == "Hold" and not isDown(key) then self._resume = false; return end
        if UIS:GetFocusedTextBox() or state:GetTransient("IsBindingKey") then return end
        if not UIS:IsKeyDown(Enum.KeyCode.S) then return end
        local assets = tracker:GetLocalAssets()
        if not assets or assets.Humanoid.Health <= 0 then return end
        -- Only ever back onto the character the hold was interrupted on
        if assets.Character ~= self._stoppedCharacter then self._resume = false; return end
        self:Arm(assets)
    end

    function Macro:Arm(assets: any)
        self._humanoid, self._root, self._character, self._armed =
            assets.Humanoid, assets.RootPart, assets.Character, true
        self._resume, self._block, self._error = false, "", nil
        groundRay.FilterDescendantsInstances = { assets.Character }
        self._rayCharacter = assets.Character
        apply(1 / 60)
    end

    function Macro:GetStatus(): any
        return {
            Armed = self._armed, Mode = activationMode(), Block = self._block, Error = self._error,
            Speed = self._speed, Target = self._target, Resumable = self._resume,
        }
    end

    function Macro:Initialize()
        if self._initialized then return end
        self._initialized = true
        scope:ConnectImmediate(UIS.InputBegan, function(input: InputObject, processed: boolean)
            if processed or state:Peek("Game.DaHoodMacroEnabled") ~= true
                or UIS:GetFocusedTextBox() or state:GetTransient("IsBindingKey") then return end
            local key = boundKey()
            if not key or not matches(input, key) then return end
            if activationMode() == "Toggle" and self._armed then self:Stop("toggle"); return end
            if self._armed then return end
            local assets = tracker:GetLocalAssets()
            if not assets or assets.Humanoid.Health <= 0 then return end
            self:Arm(assets)
        end)
        scope:ConnectImmediate(UIS.InputEnded, function(input: InputObject)
            if input.KeyCode == Enum.KeyCode.S then facingOwner:RestoreProperties() end
            local key = boundKey()
            if self._armed and activationMode() == "Hold" and key and matches(input, key) then self:Stop("released") end
        end)
        scope:ConnectImmediate(UIS.WindowFocused, function() Macro._windowFocused = true end)
        scope:ConnectImmediate(UIS.WindowFocusReleased, function()
            Macro._windowFocused = false
            self:Stop("focus")
        end)
        scope:ConnectImmediate(Players.LocalPlayer.CharacterRemoving, function() self:Stop("character") end)
        scope:Add(state:Observe("Game.DaHoodMacroEnabled", function(enabled: boolean)
            if enabled ~= true then self:Stop("disabled") end
        end))
        scope:Add(state:Observe("Game.DaHoodMacroKey", function() self:Stop("rebound") end))
        scope:Add(state:Observe("Game.DaHoodMacroMode", function() self:Stop("mode") end))
        scope:Add(services:Get("TaskScheduler"):RegisterCamera("Game.DaHood.MacroFacing", 20, function(dt: number)
            -- The facing pass must not be able to disable itself: an error here would leave the
            -- character turning with no push behind it
            local ok, err = pcall(face, dt)
            if ok then return end
            Macro._error = tostring(err)
            Macro:Report(`Facing error: {Macro._error}`)
        end))
        scope:Add(services:Get("TaskScheduler"):RegisterHeartbeat("Game.DaHood.SpeedMacro", 20, function(dt: number)
            local ok, err = pcall(function()
                if not Macro._armed then Macro:Resume(); return end
                local key = boundKey()
                if state:Peek("Game.DaHoodMacroEnabled") ~= true then Macro:Stop("disabled"); return end
                if not key then Macro:Stop("unbound"); return end
                if activationMode() == "Hold" and not isDown(key) then Macro:Stop("released"); return end
                if UIS:GetFocusedTextBox() then Macro:Stop("typing"); return end
                if state:GetTransient("IsBindingKey") then Macro:Stop("binding"); return end
                apply(dt)
            end)
            if ok then return end
            -- Reported instead of rethrown: five consecutive throws would open the scheduler's
            -- circuit breaker and end the macro for the rest of the session
            Macro._error = tostring(err)
            Macro:Report(`Speed error: {Macro._error}`)
        end))
    end

    function Macro:Destroy()
        self:Stop("destroyed")
        scope:Dispose()
    end

    return Macro
end
