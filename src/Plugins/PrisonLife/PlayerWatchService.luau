--!nonstrict
-- Prison Life player watch: a live player list with distances and tools, plus spectate,
-- whitelist, and copy-name actions. Stateless by design; the UI polls at its own rate.
return function(services: any, _Prison: any?): any
    local PlayerTracker = services:Get("PlayerTracker")
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
        return {
            Player = player, Distance = distance, Tool = tool,
            Alive = assets ~= nil and assets.Humanoid.Health > 0,
        }
    end

    function PlayerWatch:GetEntries(): { any }
        local entries = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then table.insert(entries, describe(player)) end
        end
        table.sort(entries, function(a: any, b: any)
            return (a.Distance or math.huge) < (b.Distance or math.huge)
        end)
        return entries
    end

    function PlayerWatch:GetWatchNames(): { string }
        local names = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then table.insert(names, player.Name) end
        end
        table.sort(names, function(a: string, b: string) return a:lower() < b:lower() end)
        return names
    end

    function PlayerWatch:GetSelected(): Player? return self._selected end

    function PlayerWatch:SetSelectedByName(name: string): (boolean, string)
        local player = PlayerTracker:GetPlayerByName(name)
        if not player then return false, "Select a player who is still in the server" end
        self._selected = player
        return true, "Watching " .. player.Name
    end

    function PlayerWatch:ResolveWatchName(name: string): Player?
        return PlayerTracker:GetPlayerByName(name)
    end

    function PlayerWatch:GetSelectedSummary(): any?
        local selected = self._selected
        if not selected or not selected.Parent then return nil end
        return describe(selected)
    end

    return PlayerWatch
end
