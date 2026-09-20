local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

export type ZombieTarget = {
    Model: Instance,
    Humanoid: Humanoid,
    Part: BasePart,
    Root: BasePart,
    Distance: number,
}

return function(_services: any, Aura: any?): any
    local LocalPlayer = Players.LocalPlayer

    local Aura = Aura or {}
    local manifest = Aura.Manifest
    local enemyConfig = manifest.Enemies
    local aimConfig = manifest.Aim

    local Targets = { _container = nil :: Instance?, _scanned = 0 }

    local function findContainer(): Instance?
        local cached = Targets._container
        if cached and cached.Parent then return cached end
        Targets._container = nil

        for _, name in ipairs(enemyConfig.Containers) do
            local direct = Workspace:FindFirstChild(name)
            if direct then
                Targets._container = direct
                return direct
            end
        end

        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") then
                for _, name in ipairs(enemyConfig.Containers) do
                    if child.Name:lower() == name:lower() then
                        Targets._container = child
                        return child
                    end
                end
            end
        end
        return nil
    end

    function Targets:GetContainerName(): string
        local container = findContainer()
        return if container then container:GetFullName() else "not found"
    end

    local function resolvePart(model: Instance, preferred: string): BasePart?
        local wanted = model:FindFirstChild(preferred)
        if wanted and wanted:IsA("BasePart") then return wanted end
        for _, name in ipairs(aimConfig.Parts) do
            local fallback = model:FindFirstChild(name)
            if fallback and fallback:IsA("BasePart") then return fallback end
        end
        local primary = model.PrimaryPart
        return if primary and primary:IsA("BasePart") then primary else nil
    end

    -- The aim part is often a head, so anything that stands the player off the body anchors
    -- on the root instead rather than two studs above the skull
    local function resolveRoot(model: Instance, fallback: BasePart): BasePart
        local root = model:FindFirstChild("HumanoidRootPart")
        if root and root:IsA("BasePart") then return root end
        local primary = model.PrimaryPart
        return if primary and primary:IsA("BasePart") then primary else fallback
    end

    -- Walks the live zombies once; the scan is capped so an oversized container cannot stall a frame
    local function forEachAlive(callback: (model: Instance, humanoid: Humanoid) -> ()): number
        local container = findContainer()
        if not container then return 0 end
        local scanned = 0
        for _, child in ipairs(container:GetChildren()) do
            if scanned >= enemyConfig.MaxScan then break end
            if child:IsA("Model") and child ~= LocalPlayer.Character then
                scanned += 1
                local humanoid = child:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    callback(child, humanoid)
                end
            end
        end
        return scanned
    end

    function Targets:CountAlive(): number
        local count = 0
        self._scanned = forEachAlive(function() count += 1 end)
        return count
    end

    function Targets:GetScanned(): number
        return self._scanned
    end

    function Targets:GetTargets(preferredPart: string?, maxRange: number?): { ZombieTarget }
        local list: { ZombieTarget } = {}
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then return list end

        local preferred = if type(preferredPart) == "string" and preferredPart ~= "" then preferredPart else aimConfig.Parts[1]
        local limit = tonumber(maxRange) or 0
        local origin = root.Position

        self._scanned = forEachAlive(function(model: Instance, humanoid: Humanoid)
            local part = resolvePart(model, preferred)
            if not part then return end
            local distance = (part.Position - origin).Magnitude
            if limit > 0 and distance > limit then return end
            table.insert(list, { Model = model, Humanoid = humanoid, Part = part, Root = resolveRoot(model, part), Distance = distance })
        end)

        table.sort(list, function(a: ZombieTarget, b: ZombieTarget): boolean
            return a.Distance < b.Distance
        end)
        return list
    end

    function Targets:GetNearest(preferredPart: string?, maxRange: number?): ZombieTarget?
        local targets = self:GetTargets(preferredPart, maxRange)
        return if #targets > 0 then targets[1] else nil
    end

    return Targets
end
