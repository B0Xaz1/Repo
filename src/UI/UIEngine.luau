--!nonstrict
local TABS = {
    { Name = "Combat", Path = "src/UI/Tabs/CombatTab.luau" }, { Name = "Visuals", Path = "src/UI/Tabs/VisualsTab.luau" },
    { Name = "Movement", Path = "src/UI/Tabs/MovementTab.luau" }, { Name = "Players", Path = "src/UI/Tabs/PlayersTab.luau" },
    { Name = "Game", Path = "src/UI/Tabs/GameTab.luau" }, { Name = "Utility", Path = "src/UI/Tabs/UtilityTab.luau" },
    { Name = "Settings", Path = "src/UI/Tabs/SettingsTab.luau" },
}

return function(services: any): any
    local dom, theme, state, environment = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("StateStore"), services:Get("Environment")
    local bus, load = services:Get("EventBus"), services:Get("Require")
    local scope = services:Get("Disposer"):CreateChild("UIEngine")
    local input, workspace = game:GetService("UserInputService"), game:GetService("Workspace")
    local UIEngine = { _root = nil, _main = nil, _tabs = {}, _tabByName = {}, _active = nil, _controls = {}, _dropdowns = {},
        _query = "", _searchHeaders = {}, _toasts = {}, _pending = {}, _toastId = 0, _initialized = false, _constructing = false }

    local function viewport(): Vector2 return if workspace.CurrentCamera then workspace.CurrentCamera.ViewportSize else Vector2.new(1280, 720) end
    local function restoreSearch()
        for _, record in pairs(UIEngine._controls) do
            if record.HomeParent then
                local ok = pcall(function() record.Row.Parent = record.HomeParent; record.Row.LayoutOrder = record.HomeOrder end)
                if not ok then warn("[B0Xaz][Search restore] A source row was destroyed") end
                record.HomeParent, record.HomeOrder = nil, nil
            end
        end
        for _, header in ipairs(UIEngine._searchHeaders) do dom:DestroyInstance(header) end
        table.clear(UIEngine._searchHeaders)
        for _, tab in ipairs(UIEngine._tabs) do tab.Columns.Visible, tab.ResultsCol.Visible = true, false end
    end
    function UIEngine:RegisterControl(row: GuiObject, label: string): any
        local node: Instance? = row.Parent
        local tabName, sectionName = nil, "General"
        while node do
            if sectionName == "General" and node:GetAttribute("B0XazSection") then sectionName = node:GetAttribute("B0XazSection") end
            if node:GetAttribute("B0XazTab") then tabName = node:GetAttribute("B0XazTab"); break end
            node = node.Parent
        end
        local connection = { Connected = true }
        if tabName then self._controls[row] = { Row = row, Label = label, TabName = tabName, SectionName = sectionName } end
        function connection:Disconnect()
            if not self.Connected then return end
            self.Connected = false
            UIEngine._controls[row] = nil
        end
        return connection
    end
    function UIEngine:RegisterDropdownClose(callback: () -> ()): any
        self._dropdowns[callback] = true
        local connection = { Connected = true }
        function connection:Disconnect() self.Connected = false; UIEngine._dropdowns[callback] = nil end
        return connection
    end
    function UIEngine:CloseAllDropdownsExcept(except: (() -> ())?)
        for callback in pairs(self._dropdowns) do
            if callback ~= except then local ok, message = pcall(callback); if not ok then warn("[B0Xaz][Dropdown] " .. tostring(message)) end end
        end
    end
    function UIEngine:Search(query: string)
        self._query = tostring(query):lower():gsub("^%s+", ""):gsub("%s+$", "")
        self:CloseAllDropdownsExcept(nil)
        local ok, message = pcall(function()
            restoreSearch()
            if self._query == "" or not self._active then return end
            local results = {}
            for _, record in pairs(self._controls) do
                local tab = self._tabByName[record.TabName]
                if not tab or not record.Row.Parent then continue end
                local searchable = (record.TabName .. " " .. record.SectionName .. " " .. record.Label):lower()
                local matches = true
                for word in self._query:gmatch("%S+") do if not searchable:find(word, 1, true) then matches = false; break end end
                if matches then table.insert(results, record) end
            end
            table.sort(results, function(a: any, b: any)
                if a.TabName ~= b.TabName then return self._tabByName[a.TabName].Index < self._tabByName[b.TabName].Index end
                if a.SectionName ~= b.SectionName then return a.SectionName < b.SectionName end
                return a.Row.LayoutOrder < b.Row.LayoutOrder
            end)
            local active, previousGroup, order = self._active, nil, 0
            active.Columns.Visible, active.ResultsCol.Visible = false, true
            for _, record in ipairs(results) do
                local group = record.TabName .. " / " .. record.SectionName
                if group ~= previousGroup then
                    order += 1
                    local header = dom:Create("TextLabel", { Parent = active.ResultsCol, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30),
                        LayoutOrder = order, Text = group, Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left })
                    theme:BindToken(header, "TextColor3", "Accent")
                    table.insert(self._searchHeaders, header)
                    previousGroup = group
                end
                order += 1
                record.HomeParent, record.HomeOrder = record.Row.Parent, record.Row.LayoutOrder
                record.Row.Parent, record.Row.LayoutOrder = active.ResultsCol, order
            end
            if #results == 0 then
                local empty = dom:Create("TextLabel", { Parent = active.ResultsCol, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 80),
                    Text = "No matching controls.\nTry a feature, section, or tab name.", TextSize = 12, Font = Enum.Font.Gotham, TextWrapped = true })
                theme:BindToken(empty, "TextColor3", "TextMuted"); table.insert(self._searchHeaders, empty)
            end
            active.Page.CanvasPosition = Vector2.zero
        end)
        if not ok then
            -- A partial filter is worse than no filter: always return rows to their exact source locations on error.
            restoreSearch(); self._query = ""
            if self._searchBox then self._searchBox.Text = "" end
            self:Notify("Search reset", tostring(message), 5, theme:GetToken("Warning"))
        end
    end
    function UIEngine:ClearSearch()
        restoreSearch(); self._query = ""
        if self._searchBox then self._searchBox.Text = "" end
    end
    function UIEngine:SelectTab(name: string): boolean
        local tab = self._tabByName[name]
        if not tab then return false end
        restoreSearch(); self:CloseAllDropdownsExcept(nil)
        self._active = tab
        for _, candidate in ipairs(self._tabs) do
            local active = candidate == tab
            candidate.Page.Visible, candidate.Underline.Visible = active, active
            candidate.Button.BackgroundTransparency = 1
            theme:BindToken(candidate.Button, "TextColor3", if active then "Text" else "TextMuted")
        end
        if self._query ~= "" then self:Search(self._query) end
        bus:Publish("TabSelected", name)
        return true
    end
    function UIEngine:MakeDraggable(frame: GuiObject, handle: GuiObject): any
        local owner = scope:CreateChild("Window drag")
        local dragStart: Vector2? = nil
        local startPos: UDim2? = nil
        local activeTouch: InputObject? = nil
        owner:Connect(handle.InputBegan, function(event: InputObject)
            if event.UserInputType ~= Enum.UserInputType.MouseButton1 and event.UserInputType ~= Enum.UserInputType.Touch then return end
            -- Delta against the live UDim2, not AbsolutePosition: mixing those spaces jumps the window by the topbar inset on the first click.
            dragStart, startPos = environment:GetPointerLocation(event), frame.Position
            activeTouch = if event.UserInputType == Enum.UserInputType.Touch then event else nil
        end)
        owner:ConnectImmediate(input.InputChanged, function(event: InputObject)
            if not dragStart or not startPos or not frame.Parent then return end
            if activeTouch and event ~= activeTouch then return end
            if event.UserInputType ~= Enum.UserInputType.MouseMovement and event.UserInputType ~= Enum.UserInputType.Touch then return end
            local delta, size, screen = environment:GetPointerLocation(event) - dragStart, frame.AbsoluteSize, viewport()
            local scale = math.max(if UIEngine._scale then UIEngine._scale.Scale else 1, 0.01)
            local centre = Vector2.new(startPos.X.Scale * screen.X + startPos.X.Offset + delta.X / scale,
                startPos.Y.Scale * screen.Y + startPos.Y.Offset + delta.Y / scale)
            local minimum = Vector2.new(math.min(size.X / 2 + 8, screen.X / 2), math.min(size.Y / 2 + 8, screen.Y / 2))
            centre = Vector2.new(math.clamp(centre.X, minimum.X, screen.X - minimum.X), math.clamp(centre.Y, minimum.Y, screen.Y - minimum.Y))
            frame.Position = UDim2.new(startPos.X.Scale, centre.X - startPos.X.Scale * screen.X, startPos.Y.Scale, centre.Y - startPos.Y.Scale * screen.Y)
        end)
        owner:Connect(input.InputEnded, function(event: InputObject)
            if event.UserInputType == Enum.UserInputType.MouseButton1 or event == activeTouch then dragStart, startPos, activeTouch = nil, nil, nil end
        end)
        owner:Connect(frame.Destroying, function() owner:Dispose() end)
        return owner
    end
    local function removeToast(record: any)
        local index = table.find(UIEngine._toasts, record)
        if index then table.remove(UIEngine._toasts, index) end
        record.Scope:Dispose()
    end
    function UIEngine:Notify(title: string, message: string, duration: number?, color: Color3?)
        if scope:IsDisposed() then return end
        if not self._toastRoot then
            table.insert(self._pending, { title, message, duration, color })
            if #self._pending > 8 then table.remove(self._pending, 1) end
            return
        end
        self._toastId += 1
        local owner = scope:CreateChild("Toast")
        local frame = dom:Create("Frame", { Parent = self._toastRoot, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = -self._toastId, BackgroundColor3 = theme:GetToken("Panel") })
        theme:BindToken(frame, "BackgroundColor3", "Panel")
        dom:Create("UICorner", { Parent = frame, CornerRadius = UDim.new(0, 3) })
        local stroke = dom:CreateStroke(frame, color or theme:GetToken("Accent"), 1)
        if not color then theme:BindToken(stroke, "Color", "Accent") end
        dom:CreatePadding(frame, 12, 14)
        dom:Create("UIListLayout", { Parent = frame, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder })
        local heading = dom:Create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16),
            Text = tostring(title), Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = color or theme:GetToken("Accent"), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0 })
        if not color then theme:BindToken(heading, "TextColor3", "Accent") end
        local body = dom:Create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            Text = tostring(message), TextWrapped = true, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 })
        theme:BindToken(body, "TextColor3", "TextDim")
        owner:Add(function() dom:DestroyInstance(frame) end)
        local record = { Frame = frame, Scope = owner }
        table.insert(self._toasts, record)
        if #self._toasts > 4 then removeToast(self._toasts[1]) end
        owner:Delay(math.clamp(duration or 4, 1, 20), function() removeToast(record) end)
    end
    local function resize()
        if not UIEngine._main then return end
        local screen = viewport()
        local requested = math.clamp(state:Get("Settings.UIScale"), 0.6, 1.5)
        local width = if environment:IsMobile() then math.clamp(screen.X / requested - 28, 320, 760) else 760
        local height = math.clamp(screen.Y / requested - 40, 380, 540)
        local scale = math.max(0.25, math.min(requested, (screen.X - 24) / width, (screen.Y - 24) / height))
        UIEngine._main.Size, UIEngine._scale.Scale = UDim2.fromOffset(width, height), scale
        local stacked = width < 620
        for _, tab in ipairs(UIEngine._tabs) do
            tab.ColumnLayout.FillDirection = if stacked then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
            tab.LeftCol.Size, tab.RightCol.Size = UDim2.new(if stacked then 1 else 0.5, if stacked then 0 else -6, 0, 0), UDim2.new(if stacked then 1 else 0.5, if stacked then 0 else -6, 0, 0)
        end
        UIEngine._toastRoot.Size = UDim2.new(0, math.min(330, screen.X - 32), 1, -40)
    end
    function UIEngine:ConstructInterface()
        if self._root or self._constructing then return end
        self._constructing = true
        local parent = assert(environment:GetSafeGuiParent(), "No writable GUI parent is available")
        local root = dom:Create("ScreenGui", { Parent = parent, Name = dom:RandomName(), ResetOnSpawn = false, IgnoreGuiInset = true,
            DisplayOrder = 1000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
        self._root = root
        theme:RegisterRoot(root)
        local main = dom:Create("Frame", { Parent = root, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(760, 540), BackgroundColor3 = theme:GetToken("Bg"), Active = true })
        self._main = main
        theme:BindToken(main, "BackgroundColor3", "Bg"); dom:Create("UICorner", { Parent = main, CornerRadius = UDim.new(0, 6) })
        theme:BindToken(dom:CreateStroke(main, theme:GetToken("Border")), "Color", "Border")
        self._scale = dom:Create("UIScale", { Parent = main, Scale = 1 })
        local titleBar = dom:Create("Frame", { Parent = main, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 42), Active = true })
        local brand = dom:Create("TextLabel", { Parent = titleBar, BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 11), Size = UDim2.new(1, -200, 0, 22),
            Text = "B0Xaz Universal", Font = Enum.Font.GothamMedium, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
        theme:BindToken(brand, "TextColor3", "Text")
        local close = dom:Create("TextButton", { Parent = titleBar, Text = "X", AutoButtonColor = false, BackgroundTransparency = 1, Position = UDim2.new(1, -28, 0, 9), Size = UDim2.fromOffset(20, 22), Font = Enum.Font.GothamMedium, TextSize = 13 })
        theme:BindToken(close, "TextColor3", "TextMuted")
        scope:Connect(close.Activated, function() state:Set("Settings.MenuVisible", false) end)
        local search = dom:Create("TextBox", { Parent = titleBar, BorderSizePixel = 0, Position = UDim2.new(1, -168, 0, 10), Size = UDim2.fromOffset(132, 22), ClearTextOnFocus = false,
            Text = "", PlaceholderText = "search...", TextSize = 12, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left })
        self._searchBox = search
        theme:BindToken(search, "BackgroundColor3", "Elem"); theme:BindToken(search, "TextColor3", "Text"); theme:BindToken(search, "PlaceholderColor3", "TextMuted")
        theme:BindToken(dom:CreateStroke(search, theme:GetToken("BorderDim")), "Color", "BorderDim")
        dom:Create("UICorner", { Parent = search, CornerRadius = UDim.new(0, 3) }); dom:CreatePadding(search, 0, 8)
        scope:Connect(search:GetPropertyChangedSignal("Text"), function() UIEngine:Search(search.Text) end)
        self:MakeDraggable(main, titleBar)
        local strip = dom:Create("ScrollingFrame", { Parent = main, BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 42), Size = UDim2.new(1, -16, 0, 28),
            ScrollBarThickness = 0, CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X })
        theme:BindToken(strip, "ScrollBarImageColor3", "Accent")
        dom:Create("UIListLayout", { Parent = strip, FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
        local divider = dom:Create("Frame", { Parent = main, BorderSizePixel = 0, Position = UDim2.fromOffset(16, 70), Size = UDim2.new(1, -32, 0, 1) })
        theme:BindToken(divider, "BackgroundColor3", "BorderDim")
        for index, entry in ipairs(TABS) do
            local button = dom:Create("TextButton", { Parent = strip, BackgroundTransparency = 1, BorderSizePixel = 0, Text = entry.Name, AutoButtonColor = false, Font = Enum.Font.GothamMedium, TextSize = 12, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = index })
            dom:CreatePadding(button, 0, 8, 0, 8)
            local underline = dom:Create("Frame", { Parent = button, BorderSizePixel = 0, Position = UDim2.new(0.14, 0, 1, -2), Size = UDim2.new(0.72, 0, 0, 2), Visible = false })
            theme:BindToken(underline, "BackgroundColor3", "Accent")
            local page = dom:Create("ScrollingFrame", { Parent = main, BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(14, 78), Size = UDim2.new(1, -28, 1, -96),
                Visible = false, ScrollBarThickness = 3, CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y })
            page:SetAttribute("B0XazTab", entry.Name)
            theme:BindToken(page, "ScrollBarImageColor3", "Accent")
            dom:CreatePadding(page, 2, 7, 12, 1)
            dom:Create("UIListLayout", { Parent = page, SortOrder = Enum.SortOrder.LayoutOrder })
            local columns = dom:Create("Frame", { Parent = page, BackgroundTransparency = 1, Size = UDim2.new(1, -1, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 0 })
            local columnLayout = dom:Create("UIListLayout", { Parent = columns, FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder })
            local left = dom:Create("Frame", { Parent = columns, BackgroundTransparency = 1, Size = UDim2.new(0.5, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 0 })
            local right = dom:Create("Frame", { Parent = columns, BackgroundTransparency = 1, Size = UDim2.new(0.5, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
            local results = dom:Create("Frame", { Parent = page, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, LayoutOrder = 1 })
            for _, column in ipairs({ left, right, results }) do dom:Create("UIListLayout", { Parent = column, Padding = UDim.new(0, if column == results then 4 else 12), SortOrder = Enum.SortOrder.LayoutOrder }) end
            local tab = { Name = entry.Name, Button = button, Underline = underline, Page = page, LeftCol = left, RightCol = right,
                ResultsCol = results, Columns = columns, ColumnLayout = columnLayout, Index = index }
            table.insert(self._tabs, tab); self._tabByName[tab.Name] = tab
            scope:Connect(button.Activated, function() UIEngine:SelectTab(tab.Name) end)
            print("[B0Xaz][Trace] step start tab " .. entry.Name)
            local factory = load(entry.Path)
            local ok, result = pcall(factory, services, tab)
            if not ok then error("Init Error in '" .. entry.Path .. "': " .. tostring(result)) end
            print("[B0Xaz][Trace] step end tab " .. entry.Name)
        end
        local footer = dom:Create("TextLabel", { Parent = main, BackgroundTransparency = 1, Position = UDim2.new(0, 18, 1, -18), Size = UDim2.new(1, -96, 0, 14),
            Font = Enum.Font.Code, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left })
        theme:BindToken(footer, "TextColor3", "TextMuted")
        local function updateFooter() footer.Text = environment:FormatKeybindName(state:Get("Settings.MenuKeybind")) .. "  menu     " .. environment:FormatKeybindName(state:Get("Settings.UnloadKeybind")) .. "  unload" end
        updateFooter(); scope:Add(state:Observe("Settings.MenuKeybind", updateFooter)); scope:Add(state:Observe("Settings.UnloadKeybind", updateFooter))
        self._versionLabel = dom:Create("TextLabel", { Parent = main, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 1, -18), Size = UDim2.fromOffset(72, 14),
            Text = "v" .. services.Version, Font = Enum.Font.Code, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Right })
        theme:BindToken(self._versionLabel, "TextColor3", "TextMuted")
        self._toastRoot = dom:Create("Frame", { Parent = root, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.new(0, 330, 1, -40) })
        dom:Create("UIListLayout", { Parent = self._toastRoot, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder })
        local reopen = dom:Create("TextButton", { Parent = root, BorderSizePixel = 0, Position = UDim2.new(0, 16, 1, -52), Size = UDim2.fromOffset(78, 34),
            Text = "B0Xaz", TextSize = 13, Font = Enum.Font.GothamBold })
        theme:BindToken(reopen, "BackgroundColor3", "Panel"); theme:BindToken(reopen, "TextColor3", "Accent")
        theme:BindToken(dom:CreateStroke(reopen, theme:GetToken("Border")), "Color", "Border")
        dom:Create("UICorner", { Parent = reopen, CornerRadius = UDim.new(0, 3) })
        scope:Connect(reopen.Activated, function() state:Set("Settings.MenuVisible", not state:Get("Settings.MenuVisible")) end)
        local function updateVisibility(value: boolean) main.Visible = value; reopen.Visible = not value or environment:IsMobile(); if not value then UIEngine:CloseAllDropdownsExcept(nil) end end
        scope:Add(state:Observe("Settings.MenuVisible", updateVisibility)); updateVisibility(state:Get("Settings.MenuVisible"))
        scope:Add(state:Observe("Settings.UIScale", resize))
        local function bindViewport()
            scope:Unbind("Viewport")
            if workspace.CurrentCamera then scope:Bind("Viewport", scope:Connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), resize)) end
            resize()
        end
        scope:Connect(workspace:GetPropertyChangedSignal("CurrentCamera"), bindViewport); bindViewport()
        if self._tabs[1] then self:SelectTab(self._tabs[1].Name) end
        self._constructing = false
        local pending = self._pending; self._pending = {}
        for _, notification in ipairs(pending) do self:Notify(table.unpack(notification, 1, 4)) end
        self:Notify("B0Xaz Universal", "Ready. Every active feature is owned by this session.", 4)
    end
    function UIEngine:Initialize()
        if self._initialized then return end
        self._initialized = true
        -- HotkeyService is the single input dispatcher for Menu; duplicating it here would toggle twice.
    end
    function UIEngine:Destroy() scope:Dispose() end
    scope:Add(bus:Subscribe("Notify", function(...: any) UIEngine:Notify(...) end))
    scope:Add(function()
        restoreSearch()
        if UIEngine._root then dom:DestroyInstance(UIEngine._root) end
        UIEngine._root, UIEngine._main, UIEngine._toastRoot = nil, nil, nil
        table.clear(UIEngine._controls); table.clear(UIEngine._dropdowns); table.clear(UIEngine._toasts); table.clear(UIEngine._pending)
    end)
    return UIEngine
end
