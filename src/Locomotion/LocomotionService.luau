--!nonstrict
return function(services: any): any
    local state, tracker, scheduler = services:Get("StateStore"), services:Get("PlayerTracker"), services:Get("TaskScheduler")
    local environment, filter = services:Get("Environment"), services:Get("TargetFilter")
    local scope = services:Get("Disposer"):CreateChild("LocomotionService")
    local characterChanges, cameraChanges = scope:CreateChild("Humanoid overrides"), scope:CreateChild("Camera FOV")
    local worldChanges, positionChanges = scope:CreateChild("World gravity"), scope:CreateChild("Position changes")
    local workspace, input, players = game:GetService("Workspace"), game:GetService("UserInputService"), game:GetService("Players")
    local runService = game:GetService("RunService")
    local LocomotionService = { _humanoid = nil, _root = nil, _camera = nil, _bookmarks = {}, _jumpStates = {},
        _flingScope = nil, _flingTarget = nil, _flingElapsed = 0, _initialized = false }

    local function suppress(duration: number)
        state:SetTransient("AntiFlingSuppressUntil", math.max(state:GetTransient("AntiFlingSuppressUntil") or 0, os.clock() + duration))
    end
    local function stopFling()
        if LocomotionService._flingScope then LocomotionService._flingScope:Dispose(); LocomotionService._flingScope = nil end
        LocomotionService._flingTarget = nil
        state:SetTransient("FlingTarget", nil)
        state:Set("Movement.Fling", false, true)
        suppress(1)
    end
    local function teleportRoot(owner: any, root: BasePart, target: CFrame)
        suppress(1.5)
        owner:SetProperty(root, "AssemblyLinearVelocity", Vector3.zero, true)
        owner:SetProperty(root, "AssemblyAngularVelocity", Vector3.zero, true)
        owner:SetProperty(root, "CFrame", target, true)
    end
    function LocomotionService:Teleport(target: any): (boolean, string)
        local assets = tracker:GetLocalAssets()
        if not assets then return false, "Your character is not ready" end
        if typeof(target) == "Vector3" then target = CFrame.new(target) * assets.RootPart.CFrame.Rotation end
        if typeof(target) ~= "CFrame" then return false, "Teleport requires a CFrame or Vector3" end
        teleportRoot(positionChanges, assets.RootPart, target)
        return true, "Teleported"
    end
    function LocomotionService:TeleportToPlayer(player: Player): (boolean, string)
        local assets = player and tracker:GetPlayerAssets(player)
        if not assets then return false, "Target character is not ready" end
        return self:Teleport(assets.RootPart.CFrame + Vector3.new(3, 0, 0))
    end
    function LocomotionService:TeleportToScreen(point: Vector2): (boolean, string)
        local camera = workspace.CurrentCamera
        if not camera then return false, "Camera is not ready" end
        local ray = camera:ViewportPointToRay(point.X, point.Y)
        local hit = filter:Raycast(ray.Origin, ray.Direction * 10000)
        if not hit then return false, "No surface at this point" end
        local assets = tracker:GetLocalAssets()
        if not assets then return false, "Your character is not ready" end
        local clearance = math.max(3, assets.Humanoid.HipHeight + assets.RootPart.Size.Y / 2)
        return self:Teleport(hit.Position + Vector3.new(0, clearance, 0))
    end
    function LocomotionService:SaveBookmark(name: string): (boolean, string)
        name = tostring(name):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 64)
        if name == "" then return false, "Enter a bookmark name" end
        local assets = tracker:GetLocalAssets()
        if not assets then return false, "Your character is not ready" end
        self._bookmarks[name] = assets.RootPart.CFrame
        services:Get("EventBus"):Publish("BookmarksChanged")
        return true, "Bookmarked " .. name
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
        services:Get("EventBus"):Publish("BookmarksChanged")
        return true, "Bookmark removed"
    end
    function LocomotionService:FlingPlayer(player: Player): (boolean, string)
        if not player or player == players.LocalPlayer or not tracker:IsAlive(player) then return false, "Select a living target" end
        if state:Get("Movement.FlyEnabled") then return false, "Stop flight before a fling attack" end
        local assets = tracker:GetLocalAssets()
        if not assets then return false, "Your character is not ready" end
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

    local function update(dt: number)
        local config = state:Peek("Movement")
        local fov = state:Peek("Camera.FOV")
        if not LocomotionService._flingTarget and not config.CFrameSpeed and config.Speed <= 0 and config.JumpPower <= 0
            and not config.SprintEnabled and config.WorldGravity <= 0 and (not fov or fov <= 0) then
            if LocomotionService._applied then
                characterChanges:RestoreProperties(); positionChanges:RestoreProperties()
                worldChanges:RestoreProperties(); cameraChanges:RestoreProperties()
                LocomotionService._applied = false
            end
            return
        end
        LocomotionService._applied = true
        local assets = tracker:GetLocalAssets()
        if assets and LocomotionService._humanoid ~= assets.Humanoid then
            characterChanges:RestoreProperties(); positionChanges:RestoreProperties(); stopFling()
            LocomotionService._humanoid, LocomotionService._root = assets.Humanoid, assets.RootPart
        elseif not assets then characterChanges:RestoreProperties(); positionChanges:RestoreProperties(); stopFling(); LocomotionService._humanoid = nil end
        if assets then
            local humanoid, root = assets.Humanoid, assets.RootPart
            local sprint = config.SprintEnabled and not input:GetFocusedTextBox() and not state:GetTransient("IsBindingKey") and input:IsKeyDown(Enum.KeyCode.LeftShift)
            local speed = if sprint then config.SprintSpeed else config.Speed
            if speed > 0 then characterChanges:SetProperty(humanoid, "WalkSpeed", math.clamp(speed, 1, 300)) else characterChanges:RestoreProperty(humanoid, "WalkSpeed") end
            if config.JumpPower > 0 then characterChanges:SetProperty(humanoid, "JumpPower", math.clamp(config.JumpPower, 0, 300))
            else characterChanges:RestoreProperty(humanoid, "JumpPower") end
            if config.CFrameSpeed and not config.FlyEnabled and not LocomotionService._flingTarget then
                suppress(0.3)
                -- Bound hitch displacement: resuming a paused client must not jump hundreds of studs in one step.
                positionChanges:SetProperty(root, "CFrame", root.CFrame + humanoid.MoveDirection * math.clamp(config.CFrameSpeedValue, 0, 200) * math.min(dt, 0.1), true)
            end
        else characterChanges:RestoreProperties() end
        if config.WorldGravity > 0 then worldChanges:SetProperty(workspace, "Gravity", math.clamp(config.WorldGravity, 0.1, 1000))
        else worldChanges:RestoreProperties() end
        local camera = workspace.CurrentCamera
        if camera ~= LocomotionService._camera then cameraChanges:RestoreProperties(); LocomotionService._camera = camera end
        if camera and fov and fov > 0 then cameraChanges:SetProperty(camera, "FieldOfView", math.clamp(fov, 20, 120))
        else cameraChanges:RestoreProperties() end
        if LocomotionService._flingTarget then
            local target = tracker:GetPlayerAssets(LocomotionService._flingTarget)
            LocomotionService._flingElapsed += dt
            if not assets or not target or target.Humanoid.Health <= 0 or not state:Get("Movement.Fling")
                or LocomotionService._flingElapsed >= 2 then stopFling(); return end
            suppress(1)
            local owner, root = LocomotionService._flingScope, assets.RootPart
            local angle = LocomotionService._flingElapsed * 24
            teleportRoot(owner, root, target.RootPart.CFrame * CFrame.new(math.cos(angle) * 1.5, 0, math.sin(angle) * 1.5))
            owner:SetProperty(root, "AssemblyAngularVelocity", Vector3.new(0, 1500, 0), true)
            owner:SetProperty(root, "AssemblyLinearVelocity", Vector3.new(math.cos(angle) * 400, 100, math.sin(angle) * 400), true)
        end
    end
    local function touchFlingLoop()
        -- Heartbeat / RenderStepped / Stepped order is the fling: replicate a huge impulse, then restore locally before physics.
        local movel = 0.1
        while not scope:IsDisposed() do
            if not state:Peek("Movement.TouchFling") or LocomotionService._flingTarget then
                task.wait(0.25)
                continue
            end
            runService.Heartbeat:Wait()
            if scope:IsDisposed() then break end
            if not state:Peek("Movement.TouchFling") or LocomotionService._flingTarget then continue end
            local character = players.LocalPlayer and players.LocalPlayer.Character
            if not character then continue end
            local hrp = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
            if not hrp then continue end
            suppress(0.3)
            local ok, oldVelocity = pcall(function() return hrp.Velocity end)
            if not ok or typeof(oldVelocity) ~= "Vector3" then continue end
            pcall(function() hrp.Velocity = oldVelocity * 10000 + Vector3.new(0, 10000, 0) end)
            runService.RenderStepped:Wait()
            if scope:IsDisposed() then break end
            if hrp.Parent then pcall(function() hrp.Velocity = oldVelocity end) end
            runService.Stepped:Wait()
            if scope:IsDisposed() then break end
            if hrp.Parent then pcall(function() hrp.Velocity = oldVelocity + Vector3.new(0, movel, 0) end) end
            movel *= -1
        end
    end
    function LocomotionService:Initialize()
        if self._initialized then return end
        self._initialized = true
        scope:Spawn(touchFlingLoop)
        scope:Add(scheduler:RegisterHeartbeat("Movement.Overrides", 10, update))
        scope:Connect(input.JumpRequest, function()
            if not state:Get("Movement.InfJump") or input:GetFocusedTextBox() then return end
            local assets = tracker:GetLocalAssets()
            if assets and assets.Humanoid.Health > 0 then
                if LocomotionService._jumpStates[assets.Humanoid] == nil then LocomotionService._jumpStates[assets.Humanoid] = assets.Humanoid:GetState() end
                assets.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
        scope:Connect(input.InputBegan, function(event: InputObject, processed: boolean)
            if processed or input:GetFocusedTextBox() or state:GetTransient("IsBindingKey") or not state:Get("Settings.TpToMouse") then return end
            if event.UserInputType == Enum.UserInputType.MouseButton1 and (input:IsKeyDown(Enum.KeyCode.LeftControl) or input:IsKeyDown(Enum.KeyCode.RightControl)) then
                LocomotionService:TeleportToScreen(input:GetMouseLocation() - environment:GetGuiInset())
            end
        end)
        scope:Connect(input.TouchTapInWorld, function(point: Vector2, processed: boolean)
            if processed or not environment:IsMobile() or not state:Get("Settings.TpToMouse") or state:GetTransient("IsBindingKey") then return end
            LocomotionService:TeleportToScreen(point - environment:GetGuiInset())
        end)
        scope:Add(tracker:OnLocalCharacterRespawn(function() stopFling() end))
        scope:Add(state:Observe("Movement.Fling", function(value: boolean) if not value then stopFling() end end))
    end
    function LocomotionService:Destroy() scope:Dispose() end
    scope:Add(function()
        stopFling()
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
    end)
    return LocomotionService
end
