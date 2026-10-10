-- Run with: python3 tests/run_simulated_input.py /path/to/luau
-- The runner injects both module sources: the Luau CLI isolates globals in require() modules.

-- Signals ---------------------------------------------------------------
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

-- Value types -----------------------------------------------------------
local vectorMethods = {}
local vectorMt = {
    __index = function(value, key)
        if key == "Magnitude" then return math.sqrt(value.X ^ 2 + value.Y ^ 2 + value.Z ^ 2) end
        return vectorMethods[key]
    end,
    __add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
    __sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
    __mul = function(a, b)
        if type(a) == "number" then return Vector3.new(a * b.X, a * b.Y, a * b.Z) end
        if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
    end,
}
Vector3 = { new = function(x, y, z) return setmetatable({ X = x, Y = y, Z = z, __type = "Vector3" }, vectorMt) end }
Vector2 = { new = function(x, y) return setmetatable({ X = x, Y = y, __type = "Vector2" }, {
    __index = function(value, key) if key == "Magnitude" then return math.sqrt(value.X ^ 2 + value.Y ^ 2) end return nil end,
    __sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end,
}) end }
local oldTypeof = typeof
typeof = function(value)
    if type(value) == "table" and value.__type then return value.__type end
    if type(value) == "table" and value.__enum then return "EnumItem" end
    return oldTypeof(value)
end

-- Enums -----------------------------------------------------------------
local keyCode = { Name = "KeyCode" }
local inputType = { Name = "UserInputType" }
local function item(group, name) return { EnumType = group, Name = name, __enum = true } end
function keyCode:GetEnumItems() return { self.Unknown, self.RightShift } end
function inputType:GetEnumItems() return { self.MouseButton1, self.MouseButton2 } end
Enum = { KeyCode = keyCode, UserInputType = inputType }
keyCode.Unknown, keyCode.RightShift = item(keyCode, "Unknown"), item(keyCode, "RightShift")
inputType.MouseButton1, inputType.MouseButton2 = item(inputType, "MouseButton1"), item(inputType, "MouseButton2")

-- Services --------------------------------------------------------------
local requestedServices = {}
local workspace = {}
local characterChildren = {}
local character = { GetChildren = function() return characterChildren end }
local localPlayer = { Name = "Tester", Character = character }
local input = {
    InputBegan = signal(), WindowFocused = signal(), WindowFocusReleased = signal(),
    TouchEnabled = false, KeyboardEnabled = true, FocusedTextBox = nil,
}
function input:GetFocusedTextBox() return self.FocusedTextBox end
function input:GetMouseLocation() return Vector2.new(100, 200) end
function input:IsKeyDown() return false end
function input:IsMouseButtonPressed() return false end
game = { GetService = function(_self, name)
    table.insert(requestedServices, name)
    if name == "Players" then return { LocalPlayer = localPlayer } end
    if name == "UserInputService" then return input end
    if name == "Workspace" then return workspace end
    if name == "GuiService" then return { GetGuiInset = function() return Vector2.new(0, 0) end } end
    if name == "HttpService" then return {} end
    error(`unexpected service {name}`)
end }
getfenv = function() return {} end
local clock = 0
os = { clock = function() return clock end, time = function() return 0 end }

-- Disposer --------------------------------------------------------------
local function scope()
    local result = { _disposed = false }
    function result:CreateChild() return scope() end
    function result:Add(value) return value end
    function result:Connect(event, callback) event:Connect(callback) return { Disconnect = function() end } end
    function result:ConnectImmediate(event, callback) event:Connect(callback) return { Disconnect = function() end } end
    function result:Spawn(callback) callback() end
    function result:Delay(_seconds, callback) callback() end
    function result:SetProperty(object, property, value) object[property] = value end
    function result:RestoreProperties() end
    function result:ReleaseProperties() end
    function result:IsDisposed() return self._disposed end
    function result:Dispose() self._disposed = true end
    return result
end

-- Environment -----------------------------------------------------------
local makeEnvironment = __ENVIRONMENT__
local environment = makeEnvironment(scope())

assert(environment.MouseClick == nil, "the injected click API must be gone")
assert(environment.MouseMove == nil, "the injected cursor-move API must be gone")
assert(environment.Capabilities.MouseMove == nil and environment.Capabilities.NativeClick == nil
    and environment.Capabilities.VirtualInput == nil, "input-injection capabilities must not be advertised")
for _, name in ipairs(requestedServices) do
    assert(name ~= "VirtualInputManager", "the engine's virtual input manager must never be requested")
end
assert(type(environment.ActivateTool) == "function", "simulated activation must be available")

-- A tool that records every simulated activation instead of receiving a real click
local activations = 0
local function makeTool(name: string, parent: any)
    return {
        Name = name, Parent = parent,
        IsA = function(_self, class) return class == "Tool" end,
        Activate = function(_self) activations += 1 end,
    }
end

local gun = makeTool("Revolver", character)
characterChildren = { gun, { Name = "Shirt", IsA = function(_self, class) return class == "Shirt" end } }
assert(environment:GetEquippedTool() == gun, "the equipped tool is the first Tool in the character")

local ok, reason = environment:ActivateTool()
assert(ok and activations == 1, `activation should reach the tool, got {tostring(reason)}`)

ok, reason = environment:ActivateTool(gun)
assert(ok and activations == 2, `an explicit tool should activate, got {tostring(reason)}`)

-- Nothing is simulated while the player is typing, so chat and the menu keep their keys
input.FocusedTextBox = { Text = "typing" }
ok, reason = environment:ActivateTool()
assert(not ok and activations == 2, "a focused text box must block simulated activation")
assert(type(reason) == "string" and reason ~= "", "blocking reports a reason")
input.FocusedTextBox = nil

-- Nothing is simulated while another window owns the desktop
input.WindowFocusReleased:Fire()
ok, reason = environment:ActivateTool()
assert(not ok and activations == 2, "an unfocused window must block simulated activation")
input.WindowFocused:Fire()
ok = environment:ActivateTool()
assert(ok and activations == 3, "focus returns simulated activation")

characterChildren = {}
ok, reason = environment:ActivateTool()
assert(not ok and activations == 3 and reason == "No tool is equipped", "an empty hand reports itself")

local backpackTool = makeTool("Knife", { Name = "Backpack" })
ok, reason = environment:ActivateTool(backpackTool)
assert(not ok and activations == 3 and reason == "That tool is not equipped", "an unequipped tool is refused")

-- Triggerbot --------------------------------------------------------------
local makeTriggerbot = __TRIGGERBOT__
local notices, settings = {}, {
    Enabled = true, Delay = 0, MaxDistance = 500, Keybind = Enum.KeyCode.Unknown,
    TeamCheck = false, FriendCheck = false, WhitelistCheck = false, ForceFieldCheck = false, VisCheck = false,
}
local writes = {}
local state = {}
function state:Peek(path) if path == "Aimbot.Triggerbot" then return settings end return nil end
function state:Get(path) return self:Peek(path) end
function state:GetTransient() return nil end
function state:Set(path, value) table.insert(writes, { Path = path, Value = value }) end
function state:Observe(_path, _callback) return { Disconnect = function() end } end

local bus = {}
function bus:Publish(channel, ...) if channel == "Notify" then table.insert(notices, table.pack(...)) end end

local target = { Name = "Target", UserId = 7 }
local part = { Name = "Head", IsA = function(_self, class) return class == "BasePart" end }
local camera = { ViewportPointToRay = function(_self, _x, _y)
    return { Origin = Vector3.new(0, 0, 0), Direction = Vector3.new(0, 0, -1) }
end }
local filter = {}
function filter:Raycast() return { Instance = part, Position = Vector3.new(0, 0, -10) } end
function filter:GetPlayerFromPart(hitPart) return if hitPart == part then target else nil end
function filter:ValidateTarget(player) return player == target end

local job
local scheduler = {}
function scheduler:RegisterPreSim(_name, _priority, callback)
    job = callback
    return { Enabled = false }
end

local services = { Get = function(_self, name)
    if name == "StateStore" then return state end
    if name == "Environment" then return environment end
    if name == "TargetFilter" then return filter end
    if name == "TaskScheduler" then return scheduler end
    if name == "EventBus" then return bus end
    if name == "Disposer" then return scope() end
    error(`unexpected dependency {name}`)
end }
workspace.CurrentCamera = camera

local triggerbot = makeTriggerbot(services)
triggerbot:Initialize()
assert(job, "the triggerbot must register its check")

-- Two ticks clear the minimum shot interval, so each pump is exactly one shot attempt
local function pump()
    job(1 / 30)
    job(1 / 30)
end

characterChildren = { gun }
local before = activations
pump()
assert(activations == before + 1, "a validated target is shot through the tool's own activation")

-- A shot that cannot be simulated is explained, not turned into a click, and the feature stays on
characterChildren = {}
before = activations
pump()
assert(activations == before, "nothing is pressed on the player's behalf")
assert(#notices == 1 and notices[1][2] == "No tool is equipped", "the reason reaches the player once")
pump()
pump()
assert(#notices == 1, "repeated misses must not spam notifications")
for _, write in ipairs(writes) do
    assert(write.Path ~= "Aimbot.Triggerbot.Enabled", "a skipped shot must not disable the triggerbot")
end
clock += 10
pump()
assert(#notices == 2, "the reason is repeated once the cooldown passes")

-- Alt-tabbing mid-run stops the simulated shots instead of clicking another window
characterChildren = { gun }
input.WindowFocusReleased:Fire()
before = activations
pump()
assert(activations == before, "no activation while Roblox is unfocused")
input.WindowFocused:Fire()
pump()
assert(activations == before + 1, "focus returns the simulated shot")

print("Simulated input scenarios passed")
