local Players = game:GetService("Players")

local CONFIG = table.freeze({
    FIRE_RATE_MIN = 0.001,
    FIRE_RATE_MAX = 0.5,
    FIRE_RATE_DEFAULT = 0.001,
    RANGE_MIN = 500,
    RANGE_MAX = 100000,
    RANGE_DEFAULT = 10000,
    OBSERVED_PATHS = {
        "Game.NoSpread", "Game.FastFire", "Game.ForceAuto", "Game.ForceRange",
        "Game.FastFireDelay", "Game.ForceRangeValue",
    },
})

return function(services: any, Prison: any?): any
    local StateStore = services:Get("StateStore")
    local Disposer = services:Get("Disposer")
    local EventBus = services:Get("EventBus")

    local Prison = Prison or {}
    local manifest = Prison.Manifest
    local scope = Disposer:CreateChild(`{manifest.Name}.WeaponMods`)
    local LocalPlayer = Players.LocalPlayer

    local ABSENT = {}

    local WeaponMods = {
        _tracked = {},
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

    local function collectAttrTargets(tool: Tool): { any }
        local targets = {}
        if hasGunAttributes(tool) then table.insert(targets, { Object = tool, Backup = {} }) end
        for _, descendant in ipairs(tool:GetDescendants()) do
            if hasGunAttributes(descendant) then table.insert(targets, { Object = descendant, Backup = {} }) end
        end
        return targets
    end

    function WeaponMods:ScanAllWeapons(): number
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

    function WeaponMods:RestoreAll(): number
        for _, record in pairs(self._tracked) do restoreRecord(record) end
        return self:GetScannedCount()
    end

    local function applyRecord(record: any)
        local noSpread = StateStore:Get("Game.NoSpread") == true
        local fastFire = StateStore:Get("Game.FastFire") == true
        local forceAuto = StateStore:Get("Game.ForceAuto") == true
        local forceRange = StateStore:Get("Game.ForceRange") == true

        local fireRate = math.clamp(tonumber(StateStore:Get("Game.FastFireDelay")) or CONFIG.FIRE_RATE_DEFAULT, CONFIG.FIRE_RATE_MIN, CONFIG.FIRE_RATE_MAX)
        local range = math.clamp(tonumber(StateStore:Get("Game.ForceRangeValue")) or CONFIG.RANGE_DEFAULT, CONFIG.RANGE_MIN, CONFIG.RANGE_MAX)

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

    function WeaponMods:Reapply()
        self:RestoreAll()
        self:ScanAllWeapons()
        for _, record in pairs(self._tracked) do applyRecord(record) end
        EventBus:Publish("PrisonWeaponsChanged", self:GetStats())
    end

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
            Backups = #names,
            AttrObjects = attrObjects,
            Names = names,
        }
    end

    function WeaponMods:Initialize()
        for _, path in ipairs(CONFIG.OBSERVED_PATHS) do
            scope:Add(StateStore:Observe(path, function() self:QueueReapply() end))
        end

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
