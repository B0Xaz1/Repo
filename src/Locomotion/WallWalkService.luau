--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CONFIG = table.freeze({
    RAY_DISTANCE = 4,
    GRAVITY_FORCE = 196.2,
    ORIENTATION_RESPONSIVENESS = 35,
})

return function(services: any): any
    local state, tracker, scheduler = services:Get("StateStore"), services:Get("PlayerTracker"), services:Get("TaskScheduler")
    local scope = services:Get("Disposer"):CreateChild("WallWalkService")
    local changes = scope:CreateChild("Wall walk properties")
    local WallWalkService = { _active = false, _root = nil, _walkScope = nil, _attachment = nil, _orientation = nil, _force = nil, _initialized = false }

    function WallWalkService:Stop()
        self._active, self._root = false, nil
        if self._walkScope then self._walkScope:Dispose(); self._walkScope = nil end
        self._attachment, self._orientation, self._force = nil, nil, nil
        changes:RestoreProperties()
    end

    local function findSurface(character: Model, root: BasePart): Vector3?
        local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances = { character }
        local directions = { root.CFrame.UpVector, -root.CFrame.UpVector, root.CFrame.RightVector, -root.CFrame.RightVector,
            root.CFrame.LookVector, -root.CFrame.LookVector }
        for _, direction in ipairs(directions) do
            local hit = Workspace:Raycast(root.Position, direction * CONFIG.RAY_DISTANCE, params)
            if hit and math.abs(hit.Normal.Y) < 0.92 then return hit.Normal end
        end
        return nil
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
            local normal = findSurface(assets.Character, root)
            if not normal then self:Stop(); return end
            if not self._active then
                self._active = true
                self._walkScope = scope:CreateChild("Wall walk cycle")
                local owner = self._walkScope
                local attachment = Instance.new("Attachment"); attachment.Name, attachment.Parent = "B0XazWallWalkAttachment", root; owner:Add(attachment)
                local orientation = Instance.new("AlignOrientation"); orientation.Name, orientation.Mode, orientation.Responsiveness = "B0XazWallWalkOrientation", Enum.OrientationAlignmentMode.OneAttachment, CONFIG.ORIENTATION_RESPONSIVENESS
                orientation.Attachment0, orientation.Parent = attachment, root; owner:Add(orientation)
                local force = Instance.new("VectorForce"); force.Name, force.RelativeTo, force.Attachment0, force.Parent = "B0XazWallWalkGravity", Enum.ActuatorRelativeTo.World, attachment, root; owner:Add(force)
                self._attachment, self._orientation, self._force = attachment, orientation, force
                changes:SetProperty(humanoid, "AutoRotate", false)
            end
            local forward = humanoid.MoveDirection
            local tangent = forward - normal * forward:Dot(normal)
            local look = if tangent.Magnitude > 0.01 then tangent.Unit else root.CFrame.LookVector
            self._orientation.CFrame = CFrame.lookAt(Vector3.zero, look, normal)
            self._force.Force = (Vector3.yAxis - normal) * root.AssemblyMass * CONFIG.GRAVITY_FORCE
        end)
        local function sync(value: boolean) job.Enabled = value == true; if not value then self:Stop() end end
        scope:Add(state:Observe("Movement.WallWalkEnabled", sync)); sync(state:Peek("Movement.WallWalkEnabled") == true)
        scope:Add(tracker:OnLocalCharacterRespawn(function() self:Stop() end))
    end

    function WallWalkService:Destroy() scope:Dispose() end
    scope:Add(function() WallWalkService:Stop() end)
    return WallWalkService
end