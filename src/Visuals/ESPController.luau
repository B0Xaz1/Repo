local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CONFIG = table.freeze({
    -- ESP follows the render frame with no timer-based visual cadence. Expensive full bounds are
    -- rebased only after a meaningful spatial/viewport change; root projection interpolates the
    -- cached box on every frame in between.
    BOUNDS_ROOT_REBASE_DISTANCE = 24,
    BOUNDS_CAMERA_REBASE_DISTANCE = 24,
    BOUNDS_DEPTH_REBASE_RATIO = 0.25,
    VISIBILITY_POSITION_EPSILON = 2,
    VISIBILITY_CAMERA_EPSILON = 2,
    VISIBILITY_LOOK_DOT = 0.995,
    TEXT_SIZE = 14,
    -- This is intentionally an activity estimate. Roblox does not expose another client's window focus to an ESP client.
    AFK_IDLE_SECONDS = 60,
    AFK_POSITION_EPSILON = 1.25,
    AFK_ACTIVITY_SPEED = 1,
    -- Four compact status rows fit without allocating the oversized native-label surface used
    -- by the prior readout experiment.
    READOUT_WIDTH = 168,
    READOUT_HEIGHT = 62,
    -- Some executors reset their scheduler target after an overlay becomes visible. These finite
    -- repairs happen only on a hidden-to-visible transition, never in the render hot path.
    OVERLAY_FRAME_RATE_REPAIR_DELAYS = { 0.15, 0.6 },
    BOX_THICKNESS = 1,
    CORNER_WIDTH_FACTOR = 0.26,
    CORNER_HEIGHT_FACTOR = 0.2,
    HEALTH_BAR_INNER_WIDTH = 2,
    HEALTH_BAR_OFFSET = 7,
    HEALTH_LOW = Color3.fromRGB(247, 87, 105),
    HEALTH_HIGH = Color3.fromRGB(79, 222, 157),
    MAX_BOX_ASPECT_RATIO = 2.5,
    CHAMS_FILL_TRANSPARENCY = 0.66,
    CHAMS_OUTLINE_TRANSPARENCY = 0.05,
    -- Direct body-part names deliberately exclude Tool and accessory geometry. Those instances
    -- can be extremely long and were the source of the occasional screen-spanning ESP box.
    BODY_PART_NAMES = { "Head", "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
        "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
        "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" },
    -- The common full-box route uses lightweight native Frames in the one shared ScreenGui beside
    -- its native status labels. Executor Drawing is retained only for the optional corner style
    -- (and as a full-box fallback if no safe GUI parent is available).
    BASE_DRAWINGS = { Box = "Square", Corner1 = "Line", Corner2 = "Line", Corner3 = "Line", Corner4 = "Line",
        Corner5 = "Line", Corner6 = "Line", Corner7 = "Line", Corner8 = "Line" },
})

return function(services: any): any
    local state, tracker, pool, filter = services:Get("StateStore"), services:Get("PlayerTracker"), services:Get("DrawingPool"), services:Get("TargetFilter")
    local scheduler, bus, environment = services:Get("TaskScheduler"), services:Get("EventBus"), services:Get("Environment")
    local scope = services:Get("Disposer"):CreateChild("ESPController")
    local ESPController = { _records = {}, _initialized = false, _chamsAvailable = true, _idle = true, _menuCovered = false, _job = nil, _textGui = nil,
        _frameRateRepairQueued = false }

    -- Visibility transitions can make some executors reapply their 60-FPS fallback after the
    -- camera-motion repair has already run. Coalesce the per-target transitions into two delayed
    -- recovery writes; no target rendering is skipped or rate-limited.
    local function requestOverlayFrameRateRepair()
        if ESPController._frameRateRepairQueued then return end
        ESPController._frameRateRepairQueued = true
        for index, delay in ipairs(CONFIG.OVERLAY_FRAME_RATE_REPAIR_DELAYS) do
            local finalRepair = index == #CONFIG.OVERLAY_FRAME_RATE_REPAIR_DELAYS
            scope:Delay(delay, function()
                if scope:IsDisposed() then return end
                environment:RepairFrameRate()
                if finalRepair then ESPController._frameRateRepairQueued = false end
            end)
        end
    end

    local function ensureTextGui(): ScreenGui?
        local gui = ESPController._textGui
        if gui and gui.Parent then return gui end
        local parent = environment:GetSafeGuiParent()
        if not parent then return nil end
        gui = Instance.new("ScreenGui")
        gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "B0XazESPReadouts", false, true
        gui.DisplayOrder, gui.ZIndexBehavior = 1001, Enum.ZIndexBehavior.Sibling
        gui.Parent = parent
        ESPController._textGui = gui
        scope:Bind("ESP readouts", gui)
        return gui
    end

    local function ensureReadout(record: any): TextLabel?
        local label = record.ReadoutLabel
        if label and label.Parent then return label end
        local gui = ensureTextGui()
        if not gui then return nil end
        label = Instance.new("TextLabel")
        label.Name, label.BackgroundTransparency, label.BorderSizePixel = "B0XazReadout", 1, 0
        label.AnchorPoint, label.Size = Vector2.new(0.5, 1), UDim2.fromOffset(CONFIG.READOUT_WIDTH, CONFIG.READOUT_HEIGHT)
        label.Font, label.TextSize = Enum.Font.Gotham, CONFIG.TEXT_SIZE
        label.TextXAlignment, label.TextYAlignment = Enum.TextXAlignment.Center, Enum.TextYAlignment.Bottom
        -- Text strokes are expensive to rasterize across a crowd. The compact readout deliberately
        -- uses the overlay color without a stroke so native text remains the light path.
        label.TextStrokeTransparency, label.ZIndex = 1, 5
        label.Visible, label.Parent = false, gui
        record.ReadoutLabel = label
        record.ReadoutAppliedText, record.ReadoutX, record.ReadoutY, record.ReadoutColor = nil, nil, nil, nil
        record.Scope:Add(label)
        return label
    end

    local function drawReadout(record: any, text: string, x: number, y: number, color: Color3)
        local label = ensureReadout(record)
        if not label then return end
        local roundedX, roundedY = math.round(x), math.round(y)
        if record.ReadoutAppliedText ~= text then label.Text, record.ReadoutAppliedText = text, text end
        if record.ReadoutX ~= roundedX or record.ReadoutY ~= roundedY then
            label.Position, record.ReadoutX, record.ReadoutY = UDim2.fromOffset(roundedX, roundedY), roundedX, roundedY
        end
        if record.ReadoutColor ~= color then label.TextColor3, record.ReadoutColor = color, color end
        if not label.Visible then
            label.Visible = true
            requestOverlayFrameRateRepair()
        end
        record.ReadoutShown = true
    end

    local function hideReadout(record: any)
        local label = record.ReadoutLabel
        if label and label.Visible then label.Visible = false end
    end

    local function hideNativeGeometry(record: any)
        if record.NativeBoxEdges then
            for _, edge in ipairs(record.NativeBoxEdges) do
                if edge.Visible then edge.Visible = false end
            end
        end
        if record.NativeHealthBar and record.NativeHealthBar.Visible then record.NativeHealthBar.Visible = false end
    end

    local function hideDrawings(record: any)
        hideNativeGeometry(record)
        for _, object in pairs(record.Drawings) do
            if object.Visible then object.Visible = false end
        end
        for _, last in pairs(record.Last) do last.Visible = false end
        hideReadout(record)
    end

    local function disableChams(record: any)
        if record.Highlight and record.Highlight.Enabled then record.Highlight.Enabled = false end
    end

    local function hide(record: any)
        hideDrawings(record)
        disableChams(record)
    end

    local function hideAll()
        for _, record in pairs(ESPController._records) do hide(record) end
    end

    local function createRecord(player: Player)
        if ESPController._records[player] or (player == Players.LocalPlayer and state:Peek("ESP.ShowSelf") ~= true) then return end
        local owner = scope:CreateChild(`ESP {player.UserId}`)
        local record = { Player = player, Scope = owner, Drawings = {}, Last = {}, Shown = {}, ReadoutLabel = nil, ReadoutShown = false,
            ReadoutText = nil, ReadoutAppliedText = nil, ReadoutX = nil, ReadoutY = nil, ReadoutColor = nil, ReadoutName = nil, ReadoutDistance = nil,
            ReadoutHealth = nil, ReadoutStatus = nil, ReadoutTool = nil, NativeBoxEdges = nil, NativeBoxShown = false,
            NativeBoxX = nil, NativeBoxY = nil, NativeBoxWidth = nil, NativeBoxHeight = nil, NativeBoxColor = nil,
            NativeHealthBar = nil, NativeHealthShown = false, NativeHealthX = nil, NativeHealthY = nil,
            NativeHealthWidth = nil, NativeHealthHeight = nil, NativeHealthColor = nil, Highlight = nil,
            BoundsCharacter = nil, BoundsCamera = nil, BoundsX = nil, BoundsY = nil, BoundsWidth = nil, BoundsHeight = nil, BoundsDepth = nil,
            BoundsCenterOffsetX = nil, BoundsCenterOffsetY = nil, BoundsRootPosition = nil, BoundsCameraPosition = nil, BoundsViewport = nil, BoundsFOV = nil,
            BodyCharacter = nil, BodyParts = nil, BodyPartsDirty = true, VisibilityCharacter = nil, VisibilityPart = nil,
            VisibilityPartPosition = nil, VisibilityCameraPosition = nil, VisibilityCameraLook = nil, Visibility = false,
            ToolCharacter = nil, ToolDirty = true, ToolText = "[None]", ChamsCharacter = nil, ChamsColor = nil, ChamsDepth = nil,
            ActivityWatch = nil, ActivityCharacter = nil, ActivityRoot = nil, ActivityHumanoid = nil, ActivityPosition = nil, LastActivityAt = 0 }
        ESPController._records[player] = record
        owner:Add(function()
            for _, object in pairs(record.Drawings) do pool:Release(object) end
            table.clear(record.Drawings)
        end)
    end

    local function removeRecord(player: Player)
        local record = ESPController._records[player]
        ESPController._records[player] = nil
        if record then record.Scope:Dispose() end
    end

    local function ensureDrawing(record: any, name: string)
        if not pool.Available or record.Drawings[name] then return end
        local kind = CONFIG.BASE_DRAWINGS[name]
        if kind then record.Drawings[name] = pool:Acquire(kind) end
    end

    -- Crossing into a Drawing implementation can be more expensive than the comparison itself.
    -- Store scalar geometry, not transient property tables and Vector2s, so unchanged overlays
    -- make no executor writes and allocate no render-frame garbage.
    local function obtainDrawing(record: any, name: string): (any?, any?)
        local object = record.Drawings[name]
        if not object then ensureDrawing(record, name); object = record.Drawings[name] end
        if not object then return nil, nil end
        local last = record.Last[name]
        if not last then last = {}; record.Last[name] = last end
        return object, last
    end

    local function showDrawing(record: any, name: string, object: any, last: any)
        if last.Visible ~= true then
            object.Visible, last.Visible = true, true
            requestOverlayFrameRateRepair()
        end
        record.Shown[name] = true
    end

    local function drawSquare(record: any, name: string, x: number, y: number, width: number, height: number, color: Color3)
        local object, last = obtainDrawing(record, name)
        if not object or not last then return end
        x, y, width, height = math.round(x), math.round(y), math.max(1, math.round(width)), math.max(1, math.round(height))
        if last.X ~= x or last.Y ~= y then object.Position, last.X, last.Y = Vector2.new(x, y), x, y end
        if last.Width ~= width or last.Height ~= height then object.Size, last.Width, last.Height = Vector2.new(width, height), width, height end
        if last.Color ~= color then object.Color, last.Color = color, color end
        if last.Thickness ~= CONFIG.BOX_THICKNESS then object.Thickness, last.Thickness = CONFIG.BOX_THICKNESS, CONFIG.BOX_THICKNESS end
        if last.Filled ~= false then object.Filled, last.Filled = false, false end
        if last.Transparency ~= 1 then object.Transparency, last.Transparency = 1, 1 end
        showDrawing(record, name, object, last)
    end

    local function drawLine(record: any, name: string, fromX: number, fromY: number, toX: number, toY: number, color: Color3, thickness: number)
        local object, last = obtainDrawing(record, name)
        if not object or not last then return end
        fromX, fromY, toX, toY = math.round(fromX), math.round(fromY), math.round(toX), math.round(toY)
        if last.FromX ~= fromX or last.FromY ~= fromY then object.From, last.FromX, last.FromY = Vector2.new(fromX, fromY), fromX, fromY end
        if last.ToX ~= toX or last.ToY ~= toY then object.To, last.ToX, last.ToY = Vector2.new(toX, toY), toX, toY end
        if last.Color ~= color then object.Color, last.Color = color, color end
        if last.Thickness ~= thickness then object.Thickness, last.Thickness = thickness, thickness end
        if last.Transparency ~= 1 then object.Transparency, last.Transparency = 1, 1 end
        showDrawing(record, name, object, last)
    end

    -- Full boxes and health bars use native Frame geometry in the same shared ScreenGui as the
    -- labels. Some executor GUI hosts cull a fully transparent Frame and all of its descendants,
    -- so the four opaque box edges are direct ScreenGui children instead of transparent-container
    -- children. They still avoid executor Drawing and only receive writes when the cached bounds
    -- or color actually change. Corner boxes retain their exact Drawing line geometry below.
    local function makeNativeBoxEdge(parent: Instance, name: string): Frame
        local edge = Instance.new("Frame")
        edge.Name, edge.BackgroundTransparency, edge.BorderSizePixel = name, 0, 0
        edge.ZIndex, edge.Visible, edge.Parent = 4, false, parent
        return edge
    end

    local function ensureNativeBoxEdges(record: any): { Frame }?
        local edges = record.NativeBoxEdges
        if edges and edges[1] and edges[1].Parent then return edges end
        local gui = ensureTextGui()
        if not gui then return nil end
        edges = {
            makeNativeBoxEdge(gui, "B0XazESPBoxTop"),
            makeNativeBoxEdge(gui, "B0XazESPBoxBottom"),
            makeNativeBoxEdge(gui, "B0XazESPBoxLeft"),
            makeNativeBoxEdge(gui, "B0XazESPBoxRight"),
        }
        record.NativeBoxEdges = edges
        record.NativeBoxX, record.NativeBoxY, record.NativeBoxWidth, record.NativeBoxHeight, record.NativeBoxColor = nil, nil, nil, nil, nil
        for _, edge in ipairs(edges) do record.Scope:Add(edge) end
        return edges
    end

    local function drawFullBox(record: any, x: number, y: number, width: number, height: number, color: Color3)
        local edges = ensureNativeBoxEdges(record)
        if not edges then drawSquare(record, "Box", x, y, width, height, color); return end
        local roundedX, roundedY = math.round(x), math.round(y)
        local roundedWidth, roundedHeight = math.max(1, math.round(width)), math.max(1, math.round(height))
        if record.NativeBoxX ~= roundedX or record.NativeBoxY ~= roundedY or record.NativeBoxWidth ~= roundedWidth or record.NativeBoxHeight ~= roundedHeight then
            local right, bottom = roundedX + roundedWidth - CONFIG.BOX_THICKNESS, roundedY + roundedHeight - CONFIG.BOX_THICKNESS
            edges[1].Position, edges[1].Size = UDim2.fromOffset(roundedX, roundedY), UDim2.fromOffset(roundedWidth, CONFIG.BOX_THICKNESS)
            edges[2].Position, edges[2].Size = UDim2.fromOffset(roundedX, bottom), UDim2.fromOffset(roundedWidth, CONFIG.BOX_THICKNESS)
            edges[3].Position, edges[3].Size = UDim2.fromOffset(roundedX, roundedY), UDim2.fromOffset(CONFIG.BOX_THICKNESS, roundedHeight)
            edges[4].Position, edges[4].Size = UDim2.fromOffset(right, roundedY), UDim2.fromOffset(CONFIG.BOX_THICKNESS, roundedHeight)
            record.NativeBoxX, record.NativeBoxY = roundedX, roundedY
            record.NativeBoxWidth, record.NativeBoxHeight = roundedWidth, roundedHeight
        end
        if record.NativeBoxColor ~= color then
            for _, edge in ipairs(edges) do edge.BackgroundColor3 = color end
            record.NativeBoxColor = color
        end
        if not edges[1].Visible then
            for _, edge in ipairs(edges) do edge.Visible = true end
            requestOverlayFrameRateRepair()
        end
        record.NativeBoxShown = true
    end

    local function ensureNativeHealthBar(record: any): Frame?
        local frame = record.NativeHealthBar
        if frame and frame.Parent then return frame end
        local gui = ensureTextGui()
        if not gui then return nil end
        frame = Instance.new("Frame")
        frame.Name, frame.BackgroundTransparency, frame.BorderSizePixel = "B0XazESPHealth", 0, 0
        frame.AnchorPoint, frame.ZIndex, frame.Visible, frame.Parent = Vector2.zero, 4, false, gui
        record.NativeHealthBar = frame
        record.NativeHealthX, record.NativeHealthY, record.NativeHealthWidth = nil, nil, nil
        record.NativeHealthHeight, record.NativeHealthColor = nil, nil
        record.Scope:Add(frame)
        return frame
    end

    local function drawNativeHealthBar(record: any, x: number, y: number, boxHeight: number, fraction: number)
        local frame = ensureNativeHealthBar(record)
        if not frame then return end
        local thickness = CONFIG.HEALTH_BAR_INNER_WIDTH + 1
        local bottom = y + boxHeight - 1
        local top = math.max(y + 1, bottom - math.max(1, boxHeight * fraction - 2))
        local roundedX, roundedY = math.round(x - thickness / 2), math.round(top)
        local roundedHeight = math.max(1, math.round(bottom - top))
        local color = CONFIG.HEALTH_LOW:Lerp(CONFIG.HEALTH_HIGH, fraction)
        if record.NativeHealthX ~= roundedX or record.NativeHealthY ~= roundedY then
            frame.Position, record.NativeHealthX, record.NativeHealthY = UDim2.fromOffset(roundedX, roundedY), roundedX, roundedY
        end
        if record.NativeHealthWidth ~= thickness or record.NativeHealthHeight ~= roundedHeight then
            frame.Size, record.NativeHealthWidth, record.NativeHealthHeight = UDim2.fromOffset(thickness, roundedHeight), thickness, roundedHeight
        end
        if record.NativeHealthColor ~= color then frame.BackgroundColor3, record.NativeHealthColor = color, color end
        if not frame.Visible then frame.Visible = true; requestOverlayFrameRateRepair() end
        record.NativeHealthShown = true
    end

    local function concealUnused(record: any)
        for name, object in pairs(record.Drawings) do
            if object.Visible and not record.Shown[name] then
                object.Visible = false
                local last = record.Last[name]
                if last then last.Visible = false end
            end
        end
        if not record.NativeBoxShown and record.NativeBoxEdges and record.NativeBoxEdges[1].Visible then
            for _, edge in ipairs(record.NativeBoxEdges) do edge.Visible = false end
        end
        if not record.NativeHealthShown and record.NativeHealthBar and record.NativeHealthBar.Visible then record.NativeHealthBar.Visible = false end
        if not record.ReadoutShown then hideReadout(record) end
    end

    local function drawCornerBox(record: any, x: number, y: number, boxWidth: number, boxHeight: number, color: Color3)
        local width = math.max(4, boxWidth * CONFIG.CORNER_WIDTH_FACTOR)
        local height = math.max(4, boxHeight * CONFIG.CORNER_HEIGHT_FACTOR)
        local left, top, right, bottom = x, y, x + boxWidth, y + boxHeight
        drawLine(record, "Corner1", left, top, left + width, top, color, CONFIG.BOX_THICKNESS)
        drawLine(record, "Corner2", left, top, left, top + height, color, CONFIG.BOX_THICKNESS)
        drawLine(record, "Corner3", right, top, right - width, top, color, CONFIG.BOX_THICKNESS)
        drawLine(record, "Corner4", right, top, right, top + height, color, CONFIG.BOX_THICKNESS)
        drawLine(record, "Corner5", left, bottom, left + width, bottom, color, CONFIG.BOX_THICKNESS)
        drawLine(record, "Corner6", left, bottom, left, bottom - height, color, CONFIG.BOX_THICKNESS)
        drawLine(record, "Corner7", right, bottom, right - width, bottom, color, CONFIG.BOX_THICKNESS)
        drawLine(record, "Corner8", right, bottom, right, bottom - height, color, CONFIG.BOX_THICKNESS)
    end

    local function rootProjection(camera: Camera, viewport: Vector2, position: Vector3): (number, number, boolean, number)
        local point = camera:WorldToViewportPoint(position)
        return point.X, point.Y, point.Z > 0 and point.X >= 0 and point.X <= viewport.X and point.Y >= 0 and point.Y <= viewport.Y, point.Z
    end

    local function fallbackBounds(camera: Camera, viewport: Vector2, character: Model): (number?, number?, number?, number?)
        local root, head = character:FindFirstChild("HumanoidRootPart"), character:FindFirstChild("Head")
        if not root or not root:IsA("BasePart") or not head or not head:IsA("BasePart") then return nil, nil, nil, nil end
        local rootPoint, rootVisible = camera:WorldToViewportPoint(root.Position)
        local headPoint, headVisible = camera:WorldToViewportPoint(head.Position)
        if not rootVisible or not headVisible or rootPoint.Z <= 0 or headPoint.Z <= 0 then return nil, nil, nil, nil end
        local height = math.abs(rootPoint.Y - headPoint.Y) * 2.6
        if height < 8 then return nil, nil, nil, nil end
        local width = height * 0.46
        local centerX = (rootPoint.X + headPoint.X) / 2
        return centerX - width / 2, headPoint.Y - height * 0.14, width, height
    end

    -- Rigs and equipped tools change through character events, not a recurring timer. This keeps
    -- the rendered overlay frame-synchronous without repeatedly scanning an unchanged model.
    local function bodyParts(record: any, character: Model): { BasePart }
        if record.BodyCharacter == character and record.BodyParts and not record.BodyPartsDirty then return record.BodyParts end
        if record.BodyCharacter ~= character then
            record.Scope:Bind("Body part added", character.ChildAdded:Connect(function(child: Instance)
                if table.find(CONFIG.BODY_PART_NAMES, child.Name) then record.BodyPartsDirty = true end
            end))
            record.Scope:Bind("Body part removed", character.ChildRemoved:Connect(function(child: Instance)
                if table.find(CONFIG.BODY_PART_NAMES, child.Name) then record.BodyPartsDirty = true end
            end))
        end
        local parts = {}
        for _, name in ipairs(CONFIG.BODY_PART_NAMES) do
            local part = character:FindFirstChild(name)
            if part and part:IsA("BasePart") then table.insert(parts, part) end
        end
        record.BodyCharacter, record.BodyParts, record.BodyPartsDirty = character, parts, false
        return parts
    end

    local function bounds(record: any, camera: Camera, viewport: Vector2, character: Model): (number?, number?, number?, number?)
        local minX, minY, maxX, maxY, projected = math.huge, math.huge, -math.huge, -math.huge, 0
        for _, part in ipairs(bodyParts(record, character)) do
            if part.Parent == character then
                local size, cframe = part.Size, part.CFrame
                local halfX, halfY, halfZ = size.X / 2, size.Y / 2, size.Z / 2
                for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
                    -- PointToWorldSpace avoids creating a temporary CFrame for each body corner.
                    local point = camera:WorldToViewportPoint(cframe:PointToWorldSpace(Vector3.new(halfX * x, halfY * y, halfZ * z)))
                    if point.Z > 0 then
                        minX, minY, maxX, maxY = math.min(minX, point.X), math.min(minY, point.Y), math.max(maxX, point.X), math.max(maxY, point.Y)
                        projected += 1
                    end
                end end end
            end
        end
        if projected == 0 or maxX < 0 or minX > viewport.X or maxY < 0 or minY > viewport.Y then return nil, nil, nil, nil end
        local width, height = maxX - minX, maxY - minY
        if height <= 0 or width / height > CONFIG.MAX_BOX_ASPECT_RATIO then return fallbackBounds(camera, viewport, character) end
        return minX, minY, width, height
    end

    local function cachedBounds(record: any, camera: Camera, character: Model, rootPosition: Vector3, anchorX: number, anchorY: number, depth: number,
        cameraPosition: Vector3, viewport: Vector2, cameraFOV: number): (number?, number?, number?, number?)
        local priorDepth = record.BoundsDepth
        local depthChanged = priorDepth == nil or math.abs(depth - priorDepth) / math.max(priorDepth, 0.001) >= CONFIG.BOUNDS_DEPTH_REBASE_RATIO
        local stale = record.BoundsCharacter ~= character or record.BoundsCamera ~= camera or record.BodyPartsDirty
            or record.BoundsViewport ~= viewport or record.BoundsFOV ~= cameraFOV or depthChanged
            or not record.BoundsRootPosition or (rootPosition - record.BoundsRootPosition).Magnitude >= CONFIG.BOUNDS_ROOT_REBASE_DISTANCE
            or not record.BoundsCameraPosition or (cameraPosition - record.BoundsCameraPosition).Magnitude >= CONFIG.BOUNDS_CAMERA_REBASE_DISTANCE
        if stale then
            local x, y, width, height = bounds(record, camera, viewport, character)
            record.BoundsX, record.BoundsY, record.BoundsWidth, record.BoundsHeight, record.BoundsDepth = x, y, width, height, depth
            record.BoundsRootPosition, record.BoundsCameraPosition = rootPosition, cameraPosition
            record.BoundsViewport, record.BoundsFOV = viewport, cameraFOV
            record.BoundsCenterOffsetX = if x and width then x + width / 2 - anchorX else nil
            record.BoundsCenterOffsetY = if y and height then y + height / 2 - anchorY else nil
        end
        if not record.BoundsWidth or not record.BoundsHeight or not record.BoundsDepth
            or not record.BoundsCenterOffsetX or not record.BoundsCenterOffsetY then return nil, nil, nil, nil end
        local scale = math.clamp(record.BoundsDepth / math.max(depth, 0.001), 0.35, 3)
        local width, height = record.BoundsWidth * scale, record.BoundsHeight * scale
        return anchorX + record.BoundsCenterOffsetX * scale - width / 2, anchorY + record.BoundsCenterOffsetY * scale - height / 2, width, height
    end

    local function cachedVisibility(record: any, part: BasePart, character: Model, cameraPosition: Vector3, cameraLook: Vector3): boolean
        local partPosition = part.Position
        local stale = record.VisibilityCharacter ~= character or record.VisibilityPart ~= part or not record.VisibilityPartPosition
            or (partPosition - record.VisibilityPartPosition).Magnitude >= CONFIG.VISIBILITY_POSITION_EPSILON
            or not record.VisibilityCameraPosition or (cameraPosition - record.VisibilityCameraPosition).Magnitude >= CONFIG.VISIBILITY_CAMERA_EPSILON
            or not record.VisibilityCameraLook or cameraLook:Dot(record.VisibilityCameraLook) <= CONFIG.VISIBILITY_LOOK_DOT
        if stale then
            local hit = filter:Raycast(cameraPosition, partPosition - cameraPosition)
            record.Visibility = not hit or hit.Instance:IsDescendantOf(character)
            record.VisibilityCharacter, record.VisibilityPart = character, part
            record.VisibilityPartPosition, record.VisibilityCameraPosition, record.VisibilityCameraLook = partPosition, cameraPosition, cameraLook
        end
        return record.Visibility == true
    end

    local function overlayColor(record: any, player: Player, config: any): Color3
        if config.UseTeamColor then
            local team, teamColor = player.Team, player.TeamColor
            if record.OverlayTeam ~= team or record.OverlayTeamColor ~= teamColor or not record.OverlayColor then
                record.OverlayTeam, record.OverlayTeamColor = team, teamColor
                record.OverlayColor = filter:GetTeamColor(player)
            end
            return record.OverlayColor
        end
        return config.Color
    end

    local function updateTool(record: any, character: Model)
        if record.ToolCharacter ~= character then
            record.Scope:Bind("Tool added", character.ChildAdded:Connect(function(child: Instance)
                if child:IsA("Tool") then record.ToolDirty = true end
            end))
            record.Scope:Bind("Tool removed", character.ChildRemoved:Connect(function(child: Instance)
                if child:IsA("Tool") then record.ToolDirty = true end
            end))
            record.ToolCharacter, record.ToolDirty = character, true
        end
        if not record.ToolDirty then return end
        local tool = character:FindFirstChildOfClass("Tool")
        record.ToolText, record.ToolDirty = if tool then `[{tool.Name}]` else "[None]", false
    end

    -- The label text normally changes far less often than its projected position. Cache its
    -- source fields so a crowd does not allocate a table and concatenate strings every frame.
    local function readoutText(record: any, player: Player, config: any, distance: number, humanoid: Humanoid, status: string?, character: Model): string?
        local name = if config.Name then player.Name else false
        local range = if config.Distance then math.floor(distance) else false
        local health = if config.Health then math.max(0, math.floor(humanoid.Health)) else false
        local tool: string | boolean = false
        if config.Tool then
            updateTool(record, character)
            tool = record.ToolText
        end
        local activity = status or false
        if record.ReadoutName == name and record.ReadoutDistance == range and record.ReadoutHealth == health
            and record.ReadoutStatus == activity and record.ReadoutTool == tool then return record.ReadoutText end
        record.ReadoutName, record.ReadoutDistance, record.ReadoutHealth = name, range, health
        record.ReadoutStatus, record.ReadoutTool = activity, tool
        local text: string? = nil
        if name then text = name end
        if range then
            local row = `[{range}m]`
            text = if text then text .. "\n" .. row else row
        end
        if health then
            local row = `HP: {health}`
            if activity then row = `{row} | {activity}` end
            text = if text then text .. "\n" .. row else row
        elseif activity then
            local row = `Status: {activity}`
            text = if text then text .. "\n" .. row else row
        end
        if tool then text = if text then text .. "\n" .. tool else tool end
        record.ReadoutText = text
        return text
    end

    -- Window focus is private to each Roblox client, so another player's focus cannot be
    -- observed here. Track replicated character activity instead, only while the optional ESP
    -- status is enabled. Movement, velocity, Humanoid state, and tool signals keep this fully
    -- event-driven for both on-screen and off-screen targets.
    local function markActivity(record: any, position: Vector3?)
        record.LastActivityAt = os.clock()
        if position then record.ActivityPosition = position end
    end

    local function stopActivityTracking(record: any)
        local watch = record.ActivityWatch
        record.ActivityWatch = nil
        record.ActivityCharacter, record.ActivityRoot, record.ActivityHumanoid, record.ActivityPosition = nil, nil, nil, nil
        if watch then watch:Dispose() end
    end

    local function ensureActivityTracking(record: any, assets: any)
        local character, root, humanoid = assets.Character, assets.RootPart, assets.Humanoid
        if record.ActivityCharacter == character and record.ActivityRoot == root and record.ActivityHumanoid == humanoid and record.ActivityWatch then return end
        stopActivityTracking(record)
        local watch = record.Scope:CreateChild("Activity status")
        record.ActivityWatch, record.ActivityCharacter, record.ActivityRoot, record.ActivityHumanoid = watch, character, root, humanoid
        markActivity(record, root.Position)
        local function current(): boolean
            return record.ActivityWatch == watch and record.ActivityCharacter == character and record.ActivityRoot == root
                and root.Parent ~= nil and humanoid.Parent ~= nil
        end
        watch:ConnectImmediate(root:GetPropertyChangedSignal("Position"), function()
            if not current() then return end
            local position, prior = root.Position, record.ActivityPosition
            if not prior or (position - prior).Magnitude >= CONFIG.AFK_POSITION_EPSILON then markActivity(record, position) end
        end)
        watch:ConnectImmediate(humanoid.Running, function(speed: number)
            if current() and speed >= CONFIG.AFK_ACTIVITY_SPEED then markActivity(record, root.Position) end
        end)
        watch:ConnectImmediate(humanoid:GetPropertyChangedSignal("MoveDirection"), function()
            if current() and humanoid.MoveDirection.Magnitude > 0.05 then markActivity(record, root.Position) end
        end)
        watch:ConnectImmediate(root:GetPropertyChangedSignal("AssemblyLinearVelocity"), function()
            if current() and root.AssemblyLinearVelocity.Magnitude >= CONFIG.AFK_ACTIVITY_SPEED then markActivity(record, root.Position) end
        end)
        watch:ConnectImmediate(humanoid.StateChanged, function(_old: Enum.HumanoidStateType, nextState: Enum.HumanoidStateType)
            if not current() then return end
            if nextState == Enum.HumanoidStateType.Jumping or nextState == Enum.HumanoidStateType.Climbing
                or nextState == Enum.HumanoidStateType.Swimming then markActivity(record, root.Position) end
        end)
        watch:ConnectImmediate(character.ChildAdded, function(child: Instance)
            if current() and child:IsA("Tool") then markActivity(record, root.Position) end
        end)
        watch:ConnectImmediate(character.ChildRemoved, function(child: Instance)
            if current() and child:IsA("Tool") then markActivity(record, root.Position) end
        end)
    end

    local function activityStatus(record: any, assets: any): string
        ensureActivityTracking(record, assets)
        return if os.clock() - record.LastActivityAt >= CONFIG.AFK_IDLE_SECONDS then "AFK" else "Active"
    end

    local function stopAllActivityTracking()
        for _, record in pairs(ESPController._records) do stopActivityTracking(record) end
    end

    local function chams(record: any, character: Model, color: Color3, depthMode: string)
        if not ESPController._chamsAvailable then return end
        local depth = if depthMode == "Occluded" then Enum.HighlightDepthMode.Occluded else Enum.HighlightDepthMode.AlwaysOnTop
        local object = record.Highlight
        if object and object.Parent and record.ChamsCharacter == character and record.ChamsColor == color and record.ChamsDepth == depth and object.Enabled then return end
        if not object or not object.Parent then
            local ok, highlight = pcall(function()
                local nextHighlight = Instance.new("Highlight")
                nextHighlight.Name = "B0XazChams"
                record.Scope:Bind("Highlight", nextHighlight)
                nextHighlight.Adornee, nextHighlight.Parent = character, character
                return nextHighlight
            end)
            if not ok then
                ESPController._chamsAvailable = false
                state:Set("Chams.Enabled", false)
                bus:Publish("Notify", "Chams unavailable", "This client could not create a native Highlight")
                return
            end
            record.Highlight, object = highlight, highlight
        end
        if object.Adornee ~= character then object.Adornee, object.Parent = character, character end
        if object.FillColor ~= color then object.FillColor = color end
        if object.OutlineColor ~= color then object.OutlineColor = color end
        if object.FillTransparency ~= CONFIG.CHAMS_FILL_TRANSPARENCY then object.FillTransparency = CONFIG.CHAMS_FILL_TRANSPARENCY end
        if object.OutlineTransparency ~= CONFIG.CHAMS_OUTLINE_TRANSPARENCY then object.OutlineTransparency = CONFIG.CHAMS_OUTLINE_TRANSPARENCY end
        if object.DepthMode ~= depth then object.DepthMode = depth end
        if not object.Enabled then
            object.Enabled = true
            requestOverlayFrameRateRepair()
        end
        record.ChamsCharacter, record.ChamsColor, record.ChamsDepth = character, color, depth
    end

    local function render(_dt: number)
        -- Executor Drawing primitives cannot reliably sit below Roblox UI. Suppress the complete
        -- overlay while the suite menu is open so neither boxes nor readouts bleed through it.
        if state:Peek("Settings.MenuVisible") == true then
            if not ESPController._menuCovered then hideAll(); ESPController._menuCovered = true end
            return
        end
        ESPController._menuCovered = false
        local espConfig, chamsConfig = state:Peek("ESP"), state:Peek("Chams")
        local espEnabled, chamsEnabled = espConfig.Enabled, chamsConfig.Enabled
        if not espEnabled and not chamsEnabled then
            if not ESPController._idle then hideAll(); ESPController._idle = true end
            return
        end
        ESPController._idle = false
        local camera = Workspace.CurrentCamera
        if not camera then hideAll(); return end
        local cameraCFrame, viewport, cameraFOV = camera.CFrame, camera.ViewportSize, camera.FieldOfView
        local cameraPosition, cameraLook = cameraCFrame.Position, cameraCFrame.LookVector
        for player, record in pairs(ESPController._records) do
            table.clear(record.Shown)
            record.ReadoutShown, record.NativeBoxShown, record.NativeHealthShown = false, false, false
            local assets = tracker:GetPlayerAssets(player)
            if not assets or assets.Humanoid.Health <= 0 then hide(record); continue end
            local rootPosition = assets.RootPart.Position
            local distance = (cameraPosition - rootPosition).Magnitude
            if distance > math.max(1, espConfig.MaxDistance) then hide(record); continue end
            local anchorX, anchorY, visible, depth = rootProjection(camera, viewport, rootPosition)
            if not visible then hide(record); continue end
            local status = if espEnabled and espConfig.ActivityStatus then activityStatus(record, assets) else nil
            local color = overlayColor(record, player, espConfig)
            if chamsEnabled then chams(record, assets.Character, color, espConfig.DepthMode) else disableChams(record) end
            if not espEnabled then hideDrawings(record); continue end
            if espConfig.DepthMode == "Occluded" and not cachedVisibility(record, assets.Head or assets.RootPart, assets.Character, cameraPosition, cameraLook) then
                hideDrawings(record)
                continue
            end
            local x, y, width, height = cachedBounds(record, camera, assets.Character, rootPosition, anchorX, anchorY, depth, cameraPosition, viewport, cameraFOV)
            if not x or not y or not width or not height then concealUnused(record); continue end
            local centerX = x + width / 2
            if espConfig.Box then
                if espConfig.BoxStyle == "Corner" then drawCornerBox(record, x, y, width, height, color)
                else drawFullBox(record, x, y, width, height, color) end
            end
            local text = readoutText(record, player, espConfig, distance, assets.Humanoid, status, assets.Character)
            if text then drawReadout(record, text, centerX, y - 3, color) end
            if espConfig.HealthBar then
                local healthFraction = math.clamp(assets.Humanoid.Health / math.max(assets.Humanoid.MaxHealth, 1), 0, 1)
                drawNativeHealthBar(record, x - CONFIG.HEALTH_BAR_OFFSET + 2, y, height, healthFraction)
            end
            concealUnused(record)
        end
    end

    local function syncSelfRecord(showSelf: boolean)
        local player = Players.LocalPlayer
        if not player then return end
        if showSelf == true then createRecord(player) else removeRecord(player) end
    end

    local function syncThemeColor()
        if state:Peek("ESP.ColorFollowsTheme") ~= true then return end
        state:Set("ESP.Color", services:Get("ThemeEngine"):GetToken("Accent"))
    end

    local function syncJob()
        local menuVisible = state:Peek("Settings.MenuVisible") == true
        local on = (state:Peek("ESP.Enabled") == true or state:Peek("Chams.Enabled") == true) and not menuVisible
        if ESPController._job then ESPController._job.Enabled = on end
        if menuVisible then
            hideAll()
            stopAllActivityTracking()
            ESPController._idle, ESPController._menuCovered = true, true
            return
        end
        ESPController._menuCovered = false
        if not state:Peek("ESP.Enabled") or state:Peek("ESP.ActivityStatus") ~= true then stopAllActivityTracking() end
        if not on then hideAll(); ESPController._idle = true end
    end

    function ESPController:Initialize()
        if self._initialized then return end
        self._initialized = true
        for _, player in ipairs(Players:GetPlayers()) do createRecord(player) end
        scope:Add(bus:Subscribe("PlayerJoined", createRecord))
        scope:Add(bus:Subscribe("PlayerLeft", removeRecord))
        self._job = scheduler:RegisterRender("Visuals.ESP", 10, render)
        scope:Add(state:Observe("ESP.Enabled", syncJob))
        scope:Add(state:Observe("Chams.Enabled", syncJob))
        scope:Add(state:Observe("Settings.MenuVisible", syncJob))
        scope:Add(state:Observe("ESP.ShowSelf", syncSelfRecord))
        scope:Add(state:Observe("ESP.ActivityStatus", function(enabled: boolean)
            if enabled ~= true then stopAllActivityTracking() end
        end))
        scope:Add(state:Observe("ESP.ColorFollowsTheme", function(follows: boolean)
            if follows then syncThemeColor() end
        end))
        scope:Add(bus:Subscribe("ThemeChanged", syncThemeColor))
        syncThemeColor()
        syncSelfRecord(state:Peek("ESP.ShowSelf") == true)
        syncJob()
    end

    function ESPController:Destroy() scope:Dispose() end

    scope:Add(function() for player in pairs(table.clone(ESPController._records)) do removeRecord(player) end end)
    return ESPController
end
