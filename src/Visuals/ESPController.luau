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
    -- The default full-box readout uses one executor Drawing primitive per player: the box.
    -- Its compact status lives in one shared ScreenGui with one lightweight native TextLabel per
    -- target. This avoids the Drawing.Text visibility cap without creating per-target billboards.
    -- The optional health bar is a second Drawing primitive only when enabled.
    BASE_DRAWINGS = { Box = "Square", HealthBar = "Line",
        Corner1 = "Line", Corner2 = "Line", Corner3 = "Line", Corner4 = "Line", Corner5 = "Line", Corner6 = "Line", Corner7 = "Line", Corner8 = "Line" },
})

return function(services: any): any
    local state, tracker, pool, filter = services:Get("StateStore"), services:Get("PlayerTracker"), services:Get("DrawingPool"), services:Get("TargetFilter")
    local scheduler, bus, environment = services:Get("TaskScheduler"), services:Get("EventBus"), services:Get("Environment")
    local scope = services:Get("Disposer"):CreateChild("ESPController")
    local ESPController = { _records = {}, _initialized = false, _chamsAvailable = true, _idle = true, _job = nil, _textGui = nil,
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
        record.Scope:Add(label)
        return label
    end

    local function drawReadout(record: any, text: string, position: Vector2, color: Color3)
        local label = ensureReadout(record)
        if not label then return end
        local rounded = UDim2.fromOffset(math.round(position.X), math.round(position.Y))
        if label.Text ~= text then label.Text = text end
        if label.Position ~= rounded then label.Position = rounded end
        if label.TextColor3 ~= color then label.TextColor3 = color end
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

    local function hideDrawings(record: any)
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
        local record = { Player = player, Scope = owner, Drawings = {}, Last = {}, Shown = {}, ReadoutLabel = nil, ReadoutShown = false, Highlight = nil,
            BoundsCharacter = nil, BoundsCamera = nil, BoundsPosition = nil, BoundsSize = nil, BoundsAnchor = nil, BoundsDepth = nil,
            BoundsCenterOffset = nil, BoundsRootPosition = nil, BoundsCameraPosition = nil, BoundsViewport = nil, BoundsFOV = nil,
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
    -- Cache the last applied properties so each simple overlay only writes actual changes.
    local function draw(record: any, name: string, properties: any)
        local object = record.Drawings[name]
        if not object then ensureDrawing(record, name); object = record.Drawings[name] end
        if not object then return end
        local last = record.Last[name]
        if not last then last = {}; record.Last[name] = last end
        for property, value in pairs(properties) do
            if last[property] ~= value then object[property] = value; last[property] = value end
        end
        if last.Visible ~= true then
            object.Visible, last.Visible = true, true
            requestOverlayFrameRateRepair()
        end
        record.Shown[name] = true
    end

    local function concealUnused(record: any)
        for name, object in pairs(record.Drawings) do
            if object.Visible and not record.Shown[name] then
                object.Visible = false
                local last = record.Last[name]
                if last then last.Visible = false end
            end
        end
        if not record.ReadoutShown then hideReadout(record) end
    end

    local function drawCornerBox(record: any, position: Vector2, size: Vector2, color: Color3)
        local width = math.max(4, size.X * CONFIG.CORNER_WIDTH_FACTOR)
        local height = math.max(4, size.Y * CONFIG.CORNER_HEIGHT_FACTOR)
        local left, top, right, bottom = position.X, position.Y, position.X + size.X, position.Y + size.Y
        local properties = { Color = color, Thickness = CONFIG.BOX_THICKNESS, Transparency = 1 }
        draw(record, "Corner1", { From = Vector2.new(left, top), To = Vector2.new(left + width, top), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner2", { From = Vector2.new(left, top), To = Vector2.new(left, top + height), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner3", { From = Vector2.new(right, top), To = Vector2.new(right - width, top), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner4", { From = Vector2.new(right, top), To = Vector2.new(right, top + height), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner5", { From = Vector2.new(left, bottom), To = Vector2.new(left + width, bottom), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner6", { From = Vector2.new(left, bottom), To = Vector2.new(left, bottom - height), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner7", { From = Vector2.new(right, bottom), To = Vector2.new(right - width, bottom), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner8", { From = Vector2.new(right, bottom), To = Vector2.new(right, bottom - height), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
    end

    local function drawHealthBar(record: any, position: Vector2, size: Vector2, fraction: number)
        local x, bottom = position.X - CONFIG.HEALTH_BAR_OFFSET + 2, position.Y + size.Y - 1
        draw(record, "HealthBar", { From = Vector2.new(x, bottom), To = Vector2.new(x, math.max(position.Y + 1, bottom - math.max(1, size.Y * fraction - 2))),
            Color = CONFIG.HEALTH_LOW:Lerp(CONFIG.HEALTH_HIGH, fraction), Thickness = CONFIG.HEALTH_BAR_INNER_WIDTH + 1, Transparency = 1 })
    end

    local function rootProjection(camera: Camera, position: Vector3): (Vector2, boolean, number)
        local point = camera:WorldToViewportPoint(position)
        local viewport = camera.ViewportSize
        return Vector2.new(point.X, point.Y), point.Z > 0 and point.X >= 0 and point.X <= viewport.X and point.Y >= 0 and point.Y <= viewport.Y, point.Z
    end

    local function fallbackBounds(camera: Camera, character: Model): (Vector2?, Vector2?)
        local root, head = character:FindFirstChild("HumanoidRootPart"), character:FindFirstChild("Head")
        if not root or not root:IsA("BasePart") or not head or not head:IsA("BasePart") then return nil, nil end
        local rootPoint, rootVisible = camera:WorldToViewportPoint(root.Position)
        local headPoint, headVisible = camera:WorldToViewportPoint(head.Position)
        if not rootVisible or not headVisible or rootPoint.Z <= 0 or headPoint.Z <= 0 then return nil, nil end
        local height = math.abs(rootPoint.Y - headPoint.Y) * 2.6
        if height < 8 then return nil, nil end
        local width = height * 0.46
        local centerX = (rootPoint.X + headPoint.X) / 2
        return Vector2.new(centerX - width / 2, headPoint.Y - height * 0.14), Vector2.new(width, height)
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

    local function bounds(record: any, camera: Camera, character: Model): (Vector2?, Vector2?)
        local minX, minY, maxX, maxY, projected = math.huge, math.huge, -math.huge, -math.huge, 0
        for _, part in ipairs(bodyParts(record, character)) do
            if part.Parent == character then
                local size = part.Size
                for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
                    local point = camera:WorldToViewportPoint((part.CFrame * CFrame.new(size.X * x / 2, size.Y * y / 2, size.Z * z / 2)).Position)
                    if point.Z > 0 then
                        minX, minY, maxX, maxY = math.min(minX, point.X), math.min(minY, point.Y), math.max(maxX, point.X), math.max(maxY, point.Y)
                        projected += 1
                    end
                end end end
            end
        end
        if projected == 0 or maxX < 0 or minX > camera.ViewportSize.X or maxY < 0 or minY > camera.ViewportSize.Y then return nil, nil end
        local size = Vector2.new(maxX - minX, maxY - minY)
        if size.Y <= 0 or size.X / size.Y > CONFIG.MAX_BOX_ASPECT_RATIO then return fallbackBounds(camera, character) end
        return Vector2.new(minX, minY), size
    end

    local function cachedBounds(record: any, camera: Camera, character: Model, rootPosition: Vector3, anchor: Vector2, depth: number): (Vector2?, Vector2?)
        local cameraPosition, viewport = camera.CFrame.Position, camera.ViewportSize
        local priorDepth = record.BoundsDepth
        local depthChanged = priorDepth == nil or math.abs(depth - priorDepth) / math.max(priorDepth, 0.001) >= CONFIG.BOUNDS_DEPTH_REBASE_RATIO
        local stale = record.BoundsCharacter ~= character or record.BoundsCamera ~= camera or record.BodyPartsDirty
            or record.BoundsViewport ~= viewport or record.BoundsFOV ~= camera.FieldOfView or depthChanged
            or not record.BoundsRootPosition or (rootPosition - record.BoundsRootPosition).Magnitude >= CONFIG.BOUNDS_ROOT_REBASE_DISTANCE
            or not record.BoundsCameraPosition or (cameraPosition - record.BoundsCameraPosition).Magnitude >= CONFIG.BOUNDS_CAMERA_REBASE_DISTANCE
        if stale then
            local position, size = bounds(record, camera, character)
            record.BoundsPosition, record.BoundsSize, record.BoundsAnchor, record.BoundsDepth = position, size, anchor, depth
            record.BoundsRootPosition, record.BoundsCameraPosition = rootPosition, cameraPosition
            record.BoundsViewport, record.BoundsFOV = viewport, camera.FieldOfView
            record.BoundsCenterOffset = if position and size then position + size / 2 - anchor else nil
        end
        if not record.BoundsSize or not record.BoundsDepth or not record.BoundsCenterOffset then return nil, nil end
        local scale = math.clamp(record.BoundsDepth / math.max(depth, 0.001), 0.35, 3)
        local size = record.BoundsSize * scale
        return anchor + record.BoundsCenterOffset * scale - size / 2, size
    end

    local function cachedVisibility(record: any, part: BasePart, character: Model, camera: Camera): boolean
        local cameraPosition, cameraLook, partPosition = camera.CFrame.Position, camera.CFrame.LookVector, part.Position
        local stale = record.VisibilityCharacter ~= character or record.VisibilityPart ~= part or not record.VisibilityPartPosition
            or (partPosition - record.VisibilityPartPosition).Magnitude >= CONFIG.VISIBILITY_POSITION_EPSILON
            or not record.VisibilityCameraPosition or (cameraPosition - record.VisibilityCameraPosition).Magnitude >= CONFIG.VISIBILITY_CAMERA_EPSILON
            or not record.VisibilityCameraLook or cameraLook:Dot(record.VisibilityCameraLook) <= CONFIG.VISIBILITY_LOOK_DOT
        if stale then
            record.Visibility = filter:IsVisible(part)
            record.VisibilityCharacter, record.VisibilityPart = character, part
            record.VisibilityPartPosition, record.VisibilityCameraPosition, record.VisibilityCameraLook = partPosition, cameraPosition, cameraLook
        end
        return record.Visibility == true
    end

    local function overlayColor(player: Player, config: any): Color3
        if config.UseTeamColor then return filter:GetTeamColor(player) end
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

    -- Window focus is private to each Roblox client, so another player's focus cannot be
    -- observed here. Track replicated character activity instead, only while the optional ESP
    -- status is enabled. The watch is event-driven for off-screen targets; the existing render
    -- pass supplies a small current-motion safeguard for visible targets.
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
        local root, humanoid = assets.RootPart, assets.Humanoid
        local position, prior = root.Position, record.ActivityPosition
        if not prior or (position - prior).Magnitude >= CONFIG.AFK_POSITION_EPSILON then
            markActivity(record, position)
        elseif humanoid.MoveDirection.Magnitude > 0.05 or root.AssemblyLinearVelocity.Magnitude >= CONFIG.AFK_ACTIVITY_SPEED then
            markActivity(record, position)
        end
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
        local espConfig, chamsConfig = state:Peek("ESP"), state:Peek("Chams")
        local espEnabled, chamsEnabled = pool.Available and espConfig.Enabled, chamsConfig.Enabled
        if not espEnabled and not chamsEnabled then
            if not ESPController._idle then hideAll(); ESPController._idle = true end
            return
        end
        ESPController._idle = false
        local camera = Workspace.CurrentCamera
        for player, record in pairs(ESPController._records) do
            table.clear(record.Shown)
            record.ReadoutShown = false
            if not camera then hide(record); continue end
            local assets = tracker:GetPlayerAssets(player)
            if not assets or assets.Humanoid.Health <= 0 then hide(record); continue end
            local rootPosition = assets.RootPart.Position
            local status = if espEnabled and espConfig.ActivityStatus then activityStatus(record, assets) else nil
            local distance = (camera.CFrame.Position - rootPosition).Magnitude
            if distance > math.max(1, espConfig.MaxDistance) then hide(record); continue end
            local anchor, visible, depth = rootProjection(camera, rootPosition)
            if not visible then hide(record); continue end
            local color = overlayColor(player, espConfig)
            if chamsEnabled then chams(record, assets.Character, color, espConfig.DepthMode) else disableChams(record) end
            if not espEnabled then hideDrawings(record); continue end
            if espConfig.DepthMode == "Occluded" and not cachedVisibility(record, assets.Head or assets.RootPart, assets.Character, camera) then
                hideDrawings(record)
                continue
            end
            local position, size = cachedBounds(record, camera, assets.Character, rootPosition, anchor, depth)
            if not position or not size then concealUnused(record); continue end
            local centerX = position.X + size.X / 2
            if espConfig.Box then
                if espConfig.BoxStyle == "Corner" then drawCornerBox(record, position, size, color)
                else draw(record, "Box", { Position = position, Size = size, Color = color, Thickness = CONFIG.BOX_THICKNESS, Filled = false, Transparency = 1 }) end
            end
            local healthFraction = math.clamp(assets.Humanoid.Health / math.max(assets.Humanoid.MaxHealth, 1), 0, 1)
            local readout = {}
            if espConfig.Name then table.insert(readout, player.Name) end
            if espConfig.Distance then table.insert(readout, `[{math.floor(distance)}m]`) end
            if espConfig.Health then
                local healthText = `HP: {math.max(0, math.floor(assets.Humanoid.Health))}`
                table.insert(readout, if status then `{healthText} | {status}` else healthText)
            elseif status then
                table.insert(readout, `Status: {status}`)
            end
            if espConfig.Tool then
                updateTool(record, assets.Character)
                table.insert(readout, record.ToolText)
            end
            if #readout > 0 then
                drawReadout(record, table.concat(readout, "\n"), Vector2.new(centerX, position.Y - 3), color)
            end
            if espConfig.HealthBar then drawHealthBar(record, position, size, healthFraction) end
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
        local on = state:Peek("ESP.Enabled") == true or state:Peek("Chams.Enabled") == true
        if ESPController._job then ESPController._job.Enabled = on end
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
