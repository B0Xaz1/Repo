--!nonstrict
return function(sources: any, core: any): any
    local Test = { Passed = 0 }
    local function expect(condition: boolean, message: string) assert(condition, message); Test.Passed += 1 end
    function Test:Run(): number
        local runtime, vector2 = core.Environment, core.Environment.Vector2
        local properties, instances = {}, {}
        for name, values in pairs({ Font = { "Gotham", "GothamSemibold", "GothamBold", "GothamMedium", "Code" }, AutomaticSize = { "None", "X", "Y", "XY" },
            SortOrder = { "LayoutOrder" }, FillDirection = { "Horizontal", "Vertical" }, TextXAlignment = { "Left", "Right", "Center" },
            TextYAlignment = { "Top", "Center" }, ApplyStrokeMode = { "Border" }, TextTruncate = { "AtEnd" },
            ScrollingDirection = { "X", "Y", "XY" }, ZIndexBehavior = { "Sibling" }, VerticalAlignment = { "Bottom", "Top" } }) do core.EnumType(name, values) end
        runtime.UDim = { new = function(scale: number, offset: number) return { Scale = scale, Offset = offset } end }
        runtime.UDim2 = { new = function(x: number, xo: number, y: number, yo: number) return { X = { Scale = x, Offset = xo }, Y = { Scale = y, Offset = yo } } end }
        runtime.UDim2.fromOffset = function(x: number, y: number) return runtime.UDim2.new(0, x, 0, y) end
        runtime.UDim2.fromScale = function(x: number, y: number) return runtime.UDim2.new(x, 0, y, 0) end
        runtime.NumberSequence, runtime.ColorSequence = { new = function(value: any) return value end }, { new = function(value: any) return value end }
        runtime.NumberSequenceKeypoint, runtime.ColorSequenceKeypoint = { new = function(...: any) return { ... } end }, { new = function(...: any) return { ... } end }
        runtime.Color3.fromHSV = function(h: number, s: number, v: number): any
            local sector = (h % 1) * 6
            local chroma, x = v * s, v * s * (1 - math.abs(sector % 2 - 1))
            local rgb = if sector < 1 then { chroma, x, 0 } elseif sector < 2 then { x, chroma, 0 } elseif sector < 3 then { 0, chroma, x }
                elseif sector < 4 then { 0, x, chroma } elseif sector < 5 then { x, 0, chroma } else { chroma, 0, x }
            return runtime.Color3.new(rgb[1] + v - chroma, rgb[2] + v - chroma, rgb[3] + v - chroma)
        end
        local function create(class: string): any
            local data: any = { ClassName = class, Name = class, Children = {}, Attributes = {}, Signals = {}, Parent = nil,
                Position = runtime.UDim2.fromOffset(0, 0), Size = runtime.UDim2.fromOffset(300, 40), Text = "", Visible = true, LayoutOrder = 0,
                AbsolutePosition = vector2.zero, AbsoluteSize = vector2.new(300, 40), AnchorPoint = vector2.zero,
                BackgroundColor3 = runtime.Color3.new(1, 1, 1), TextColor3 = runtime.Color3.new(0, 0, 0) }
            local object = core.TypedValue("Instance", data)
            properties[object] = data; table.insert(instances, object)
            for _, name in ipairs({ "Destroying", "ChildAdded", "ChildRemoved", "DescendantAdded", "InputBegan", "InputChanged", "InputEnded", "MouseEnter", "MouseLeave", "Activated", "FocusLost" }) do data[name] = core.Signal() end
            function data:GetChildren(): any return table.clone(data.Children) end
            function data:GetDescendants(): any
                local result = {}
                for _, child in ipairs(data.Children) do table.insert(result, child); for _, nested in ipairs(child:GetDescendants()) do table.insert(result, nested) end end
                return result
            end
            function data:IsA(name: string): boolean
                return name == class or (name == "GuiObject" and table.find({ "Frame", "ScrollingFrame", "TextLabel", "TextButton", "TextBox" }, class) ~= nil)
            end
            function data:SetAttribute(name: string, value: any) data.Attributes[name] = value end
            function data:GetAttribute(name: string): any return data.Attributes[name] end
            function data:GetPropertyChangedSignal(name: string): any
                if not data.Signals[name] then data.Signals[name] = core.Signal() end
                return data.Signals[name]
            end
            function data:FindFirstChild(name: string): any for _, child in ipairs(data.Children) do if child.Name == name then return child end end; return nil end
            function data:FindFirstChildOfClass(name: string): any for _, child in ipairs(data.Children) do if child:IsA(name) then return child end end; return nil end
            function data:Destroy()
                if data.Destroyed then return end
                data.Destroying:Fire()
                for _, child in ipairs(table.clone(data.Children)) do child:Destroy() end
                object.Parent = nil; data.Destroyed = true
            end
            getmetatable(object).__newindex = function(_object: any, key: string, value: any)
                if data[key] == value then return end
                if key == "Parent" then
                    if value and data.FailParent == value then error("Injected reparent failure") end
                    assert(not data.Destroyed or value == nil, "Destroyed instance cannot be reparented")
                    local previous = data.Parent
                    if previous and properties[previous] then local index = table.find(properties[previous].Children, object); if index then table.remove(properties[previous].Children, index) end end
                    data.Parent = value
                    if value and properties[value] then table.insert(properties[value].Children, object); value.ChildAdded:Fire(object) end
                else data[key] = value end
                if data.Signals[key] then data.Signals[key]:Fire() end
            end
            return object
        end
        runtime.Instance = { new = create }
        local world, parent, camera = create("Workspace"), create("CoreGui"), create("Camera")
        parent.Parent = world; camera.Parent = world; camera.ViewportSize = vector2.new(1280, 800); world.CurrentCamera = camera
        core.Services.Workspace, core.Services.CoreGui = world, parent
        core.Services.GuiService = { GetGuiInset = function() return vector2.zero end }
        core.Services.TeleportService = {}
        core.Services.UserInputService.InputChanged = core.Signal()
        core.Services.Players.LocalPlayer.FindFirstChildOfClass = function() return nil end
        runtime.game.PlaceId, runtime.game.GameId = 100, 200
        runtime.Drawing = nil
        local master = core.Load("src/Core/Disposer.luau")().new("UITest")
        local bus = core.Load("src/Core/EventBus.luau")(master)
        local state = core.Load("src/Core/StateStore.luau")(bus, master); state:SetTier(3)
        local environment = core.Load("src/Core/Environment.luau")(master)
        local services = core.Load("src/Core/ServiceContainer.luau")(master); services.Version = "2.0.0-test"
        local factories, initialized = {}, {}
        local function load(path: string, ...: any): any
            if not factories[path] then factories[path] = core.Load(path) end
            if select("#", ...) == 0 then return factories[path] end
            if initialized[path] == nil then initialized[path] = factories[path](...) end
            return initialized[path]
        end
        for name, value in pairs({ Disposer = master, EventBus = bus, StateStore = state, Environment = environment, Require = load,
            DrawingPool = { Available = false }, LocomotionService = { ListBookmarks = function() return {} end },
            PlayerTracker = { GetPlayerNames = function() return { "Ann", "Anna" } end, GetWhitelistSummary = function() return "None" end },
            KeyService = { GetTierName = function() return ({ "Entry", "Normal", "Full" })[state:GetTier()] or "No Access" end, GetMaskedKey = function() return "masked" end,
                AuthenticateKey = function() return false, 0, "Backend maintenance: please retry later", "transient" end },
            LightingService = { SetMode = function(_service: any, mode: string) state:Set("Lighting.Mode", mode) end } }) do services:Register(name, value) end
        services:Register("DOM", load("src/UI/DOM.luau", services))
        services:Register("ConfigService", load("src/Services/ConfigService.luau", services))
        services:Register("HotkeyService", load("src/Services/HotkeyService.luau", services))
        services:Register("PluginManager", load("src/Plugins/PluginManager.luau", services))
        local theme = load("src/UI/ThemeEngine.luau", services); services:Register("ThemeEngine", theme); theme:Initialize()
        local ui = load("src/UI/UIEngine.luau", services); services:Register("UIEngine", ui)
        ui:ConstructInterface()
        expect(#ui._tabs == 7 and ui._active.Name == "Combat", "All seven real tab factories construct in registration order")
        expect(ui._versionLabel.Text:find(services.Version, 1, true) ~= nil, "Version is visible in the title bar")
        local rows, count, boundCount = {}, 0, 0
        for row, record in pairs(ui._controls) do
            rows[row] = { Parent = row.Parent, Order = row.LayoutOrder, Record = record }; count += 1
            local path = row:GetAttribute("StatePath")
            if path then
                expect(state:Get(path) ~= nil, "Every bound UI path exists: " .. path)
                expect(row:GetAttribute("RequiredTier") == state:GetRequiredTier(path), "UI tier matches state permission map: " .. path)
                boundCount += 1
            end
        end
        expect(count >= 190 and boundCount >= 115, "Interface constructs the complete control surface, not placeholder tabs")
        ui:Search("flight")
        local moved = 0
        for row, home in pairs(rows) do if row.Parent ~= home.Parent then moved += 1; expect(row.Parent == ui._active.ResultsCol, "All matches move into the active results column") end end
        expect(moved >= 5, "Search finds controls by feature/section across tabs")
        ui:SelectTab("Settings")
        expect(ui._active.Name == "Settings" and ui._active.ResultsCol.Visible, "Switching tabs carries the live search to the new page")
        ui:ClearSearch()
        for row, home in pairs(rows) do expect(row.Parent == home.Parent and row.LayoutOrder == home.Order, "Clearing search restores exact parent and order") end
        local badRow = nil
        for row, home in pairs(rows) do if home.Record.Label == "Enable aimbot" then badRow = row; break end end
        properties[badRow].FailParent = ui._active.ResultsCol
        ui:Search("enable aimbot")
        expect(ui._query == "" and badRow.Parent == rows[badRow].Parent, "A mid-filter exception rolls back the whole search")
        properties[badRow].FailParent = nil
        state:Set("Aimbot.Hitpart", "not-a-part")
        expect(state:Get("Aimbot.Hitpart") == "Head", "Invalid saved dropdown values fall back to the first option")
        ui:SelectTab("Combat"); state:Set("Aimbot.Enabled", true); state:Set("ESP.Enabled", true); state:SetTier(1)
        expect(ui._tabByName.Combat.Locked and ui._active.Name == "Visuals" and not state:Get("ESP.Enabled"), "Tier downgrade locks tabs, switches off features and bounces the active tab")
        badRow:FindFirstChildOfClass("TextButton").Activated:Fire()
        expect(not state:Get("Aimbot.Enabled"), "A locked toggle cannot enable its feature")
        state:SetTier(0)
        expect(ui._active.Name == "Settings", "Tier zero has only the Settings tab")
        local dom = services:Get("DOM")
        local unbound = dom:Create("TextLabel", { Parent = ui._root, TextColor3 = theme:GetToken("Accent") })
        theme:SetPreset("Ocean")
        expect(unbound.TextColor3 == theme:GetToken("Accent"), "Root rescanning recolors even an unbound previous-token color")
        local keyButtons = {}
        for row in pairs(ui._controls) do
            local path = row:GetAttribute("StatePath")
            if path == "Settings.MenuKeybind" or path == "Settings.UnloadKeybind" then keyButtons[path] = row:FindFirstChildOfClass("TextButton") end
        end
        local originalMenu = state:Get("Settings.MenuKeybind")
        keyButtons["Settings.MenuKeybind"].Activated:Fire()
        keyButtons["Settings.UnloadKeybind"].Activated:Fire()
        core.Services.UserInputService.InputBegan:Fire({ KeyCode = runtime.Enum.KeyCode.B, UserInputType = runtime.Enum.UserInputType.Keyboard })
        expect(state:Get("Settings.UnloadKeybind") == runtime.Enum.KeyCode.B and state:Get("Settings.MenuKeybind") == originalMenu, "One shared key capture owns only the latest armed control")
        expect(state:GetTransient("IsBindingKey") == true, "The bind guard covers the rest of the input dispatch")
        for _, delay in ipairs(core.Delays) do if delay.Duration == 0.05 and coroutine.status(delay.Worker) == "suspended" then local ok, message = coroutine.resume(delay.Worker); assert(ok, message) end end
        expect(not state:GetTransient("IsBindingKey"), "The bind guard clears after the dispatch")
        local share = load("src/UI/Modals/ConfigShareModal.luau", services); share:Show("{}")
        expect(share._view ~= nil, "The two-way JSON modal constructs")
        share:Hide()
        local auth = load("src/UI/Modals/KeyAuthModal.luau", services)
        local succeeded = false
        auth:Show(function() succeeded = true end, "Initial server message")
        local verify = nil
        for _, object in ipairs(instances) do if not properties[object].Destroyed and object:IsA("TextButton") and object.Text == "Verify license" then verify = object end end
        expect(verify ~= nil, "Pre-launch auth has a responsive verification action")
        verify.Activated:Fire()
        local found = false
        for _, object in ipairs(instances) do if not properties[object].Destroyed and object:IsA("TextLabel") and object.Text == "Backend maintenance: please retry later" then found = true end end
        expect(found and not succeeded, "Auth surfaces transient server text verbatim without granting access")
        master:Dispose()
        local alive = 0
        for _, object in ipairs(instances) do if not properties[object].Destroyed and object ~= world and object ~= parent and object ~= camera then alive += 1 end end
        expect(alive == 0, "No UI instance, modal or temporary toast survives master disposal")
        -- Smoke the actual production bootstrap too: only Roblox/executor APIs are mocked, not application services.
        runtime.Random = { new = function() return { NextNumber = function(_random: any, low: number, high: number) return (low + high) / 2 end } end }
        runtime.game.IsLoaded = function() return true end
        local fetched = {}
        runtime.game.HttpGet = function(_game: any, url: string): string
            local path = assert(url:match("/(src/.-%.luau)%?"), "Unexpected bootstrap URL")
            fetched[path] = (fetched[path] or 0) + 1
            return assert(sources[path], "Missing production source " .. path)
        end
        runtime.loadstring = function(source: string, name: string?): any
            local chunk, message = loadstring(source, name)
            if chunk then setfenv(chunk, runtime) end
            return chunk, message
        end
        local previousPrint = runtime.print
        runtime.print = function() end
        local boot = assert(runtime.loadstring(sources["init.luau"], "@ProductionSmoke"))
        boot()
        expect(runtime._G.B0XazMasterDisposer ~= nil and runtime._G.B0XazServiceContainer ~= nil and not runtime._G.B0XazRunning,
            "The complete real production graph reaches its fail-closed auth gate: " .. tostring(core.Warnings[#core.Warnings]))
        expect(runtime._G.B0XazBaseURL == "https://raw.githubusercontent.com/B0Xaz1/Repo/main/", "The direct release entry point defaults to main")
        local fetchedCount = 0
        for path, times in pairs(fetched) do expect(times == 1, "Actual boot fetches each module once: " .. path); fetchedCount += 1 end
        expect(fetchedCount >= 28, "Smoke coverage includes the real service, plugin, UI and auth factories")
        runtime._G.B0XazUnload()
        expect(runtime._G.B0XazMasterDisposer == nil, "The real production bootstrap can be unloaded before auth")
        local survivors = 0
        for _, object in ipairs(instances) do if not properties[object].Destroyed and object ~= world and object ~= parent and object ~= camera then survivors += 1 end end
        expect(survivors == 0, "Production auth-gate cleanup leaves no owned GUI instances")
        runtime.print = previousPrint
        print(string.format("PASS UI: %d assertions (%d controls, %d bound paths)", Test.Passed, count, boundCount))
        return Test.Passed
    end
    return Test
end
