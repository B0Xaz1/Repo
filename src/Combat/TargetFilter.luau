--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CONFIG = table.freeze({
    FALLBACK_TEAM_COLOR = Color3.fromRGB(80, 140, 220),
    DEFAULT_MAX_DISTANCE = 2000,
})

return function(services: any): any
    local state, tracker = services:Get("StateStore"), services:Get("PlayerTracker")
    local scope = services:Get("Disposer"):CreateChild("TargetFilter")
    local params = RaycastParams.new()
    params.FilterType, params.IgnoreWater = Enum.RaycastFilterType.Exclude, true
    local TargetFilter = { _friends = {}, _pending = {} }

    function TargetFilter:IsTeammate(player: Player): boolean
        local localPlayer = Players.LocalPlayer
        if localPlayer.Team and player.Team then return localPlayer.Team == player.Team end
        if localPlayer.Neutral or player.Neutral then return false end
        return localPlayer.TeamColor == player.TeamColor
    end

    function TargetFilter:GetTeamColor(player: Player): Color3
        local ok, color = pcall(function()
            if player.Team then return player.Team.TeamColor.Color end
            return player.TeamColor.Color
        end)
        return if ok and typeof(color) == "Color3" then color else CONFIG.FALLBACK_TEAM_COLOR
    end

    function TargetFilter:IsFriend(player: Player): boolean
        local id = player.UserId
        if self._friends[id] ~= nil then return self._friends[id] end
        if not self._pending[id] then
            self._pending[id] = true
            scope:Spawn(function()
                local ok, friend = pcall(function() return Players.LocalPlayer:IsFriendsWith(id) end)
                if not scope:IsDisposed() then TargetFilter._friends[id] = ok and friend == true; TargetFilter._pending[id] = nil end
            end)
        end
        return self._friends[id] ~= false
    end

    function TargetFilter:IsWhitelisted(player: Player): boolean
        local whitelist = state:Get("Settings.Whitelist")
        if whitelist[tostring(player.UserId)] == true or whitelist[player.UserId] == true then return true end
        for _, name in ipairs(whitelist) do
            if tostring(name):lower() == player.Name:lower() or tostring(name) == tostring(player.UserId) then return true end
        end
        return false
    end

    function TargetFilter:HasForceField(player: Player): boolean
        return player.Character ~= nil and player.Character:FindFirstChildWhichIsA("ForceField", true) ~= nil
    end

    function TargetFilter:Raycast(origin: Vector3, direction: Vector3): RaycastResult?
        local exclude = {}
        if Players.LocalPlayer.Character then table.insert(exclude, Players.LocalPlayer.Character) end
        if Workspace.CurrentCamera then table.insert(exclude, Workspace.CurrentCamera) end
        params.FilterDescendantsInstances = exclude
        return Workspace:Raycast(origin, direction, params)
    end

    function TargetFilter:IsVisible(part: BasePart): boolean
        local camera = Workspace.CurrentCamera
        if not camera or not part.Parent then return false end
        local hit = self:Raycast(camera.CFrame.Position, part.Position - camera.CFrame.Position)
        if not hit then return true end
        local player = self:GetPlayerFromPart(part)
        return player ~= nil and player.Character ~= nil and hit.Instance:IsDescendantOf(player.Character)
    end

    function TargetFilter:GetPlayerFromPart(part: Instance): Player?
        local current: Instance? = part
        while current and current ~= Workspace do
            if current:IsA("Model") then
                local player = Players:GetPlayerFromCharacter(current)
                if player then return player end
            end
            current = current.Parent
        end
        return nil
    end

    function TargetFilter:ValidateTarget(player: Player, part: BasePart?, configScope: any): boolean
        if not player or player == Players.LocalPlayer or not part or not part.Parent then return false end
        local assets = tracker:GetPlayerAssets(player)
        if not assets or assets.Humanoid.Health <= 0 or not part:IsDescendantOf(assets.Character) then return false end
        local config = if type(configScope) == "string" then state:Get(configScope) else configScope
        if type(config) ~= "table" then return false end
        if config.TeamCheck and self:IsTeammate(player) then return false end
        if config.FriendCheck and self:IsFriend(player) then return false end
        if config.WhitelistCheck and self:IsWhitelisted(player) then return false end
        if config.ForceFieldCheck and self:HasForceField(player) then return false end
        local camera = Workspace.CurrentCamera
        if not camera then return false end
        if (part.Position - camera.CFrame.Position).Magnitude > math.max(0, config.MaxDistance or CONFIG.DEFAULT_MAX_DISTANCE) then return false end
        if config.VisCheck and not self:IsVisible(part) then return false end
        local extension = state:GetTransient("TargetFilterExtension")
        if type(extension) == "function" then
            local ok, allowed = pcall(extension, player)
            if ok and allowed == false then return false end
        end
        return true
    end

    function TargetFilter:Initialize() end

    function TargetFilter:Destroy() scope:Dispose(); table.clear(self._friends); table.clear(self._pending) end

    return TargetFilter
end
