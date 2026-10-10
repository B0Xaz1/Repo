-- Run with: python3 tests/run_da_hood.py /path/to/luau
-- The runner injects the service source: the Luau CLI isolates globals in require() modules.
local function signal()
    local listeners = {}
    local event = {}
    function event:Connect(callback)
        table.insert(listeners, callback)
        return { Disconnect = function() end }
    end
    function event:Fire(...)
        for _, callback in ipairs(listeners) do callback(...) end
    end
    return event
end

local vectorMethods = {}
local vectorMt = {
    __index = function(value, key)
        if key == "Magnitude" then return math.sqrt(value.X ^ 2 + value.Y ^ 2 + value.Z ^ 2) end
        if key == "Unit" then return value / value.Magnitude end
        return vectorMethods[key]
    end,
    __add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
    __sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
    __mul = function(a, b)
        if type(a) == "number" then return Vector3.new(a * b.X, a * b.Y, a * b.Z) end
        return Vector3.new(a.X * b, a.Y * b, a.Z * b)
    end,
    __div = function(a, b) return Vector3.new(a.X / b, a.Y / b, a.Z / b) end,
}
Vector3 = { new = function(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, vectorMt) end }
function vectorMethods:Lerp(other, alpha) return self + (other - self) * alpha end
function vectorMethods:Dot(other) return self.X * other.X + self.Y * other.Y + self.Z * other.Z end
local function same(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
local frameMt = {}
function frameMt.__index(frame, key)
    if key == "LookVector" then return Vector3.new(-math.sin(frame.Yaw), 0, -math.cos(frame.Yaw)) end
    return nil
end
function frameMt.__mul(frame, angles)
    return setmetatable({ Position = frame.Position, Yaw = angles.Yaw }, frameMt)
end
CFrame = {
    new = function(position) return setmetatable({ Position = position, Yaw = 0 }, frameMt) end,
    Angles = function(_x, y, _z) return { Yaw = y } end,
}

local keyCode = { Name = "KeyCode" }
local inputType = { Name = "UserInputType" }
local function item(group, name) return { EnumType = group, Name = name, __enum = true } end
Enum = {
    KeyCode = keyCode, UserInputType = inputType,
    RaycastFilterType = { Exclude = "Exclude" },
    Material = { Air = "Air", Concrete = "Concrete" },
    HumanoidStateType = { Running = "Running", Jumping = "Jumping", Freefall = "Freefall", Flying = "Flying", Swimming = "Swimming" },
}
keyCode.Unknown, keyCode.V, keyCode.B, keyCode.S = item(keyCode, "Unknown"), item(keyCode, "V"), item(keyCode, "B"), item(keyCode, "S")
inputType.MouseButton1, inputType.MouseButton2, inputType.MouseButton3 =
    item(inputType, "MouseButton1"), item(inputType, "MouseButton2"), item(inputType, "MouseButton3")
local oldTypeof = typeof
typeof = function(value)
    if type(value) == "table" and value.__enum then return "EnumItem" end
    return oldTypeof(value)
end
RaycastParams = { new = function() return {} end }

local player = { CharacterRemoving = signal() }
local keysDown = {}
local input = { InputBegan = signal(), InputEnded = signal(), WindowFocusReleased = signal(), Focused = false }
function input:GetFocusedTextBox() return if self.Focused then {} else nil end
function input:IsKeyDown(key) return keysDown[key] == true end
function input:IsMouseButtonPressed(key) return keysDown[key] == true end
local groundHit = { Normal = Vector3.new(0, 1, 0) }
local camera = { CFrame = { LookVector = Vector3.new(1, 0, 0) } }
local world = { CurrentCamera = camera, Raycast = function(_self, _from, _direction, params)
    assert(params.FilterDescendantsInstances and params.FilterDescendantsInstances[1], "ray must exclude own character")
    return groundHit
end }
game = { GetService = function(_self, name)
    if name == "Players" then return { LocalPlayer = player } end
    if name == "UserInputService" then return input end
    if name == "Workspace" then return world end
    error("unexpected service " .. name)
end }

local makeMacro = __SERVICE__
local humanoid = {
    WalkSpeed = 18, AutoRotate = true, Health = 100, FloorMaterial = Enum.Material.Concrete, HipHeight = 2,
    MoveDirection = Vector3.new(-1, 0, 0), Sit = false, PlatformStand = false, MotionState = Enum.HumanoidStateType.Running,
}
function humanoid:GetState() return self.MotionState end
local root = { AssemblyLinearVelocity = Vector3.new(0, 7, 0), Position = Vector3.new(0, 4, 0), Size = Vector3.new(2, 2, 1) }
root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.pi / 2, 0) -- initially facing backward
local assets = { Humanoid = humanoid, RootPart = root, Character = {} }
local values = { ["Game.DaHoodMacroEnabled"] = true, ["Game.DaHoodMacroKey"] = Enum.KeyCode.V, ["Game.DaHoodMacroMode"] = "Hold", ["Game.DaHoodMacroSpeed"] = 85 }
local observations = {}
local state = {}
function state:Peek(path) return values[path] end
function state:GetTransient(_path) return nil end
function state:Observe(path, callback)
    observations[path] = callback
    return { Disconnect = function() end }
end
function state:Set(path, value)
    values[path] = value
    if observations[path] then observations[path](value) end
end
local disposed = false
local function scope()
    local result = {}
    function result:CreateChild() return scope() end
    function result:ConnectImmediate(event, callback) event:Connect(callback) end
    function result:Add(value) return value end
    function result:SetProperty(object, property, value)
        self.originals = self.originals or {}
        if not self.originals[object] then self.originals[object] = {} end
        if self.originals[object][property] == nil then self.originals[object][property] = object[property] end
        object[property] = value
    end
    function result:RestoreProperties()
        for object, properties in pairs(self.originals or {}) do
            for property, original in pairs(properties) do object[property] = original end
        end
        self.originals = nil
    end
    function result:Dispose() self:RestoreProperties(); disposed = true end
    return result
end
local job, facingJob
local services = { Get = function(_self, name)
    if name == "StateStore" then return state end
    if name == "PlayerTracker" then return { GetLocalAssets = function() return assets end } end
    if name == "Disposer" then return scope() end
    if name == "TaskScheduler" then return {
        RegisterHeartbeat = function(_self, _name, priority, callback)
            assert(priority > 10, "macro must run after universal movement")
            job = callback
            return { Disconnect = function() end }
        end,
        RegisterCamera = function(_self, _name, _priority, callback)
            facingJob = callback
            return { Disconnect = function() end }
        end,
    } end
    error("unexpected dependency " .. name)
end }
local macro = makeMacro(services, { Macro = { DefaultSpeed = 180, MinSpeed = 16, MaxSpeed = 400 } })
macro:Initialize()
local function press(key, processed)
    keysDown[key] = true
    input.InputBegan:Fire({ KeyCode = if key.EnumType == keyCode then key else Enum.KeyCode.Unknown,
        UserInputType = if key.EnumType == inputType then key else nil }, processed or false)
end
local function release(key)
    keysDown[key] = false
    input.InputEnded:Fire({ KeyCode = if key.EnumType == keyCode then key else Enum.KeyCode.Unknown,
        UserInputType = if key.EnumType == inputType then key else nil })
end

-- Native S movement is backward (-X); the macro should reverse it into camera-forward (+X).
root.AssemblyLinearVelocity = Vector3.new(-18, 7, 0)
local start = root.AssemblyLinearVelocity
press(Enum.KeyCode.V, true)
assert(same(root.AssemblyLinearVelocity, start), "processed input must be ignored")
release(Enum.KeyCode.V)
press(Enum.KeyCode.V)
job(1 / 60)
assert(same(root.AssemblyLinearVelocity, start), "holding V alone must never boost")
facingJob(1 / 60)
assert(humanoid.AutoRotate == true, "V alone must not change facing")
press(Enum.KeyCode.S)
job(1 / 60)
for _ = 1, 12 do facingJob(1 / 60) end
assert(humanoid.AutoRotate == false and root.CFrame.LookVector:Dot(camera.CFrame.LookVector) > 0.95,
    "V + S should turn the player to face camera-forward travel")
assert(root.AssemblyLinearVelocity.X > 0 and root.AssemblyLinearVelocity.X < 85, "V + S must move camera-forward, not S-backward")
assert(humanoid.WalkSpeed == 18 and root.AssemblyLinearVelocity.Y == 7, "never change WalkSpeed or vertical velocity")
local whileMoving = root.AssemblyLinearVelocity
release(Enum.KeyCode.S)
facingJob(1 / 60)
job(1 / 60)
assert(humanoid.AutoRotate == true, "releasing S should restore the usual rotation")
assert(same(root.AssemblyLinearVelocity, whileMoving), "letting go of S stops pushing without cancelling V")
press(Enum.KeyCode.S)
-- Forward follows horizontal camera look even when the camera is pitched or turned.
camera.CFrame.LookVector = Vector3.new(0, 0.8, 0.6)
humanoid.MoveDirection = Vector3.new(0, 0, -1)
root.AssemblyLinearVelocity = Vector3.new(0, 7, -18)
job(1 / 60)
assert(root.AssemblyLinearVelocity.Z > 0 and root.AssemblyLinearVelocity.Y == 7,
    "pitched camera must still push along horizontal camera-forward")
camera.CFrame.LookVector = Vector3.new(1, 0, 0)
humanoid.MoveDirection = Vector3.new(-1, 0, 0)
root.AssemblyLinearVelocity = Vector3.new(0, 7, 0)
state:Set("Game.DaHoodMacroSpeed", 120)
for _ = 1, 90 do job(1 / 60) end
assert(math.abs(root.AssemblyLinearVelocity.X - 120) < 0.001, "slider caps sustained ground speed")

-- Changing direction should curve through momentum rather than instantly snapping to the input.
root.AssemblyLinearVelocity = Vector3.new(80, 7, 0)
humanoid.MoveDirection = Vector3.new(0, 0, 1)
job(1 / 60)
assert(root.AssemblyLinearVelocity.X > 70 and root.AssemblyLinearVelocity.Z > 0
    and root.AssemblyLinearVelocity.Z < 10, "sideways input adds a small lateral push without deleting forward slide")
camera.CFrame.LookVector = Vector3.new(-1, 0, 0)
humanoid.MoveDirection = Vector3.new(1, 0, 0)
job(1 / 60)
assert(root.AssemblyLinearVelocity.X > 0, "turning camera around bleeds momentum instead of snapping backward")
camera.CFrame.LookVector = Vector3.new(1, 0, 0)
humanoid.MoveDirection = Vector3.new(-1, 0, 0)

-- Airborne: preserve every velocity component across repeated frames, even after releasing.
root.AssemblyLinearVelocity = Vector3.new(48, 23, -9)
humanoid.FloorMaterial = Enum.Material.Air
local airFacing = root.CFrame.LookVector
camera.CFrame.LookVector = Vector3.new(0, 0, -1)
facingJob(1 / 60)
job(0.1)
job(0.1)
assert(same(root.CFrame.LookVector, airFacing), "facing should not be forced while airborne")
assert(same(root.AssemblyLinearVelocity, Vector3.new(48, 23, -9)), "no writes while airborne")
camera.CFrame.LookVector = Vector3.new(1, 0, 0)
release(Enum.KeyCode.V)
assert(same(root.AssemblyLinearVelocity, Vector3.new(48, 23, -9)), "release does not erase airborne momentum")
press(Enum.KeyCode.V)
job(0.1)
assert(same(root.AssemblyLinearVelocity, Vector3.new(48, 23, -9)), "press in air must not boost")
humanoid.FloorMaterial = Enum.Material.Concrete
job(0.1)
assert(root.AssemblyLinearVelocity.X > 48 and root.AssemblyLinearVelocity.Y == 23, "boost resumes on landing")

root.AssemblyLinearVelocity = Vector3.new(0, 5, 0)
humanoid.MotionState = Enum.HumanoidStateType.Jumping
job(0.1)
assert(same(root.AssemblyLinearVelocity, Vector3.new(0, 5, 0)), "jump state must not boost on stale floor data")
humanoid.MotionState = Enum.HumanoidStateType.Running
groundHit = nil
job(0.1)
assert(same(root.AssemblyLinearVelocity, Vector3.new(0, 5, 0)), "missing ground hit must not boost")
groundHit = { Normal = Vector3.new(0, 0.75, 0) }
job(0.1)
assert(same(root.AssemblyLinearVelocity, Vector3.new(0, 5, 0)), "steep slope must not boost")
groundHit = { Normal = Vector3.new(0, 0.87, 0) }
job(0.1)
local inclineGain = root.AssemblyLinearVelocity.X
assert(inclineGain > 0 and inclineGain < 70, "incline boost must be weaker than flat boost")
groundHit = { Normal = Vector3.new(0, 1, 0) }
root.AssemblyLinearVelocity = Vector3.new(0, 5, 0)
job(0.1)
assert(root.AssemblyLinearVelocity.X > inclineGain, "flat ground boosts more than an incline")
local moving = root.AssemblyLinearVelocity
humanoid.MoveDirection = Vector3.new(0, 0, 0)
job(0.1)
assert(root.AssemblyLinearVelocity.X > moving.X, "S should still push forward if MoveDirection is stale")
humanoid.MoveDirection = Vector3.new(-1, 0, 0)

input.WindowFocusReleased:Fire()
local afterFocus = root.AssemblyLinearVelocity
job(1)
assert(same(root.AssemblyLinearVelocity, afterFocus), "focus loss must stop without resetting momentum")
release(Enum.KeyCode.V)
press(Enum.KeyCode.V)
state:Set("Game.DaHoodMacroEnabled", false)
local afterDisable = root.AssemblyLinearVelocity
job(1)
assert(same(root.AssemblyLinearVelocity, afterDisable), "disabling must stop without resetting momentum")
release(Enum.KeyCode.V)
state:Set("Game.DaHoodMacroEnabled", true)
state:Set("Game.DaHoodMacroKey", Enum.KeyCode.B)
local beforeOldKey = root.AssemblyLinearVelocity
press(Enum.KeyCode.V)
assert(same(root.AssemblyLinearVelocity, beforeOldKey), "old bind must not activate")
release(Enum.KeyCode.V)
press(Enum.KeyCode.B)
player.CharacterRemoving:Fire()
local afterRespawn = root.AssemblyLinearVelocity
job(1)
assert(same(root.AssemblyLinearVelocity, afterRespawn), "respawn must stop")
release(Enum.KeyCode.B)
state:Set("Game.DaHoodMacroKey", Enum.UserInputType.MouseButton2)
root.AssemblyLinearVelocity = Vector3.new(0, 5, 0)
press(Enum.UserInputType.MouseButton2)
assert(root.AssemblyLinearVelocity.X > 0, "mouse bind must work")
keysDown[Enum.UserInputType.MouseButton2] = false
local beforeMissedRelease = root.AssemblyLinearVelocity
job(1)
assert(same(root.AssemblyLinearVelocity, beforeMissedRelease), "missed release must stop on heartbeat")
press(Enum.UserInputType.MouseButton2)
state:Set("Game.DaHoodMacroKey", Enum.KeyCode.Unknown)
local afterUnbind = root.AssemblyLinearVelocity
job(1)
assert(same(root.AssemblyLinearVelocity, afterUnbind), "rebinding during a hold must stop")
release(Enum.UserInputType.MouseButton2)
press(Enum.KeyCode.Unknown)
assert(same(root.AssemblyLinearVelocity, afterUnbind), "unbound key must not activate")
release(Enum.KeyCode.Unknown)
state:Set("Game.DaHoodMacroKey", Enum.KeyCode.V)
input.Focused = true
press(Enum.KeyCode.V)
assert(same(root.AssemblyLinearVelocity, afterUnbind), "typing must not activate")
release(Enum.KeyCode.V)
input.Focused = false
state:Set("Game.DaHoodMacroSpeed", 500)
root.AssemblyLinearVelocity = Vector3.new(0, 5, 0)
press(Enum.KeyCode.V)
for _ = 1, 90 do job(1 / 60) end
assert(math.abs(root.AssemblyLinearVelocity.X - 400) < 0.001, "speed must stay inside slider bounds")
local nextRoot = { AssemblyLinearVelocity = Vector3.new(9, 12, 0) }
assets = { Humanoid = humanoid, RootPart = nextRoot, Character = {} }
job(1)
assert(same(nextRoot.AssemblyLinearVelocity, Vector3.new(9, 12, 0)), "hold must not transfer to a new character")
release(Enum.KeyCode.V)
assets = { Humanoid = humanoid, RootPart = root, Character = {} }

-- Toggle mode arms on one V press, still requires S, and disarms on the next V press.
release(Enum.KeyCode.S)
state:Set("Game.DaHoodMacroMode", "Toggle")
root.AssemblyLinearVelocity = Vector3.new(0, 5, 0)
press(Enum.KeyCode.V)
release(Enum.KeyCode.V)
job(1 / 60)
assert(same(root.AssemblyLinearVelocity, Vector3.new(0, 5, 0)), "toggle armed without S must not boost")
press(Enum.KeyCode.S)
job(1 / 60)
assert(root.AssemblyLinearVelocity.X > 0, "toggle stays armed after releasing V and works with S")
local toggledSpeed = root.AssemblyLinearVelocity
release(Enum.KeyCode.S)
job(1 / 60)
assert(same(root.AssemblyLinearVelocity, toggledSpeed), "toggle mode stops adding velocity when S is released")
press(Enum.KeyCode.V)
release(Enum.KeyCode.V)
press(Enum.KeyCode.S)
job(1 / 60)
assert(same(root.AssemblyLinearVelocity, toggledSpeed), "second V press disarms toggle mode")
release(Enum.KeyCode.S)

-- Changing mode while armed must clear activation, not let the old hold linger.
press(Enum.KeyCode.V)
release(Enum.KeyCode.V)
state:Set("Game.DaHoodMacroMode", "Hold")
press(Enum.KeyCode.S)
local beforeModeChange = root.AssemblyLinearVelocity
job(1 / 60)
assert(same(root.AssemblyLinearVelocity, beforeModeChange), "mode change clears the old toggle")
release(Enum.KeyCode.S)
state:Set("Game.DaHoodMacroKey", Enum.KeyCode.S)
press(Enum.KeyCode.S)
job(1 / 60)
assert(same(root.AssemblyLinearVelocity, beforeModeChange), "S alone cannot be an activation bind")
release(Enum.KeyCode.S)
state:Set("Game.DaHoodMacroKey", Enum.KeyCode.V)
press(Enum.KeyCode.S)
press(Enum.KeyCode.V)
job(1 / 60)
facingJob(1 / 60)
assert(root.AssemblyLinearVelocity.X > beforeModeChange.X, "S then V also works in hold mode")
assert(humanoid.AutoRotate == false, "active macro owns the facing rotation")
local beforeDestroy = root.AssemblyLinearVelocity
macro:Destroy()
assert(disposed and same(root.AssemblyLinearVelocity, beforeDestroy), "destroy must leave momentum intact")
assert(humanoid.AutoRotate == true, "destroy must restore AutoRotate")
print("Da Hood V + S hold/toggle scenarios passed")
