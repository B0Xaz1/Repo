local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CONFIG = table.freeze({
    REMOTE_SCAN_LIMIT = 400,
})

return function(services: any, Aura: any?): any
    local StateStore = services:Get("StateStore")
    local Disposer = services:Get("Disposer")
    local LocalPlayer = Players.LocalPlayer

    local Aura = Aura or {}
    local manifest = Aura.Manifest
    local gunConfig = manifest.Gun
    local auraConfig = manifest.Aura
    local scope = Disposer:CreateChild(`{manifest.Name}.KillAura`)

    local KillAura = {
        _remote = nil :: Instance?,
        _remoteChecked = -math.huge,
        _lastShot = -math.huge,
        _shots = 0,
        _misses = 0,
        _lastTarget = "none",
    }

    local function isRemote(node: Instance?): boolean
        return node ~= nil and (node:IsA("RemoteEvent") or node:IsA("RemoteFunction"))
    end

    -- `ReplicatedStorage.Gun` is the documented path; the named sweep is the fallback for
    -- places that nest or rename it, throttled so a missing remote costs one scan every
    -- few seconds instead of one per frame
    local function getRemote(now: number): Instance?
        local cached = KillAura._remote
        if cached and cached.Parent and isRemote(cached) then return cached end
        if now - KillAura._remoteChecked < gunConfig.RemoteRetryDelay then return nil end
        KillAura._remoteChecked = now
        KillAura._remote = nil

        local node: any = ReplicatedStorage
        for _, name in ipairs(gunConfig.Remote) do
            node = node and node:FindFirstChild(name)
        end
        if isRemote(node) then
            KillAura._remote = node
            return node
        end

        for _, name in ipairs(gunConfig.RemoteNames) do
            local direct = ReplicatedStorage:FindFirstChild(name)
            if isRemote(direct) then
                KillAura._remote = direct
                return direct
            end
        end

        local seen = 0
        for _, candidate in ipairs(ReplicatedStorage:GetDescendants()) do
            seen += 1
            if seen > CONFIG.REMOTE_SCAN_LIMIT then break end
            for _, name in ipairs(gunConfig.RemoteNames) do
                if candidate.Name == name and isRemote(candidate) then
                    KillAura._remote = candidate
                    return candidate
                end
            end
        end
        return nil
    end

    -- Equipped tool first, then the backpack, matching the original script
    local function getWeaponName(): string?
        local character = LocalPlayer.Character
        if character then
            for _, item in ipairs(character:GetChildren()) do
                if item:IsA("Tool") then return item.Name end
            end
        end
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                if item:IsA("Tool") then return item.Name end
            end
        end
        return nil
    end

    local function currentRate(): number
        local value = tonumber(StateStore:Get("Game.ZombieAuraRate"))
        if not value then return auraConfig.DefaultRate end
        return math.clamp(value, auraConfig.MinRate, auraConfig.MaxRate)
    end

    local function currentRange(): number
        local value = tonumber(StateStore:Get("Game.ZombieAuraRange"))
        return if value and value > 0 then math.min(value, auraConfig.MaxRange) else 0
    end

    local function currentPart(): string
        local value = StateStore:Get("Game.ZombieAuraPart")
        return if type(value) == "string" and value ~= "" then value else manifest.Aim.Parts[1]
    end

    local function buildPayload(weaponName: string, part: BasePart, origin: Vector3): any
        local direction = (part.Position - origin).Unit * gunConfig.DirectionMagnitude
        return {
            Normal = { gunConfig.Normal[1], gunConfig.Normal[2], gunConfig.Normal[3] },
            Direction = { direction.X, direction.Y, direction.Z },
            Name = weaponName,
            Hit = part,
            Origin = { origin.X, origin.Y, origin.Z },
            Pos = { part.Position.X, part.Position.Y, part.Position.Z },
        }
    end

    local function fireAt(target: any, now: number): (boolean, string)
        local remote = getRemote(now)
        if not remote then
            KillAura._misses += 1
            return false, `No {gunConfig.Remote[#gunConfig.Remote]} remote in ReplicatedStorage`
        end
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then return false, "No HumanoidRootPart" end
        local part = target and target.Part
        if not part or not part.Parent then return false, "Target part is gone" end
        local weaponName = getWeaponName()
        if not weaponName then
            KillAura._misses += 1
            return false, "No weapon equipped"
        end

        local origin = root.Position + Vector3.new(0, gunConfig.OriginHeight, 0)
        local payload = buildPayload(weaponName, part, origin)
        local ok, err = pcall(function()
            if remote:IsA("RemoteFunction") then remote:InvokeServer(payload) else remote:FireServer(payload) end
        end)
        if not ok then
            KillAura._misses += 1
            return false, tostring(err)
        end

        KillAura._shots += 1
        KillAura._lastTarget = if target.Model then target.Model.Name else "unknown"
        return true, weaponName
    end

    local function tick(now: number)
        if StateStore:Get("Game.ZombieAura") ~= true then return end
        -- While the farm runs it owns targeting; firing here too would alternate targets through the same gate
        if StateStore:Get("Game.ZombieFarm") == true then return end
        if now - KillAura._lastShot < currentRate() then return end

        local target = Aura.Targets and Aura.Targets:GetNearest(currentPart(), currentRange())
        if not target then return end

        -- Gating on the attempt rather than the result keeps a weaponless loop from spinning
        -- at frame rate; the original only advanced its timer after a successful shot
        KillAura._lastShot = now
        fireAt(target, now)
    end

    function KillAura:FireOnce(): (boolean, string)
        local target = Aura.Targets and Aura.Targets:GetNearest(currentPart(), currentRange())
        if not target then return false, "No zombie in range" end
        return fireAt(target, os.clock())
    end

    -- Shares the remote, the payload, and the rate gate, so a second driver cannot outrun the
    -- configured fire rate. The third result separates "waited for the gate" from "tried and missed"
    function KillAura:FireAtTarget(target: any): (boolean, string, boolean)
        local now = os.clock()
        if now - KillAura._lastShot < currentRate() then return false, "Rate limited", false end
        KillAura._lastShot = now
        local ok, message = fireAt(target, now)
        return ok, message, true
    end

    function KillAura:Reset(_reason: string?)
        self._lastShot = -math.huge
        self._lastTarget = "none"
    end

    function KillAura:GetStatus(): any
        return {
            Enabled = StateStore:Get("Game.ZombieAura") == true,
            Shots = self._shots,
            Misses = self._misses,
            Target = self._lastTarget,
            Weapon = getWeaponName() or "none",
            Remote = if self._remote and self._remote.Parent then self._remote:GetFullName() else "not found",
        }
    end

    function KillAura:Initialize()
        scope:Add(RunService.Heartbeat:Connect(function()
            pcall(tick, os.clock())
        end))
        scope:Add(LocalPlayer.CharacterAdded:Connect(function()
            self:Reset("respawn")
        end))
    end

    function KillAura:Destroy()
        scope:Dispose()
    end

    return KillAura
end
