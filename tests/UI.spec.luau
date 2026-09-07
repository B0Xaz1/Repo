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
        function core.Services.UserInputService:GetMouseLocation() return vector2.zero end
        core.Services.Players.LocalPlayer.FindFirstChildOfClass = function() return nil end
        runtime.game.PlaceId, runtime.game.GameId = 100, 200
        runtime.Drawing = nil
        local master = core.Load("src/Core/Disposer.luau")().new("UITest")
        local bus = core.Load("src/Core/EventBus.luau")(master)
        local state = core.Load("src/Core/StateStore.luau")(bus, master)
        local environment = core.Load("src/Core/Environment.luau")(master)
        local services = core.Load("src/Core/ServiceContainer.luau")(master); services.Version = "2.1.0-test"
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
            LightingService = { SetMode = function(_service: any, mode: string) state:Set("Lighting.Mode", mode) end } }) do services:Register(name, value) end
        services:Register("DOM", load("src/UI/DOM.luau", services))
        services:Register("ConfigService", load("src/Services/ConfigService.luau", services))
        services:Register("HotkeyService", load("src/Services/HotkeyService.luau", services))
        services:Register("PluginManager", load("src/Plugins/PluginManager.luau", services))
        local theme = load("src/UI/ThemeEngine.luau", services); services:Register("ThemeEngine", theme); theme:Initialize()
        local ui = load("src/UI/UIEngine.luau", services); services:Register("UIEngine", ui)
        ui:ConstructInterface()
        expect(#ui._tabs == 7 and ui._active.Name == "Combat", "All seven real tab factories construct in registration order")
        expect(ui._versionLabel.Text:find(services.Version, 1, true) ~= nil, "Version is visible on the menu")
        expect(ui._versionLabel.Parent == ui._main, "Version sits on the main menu frame, not the title bar")
        local function isAscii(value: string): boolean
            for index = 1, #value do if string.byte(value, index) > 127 then return false end end
            return true
        end
        local function scanAscii(node: any)
            if type(node.Text) == "string" then expect(isAscii(node.Text), "Live UI text is ASCII: " .. node.Text) end
            if type(node.PlaceholderText) == "string" then expect(isAscii(node.PlaceholderText), "Live UI placeholder is ASCII: " .. node.PlaceholderText) end
            for _, child in ipairs(node:GetChildren()) do scanAscii(child) end
        end
        scanAscii(ui._root)
        expect(ui._searchBox.PlaceholderText == "search...", "Search placeholder stays ASCII")
        local closeText = nil
        for _, child in ipairs(ui._main:GetDescendants()) do
            if child:IsA("TextButton") and child.Text == "X" then closeText = child.Text; break end
        end
        expect(closeText == "X", "Close control uses an ASCII X instead of a multiply glyph")
        local rows, count, boundCount = {}, 0, 0
        for row, record in pairs(ui._controls) do
            rows[row] = { Parent = row.Parent, Order = row.LayoutOrder, Record = record }; count += 1
            local path = row:GetAttribute("StatePath")
            if path then
                expect(state:Get(path) ~= nil, "Every bound UI path exists: " .. path)
                boundCount += 1
            end
        end
        expect(count >= 184 and boundCount >= 114, "Interface constructs the complete control surface, not placeholder tabs")
        ui:Search("flight")
        local moved = 0
        for row, home in pairs(rows) do if row.Parent ~= home.Parent then moved += 1; expect(row.Parent == ui._active.ResultsCol, "All matches move into the active results column") end end
        expect(moved >= 5, "Search finds controls by feature/section across tabs")
        ui:SelectTab("Settings")
        expect(ui._active.Name == "Settings" and ui._active.ResultsCol.Visible, "Switching tabs carries the live search to the new page")
        ui:ClearSearch()
        for row, home in pairs(rows) do expect(row.Parent == home.Parent and row.LayoutOrder == home.Order, "Clearing search restores exact parent and order") end
        local badRow = nil
        for row, home in pairs(rows) do if home.Record.Label == "Aimbot Enabled" then badRow = row; break end end
        properties[badRow].FailParent = ui._active.ResultsCol
        ui:Search("enable aimbot")
        expect(ui._query == "" and badRow.Parent == rows[badRow].Parent, "A mid-filter exception rolls back the whole search")
        properties[badRow].FailParent = nil
        state:Set("Aimbot.Hitpart", "not-a-part")
        expect(state:Get("Aimbot.Hitpart") == "Head", "Invalid saved dropdown values fall back to the first option")
        for _, tab in ipairs(ui._tabs) do
            expect(ui:SelectTab(tab.Name) and ui._active.Name == tab.Name, "Every tab remains available without an access gate: " .. tab.Name)
        end
        ui:SelectTab("Combat")
        state:Set("Aimbot.Enabled", false)
        badRow:FindFirstChildOfClass("TextButton").Activated:Fire()
        expect(state:Get("Aimbot.Enabled"), "Aimbot controls can enable their feature directly")
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
        master:Dispose()
        local alive = 0
        for _, object in ipairs(instances) do if not properties[object].Destroyed and object ~= world and object ~= parent and object ~= camera then alive += 1 end end
        expect(alive == 0, "No UI instance, modal or temporary toast survives master disposal")
        print(string.format("PASS UI: %d assertions (%d controls, %d bound paths)", Test.Passed, count, boundCount))
        return Test.Passed
    end
    return Test
end
