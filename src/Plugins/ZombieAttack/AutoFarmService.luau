local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

return function(services: any, Aura: any?): any
    local StateStore = services:Get("StateStore")
    local Disposer = services:Get("Disposer")
    local LocomotionService = services:Get("LocomotionService")
    local LocalPlayer = Players.LocalPlayer

    local Aura = Aura or {}
    local manifest = Aura.Manifest
    local farmConfig = manifest.Farm
    local scope = Disposer:CreateChild(`{manifest.Name}.AutoFarm`)

    local AutoFarm = {
        _locked = nil :: any?,
        _targets = 0,
        _placements = 0,
        _failures = 0,
        _lockDistance = 0,
        _state = "off",
    }

    local function assets(): (BasePart?, Humanoid?)
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not root or not root:IsA("BasePart") or not humanoid then return nil, nil end
        return root, humanoid
    end

    -- Staying on a target costs a three-field read, so the container scan only runs when it fails
    local function stillLocked(target: any?): boolean
        if not target then return false end
        if not target.Model.Parent or not target.Root.Parent or not target.Part.Parent then return false end
        return target.Humanoid.Health > 0
    end

    -- Part and range come from the kill aura settings, so one pair of controls drives both
    local function acquire(): any?
        if not Aura.Targets then return nil end
        return Aura.Targets:GetNearest(StateStore:Get("Game.ZombieAuraPart"), StateStore:Get("Game.ZombieAuraRange"))
    end

    -- Behind the zombie's own facing rather than the camera's, so the lock holds as it turns
    local function engageFrame(target: any): CFrame
        local anchor = target.Root
        local spot = anchor.Position - anchor.CFrame.LookVector * farmConfig.BackOffset + Vector3.new(0, farmConfig.UpOffset, 0)
        return CFrame.lookAt(spot, anchor.Position)
    end

    local function tick()
        if StateStore:Get("Game.ZombieFarm") ~= true then
            AutoFarm._state = "off"
            return
        end

        local root, humanoid = assets()
        if not root or not humanoid or humanoid.Health <= 0 then
            AutoFarm._state = "no character"
            return
        end

        if not stillLocked(AutoFarm._locked) then
            local acquired = acquire()
            if not acquired then
                AutoFarm._locked = nil
                AutoFarm._state = "no zombie in range"
                return
            end
            AutoFarm._locked = acquired
            AutoFarm._targets += 1
            AutoFarm._lockDistance = (acquired.Root.Position - root.Position).Magnitude
        end

        local target = AutoFarm._locked
        if LocomotionService:Teleport(engageFrame(target)) then
            AutoFarm._placements += 1
        else
            AutoFarm._failures += 1
        end

        AutoFarm._state = `locked on {target.Model.Name} at {math.floor(target.Humanoid.Health)} hp`
        if not Aura.KillAura then return end
        local fired, reason, attempted = Aura.KillAura:FireAtTarget(target)
        -- Most frames are rate limited, which is normal; anything else is why no zombie is dying
        if attempted and not fired then AutoFarm._state = `{AutoFarm._state}  {reason}` end
    end

    function AutoFarm:GetStatus(): any
        local target = if stillLocked(self._locked) then self._locked else nil
        return {
            Enabled = StateStore:Get("Game.ZombieFarm") == true,
            State = self._state,
            Target = if target then target.Model.Name else "none",
            Health = if target then math.floor(target.Humanoid.Health) else 0,
            LockDistance = self._lockDistance,
            Targets = self._targets,
            Placements = self._placements,
            Failures = self._failures,
        }
    end

    function AutoFarm:Reset(_reason: string?)
        self._locked = nil
        self._state = if StateStore:Get("Game.ZombieFarm") == true then "idle" else "off"
    end

    function AutoFarm:Initialize()
        scope:Add(RunService.Heartbeat:Connect(function()
            pcall(tick)
        end))
        scope:Add(LocalPlayer.CharacterAdded:Connect(function()
            self:Reset("respawn")
        end))
        self:Reset("initialize")
    end

    function AutoFarm:Destroy()
        scope:Dispose()
    end

    return AutoFarm
end
