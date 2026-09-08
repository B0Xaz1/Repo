--!nonstrict
-- Prison Life armory: weapon inventory across backpack/character, manifest spawn awareness,
-- and the game's own ItemHandler pickup flow.
return function(services: any, Prison: any?): any
    local EventBus, Disposer = services:Get("EventBus"), services:Get("Disposer")
    local PlayerTracker = services:Get("PlayerTracker")
    local LocomotionService = services:Get("LocomotionService")
    local Players = game:GetService("Players")
    local workspace = game:GetService("Workspace")

    local Prison = Prison or {}
    local manifest = Prison.Manifest
    local scope = Disposer:CreateChild("PrisonLife.Armory")
    local LocalPlayer = Players.LocalPlayer

    local ArmoryService = {
        _inventory = {},       -- ordered entries: { Weapon, Status, Tool }
        _lastScan = 0,
    }

    local function weaponForTool(tool: Tool): any?
        for _, weapon in ipairs(manifest.Weapons) do
            if table.find(weapon.ToolNames, tool.Name) then return weapon end
        end
        return nil
    end

    -- Unknown-but-real guns (future map updates) are detected through the shared check.
    local function isGunTool(tool: Tool): boolean
        return Prison.WeaponMods ~= nil and Prison.WeaponMods:IsGunTool(tool) == true
    end

    -- Known manifest weapons first (stable order), then any unknown gun tool.
    function ArmoryService:Scan(): { any }
        local backpack = LocalPlayer and LocalPlayer:FindFirstChildOfClass("Backpack")
        local character = LocalPlayer and LocalPlayer.Character
        local found = {}      -- [weaponId] = { Status, Tool }
        local extras = {}     -- unknown gun tools

        local function visit(parent: Instance, equipped: boolean)
            if not parent then return end
            for _, child in ipairs(parent:GetChildren()) do
                if child:IsA("Tool") then
                    local weapon = weaponForTool(child)
                    if weapon then
                        found[weapon.Id] = { Status = if equipped then "Equipped" else "Owned", Tool = child }
                    elseif isGunTool(child) then
                        table.insert(extras, { Weapon = { Id = child.Name, Name = child.Name, Category = "Detected" }, Status = if equipped then "Equipped" else "Owned", Tool = child })
                    end
                end
            end
        end
        visit(character, true)
        visit(backpack, false)

        local inventory = {}
        for _, weapon in ipairs(manifest.Weapons) do
            local entry = found[weapon.Id]
            if entry then
                table.insert(inventory, { Weapon = weapon, Status = entry.Status, Tool = entry.Tool })
            else
                local status = "Unavailable"
                if weapon.Spawn then status = "Spawn available"
                elseif weapon.Pickup then status = "Pickup available" end
                table.insert(inventory, { Weapon = weapon, Status = status, Tool = nil })
            end
        end
        for _, extra in ipairs(extras) do table.insert(inventory, extra) end

        self._inventory = inventory
        self._lastScan = os.clock()
        EventBus:Publish("PrisonInventoryChanged", inventory)
        return inventory
    end

    function ArmoryService:GetInventory(): { any }
        if os.clock() - self._lastScan > 0.5 then return self:Scan() end
        return self._inventory
    end

    function ArmoryService:GetWeaponByName(name: string): any?
        local lowered = tostring(name or ""):lower()
        for _, weapon in ipairs(manifest.Weapons) do
            if weapon.Name:lower() == lowered or weapon.Id:lower() == lowered then return weapon end
        end
        for _, entry in ipairs(self:GetInventory()) do
            if entry.Weapon.Name:lower() == lowered then return entry.Weapon end
        end
        return nil
    end

    function ArmoryService:Equip(name: string): (boolean, string)
        local assets = PlayerTracker:GetLocalAssets()
        if not assets then return false, "Your character is not ready" end
        local weapon = self:GetWeaponByName(name)
        if not weapon then return false, "Unknown weapon" end
        for _, entry in ipairs(self:GetInventory()) do
            if entry.Weapon.Id == weapon.Id and entry.Tool then
                local ok, err = pcall(function() assets.Humanoid:EquipTool(entry.Tool) end)
                return ok, if ok then ("Equipped " .. weapon.Name) else tostring(err)
            end
        end
        return false, weapon.Name .. " is not in your backpack"
    end

    function ArmoryService:GoToWeapon(name: string): (boolean, string)
        local weapon = self:GetWeaponByName(name)
        if not weapon then return false, "Unknown weapon" end
        if not weapon.Spawn then return false, weapon.Name .. " has no known spawn point" end
        local ok, message = LocomotionService:Teleport(CFrame.new(weapon.Spawn))
        return ok, if ok then ("Teleported to " .. weapon.Name .. " spawn") else message
    end

    -- Uses the game's own pickup flow (the same remote the map's ITEMPICKUP parts use).
    function ArmoryService:Pickup(name: string): (boolean, string)
        local weapon = self:GetWeaponByName(name)
        if not weapon then return false, "Unknown weapon" end
        if not weapon.Pickup then return false, weapon.Name .. " has no pickup point" end
        local remote = workspace:FindFirstChild(manifest.Items.RemoteFolder)
        remote = remote and remote:FindFirstChild(manifest.Items.RemoteName)
        local root = workspace:FindFirstChild(manifest.Items.GiverRoot)
        if not remote or not root then
            return false, "Pickup remote is not present on this map"
        end
        for _, folderName in ipairs(manifest.Items.GiverFolders) do
            local folder = root:FindFirstChild(folderName)
            local giver = folder and folder:FindFirstChild(weapon.Pickup)
            local pickup = giver and giver:FindFirstChild(manifest.Items.PickupChild)
            if pickup then
                local ok, err = pcall(function() (remote :: any):InvokeServer(pickup) end)
                if ok then
                    task.delay(0.2, function() if not scope:IsDisposed() then ArmoryService:Scan() end end)
                    return true, "Requested " .. weapon.Name
                end
                return false, "Pickup rejected: " .. tostring(err)
            end
        end
        return false, "No pickup point found for " .. weapon.Name
    end

    function ArmoryService:Initialize()
        self:Scan()
        local function watch(parent: Instance)
            if not parent then return end
            scope:Connect(parent.ChildAdded, function() self:Scan() end)
            scope:Connect(parent.ChildRemoved, function() self:Scan() end)
        end
        if LocalPlayer then
            local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
            if backpack then watch(backpack) end
            scope:Connect(LocalPlayer.ChildAdded, function(child: Instance)
                if child:IsA("Backpack") then watch(child) end
            end)
            scope:Add(PlayerTracker:OnLocalCharacterRespawn(function() self:Scan() end))
            if LocalPlayer.Character then watch(LocalPlayer.Character) end
            scope:Connect(LocalPlayer.CharacterAdded, function(character: Model) watch(character) end)
        end
    end

    function ArmoryService:Destroy() scope:Dispose(); table.clear(self._inventory) end

    return ArmoryService
end
