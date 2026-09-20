local Players = game:GetService("Players")

local CONFIG = table.freeze({
    HITBOX_INTERVAL = 0.2,
    HITBOX_MIN_SIZE = 2,
    HITBOX_MAX_SIZE = 20,
    HITBOX_TRANSPARENCY = 0.65,
    PASSIVE_SCAN_INTERVAL = 0.3,
    FLING_NOTICE_COOLDOWN = 5,
    FLING_FALL_SPEED_CAP = 350,
    FLING_UPWARD_CAP = 250,
    FLING_ANGULAR_CAP = 120,
    SPIN_SPEED_LIMIT = 1440,
})

return function(services: any): any
    local state, tracker, scheduler = services:Get("StateStore"), services:Get("PlayerTracker"), services:Get("TaskScheduler")
    local bus = services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("ExtrasService")
    local guardChanges = scope:CreateChild("Anti-fling recovery")
    local virtualUser: any = nil
    pcall(function() virtualUser = game:GetService("VirtualUser") end)
    local ExtrasService = { _hitboxBackups = {}, _passive = {}, _spinScope = nil, _spinRoot = nil,
        _baseline = nil, _baselineRoot = nil, _guardRoot = nil, _lastNotice = -math.huge, _scanElapsed = 0, _initialized = false }

    local function restoreHitbox(player: Player)
        local backup = ExtrasService._hitboxBackups[player]
        ExtrasService._hitboxBackups[player] = nil
        if backup then backup.Scope:Dispose() end
    end

    local function restorePassive(player: Player)
        local record = ExtrasService._passive[player]
        ExtrasService._passive[player] = nil
        if record then record.Scope:Dispose() end
    end

    local function restoreHitboxes()
        for player in pairs(table.clone(ExtrasService._hitboxBackups)) do restoreHitbox(player) end
    end

    local function restoreDefence()
        for player in pairs(table.clone(ExtrasService._passive)) do restorePassive(player) end
        guardChanges:RestoreProperties()
    end

    local function stopSpin()
        local owner, root = ExtrasService._spinScope, ExtrasService._spinRoot
        ExtrasService._spinScope, ExtrasService._spinRoot = nil, nil
        if owner then
            if root then
                owner:ReleaseProperty(root, "CFrame")
                owner:ReleaseProperty(root, "AssemblyAngularVelocity")
            end
            owner:Dispose()
        end
    end

    local function updateHitboxes()
        local config = state:Peek("Extras.Hitbox")
        if not config.Enabled then restoreHitboxes(); return end
        local size = math.clamp(config.Size, CONFIG.HITBOX_MIN_SIZE, CONFIG.HITBOX_MAX_SIZE)
        for _, player in ipairs(Players:GetPlayers()) do
            if player == Players.LocalPlayer then continue end
            local assets = tracker:GetPlayerAssets(player)
            local backup = ExtrasService._hitboxBackups[player]
            if backup and (not assets or backup.Root ~= assets.RootPart) then restoreHitbox(player); backup = nil end
            if assets then
                local root = assets.RootPart
                if not backup then
                    local owner = scope:CreateChild(`Hitbox {player.UserId}`)
                    backup = { Root = root, Size = root.Size, Transparency = root.Transparency, CanCollide = root.CanCollide, Scope = owner }
                    ExtrasService._hitboxBackups[player] = backup
                end
                backup.Scope:SetProperty(root, "Size", Vector3.new(size, size, size))
                backup.Scope:SetProperty(root, "Transparency", CONFIG.HITBOX_TRANSPARENCY)
                backup.Scope:SetProperty(root, "CanCollide", false)
            end
        end
    end

    local function scanPassive()
        for _, player in ipairs(Players:GetPlayers()) do
            if player == Players.LocalPlayer then continue end
            local assets = tracker:GetPlayerAssets(player)
            local record = ExtrasService._passive[player]
            if record and (not assets or record.Character ~= assets.Character) then restorePassive(player); record = nil end
            if assets then
                if not record then
                    record = { Character = assets.Character, Scope = scope:CreateChild(`Collision defence {player.UserId}`), Parts = {} }
                    ExtrasService._passive[player] = record
                end
                for _, part in ipairs(assets.Character:GetDescendants()) do if part:IsA("BasePart") then record.Parts[part] = true end end
            end
        end
    end

    -- Anti-fling keeps a known-good baseline CFrame and only snaps back once an impulse exceeds
    -- every plausible cap, which keeps ordinary knockback and jumps untouched
    local function antiFling(dt: number)
        local assets = tracker:GetLocalAssets()
        if not assets then restoreDefence(); ExtrasService._baselineRoot = nil; return end
        local root, humanoid = assets.RootPart, assets.Humanoid
        local config = state:Peek("Extras.AntiFling")
        local enabled = config.Enabled
        local suppressed = os.clock() < (state:GetTransient("AntiFlingSuppressUntil") or 0)
        if ExtrasService._guardRoot ~= root then guardChanges:RestoreProperties(); ExtrasService._guardRoot = root end
        if not enabled or suppressed or humanoid.Health <= 0 or ExtrasService._baselineRoot ~= root then
            ExtrasService._baseline, ExtrasService._baselineRoot = root.CFrame, root
            if not enabled then restoreDefence() end
            return
        end
        ExtrasService._scanElapsed += dt
        if ExtrasService._scanElapsed >= CONFIG.PASSIVE_SCAN_INTERVAL then ExtrasService._scanElapsed = 0; scanPassive() end
        for _, record in pairs(ExtrasService._passive) do
            for part in pairs(record.Parts) do
                if part.Parent then record.Scope:SetProperty(part, "CanCollide", false) else record.Scope:RestoreObject(part); record.Parts[part] = nil end
            end
        end
        local velocity, angular = root.AssemblyLinearVelocity, root.AssemblyAngularVelocity
        local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
        local threshold = math.max(CONFIG.FLING_FALL_SPEED_CAP, config.Threshold, humanoid.WalkSpeed * 6, state:Get("Movement.SprintSpeed") * 6)
        local upwardLimit = math.max(CONFIG.FLING_UPWARD_CAP, humanoid.JumpPower * 5)
        local impossible = horizontal > threshold or velocity.Y > upwardLimit or angular.Magnitude > CONFIG.FLING_ANGULAR_CAP
        if impossible then
            guardChanges:SetProperty(root, "AssemblyLinearVelocity", Vector3.new(0, math.min(velocity.Y, 0), 0), true)
            guardChanges:SetProperty(root, "AssemblyAngularVelocity", Vector3.zero, true)
            if config.SnapBack and ExtrasService._baseline then guardChanges:SetProperty(root, "CFrame", ExtrasService._baseline, true) end
            if os.clock() - ExtrasService._lastNotice > CONFIG.FLING_NOTICE_COOLDOWN then
                ExtrasService._lastNotice = os.clock()
                bus:Publish("Notify", "Anti-fling", "Stopped an impossible impulse before physics integrated it")
            end
        else ExtrasService._baseline = root.CFrame end
        ExtrasService._baselineRoot = root
    end

    function ExtrasService:Initialize()
        if self._initialized then return end
        self._initialized = true
        local elapsed = 0
        local hitboxJob = scheduler:RegisterHeartbeat("Extras.HitboxSpin", 45, function(dt: number)
            local hitboxOn = state:Peek("Extras.Hitbox.Enabled")
            local spinOn = state:Peek("Extras.SpinBot.Enabled")
            if not hitboxOn and not spinOn then stopSpin(); return end
            elapsed += dt
            if hitboxOn and elapsed >= CONFIG.HITBOX_INTERVAL then elapsed = 0; updateHitboxes() elseif not hitboxOn then restoreHitboxes() end
            if not spinOn then stopSpin(); return end
            local assets = tracker:GetLocalAssets()
            local config = state:Peek("Extras.SpinBot")
            if not assets or assets.Humanoid.Health <= 0 then stopSpin(); return end
            local root = assets.RootPart
            if ExtrasService._spinRoot ~= root then
                stopSpin()
                ExtrasService._spinRoot, ExtrasService._spinScope = root, scope:CreateChild("Spin cycle")
            end
            local owner = ExtrasService._spinScope
            owner:SetProperty(assets.Humanoid, "AutoRotate", false)
            owner:SetProperty(root, "AssemblyAngularVelocity", Vector3.zero, true)
            owner:SetProperty(root, "CFrame", root.CFrame * CFrame.Angles(0, math.rad(math.clamp(config.Speed, -CONFIG.SPIN_SPEED_LIMIT, CONFIG.SPIN_SPEED_LIMIT)) * dt, 0), true)
        end)
        local function syncHitboxSpin()
            hitboxJob.Enabled = state:Peek("Extras.Hitbox.Enabled") == true or state:Peek("Extras.SpinBot.Enabled") == true
        end
        local antiJob = scheduler:RegisterPreSim("Extras.AntiFling", -100, antiFling)
        antiJob.Enabled = state:Peek("Extras.AntiFling.Enabled") == true
        scope:Add(state:Observe("Extras.Hitbox.Enabled", function(value: boolean) if not value then restoreHitboxes() end; syncHitboxSpin() end))
        scope:Add(state:Observe("Extras.AntiFling.Enabled", function(value: boolean)
            antiJob.Enabled = value == true
            if not value then restoreDefence() end
        end))
        scope:Add(state:Observe("Extras.SpinBot.Enabled", function(value: boolean) if not value then stopSpin() end; syncHitboxSpin() end))
        syncHitboxSpin()
        scope:Add(bus:Subscribe("PlayerLeft", function(player: Player) restoreHitbox(player); restorePassive(player) end))
        scope:Connect(Players.LocalPlayer.Idled, function()
            if not state:Get("Settings.AntiAfk") or not virtualUser then return end
            local sent = pcall(function()
                virtualUser:CaptureController()
                virtualUser:ClickButton2(Vector2.zero)
            end)
            if not sent then bus:Publish("Notify", "Anti-AFK", "This executor cannot send idle-prevention input"); state:Set("Settings.AntiAfk", false) end
        end)
    end

    function ExtrasService:Destroy() scope:Dispose() end

    scope:Add(function() restoreHitboxes(); restoreDefence(); stopSpin() end)
    return ExtrasService
end
