local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")

local CONFIG = table.freeze({
    DELAY_DEFAULT = 0.06,
    DELAY_MIN = 0.03,
    DELAY_MAX = 0.5,
    PAUSE_POLL_INTERVAL = 0.1,
    RESPAWN_RESTART_DELAY = 0.5,
})

return function(services: any, Prison: any?): any
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local Disposer = services:Get("Disposer")
    local PlayerTracker = services:Get("PlayerTracker")
    local Environment = services:Get("Environment")

    local Prison = Prison or {}
    local manifest = Prison.Manifest
    local scope = Disposer:CreateChild(`{manifest.Name}.Macro`)
    local LocalPlayer = Players.LocalPlayer

    local MacroService = {
        _running = false,
        _generation = 0,
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
                if child:IsA("Tool") and Prison.WeaponMods and Prison.WeaponMods:IsGunTool(child) then
                    table.insert(tools, child)
                end
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
            local equippedNext = pcall(function() assets.Humanoid:EquipTool(nextTool) end)
            if not equippedNext then return nil end
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
            Delay = math.clamp(tonumber(StateStore:Get("Game.FakeMacroDelay")) or CONFIG.DELAY_DEFAULT, CONFIG.DELAY_MIN, CONFIG.DELAY_MAX),
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

        if #self:GetValidWeapons() < (manifest.Macro.MinGuns or 2) then
            return false, "Need at least two guns to cycle the macro"
        end

        self._running = true
        self._state = "Running"
        self._stopReason = nil
        StateStore:Set("Game.FakeMacro", true)

        self._generation += 1
        local generation = self._generation
        scope:Spawn(function()
            while self._running and self._generation == generation do
                if not PlayerTracker:IsAlive(Players.LocalPlayer) then
                    self:Stop("died")
                    break
                end

                if UIS:GetFocusedTextBox() or StateStore:GetTransient("IsBindingKey") then
                    if self._state ~= "Paused" then self._state = "Paused"; publish() end
                    task.wait(CONFIG.PAUSE_POLL_INTERVAL)
                    continue
                end
                if self._state ~= "Running" then self._state = "Running"; publish() end

                local tools = self:GetValidWeapons()
                if #tools < (manifest.Macro.MinGuns or 2) then
                    self:Stop("not enough guns")
                    break
                end

                self:SwitchToNextTool(tools)
                publish()

                local delayTime = math.clamp(
                    tonumber(StateStore:Get("Game.FakeMacroDelay")) or CONFIG.DELAY_DEFAULT, CONFIG.DELAY_MIN, CONFIG.DELAY_MAX)
                task.wait(delayTime)
            end
        end)
        publish()
        return true, "Macro running"
    end

    function MacroService:Stop(reason: string?)
        self._running = false
        self._generation += 1
        self._state = if reason then "Cancelled" else "Idle"
        self._stopReason = reason
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

        scope:Add(StateStore:Observe("Game.FakeMacro", function(enabled: any)
            if enabled == true and not self._running then
                self:Start()
            elseif enabled ~= true and self._running then
                self:Stop("disabled")
            end
        end))

        scope:Connect(UIS.InputBegan, function(input: InputObject, processed: boolean)
            if processed or UIS:GetFocusedTextBox() or StateStore:GetTransient("IsBindingKey") then return end
            if not Environment:MatchesInput(input, StateStore:Get("Game.FakeMacroKey")) then return end
            if StateStore:Get("Game.FakeMacroMode") == "Hold" then
                self:Start()
            else
                self:Toggle()
            end
        end)
        scope:Connect(UIS.InputEnded, function(input: InputObject)
            if not Environment:MatchesInput(input, StateStore:Get("Game.FakeMacroKey")) then return end
            if StateStore:Get("Game.FakeMacroMode") == "Hold" and self._running then
                self:Stop("key released")
            end
        end)

        scope:Add(PlayerTracker:OnLocalCharacterRespawn(function()
            if self._running then self:Stop("respawned") end
            if StateStore:Get("Game.StopAutomationOnRespawn") ~= true
                and StateStore:Get("Game.FakeMacro") == true then
                task.wait(CONFIG.RESPAWN_RESTART_DELAY)
                if not scope:IsDisposed() and not self._running and StateStore:Get("Game.FakeMacro") == true then
                    self:Start()
                end
            end
        end))

        if StateStore:Get("Game.FakeMacro") == true then self:Start() end
    end

    function MacroService:Destroy()
        self:Stop("plugin destroyed")
        scope:Dispose()
    end

    return MacroService
end
