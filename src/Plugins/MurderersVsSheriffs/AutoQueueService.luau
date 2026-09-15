--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

return function(services: any, Duel: any?): any
    local StateStore = services:Get("StateStore")
    local Disposer = services:Get("Disposer")
    local EventBus = services:Get("EventBus")
    local LocalPlayer = Players.LocalPlayer

    local Duel = Duel or {}
    local manifest = Duel.Manifest or {}
    local queueConfig = manifest.Queue or {}
    local matchAttribute = (manifest.Match and manifest.Match.Attribute) or "Match"

    local scope = Disposer:CreateChild(`{manifest.Name or "MvSDuels"}.AutoQueue`)

    local AutoQueue = {
        _running = false,
        _state = "Idle",
        _lastAttempt = 0,
        _lastMatchValue = nil :: any,
        _selectedMode = "1v1",
        _queueAttempts = 0,
        _matchesCount = 0,
        _lastStatusMessage = "Ready",
        _charScope = nil :: any,
    }

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

    local CONFIG = table.freeze({
        CHECK_RADIUS = 3.2,
        OCCUPANT_VERTICAL_TOLERANCE = 4.5,
        HOLD_DISTANCE = 3.5,
        PAD_PROXIMITY = 5,
        TOUCH_DEBOUNCE = 0.3,
        FULL_RETRY_INTERVAL = 1.5,
        RAYCAST_DEPTH = 6,
        FALLBACK_MODE = "1v1",
        FALLBACK_REMOTE_NAMES = { "Queue", "QueueRemote", "JoinQueue", "EnterQueue", "Matchmaking", "Queue1v1", "QueueDuel" },
        FOOT_PART_NAMES = { "HumanoidRootPart", "LeftFoot", "RightFoot", "LowerTorso" },
        MODE_CAPACITY = { ["1v1"] = 1, ["2v2"] = 2, ["3v3"] = 3, ["4v4"] = 4 },
    })

    local function getPierFolder(): Instance?
        local lobby = Workspace:FindFirstChild("Lobby")
        if lobby then
            local env = lobby:FindFirstChild("Environment") or lobby:FindFirstChild("environment")
            if env then
                local pier = env:FindFirstChild("Pier") or env:FindFirstChild("pier")
                if pier then return pier end
            end
        end
        return nil
    end

    local function isPierPart(part: Instance?): boolean
        if not part then return false end
        local pier = getPierFolder()
        if pier and part:IsDescendantOf(pier) then
            return true
        end
        return false
    end

    function AutoQueue:IsTouchingPier(): boolean
        local char = LocalPlayer and LocalPlayer.Character
        if not char then return false end
        local root = char:FindFirstChild("HumanoidRootPart")
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not root then return false end

        for _, positions in pairs(QUEUE_POSITIONS) do
            for _, padPos in ipairs(positions) do
                if (root.Position - padPos).Magnitude <= CONFIG.PAD_PROXIMITY then
                    return false
                end
            end
        end

        local pier = getPierFolder()
        if not pier then return false end

        local floorPart: Instance? = nil
        pcall(function()
            floorPart = humanoid.FloorPart
        end)
        if floorPart and floorPart:IsDescendantOf(pier) then
            return true
        end

        local origin = root.Position
        local direction = Vector3.new(0, -CONFIG.RAYCAST_DEPTH, 0)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = { pier }
        local hit = Workspace:Raycast(origin, direction, params)
        if hit and hit.Instance and hit.Instance:IsDescendantOf(pier) then
            return true
        end

        local isTouching = false
        pcall(function()
            local overlap = OverlapParams.new()
            overlap.FilterType = Enum.RaycastFilterType.Include
            overlap.FilterDescendantsInstances = { pier }

            for _, partName in ipairs(CONFIG.FOOT_PART_NAMES) do
                local bodyPart = char:FindFirstChild(partName)
                if bodyPart and bodyPart:IsA("BasePart") then
                    local touching = Workspace:GetPartsInPart(bodyPart, overlap)
                    if touching and #touching > 0 then
                        isTouching = true
                        return
                    end
                end
            end
        end)

        return isTouching
    end

    function AutoQueue:IsOnPier(): boolean
        return self:IsTouchingPier()
    end

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

    function AutoQueue:CountOccupants(pos: Vector3, radius: number?): number
        local checkRadius = radius or CONFIG.CHECK_RADIUS
        local count = 0
        local countedChars: { [Model]: boolean } = {}

        local function checkChar(char: Instance?)
            if not char or not char:IsA("Model") or countedChars[char] then return end
            if LocalPlayer and char == LocalPlayer.Character then return end

            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then return end

            local part = char:FindFirstChild("HumanoidRootPart")
                or char:FindFirstChild("Torso")
                or char:FindFirstChild("UpperTorso")
                or char.PrimaryPart

            if part and part:IsA("BasePart") then
                local pPos = part.Position
                local horizDist = Vector2.new(pPos.X - pos.X, pPos.Z - pos.Z).Magnitude
                local vertDist = math.abs(pPos.Y - pos.Y)
                if horizDist <= checkRadius and vertDist <= CONFIG.OCCUPANT_VERTICAL_TOLERANCE then
                    countedChars[char] = true
                    count += 1
                end
            end
        end

        for _, player in ipairs(Players:GetPlayers()) do
            checkChar(player.Character)
        end

        return count
    end

    function AutoQueue:GetBestPosition(mode: string): (Vector3?, number?, boolean)
        local pair = QUEUE_POSITIONS[mode] or QUEUE_POSITIONS["1v1"]
        local pos1, pos2 = pair[1], pair[2]
        local maxPerStrand = CONFIG.MODE_CAPACITY[mode] or 1
        local count1 = self:CountOccupants(pos1, CONFIG.CHECK_RADIUS)

        if count1 < maxPerStrand then
            return pos1, 1, false
        end

        local count2 = self:CountOccupants(pos2, CONFIG.CHECK_RADIUS)
        if count2 < maxPerStrand then
            return pos2, 2, false
        end

        return nil, nil, true
    end

    function AutoQueue:TeleportToQueue(mode: string): (boolean, string)
        local char = LocalPlayer and LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            return false, "No HumanoidRootPart found"
        end

        local targetPos, strandIndex, isFull = self:GetBestPosition(mode)

        if isFull or not targetPos or not strandIndex then
            local maxPerStrand = CONFIG.MODE_CAPACITY[mode] or 1
            local fullMsg = `no available {mode} left`
            self._lastStatusMessage = fullMsg
            if EventBus then
                EventBus:Publish("Notify", "Auto Queue", fullMsg, 4)
            end
            return false, fullMsg
        end

        if strandIndex == 2 then
            if EventBus then
                EventBus:Publish("Notify", "Auto Queue", "stand 1 is full going to next one", 3)
            end
        end

        local currentDist = (root.Position - targetPos).Magnitude

        if currentDist <= CONFIG.HOLD_DISTANCE then
            self._lastStatusMessage = `Holding {mode} strand #{strandIndex}`
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

        self._lastStatusMessage = `Moved to {mode} strand #{strandIndex}{strandIndex == 2 and " (strand 1 full)" or ""}`
        return true, self._lastStatusMessage
    end

    local function tryQueueRemote(mode: string): boolean
        local remoteNames = queueConfig.RemoteNames or CONFIG.FALLBACK_REMOTE_NAMES
        for _, name in ipairs(remoteNames) do
            local rem = ReplicatedStorage:FindFirstChild(name) or (ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild(name))
            if rem then
                pcall(function()
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

    function AutoQueue:TriggerQueue(): (boolean, string)
        local mode = tostring(StateStore:Get("Game.MvSQueueMode") or self._selectedMode or CONFIG.FALLBACK_MODE)
        self._selectedMode = mode

        local success, msg = self:TeleportToQueue(mode)
        if success then
            task.spawn(tryQueueRemote, mode)
            return true, msg
        end

        self._lastStatusMessage = msg
        return false, msg
    end

    function AutoQueue:OnTouchedPart(hit: Instance)
        if StateStore:Get("Game.MvSAutoQueue") ~= true then return end
        if self:IsInMatch() then return end

        if isPierPart(hit) then
            local now = os.clock()
            if now - self._lastAttempt >= CONFIG.TOUCH_DEBOUNCE then
                self._lastAttempt = now
                self._state = "Queued"
                self._queueAttempts += 1
                self:TriggerQueue()
            end
        end
    end

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

        if AutoQueue:IsTouchingPier() then
            local mode = tostring(StateStore:Get("Game.MvSQueueMode") or AutoQueue._selectedMode or CONFIG.FALLBACK_MODE)
            local bestPos, strandIdx, isFull = AutoQueue:GetBestPosition(mode)

            if isFull or not bestPos then
                if now - AutoQueue._lastAttempt >= CONFIG.FULL_RETRY_INTERVAL then
                    AutoQueue._lastAttempt = now
                    AutoQueue:TriggerQueue()
                end
                return
            end

            local char = LocalPlayer and LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local distToTarget = root and (root.Position - bestPos).Magnitude or 9999

            if distToTarget > CONFIG.HOLD_DISTANCE then
                if now - AutoQueue._lastAttempt >= CONFIG.TOUCH_DEBOUNCE then
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
        self._lastStatusMessage = `Reset ({tostring(reason or "user")})`
    end

    function AutoQueue:Initialize()
        scope:Add(RunService.Heartbeat:Connect(function()
            pcall(step, os.clock())
        end))

        if LocalPlayer.Character then
            self:BindCharacterTouches(LocalPlayer.Character)
        end

        scope:Add(LocalPlayer.CharacterAdded:Connect(function(char)
            self:BindCharacterTouches(char)
            if not AutoQueue:IsInMatch() then
                AutoQueue._lastAttempt = 0
            end
        end))
    end

    function AutoQueue:GetStatus(): any
        local enabled = StateStore:Get("Game.MvSAutoQueue") == true
        return {
            Enabled = enabled,
            State = if enabled then self._state else "Off",
            Mode = tostring(StateStore:Get("Game.MvSQueueMode") or self._selectedMode or CONFIG.FALLBACK_MODE),
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
