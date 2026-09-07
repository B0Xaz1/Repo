--!nonstrict
return function(services: any): any
    local state, environment, filter = services:Get("StateStore"), services:Get("Environment"), services:Get("TargetFilter")
    local scheduler = services:Get("TaskScheduler")
    local scope = services:Get("Disposer"):CreateChild("TriggerbotService")
    local workspace, input = game:GetService("Workspace"), game:GetService("UserInputService")
    local TriggerbotService = { _candidate = nil, _elapsed = 0, _sinceShot = 0, _initialized = false }
    function TriggerbotService:Initialize()
        if self._initialized then return end
        self._initialized = true
        local job = scheduler:RegisterPreSim("Combat.Triggerbot", 20, function(dt: number)
            local config = state:Peek("Aimbot.Triggerbot")
            if not config.Enabled or input:GetFocusedTextBox() or state:GetTransient("IsBindingKey") then
                TriggerbotService._candidate, TriggerbotService._elapsed = nil, 0; return
            end
            local camera = workspace.CurrentCamera
            if not camera then return end
            local point = environment:GetAimPoint(camera)
            local ray = camera:ViewportPointToRay(point.X, point.Y)
            local hit = filter:Raycast(ray.Origin, ray.Direction * math.clamp(config.MaxDistance, 1, 100000))
            local player = hit and filter:GetPlayerFromPart(hit.Instance)
            if not player or not hit or not hit.Instance:IsA("BasePart") or not filter:ValidateTarget(player, hit.Instance, config) then
                TriggerbotService._candidate, TriggerbotService._elapsed = nil, 0; return
            end
            if TriggerbotService._candidate ~= player then TriggerbotService._candidate, TriggerbotService._elapsed = player, 0 end
            TriggerbotService._elapsed += dt
            TriggerbotService._sinceShot += dt
            local delay = math.clamp(config.Delay, 0, 5)
            -- A small rate floor avoids saturating the virtual-input fallback when delay is explicitly zero.
            if TriggerbotService._elapsed < delay or TriggerbotService._sinceShot < math.max(0.04, delay) then return end
            TriggerbotService._sinceShot = 0
            if not environment:MouseClick() then
                state:Set("Aimbot.Triggerbot.Enabled", false)
                services:Get("EventBus"):Publish("Notify", "Triggerbot unavailable", "Neither native click nor virtual input succeeded on this executor")
            end
        end)
        job.Enabled = state:Peek("Aimbot.Triggerbot.Enabled") == true
        scope:Add(state:Observe("Aimbot.Triggerbot.Enabled", function(value: boolean) job.Enabled = value == true end))
    end
    function TriggerbotService:Destroy() scope:Dispose() end
    return TriggerbotService
end
