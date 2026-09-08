--!nonstrict
-- Prison Life melee: punch aura and burst punching behind an isolated remote service.
-- The meleeEvent remote name never leaks into the rest of the plugin; every action passes
-- through a rate limiter and the shared role/team/friend/whitelist/force-field/LOS checks.
return function(services: any, Prison: any?): any
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local Disposer = services:Get("Disposer")
    local PlayerTracker = services:Get("PlayerTracker")
    local TargetFilter = services:Get("TargetFilter")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local UserInputService = game:GetService("UserInputService")
    local Players = game:GetService("Players")

    local Prison = Prison or {}
    local manifest = Prison.Manifest
    local scope = Disposer:CreateChild("PrisonLife.Melee")
    local LocalPlayer = Players.LocalPlayer

    local MeleeService = {
        _lastAction = 0,
        _remote = nil :: any,
        _loop = nil :: thread?,
        _actions = 0,
        _lastTarget = "None",
    }

    function MeleeService:GetRemote(): any?
        if self._remote and self._remote.Parent then return self._remote end
        local remote = ReplicatedStorage:FindFirstChild(manifest.Melee.RemoteName)
        if remote then self._remote = remote end
        return self._remote
    end

    function MeleeService:CanAct(): boolean
        local now = os.clock()
        local maxPerSecond = math.clamp(tonumber(StateStore:Get("Game.MeleeMaxPerSecond")) or manifest.Melee.DefaultMaxPerSecond, 1, 30)
        local interval = 1 / maxPerSecond
        if now - self._lastAction < interval then return false end
        self._lastAction = now
        return true
    end

    function MeleeService:CooldownRemaining(): number
        local maxPerSecond = math.clamp(tonumber(StateStore:Get("Game.MeleeMaxPerSecond")) or manifest.Melee.DefaultMaxPerSecond, 1, 30)
        local remaining = (1 / maxPerSecond) - (os.clock() - self._lastAction)
        return math.max(0, remaining)
    end

    -- Stop conditions shared by every action: dead, typing, unloading, missing remote.
    function MeleeService:CanFight(): (boolean, string?)
        if scope:IsDisposed() then return false, "unloading" end
        if not PlayerTracker:IsAlive(LocalPlayer) then return false, "dead" end
        if UserInputService:GetFocusedTextBox() then return false, "typing" end
        if not self:GetRemote() then return false, "melee remote missing" end
        return true
    end

    function MeleeService:Fire(target: Player): boolean
        local remote = self:GetRemote()
        if not remote then return false end
        local ok = pcall(function() (remote :: any):FireServer(target) end)
        if ok then
            self._actions += 1
            self._lastTarget = target.Name
        end
        return ok
    end

    function MeleeService:GetMeleeConfig(): any
        return {
            TeamCheck = StateStore:Get("Game.MeleeTeamCheck") == true,
            FriendCheck = StateStore:Get("Game.MeleeFriendCheck") == true,
            WhitelistCheck = StateStore:Get("Game.MeleeWhitelistCheck") == true,
            ForceFieldCheck = StateStore:Get("Game.MeleeForceFieldCheck") == true,
            VisCheck = StateStore:Get("Game.MeleeLOS") == true,
            MaxDistance = math.clamp(tonumber(StateStore:Get("Game.PunchAuraRange")) or manifest.Melee.DefaultRange, 1, 200),
        }
    end

    -- Candidate pipeline: universal checks first, then the Prison Life role gate.
    function MeleeService:GetTargets(): { { Player: Player, Distance: number, Health: number } }
        local assets = PlayerTracker:GetLocalAssets()
        if not assets then return {} end
        local config = self:GetMeleeConfig()
        local range = config.MaxDistance
        local selectedRole = StateStore:Get("Game.MeleeTargetRole") or "Any"
        local candidates = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local targetAssets = PlayerTracker:GetPlayerAssets(player)
                if targetAssets and targetAssets.Humanoid.Health > 0 then
                    local part = targetAssets.RootPart
                    if TargetFilter:ValidateTarget(player, part, config) then
                        if Prison.Context and Prison.Context:ValidateTargetRole(player) then
                            local role = Prison.Context:GetPlayerRole(player)
                            if selectedRole == "Any" or role == selectedRole then
                                local distance = (targetAssets.RootPart.Position - assets.RootPart.Position).Magnitude
                                if distance <= range then
                                    table.insert(candidates, {
                                        Player = player, Distance = distance, Health = targetAssets.Humanoid.Health,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
        return candidates
    end

    function MeleeService:PickTarget(candidates: { any }): any?
        local priority = StateStore:Get("Game.MeleePriority") or "Nearest"
        table.sort(candidates, function(a: any, b: any)
            if priority == "Lowest Health" then
                if a.Health ~= b.Health then return a.Health < b.Health end
            end
            return a.Distance < b.Distance
        end)
        return candidates[1]
    end

    function MeleeService:Pulse(): boolean
        local ok, reason = self:CanFight()
        if not ok then
            if reason == "dead" or reason == "unloading" then return false end
            return true -- paused (typing or missing remote): keep the loop alive
        end
        if not StateStore:Get("Game.PunchAura") then return false end
        if not self:CanAct() then return true end
        local candidates = self:GetTargets()
        local target = self:PickTarget(candidates)
        if not target then return true end
        local hits = if StateStore:Get("Game.SuperPunch") == true
            then math.clamp(tonumber(StateStore:Get("Game.SuperPunchHits")) or 10, 1, 25) else 1
        for _ = 1, hits do
            if not self:Fire(target.Player) then break end
        end
        return true
    end

    function MeleeService:StartLoop()
        if self._loop and coroutine.status(self._loop) ~= "dead" then return end
        self._loop = scope:Spawn(function()
            while not scope:IsDisposed() do
                if not MeleeService:Pulse() then break end
                task.wait(0.1)
            end
            MeleeService._loop = nil
        end)
    end

    function MeleeService:StopLoop(reason: string?)
        if self._loop and self._loop ~= coroutine.running() and coroutine.status(self._loop) ~= "dead" then
            task.cancel(self._loop)
        end
        self._loop = nil
        EventBus:Publish("PrisonMeleeChanged", self:GetStatus())
        if reason then EventBus:Publish("Notify", "Prison Life", "Punch aura stopped: " .. reason) end
    end

    function MeleeService:GetStatus(): any
        return {
            Enabled = StateStore:Get("Game.PunchAura") == true,
            Running = self._loop ~= nil,
            Ready = self:CooldownRemaining() <= 0,
            Cooldown = self:CooldownRemaining(),
            Actions = self._actions,
            LastTarget = self._lastTarget,
            RemoteFound = self:GetRemote() ~= nil,
        }
    end

    function MeleeService:Initialize()
        self:GetRemote()
        scope:Add(StateStore:Observe("Game.PunchAura", function(enabled: any)
            if enabled == true then
                self:StartLoop()
            else
                self:StopLoop()
            end
            EventBus:Publish("PrisonMeleeChanged", self:GetStatus())
        end))
        -- Death ends the aura; respawn restarts it only if the toggle is still on.
        scope:Add(PlayerTracker:OnLocalCharacterRespawn(function()
            if StateStore:Get("Game.PunchAura") == true then
                task.wait(0.5)
                if not scope:IsDisposed() and StateStore:Get("Game.PunchAura") == true then self:StartLoop() end
            end
        end))
        if StateStore:Get("Game.PunchAura") == true then self:StartLoop() end
    end

    function MeleeService:Destroy()
        self:StopLoop()
        scope:Dispose()
    end

    return MeleeService
end
