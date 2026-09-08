--!nonstrict
-- Prison Life weapon macro: a small state machine (Idle/Starting/Running/Paused/Cancelled/
-- Completed) that rotates through held tools. Death, respawn, focus loss, panic, and unload
-- all stop it; the UI can always show the exact state and stop reason.
return function(services: any, Prison: any?): any
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local Disposer = services:Get("Disposer")
    local PlayerTracker = services:Get("PlayerTracker")
    local Environment = services:Get("Environment")
    local UserInputService = game:GetService("UserInputService")
    local Players = game:GetService("Players")

    local Prison = Prison or {}
    local scope = Disposer:CreateChild("PrisonLife.Macro")
    local LocalPlayer = Players.LocalPlayer

    local MacroService = {
        _running = false,
        _thread = nil :: thread?,
        _state = "Idle",
        _stopReason = nil :: string?,
        _nextTool = "None",
        _cycles = 0,
    }

    function MacroService:GetValidWeapons(): { Tool }
        local tools = {}
        local function visit(parent: Instance)
            if not parent then return end
            for _, child in ipairs(parent:GetChildren()) do
                if child:IsA("Tool") then table.insert(tools, child) end
            end
        end
        visit(LocalPlayer and LocalPlayer:FindFirstChildOfClass("Backpack"))
        visit(LocalPlayer and LocalPlayer.Character)
        table.sort(tools, function(a: Tool, b: Tool) return a.Name:lower() < b.Name:lower() end)
        return tools
    end

    function MacroService:SwitchToNextTool(tools: { Tool }): string?
        local assets = PlayerTracker:GetLocalAssets()
        if not assets or #tools == 0 then return nil end
        local equipped = nil
        for _, tool in ipairs(tools) do
            if tool.Parent == assets.Character then equipped = tool break end
        end
        local index = if equipped then table.find(tools, equipped) or 0 else 0
        local nextTool = tools[(index % #tools) + 1]
        if nextTool and nextTool ~= equipped then
            local ok = pcall(function() assets.Humanoid:EquipTool(nextTool) end)
            if not ok then return nil end
        end
        self._nextTool = nextTool and nextTool.Name or "None"
        self._cycles += 1
        return self._nextTool
    end

    function MacroService:GetState(): string return self._state end

    function MacroService:GetStatus(): any
        return {
            State = self._state,
            StopReason = self._stopReason,
            NextTool = self._nextTool,
            Cycles = self._cycles,
            Delay = math.clamp(tonumber(StateStore:Get("Game.FakeMacroDelay")) or 0.06, 0.03, 0.5),
            Running = self._running,
        }
    end

    local function publish()
        EventBus:Publish("PrisonMacroChanged", MacroService:GetStatus())
    end

    function MacroService:Start(): (boolean, string)
        if self._running then return false, "Macro is already running" end
        local assets = PlayerTracker:GetLocalAssets()
        if not assets or not assets.Humanoid then return false, "Your character is not ready" end

        self._running = true
        self._state = "Running"
        self._stopReason = nil
        StateStore:Set("Game.FakeMacro", true)

        self._thread = scope:Spawn(function()
            while self._running do
                if not PlayerTracker:IsAlive(Players.LocalPlayer) then
                    self:Stop("died")
                    break
                end
                -- A focused textbox (chat, search, key capture) pauses instead of fighting the user.
                if UserInputService:GetFocusedTextBox() or StateStore:GetTransient("IsBindingKey") then
                    if self._state ~= "Paused" then self._state = "Paused"; publish() end
                    task.wait(0.1)
                    continue
                end
                if self._state ~= "Running" then self._state = "Running"; publish() end

                local tools = self:GetValidWeapons()
                if #tools == 0 then
                    self:Stop("no weapons")
                    break
                end

                self:SwitchToNextTool(tools)
                publish()

                local delayTime = math.clamp(
                    tonumber(StateStore:Get("Game.FakeMacroDelay")) or 0.06, 0.03, 0.5)
                task.wait(delayTime)
            end
        end)
        publish()
        return true, "Macro running"
    end

    function MacroService:Stop(reason: string?)
        self._running = false
        self._state = if reason then "Cancelled" else "Idle"
        self._stopReason = reason
        if self._thread and self._thread ~= coroutine.running() and coroutine.status(self._thread) ~= "dead" then
            task.cancel(self._thread)
        end
        self._thread = nil
        if StateStore:Peek("Game.FakeMacro") == true then StateStore:Set("Game.FakeMacro", false) end
        publish()
    end

    function MacroService:Toggle(): (boolean, string)
        if self._running then
            self:Stop("toggled off")
            return true, "Macro stopped"
        end
        return self:Start()
    end

    function MacroService:Initialize()
        -- The UI toggle drives the same start/stop path as the hotkey.
        scope:Add(StateStore:Observe("Game.FakeMacro", function(enabled: any)
            if enabled == true and not self._running then
                self:Start()
            elseif enabled ~= true and self._running then
                self:Stop("disabled")
            end
        end))

        -- Hold mode runs only while the key is down; Toggle mode flips on each press.
        scope:Add(scope:Connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
            if processed or UserInputService:GetFocusedTextBox() or StateStore:GetTransient("IsBindingKey") then return end
            if not Environment:MatchesInput(input, StateStore:Get("Game.FakeMacroKey")) then return end
            if StateStore:Get("Game.FakeMacroMode") == "Hold" then
                self:Start()
            else
                self:Toggle()
            end
        end))
        scope:Add(scope:Connect(UserInputService.InputEnded, function(input: InputObject)
            if not Environment:MatchesInput(input, StateStore:Get("Game.FakeMacroKey")) then return end
            if StateStore:Get("Game.FakeMacroMode") == "Hold" and self._running then
                self:Stop("key released")
            end
        end))

        -- Death always stops the rotation; respawn restarts only when asked to keep automations.
        scope:Add(PlayerTracker:OnLocalCharacterRespawn(function()
            if self._running then self:Stop("respawned") end
            if StateStore:Get("Game.StopAutomationOnRespawn") ~= true
                and StateStore:Get("Game.FakeMacro") == true then
                task.wait(0.5)
                if not scope:IsDisposed() and not self._running and StateStore:Get("Game.FakeMacro") == true then
                    self:Start()
                end
            end
        end))

        -- A profile load can flip the toggle; make sure the thread follows the stored value.
        if StateStore:Get("Game.FakeMacro") == true then self:Start() end
    end

    function MacroService:Destroy()
        self:Stop("plugin destroyed")
        scope:Dispose()
    end

    return MacroService
end
