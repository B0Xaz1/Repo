--!nonstrict
export type Assets = { Player: Player, Character: Model, Humanoid: Humanoid, RootPart: BasePart, Head: BasePart }

return function(services: any): any
    local players, workspace = game:GetService("Players"), game:GetService("Workspace")
    local bus = services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("PlayerTracker")
    local spectateScope = scope:CreateChild("Spectate")
    local PlayerTracker = { _registry = {}, _players = {}, _versions = {}, _spectating = nil, _cameraOriginals = {}, _initialized = false }

    local function resolve(player: Player, waitForParts: boolean): any?
        local character = player.Character
        if not character or not character.Parent then return nil end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local root = character:FindFirstChild("HumanoidRootPart")
        if waitForParts then
            humanoid = humanoid or character:WaitForChild("Humanoid", 6)
            root = root or character:WaitForChild("HumanoidRootPart", 6)
        end
        if scope:IsDisposed() or player.Character ~= character or not character.Parent then return nil end
        if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then return nil end
        local head = character:FindFirstChild("Head")
        return { Player = player, Character = character, Humanoid = humanoid, RootPart = root,
            Head = if head and head:IsA("BasePart") then head else root }
    end
    local function applySpectate()
        local target = PlayerTracker._spectating
        local camera = workspace.CurrentCamera
        local assets = target and PlayerTracker:GetPlayerAssets(target)
        if camera and assets then
            if PlayerTracker._cameraOriginals[camera] == nil then
                local _, subject = spectateScope:GetOriginal(camera, "CameraSubject")
                PlayerTracker._cameraOriginals[camera] = { Value = subject }
            end
            spectateScope:SetProperty(camera, "CameraSubject", assets.Humanoid)
        end
    end
    local function indexCharacter(player: Player, character: Model)
        PlayerTracker._versions[player] = (PlayerTracker._versions[player] or 0) + 1
        local version = PlayerTracker._versions[player]
        PlayerTracker._registry[player] = nil
        local assets = resolve(player, true)
        if assets and version == PlayerTracker._versions[player] and player.Character == character and PlayerTracker._players[player] then
            PlayerTracker._registry[player] = assets
            if player == players.LocalPlayer then bus:Publish("LocalCharacterRespawn", assets) end
            if player == PlayerTracker._spectating then applySpectate() end
        end
    end
    local function attach(player: Player)
        if PlayerTracker._players[player] or scope:IsDisposed() then return end
        local playerScope = scope:CreateChild("Player " .. player.UserId)
        PlayerTracker._players[player] = playerScope
        playerScope:Connect(player.CharacterAdded, function(character: Model) indexCharacter(player, character) end)
        playerScope:Connect(player.CharacterRemoving, function(character: Model)
            local assets = PlayerTracker._registry[player]
            if assets and assets.Character == character then PlayerTracker._registry[player] = nil end
            PlayerTracker._versions[player] = (PlayerTracker._versions[player] or 0) + 1
        end)
        if player.Character then playerScope:Spawn(function() indexCharacter(player, player.Character) end) end
        bus:Publish("PlayerJoined", player)
    end
    function PlayerTracker:GetPlayerAssets(player: Player): Assets?
        local assets = self._registry[player]
        if assets and assets.Character == player.Character and assets.Humanoid.Parent and assets.RootPart.Parent
            and assets.RootPart:IsDescendantOf(assets.Character) then return assets end
        -- Frame callers may re-resolve, but never yield waiting for a half-streamed rig.
        assets = resolve(player, false)
        self._registry[player] = assets
        return assets
    end
    function PlayerTracker:GetLocalAssets(): Assets? return self:GetPlayerAssets(players.LocalPlayer) end
    function PlayerTracker:IsAlive(player: Player): boolean
        local assets = self:GetPlayerAssets(player)
        return assets ~= nil and assets.Humanoid.Health > 0
    end
    function PlayerTracker:GetPlayerByName(query: string): Player?
        query = tostring(query):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if query == "" then return nil end
        local current = players:GetPlayers()
        for _, player in ipairs(current) do if player.Name:lower() == query or player.DisplayName:lower() == query then return player end end
        for _, player in ipairs(current) do
            if player.Name:lower():find(query, 1, true) or player.DisplayName:lower():find(query, 1, true) then return player end
        end
        return nil
    end
    function PlayerTracker:GetPlayerNames(excludeLocal: boolean?, query: string?): { string }
        local names = {}
        local filter = tostring(query or ""):lower()
        for _, player in ipairs(players:GetPlayers()) do
            if (not excludeLocal or player ~= players.LocalPlayer) and (filter == "" or player.Name:lower():find(filter, 1, true) or player.DisplayName:lower():find(filter, 1, true)) then
                table.insert(names, player.Name)
            end
        end
        table.sort(names, function(a: string, b: string) return a:lower() < b:lower() end)
        return names
    end
    function PlayerTracker:OnLocalCharacterRespawn(callback: (Assets) -> ()): any return bus:Subscribe("LocalCharacterRespawn", callback) end
    function PlayerTracker:StartSpectate(player: Player): (boolean, string)
        if not player or not player.Parent then return false, "Select a player who is still in the server" end
        self._spectating = player
        applySpectate()
        return true, "Spectating " .. player.Name
    end
    function PlayerTracker:StopSpectate()
        self._spectating = nil
        spectateScope:RestoreProperties()
        if next(self._cameraOriginals) == nil then return end
        local localAssets = self:GetLocalAssets()
        for camera, original in pairs(self._cameraOriginals) do
            -- A destroyed original subject is the one documented restoration exception: use the local humanoid.
            if not original.Value or not original.Value.Parent then
                if localAssets then pcall(function() camera.CameraSubject = localAssets.Humanoid end) end
            end
        end
        table.clear(self._cameraOriginals)
    end
    function PlayerTracker:AddWhitelist(player: Player): (boolean, string)
        if not player then return false, "Select a player" end
        local state = services:Get("StateStore")
        local names = state:Get("Settings.Whitelist")
        if not table.find(names, player.Name) then table.insert(names, player.Name) end
        local ok, message = state:Set("Settings.Whitelist", names)
        return ok, message or ("Whitelisted " .. player.Name)
    end
    function PlayerTracker:RemoveWhitelist(player: Player): (boolean, string)
        if not player then return false, "Select a player" end
        local state = services:Get("StateStore")
        local names = state:Get("Settings.Whitelist")
        for index = #names, 1, -1 do if tostring(names[index]):lower() == player.Name:lower() or tostring(names[index]) == tostring(player.UserId) then table.remove(names, index) end end
        names[tostring(player.UserId)] = nil
        local ok, message = state:Set("Settings.Whitelist", names)
        return ok, message or ("Removed " .. player.Name .. " from the whitelist")
    end
    function PlayerTracker:GetWhitelistSummary(): string
        local names = services:Get("StateStore"):Get("Settings.Whitelist")
        local display = {}
        for key, value in pairs(names) do table.insert(display, if value == true then tostring(key) else tostring(value)) end
        table.sort(display)
        return if #display > 0 then table.concat(display, ", ") else "No whitelisted players"
    end
    function PlayerTracker:CopyName(player: Player): (boolean, string)
        if not player then return false, "Select a player" end
        local ok, message = services:Get("Environment"):SetClipboard(player.Name)
        return ok, message or ("Copied " .. player.Name)
    end
    function PlayerTracker:Initialize()
        if self._initialized then return end
        self._initialized = true
        scope:Connect(players.PlayerAdded, attach)
        scope:Connect(players.PlayerRemoving, function(player: Player)
            if self._spectating == player then self:StopSpectate() end
            local playerScope = self._players[player]
            self._players[player], self._registry[player], self._versions[player] = nil, nil, nil
            if playerScope then playerScope:Dispose() end
            bus:Publish("PlayerLeft", player)
        end)
        scope:Connect(workspace:GetPropertyChangedSignal("CurrentCamera"), applySpectate)
        for _, player in ipairs(players:GetPlayers()) do attach(player) end
    end
    function PlayerTracker:Destroy() self:StopSpectate(); scope:Dispose() end
    scope:Add(function() PlayerTracker:StopSpectate(); table.clear(PlayerTracker._registry); table.clear(PlayerTracker._players) end)
    return PlayerTracker
end
