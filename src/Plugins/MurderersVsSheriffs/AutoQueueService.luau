--!nonstrict
-- AutoQueueService: automated queue entry and match detection for Murderers VS Sheriffs DUELS.
-- When the player is on any part in Workspace.Lobby.Environment.Pier (or in the lobby),
-- it teleports them to their selected duel strand position (1v1, 2v2, 3v3, 4v4).
-- It checks if any other player is occupying Position 1 (within a 1 stud leeway) and if so,
-- moves to Position 2 (the second strand). It also handles remote and pad triggers as fallback.
return function(services: any, Duel: any?): any
    local StateStore = services:Get("StateStore")
    local Disposer = services:Get("Disposer")
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = Players.LocalPlayer

    local Duel = Duel or {}
    local manifest = Duel.Manifest or {}
    local queueConfig = manifest.Queue or {}
    local matchAttribute = (manifest.Match and manifest.Match.Attribute) or "Match"

    local scope = Disposer:CreateChild((manifest.Name or "MvSDuels") .. ".AutoQueue")

    local AutoQueue = {
        _running = false,
        _state = "Idle", -- "Idle" | "Queued" | "InMatch" | "Searching"
        _lastAttempt = 0,
        _lastMatchValue = nil :: any,
        _selectedMode = "1v1",
        _queueAttempts = 0,
        _matchesCount = 0,
        _lastStatusMessage = "Ready",
    }

    -- Exact mode strand positions with +2 studs Y elevation
    local QUEUE_POSITIONS: { [string]: { Vector3 } } = queueConfig.Positions or {
        ["1v1"] = {
            Vector3.new(56.9468994140625, -93.15959167480469, -203.5184783935547),
            Vector3.new(27.4266357421875, -93.15959167480469, -203.4810028076172),
        },
        ["2v2"] = {
            Vector3.new(56.784793853759766, -93.17820739746094, -189.26991271972656),
            Vector3.new(27.93301010131836, -93.17820739746094, -189.24061584472656),
        },
        ["3v3"] = {
            Vector3.new(56.6617431640625, -93.03361511230469, -173.23150634765625),
            Vector3.new(28.4437255859375, -93.03361511230469, -173.20989990234375),
        },
        ["4v4"] = {
            Vector3.new(56.58056640625, -92.84336853027344, -155.25958251953125),
            Vector3.new(28.959228515625, -92.84336853027344, -155.24517822265625),
        },
    }

    local LEEWAY: number = queueConfig.Leeway or 1.0

    -- Resolves Workspace.Lobby.Environment.Pier case-insensitively
    local function getPierFolder(): Instance?
        local pierPath = queueConfig.PierPath or { "Lobby", "Environment", "Pier" }
        local node: any = workspace

        for _, targetName in ipairs(pierPath) do
            if not node then break end
            local nextNode = node:FindFirstChild(targetName)
            if not nextNode then
                local lowerTarget = targetName:lower()
                for _, child in ipairs(node:GetChildren()) do
                    if child.Name:lower() == lowerTarget then
                        nextNode = child
                        break
                    end
                end
            end
            node = nextNode
        end

        -- Direct search fallback if not located via strict path
        if not node then
            local lobby = workspace:FindFirstChild("Lobby")
            if lobby then
                for _, desc in ipairs(lobby:GetDescendants()) do
                    if desc.Name:lower() == "pier" then
                        node = desc
                        break
                    end
                end
            end
        end

        return node
    end

    -- Check if player is on any part inside Workspace.Lobby.Environment.Pier
    function AutoQueue:IsOnPier(): boolean
        local char = LocalPlayer and LocalPlayer.Character
        if not char then return false end
        local root = char:FindFirstChild("HumanoidRootPart")
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not root or not humanoid then return false end

        local pier = getPierFolder()

        -- 1. Check FloorMaterial / FloorPart if available
        local floorPart = humanoid.FloorPart
        if floorPart and pier and floorPart:IsDescendantOf(pier) then
            return true
        end

        -- 2. Raycast downwards from HumanoidRootPart to see if touching any part inside Pier
        local origin = root.Position
        local direction = Vector3.new(0, -10, 0)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { char }
        local hit = workspace:Raycast(origin, direction, params)
        if hit and hit.Instance and pier and hit.Instance:IsDescendantOf(pier) then
            return true
        end

        -- 3. Proximity / bounding check to Pier parts
        if pier then
            for _, child in ipairs(pier:GetDescendants()) do
                if child:IsA("BasePart") then
                    local diff = (child.Position - root.Position)
                    local halfSize = child.Size * 0.5 + Vector3.new(4, 8, 4)
                    if math.abs(diff.X) <= halfSize.X and math.abs(diff.Y) <= halfSize.Y and math.abs(diff.Z) <= halfSize.Z then
                        return true
                    end
                end
            end
        end

        return false
    end

    -- Check if player is currently in an active duel match.
    -- In lobby, players often have Match = nil, "0", "Lobby", or have no non-nil opposing team.
    function AutoQueue:IsInMatch(): boolean
        if not LocalPlayer then return false end
        -- If player is on or near the pier, they are definitively in the lobby, never in a match.
        if self:IsOnPier() then return false end

        local matchVal = LocalPlayer:GetAttribute(matchAttribute)
        if matchVal ~= nil and tostring(matchVal) ~= "" and tostring(matchVal) ~= "0" and tostring(matchVal):lower() ~= "lobby" then
            -- Verify team status: spectators or lobby players are not fighting
            if LocalPlayer.Team ~= nil and tostring(LocalPlayer.Team.Name):lower() ~= "spectator" and tostring(LocalPlayer.Team.Name):lower() ~= "lobby" then
                return true
            end
        end

        return false
    end

    -- Check if any other player is occupying a position within leeway
    function AutoQueue:IsPositionOccupied(pos: Vector3, leeway: number?): boolean
        local threshold = leeway or LEEWAY
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local char = player.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root then
                    -- 3D Euclidean distance
                    local dist = (root.Position - pos).Magnitude
                    if dist <= threshold then
                        return true
                    end
                    -- Horizontal distance with vertical cylinder tolerance
                    local horizDist = Vector2.new(root.Position.X - pos.X, root.Position.Z - pos.Z).Magnitude
                    local vertDist = math.abs(root.Position.Y - pos.Y)
                    if horizDist <= threshold and vertDist <= 4.0 then
                        return true
                    end
                end
            end
        end
        return false
    end

    -- Determine target position based on chosen mode and occupancy
    function AutoQueue:GetBestPosition(mode: string): (Vector3, number)
        local pair = QUEUE_POSITIONS[mode] or QUEUE_POSITIONS["1v1"]
        local pos1, pos2 = pair[1], pair[2]

        -- If pos1 is occupied by another player within leeway, use pos2
        if self:IsPositionOccupied(pos1, LEEWAY) then
            return pos2, 2
        else
            return pos1, 1
        end
    end

    -- Move/Teleport player reliably to the destination
    function AutoQueue:TeleportToQueue(mode: string): (boolean, string)
        local char = LocalPlayer and LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            return false, "No HumanoidRootPart found"
        end

        local targetPos, strandIndex = self:GetBestPosition(mode)
        local currentDist = (root.Position - targetPos).Magnitude

        -- If we are already right there, consider it queued
        if currentDist <= LEEWAY then
            self._lastStatusMessage = "Holding " .. mode .. " strand #" .. strandIndex
            return true, self._lastStatusMessage
        end

        -- Multiple teleport approaches for robust executor compatibility
        pcall(function()
            if char.PivotTo then
                char:PivotTo(CFrame.new(targetPos))
            else
                root.CFrame = CFrame.new(targetPos)
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)

        self._lastStatusMessage = "Moved to " .. mode .. " strand #" .. strandIndex .. (strandIndex == 2 and " (strand 1 occupied)" or "")
        return true, self._lastStatusMessage
    end

    -- Fallback remote queue trigger if remote exists
    local function tryQueueRemote(mode: string): boolean
        local remoteNames = queueConfig.RemoteNames or {
            "Queue", "QueueRemote", "JoinQueue", "EnterQueue", "Matchmaking", "Queue1v1", "QueueDuel"
        }
        for _, name in ipairs(remoteNames) do
            local rem = ReplicatedStorage:FindFirstChild(name) or (ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild(name))
            if rem then
                local ok = pcall(function()
                    if rem:IsA("RemoteFunction") then
                        rem:InvokeServer(mode)
                    else
                        rem:FireServer(mode)
                    end
                end)
                if ok then return true end
            end
        end
        return false
    end

    -- Trigger queue action: Pier location positioning takes precedence, followed by fallback triggers
    function AutoQueue:TriggerQueue(): (boolean, string)
        local mode = tostring(StateStore:Get("Game.MvSQueueMode") or self._selectedMode or "1v1")
        self._selectedMode = mode

        -- Primary mechanism: send player to the specified duel strand position
        local success, msg = self:TeleportToQueue(mode)
        if success then
            task.spawn(tryQueueRemote, mode)
            return true, msg
        end

        self._lastStatusMessage = msg
        return false, msg
    end

    local function step(now: number)
        local enabled = StateStore:Get("Game.MvSAutoQueue") == true
        if not enabled then
            AutoQueue._state = "Idle"
            return
        end

        local inMatch = AutoQueue:IsInMatch()

        -- Match state change detection
        local currentMatchVal = LocalPlayer and LocalPlayer:GetAttribute(matchAttribute)
        if AutoQueue._lastMatchValue ~= currentMatchVal then
            if inMatch and not AutoQueue._lastMatchValue then
                AutoQueue._matchesCount += 1
            end
            AutoQueue._lastMatchValue = currentMatchVal
        end

        if inMatch then
            AutoQueue._state = "InMatch"
            return
        end

        -- In lobby: if enabled, mark active
        if AutoQueue._state == "Idle" then
            AutoQueue._state = "Active"
        end

        local onPier = AutoQueue:IsOnPier()
        local mode = tostring(StateStore:Get("Game.MvSQueueMode") or AutoQueue._selectedMode or "1v1")
        local bestPos, strandIdx = AutoQueue:GetBestPosition(mode)

        local char = LocalPlayer and LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local distToTarget = root and (root.Position - bestPos).Magnitude or 9999

        -- If player is on Pier and not on target position, move immediately!
        if onPier and distToTarget > LEEWAY then
            if now - AutoQueue._lastAttempt >= 0.5 then
                AutoQueue._lastAttempt = now
                AutoQueue._state = "Queued"
                AutoQueue._queueAttempts += 1
                task.spawn(function()
                    AutoQueue:TriggerQueue()
                end)
            end
            return
        end

        -- Periodic lobby queue check
        local delay = tonumber(StateStore:Get("Game.MvSQueueDelay")) or 3.0
        if delay < 0.5 then delay = 0.5 end

        if now - AutoQueue._lastAttempt >= delay then
            AutoQueue._lastAttempt = now
            AutoQueue._state = "Queued"
            AutoQueue._queueAttempts += 1
            task.spawn(function()
                AutoQueue:TriggerQueue()
            end)
        end
    end

    function AutoQueue:Reset(reason: string?)
        self._queueAttempts = 0
        self._lastAttempt = 0
        self._state = "Idle"
        self._lastStatusMessage = "Reset (" .. tostring(reason or "user") .. ")"
    end

    function AutoQueue:Initialize()
        scope:Add(RunService.Heartbeat:Connect(function()
            local ok, err = pcall(step, os.clock())
            if not ok then
                warn("[B0Xaz][" .. (manifest.Name or "MvSDuels") .. ":AutoQueue] " .. tostring(err))
            end
        end))

        -- Reset queue timer on respawn
        scope:Add(LocalPlayer.CharacterAdded:Connect(function()
            if not AutoQueue:IsInMatch() then
                AutoQueue._lastAttempt = os.clock()
            end
        end))
    end

    function AutoQueue:GetStatus(): any
        local enabled = StateStore:Get("Game.MvSAutoQueue") == true
        return {
            Enabled = enabled,
            State = if enabled then self._state else "Off",
            Mode = tostring(StateStore:Get("Game.MvSQueueMode") or self._selectedMode or "1v1"),
            Attempts = self._queueAttempts,
            Matches = self._matchesCount,
            Message = self._lastStatusMessage,
            OnPier = self:IsOnPier(),
        }
    end

    function AutoQueue:Destroy()
        scope:Dispose()
    end

    return AutoQueue
end
