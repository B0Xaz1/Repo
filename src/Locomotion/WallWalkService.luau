--!strict
local Workspace = game:GetService("Workspace")

local CONFIG = table.freeze({
    HIP_HEIGHT_OFFSET = 1,
    RAY_LENGTH = 25,
    FEELER_LENGTH = 4,
    FEELER_RADIUS = 3.5,
    DOWN_RAYS = 16,
    FEELER_RAYS = 8,
    TRANSITION = 0.15,
    FORCE_SCALE = 200 / 3,
})

return function(services: any): any
    local state, tracker, scheduler = services:Get("StateStore"), services:Get("PlayerTracker"), services:Get("TaskScheduler")
    local scope = services:Get("Disposer"):CreateChild("WallWalkService")
    local changes = scope:CreateChild("Wall walk properties")
    local WallWalkService = { _active = false, _root = nil, _walkScope = nil, _gyro = nil, _force = nil,
        _gravityUp = Vector3.yAxis, _initialized = false }

    function WallWalkService:Stop()
        self._active, self._root = false, nil
        if self._walkScope then self._walkScope:Dispose(); self._walkScope = nil end
        self._gyro, self._force = nil, nil
        self._gravityUp = Vector3.yAxis
        changes:RestoreProperties()
    end

    local function findSurface(character: Model, root: BasePart, oldUp: Vector3): Vector3
        local params = RaycastParams.new(); params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { character }
        local origin = root.Position + oldUp * 0.35
        local radial = if math.abs(root.CFrame.LookVector:Dot(oldUp)) < 0.999 then root.CFrame.LookVector:Cross(oldUp) else root.CFrame.RightVector:Cross(oldUp)
        local normal, hits = Vector3.zero, 0
        local center = Workspace:Raycast(origin, -oldUp * CONFIG.RAY_LENGTH, params)
        if center then normal += center.Normal; hits += 1 end
        for index = 1, CONFIG.DOWN_RAYS do
            local angle = math.pi * 2 * ((index - 1) / CONFIG.DOWN_RAYS)
            local offset = CFrame.fromAxisAngle(oldUp, angle) * radial
            local result = Workspace:Raycast(origin + offset * 2.5, (-oldUp * 3 + offset).Unit * CONFIG.RAY_LENGTH, params)
            if result then normal += result.Normal; hits += 1 end
        end
        for index = 1, CONFIG.FEELER_RAYS do
            local angle = math.pi * 2 * ((index - 1) / CONFIG.FEELER_RAYS)
            local offset = CFrame.fromAxisAngle(oldUp, angle) * radial
            local result = Workspace:Raycast(origin + offset * 2, (offset * CONFIG.FEELER_RADIUS - oldUp * 3).Unit * CONFIG.FEELER_LENGTH, params)
            if result then normal += result.Normal * 2; hits += 1 end
        end
        return if hits > 0 and normal.Magnitude > 0 then normal.Unit else oldUp
    end

    function WallWalkService:Initialize()
        if self._initialized then return end
        self._initialized = true
        local job = scheduler:RegisterHeartbeat("Movement.WallWalk", 15, function(_dt: number)
            if not state:Peek("Movement.WallWalkEnabled") then self:Stop(); return end
            local assets = tracker:GetLocalAssets()
            if not assets or assets.Humanoid.Health <= 0 then self:Stop(); return end
            local root, humanoid = assets.RootPart, assets.Humanoid
            if self._root ~= root then self:Stop(); self._root = root end
            if not self._active then
                self._active = true
                self._walkScope = scope:CreateChild("Wall walk cycle")
                local owner = self._walkScope
                local gyro = Instance.new("BodyGyro"); gyro.Name, gyro.MaxTorque, gyro.P, gyro.D, gyro.CFrame, gyro.Parent = "B0XazWallWalkGyro", Vector3.new(math.huge, math.huge, math.huge), 90000, 900, root.CFrame, root; owner:Add(gyro)
                local force = Instance.new("VectorForce"); force.Name, force.RelativeTo, force.ApplyAtCenterOfMass, force.Parent = "B0XazWallWalkForce", Enum.ActuatorRelativeTo.World, true, root; owner:Add(force)
                force.Attachment0 = if humanoid.RigType == Enum.HumanoidRigType.R15 then root:FindFirstChild("RootRigAttachment") else root:FindFirstChild("RootAttachment")
                if not force.Attachment0 then self:Stop(); return end
                self._gyro, self._force = gyro, force
                changes:SetProperty(humanoid, "AutoRotate", false)
                changes:SetProperty(humanoid, "HipHeight", humanoid.HipHeight + CONFIG.HIP_HEIGHT_OFFSET)
            end
            local normal = findSurface(assets.Character, root, self._gravityUp)
            self._gravityUp = self._gravityUp:Lerp(normal, math.clamp(CONFIG.TRANSITION * dt * 60, 0, 1)).Unit
            local camera = Workspace.CurrentCamera
            local forward = (camera and camera.CFrame.LookVector or root.CFrame.LookVector) - self._gravityUp * (camera and camera.CFrame.LookVector or root.CFrame.LookVector):Dot(self._gravityUp)
            if forward.Magnitude < 0.01 then forward = root.CFrame.LookVector - self._gravityUp * root.CFrame.LookVector:Dot(self._gravityUp) end
            forward = forward.Unit
            local right = forward:Cross(self._gravityUp).Unit
            local move = humanoid.MoveDirection
            local worldMove = right * move:Dot(right) + forward * move:Dot(forward)
            if worldMove.Magnitude > 1 then worldMove = worldMove.Unit end
            local velocity = root.AssemblyLinearVelocity
            local tangent = velocity - velocity:Dot(self._gravityUp) * self._gravityUp
            local delta = worldMove * humanoid.WalkSpeed - tangent
            local walkForce = if delta.Magnitude > 0.01 then delta.Unit * math.min(10000, CONFIG.FORCE_SCALE * root.AssemblyMass * delta.Magnitude / math.max(dt * 60, 1)) else Vector3.zero
            self._force.Force = walkForce + Workspace.Gravity * root.AssemblyMass * (Vector3.yAxis - self._gravityUp)
            self._gyro.CFrame = CFrame.lookAt(Vector3.zero, if worldMove.Magnitude > 0.01 then worldMove else forward, self._gravityUp)
        end)
        local function sync(value: boolean) job.Enabled = value == true; if not value then self:Stop() end end
        scope:Add(state:Observe("Movement.WallWalkEnabled", sync)); sync(state:Peek("Movement.WallWalkEnabled") == true)
        scope:Add(tracker:OnLocalCharacterRespawn(function() self:Stop() end))
    end

    function WallWalkService:Destroy() scope:Dispose() end
    scope:Add(function() WallWalkService:Stop() end)
    return WallWalkService
end