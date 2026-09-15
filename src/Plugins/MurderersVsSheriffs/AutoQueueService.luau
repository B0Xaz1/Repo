--!nonstrict
-- AutoQueueService: automated queue entry and match detection for Murderers VS Sheriffs DUELS.
-- Whenever AutoQueue is enabled and the player is touching any part/meshpart in
-- Workspace.Lobby.Environment.Pier (or in the pier area), it executes the exact same
-- working queue logic as "Queue now": checking Position 1 occupancy with 1-stud leeway
-- and teleporting to Position 2 if Position 1 is taken.
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
        _state = "Idle", -- "Idle" | "Active" | "Queued" | "InMatch"
        _lastAttempt = 0,
        _lastMatchValue = nil :: any,
        _selectedMode = "1v1",
        _queueAttempts = 0,
        _matchesCount = 0,
        _lastStatusMessage = "Ready",
        _charScope = nil :: any,
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
        local lobby = workspace:FindFirstChild("Lobby")
        if lobby then
            local env = lobby:FindFirstChild("Environment") or lobby:FindFirstChild("environment")
            if env then
                local pier = env:FindFirstChild("Pier") or env:FindFirstChild("pier")
                if pier then return pier end
            end
            for _, desc in ipairs(lobby:GetDescendants()) do
                if desc.Name:lower() == "pier" then
                    return desc
                end
            end
        end

        for _, desc in ipairs(workspace:GetChildren()) do
            if desc.Name:lower() == "lobby" then
                for _, sub in ipairs(desc:GetDescendants()) do
                    if sub.Name:lower() == "pier" then
                        return sub
                    end
                end
            end
        end

        return nil
    end

    -- Fast check to see if an instance belongs to Workspace.Lobby.Environment.Pier
    local function isPierPart(part: Instance?): boolean
        if not part then return false end
        local pier = getPierFolder()
        if pier and part:IsDescendantOf(pier) then
            return true
        end

        -- Path ancestry fallback
        local p: Instance? = part
        while p and p ~= workspace do
            if p.Name:lower() == "pier" then
                return true
            end
            p = p.Parent
        end
        return false
    end

    -- Check if player is on or physically touching any part in Workspace.Lobby.Environment.Pier
    function AutoQueue:IsTouchingPier(): boolean
        local char = LocalPlayer and LocalPlayer.Character
        if not char then return false end
        local root = char:FindFirstChild("HumanoidRootPart")
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not root then return false end

        -- 1. Check FloorPart from humanoid safely (FloorPart is not supported or accessible on some humanoid/rig types)
        local floorPart: Instance? = nil
        pcall(function()
            floorPart = humanoid.FloorPart
        end)
        if floorPart and isPierPart(floorPart) then
            return true
        end

        local pier = getPierFolder()

        -- 2. Spatial query using GetPartsInPart
        if pier then
            pcall(function()
                local overlap = OverlapParams.new()
                overlap.FilterType = Enum.RaycastFilterType.Include
                overlap.FilterDescendantsInstances = { pier }

                for _, partName in ipairs({ "HumanoidRootPart", "LeftFoot", "RightFoot", "LowerTorso" }) do
                    local bodyPart = char:FindFirstChild(partName)
                    if bodyPart and bodyPart:IsA("BasePart") then
                        local touching = workspace:GetPartsInPart(bodyPart, overlap)
                        if touching and #touching > 0 then
                            return true
                        end
                    end
                end
            end)
        end

        -- 3. Raycast downwards directly beneath the character
        local origin = root.Position
        local direction = Vector3.new(0, -8, 0)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { char }
        local hit = workspace:Raycast(origin, direction, params)
        if hit and hit.Instance and isPierPart(hit.Instance) then
            return true
        end

        -- 4. Bounding volume check of the pier area (coordinates around X: 20-65, Y: -100 to -80, Z: -220 to -140)
        local pos = root.Position
        if (pos.X >= 15 and pos.X <= 70) and (pos.Y >= -105 and pos.Y <= -75) and (pos.Z >= -230 and pos.Z <= -135) then
            return true
        end

        return false
    end

    function AutoQueue:IsOnPier(): boolean
        return self:IsTouchingPier()
    end

    -- Check if player is currently in an active duel match.
    function AutoQueue:IsInMatch(): boolean
        if not LocalPlayer then return false end
        if self:IsTouchingPier() then return false end

        local matchVal = LocalPlayer:GetAttribute(matchAttribute)
        if matchVal ~= nil and tostring(matchVal) ~= "" and tostring(matchVal) ~= "0" and tostring(matchVal):lower() ~= "lobby" then
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
                    local dist = (root.Position - pos).Magnitude
                    if dist <= threshold then
                        return true
                    end
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

    -- Teleport player to the destination (same logic that executes on "Queue now")
    function AutoQueue:TeleportToQueue(mode: string): (boolean, string)
        local char = LocalPlayer and LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            return false, "No HumanoidRootPart found"
        end

        local targetPos, strandIndex = self:GetBestPosition(mode)
        local currentDist = (root.Position - targetPos).Magnitude

        -- If already at this strand position within leeway, we are holding it
        if currentDist <= LEEWAY then
            self._lastStatusMessage = "Holding " .. mode .. " strand #" .. strandIndex
            return true, self._lastStatusMessage
        end

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

    -- Trigger queue action: runs the exact "Queue now" logic
    function AutoQueue:TriggerQueue(): (boolean, string)
        local mode = tostring(StateStore:Get("Game.MvSQueueMode") or self._selectedMode or "1v1")
        self._selectedMode = mode

        local success, msg = self:TeleportToQueue(mode)
        if success then
            task.spawn(tryQueueRemote, mode)
            return true, msg
        end

        self._lastStatusMessage = msg
        return false, msg
    end

    -- Touch handler for immediate response on contact with Pier
    function AutoQueue:OnTouchedPart(hit: Instance)
        if StateStore:Get("Game.MvSAutoQueue") ~= true then return end
        if self:IsInMatch() then return end

        if isPierPart(hit) then
            local now = os.clock()
            if now - self._lastAttempt >= 0.3 then
                self._lastAttempt = now
                self._state = "Queued"
                self._queueAttempts += 1
                self:TriggerQueue()
            end
        end
    end

    -- Hook Touched events on character parts to instantly react when touching Pier
    function AutoQueue:BindCharacterTouches(char: Model)
        if self._charScope then
            self._charScope:Dispose()
        end
        self._charScope = scope:CreateChild("CharTouches")

        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then
                self._charScope:Add(part.Touched:Connect(function(hit: Instance)
                    self:OnTouchedPart(hit)
                end))
            end
        end

        -- Also listen for DescendantAdded if parts are loaded dynamically
        self._charScope:Add(char.DescendantAdded:Connect(function(child: Instance)
            if child:IsA("BasePart") then
                self._charScope:Add(child.Touched:Connect(function(hit: Instance)
                    self:OnTouchedPart(hit)
                end))
            end
        end))
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

        if AutoQueue._state == "Idle" then
            AutoQueue._state = "Active"
        end

        -- Every step: if the player is touching Pier, trigger the exact queue logic
        if AutoQueue:IsTouchingPier() then
            local mode = tostring(StateStore:Get("Game.MvSQueueMode") or AutoQueue._selectedMode or "1v1")
            local bestPos, strandIdx = AutoQueue:GetBestPosition(mode)

            local char = LocalPlayer and LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local distToTarget = root and (root.Position - bestPos).Magnitude or 9999

            -- If touching Pier and not yet on the best position, trigger Queue Now logic
            if distToTarget > LEEWAY then
                if now - AutoQueue._lastAttempt >= 0.3 then
                    AutoQueue._lastAttempt = now
                    AutoQueue._state = "Queued"
                    AutoQueue._queueAttempts += 1
                    AutoQueue:TriggerQueue()
                end
                return
            end
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

        if LocalPlayer.Character then
            self:BindCharacterTouches(LocalPlayer.Character)
        end

        scope:Add(LocalPlayer.CharacterAdded:Connect(function(char)
            self:BindCharacterTouches(char)
            if not AutoQueue:IsInMatch() then
                AutoQueue._lastAttempt = 0 -- immediately ready
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
            OnPier = self:IsTouchingPier(),
        }
    end

    function AutoQueue:Destroy()
        if self._charScope then
            self._charScope:Dispose()
            self._charScope = nil
        end
        scope:Dispose()
    end

    return AutoQueue
end
