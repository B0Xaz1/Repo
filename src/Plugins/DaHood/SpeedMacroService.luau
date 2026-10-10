local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CONFIG = table.freeze({
    PUSH_RATE = 1.8, -- seconds^-1; accelerates along input rather than steering velocity toward it
    MAX_STEP = 0.05, -- avoid an oversized impulse after a delayed frame
    NO_BOOST_NORMAL_Y = 0.8, -- roughly 37 degrees: no boost on steep inclines
    FULL_BOOST_NORMAL_Y = 0.985, -- roughly 10 degrees: full boost on nearly flat ground
    GROUND_CHECK_EXTRA = 1.5,
})

return function(services: any, manifest: any): any
    local state = services:Get("StateStore")
    local tracker = services:Get("PlayerTracker")
    local scope = services:Get("Disposer"):CreateChild("DaHood.SpeedMacro")
    local groundRay = RaycastParams.new()
    groundRay.FilterType = Enum.RaycastFilterType.Exclude
    groundRay.IgnoreWater = true
    local Macro = { _armed = false, _humanoid = nil, _root = nil, _character = nil, _initialized = false }

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

    function Macro:Stop()
        self._armed = false
        self._humanoid, self._root, self._character = nil, nil, nil
        -- Never zero or restore velocity: existing momentum (especially in the air) is physical.
    end

    local function apply(dt: number)
        if not Macro._armed then return end
        local assets = tracker:GetLocalAssets()
        -- A hold belongs to the character it began on. Never transfer it to a respawn.
        if not assets or assets.Humanoid ~= Macro._humanoid or assets.RootPart ~= Macro._root
            or assets.Character ~= Macro._character or assets.Humanoid.Health <= 0 then
            Macro:Stop()
            return
        end

        -- Activation only arms the macro. S is required for every velocity write in both modes.
        if not UIS:IsKeyDown(Enum.KeyCode.S) then return end
        local humanoid, root = assets.Humanoid, assets.RootPart
        -- In freefall / flight / swimming, do not write velocity at all: preserve the whole vector.
        if humanoid.FloorMaterial == Enum.Material.Air or humanoid.Sit or humanoid.PlatformStand then return end
        local motionState = humanoid:GetState()
        if motionState == Enum.HumanoidStateType.Freefall or motionState == Enum.HumanoidStateType.Jumping
            or motionState == Enum.HumanoidStateType.Flying or motionState == Enum.HumanoidStateType.Swimming then return end
        local direction = humanoid.MoveDirection
        local planarDirection = Vector3.new(direction.X, 0, direction.Z)
        if planarDirection.Magnitude < 0.05 then return end

        local groundDistance = math.max(3, humanoid.HipHeight + root.Size.Y / 2 + CONFIG.GROUND_CHECK_EXTRA)
        local hit = Workspace:Raycast(root.Position, Vector3.new(0, -groundDistance, 0), groundRay)
        if not hit then return end
        local incline = math.clamp((hit.Normal.Y - CONFIG.NO_BOOST_NORMAL_Y)
            / (CONFIG.FULL_BOOST_NORMAL_Y - CONFIG.NO_BOOST_NORMAL_Y), 0, 1)
        if incline <= 0 then return end

        local speed = math.clamp(tonumber(state:Peek("Game.DaHoodMacroSpeed")) or manifest.Macro.DefaultSpeed,
            manifest.Macro.MinSpeed, manifest.Macro.MaxSpeed)
        local current = root.AssemblyLinearVelocity
        local horizontal = Vector3.new(current.X, 0, current.Z)
        -- Old-style macro slides keep their heading as the camera turns. Push in the desired
        -- direction instead of snapping the existing velocity toward MoveDirection: strafing
        -- curves, and reversing first bleeds off forward momentum before moving backward.
        local impulse = planarDirection.Unit * (speed * CONFIG.PUSH_RATE * math.clamp(dt, 0, CONFIG.MAX_STEP) * incline)
        local boosted = horizontal + impulse
        local currentSpeed = horizontal.Magnitude
        if boosted.Magnitude > speed then
            if currentSpeed <= speed then
                boosted = boosted.Unit * speed
            elseif boosted.Magnitude >= currentSpeed then
                return -- already above the slider's cap: do not inject more speed
            end
        end
        -- Ground-only horizontal push. No braking or velocity writes on release or in the air.
        root.AssemblyLinearVelocity = Vector3.new(boosted.X, current.Y, boosted.Z)
    end

    function Macro:Initialize()
        if self._initialized then return end
        self._initialized = true
        scope:ConnectImmediate(UIS.InputBegan, function(input: InputObject, processed: boolean)
            if processed or state:Peek("Game.DaHoodMacroEnabled") ~= true
                or UIS:GetFocusedTextBox() or state:GetTransient("IsBindingKey") then return end
            local key = boundKey()
            if not key or not matches(input, key) then return end
            if activationMode() == "Toggle" and self._armed then self:Stop(); return end
            if self._armed then return end
            local assets = tracker:GetLocalAssets()
            if not assets or assets.Humanoid.Health <= 0 then return end
            self._humanoid, self._root, self._character, self._armed =
                assets.Humanoid, assets.RootPart, assets.Character, true
            groundRay.FilterDescendantsInstances = { assets.Character }
            apply(1 / 60)
        end)
        scope:ConnectImmediate(UIS.InputEnded, function(input: InputObject)
            local key = boundKey()
            if self._armed and activationMode() == "Hold" and key and matches(input, key) then self:Stop() end
        end)
        scope:ConnectImmediate(UIS.WindowFocusReleased, function() self:Stop() end)
        scope:ConnectImmediate(Players.LocalPlayer.CharacterRemoving, function() self:Stop() end)
        scope:Add(state:Observe("Game.DaHoodMacroEnabled", function(enabled: boolean)
            if enabled ~= true then self:Stop() end
        end))
        scope:Add(state:Observe("Game.DaHoodMacroKey", function() self:Stop() end))
        scope:Add(state:Observe("Game.DaHoodMacroMode", function() self:Stop() end))
        scope:Add(services:Get("TaskScheduler"):RegisterHeartbeat("Game.DaHood.SpeedMacro", 20, function(dt: number)
            if not self._armed then return end
            local key = boundKey()
            if state:Peek("Game.DaHoodMacroEnabled") ~= true or not key
                or (activationMode() == "Hold" and not isDown(key))
                or UIS:GetFocusedTextBox() or state:GetTransient("IsBindingKey") then
                self:Stop()
                return
            end
            apply(dt)
        end))
    end

    function Macro:Destroy()
        self:Stop()
        scope:Dispose()
    end

    return Macro
end
