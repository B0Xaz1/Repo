--!strict
local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")

local CONFIG = table.freeze({
    OBJECTS_ASSET = "rbxassetid://17267177523",
    HIP_HEIGHT_OFFSET = 0.5,
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
    local WallWalkService = { _active = false, _root = nil, _walkScope = nil, _collider = nil, _floor = nil, _gyro = nil, _force = nil,
        _gravityUp = Vector3.yAxis, _lastPart = nil, _lastPartCFrame = CFrame.identity, _initialized = false }

    local function createObjects(character: Model, root: BasePart, humanoid: Humanoid, owner: any): (BasePart?, BasePart?, BodyGyro?, VectorForce?)
        local ok, model = pcall(function() return game:GetObjects(CONFIG.OBJECTS_ASSET)[1] end)
        if not ok or not model then return nil, nil, nil, nil end
        local sphereTemplate, floorTemplate = model:FindFirstChild("Sphere"), model:FindFirstChild("Floor")
        local forceTemplate, gyroTemplate = model:FindFirstChild("VectorForce"), model:FindFirstChild("BodyGyro")
        if not sphereTemplate or not floorTemplate or not forceTemplate or not gyroTemplate then model:Destroy(); return nil, nil, nil, nil end
        local sphere, floor = sphereTemplate:Clone(), floorTemplate:Clone()
        sphere.Parent, floor.Parent = character, character
        owner:Add(sphere); owner:Add(floor)
        local height = humanoid.HipHeight + 0.05
        local weld = Instance.new("Weld"); weld.C0, weld.Part0, weld.Part1, weld.Parent = CFrame.new(0, -height, 0.1), root, sphere, sphere; owner:Add(weld)
        local floorWeld = Instance.new("Weld"); floorWeld.C0, floorWeld.Part0, floorWeld.Part1, floorWeld.Parent = CFrame.new(0, -(height + 1.5), 0), root, floor, floor; owner:Add(floorWeld)
        local gyro = gyroTemplate:Clone(); gyro.CFrame, gyro.Parent = root.CFrame, root; owner:Add(gyro)
        local force = forceTemplate:Clone()
        force.Attachment0 = if humanoid.RigType == Enum.HumanoidRigType.R15 then root:FindFirstChild("RootRigAttachment") else root:FindFirstChild("RootAttachment")
        force.Parent = root; owner:Add(force)
        model:Destroy()
        if not force.Attachment0 then return nil, nil, nil, nil end
        return sphere, floor, gyro, force
    end

    function WallWalkService:Stop()
        self._active, self._root = false, nil
        if self._walkScope then self._walkScope:Dispose(); self._walkScope = nil end
        self._collider, self._floor, self._gyro, self._force = nil, nil, nil, nil
        self._gravityUp, self._lastPart, self._lastPartCFrame = Vector3.yAxis, nil, CFrame.identity
        changes:RestoreProperties()
    end

    local function findSurface(character: Model, root: BasePart, collider: BasePart, oldUp: Vector3): Vector3
        local params = RaycastParams.new(); params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { character }
        local origin = collider.Position + oldUp * 0.35
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
        local job = scheduler:RegisterHeartbeat("Movement.WallWalk", 15, function(dt: number)
            if not state:Peek("Movement.WallWalkEnabled") then self:Stop(); return end
            local assets = tracker:GetLocalAssets()
            if not assets or assets.Humanoid.Health <= 0 then self:Stop(); return end
            local root, humanoid = assets.RootPart, assets.Humanoid
            if self._root ~= root then self:Stop(); self._root = root end
            if not self._active then
                self._walkScope = scope:CreateChild("Wall walk cycle")
                local owner = self._walkScope
                local collider, floor, gyro, force = createObjects(assets.Character, root, humanoid, owner)
                if not collider or not floor or not gyro or not force then self:Stop(); return end
                self._active, self._collider, self._floor, self._gyro, self._force = true, collider, floor, gyro, force
                changes:SetProperty(humanoid, "AutoRotate", false)
                changes:SetProperty(humanoid, "PlatformStand", false)
                changes:SetProperty(humanoid, "HipHeight", humanoid.HipHeight + CONFIG.HIP_HEIGHT_OFFSET)
            end
            local originalHipHeight = changes:GetOriginal(humanoid, "HipHeight")
            if typeof(originalHipHeight) == "number" then changes:SetProperty(humanoid, "HipHeight", originalHipHeight + CONFIG.HIP_HEIGHT_OFFSET) end
            local normal = findSurface(assets.Character, root, self._collider, self._gravityUp)
            self._gravityUp = self._gravityUp:Lerp(normal, math.clamp(CONFIG.TRANSITION * dt * 60, 0, 1)).Unit
            local camera = Workspace.CurrentCamera
            local cameraForward = camera and camera.CFrame.LookVector or root.CFrame.LookVector
            local forward = cameraForward - self._gravityUp * cameraForward:Dot(self._gravityUp)
            if forward.Magnitude < 0.01 then forward = root.CFrame.LookVector - self._gravityUp * root.CFrame.LookVector:Dot(self._gravityUp) end
            forward = forward.Unit
            local right = forward:Cross(self._gravityUp).Unit
            local move = humanoid.MoveDirection
            local worldMove = right * move:Dot(right) + forward * move:Dot(forward)
            if worldMove.Magnitude > 1 then worldMove = worldMove.Unit end
            humanoid:Move(worldMove, false)
            local velocity = root.AssemblyLinearVelocity
            local tangent = velocity - velocity:Dot(self._gravityUp) * self._gravityUp
            local delta = worldMove * humanoid.WalkSpeed - tangent
            local walkForce = if delta.Magnitude > 0.01 then delta.Unit * math.min(10000, CONFIG.FORCE_SCALE * root.AssemblyMass * delta.Magnitude / math.max(dt * 60, 1)) else Vector3.zero
            self._force.Force = walkForce + Workspace.Gravity * root.AssemblyMass * (Vector3.yAxis - self._gravityUp)
            self._gyro.CFrame = CFrame.lookAt(Vector3.zero, if worldMove.Magnitude > 0.01 then worldMove else forward, self._gravityUp)
            local params = RaycastParams.new(); params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { assets.Character }
            local surface = Workspace:Raycast(self._collider.Position, -self._gravityUp * 1.1, params)
            if surface and self._lastPart == surface.Instance and self._lastPart.Parent then
                local offset = self._lastPartCFrame:ToObjectSpace(root.CFrame)
                root.CFrame = surface.Instance.CFrame:ToWorldSpace(offset)
            end
            self._lastPart, self._lastPartCFrame = if surface then surface.Instance else Workspace.Terrain, if surface then surface.Instance.CFrame else CFrame.identity
        end)
        local function sync(value: boolean) job.Enabled = value == true; if not value then self:Stop() end end
        scope:Add(state:Observe("Movement.WallWalkEnabled", sync)); sync(state:Peek("Movement.WallWalkEnabled") == true)
        scope:Connect(UIS.JumpRequest, function()
            if not state:Peek("Movement.WallWalkEnabled") or not self._active then return end
            local assets = tracker:GetLocalAssets()
            if not assets or assets.Humanoid.Health <= 0 then return end
            local root, humanoid = assets.RootPart, assets.Humanoid
            local velocity = root.AssemblyLinearVelocity
            local tangent = velocity - velocity:Dot(self._gravityUp) * self._gravityUp
            local jumpSpeed = if humanoid.UseJumpPower then humanoid.JumpPower else math.sqrt(math.max(0, 2 * Workspace.Gravity * humanoid.JumpHeight))
            root.AssemblyLinearVelocity = tangent
            root:ApplyImpulse(self._gravityUp * root.AssemblyMass * jumpSpeed * 1.2)
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end)
        scope:Add(tracker:OnLocalCharacterRespawn(function() self:Stop() end))
    end

    function WallWalkService:Destroy() scope:Dispose() end
    scope:Add(function() WallWalkService:Stop() end)
    return WallWalkService
end
