--!nonstrict
return function(_sources: any, core: any): any
    local Test = { Passed = 0 }
    local function expect(condition: boolean, message: string) assert(condition, message); Test.Passed += 1 end
    local function vector(dimension: number, x: number, y: number, z: number?): any
        local data = { X = x, Y = y, Z = z or 0 }
        local value = core.TypedValue("Vector" .. dimension, data)
        local mt = getmetatable(value)
        local function new(a: number, b: number, c: number): any return vector(dimension, a, b, c) end
        mt.__add = function(a: any, b: any) return new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
        mt.__sub = function(a: any, b: any) return new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
        mt.__mul = function(a: any, b: any) if type(a) == "number" then a, b = b, a end; return new(a.X * b, a.Y * b, a.Z * b) end
        mt.__div = function(a: any, b: number) return new(a.X / b, a.Y / b, a.Z / b) end
        mt.__index = function(_value: any, key: string): any
            local magnitude = math.sqrt(x * x + y * y + (z or 0) ^ 2)
            if key == "Magnitude" then return magnitude end
            if key == "Unit" then return new(x / magnitude, y / magnitude, (z or 0) / magnitude) end
            return data[key]
        end
        return value
    end
    function Test:Run(): number
        local runtime = core.Environment
        runtime.Vector2 = { new = function(x: number, y: number) return vector(2, x, y) end, zero = vector(2, 0, 0) }
        runtime.Vector3 = { new = function(x: number, y: number, z: number) return vector(3, x, y, z) end,
            zero = vector(3, 0, 0, 0), yAxis = vector(3, 0, 1, 0) }
        core.EnumType("ActuatorRelativeTo", { "World" })
        core.EnumType("RaycastFilterType", { "Exclude" })
        local allInstances, drawingObjects = {}, {}
        local function instance(class: string, props: any?): any
            local object = props or {}
            object._type, object.ClassName, object.Name = "Instance", class, object.Name or class
            object.Destroying = core.Signal()
            function object:IsA(name: string): boolean return name == class or (name == "BasePart" and class == "Part") end
            function object:IsDescendantOf(parent: any): boolean local node = self.Parent; while node do if node == parent then return true end; node = node.Parent end; return false end
            function object:Destroy() self.Destroying:Fire(); self.Destroyed = true; self.Parent = nil end
            table.insert(allInstances, object)
            return object
        end
        runtime.Instance = { new = instance }
        runtime.Drawing = { new = function(kind: string): any
            local object = { Kind = kind, Visible = true }
            function object:Remove() expect(not self.Visible, "Every Drawing removal hides first"); self.Removed = true end
            table.insert(drawingObjects, object)
            return object
        end }
        runtime.RaycastParams = { new = function() return {} end }
        local workspace = { CurrentCamera = { CFrame = { Position = vector(3, 0, 0, 0), LookVector = vector(3, 0, 0, -1), RightVector = vector(3, 1, 0, 0) } } }
        local lastParams = nil
        function workspace:Raycast(_origin: any, _direction: any, params: any): any lastParams = params; return nil end
        core.Services.Workspace = workspace
        local localPlayer = { Name = "Local", DisplayName = "Local", UserId = 1, Neutral = true, TeamColor = {} }
        local target = { Name = "Anna", DisplayName = "Anna", UserId = 2, Neutral = true, TeamColor = {} }
        local exact = { Name = "Ann", DisplayName = "Ann", UserId = 3, Neutral = true, TeamColor = {} }
        local players = { LocalPlayer = localPlayer }
        function players:GetPlayers(): any return { localPlayer, target, exact } end
        function players:GetPlayerFromCharacter(character: any): any for _, player in ipairs(self:GetPlayers()) do if player.Character == character then return player end end; return nil end
        local friendCalls = 0
        function localPlayer:IsFriendsWith(_userId: number): boolean friendCalls += 1; return true end
        core.Services.Players = players
        local input = core.Services.UserInputService
        input.InputBegan, input.InputEnded = core.Signal(), core.Signal()
        function input:GetFocusedTextBox(): any return nil end
        function input:IsKeyDown(_key: any): boolean return false end
        local function assets(player: any): any
            local character = instance("Model", { Parent = workspace })
            function character:FindFirstChildWhichIsA(_class: string, _recursive: boolean): any return nil end
            local root = instance("Part", { Parent = character, Position = vector(3, 10, 0, 0), AssemblyLinearVelocity = vector(3, 4, 5, 6), AssemblyAngularVelocity = vector(3, 1, 2, 3) })
            local humanoid = instance("Humanoid", { Parent = character, Health = 100, PlatformStand = false, AutoRotate = true })
            player.Character = character
            return { Player = player, Character = character, RootPart = root, Humanoid = humanoid, Head = root }
        end
        local localAssets, targetAssets, ready = assets(localPlayer), assets(target), true
        local registry = { [localPlayer] = localAssets, [target] = targetAssets }
        local master = core.Load("src/Core/Disposer.luau")().new("FeaturesTest")
        local bus = core.Load("src/Core/EventBus.luau")(master)
        local state = core.Load("src/Core/StateStore.luau")(bus, master); state:SetTier(3)
        local environment = core.Load("src/Core/Environment.luau")(master)
        local scheduler = core.Load("src/Core/TaskScheduler.luau")(master)
        local tracker = {}
        function tracker:GetLocalAssets(): any return if ready then registry[localPlayer] else nil end
        function tracker:GetPlayerAssets(player: any): any return registry[player] end
        function tracker:OnLocalCharacterRespawn(callback: any): any return bus:Subscribe("LocalCharacterRespawn", callback) end
        local services = core.Load("src/Core/ServiceContainer.luau")(master)
        for name, value in pairs({ Disposer = master, StateStore = state, Environment = environment, TaskScheduler = scheduler, PlayerTracker = tracker, EventBus = bus }) do services:Register(name, value) end
        local actualTracker = core.Load("src/Services/PlayerTracker.luau")(services)
        expect(actualTracker:GetPlayerByName("Ann") == exact, "Exact player-name match precedes substring matches")
        local filter = core.Load("src/Combat/TargetFilter.luau")(services)
        expect(not filter:IsTeammate(target), "Neutral players are not teammates just because their team color defaults match")
        expect(filter:IsFriend(target) and filter:IsFriend(target) and friendCalls == 1, "Friendship lookups are cached per UserId")
        state:Set("Settings.Whitelist", { "anna" })
        expect(filter:IsWhitelisted(target), "Whitelist matches case-insensitive usernames")
        local config = { TeamCheck = false, FriendCheck = false, WhitelistCheck = false, ForceFieldCheck = false, VisCheck = false, MaxDistance = 50 }
        expect(filter:ValidateTarget(target, targetAssets.RootPart, config), "An independent filter scope accepts an eligible target")
        config.WhitelistCheck = true
        expect(not filter:ValidateTarget(target, targetAssets.RootPart, config), "One scope can enable a filter without affecting another")
        filter:Raycast(vector(3, 0, 0, 0), vector(3, 1, 0, 0))
        local firstParams = lastParams
        filter:Raycast(vector(3, 0, 0, 0), vector(3, 2, 0, 0))
        expect(lastParams == firstParams and #lastParams.FilterDescendantsInstances == 2, "Visibility reuses one RaycastParams excluding local character and camera")
        services:Register("TargetFilter", filter)
        local aim = core.Load("src/Combat/AimbotService.luau")(services)
        local results = {}
        for _, fps in ipairs({ 30, 60, 240 }) do
            local remaining = 100
            for _ = 1, fps do remaining *= 1 - aim:SmoothingAlpha(1 / fps, 8) end
            results[fps] = remaining
        end
        expect(math.abs(results[30] - results[240]) < 1e-8 and math.abs(results[60] - results[240]) < 1e-8, "The production smoothing function integrates identically at 30, 60 and 240 FPS")
        local pool = core.Load("src/Visuals/DrawingPool.luau")(services)
        expect(pool.Available, "Drawing availability is established by a real throwaway primitive")
        local line = pool:Acquire("Line"); line.Visible = true; pool:Release(line)
        local count = #drawingObjects
        expect(pool:Acquire("Line") == line and #drawingObjects == count, "Released primitives are reused, not reallocated")
        expect(pool:GetStats().Active == 1, "Drawing pool ownership statistics remain consistent")
        local flight = core.Load("src/Locomotion/FlightService.luau")(services)
        flight:Initialize()
        ready = false; state:Set("Movement.FlyEnabled", true)
        core.Services.RunService.Heartbeat:Fire(0.02)
        expect(not flight:IsFlying(), "Flight waits harmlessly for an indexed character")
        ready = true; core.Services.RunService.Heartbeat:Fire(0.02)
        expect(flight:IsFlying() and localAssets.Humanoid.PlatformStand and not localAssets.Humanoid.AutoRotate, "Flight self-heals when the character becomes available")
        local firstScope = flight._flightScope
        state:Set("Movement.FlyEnabled", false)
        expect(firstScope:IsDisposed() and not flight:IsFlying() and not localAssets.Humanoid.PlatformStand and localAssets.Humanoid.AutoRotate, "Stopping flight disposes constraints and restores humanoid values")
        expect(localAssets.RootPart.AssemblyLinearVelocity.X == 4 and localAssets.RootPart.AssemblyAngularVelocity.Y == 2, "Flight restores the captured assembly velocities")
        state:Set("Movement.FlyEnabled", true); core.Services.RunService.Heartbeat:Fire(0.02)
        expect(flight:IsFlying() and flight._flightScope ~= firstScope, "Second flight cycle never reuses a disposed bag")
        local newAssets = assets(localPlayer); registry[localPlayer] = newAssets
        bus:Publish("LocalCharacterRespawn", newAssets); core.Services.RunService.Heartbeat:Fire(0.02)
        expect(flight:IsFlying() and flight._root == newAssets.RootPart and not localAssets.Humanoid.PlatformStand, "Respawn rebuilds flight on the new assembly and restores the old one")
        state:SetTier(0)
        expect(not flight:IsFlying() and not state:Get("Movement.FlyEnabled"), "Tier revocation stops flight immediately")
        local attributeObject = { Values = { Existing = 9 } }
        function attributeObject:GetAttribute(name: string): any return self.Values[name] end
        function attributeObject:SetAttribute(name: string, value: any) self.Values[name] = value end
        local attributes = master:CreateChild("Attributes")
        attributes:SetAttribute(attributeObject, "Existing", 1); attributes:SetAttribute(attributeObject, "Added", true); attributes:Dispose()
        expect(attributeObject.Values.Existing == 9 and attributeObject.Values.Added == nil, "Plugin attribute restoration preserves both values and original absence")
        local transform, a, b = { Value = 0 }, master:CreateChild("Dynamic A"), master:CreateChild("Dynamic B")
        a:SetProperty(transform, "Value", 1, true); b:SetProperty(transform, "Value", 2, true); a:SetProperty(transform, "Value", 3, true)
        expect(transform.Value == 3, "Dynamic transform leases compose in write order")
        b:Dispose(); a:Dispose(); expect(transform.Value == 0, "Dynamic leases still restore the shared baseline")
        runtime.CFrame = { new = function(x: number, y: number, z: number): any return core.TypedValue("CFrame", { Position = vector(3, x, y, z) }) end }
        local manifest = core.Load("src/Plugins/ExampleGame/Manifest.luau")()
        expect(table.isfrozen(manifest) and table.isfrozen(manifest.Weapons.Attributes), "Plugin manifest data is recursively frozen")
        expect(not pcall(function() manifest.Weapons.Attributes.Spread = 10 end), "Accidental manifest mutation fails loudly")
        local registryModule = core.Load("src/Plugins/PluginRegistry.luau")()
        expect(registryModule:Resolve(123, 456) == nil, "The example plugin is never silently registered for a live game")
        state:SetTier(3)
        local pluginValue = { Value = 7 }
        services:Register("Require", function(path: string): any
            if path == "src/Plugins/PluginRegistry.luau" then return { Resolve = function() return { Name = "Broken test plugin", PluginModule = "src/TestPlugin.luau" } end } end
            return function(pluginServices: any): any
                pluginServices:Get("Disposer"):SetProperty(pluginValue, "Value", 99)
                error("Deliberate partial plugin construction failure")
            end
        end)
        local manager = core.Load("src/Plugins/PluginManager.luau")(services)
        manager:Initialize()
        expect(pluginValue.Value == 7 and manager._active == nil and manager._activeOwner == nil, "A plugin factory that throws midway still restores its owned changes immediately")
        master:Dispose()
        for _, object in ipairs(drawingObjects) do expect(object.Removed == true, "No Drawing object survives master disposal") end
        for _, object in ipairs(allInstances) do
            if object.ClassName == "LinearVelocity" or object.ClassName == "Attachment" or object.ClassName == "BodyGyro" then expect(object.Destroyed == true, "No flight constraint survives master disposal") end
        end
        print(string.format("PASS Features: %d assertions", Test.Passed))
        return Test.Passed
    end
    return Test
end
