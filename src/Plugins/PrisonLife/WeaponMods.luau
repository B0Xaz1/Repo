--!nonstrict
-- Prison Life weapon mods. Prison Life guns have carried their stats in two forms across
-- updates: instance attributes (SpreadRadius / FireRate / AutoFire / Range) on the tool or
-- its children, and a GunStates ModuleScript table. Both mechanisms are honored, captured,
-- and restored. Disabling any setting restores the captured originals before the enabled
-- set is reapplied, so toggles are fully reversible at any moment.
return function(services: any, Prison: any?): any
    local StateStore = services:Get("StateStore")
    local Disposer = services:Get("Disposer")
    local EventBus = services:Get("EventBus")
    local Players = game:GetService("Players")

    local Prison = Prison or {}
    local manifest = Prison.Manifest
    local scope = Disposer:CreateChild("PrisonLife.WeaponMods")
    local LocalPlayer = Players.LocalPlayer

    local ABSENT = {} -- marker for module fields the table did not define before we touched it

    local WeaponMods = {
        _tracked = {},      -- [Tool] = { AttrTargets = {...}, Module = table?, ModuleBackup = {} }
        _reapplyQueued = false,
    }

    local function isKnownGunName(name: string): boolean
        for _, weapon in ipairs(manifest.Weapons) do
            if weapon.IsGun and table.find(weapon.ToolNames, name) then return true end
        end
        return false
    end

    local function hasGunAttributes(instance: Instance): boolean
        for _, attribute in ipairs(manifest.GunMods.Attributes) do
            if instance:GetAttribute(attribute) ~= nil then return true end
        end
        return false
    end

    local function moduleFor(tool: Tool): any?
        local moduleScript = tool:FindFirstChild(manifest.GunMods.ModuleName, true)
        if not moduleScript or not moduleScript:IsA("ModuleScript") then return nil end
        local ok, module = pcall(function() return require(moduleScript) end)
        if not ok or type(module) ~= "table" then return nil end
        return module
    end

    -- Public: the armory and the macro reuse this so "a gun" means the same thing everywhere.
    -- A tool counts if it is a known gun name, carries a GunStates module, or exposes gun
    -- attributes itself or on any descendant.
    function WeaponMods:IsGunTool(tool: Tool): boolean
        if not tool:IsA("Tool") then return false end
        if isKnownGunName(tool.Name) then return true end
        if tool:FindFirstChild(manifest.GunMods.ModuleName, true) then return true end
        if hasGunAttributes(tool) then return true end
        for _, descendant in ipairs(tool:GetDescendants()) do
            if hasGunAttributes(descendant) then return true end
        end
        return false
    end

    -- Legacy behavior: spread and fire rate can live on the tool itself or on child models
    -- inside it; every object that carries a gun attribute is its own backup target.
    local function collectAttrTargets(tool: Tool): { any }
        local targets = {}
        if hasGunAttributes(tool) then table.insert(targets, { Object = tool, Backup = {} }) end
        for _, descendant in ipairs(tool:GetDescendants()) do
            if hasGunAttributes(descendant) then table.insert(targets, { Object = descendant, Backup = {} }) end
        end
        return targets
    end

    function WeaponMods:ScanAllWeapons(): number
        -- Forget tools that left the inventory, then track every current gun.
        local present = {}
        local function visit(parent: Instance)
            if not parent then return end
            for _, child in ipairs(parent:GetChildren()) do
                if child:IsA("Tool") and self:IsGunTool(child) then
                    present[child] = true
                    if not self._tracked[child] then
                        self._tracked[child] = {
                            AttrTargets = collectAttrTargets(child),
                            Module = moduleFor(child),
                            ModuleBackup = {},
                        }
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

    -- Attributes are only written where they already exist (the legacy rule), and the
    -- original value is captured before the first write.
    local function applyAttr(target: any, attribute: string, value: any)
        local object = target.Object
        if object:GetAttribute(attribute) == nil then return end
        if target.Backup[attribute] == nil then target.Backup[attribute] = object:GetAttribute(attribute) end
        object:SetAttribute(attribute, value)
    end

    local function restoreRecord(record: any)
        for _, target in ipairs(record.AttrTargets) do
            for attribute, original in pairs(target.Backup) do
                target.Object:SetAttribute(attribute, original)
            end
            table.clear(target.Backup)
        end
        if record.Module then
            for field, original in pairs(record.ModuleBackup) do
                record.Module[field] = if original == ABSENT then nil else original
            end
            table.clear(record.ModuleBackup)
        end
    end

    -- Restores every tracked attribute target and GunStates module to its captured state.
    function WeaponMods:RestoreAll(): number
        for _, record in pairs(self._tracked) do restoreRecord(record) end
        return self:GetScannedCount()
    end

    local function applyRecord(record: any)
        local noSpread = StateStore:Get("Game.NoSpread") == true
        local fastFire = StateStore:Get("Game.FastFire") == true
        local forceAuto = StateStore:Get("Game.ForceAuto") == true
        local forceRange = StateStore:Get("Game.ForceRange") == true
        -- Legacy targets: fire rate 0.001 and range 10000; both stay tunable.
        local fireRate = math.clamp(tonumber(StateStore:Get("Game.FastFireDelay")) or 0.001, 0.001, 0.5)
        local range = math.clamp(tonumber(StateStore:Get("Game.ForceRangeValue")) or 10000, 500, 100000)

        for _, target in ipairs(record.AttrTargets) do
            if noSpread then applyAttr(target, "SpreadRadius", 0) end
            if fastFire then applyAttr(target, "FireRate", fireRate) end
            if forceAuto then applyAttr(target, "AutoFire", true) end
            if forceRange then applyAttr(target, "Range", range) end
        end

        local module = record.Module
        if module then
            local backup = record.ModuleBackup
            local function write(field: string, value: any)
                if backup[field] == nil then
                    backup[field] = if module[field] == nil then ABSENT else module[field]
                end
                module[field] = value
            end
            if noSpread then write("Spread", 0) end
            if fastFire then write("FireRate", fireRate) end
            if forceAuto then write("AutoFire", true) end
            if forceRange then write("Range", range) end
        end
    end

    -- The core reversibility rule: restore-first, then apply only the enabled settings.
    function WeaponMods:Reapply()
        self:RestoreAll()
        self:ScanAllWeapons()
        for _, record in pairs(self._tracked) do applyRecord(record) end
        EventBus:Publish("PrisonWeaponsChanged", self:GetStats())
    end

    -- Coalesced variant for observers: several flags may flip at once.
    -- task.defer keeps the reapply in the same resumption instead of a full frame later.
    function WeaponMods:QueueReapply()
        if self._reapplyQueued then return end
        self._reapplyQueued = true
        task.defer(function()
            WeaponMods._reapplyQueued = false
            if not scope:IsDisposed() then WeaponMods:Reapply() end
        end)
    end

    function WeaponMods:GetScannedCount(): number
        local count = 0
        for _ in pairs(self._tracked) do count += 1 end
        return count
    end

    function WeaponMods:GetStats(): any
        local names = {}
        local attrObjects = 0
        for tool, record in pairs(self._tracked) do
            table.insert(names, tool.Name)
            attrObjects += #record.AttrTargets
        end
        table.sort(names)
        return {
            Scanned = #names,
            Backups = #names, -- every tracked tool keeps attribute and/or module backups
            AttrObjects = attrObjects,
            Names = names,
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

        -- New guns picked up mid-session inherit the enabled settings immediately; the
        -- deferred reapply gives the game a moment to finish wiring the new tool.
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
