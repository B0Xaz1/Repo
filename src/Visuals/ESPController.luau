local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CONFIG = table.freeze({
    -- ESP samples at a stable 30 Hz instead of doing per-player projection and raycast work at
    -- every render callback. This remains visually responsive while protecting client frame time.
    RENDER_INTERVAL = 1 / 30,
    BOUNDS_INTERVAL = 1 / 20,
    VISIBILITY_INTERVAL = 0.15,
    SKELETON_INTERVAL = 1 / 20,
    INVENTORY_REFRESH = 0.25,
    RAINBOW_SPEED = 0.15,
    SCALE_DISTANCE_REF = 1500,
    SCALE_MIN = 0.7,
    SCALE_MAX = 1.25,
    TEXT_SIZE_MIN = 8,
    TEXT_SIZE_MAX = 24,
    LINE_THICKNESS_MIN = 1,
    LINE_THICKNESS_MAX = 4,
    OPACITY_MIN = 0.05,
    OPACITY_MAX = 1,
    BOX_FILL_OPACITY_MAX = 0.85,
    ARROW_RADIUS_MIN = 80,
    ARROW_RADIUS_EDGE_PADDING = 18,
    ARROW_SIZE_MIN = 4,
    ARROW_SIZE_MAX = 28,
    LOOK_DIRECTION_LENGTH = 5,
    HEAD_DOT_MIN = 2,
    HEAD_DOT_MAX = 7,
    OUTLINE_LIGHTEN = 0.35,
    CHAMS_TRANSPARENCY_MIN = 0,
    CHAMS_TRANSPARENCY_MAX = 1,
    HEALTH_BAR_WIDTH = 4,
    HEALTH_BAR_INNER_WIDTH = 2,
    HEALTH_BAR_OFFSET = 7,
    HEALTH_BAR_BACKGROUND = Color3.fromRGB(15, 19, 25),
    HEALTH_LOW = Color3.fromRGB(247, 87, 105),
    HEALTH_HIGH = Color3.fromRGB(79, 222, 157),
    FONTS = { UI = 0, System = 1, Plex = 2, Monospace = 3 },
    BASE_DRAWINGS = { Box = "Square", BoxFill = "Square", HealthBackground = "Square", Health = "Square", Name = "Text", Distance = "Text",
        Tool = "Text", Backpack = "Text", Tracer = "Line", HeadDot = "Circle", LookDir = "Line" },
    CORNER_SEGMENTS = { "Corner1", "Corner2", "Corner3", "Corner4", "Corner5", "Corner6", "Corner7", "Corner8" },
    ARROW_SEGMENTS = { "Arrow1", "Arrow2", "Arrow3" },
    R15_BONES = { { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" }, { "UpperTorso", "LeftUpperArm" },
        { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" }, { "UpperTorso", "RightUpperArm" },
        { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" }, { "LowerTorso", "LeftUpperLeg" },
        { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" }, { "LowerTorso", "RightUpperLeg" },
        { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" } },
    R6_BONES = { { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" }, { "Torso", "Left Leg" }, { "Torso", "Right Leg" } },
})

return function(services: any): any
    local state, tracker, pool, filter = services:Get("StateStore"), services:Get("PlayerTracker"), services:Get("DrawingPool"), services:Get("TargetFilter")
    local scheduler, bus = services:Get("TaskScheduler"), services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("ESPController")
    local ESPController = { _records = {}, _initialized = false, _chamsAvailable = true, _idle = true, _job = nil, _renderElapsed = 0 }
    local skeletonElapsed = 0

    local function hideDrawings(record: any)
        for _, object in pairs(record.Drawings) do
            if object.Visible then object.Visible = false end
        end
        if record.Last then
            for _, last in pairs(record.Last) do last.Visible = false end
        end
    end

    local function hide(record: any)
        hideDrawings(record)
        if record.Highlight and record.Highlight.Enabled then record.Highlight.Enabled = false end
    end

    local function hideAll()
        for _, record in pairs(ESPController._records) do hide(record) end
    end

    local function createRecord(player: Player)
        if player == Players.LocalPlayer or ESPController._records[player] then return end
        local owner = scope:CreateChild(`ESP {player.UserId}`)
        local record = { Player = player, Scope = owner, Drawings = {}, Highlight = nil, Signature = "", InventoryText = "", ToolText = "",
            InventoryAt = -math.huge, Shown = {}, Last = {}, Bones = false, Rig = nil, BoneParts = nil,
            BoundsAt = -math.huge, BoundsCharacter = nil, BoundsCamera = nil, BoundsPosition = nil, BoundsSize = nil,
            VisibilityAt = -math.huge, VisibilityCharacter = nil, Visibility = false }
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

    local function ensureDrawing(record: any, name: string, kind: string)
        if not pool.Available or record.Drawings[name] then return end
        record.Drawings[name] = pool:Acquire(kind)
    end

    local function ensureLines(record: any, names: { string })
        for _, name in ipairs(names) do ensureDrawing(record, name, "Line") end
    end

    local function ensureBones(record: any)
        if not pool.Available or record.Bones then return end
        for index = 1, #CONFIG.R15_BONES do ensureDrawing(record, `Bone{index}`, "Line") end
        record.Bones = true
    end

    -- Drawing properties are only written when they change: each write crosses into the executor,
    -- which costs far more than comparing against the cached value
    local function draw(record: any, name: string, properties: any)
        local object = record.Drawings[name]
        if not object then
            local kind = CONFIG.BASE_DRAWINGS[name]
            if kind then ensureDrawing(record, name, kind); object = record.Drawings[name] end
        end
        if not object then return end
        local last = record.Last[name]
        if not last then last = {}; record.Last[name] = last end
        for property, value in pairs(properties) do
            if last[property] ~= value then object[property] = value; last[property] = value end
        end
        if last.Visible ~= true then object.Visible = true; last.Visible = true end
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
    end

    local function project(camera: Camera, position: Vector3): (Vector2, boolean)
        local point, visible = camera:WorldToViewportPoint(position)
        return Vector2.new(point.X, point.Y), visible and point.Z > 0
    end

    local function bounds(camera: Camera, character: Model): (Vector2?, Vector2?)
        local frame, size = character:GetBoundingBox()
        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
        for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
            local point = camera:WorldToViewportPoint((frame * CFrame.new(size.X * x / 2, size.Y * y / 2, size.Z * z / 2)).Position)
            if point.Z <= 0 then return nil, nil end
            minX, minY, maxX, maxY = math.min(minX, point.X), math.min(minY, point.Y), math.max(maxX, point.X), math.max(maxY, point.Y)
        end end end
        if maxX < 0 or minX > camera.ViewportSize.X or maxY < 0 or minY > camera.ViewportSize.Y then return nil, nil end
        return Vector2.new(minX, minY), Vector2.new(maxX - minX, maxY - minY)
    end

    local function cachedBounds(record: any, camera: Camera, character: Model, now: number): (Vector2?, Vector2?)
        local stale = record.BoundsCharacter ~= character or record.BoundsCamera ~= camera or now - record.BoundsAt >= CONFIG.BOUNDS_INTERVAL
        if stale then
            record.BoundsPosition, record.BoundsSize = bounds(camera, character)
            record.BoundsAt, record.BoundsCharacter, record.BoundsCamera = now, character, camera
        end
        return record.BoundsPosition, record.BoundsSize
    end

    local function cachedVisibility(record: any, part: BasePart, character: Model, now: number): boolean
        local stale = record.VisibilityCharacter ~= character or now - record.VisibilityAt >= CONFIG.VISIBILITY_INTERVAL
        if stale then
            record.Visibility = filter:IsVisible(part)
            record.VisibilityAt, record.VisibilityCharacter = now, character
        end
        return record.Visibility == true
    end

    local function inViewport(camera: Camera, position: Vector3): boolean
        local point = camera:WorldToViewportPoint(position)
        local viewport = camera.ViewportSize
        return point.Z > 0 and point.X >= 0 and point.X <= viewport.X and point.Y >= 0 and point.Y <= viewport.Y
    end

    local function updateInventory(record: any, character: Model)
        if os.clock() - record.InventoryAt < CONFIG.INVENTORY_REFRESH then return end
        record.InventoryAt = os.clock()
        local equipped, backpack = {}, {}
        for _, tool in ipairs(character:GetChildren()) do if tool:IsA("Tool") then table.insert(equipped, tool.Name) end end
        local bag = record.Player:FindFirstChildOfClass("Backpack")
        if bag then for _, tool in ipairs(bag:GetChildren()) do if tool:IsA("Tool") then table.insert(backpack, tool.Name) end end end
        table.sort(equipped); table.sort(backpack)
        local signature = `{table.concat(equipped, "\0")}\1{table.concat(backpack, "\0")}`
        if signature ~= record.Signature then
            record.Signature, record.ToolText, record.InventoryText = signature, table.concat(equipped, ", "), table.concat(backpack, ", ")
        end
    end

    local function rainbowColor(): Color3
        return Color3.fromHSV((os.clock() * CONFIG.RAINBOW_SPEED) % 1, 0.75, 1)
    end

    local function overlayColor(player: Player, config: any, fallback: Color3, source: string?): Color3
        if config.Rainbow then return rainbowColor() end
        local resolver = state:GetTransient("PlayerColorResolver")
        if type(resolver) == "function" then
            local ok, color = pcall(resolver, player, source or "ESP")
            if ok and typeof(color) == "Color3" then return color end
        end
        if config.UseTeamColor then return filter:GetTeamColor(player) end
        return fallback
    end

    local function chams(record: any, assets: any, config: any)
        if not ESPController._chamsAvailable then return end
        if not record.Highlight or not record.Highlight.Parent then
            local ok, highlight = pcall(function()
                local object = Instance.new("Highlight")
                record.Scope:Bind("Highlight", object)
                object.Name = "B0XazChams"
                object.Adornee, object.Parent = assets.Character, assets.Character
                return object
            end)
            if not ok then
                ESPController._chamsAvailable = false
                state:Set("Chams.Enabled", false)
                bus:Publish("Notify", "Chams unavailable", "This client could not create a native Highlight")
                return
            end
            record.Highlight = highlight
        end
        local object = record.Highlight
        local fill = overlayColor(record.Player, config, config.FillColor, "Chams")
        if object.Adornee ~= assets.Character then object.Adornee, object.Parent = assets.Character, assets.Character end
        if object.FillColor ~= fill then object.FillColor = fill end
        local fillTransparency = math.clamp(tonumber(config.FillTransparency) or 0.55, CONFIG.CHAMS_TRANSPARENCY_MIN, CONFIG.CHAMS_TRANSPARENCY_MAX)
        if object.FillTransparency ~= fillTransparency then object.FillTransparency = fillTransparency end
        local outline = if config.Rainbow then fill:Lerp(Color3.new(1, 1, 1), CONFIG.OUTLINE_LIGHTEN) else config.OutlineColor
        if object.OutlineColor ~= outline then object.OutlineColor = outline end
        local outlineTransparency = math.clamp(tonumber(config.OutlineTransparency) or 0.1, CONFIG.CHAMS_TRANSPARENCY_MIN, CONFIG.CHAMS_TRANSPARENCY_MAX)
        if object.OutlineTransparency ~= outlineTransparency then object.OutlineTransparency = outlineTransparency end
        local depth = if state:Peek("ESP.DepthMode") == "Occluded" then Enum.HighlightDepthMode.Occluded else Enum.HighlightDepthMode.AlwaysOnTop
        if object.DepthMode ~= depth then object.DepthMode = depth end
        if not object.Enabled then object.Enabled = true end
    end

    local function boneParts(record: any, assets: any): any
        if record.Rig == assets.Character and record.BoneParts then return record.BoneParts end
        record.Rig = assets.Character
        local pairsForRig = if assets.Humanoid.RigType == Enum.HumanoidRigType.R15 then CONFIG.R15_BONES else CONFIG.R6_BONES
        local parts = {}
        for index, pair in ipairs(pairsForRig) do
            local first, second = assets.Character:FindFirstChild(pair[1]), assets.Character:FindFirstChild(pair[2])
            parts[index] = { first, second }
        end
        record.BoneParts = parts
        return parts
    end

    local function visualOpacity(config: any): number
        return math.clamp(tonumber(config.Opacity) or 1, CONFIG.OPACITY_MIN, CONFIG.OPACITY_MAX)
    end

    local function lineThickness(config: any): number
        return math.clamp(tonumber(config.BoxThickness) or 1, CONFIG.LINE_THICKNESS_MIN, CONFIG.LINE_THICKNESS_MAX)
    end

    local function drawCornerBox(record: any, position: Vector2, size: Vector2, color: Color3, thickness: number, opacity: number)
        ensureLines(record, CONFIG.CORNER_SEGMENTS)
        local width, height = math.max(4, size.X * 0.26), math.max(4, size.Y * 0.2)
        local left, top, right, bottom = position.X, position.Y, position.X + size.X, position.Y + size.Y
        local properties = { Color = color, Thickness = thickness, Transparency = opacity }
        draw(record, "Corner1", { From = Vector2.new(left, top), To = Vector2.new(left + width, top), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner2", { From = Vector2.new(left, top), To = Vector2.new(left, top + height), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner3", { From = Vector2.new(right, top), To = Vector2.new(right - width, top), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner4", { From = Vector2.new(right, top), To = Vector2.new(right, top + height), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner5", { From = Vector2.new(left, bottom), To = Vector2.new(left + width, bottom), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner6", { From = Vector2.new(left, bottom), To = Vector2.new(left, bottom - height), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner7", { From = Vector2.new(right, bottom), To = Vector2.new(right - width, bottom), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Corner8", { From = Vector2.new(right, bottom), To = Vector2.new(right, bottom - height), Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
    end

    local function drawOffscreenArrow(record: any, camera: Camera, worldPosition: Vector3, config: any, color: Color3, opacity: number): boolean
        local point = camera:WorldToViewportPoint(worldPosition)
        local viewport = camera.ViewportSize
        if point.Z <= 0 or (point.X >= 0 and point.X <= viewport.X and point.Y >= 0 and point.Y <= viewport.Y) then return false end
        local centre = viewport / 2
        local offset = Vector2.new(point.X, point.Y) - centre
        if offset.Magnitude < 0.01 then return false end
        local maximumRadius = math.max(CONFIG.ARROW_RADIUS_MIN, math.min(viewport.X, viewport.Y) / 2 - CONFIG.ARROW_RADIUS_EDGE_PADDING)
        local radius = math.clamp(tonumber(config.ArrowRadius) or 260, CONFIG.ARROW_RADIUS_MIN, maximumRadius)
        local size = math.clamp(tonumber(config.ArrowSize) or 10, CONFIG.ARROW_SIZE_MIN, CONFIG.ARROW_SIZE_MAX)
        local direction = offset.Unit
        local anchor = centre + direction * radius
        local tip = anchor + direction * size
        local base = anchor - direction * size * 0.55
        local perpendicular = Vector2.new(-direction.Y, direction.X) * size * 0.62
        ensureLines(record, CONFIG.ARROW_SEGMENTS)
        local properties = { Color = color, Thickness = lineThickness(config), Transparency = opacity }
        draw(record, "Arrow1", { From = tip, To = base + perpendicular, Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Arrow2", { From = base + perpendicular, To = base - perpendicular, Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        draw(record, "Arrow3", { From = base - perpendicular, To = tip, Color = properties.Color, Thickness = properties.Thickness, Transparency = properties.Transparency })
        return true
    end

    local function tracerOrigin(camera: Camera, origin: any): Vector2
        local viewport = camera.ViewportSize
        if origin == "Center" then return viewport / 2 end
        if origin == "Top" then return Vector2.new(viewport.X / 2, 0) end
        return Vector2.new(viewport.X / 2, viewport.Y)
    end

    local function drawHealth(record: any, position: Vector2, size: Vector2, fraction: number, config: any, opacity: number): number
        if config.HealthStyle == "Bottom" then
            local y = position.Y + size.Y + 4
            draw(record, "HealthBackground", { Position = Vector2.new(position.X, y), Size = Vector2.new(size.X, CONFIG.HEALTH_BAR_WIDTH), Color = CONFIG.HEALTH_BAR_BACKGROUND, Filled = true, Transparency = opacity })
            draw(record, "Health", { Position = Vector2.new(position.X + 1, y + 1), Size = Vector2.new(math.max(1, (size.X - 2) * fraction), CONFIG.HEALTH_BAR_INNER_WIDTH),
                Color = CONFIG.HEALTH_LOW:Lerp(CONFIG.HEALTH_HIGH, fraction), Filled = true, Transparency = opacity })
            return CONFIG.HEALTH_BAR_WIDTH + 5
        end
        draw(record, "HealthBackground", { Position = position - Vector2.new(CONFIG.HEALTH_BAR_OFFSET, 0), Size = Vector2.new(CONFIG.HEALTH_BAR_WIDTH, size.Y), Color = CONFIG.HEALTH_BAR_BACKGROUND, Filled = true, Transparency = opacity })
        draw(record, "Health", { Position = position - Vector2.new(CONFIG.HEALTH_BAR_OFFSET - 1, -size.Y * (1 - fraction)), Size = Vector2.new(CONFIG.HEALTH_BAR_INNER_WIDTH, size.Y * fraction),
            Color = CONFIG.HEALTH_LOW:Lerp(CONFIG.HEALTH_HIGH, fraction), Filled = true, Transparency = opacity })
        return 0
    end

    local function render(dt: number)
        ESPController._renderElapsed += dt
        skeletonElapsed += dt
        if ESPController._renderElapsed < CONFIG.RENDER_INTERVAL then return end
        ESPController._renderElapsed %= CONFIG.RENDER_INTERVAL
        local updateSkeleton = skeletonElapsed >= CONFIG.SKELETON_INTERVAL
        if updateSkeleton then skeletonElapsed %= CONFIG.SKELETON_INTERVAL end
        local config, chamsConfig = state:Peek("ESP"), state:Peek("Chams")
        local espEnabled = pool.Available and config.Enabled
        local chamsEnabled = chamsConfig.Enabled
        if not espEnabled and not chamsEnabled then
            if not ESPController._idle then hideAll(); ESPController._idle = true end
            return
        end
        ESPController._idle = false
        local camera = Workspace.CurrentCamera
        local occluded, now = config.DepthMode == "Occluded", os.clock()
        for player, record in pairs(ESPController._records) do
            table.clear(record.Shown)
            if not camera then hide(record); continue end
            local assets = tracker:GetPlayerAssets(player)
            if not assets or assets.Humanoid.Health <= 0 then hide(record); continue end
            if config.TeamCheck and filter:IsTeammate(player) then hide(record); continue end
            local distance = (camera.CFrame.Position - assets.RootPart.Position).Magnitude
            if distance > math.max(1, config.MaxDist) then hide(record); continue end
            if chamsEnabled then chams(record, assets, chamsConfig)
            elseif record.Highlight and record.Highlight.Enabled then record.Highlight.Enabled = false end
            if not espEnabled then hideDrawings(record); continue end
            local color, opacity = overlayColor(player, config, config.Color, "ESP"), visualOpacity(config)
            -- Off-screen records only need a single root projection for optional direction pointers;
            -- skip their expensive occlusion raycast and 3D-box projection entirely.
            if not inViewport(camera, assets.RootPart.Position) then
                if config.OffscreenArrows then drawOffscreenArrow(record, camera, assets.RootPart.Position, config, color, opacity) end
                concealUnused(record)
                continue
            end
            if occluded and not cachedVisibility(record, assets.Head or assets.RootPart, assets.Character, now) then hideDrawings(record); continue end
            local position, size = cachedBounds(record, camera, assets.Character, now)
            if not position or not size then
                if config.OffscreenArrows then drawOffscreenArrow(record, camera, assets.RootPart.Position, config, color, opacity) end
                concealUnused(record)
                continue
            end
            local centerX, bottom = position.X + size.X / 2, position.Y + size.Y
            local scale = if config.AutoScaling then math.clamp(CONFIG.SCALE_MAX - distance / CONFIG.SCALE_DISTANCE_REF, CONFIG.SCALE_MIN, CONFIG.SCALE_MAX) else 1
            local baseTextSize = math.clamp(tonumber(config.TextSize) or 13, CONFIG.TEXT_SIZE_MIN, CONFIG.TEXT_SIZE_MAX)
            local textSize, font = math.round(baseTextSize * scale), CONFIG.FONTS[config.Font] or CONFIG.FONTS.Plex
            local thickness = lineThickness(config)
            if config.Box then
                if config.BoxFill then
                    local fillOpacity = math.clamp(tonumber(config.BoxFillOpacity) or 0.12, 0, CONFIG.BOX_FILL_OPACITY_MAX) * opacity
                    draw(record, "BoxFill", { Position = position, Size = size, Color = color, Filled = true, Transparency = fillOpacity })
                end
                if config.BoxStyle == "Full" then
                    draw(record, "Box", { Position = position, Size = size, Color = color, Thickness = thickness, Filled = false, Transparency = opacity })
                else
                    drawCornerBox(record, position, size, color, thickness, opacity)
                end
            end
            if config.Name then draw(record, "Name", { Text = `{player.DisplayName}{if player.DisplayName ~= player.Name then ` (@{player.Name})` else ""}`,
                Position = Vector2.new(centerX, position.Y - textSize - 3), Size = textSize, Font = font, Outline = config.Outline, Color = color, Transparency = opacity }) end
            local healthOffset = 0
            if config.Health then
                local fraction = math.clamp(assets.Humanoid.Health / math.max(assets.Humanoid.MaxHealth, 1), 0, 1)
                healthOffset = drawHealth(record, position, size, fraction, config, opacity)
            end
            local textY = bottom + 3 + healthOffset
            if config.Distance then
                draw(record, "Distance", { Text = `{math.floor(distance)} studs`, Position = Vector2.new(centerX, textY), Size = textSize, Font = font, Outline = config.Outline, Color = color, Transparency = opacity })
                textY += textSize + 1
            end
            if config.Tool or config.Backpack then updateInventory(record, assets.Character) end
            if config.Tool and record.ToolText ~= "" then
                draw(record, "Tool", { Text = record.ToolText, Position = Vector2.new(centerX, textY), Size = textSize, Font = font, Outline = config.Outline, Color = color, Transparency = opacity }); textY += textSize + 1
            end
            if config.Backpack and record.InventoryText ~= "" then
                draw(record, "Backpack", { Text = `Bag: {record.InventoryText}`, Position = Vector2.new(centerX, textY), Size = textSize, Font = font, Outline = config.Outline, Color = color, Transparency = opacity })
            end
            if config.Tracers then draw(record, "Tracer", { From = tracerOrigin(camera, config.TracerOrigin), To = Vector2.new(centerX, bottom), Color = color, Thickness = thickness, Transparency = opacity }) end
            local head, headVisible = nil, false
            if config.HeadDot or config.LookDir then head, headVisible = project(camera, assets.Head.Position) end
            if config.HeadDot and headVisible then draw(record, "HeadDot", { Position = head, Radius = math.clamp(size.X / 8, CONFIG.HEAD_DOT_MIN, CONFIG.HEAD_DOT_MAX), Filled = true, Color = color, Transparency = opacity }) end
            if config.LookDir and headVisible then
                local endpoint, visible = project(camera, assets.Head.Position + assets.Head.CFrame.LookVector * CONFIG.LOOK_DIRECTION_LENGTH)
                if visible then draw(record, "LookDir", { From = head, To = endpoint, Color = color, Thickness = thickness, Transparency = opacity }) end
            end
            if config.Skeleton then
                if updateSkeleton then
                    ensureBones(record)
                    for index, pair in ipairs(boneParts(record, assets)) do
                        local first, second = pair[1], pair[2]
                        if first and second and first:IsA("BasePart") and second:IsA("BasePart") then
                            local a, aVisible = project(camera, first.Position)
                            local b, bVisible = project(camera, second.Position)
                            if aVisible and bVisible then draw(record, `Bone{index}`, { From = a, To = b, Color = color, Thickness = thickness, Transparency = opacity }) end
                        end
                    end
                else
                    for index = 1, #CONFIG.R15_BONES do
                        local name = `Bone{index}`
                        local bone = record.Drawings[name]
                        if bone and bone.Visible then record.Shown[name] = true end
                    end
                end
            end
            concealUnused(record)
        end
    end

    local function syncJob()
        local on = state:Peek("ESP.Enabled") == true or state:Peek("Chams.Enabled") == true
        if ESPController._job then ESPController._job.Enabled = on end
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
        syncJob()
    end

    function ESPController:Destroy() scope:Dispose() end

    scope:Add(function() for player in pairs(table.clone(ESPController._records)) do removeRecord(player) end end)
    return ESPController
end
