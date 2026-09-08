--!nonstrict
-- Prison Life player watch: role-grouped player lists with distances and tools, a nearest
-- threat summary, join/leave alerts, and the bridges that make the universal ESP/chams and
-- aim/trigger filters role-aware without changing their contracts.
return function(services: any, Prison: any?): any
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local Disposer = services:Get("Disposer")
    local PlayerTracker = services:Get("PlayerTracker")

    local Prison = Prison or {}
    local manifest = Prison.Manifest
    local scope = Disposer:CreateChild("PrisonLife.PlayerWatch")
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer

    local PlayerWatch = { _selected = nil :: Player? }

    local function describe(player: Player): any
        local assets = PlayerTracker:GetPlayerAssets(player)
        local localAssets = PlayerTracker:GetLocalAssets()
        local distance = nil
        if assets and localAssets then
            distance = (assets.RootPart.Position - localAssets.RootPart.Position).Magnitude
        end
        local tool = "None"
        if assets then
            for _, child in ipairs(assets.Character:GetChildren()) do
                if child:IsA("Tool") then tool = child.Name break end
            end
        end
        local role = Prison.Context and Prison.Context:GetPlayerRole(player) or "Unknown"
        return {
            Player = player, Role = role, Distance = distance, Tool = tool,
            Alive = assets ~= nil and assets.Humanoid.Health > 0,
        }
    end

    function PlayerWatch:GetGroups(): { any }
        local groups = {}
        for _, role in ipairs(manifest.Roles.Order) do groups[role] = { Role = role, Entries = {} } end
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local entry = describe(player)
                table.insert(groups[entry.Role].Entries, entry)
            end
        end
        local result = {}
        for _, role in ipairs(manifest.Roles.Order) do
            local group = groups[role]
            if #group.Entries > 0 then
                table.sort(group.Entries, function(a: any, b: any)
                    return (a.Distance or math.huge) < (b.Distance or math.huge)
                end)
                table.insert(result, group)
            end
        end
        return result
    end

    function PlayerWatch:GetThreats(limit: number?): { any }
        local localRole = Prison.Context and Prison.Context:GetLocalRole() or "Unknown"
        local threats = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local entry = describe(player)
                if entry.Alive and entry.Role ~= localRole and entry.Role ~= "Unknown" then
                    table.insert(threats, entry)
                end
            end
        end
        table.sort(threats, function(a: any, b: any)
            return (a.Distance or math.huge) < (b.Distance or math.huge)
        end)
        local result = {}
        for index = 1, math.min(limit or 3, #threats) do table.insert(result, threats[index]) end
        return result
    end

    function PlayerWatch:GetSelected(): Player? return self._selected end

    function PlayerWatch:SetSelectedByName(name: string): (boolean, string)
        local player = PlayerTracker:GetPlayerByName(name)
        if not player then return false, "Select a player who is still in the server" end
        self._selected = player
        return true, "Watching " .. player.Name
    end

    function PlayerWatch:GetWatchNames(): { string }
        local names = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local role = Prison.Context and Prison.Context:GetPlayerRole(player) or "Unknown"
                table.insert(names, player.Name .. " [" .. role .. "]")
            end
        end
        table.sort(names, function(a: string, b: string) return a:lower() < b:lower() end)
        return names
    end

    function PlayerWatch:ResolveWatchName(name: string): Player?
        -- Watch entries carry a trailing "[Role]" tag; strip it before resolving the player.
        local clean = tostring(name or ""):match("^(.-)%s*%[[^%]]*%]%s*$")
        return PlayerTracker:GetPlayerByName(clean or tostring(name or ""))
    end

    function PlayerWatch:Initialize()
        -- Role-aware ESP / chams colors and aim / trigger filtering through two transient hooks.
        StateStore:SetTransient("PlayerColorResolver", function(player: Player, source: string): Color3?
            if source == "Chams" and StateStore:Get("Game.RoleColoredChams") ~= true then return nil end
            if source ~= "Chams" and StateStore:Get("Game.RoleColoredESP") ~= true then return nil end
            if not Prison.Context then return nil end
            return Prison.Context:GetRoleColor(Prison.Context:GetPlayerRole(player))
        end)
        StateStore:SetTransient("TargetFilterExtension", function(player: Player): boolean
            if not Prison.Context then return true end
            return Prison.Context:ValidateTargetRole(player)
        end)

        scope:Add(EventBus:Subscribe("PlayerJoined", function(player: Player)
            if StateStore:Get("Game.WatchAlerts") == true and Prison.Context then
                local role = Prison.Context:GetPlayerRole(player)
                EventBus:Publish("Notify", "Prison Life", player.Name .. " joined (" .. role .. ")")
            end
        end))
        scope:Add(EventBus:Subscribe("PlayerLeft", function(player: Player)
            if self._selected == player then self._selected = nil end
            if StateStore:Get("Game.WatchAlerts") == true then
                EventBus:Publish("Notify", "Prison Life", player.Name .. " left")
            end
        end))
    end

    function PlayerWatch:Destroy()
        StateStore:SetTransient("PlayerColorResolver", nil)
        StateStore:SetTransient("TargetFilterExtension", nil)
        scope:Dispose()
    end

    return PlayerWatch
end
