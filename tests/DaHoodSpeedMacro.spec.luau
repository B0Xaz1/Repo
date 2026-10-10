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
local function same(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end

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
local world = { Raycast = function(_self, _from, _direction, params)
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
    WalkSpeed = 18, Health = 100, FloorMaterial = Enum.Material.Concrete, HipHeight = 2,
    MoveDirection = Vector3.new(1, 0, 0), Sit = false, PlatformStand = false, MotionState = Enum.HumanoidStateType.Running,
}
function humanoid:GetState() return self.MotionState end
local root = { AssemblyLinearVelocity = Vector3.new(0, 7, 0), Position = Vector3.new(0, 4, 0), Size = Vector3.new(2, 2, 1) }
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
    function result:Dispose() disposed = true end
    return result
end
local job
local services = { Get = function(_self, name)
    if name == "StateStore" then return state end
    if name == "PlayerTracker" then return { GetLocalAssets = function() return assets end } end
    if name == "Disposer" then return scope() end
    if name == "TaskScheduler" then return { RegisterHeartbeat = function(_self, _name, priority, callback)
        assert(priority > 10, "macro must run after universal movement")
        job = callback
        return { Disconnect = function() end }
    end } end
    error("unexpected dependency " .. name)
end }
local macro = makeMacro(services, { Macro = { DefaultSpeed = 100, MinSpeed = 16, MaxSpeed = 200 } })
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

local start = root.AssemblyLinearVelocity
press(Enum.KeyCode.V, true)
assert(same(root.AssemblyLinearVelocity, start), "processed input must be ignored")
release(Enum.KeyCode.V)
press(Enum.KeyCode.V)
job(1 / 60)
assert(same(root.AssemblyLinearVelocity, start), "holding V alone must never boost")
press(Enum.KeyCode.S)
job(1 / 60)
assert(root.AssemblyLinearVelocity.X > 0 and root.AssemblyLinearVelocity.X < 85, "V then S accelerates on ground")
assert(humanoid.WalkSpeed == 18 and root.AssemblyLinearVelocity.Y == 7, "never change WalkSpeed or vertical velocity")
local whileMoving = root.AssemblyLinearVelocity
release(Enum.KeyCode.S)
job(1 / 60)
assert(same(root.AssemblyLinearVelocity, whileMoving), "letting go of S stops pushing without cancelling V")
press(Enum.KeyCode.S)
state:Set("Game.DaHoodMacroSpeed", 120)
for _ = 1, 90 do job(1 / 60) end
assert(math.abs(root.AssemblyLinearVelocity.X - 120) < 0.001, "slider caps sustained ground speed")

-- Changing direction should curve through momentum rather than instantly snapping to the input.
root.AssemblyLinearVelocity = Vector3.new(80, 7, 0)
humanoid.MoveDirection = Vector3.new(0, 0, 1)
job(1 / 60)
assert(root.AssemblyLinearVelocity.X > 70 and root.AssemblyLinearVelocity.Z > 0
    and root.AssemblyLinearVelocity.Z < 10, "sideways input adds a small lateral push without deleting forward slide")
humanoid.MoveDirection = Vector3.new(-1, 0, 0)
job(1 / 60)
assert(root.AssemblyLinearVelocity.X > 0, "reversing first bleeds momentum instead of snapping backward")
humanoid.MoveDirection = Vector3.new(1, 0, 0)

-- Airborne: preserve every velocity component across repeated frames, even after releasing.
root.AssemblyLinearVelocity = Vector3.new(48, 23, -9)
humanoid.FloorMaterial = Enum.Material.Air
job(0.1)
job(0.1)
assert(same(root.AssemblyLinearVelocity, Vector3.new(48, 23, -9)), "no writes while airborne")
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
assert(same(root.AssemblyLinearVelocity, moving), "standing still must not add velocity")
humanoid.MoveDirection = Vector3.new(1, 0, 0)

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
assert(math.abs(root.AssemblyLinearVelocity.X - 200) < 0.001, "speed must stay inside slider bounds")
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
assert(root.AssemblyLinearVelocity.X > beforeModeChange.X, "S then V also works in hold mode")
local beforeDestroy = root.AssemblyLinearVelocity
macro:Destroy()
assert(disposed and same(root.AssemblyLinearVelocity, beforeDestroy), "destroy must leave momentum intact")
print("Da Hood V + S hold/toggle scenarios passed")
