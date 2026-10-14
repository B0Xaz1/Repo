local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local CONFIG = table.freeze({
    SPEED_MIN = 1,
    SPEED_MAX = 300,
    JUMP_POWER_MAX = 300,
    INF_JUMP_FALLBACK_VELOCITY = 50,
    CFRAME_SPEED_MAX = 200,
    DELTA_TIME_CAP = 0.1,
    GRAVITY_MIN = 0.1,
    GRAVITY_MAX = 1000,
    FOV_MIN = 20,
    FOV_MAX = 120,
    FLING_DURATION = 2,
    FLING_ORBIT_RADIUS = 1.5,
    FLING_SPIN_RATE = 24,
    FLING_ANGULAR_VELOCITY = 1500,
    FLING_ORBIT_SPEED = 400,
    FLING_LIFT = 100,
    SCREEN_RAY_DISTANCE = 10000,
    BOOKMARK_MAX_LENGTH = 64,
    TELEPORT_OFFSET = Vector3.new(3, 0, 0),
    TOUCH_FLING_IDLE_WAIT = 0.25,
    TOUCH_FLING_BOOST = 10000,
    TOUCH_FLING_OFFSET = 0.1,
    TOUCH_TELEPORT_DEBOUNCE = 0.35,
    FOLLOW_DISTANCE = 5,
})

return function(services: any): any
    local state, tracker, scheduler = services:Get("StateStore"), services:Get("PlayerTracker"), services:Get("TaskScheduler")
    local environment, filter, bus = services:Get("Environment"), services:Get("TargetFilter"), services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("LocomotionService")
    local characterChanges, cameraChanges = scope:CreateChild("Humanoid overrides"), scope:CreateChild("Camera FOV")
    local humanoidWatch = scope:CreateChild("Humanoid override watch")
    local noClipChanges = scope:CreateChild("No clip")
    local worldChanges, positionChanges = scope:CreateChild("World gravity"), scope:CreateChild("Position changes")
    local teleportChanges = scope:CreateChild("One-shot teleports")
    local touchTeleportScope = scope:CreateChild("Touch teleport")
    local LocomotionService = { _humanoid = nil, _root = nil, _camera = nil, _bookmarks = {}, _jumpStates = {},
        _flingScope = nil, _flingTarget = nil, _flingElapsed = 0, _followTarget = nil, _followJob = nil, _touchTeleportTarget = nil, _lastTouchTeleport = 0,
        _noClipCharacter = nil, _noClipWatch = nil, _watchedHumanoid = nil, _initialized = false }

    local function suppress(duration: number)
        state:SetTransient("AntiFlingSuppressUntil", math.max(state:GetTransient("AntiFlingSuppressUntil") or 0, os.clock() + duration))
    end

    local function stopFling()
        if LocomotionService._flingScope then LocomotionService._flingScope:Dispose(); LocomotionService._flingScope = nil end
        LocomotionService._flingTarget = nil
        state:SetTransient("FlingTarget", nil)
        state:Set("Movement.Fling", false)
        suppress(1)
    end

    local function teleportRoot(owner: any, root: BasePart, target: CFrame)
        suppress(1.5)
        owner:SetProperty(root, "AssemblyLinearVelocity", Vector3.zero, true)
        owner:SetProperty(root, "AssemblyAngularVelocity", Vector3.zero, true)
        owner:SetProperty(root, "CFrame", target, true)
    end

    -- A one-shot teleport must leave the character where it was placed. Release drops our lease
    -- without restoring the prior CFrame, unlike a sustained movement feature such as fling.
    local function teleportPermanently(root: BasePart, target: CFrame)
        teleportRoot(teleportChanges, root, target)
        teleportChanges:ReleaseProperty(root, "AssemblyLinearVelocity")
        teleportChanges:ReleaseProperty(root, "AssemblyAngularVelocity")
        teleportChanges:ReleaseProperty(root, "CFrame")
    end

    function LocomotionService:Teleport(target: any): (boolean, string)
        local assets = tracker:GetLocalAssets()
        if not assets then return false, "Your character is not ready" end
        if typeof(target) == "Vector3" then target = CFrame.new(target) * assets.RootPart.CFrame.Rotation end
        if typeof(target) ~= "CFrame" then return false, "Teleport requires a CFrame or Vector3" end
        teleportPermanently(assets.RootPart, target)
        return true, "Teleported"
    end

    function LocomotionService:SetTouchTeleportSpot(): (boolean, string)
        local assets = tracker:GetLocalAssets()
        if not assets then return false, "Your character is not ready" end
        self._touchTeleportTarget = assets.RootPart.CFrame
        return true, "Touch teleport destination saved"
    end

    local function bindTouchTeleport(character: Model)
        touchTeleportScope:Dispose()
        touchTeleportScope = scope:CreateChild("Touch teleport")
        local function onTouched(hit: BasePart)
            if not state:Peek("Movement.TouchTeleportEnabled") or not hit or hit:IsDescendantOf(character) then return end
            local target = LocomotionService._touchTeleportTarget
            local assets = tracker:GetLocalAssets()
            if not target or not assets or os.clock() - LocomotionService._lastTouchTeleport < CONFIG.TOUCH_TELEPORT_DEBOUNCE then return end
            LocomotionService._lastTouchTeleport = os.clock()
            teleportPermanently(assets.RootPart, target)
        end
        for _, descendant in ipairs(character:GetDescendants()) do
            if descendant:IsA("BasePart") then touchTeleportScope:ConnectImmediate(descendant.Touched, onTouched) end
        end
        touchTeleportScope:ConnectImmediate(character.DescendantAdded, function(descendant: Instance)
            if descendant:IsA("BasePart") then touchTeleportScope:ConnectImmediate(descendant.Touched, onTouched) end
        end)
    end

    local function stopNoClip()
        local watch = LocomotionService._noClipWatch
        LocomotionService._noClipWatch, LocomotionService._noClipCharacter = nil, nil
        if watch then watch:Dispose() end
        noClipChanges:RestoreProperties()
    end

    local function startNoClip(character: Model)
        if LocomotionService._noClipCharacter == character and LocomotionService._noClipWatch then return end
        stopNoClip()
        local watch = scope:CreateChild("No clip character")
        LocomotionService._noClipCharacter, LocomotionService._noClipWatch = character, watch
        local function apply(part: Instance)
            if not part:IsA("BasePart") or not part.Parent then return end
            noClipChanges:SetProperty(part, "CanCollide", false)
            -- Reassert only when the game changes this particular part instead of walking the
            -- whole character and writing every BasePart on every Heartbeat.
            watch:ConnectImmediate(part:GetPropertyChangedSignal("CanCollide"), function()
                if state:Peek("Movement.NoClip") == true and part.Parent and part.CanCollide then
                    noClipChanges:SetProperty(part, "CanCollide", false, true)
                end
            end)
        end
        for _, descendant in ipairs(character:GetDescendants()) do apply(descendant) end
        watch:ConnectImmediate(character.DescendantAdded, apply)
        watch:ConnectImmediate(character.Destroying, stopNoClip)
    end

    function LocomotionService:TeleportToPlayer(player: Player): (boolean, string)
        local assets = player and tracker:GetPlayerAssets(player)
        if not assets then return false, "Target character is not ready" end
        return self:Teleport(assets.RootPart.CFrame + CONFIG.TELEPORT_OFFSET)
    end

    function LocomotionService:TeleportToScreen(point: Vector2): (boolean, string)
        local camera = Workspace.CurrentCamera
        if not camera then return false, "Camera is not ready" end
        local ray = camera:ViewportPointToRay(point.X, point.Y)
        local hit = filter:Raycast(ray.Origin, ray.Direction * CONFIG.SCREEN_RAY_DISTANCE)
        if not hit then return false, "No surface at this point" end
        local assets = tracker:GetLocalAssets()
        if not assets then return false, "Your character is not ready" end
        local clearance = math.max(3, assets.Humanoid.HipHeight + assets.RootPart.Size.Y / 2)
        return self:Teleport(hit.Position + Vector3.new(0, clearance, 0))
    end

    function LocomotionService:SaveBookmark(name: string): (boolean, string)
        name = tostring(name):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, CONFIG.BOOKMARK_MAX_LENGTH)
        if name == "" then return false, "Enter a bookmark name" end
        local assets = tracker:GetLocalAssets()
        if not assets then return false, "Your character is not ready" end
        self._bookmarks[name] = assets.RootPart.CFrame
        bus:Publish("BookmarksChanged")
        return true, `Bookmarked {name}`
    end

    function LocomotionService:ListBookmarks(): { string }
        local result = {}
        for name in pairs(self._bookmarks) do table.insert(result, name) end
        table.sort(result)
        return result
    end

    function LocomotionService:GoToBookmark(name: string): (boolean, string)
        if not self._bookmarks[name] then return false, "Select a saved bookmark" end
        return self:Teleport(self._bookmarks[name])
    end

    function LocomotionService:DeleteBookmark(name: string): (boolean, string)
        self._bookmarks[name] = nil
        bus:Publish("BookmarksChanged")
        return true, "Bookmark removed"
    end

    function LocomotionService:FlingPlayer(player: Player): (boolean, string)
        if not player or player == Players.LocalPlayer or not tracker:IsAlive(player) then return false, "Select a living target" end
        if state:Get("Movement.FlyEnabled") then return false, "Stop flight before a fling attack" end
        local assets = tracker:GetLocalAssets()
        if not assets then return false, "Your character is not ready" end
        self:StopFollowing()
        stopFling()
        self._flingScope = scope:CreateChild("Fling cycle")
        self._flingTarget, self._flingElapsed = player, 0
        self._flingScope:SetProperty(assets.RootPart, "CFrame", assets.RootPart.CFrame, true)
        self._flingScope:SetProperty(assets.Humanoid, "AutoRotate", false)
        state:SetTransient("FlingTarget", player)
        state:Set("Movement.Fling", true)
        suppress(3)
        return true, "Attempting a two-second fling; server physics may reject it"
    end

    function LocomotionService:StopFling() stopFling() end

    function LocomotionService:GetFollowingTarget(): Player? return self._followTarget end

    function LocomotionService:StopFollowing()
        self._followTarget = nil
        state:SetTransient("FollowTarget", nil)
        if self._followJob then self._followJob.Enabled = false end
        local assets = tracker:GetLocalAssets()
        if assets and assets.Humanoid.Health > 0 then pcall(function() assets.Humanoid:Move(Vector3.zero, false) end) end
    end

    function LocomotionService:StartFollowing(player: Player): (boolean, string)
        if not player or player == Players.LocalPlayer or not player.Parent then return false, "Select another player who is still in the server" end
        local config = state:Peek("Movement")
        if config.FlyEnabled or config.FreecamEnabled or config.WallWalkEnabled or config.CFrameSpeed then return false, "Stop flight, freecam, wall walk, or CFrame speed before following" end
        if self._flingTarget then return false, "Stop the fling before following" end
        local target = tracker:GetPlayerAssets(player)
        if not target or target.Humanoid.Health <= 0 then return false, "Target character is not ready" end
        if self._followTarget == player then return true, `Already following {player.Name}` end
        self:StopFollowing()
        self._followTarget = player
        state:SetTransient("FollowTarget", player)
        if self._followJob then self._followJob.Enabled = true end
        return true, `Following {player.Name}`
    end

    local function updateFollowing()
        local player = LocomotionService._followTarget
        if not player then
            if LocomotionService._followJob then LocomotionService._followJob.Enabled = false end
            return
        end
        if not player.Parent then LocomotionService:StopFollowing(); return end
        local config = state:Peek("Movement")
        if LocomotionService._flingTarget or config.FlyEnabled or config.FreecamEnabled or config.WallWalkEnabled or config.CFrameSpeed then
            LocomotionService:StopFollowing()
            return
        end
        local localAssets, targetAssets = tracker:GetLocalAssets(), tracker:GetPlayerAssets(player)
        if not localAssets or localAssets.Humanoid.Health <= 0 then return end
        -- Keep the requested target through a short death/respawn gap, then resume normally once
        -- PlayerTracker has fresh assets. Following uses standard Humanoid input, never CFrame warps.
        if not targetAssets or targetAssets.Humanoid.Health <= 0 then return end
        local offset = targetAssets.RootPart.Position - localAssets.RootPart.Position
        local horizontal = Vector3.new(offset.X, 0, offset.Z)
        if horizontal.Magnitude <= CONFIG.FOLLOW_DISTANCE then
            localAssets.Humanoid:Move(Vector3.zero, false)
        else
            localAssets.Humanoid:Move(horizontal.Unit, false)
        end
    end

    local function sprintHeld(config: any): boolean
        return config.SprintEnabled == true and not UIS:GetFocusedTextBox() and not state:GetTransient("IsBindingKey")
            and (UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift))
    end

    -- Some experiences set WalkSpeed, JumpPower, or UseJumpPower from their own controller after
    -- a normal client heartbeat. Keep the requested override active through a focused property
    -- watcher rather than relying on one write winning that race.
    local function applyHumanoidOverrides(humanoid: Humanoid)
        local config = state:Peek("Movement")
        -- Freecam owns the character freeze. Releasing our leases first preserves the
        -- Disposer's priority ordering instead of moving a movement override above it.
        if config.FreecamEnabled == true then
            characterChanges:RestoreProperty(humanoid, "WalkSpeed")
            characterChanges:RestoreProperty(humanoid, "JumpPower")
            characterChanges:RestoreProperty(humanoid, "UseJumpPower")
            return
        end
        local speed = if sprintHeld(config) then config.SprintSpeed else config.Speed
        if speed > 0 then
            characterChanges:SetProperty(humanoid, "WalkSpeed", math.clamp(speed, CONFIG.SPEED_MIN, CONFIG.SPEED_MAX), true)
        else
            characterChanges:RestoreProperty(humanoid, "WalkSpeed")
        end
        if config.JumpPower > 0 then
            -- Many games leave UseJumpPower false and consume JumpHeight instead. Enabling this
            -- switch is required for the configured Jump power to have any effect in those rigs.
            characterChanges:SetProperty(humanoid, "UseJumpPower", true, true)
            characterChanges:SetProperty(humanoid, "JumpPower", math.clamp(config.JumpPower, 0, CONFIG.JUMP_POWER_MAX), true)
        else
            characterChanges:RestoreProperty(humanoid, "JumpPower")
            characterChanges:RestoreProperty(humanoid, "UseJumpPower")
        end
    end

    local function bindHumanoidOverrides(humanoid: Humanoid)
        humanoidWatch:Dispose()
        humanoidWatch = scope:CreateChild("Humanoid override watch")
        LocomotionService._watchedHumanoid = humanoid
        local function reapply()
            if scope:IsDisposed() or LocomotionService._watchedHumanoid ~= humanoid or not humanoid.Parent then return end
            applyHumanoidOverrides(humanoid)
        end
        for _, property in ipairs({ "WalkSpeed", "JumpPower", "UseJumpPower" }) do
            humanoidWatch:ConnectImmediate(humanoid:GetPropertyChangedSignal(property), reapply)
        end
    end

    local function clearHumanoidOverrides()
        humanoidWatch:Dispose()
        LocomotionService._watchedHumanoid = nil
    end

    local function update(dt: number)
        local config = state:Peek("Movement")
        local fov = state:Peek("Camera.FOV")
        if not LocomotionService._flingTarget and not config.CFrameSpeed and not config.NoClip and config.Speed <= 0 and config.JumpPower <= 0
            and not config.SprintEnabled and config.WorldGravity <= 0 and (not fov or fov <= 0) then
            if LocomotionService._applied then
                characterChanges:RestoreProperties(); stopNoClip(); positionChanges:ReleaseProperties()
                worldChanges:RestoreProperties(); cameraChanges:RestoreProperties()
                LocomotionService._applied = false
            end
            return
        end
        LocomotionService._applied = true
        local assets = tracker:GetLocalAssets()
        if assets and LocomotionService._humanoid ~= assets.Humanoid then
            -- Disconnect before releasing leases so an outgoing Humanoid cannot reapply a
            -- transition-time override from one of its own property-change signals.
            clearHumanoidOverrides()
            characterChanges:RestoreProperties(); stopNoClip(); positionChanges:ReleaseProperties(); stopFling()
            LocomotionService._humanoid, LocomotionService._root = assets.Humanoid, assets.RootPart
            bindHumanoidOverrides(assets.Humanoid)
        elseif not assets and LocomotionService._humanoid then
            clearHumanoidOverrides()
            characterChanges:RestoreProperties(); stopNoClip(); positionChanges:ReleaseProperties(); stopFling()
            LocomotionService._humanoid = nil
        end
        if assets then
            local humanoid, root = assets.Humanoid, assets.RootPart
            if config.NoClip then
                startNoClip(assets.Character)
            else
                stopNoClip()
            end
            applyHumanoidOverrides(humanoid)
            if config.CFrameSpeed and not config.FlyEnabled and not LocomotionService._flingTarget then
                suppress(0.3)
                positionChanges:SetProperty(root, "CFrame", root.CFrame + humanoid.MoveDirection * math.clamp(config.CFrameSpeedValue, 0, CONFIG.CFRAME_SPEED_MAX) * math.min(dt, CONFIG.DELTA_TIME_CAP), true)
            end
        else characterChanges:RestoreProperties() end
        if config.WorldGravity > 0 then worldChanges:SetProperty(Workspace, "Gravity", math.clamp(config.WorldGravity, CONFIG.GRAVITY_MIN, CONFIG.GRAVITY_MAX))
        else worldChanges:RestoreProperties() end
        local camera = Workspace.CurrentCamera
        if camera ~= LocomotionService._camera then cameraChanges:RestoreProperties(); LocomotionService._camera = camera end
        if camera and fov and fov > 0 then cameraChanges:SetProperty(camera, "FieldOfView", math.clamp(fov, CONFIG.FOV_MIN, CONFIG.FOV_MAX))
        else cameraChanges:RestoreProperties() end
        if LocomotionService._flingTarget then
            local target = tracker:GetPlayerAssets(LocomotionService._flingTarget)
            LocomotionService._flingElapsed += dt
            if not assets or not target or target.Humanoid.Health <= 0 or not state:Get("Movement.Fling")
                or LocomotionService._flingElapsed >= CONFIG.FLING_DURATION then stopFling(); return end
            suppress(1)
            local owner, root = LocomotionService._flingScope, assets.RootPart
            local angle = LocomotionService._flingElapsed * CONFIG.FLING_SPIN_RATE
            teleportRoot(owner, root, target.RootPart.CFrame * CFrame.new(math.cos(angle) * CONFIG.FLING_ORBIT_RADIUS, 0, math.sin(angle) * CONFIG.FLING_ORBIT_RADIUS))
            owner:SetProperty(root, "AssemblyAngularVelocity", Vector3.new(0, CONFIG.FLING_ANGULAR_VELOCITY, 0), true)
            owner:SetProperty(root, "AssemblyLinearVelocity", Vector3.new(math.cos(angle) * CONFIG.FLING_ORBIT_SPEED, CONFIG.FLING_LIFT, math.sin(angle) * CONFIG.FLING_ORBIT_SPEED), true)
        end
    end

    -- A touch fling crosses three engine phases in one cycle: boost, restore, then a lift offset
    -- that alternates each pass; the loop bails out whenever the state flag drops
    local function touchFlingLoop()
        local liftOffset = CONFIG.TOUCH_FLING_OFFSET
        while not scope:IsDisposed() do
            if not state:Peek("Movement.TouchFling") or LocomotionService._flingTarget then
                task.wait(CONFIG.TOUCH_FLING_IDLE_WAIT)
                continue
            end
            RunService.Heartbeat:Wait()
            if scope:IsDisposed() then break end
            if not state:Peek("Movement.TouchFling") or LocomotionService._flingTarget then continue end
            local character = Players.LocalPlayer and Players.LocalPlayer.Character
            if not character then continue end
            local hrp = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
            if not hrp then continue end
            suppress(0.3)
            local ok, oldVelocity = pcall(function() return hrp.Velocity end)
            if not ok or typeof(oldVelocity) ~= "Vector3" then continue end
            pcall(function() hrp.Velocity = oldVelocity * CONFIG.TOUCH_FLING_BOOST + Vector3.new(0, CONFIG.TOUCH_FLING_BOOST, 0) end)
            RunService.RenderStepped:Wait()
            if scope:IsDisposed() then break end
            if hrp.Parent then pcall(function() hrp.Velocity = oldVelocity end) end
            RunService.Stepped:Wait()
            if scope:IsDisposed() then break end
            if hrp.Parent then pcall(function() hrp.Velocity = oldVelocity + Vector3.new(0, liftOffset, 0) end) end
            liftOffset *= -1
        end
    end

    local function getInfiniteJumpVelocity(humanoid: Humanoid): number
        if humanoid.UseJumpPower then
            return math.max(CONFIG.INF_JUMP_FALLBACK_VELOCITY, math.clamp(humanoid.JumpPower, 0, CONFIG.JUMP_POWER_MAX))
        end
        local jumpHeight = math.max(0, humanoid.JumpHeight)
        return math.max(CONFIG.INF_JUMP_FALLBACK_VELOCITY, math.sqrt(2 * Workspace.Gravity * jumpHeight))
    end

    local function requestInfiniteJump(assets: any)
        local humanoid, root = assets.Humanoid, assets.RootPart
        if LocomotionService._jumpStates[humanoid] == nil then LocomotionService._jumpStates[humanoid] = humanoid:GetState() end
        -- Request Roblox's ordinary transition first. The velocity safeguard only covers rigs
        -- that reject or immediately override that state, and intentionally leaves X/Z motion intact.
        pcall(function()
            humanoid.Jump = true
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end)
        if root and root.Parent then
            suppress(0.35)
            local jumpVelocity = getInfiniteJumpVelocity(humanoid)
            pcall(function()
                local velocity = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = Vector3.new(velocity.X, math.max(velocity.Y, jumpVelocity), velocity.Z)
            end)
        end
    end

    function LocomotionService:Initialize()
        if self._initialized then return end
        self._initialized = true
        scope:Spawn(touchFlingLoop)
        scope:Add(scheduler:RegisterHeartbeat("Movement.Overrides", 10, update))
        self._followJob = scheduler:RegisterHeartbeat("Movement.Follow", 12, updateFollowing)
        self._followJob.Enabled = self._followTarget ~= nil
        scope:Add(self._followJob)
        scope:Connect(UIS.JumpRequest, function()
            if not state:Get("Movement.InfJump") or UIS:GetFocusedTextBox() then return end
            local assets = tracker:GetLocalAssets()
            if assets and assets.Humanoid.Health > 0 then requestInfiniteJump(assets) end
        end)
        scope:Connect(UIS.InputBegan, function(event: InputObject, processed: boolean)
            if processed or UIS:GetFocusedTextBox() or state:GetTransient("IsBindingKey") or not state:Get("Settings.TpToMouse") then return end
            if event.UserInputType == Enum.UserInputType.MouseButton1 and (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) then
                LocomotionService:TeleportToScreen(UIS:GetMouseLocation() - environment:GetGuiInset())
            end
        end)
        scope:Connect(UIS.TouchTapInWorld, function(point: Vector2, processed: boolean)
            if processed or not environment:IsMobile() or not state:Get("Settings.TpToMouse") or state:GetTransient("IsBindingKey") then return end
            LocomotionService:TeleportToScreen(point - environment:GetGuiInset())
        end)
        scope:Add(tracker:OnLocalCharacterRespawn(function(assets: any)
            stopFling()
            self._touchTeleportTarget = assets.RootPart.CFrame
            bindTouchTeleport(assets.Character)
        end))
        local assets = tracker:GetLocalAssets()
        if assets then
            self._touchTeleportTarget = assets.RootPart.CFrame
            bindTouchTeleport(assets.Character)
        end
        scope:Add(state:Observe("Movement.Fling", function(value: boolean) if not value then stopFling() end end))
        scope:Add(bus:Subscribe("PlayerLeft", function(player: Player)
            if self._followTarget == player then self:StopFollowing() end
        end))
    end

    function LocomotionService:Destroy() scope:Dispose() end

    scope:Add(function()
        stopFling()
        LocomotionService:StopFollowing()
        stopNoClip()
        local assets = tracker:GetLocalAssets()
        if assets then
            pcall(function()
                assets.RootPart.Velocity = Vector3.zero
                assets.RootPart.AssemblyLinearVelocity = Vector3.zero
            end)
        end
        for humanoid, original in pairs(LocomotionService._jumpStates) do
            if humanoid.Parent and humanoid.Health > 0 then pcall(function() humanoid:ChangeState(original) end) end
        end
        table.clear(LocomotionService._bookmarks); table.clear(LocomotionService._jumpStates)
        touchTeleportScope:Dispose()
    end)
    return LocomotionService
end
