--!nonstrict
-- Prison Life context: role, team, alive state, equipped tool, and role-aware target rules.
-- Keeps every role decision out of Mechanics and the UI.
return function(services: any, Prison: any?): any
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local Disposer = services:Get("Disposer")
    local PlayerTracker = services:Get("PlayerTracker")
    local Players = game:GetService("Players")

    local LocalPlayer = Players.LocalPlayer
    local Prison = Prison or {}
    local manifest = Prison.Manifest
    local scope = Disposer:CreateChild("PrisonLife.Context")

    local ROLE_BY_TEAM = manifest.Roles.ByTeam
    local ROLE_ORDER = manifest.Roles.Order

    local Context = {
        Role = "Unknown",
        TeamName = "Unknown",
        IsAlive = false,
        Health = 0,
        MaxHealth = 0,
        EquippedTool = "None",
        CharacterStatus = "Loading",
        SessionStart = os.clock(),
        _lastSignature = "",
    }

    local function normalize(value: any): string
        return tostring(value or ""):lower():gsub("%s+", "")
    end

    local function roleFromTeam(teamName: any): string
        return ROLE_BY_TEAM[normalize(teamName)] or "Unknown"
    end

    function Context:GetRoleColor(role: string): Color3
        return manifest.Roles.Colors[role] or manifest.Roles.Colors.Unknown
    end

    -- Auto detection reads the team; a manual override wins until it is cleared.
    function Context:GetLocalRole(): string
        local mode = StateStore:Get("Game.RoleMode")
        if mode == "Prisoner" or mode == "Guard" or mode == "Criminal" then return mode end
        return self.Role
    end

    function Context:GetPlayerRole(player: Player): string
        if player == LocalPlayer then return self:GetLocalRole() end
        local team = player.Team
        if not team then return "Unknown" end
        return roleFromTeam(team.Name)
    end

    function Context:IsRoleIgnored(role: string): boolean
        if StateStore:Get("Game.IgnoreSameRole") and role == self:GetLocalRole() then return true end
        if StateStore:Get("Game.IgnoreGuards") and role == "Guard" then return true end
        if StateStore:Get("Game.IgnorePrisoners") and role == "Prisoner" then return true end
        if StateStore:Get("Game.IgnoreCriminals") and role == "Criminal" then return true end
        return false
    end

    -- The single role gate reused by melee, the player watch, and the universal aim/trigger filters.
    function Context:ValidateTargetRole(player: Player): boolean
        if not StateStore:Get("Game.RoleAware") then return true end
        if player == LocalPlayer then return false end
        local role = self:GetPlayerRole(player)
        if self:IsRoleIgnored(role) then return false end
        local selected = StateStore:Get("Game.TargetRole") or "Any"
        if selected == "Any" then return true end
        return role == selected
    end

    function Context:GetSessionDuration(): number
        return os.clock() - self.SessionStart
    end

    function Context:GetSnapshot(): any
        local nearest = nil
        if Prison.Locations then nearest = Prison.Locations:GetNearestSummary() end
        return {
            Role = self:GetLocalRole(),
            AutoRole = self.Role,
            TeamName = self.TeamName,
            TeamColor = LocalPlayer and LocalPlayer.TeamColor or nil,
            IsAlive = self.IsAlive,
            Health = self.Health,
            MaxHealth = self.MaxHealth,
            EquippedTool = self.EquippedTool,
            CharacterStatus = self.CharacterStatus,
            NearestLocation = nearest,
            SessionDuration = self:GetSessionDuration(),
        }
    end

    function Context:Refresh()
        local assets = PlayerTracker:GetLocalAssets()
        local team = LocalPlayer and LocalPlayer.Team
        local teamName = team and team.Name or "Unknown"

        self.TeamName = teamName
        self.Role = roleFromTeam(teamName)
        self.IsAlive = assets ~= nil and assets.Humanoid.Health > 0
        self.Health = assets and math.max(0, math.floor(assets.Humanoid.Health)) or 0
        self.MaxHealth = assets and math.max(1, math.floor(assets.Humanoid.MaxHealth)) or 0
        self.EquippedTool = "None"
        self.CharacterStatus = "Loading"
        if assets then
            self.CharacterStatus = if self.IsAlive then "Ready" else "Dead"
            local character = LocalPlayer and LocalPlayer.Character
            if character then
                for _, child in ipairs(character:GetChildren()) do
                    if child:IsA("Tool") then
                        self.EquippedTool = child.Name
                        break
                    end
                end
            end
        end

        StateStore:SetTransient("PrisonRole", self:GetLocalRole())
        StateStore:SetTransient("PrisonTeamName", self.TeamName)

        local snapshot = self:GetSnapshot()
        local signature = table.concat({
            snapshot.Role, snapshot.TeamName, tostring(snapshot.IsAlive),
            tostring(snapshot.Health), tostring(snapshot.MaxHealth), snapshot.EquippedTool,
            snapshot.CharacterStatus,
        }, "|")
        if signature ~= self._lastSignature then
            self._lastSignature = signature
            EventBus:Publish("PrisonContextChanged", snapshot)
        end
        return snapshot
    end

    function Context:FormatDuration(): string
        local seconds = math.max(0, math.floor(self:GetSessionDuration()))
        return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
    end

    function Context:Initialize()
        if not LocalPlayer then return end

        local function watchCharacter(character: Model)
            -- Bind by key so a respawn replaces the previous character's watch instead of stacking.
            local owner = scope:CreateChild("Character watch")
            scope:Bind("CharacterWatch", owner)
            local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 6)
            if not humanoid or scope:IsDisposed() then owner:Dispose(); return end
            owner:Connect(humanoid:GetPropertyChangedSignal("Health"), function() Context:Refresh() end)
            owner:Connect(character.ChildAdded, function() Context:Refresh() end)
            owner:Connect(character.ChildRemoved, function() Context:Refresh() end)
            owner:Connect(character.AncestryChanged, function() Context:Refresh() end)
        end

        scope:Add(LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function() self:Refresh() end))
        scope:Add(LocalPlayer:GetPropertyChangedSignal("TeamColor"):Connect(function() self:Refresh() end))
        scope:Add(PlayerTracker:OnLocalCharacterRespawn(function(assets: any)
            self.EquippedTool, self._lastSignature = "None", ""
            if LocalPlayer.Character then watchCharacter(LocalPlayer.Character) end
            self:Refresh()
            -- Respawn ends every automation unless the user asked to keep them running.
            if StateStore:Get("Game.StopAutomationOnRespawn") and Prison.StopAllAutomation then
                Prison.StopAllAutomation("respawned")
            end
        end))
        if LocalPlayer.Character then watchCharacter(LocalPlayer.Character) end

        -- Safety net: a slow refresh keeps health/nearest/equipped honest even if a signal is missed.
        scope:Spawn(function()
            while not scope:IsDisposed() do
                task.wait(1)
                if not scope:IsDisposed() then Context:Refresh() end
            end
        end)

        self:Refresh()
    end

    function Context:Destroy() scope:Dispose() end

    return Context
end
