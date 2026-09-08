--!nonstrict
-- Prison Life weapon profiles: GunStates module tuning with immediate restore.
-- Disabling any setting restores the captured originals before the enabled set is reapplied,
-- so toggles are fully reversible at any moment (not only on plugin unload).
return function(services: any, Prison: any?): any
    local StateStore = services:Get("StateStore")
    local Disposer = services:Get("Disposer")
    local EventBus = services:Get("EventBus")
    local PlayerTracker = services:Get("PlayerTracker")
    local Players = game:GetService("Players")

    local Prison = Prison or {}
    local manifest = Prison.Manifest
    local scope = Disposer:CreateChild("PrisonLife.WeaponMods")
    local LocalPlayer = Players.LocalPlayer

    local ABSENT = {} -- marker for fields the module did not define before we touched it

    local WeaponMods = {
        _tracked = {},  -- [Tool] = { Module = table, Backup = { [field] = value or ABSENT } }
        _reapplyQueued = false,
    }

    local function moduleFor(tool: Tool): any?
        local stateModule = tool:FindFirstChild(manifest.GunStates.ModuleName)
        if not stateModule or not stateModule:IsA("ModuleScript") then return nil end
        local ok, module = pcall(function() return require(stateModule) end)
        if not ok or type(module) ~= "table" then return nil end
        return module
    end

    function WeaponMods:ScanAllWeapons(): number
        -- Forget tools that left the inventory, then track every current gun.
        local present = {}
        local function visit(parent: Instance)
            if not parent then return end
            for _, child in ipairs(parent:GetChildren()) do
                if child:IsA("Tool") and child:FindFirstChild(manifest.GunStates.ModuleName) then
                    present[child] = true
                    if not self._tracked[child] then
                        local module = moduleFor(child)
                        if module then
                            self._tracked[child] = { Module = module, Backup = {} }
                        end
                    end
                end
            end
        end
        visit(LocalPlayer and LocalPlayer.Character)
        visit(LocalPlayer and LocalPlayer:FindFirstChildOfClass("Backpack"))
        for tool in pairs(self._tracked) do
            if not present[tool] or not tool.Parent then
                self._tracked[tool] = nil
            end
        end
        return self:GetScannedCount()
    end

    -- Values are captured before the first modification; ABSENT marks fields we introduced.
    local function capture(record: any, field: string)
        if record.Backup[field] ~= nil then return end
        if record.Module[field] == nil then
            record.Backup[field] = ABSENT
        else
            record.Backup[field] = record.Module[field]
        end
    end

    local function restoreRecord(record: any)
        for field, original in pairs(record.Backup) do
            if original == ABSENT then
                record.Module[field] = nil
            else
                record.Module[field] = original
            end
        end
        table.clear(record.Backup)
    end

    function WeaponMods:RestoreAll(): number
        for _, record in pairs(self._tracked) do restoreRecord(record) end
        return self:GetScannedCount()
    end

    local function applyRecord(record: any)
        -- No spread
        if StateStore:Get("Game.NoSpread") == true then
            capture(record, "Spread")
            record.Module.Spread = 0
        end
        -- Fast fire rate
        if StateStore:Get("Game.FastFire") == true then
            capture(record, "FireRate")
            local original = if record.Backup.FireRate == ABSENT or record.Backup.FireRate == nil
                then 0.12 else record.Backup.FireRate
            local target = tonumber(StateStore:Get("Game.FastFireDelay")) or 0.05
            record.Module.FireRate = math.clamp(math.min(original, target), 0.001, 2)
        end
        -- Force full-auto
        if StateStore:Get("Game.ForceAuto") == true then
            capture(record, "AutoFire")
            record.Module.AutoFire = true
        end
        -- Force range
        if StateStore:Get("Game.ForceRange") == true then
            capture(record, "Range")
            record.Module.Range = math.clamp(tonumber(StateStore:Get("Game.ForceRangeValue")) or 2500, 100, 100000)
        end
    end

    -- The spec's core fix: restore-first, then apply only the currently enabled settings.
    function WeaponMods:Reapply()
        self:RestoreAll()
        self:ScanAllWeapons()
        for _, record in pairs(self._tracked) do applyRecord(record) end
        EventBus:Publish("PrisonWeaponsChanged", self:GetStats())
    end

    -- Coalesced variant for observers: several flags may flip during a profile change.
    -- task.defer keeps the reapply in the same resumption instead of a full frame later.
    function WeaponMods:QueueReapply()
        if self._reapplyQueued then return end
        self._reapplyQueued = true
        task.defer(function()
            WeaponMods._reapplyQueued = false
            if not scope:IsDisposed() then WeaponMods:Reapply() end
        end)
    end

    function WeaponMods:ApplyProfile(name: string): (boolean, string)
        local profile = manifest.WeaponProfiles[name]
        if not profile then
            if name == "Custom" then return true, "Custom profile keeps your current switches" end
            return false, "Unknown profile " .. tostring(name)
        end
        StateStore:Set("Game.NoSpread", profile.NoSpread == true)
        StateStore:Set("Game.FastFire", profile.FastFire == true)
        StateStore:Set("Game.ForceAuto", profile.ForceAuto == true)
        StateStore:Set("Game.ForceRange", profile.ForceRange == true)
        return true, "Weapon profile: " .. name
    end

    function WeaponMods:GetScannedCount(): number
        local count = 0
        for _ in pairs(self._tracked) do count += 1 end
        return count
    end

    function WeaponMods:GetStats(): any
        local names = {}
        for tool in pairs(self._tracked) do table.insert(names, tool.Name) end
        table.sort(names)
        return {
            Scanned = self:GetScannedCount(),
            Backups = self:GetScannedCount(), -- every tracked module keeps a backup
            Names = names,
            Profile = StateStore:Get("Game.WeaponProfile"),
        }
    end

    function WeaponMods:Initialize()
        local paths = {
            "Game.NoSpread", "Game.FastFire", "Game.ForceAuto", "Game.ForceRange",
            "Game.FastFireDelay", "Game.ForceRangeValue",
        }
        for _, path in ipairs(paths) do
            scope:Add(StateStore:Observe(path, function() self:QueueReapply() end))
        end
        scope:Add(StateStore:Observe("Game.WeaponProfile", function(name: any)
            if name ~= "Custom" then self:ApplyProfile(name) end
        end))

        -- New guns picked up mid-session inherit the enabled settings immediately.
        local function watch(parent: Instance)
            if not parent then return end
            scope:Connect(parent.ChildAdded, function() self:QueueReapply() end)
            scope:Connect(parent.ChildRemoved, function() self:QueueReapply() end)
        end
        if LocalPlayer then
            local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
            if backpack then watch(backpack) end
            scope:Connect(LocalPlayer.ChildAdded, function(child: Instance)
                if child:IsA("Backpack") then watch(child) end
            end)
            if LocalPlayer.Character then watch(LocalPlayer.Character) end
            scope:Connect(LocalPlayer.CharacterAdded, function(character: Model) watch(character) end)
        end
        self:Reapply()
    end

    function WeaponMods:Destroy()
        self:RestoreAll()
        scope:Dispose()
        table.clear(self._tracked)
    end

    return WeaponMods
end
