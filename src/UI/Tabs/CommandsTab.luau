return function(services: any, tab: any): any
    local load = services:Get("Require")
    local dom, theme, bus = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("EventBus")
    local section = load("src/UI/Components/Section.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)
    local commandService = services:Get("CommandService")
    local scope = services:Get("Disposer"):CreateChild("Commands tab")

    local listPanel = section:Create(tab.LeftCol, "Command list")
    local search = textbox(listPanel, "Filter commands", "")
    local commandList = dom:Create("ScrollingFrame", { Parent = listPanel, BorderSizePixel = 0, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 220), AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.fromOffset(0, 0), ScrollBarThickness = 3 })
    dom:Create("UIListLayout", { Parent = commandList, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })
    theme:BindToken(commandList, "ScrollBarImageColor3", "Accent")

    local preview = section:Create(tab.RightCol, "Console")
    local inputRow = dom:Create("Frame", { Parent = preview, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0 })
    local input = dom:Create("TextBox", { Parent = inputRow, BorderSizePixel = 0, BackgroundColor3 = theme:GetToken("Elem"), Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, -136, 0, 26), PlaceholderText = "Type command...", Text = "", Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left })
    theme:BindToken(input, "BackgroundColor3", "Elem")
    theme:BindToken(input, "TextColor3", "Text")
    theme:BindToken(input, "PlaceholderColor3", "TextMuted")
    theme:BindToken(dom:CreateStroke(input, theme:GetToken("BorderDim")), "Color", "BorderDim")
    dom:Create("UICorner", { Parent = input, CornerRadius = UDim.new(0, 2) })
    dom:CreatePadding(input, 0, 8)

    local runButton = dom:Create("TextButton", { Parent = inputRow, BorderSizePixel = 0, Position = UDim2.new(1, -64, 0, 0), Size = UDim2.fromOffset(60, 26), Text = "Run", Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = false })
    section:StyleButton(runButton, scope)
    local clearButton = dom:Create("TextButton", { Parent = inputRow, BorderSizePixel = 0, Position = UDim2.new(1, -128, 0, 0), Size = UDim2.fromOffset(60, 26), Text = "Clear", Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = false })
    section:StyleButton(clearButton, scope)

    local log = dom:Create("ScrollingFrame", { Parent = preview, BorderSizePixel = 0, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 160), AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.fromOffset(0, 0), ScrollBarThickness = 3, LayoutOrder = 1 })
    theme:BindToken(log, "ScrollBarImageColor3", "Accent")
    dom:Create("UIListLayout", { Parent = log, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })

    local info = section:Create(tab.RightCol, "Command details")
    local detailText = section:Info(info, "Select a command to see its usage.")
    local recent = section:Create(tab.RightCol, "Recent")
    local recentText = section:Info(recent, "No recent commands yet.")

    local rows = {}
    local function renderList()
        local query = tostring(search.Box.Text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if #rows == 0 then
            for index, entry in ipairs(commandService:GetCommandList()) do
                local row = dom:Create("TextButton", { Parent = commandList, BorderSizePixel = 0, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = "", AutoButtonColor = false, LayoutOrder = index })
                local body = dom:Create("Frame", { Parent = row, BorderSizePixel = 0, BackgroundColor3 = theme:GetToken("Panel"), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 0 })
                theme:BindToken(body, "BackgroundColor3", "Panel")
                dom:Create("UICorner", { Parent = body, CornerRadius = UDim.new(0, 3) })
                theme:BindToken(dom:CreateStroke(body, theme:GetToken("BorderDim")), "Color", "BorderDim")
                local name = dom:Create("TextLabel", { Parent = body, BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -92, 0, 16), Text = entry.Name, Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left })
                theme:BindToken(name, "TextColor3", "Accent")
                local category = dom:Create("TextLabel", { Parent = body, BackgroundTransparency = 1, Position = UDim2.new(1, -84, 0, 6), Size = UDim2.fromOffset(72, 14), Text = entry.Category, Font = Enum.Font.Gotham, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Right })
                theme:BindToken(category, "TextColor3", "TextMuted")
                local usage = dom:Create("TextLabel", { Parent = body, BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 23), Size = UDim2.new(1, -76, 0, 12), Text = entry.Usage, Font = Enum.Font.Code, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
                theme:BindToken(usage, "TextColor3", "TextMuted")
                local run = dom:Create("TextButton", { Parent = body, BorderSizePixel = 0, Position = UDim2.new(1, -62, 0, 9), Size = UDim2.fromOffset(52, 22), Text = "Run", Font = Enum.Font.GothamMedium, TextSize = 11, AutoButtonColor = false })
                section:StyleButton(run, scope)
                scope:Connect(run.Activated, function()
                    commandService:Execute(entry.Name, "menu")
                end)
                scope:Connect(row.Activated, function()
                    detailText:Set(`{entry.Name}  /  {entry.Category}\n{entry.Usage}`)
                    input.Text = entry.Name
                end)
                table.insert(rows, { Row = row, Searchable = (`{entry.Name} {entry.Category} {entry.Usage}`):lower() })
            end
        end
        for _, record in ipairs(rows) do
            local show = query == "" or record.Searchable:find(query, 1, true) ~= nil
            if record.Row.Visible ~= show then
                if not show then services:Get("Motion"):Reset(record.Row) end
                record.Row.Visible = show
            end
        end
    end

    local logRows, logOrder = {}, 0

    local function appendLog(message: string)
        logOrder += 1
        local label = dom:Create("TextLabel", { Parent = log, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = message, TextWrapped = true, LayoutOrder = logOrder, Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left })
        theme:BindToken(label, "TextColor3", "Text")
        table.insert(logRows, label)
        if #logRows > 80 then dom:DestroyInstance(table.remove(logRows, 1)) end
    end

    local function updateRecent()
        local history = commandService:GetRecentHistory()
        if #history == 0 then recentText:Set("No recent commands yet."); return end
        recentText:Set(table.concat(history, "\n"))
    end

    scope:Add(bus:Subscribe("CommandOutput", function(message: string)
        appendLog(message)
        updateRecent()
    end))

    scope:ConnectImmediate(log:GetPropertyChangedSignal("AbsoluteCanvasSize"), function()
        log.CanvasPosition = Vector2.new(0, math.max(0, log.AbsoluteCanvasSize.Y))
    end)
    scope:ConnectImmediate(search.Box:GetPropertyChangedSignal("Text"), renderList)
    scope:Connect(runButton.Activated, function()
        local command = input.Text
        if command == "" then return end
        local ok, result = commandService:Execute(command, "menu")
        if ok == false then appendLog(`error: {result}`) end
        input.Text = ""
        input:CaptureFocus()
    end)
    scope:Connect(clearButton.Activated, function()
        for _, child in ipairs(log:GetChildren()) do
            if child:IsA("GuiObject") and child ~= log:FindFirstChildOfClass("UIListLayout") then dom:DestroyInstance(child) end
        end
        table.clear(logRows)
        commandService:Execute("/clear", "menu")
        updateRecent()
    end)
    scope:Connect(input.FocusLost, function(enterPressed: boolean)
        if not enterPressed then return end
        local command = input.Text
        if command == "" then return end
        commandService:Execute(command, "menu")
        input.Text = ""
    end)

    renderList()
    updateRecent()
    return { Name = tab.Name }
end
