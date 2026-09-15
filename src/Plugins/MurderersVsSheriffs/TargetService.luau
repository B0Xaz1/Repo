--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

return function(_services: any, Duel: any?): any
    local LocalPlayer = Players.LocalPlayer

    local Duel = Duel or {}
    local manifest = Duel.Manifest
    local matchAttribute = manifest.Match.Attribute

    local Targets = {}

    function Targets:IsEnemy(player: Player): boolean
        if player == LocalPlayer then return false end
        local mine, theirs = LocalPlayer:GetAttribute(matchAttribute), player:GetAttribute(matchAttribute)
        if mine == nil or theirs == nil or tostring(mine) ~= tostring(theirs) then return false end
        return LocalPlayer.Team ~= nil and player.Team ~= nil and LocalPlayer.Team ~= player.Team
    end

    function Targets:GetOpponents(): { any }
        local list: { any } = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if self:IsEnemy(player) then
                local character = player.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                if character and character:IsDescendantOf(Workspace) and humanoid and humanoid.Health > 0 then
                    table.insert(list, { Player = player, Character = character, Humanoid = humanoid })
                end
            end
        end
        return list
    end

    function Targets:GetAttackList(): { any }
        local list: { any } = {}
        local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        for _, player in ipairs(Players:GetPlayers()) do
            if self:IsEnemy(player) then
                local character = player.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                local part
                if character then
                    for _, name in ipairs(manifest.AimParts) do
                        part = part or character:FindFirstChild(name)
                    end
                end
                local root = character and (character:FindFirstChild("HumanoidRootPart") or part)
                if character and humanoid and humanoid.Health > 0 and part and root then
                    local distance = myRoot and (root.Position - myRoot.Position).Magnitude or 0
                    table.insert(list, { Character = character, Humanoid = humanoid, Part = part, Root = root, Distance = distance })
                end
            end
        end
        table.sort(list, function(a: any, b: any) return a.Distance < b.Distance end)
        return list
    end

    return Targets
end
