--!nonstrict
-- Run with a source-map supplied by the CLI harness or an executor; production never loads tests.
return function(sources: { [string]: string }): any
    local Test = { Passed = 0 }
    local warnings, tasks, bindings, delays = {}, {}, {}, {}
    local function expect(condition: boolean, message: string)
        assert(condition, message)
        Test.Passed += 1
    end
    local function signal(): any
        local Signal = { Handlers = {} }
        function Signal:Connect(callback: (...any) -> ()): any
            local connection = { Connected = true, Callback = callback, _type = "RBXScriptConnection" }
            function connection:Disconnect() self.Connected = false end
            table.insert(self.Handlers, connection)
            return connection
        end
        function Signal:Fire(...: any)
            for _, connection in ipairs(table.clone(self.Handlers)) do if connection.Connected then connection.Callback(...) end end
        end
        return Signal
    end
    local tags = {}
    local function typedValue(tag: string, data: any): any
        if tag == "Color3" then
            data.ToHSV = function(): (number, number, number)
                local maximum, minimum = math.max(data.R, data.G, data.B), math.min(data.R, data.G, data.B)
                local delta, hue = maximum - minimum, 0
                if delta > 0 then
                    if maximum == data.R then hue = ((data.G - data.B) / delta) % 6
                    elseif maximum == data.G then hue = (data.B - data.R) / delta + 2
                    else hue = (data.R - data.G) / delta + 4 end
                    hue /= 6
                end
                return hue, if maximum == 0 then 0 else delta / maximum, maximum
            end
            data.Lerp = function(_color: any, target: any, alpha: number): any
                return typedValue("Color3", { R = data.R + (target.R - data.R) * alpha, G = data.G + (target.G - data.G) * alpha, B = data.B + (target.B - data.B) * alpha })
            end
        end
        local proxy = newproxy(true)
        local mt = getmetatable(proxy)
        mt.__index = data
        mt.__newindex = data
        mt.__tostring = function() return data.String or tag end
        tags[proxy] = tag
        return proxy
    end
    local enumTypes = {}
    local function enumType(name: string, names: { string }): any
        local enum = {}
        local items = {}
        setmetatable(enum, { __tostring = function() return "Enum." .. name end })
        for index, key in ipairs(names) do
            local item = typedValue("EnumItem", { Name = key, Value = index, EnumType = enum, String = "Enum." .. name .. "." .. key })
            enum[key] = item; table.insert(items, item)
        end
        function enum:GetEnumItems(): any return items end
        enumTypes[name] = enum
        return enum
    end
    enumType("KeyCode", { "Unknown", "F", "End", "RightShift", "A", "B", "Escape" })
    enumType("UserInputType", { "MouseButton1", "MouseButton2", "MouseButton3", "Keyboard", "Touch" })
    local renderPriority = enumType("RenderPriority", { "Camera" }); renderPriority.Camera.Value = 200
    local runService = { Stepped = signal(), Heartbeat = signal(), RenderStepped = signal() }
    function runService:BindToRenderStep(name: string, priority: number, callback: (number) -> ()) bindings[name] = { Priority = priority, Callback = callback } end
    function runService:UnbindFromRenderStep(name: string) bindings[name] = nil end
    local environment: any = setmetatable({}, { __index = getfenv(0) })
    environment._G = {}
    environment.Enum = enumTypes
    environment.Color3 = { fromRGB = function(r: number, g: number, b: number) return typedValue("Color3", { R = r / 255, G = g / 255, B = b / 255 }) end }
    environment.Color3.new = function(r: number, g: number, b: number) return typedValue("Color3", { R = r, G = g, B = b }) end
    environment.typeof = function(value: any): string return tags[value] or (if type(value) == "table" and value._type then value._type else typeof(value)) end
    environment.warn = function(...: any) table.insert(warnings, table.concat({ ... }, " ")) end
    environment.task = {
        spawn = function(callback: any, ...: any): thread
            local worker = if type(callback) == "thread" then callback else coroutine.create(callback)
            local ok, err = coroutine.resume(worker, ...); assert(ok, tostring(err)); tasks[worker] = true; return worker
        end,
        delay = function(_delay: number, callback: any): thread
            local worker = if type(callback) == "thread" then callback else coroutine.create(callback)
            tasks[worker] = true; table.insert(delays, { Worker = worker, Duration = _delay }); return worker
        end,
        cancel = function(worker: thread) tasks[worker] = nil; coroutine.close(worker) end,
        wait = function() coroutine.yield() end,
    }
    local files = {}
    local encoded, nextJson = {}, 0
    local http = {}
    function http:JSONEncode(value: any): string nextJson += 1; local key = "json:" .. nextJson; encoded[key] = value; return key end
    function http:JSONDecode(value: string): any assert(encoded[value], "Invalid JSON"); return encoded[value] end
    function http:GenerateGUID(_braces: boolean): string return "12345678-1234-1234-1234-123456789abc" end
    local services = { RunService = runService, HttpService = http, Players = {}, UserInputService = { TouchEnabled = false, KeyboardEnabled = true } }
    environment.game = { GetService = function(_game: any, name: string): any assert(services[name], "Unavailable " .. name); return services[name] end }
    environment.getfenv = function() return environment end
    environment.writefile = function(path: string, value: string) files[path] = value end
    environment.readfile = function(path: string) assert(files[path], "Missing file"); return files[path] end
    environment.isfile = function(path: string) return files[path] ~= nil end
    environment.makefolder = function(_path: string) end
    environment.delfile = function(path: string) files[path] = nil end
    environment.listfiles = function(prefix: string): any local result = {}; for path in pairs(files) do if path:sub(1, #prefix) == prefix then table.insert(result, path) end end; return result end
    local function loadModule(path: string): any
        local chunk, err = loadstring(assert(sources[path], "Missing test source: " .. path), "@" .. path)
        assert(chunk, err); setfenv(chunk, environment); return chunk()
    end

    Test.Environment, Test.Services, Test.Files, Test.Http = environment, services, files, http
    Test.Load, Test.Signal, Test.EnumType, Test.Warnings = loadModule, signal, enumType, warnings
    Test.Encoded, Test.TypedValue, Test.Delays = encoded, typedValue, delays

    function Test:Run(): number
        local Disposer = loadModule("src/Core/Disposer.luau")()
        local master = Disposer.new("Test")
        local order = {}
        master:Add(function() table.insert(order, "first") end)
        master:Add(function() table.insert(order, "second") end)
        master:Bind("slot", function() table.insert(order, "old") end)
        master:Bind("slot", function() table.insert(order, "key") end)
        expect(order[1] == "old", "Key rebinding must dispose the old occupant")
        local child = master:CreateChild("Child")
        local object = { Value = 5, Optional = nil }
        child:SetProperty(object, "Value", 10)
        local overlay = master:CreateChild("Overlay")
        overlay:SetProperty(object, "Value", 20)
        child:SetProperty(object, "Value", 11)
        expect(object.Value == 20, "A lower layer must not steal overlay priority")
        child:Dispose()
        expect(object.Value == 20, "Removing an underlying owner preserves the active overlay")
        overlay:Dispose()
        expect(object.Value == 5, "Last property lease restores the original value")
        local nilScope = master:CreateChild("Nil")
        nilScope:SetProperty(object, "Optional", "value"); nilScope:Dispose()
        expect(object.Optional == nil, "Nil originals are cached, not mistaken for missing snapshots")
        local readOnly = setmetatable({}, { __index = { Value = 12 }, __newindex = function() error("read-only") end })
        local immutable = master:CreateChild("Read-only property")
        expect(not immutable:SetProperty(readOnly, "Value", 0) and next(immutable._leases) == nil, "Rejected engine writes do not create bogus restoration leases")
        immutable:Dispose()
        local bus = loadModule("src/Core/EventBus.luau")(master)
        local calls = {}
        local first = bus:Subscribe("event", function() table.insert(calls, 1); error("isolated handler") end)
        local middle = bus:Subscribe("event", function() table.insert(calls, 2) end)
        bus:Subscribe("event", function() table.insert(calls, 3) end)
        middle:Disconnect(); bus:Publish("event")
        expect(#calls == 2 and calls[1] == 1 and calls[2] == 3, "Disconnect and throwing handlers cannot starve neighbours")
        expect(first.Next and first.Next.Previous == first, "Doubly-linked list is repaired after O(1) removal")
        local state = loadModule("src/Core/StateStore.luau")(bus, master)
        local changes = 0
        state:Observe("Settings.Whitelist", function() changes += 1 end)
        local list = state:Get("Settings.Whitelist"); list[1] = "Tester"; state:Set("Settings.Whitelist", list)
        expect(changes == 1, "Mutating a returned table must still publish on Set")
        list[2] = "Aliased"
        expect(#state:Get("Settings.Whitelist") == 1, "Store clones values on write")
        expect(state:Peek("Settings") == state._settings.Settings and state:Peek("Settings") ~= state:Get("Settings"), "Peek is the live table; Get remains a clone")
        local copy = state:GetSettingsSnapshot(); copy.Settings.UIScale = 9
        expect(state:Get("Settings.UIScale") == 1, "Snapshot is isolated")
        state:LoadSettingsSnapshot({ Movement = { FlySpeed = 77 }, Settings = { UIScale = "invalid" } })
        expect(state:Get("Movement.FlySpeed") == 77 and state:Get("Movement.SprintSpeed") == 28, "Old profiles merge over new defaults")
        expect(state:Get("Settings.UIScale") == 1, "Hydration rejects mismatched scalar types")
        state:Set("Aimbot.Enabled", true); state:Set("ESP.Enabled", true); state:Set("Movement.FlyEnabled", true)
        expect(state:Get("Aimbot.Enabled") and state:Get("ESP.Enabled") and state:Get("Movement.FlyEnabled"), "All built-in feature settings can be enabled directly")
        expect(state:Set("Game.DoorOpen", true) and state:Get("Game.DoorOpen"), "Game plugin state accepts free-form settings")
        state:LoadSettingsSnapshot({ Aimbot = { Enabled = true }, Movement = { Fling = true } })
        expect(state:Get("Aimbot.Enabled") and state:Get("Movement.Fling"), "Hydration preserves enabled settings without an access sweep")
        state:Set("Settings.MenuKeybind", enumTypes.KeyCode.B)
        expect(state:Get("Settings.Binds.Menu").Name == "B", "Menu key aliases remain consistent")
        state:Set("ESP.DepthMode", "Occluded")
        expect(state:Get("Chams.DepthMode") == "Occluded", "ESP depth mode stays aliased onto chams")
        local scheduler = loadModule("src/Core/TaskScheduler.luau")(master)
        local frames, after, deltas = 0, 0, {}
        local job = scheduler:RegisterRender("Broken", 0, function() frames += 1; error("deliberate") end)
        scheduler:RegisterRender("Healthy", 1, function(dt: number) after += 1; table.insert(deltas, dt) end)
        for _ = 1, 8 do runService.RenderStepped:Fire(1 / 60) end
        expect(frames == 5 and job.Strikes == 5 and not job.Enabled, "Circuit breaker trips at exactly five consecutive errors")
        expect(after == 8 and deltas[1] == 1 / 60, "Healthy frame jobs continue after another job trips")
        local attempts = 0
        local recovering = scheduler:RegisterHeartbeat("Recovery", 0, function() attempts += 1; if attempts ~= 4 then error("flaky") end end)
        for _ = 1, 7 do runService.Heartbeat:Fire(0.1) end
        expect(recovering.Enabled and recovering.Strikes == 3, "A successful frame resets consecutive strikes")
        local step = nil
        scheduler:RegisterPreSim("Delta", 0, function(dt: number) step = dt end)
        runService.Stepped:Fire(100, 0.02)
        expect(step == 0.02, "Stepped must forward step, not absolute time")
        expect(bindings["B0XazUniversal.Camera"].Priority == 201, "Camera work runs after the engine camera")
        local container = loadModule("src/Core/ServiceContainer.luau")(master)
        local initialized = {}
        container:Register("Dummy", { Initialize = function() table.insert(initialized, "init") end, Destroy = function() table.insert(initialized, "destroy") end })
        container:InitializeAll(); container:InitializeAll()
        expect(#initialized == 1 and container:Has("Dummy"), "Services initialize exactly once")
        expect(not pcall(function() container:Get("Missing") end), "Missing dependencies throw loudly")
        local env = loadModule("src/Core/Environment.luau")(master)
        expect(env:ParseKeybind("MB2") == enumTypes.UserInputType.MouseButton2, "Mouse aliases parse")
        expect(env:ParseKeybind({ __type = "EnumItem", enum = "KeyCode", name = "F" }) == enumTypes.KeyCode.F, "Serialized enum binds parse")
        expect(env:ParseKeybind("invalid") == nil, "Unknown key names are harmless")
        expect(not env:WriteFile("../escape", "no"), "File sandbox rejects parent traversal")
        expect(env:WriteFile("B0XazUniversal/Configs/a.json", "ok"), "Root prefix is accepted exactly once")
        expect(files["B0XazUniversal/Configs/a.json"] == "ok", "Filesystem writes stay under owned root")
        expect(env.GetDeviceId == nil, "The environment no longer exposes a device-identifier API")
        expect(not env:HasFpsCap() and not env:MouseMove(1, 1), "Optional capabilities degrade without crashing")
        local pressed, releaseAttempts = false, 0
        services.UserInputService.GetMouseLocation = function() return { X = 10, Y = 20 } end
        services.VirtualInputManager = { SendMouseButtonEvent = function(_service: any, _x: number, _y: number, _button: number, down: boolean)
            if not down then releaseAttempts += 1; if releaseAttempts == 1 then error("Transient release failure") end end
            pressed = down
        end }
        local virtual = loadModule("src/Core/Environment.luau")(master)
        expect(virtual:MouseClick() and pressed, "Virtual input fallback presses when native click is missing")
        for _, delayed in ipairs(delays) do if delayed.Duration == 0.03 and coroutine.status(delayed.Worker) == "suspended" then coroutine.resume(delayed.Worker) end end
        virtual:Destroy()
        expect(not pressed and releaseAttempts == 2, "Unload retries a virtual-button release that previously threw")
        local drawingRemoved = false
        master:Add({ Visible = true, Remove = function(primitive: any) expect(not primitive.Visible, "Drawing is hidden before Remove"); drawingRemoved = true end })
        local cancelled = master:Delay(10, function() error("Must not survive unload") end)
        master:Dispose(); master:Dispose()
        expect(drawingRemoved and bindings["B0XazUniversal.Camera"] == nil, "Master cleanup removes Drawing and camera binding")
        expect(coroutine.status(cancelled) == "dead", "Delayed threads are cancelled")
        expect(order[2] == "key" and order[#order - 1] == "second" and order[#order] == "first", "Keyed cleanup precedes reverse array cleanup")
        expect(initialized[2] == "destroy", "Container teardown runs")
        local custom = { _type = "Instance", Finished = false }
        function custom:Finish() self.Finished = true end
        master:Add(custom, "Finish")
        expect(custom.Finished, "Explicit cleanup methods override type dispatch, including late Instance registrations")
        local late = false; master:Add(function() late = true end)
        expect(late, "Late registrations on disposed scopes clean immediately")
        print(string.format("PASS Core: %d assertions", Test.Passed))
        return Test.Passed
    end
    return Test
end
