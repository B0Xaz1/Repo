local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")

local CONFIG = table.freeze({
    CHECK_INTERVAL = 1 / 60,
    RAY_MAX_DISTANCE = 10000,
    DELAY_MAX = 2,
    MIN_SHOT_INTERVAL = 0.04,
})

return function(services: any): any
    local state, environment, filter = services:Get("StateStore"), services:Get("Environment"), services:Get("TargetFilter")
    local scheduler = services:Get("TaskScheduler")
    local bus = services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("TriggerbotService")
    local TriggerbotService = { _candidate = nil, _elapsed = 0, _sinceShot = 0, _checkElapsed = 0, _initialized = false }

    local function clearCandidate()
        TriggerbotService._candidate, TriggerbotService._elapsed = nil, 0
    end

    function TriggerbotService:Initialize()
        if self._initialized then return end
        self._initialized = true
        local job = scheduler:RegisterPreSim("Combat.Triggerbot", 20, function(dt: number)
            TriggerbotService._checkElapsed += dt
            if TriggerbotService._checkElapsed < CONFIG.CHECK_INTERVAL then return end
            dt, TriggerbotService._checkElapsed = TriggerbotService._checkElapsed, 0
            local config = state:Peek("Aimbot.Triggerbot")
            local focused = UIS:GetFocusedTextBox() ~= nil or state:GetTransient("IsBindingKey")
            if not config.Enabled or focused then
                clearCandidate(); return
            end
            local camera = Workspace.CurrentCamera
            if not camera then return end
            local point = environment:GetAimPoint(camera)
            local ray = camera:ViewportPointToRay(point.X, point.Y)
            local hit = filter:Raycast(ray.Origin, ray.Direction * math.clamp(config.MaxDistance, 50, CONFIG.RAY_MAX_DISTANCE))
            local player = hit and filter:GetPlayerFromPart(hit.Instance)
            if not player or not hit or not hit.Instance:IsA("BasePart") or not filter:ValidateTarget(player, hit.Instance, config) then
                TriggerbotService._candidate, TriggerbotService._elapsed = nil, 0; return
            end
            if TriggerbotService._candidate ~= player then TriggerbotService._candidate, TriggerbotService._elapsed = player, 0 end
            TriggerbotService._elapsed += dt
            TriggerbotService._sinceShot += dt
            -- Two gates: the target has to stay under the crosshair for the delay, and shots stay rate limited
            local delay = math.clamp(config.Delay, 0, CONFIG.DELAY_MAX)
            if TriggerbotService._elapsed < delay or TriggerbotService._sinceShot < math.max(CONFIG.MIN_SHOT_INTERVAL, delay) then return end
            TriggerbotService._sinceShot = 0
            if not environment:MouseClick() then
                state:Set("Aimbot.Triggerbot.Enabled", false)
                bus:Publish("Notify", "Triggerbot unavailable", "Neither native click nor virtual input succeeded on this executor")
            end
        end)
        job.Enabled = state:Peek("Aimbot.Triggerbot.Enabled") == true
        scope:ConnectImmediate(UIS.InputBegan, function(event: InputObject, processed: boolean)
            if processed or UIS:GetFocusedTextBox() or state:GetTransient("IsBindingKey") then return end
            if environment:MatchesInput(event, state:Peek("Aimbot.Triggerbot.Keybind")) then
                state:Set("Aimbot.Triggerbot.Enabled", state:Peek("Aimbot.Triggerbot.Enabled") ~= true)
            end
        end)
        scope:ConnectImmediate(UIS.WindowFocusReleased, function()
            clearCandidate()
        end)
        scope:Add(state:Observe("Aimbot.Triggerbot.Enabled", function(value: boolean)
            job.Enabled = value == true
            if not value then
                clearCandidate()
            end
        end))
    end

    function TriggerbotService:Destroy() scope:Dispose() end
    return TriggerbotService
end
