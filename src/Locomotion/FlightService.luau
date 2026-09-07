--!nonstrict
return function(services: any): any
    local state, tracker, scheduler = services:Get("StateStore"), services:Get("PlayerTracker"), services:Get("TaskScheduler")
    local environment = services:Get("Environment")
    local scope = services:Get("Disposer"):CreateChild("FlightService")
    local input, workspace = game:GetService("UserInputService"), game:GetService("Workspace")
    local FlightService = { _flightScope = nil, _root = nil, _velocity = nil, _gyro = nil, _active = false, _initialized = false }

    function FlightService:Stop()
        local owner = self._flightScope
        self._flightScope, self._root, self._velocity, self._gyro, self._active = nil, nil, nil, nil, false
        if owner then owner:Dispose() end
    end
    function FlightService:Start(): (boolean, string)
        if scope:IsDisposed() or not state:Get("Movement.FlyEnabled") then return false, "Flight is disabled" end
        local assets = tracker:GetLocalAssets()
        local camera = workspace.CurrentCamera
        if not assets or assets.Humanoid.Health <= 0 or not camera then return false, "Character is not ready" end
        if self._active and self._root == assets.RootPart then return true, "Already flying" end
        self:Stop()
        -- Disposed bags intentionally reject Add. Each cycle gets a new bag, including after a respawn.
        local owner = scope:CreateChild("Flight cycle")
        self._flightScope = owner
        local ok, message = pcall(function()
            local root, humanoid = assets.RootPart, assets.Humanoid
            owner:SetProperty(root, "AssemblyLinearVelocity", Vector3.zero, true)
            owner:SetProperty(root, "AssemblyAngularVelocity", Vector3.zero, true)
            owner:SetProperty(humanoid, "PlatformStand", true)
            owner:SetProperty(humanoid, "AutoRotate", false)
            local attachment = Instance.new("Attachment"); owner:Add(attachment)
            attachment.Name, attachment.Parent = "B0XazFlightAttachment", root
            local velocity = Instance.new("LinearVelocity"); owner:Add(velocity)
            velocity.Name, velocity.Attachment0 = "B0XazFlightVelocity", attachment
            velocity.RelativeTo, velocity.MaxForce, velocity.VectorVelocity = Enum.ActuatorRelativeTo.World, math.huge, Vector3.zero
            velocity.Parent = root
            local gyro = Instance.new("BodyGyro"); owner:Add(gyro)
            -- Strong proportional control with damping follows the camera without a free-spinning assembly.
            gyro.Name, gyro.P, gyro.D = "B0XazFlightGyro", 90000, 900
            gyro.MaxTorque, gyro.CFrame, gyro.Parent = Vector3.new(math.huge, math.huge, math.huge), camera.CFrame, root
            self._root, self._velocity, self._gyro, self._active = root, velocity, gyro, true
        end)
        if not ok then
            self:Stop(); state:Set("Movement.FlyEnabled", false)
            services:Get("EventBus"):Publish("Notify", "Flight unavailable", tostring(message))
            return false, tostring(message)
        end
        return true, "Flight started"
    end
    function FlightService:IsFlying(): boolean return self._active end
    function FlightService:Initialize()
        if self._initialized then return end
        self._initialized = true
        local job = scheduler:RegisterHeartbeat("Movement.Flight", 20, function(_dt: number)
            if not state:Peek("Movement.FlyEnabled") then FlightService:Stop(); return end
            local assets, camera = tracker:GetLocalAssets(), workspace.CurrentCamera
            if not assets or assets.Humanoid.Health <= 0 or not camera then FlightService:Stop(); return end
            if not FlightService._active or FlightService._root ~= assets.RootPart or not FlightService._velocity or not FlightService._velocity.Parent then
                FlightService:Start()
            end
            if not FlightService._active then return end
            local direction = Vector3.zero
            if not input:GetFocusedTextBox() and not state:GetTransient("IsBindingKey") then
                if environment:IsMobile() then
                    direction = assets.Humanoid.MoveDirection
                    if state:Get("Movement.MobileFlyUp") then direction += Vector3.yAxis end
                    if state:Get("Movement.MobileFlyDown") then direction -= Vector3.yAxis end
                else
                    if input:IsKeyDown(Enum.KeyCode.W) then direction += camera.CFrame.LookVector end
                    if input:IsKeyDown(Enum.KeyCode.S) then direction -= camera.CFrame.LookVector end
                    if input:IsKeyDown(Enum.KeyCode.D) then direction += camera.CFrame.RightVector end
                    if input:IsKeyDown(Enum.KeyCode.A) then direction -= camera.CFrame.RightVector end
                    if input:IsKeyDown(Enum.KeyCode.Space) then direction += Vector3.yAxis end
                    if input:IsKeyDown(Enum.KeyCode.LeftShift) then direction -= Vector3.yAxis end
                end
            end
            if direction.Magnitude > 1 then direction = direction.Unit end
            FlightService._velocity.VectorVelocity = direction * math.clamp(state:Get("Movement.FlySpeed"), 1, 300)
            FlightService._gyro.CFrame = camera.CFrame
            FlightService._flightScope:SetProperty(assets.Humanoid, "PlatformStand", true)
            FlightService._flightScope:SetProperty(assets.Humanoid, "AutoRotate", false)
            state:SetTransient("AntiFlingSuppressUntil", math.max(state:GetTransient("AntiFlingSuppressUntil") or 0, os.clock() + 0.5))
        end)
        local function syncFlight(value: boolean)
            job.Enabled = value == true
            if not value then FlightService:Stop() end
        end
        scope:Add(state:Observe("Movement.FlyEnabled", syncFlight))
        syncFlight(state:Peek("Movement.FlyEnabled") == true)
        scope:Add(tracker:OnLocalCharacterRespawn(function() FlightService:Stop() end))
    end
    function FlightService:Destroy() scope:Dispose() end
    scope:Add(function() FlightService:Stop() end)
    return FlightService
end
