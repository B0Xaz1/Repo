--!strict
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CONFIG = table.freeze({
    SPEED_MIN = 1,
    SPEED_MAX = 300,
    MOUSE_SENSITIVITY = 0.003,
    PITCH_LIMIT = math.rad(89),
})

return function(services: any): any
    local state, scheduler = services:Get("StateStore"), services:Get("TaskScheduler")
    local scope = services:Get("Disposer"):CreateChild("FreecamService")
    local cameraChanges = scope:CreateChild("Freecam camera")
    local FreecamService = { _active = false, _yaw = 0, _pitch = 0, _position = Vector3.zero, _initialized = false }

    function FreecamService:Stop()
        self._active = false
        cameraChanges:RestoreProperties()
    end

    function FreecamService:Start(): (boolean, string)
        local camera = Workspace.CurrentCamera
        if not camera then return false, "Camera is not ready" end
        if self._active then return true, "Freecam already active" end
        local x, y, _z = camera.CFrame:ToOrientation()
        self._yaw, self._pitch, self._position = y, math.clamp(x, -CONFIG.PITCH_LIMIT, CONFIG.PITCH_LIMIT), camera.CFrame.Position
        cameraChanges:SetProperty(camera, "CameraType", Enum.CameraType.Scriptable)
        self._active = true
        return true, "Freecam enabled"
    end

    function FreecamService:Initialize()
        if self._initialized then return end
        self._initialized = true
        local job = scheduler:RegisterRender("Movement.Freecam", 5, function(dt: number)
            if not state:Peek("Movement.FreecamEnabled") then FreecamService:Stop(); return end
            local camera = Workspace.CurrentCamera
            if not camera then FreecamService:Stop(); return end
            if not self._active then self:Start() end
            if not self._active then return end
            local delta = UIS:GetMouseDelta()
            self._yaw -= delta.X * CONFIG.MOUSE_SENSITIVITY
            self._pitch = math.clamp(self._pitch - delta.Y * CONFIG.MOUSE_SENSITIVITY, -CONFIG.PITCH_LIMIT, CONFIG.PITCH_LIMIT)
            local rotation = CFrame.fromOrientation(self._pitch, self._yaw, 0)
            local direction = Vector3.zero
            if not UIS:GetFocusedTextBox() and not state:GetTransient("IsBindingKey") then
                if UIS:IsKeyDown(Enum.KeyCode.W) then direction += rotation.LookVector end
                if UIS:IsKeyDown(Enum.KeyCode.S) then direction -= rotation.LookVector end
                if UIS:IsKeyDown(Enum.KeyCode.D) then direction += rotation.RightVector end
                if UIS:IsKeyDown(Enum.KeyCode.A) then direction -= rotation.RightVector end
                if UIS:IsKeyDown(Enum.KeyCode.Space) then direction += Vector3.yAxis end
                if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then direction -= Vector3.yAxis end
            end
            if direction.Magnitude > 1 then direction = direction.Unit end
            self._position += direction * math.clamp(state:Peek("Movement.FreecamSpeed"), CONFIG.SPEED_MIN, CONFIG.SPEED_MAX) * math.min(dt, 0.1)
            camera.CFrame = CFrame.new(self._position) * rotation
        end)
        local function sync(value: boolean) job.Enabled = value == true; if not value then self:Stop() end end
        scope:Add(state:Observe("Movement.FreecamEnabled", sync)); sync(state:Peek("Movement.FreecamEnabled") == true)
        scope:Add(function() self:Stop() end)
    end

    function FreecamService:Destroy() scope:Dispose() end
    return FreecamService
end