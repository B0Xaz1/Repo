--!nonstrict
return function(services: any): any
    local dom, theme, state = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("StateStore")
    local bus = services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("VisualsPreview")
    local runService = game:GetService("RunService")
    local SAMPLE_TEAM = Color3.fromRGB(70, 150, 255)
    local VisualsPreview = { Frame = nil, _parts = {}, _initialized = false }

    local function rainbow(): Color3
        return Color3.fromHSV((os.clock() * 0.15) % 1, 0.75, 1)
    end
    local function sampleColor(config: any, fallback: Color3): Color3
        if config.Rainbow then return rainbow() end
        if config.UseTeamColor then return SAMPLE_TEAM end
        return fallback
    end
    local function paint()
        local frame = VisualsPreview.Frame
        if not frame then return end
        local menuOn = state:Peek("Settings.MenuVisible")
        local onVisuals = services:Get("UIEngine")._active and services:Get("UIEngine")._active.Name == "Visuals"
        frame.Visible = menuOn and onVisuals == true
        if not frame.Visible then return end
        local esp, chams = state:Peek("ESP"), state:Peek("Chams")
        local parts = VisualsPreview._parts
        local color = sampleColor(esp, esp.Color)
        local chamFill = sampleColor(chams, chams.FillColor)
        local espOn = esp.Enabled
        parts.Chams.Visible = chams.Enabled
        parts.Chams.BackgroundColor3 = chamFill
        parts.Box.Visible = espOn and esp.Box
        parts.BoxStroke.Color = color
        parts.Name.Visible = espOn and esp.Name
        parts.Name.TextColor3 = color
        parts.Distance.Visible = espOn and esp.Distance
        parts.Distance.TextColor3 = color
        parts.HealthBack.Visible = espOn and esp.Health
        parts.Health.Visible = espOn and esp.Health
        parts.Head.Visible = espOn and esp.HeadDot
        parts.Head.BackgroundColor3 = color
        parts.Tracer.Visible = espOn and esp.Tracers
        parts.Tracer.BackgroundColor3 = color
        parts.Look.Visible = espOn and esp.LookDir
        parts.Look.BackgroundColor3 = color
        parts.Tool.Visible = espOn and esp.Tool
        parts.Tool.TextColor3 = color
        parts.Skeleton.Visible = espOn and esp.Skeleton
        for _, bone in ipairs(parts.Bones) do bone.BackgroundColor3 = color end
        parts.Hint.Text = if espOn or chams.Enabled then "Live sample of enabled overlays" else "Enable ESP or chams to preview"
    end
    function VisualsPreview:Mount(root: Instance)
        if self.Frame then return self.Frame end
        local ui = services:Get("UIEngine")
        local frame = dom:Create("Frame", { Parent = root, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0.5, 398, 0.5, 8), Size = UDim2.fromOffset(188, 268), Visible = false })
        self.Frame = frame
        ui._visualsPreview = frame
        theme:BindToken(frame, "BackgroundColor3", "Bg")
        theme:BindToken(dom:CreateStroke(frame, theme:GetToken("Border")), "Color", "Border")
        dom:Create("UICorner", { Parent = frame, CornerRadius = UDim.new(0, 6) })
        local title = dom:Create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 18),
            Text = "ESP preview", Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left })
        theme:BindToken(title, "TextColor3", "Text")
        ui:MakeDraggable(frame, title)
        local stage = dom:Create("Frame", { Parent = frame, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 1, -58) })
        theme:BindToken(stage, "BackgroundColor3", "Panel")
        dom:Create("UICorner", { Parent = stage, CornerRadius = UDim.new(0, 4) })
        local chams = dom:Create("Frame", { Parent = stage, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 4), Size = UDim2.fromOffset(70, 132), BackgroundTransparency = 0.45 })
        dom:Create("UICorner", { Parent = chams, CornerRadius = UDim.new(0, 8) })
        local box = dom:Create("Frame", { Parent = stage, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 4), Size = UDim2.fromOffset(78, 140) })
        local boxStroke = dom:CreateStroke(box, theme:GetToken("Accent"), 1)
        local name = dom:Create("TextLabel", { Parent = stage, BackgroundTransparency = 1, Position = UDim2.new(0, 8, 0, 8), Size = UDim2.new(1, -16, 0, 14),
            Text = "Sample", Font = Enum.Font.GothamMedium, TextSize = 11 })
        local distance = dom:Create("TextLabel", { Parent = stage, BackgroundTransparency = 1, Position = UDim2.new(0, 8, 1, -22), Size = UDim2.new(1, -16, 0, 14),
            Text = "24 studs", Font = Enum.Font.Gotham, TextSize = 10 })
        local healthBack = dom:Create("Frame", { Parent = stage, BorderSizePixel = 0, Position = UDim2.new(0.5, -48, 0.5, -66), Size = UDim2.fromOffset(4, 132),
            BackgroundColor3 = Color3.fromRGB(20, 22, 26) })
        local health = dom:Create("Frame", { Parent = healthBack, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0.25, 0), Size = UDim2.new(1, 0, 0.75, 0),
            BackgroundColor3 = Color3.fromRGB(79, 222, 157) })
        local head = dom:Create("Frame", { Parent = stage, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, -58), Size = UDim2.fromOffset(8, 8) })
        dom:Create("UICorner", { Parent = head, CornerRadius = UDim.new(1, 0) })
        local tracer = dom:Create("Frame", { Parent = stage, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(2, 36) })
        local look = dom:Create("Frame", { Parent = stage, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0.5, 4, 0.5, -58), Size = UDim2.fromOffset(18, 2) })
        local tool = dom:Create("TextLabel", { Parent = stage, BackgroundTransparency = 1, Position = UDim2.new(0, 8, 1, -36), Size = UDim2.new(1, -16, 0, 12),
            Text = "Sword", Font = Enum.Font.Gotham, TextSize = 10 })
        local skeleton = dom:Create("Frame", { Parent = stage, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
        local bones = {}
        local function bone(x: number, y: number, w: number, h: number)
            local line = dom:Create("Frame", { Parent = skeleton, BorderSizePixel = 0, Position = UDim2.new(0.5, x, 0.5, y), Size = UDim2.fromOffset(w, h) })
            table.insert(bones, line)
        end
        bone(-1, -40, 2, 70)
        bone(-22, -18, 22, 2)
        bone(0, -18, 22, 2)
        bone(-10, 28, 2, 36)
        bone(8, 28, 2, 36)
        local hint = dom:Create("TextLabel", { Parent = frame, BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 246), Size = UDim2.new(1, -24, 0, 16),
            Text = "", Font = Enum.Font.Gotham, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left })
        theme:BindToken(hint, "TextColor3", "TextMuted")
        self._parts = { Chams = chams, Box = box, BoxStroke = boxStroke, Name = name, Distance = distance, HealthBack = healthBack,
            Health = health, Head = head, Tracer = tracer, Look = look, Tool = tool, Skeleton = skeleton, Bones = bones, Hint = hint }
        if not self._initialized then
            self._initialized = true
            local renderConn: RBXScriptConnection? = nil
            local function sync()
                paint()
                local on = VisualsPreview.Frame and VisualsPreview.Frame.Visible
                if on and not renderConn then
                    renderConn = runService.RenderStepped:Connect(paint)
                elseif not on and renderConn then
                    renderConn:Disconnect(); renderConn = nil
                end
            end
            scope:Add(function() if renderConn then renderConn:Disconnect(); renderConn = nil end end)
            scope:Add(bus:Subscribe("TabSelected", sync))
            scope:Add(state:Observe("Settings.MenuVisible", sync))
            self._sync = sync
        end
        if self._sync then self._sync() else paint() end
        return frame
    end
    function VisualsPreview:Destroy() scope:Dispose() end
    scope:Add(function() VisualsPreview.Frame = nil; table.clear(VisualsPreview._parts) end)
    return VisualsPreview
end
