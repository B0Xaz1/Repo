--!nonstrict
-- AutoQueueService: automated queue entry and match detection for Murderers VS Sheriffs DUELS.
-- Runs an auto-requeue loop when enabled, entering queues via remote triggers, UI buttons,
-- or physical lobby pads. It monitors match state, respawns, and round transitions,
-- pausing during active duels and re-queueing once the player returns to the lobby or ends a match.
return function(services: any, Duel: any?): any
    local StateStore = services:Get("StateStore")
    local Disposer = services:Get("Disposer")
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TeleportService = game:GetService("TeleportService")
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

    -- Common mode name aliases
    local MODE_MAP = {
        ["1v1"] = { "1v1", "Solo", "1vs1", "Duel" },
        ["2v2"] = { "2v2", "Duo", "2vs2" },
        ["3v3"] = { "3v3", "Trio", "3vs3" },
        ["4v4"] = { "4v4", "Squad", "4vs4" },
    }

    -- Check if player is currently inside an active duel
    function AutoQueue:IsInMatch(): boolean
        if not LocalPlayer then return false end
        local matchVal = LocalPlayer:GetAttribute(matchAttribute)
        if matchVal ~= nil and tostring(matchVal) ~= "" and tostring(matchVal) ~= "0" and tostring(matchVal) ~= "Lobby" then
            return true
        end

        -- Secondary check: if we have opponents with the same match attribute and opposing teams
        if Duel.Targets and Duel.Targets.GetOpponents then
            local opponents = Duel.Targets:GetOpponents()
            if opponents and #opponents > 0 then
                return true
            end
        end

        return false
    end

    -- Attempt to find a remote function/event related to queueing
    local function findQueueRemote(): any
        local remoteNames = queueConfig.RemoteNames or {
            "Queue", "QueueRemote", "JoinQueue", "EnterQueue", "Matchmaking", "Queue1v1", "QueueDuel"
        }

        local function checkContainer(parent: Instance?): any
            if not parent then return nil end
            for _, name in ipairs(remoteNames) do
                local child = parent:FindFirstChild(name)
                if child and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
                    return child
                end
            end
            for _, child in ipairs(parent:GetChildren()) do
                if child:IsA("Folder") or child:IsA("Configuration") then
                    for _, name in ipairs(remoteNames) do
                        local match = child:FindFirstChild(name)
                        if match and (match:IsA("RemoteEvent") or match:IsA("RemoteFunction")) then
                            return match
                        end
                    end
                end
            end
            return nil
        end

        return checkContainer(ReplicatedStorage) or checkContainer(ReplicatedStorage:FindFirstChild("Remotes"))
    end

    -- Click a GUI button in PlayerGui (simulating UI queue join)
    local function tryTriggerGuiQueue(mode: string): boolean
        local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then return false end

        local targetKeywords = MODE_MAP[mode] or { mode }
        local foundButton: GuiButton? = nil

        local function scanGui(parent: Instance)
            if foundButton then return end
            for _, child in ipairs(parent:GetDescendants()) do
                if child:IsA("GuiButton") and child.Visible then
                    local btnText = ""
                    if child:IsA("TextButton") then
                        btnText = child.Text:lower()
                    end
                    local btnName = child.Name:lower()

                    for _, kw in ipairs(targetKeywords) do
                        local lkw = kw:lower()
                        if string.find(btnText, lkw, 1, true) or string.find(btnName, lkw, 1, true) then
                            foundButton = child
                            return
                        end
                    end
                end
            end
        end

        pcall(scanGui, playerGui)

        if foundButton then
            pcall(function()
                if (foundButton :: any).FireServer then
                    (foundButton :: any):FireServer()
                elseif (foundButton :: any).Activated then
                    -- Trigger event signals if supported
                    for _, conn in ipairs(getconnections(foundButton.Activated) or {}) do
                        conn:Fire()
                    end
                end
            end)
            return true
        end

        return false
    end

    -- Trigger queue pad touch in workspace (physical lobby queue pad)
    local function tryTriggerPadQueue(mode: string): boolean
        local char = LocalPlayer and LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return false end

        local targetKeywords = MODE_MAP[mode] or { mode }
        local padFolderNames = { "Pads", "QueuePads", "Queues", "Lobby", "DuelPads", "Portals" }

        local function checkPad(part: Instance): boolean
            if not part:IsA("BasePart") then return end
            local name = part.Name:lower()
            for _, kw in ipairs(targetKeywords) do
                if string.find(name, kw:lower(), 1, true) then
                    return true
                end
            end
            return false
        end

        local function searchIn(parent: Instance?): BasePart?
            if not parent then return nil end
            for _, desc in ipairs(parent:GetDescendants()) do
                if desc:IsA("BasePart") and checkPad(desc) then
                    return desc
                end
            end
            return nil
        end

        local targetPad: BasePart? = nil
        for _, fName in ipairs(padFolderNames) do
            local folder = workspace:FindFirstChild(fName)
            targetPad = searchIn(folder)
            if targetPad then break end
        end
        if not targetPad then
            targetPad = searchIn(workspace)
        end

        if targetPad then
            pcall(function()
                if firetouchinterest then
                    firetouchinterest(root, targetPad, 0)
                    task.wait(0.05)
                    firetouchinterest(root, targetPad, 1)
                else
                    -- Move slightly to pad position as fallback
                    root.CFrame = targetPad.CFrame + Vector3.new(0, 3, 0)
                end
            end)
            return true
        end

        return false
    end

    -- Main attempt to enter queue
    function AutoQueue:TriggerQueue(): (boolean, string)
        local mode = tostring(StateStore:Get("Game.MvSQueueMode") or self._selectedMode or "1v1")
        self._selectedMode = mode

        -- 1. Try Remote call
        local remote = findQueueRemote()
        if remote then
            local success, err = pcall(function()
                if remote:IsA("RemoteFunction") then
                    remote:InvokeServer(mode)
                else
                    remote:FireServer(mode)
                end
            end)
            if success then
                self._lastStatusMessage = "Invoked queue remote (" .. mode .. ")"
                return true, self._lastStatusMessage
            end
        end

        -- 2. Try GUI buttons
        if tryTriggerGuiQueue(mode) then
            self._lastStatusMessage = "Triggered UI button (" .. mode .. ")"
            return true, self._lastStatusMessage
        end

        -- 3. Try Pad touch
        if tryTriggerPadQueue(mode) then
            self._lastStatusMessage = "Stepped on queue pad (" .. mode .. ")"
            return true, self._lastStatusMessage
        end

        self._lastStatusMessage = "Waiting for lobby / queue trigger"
        return false, self._lastStatusMessage
    end

    local function step(now: number)
        local enabled = StateStore:Get("Game.MvSAutoQueue") == true
        if not enabled then
            AutoQueue._state = "Idle"
            return
        end

        local inMatch = AutoQueue:IsInMatch()

        -- Match state transition detection
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

        -- We are in the lobby or waiting for a match
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

        -- Reset queue attempt timer when respawning in lobby
        scope:Add(LocalPlayer.CharacterAdded:Connect(function()
            if not AutoQueue:IsInMatch() then
                AutoQueue._lastAttempt = os.clock() -- give a grace window on spawn
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
        }
    end

    function AutoQueue:Destroy()
        scope:Dispose()
    end

    return AutoQueue
end
