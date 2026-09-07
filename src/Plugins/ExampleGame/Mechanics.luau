--!nonstrict
return function(services: any): any
    local load, state = services:Get("Require"), services:Get("StateStore")
    local manifest = load("src/Plugins/ExampleGame/Manifest.luau", services)
    local scope = services:Get("Disposer"):CreateChild("Plugin ExampleGame")
    local collection, players = game:GetService("CollectionService"), game:GetService("Players")
    local Plugin = { Name = manifest.Name, _doors = {}, _weapons = {}, _initialized = false }
    local function applyDoor(part: BasePart, owner: any)
        if scope:IsDisposed() then return end
        if state:Get("Game.Example.DoorsOpen") then
            owner:SetProperty(part, "CanCollide", false)
            owner:SetProperty(part, "Transparency", manifest.Doors.OpenTransparency)
        else owner:RestoreProperties() end
    end
    local function watchDoor(object: Instance)
        if not object:IsA("BasePart") or Plugin._doors[object] then return end
        local owner = scope:CreateChild("Door " .. object.Name)
        Plugin._doors[object] = owner
        for _, property in ipairs({ "CanCollide", "Transparency" }) do owner:Connect(object:GetPropertyChangedSignal(property), function() applyDoor(object, owner) end) end
        applyDoor(object, owner)
    end
    local function applyWeapon(tool: Tool, owner: any)
        if scope:IsDisposed() then return end
        if state:Get("Game.Example.WeaponTuning") then
            for attribute, value in pairs(manifest.Weapons.Attributes) do owner:SetAttribute(tool, attribute, value) end
        else owner:RestoreProperties() end
    end
    local function watchWeapon(object: Instance)
        if not object:IsA("Tool") or not table.find(manifest.Weapons.Names, object.Name) then return end
        if Plugin._weapons[object] then applyWeapon(object, Plugin._weapons[object]); return end
        local owner = scope:CreateChild("Weapon " .. object.Name)
        Plugin._weapons[object] = owner
        for attribute in pairs(manifest.Weapons.Attributes) do owner:Connect(object:GetAttributeChangedSignal(attribute), function() applyWeapon(object, owner) end) end
        owner:Connect(object.Destroying, function() Plugin._weapons[object] = nil; owner:Dispose() end)
        applyWeapon(object, owner)
    end
    local function watchInventory(parent: Instance, slot: string)
        local owner = scope:CreateChild(slot)
        scope:Bind(slot, owner)
        owner:Connect(parent.ChildAdded, watchWeapon)
        for _, child in ipairs(parent:GetChildren()) do watchWeapon(child) end
    end
    function Plugin:Initialize(_container: any)
        if self._initialized then return end
        self._initialized = true
        for _, path in ipairs({ "Game.Example.DoorsOpen", "Game.Example.WeaponTuning" }) do if state:Get(path) == nil then state:Set(path, false) end end
        for _, object in ipairs(collection:GetTagged(manifest.Doors.Tag)) do watchDoor(object) end
        scope:Connect(collection:GetInstanceAddedSignal(manifest.Doors.Tag), watchDoor)
        scope:Connect(collection:GetInstanceRemovedSignal(manifest.Doors.Tag), function(object: Instance)
            local owner = Plugin._doors[object]; Plugin._doors[object] = nil; if owner then owner:Dispose() end
        end)
        scope:Add(state:Observe("Game.Example.DoorsOpen", function() for door, owner in pairs(Plugin._doors) do applyDoor(door, owner) end end))
        scope:Add(state:Observe("Game.Example.WeaponTuning", function() for tool, owner in pairs(Plugin._weapons) do applyWeapon(tool, owner) end end))
        local localPlayer = players.LocalPlayer
        local backpack = localPlayer:FindFirstChildOfClass("Backpack")
        if backpack then watchInventory(backpack, "Backpack") end
        scope:Connect(localPlayer.ChildAdded, function(child: Instance) if child:IsA("Backpack") then watchInventory(child, "Backpack") end end)
        scope:Add(services:Get("PlayerTracker"):OnLocalCharacterRespawn(function(assets: any) watchInventory(assets.Character, "Character") end))
        if localPlayer.Character then watchInventory(localPlayer.Character, "Character") end
    end
    function Plugin:BuildUI(tab: any)
        local section = load("src/UI/Components/Section.luau", services)
        local toggle = load("src/UI/Components/Toggle.luau", services)
        local textbox = load("src/UI/Components/Textbox.luau", services)
        local controls = section:Create(tab.LeftCol, "Example mechanics")
        section:Info(controls, "Opt-in test-place adapter. Only tagged doors and explicitly named tools are touched. Server-owned behavior may reject client changes.")
        toggle(controls, "Phase tagged doors", "Game.Example.DoorsOpen", nil)
        toggle(controls, "Tune example weapon", "Game.Example.WeaponTuning", nil)
        local travel = section:Create(tab.RightCol, "Manifest destinations")
        textbox:CreateButton(travel, "Go to test lobby", function()
            local ok, message = services:Get("LocomotionService"):Teleport(manifest.Coordinates.Lobby)
            services:Get("EventBus"):Publish("Notify", if ok then "Plugin" else "Unavailable", message)
        end)
    end
    function Plugin:Destroy() scope:Dispose(); table.clear(self._doors); table.clear(self._weapons) end
    return Plugin
end
