local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CONFIG = table.freeze({
    -- Only the root-point projection runs at display cadence. The full 3D box remains cached,
    -- preserving smooth camera pans without bringing expensive eight-corner bounds work back per frame.
    RENDER_INTERVAL = 1 / 60,
    BOUNDS_INTERVAL = 1 / 20,
    VISIBILITY_INTERVAL = 0.15,
    TOOL_REFRESH_INTERVAL = 0.2,
    TEXT_SIZE = 14,
    BOX_THICKNESS = 1,
    CORNER_WIDTH_FACTOR = 0.26,
    CORNER_HEIGHT_FACTOR = 0.2,
    HEALTH_BAR_WIDTH = 4,
    HEALTH_BAR_INNER_WIDTH = 2,
    HEALTH_BAR_OFFSET = 7,
    HEALTH_BAR_BACKGROUND = Color3.fromRGB(15, 19, 25),
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
    BASE_DRAWINGS = { Box = "Square", Name = "Text", Distance = "Text", Tool = "Text", Health = "Text", HealthBackground = "Square", HealthBar = "Square",
        Corner1 = "Line", Corner2 = "Line", Corner3 = "Line", Corner4 = "Line", Corner5 = "Line", Corner6 = "Line", Corner7 = "Line", Corner8 = "Line" },
})

return function(services: any): any
    local state, tracker, pool, filter = services:Get("StateStore"), services:Get("PlayerTracker"), services:Get("DrawingPool"), services:Get("TargetFilter")
    local scheduler, bus = services:Get("TaskScheduler"), services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("ESPController")
    local ESPController = { _records = {}, _initialized = false, _chamsAvailable = true, _idle = true, _job = nil, _renderElapsed = 0 }

    local function hideDrawings(record: any)
        for _, object in pairs(record.Drawings) do
            if object.Visible then object.Visible = false end
        end
        for _, last in pairs(record.Last) do last.Visible = false end
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
        local record = { Player = player, Scope = owner, Drawings = {}, Last = {}, Shown = {}, Highlight = nil,
            BoundsAt = -math.huge, BoundsCharacter = nil, BoundsCamera = nil, BoundsPosition = nil, BoundsSize = nil, BoundsAnchor = nil,
            VisibilityAt = -math.huge, VisibilityCharacter = nil, Visibility = false,
            ToolAt = -math.huge, ToolCharacter = nil, ToolText = "[None]" }
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
        local barPosition = position - Vector2.new(CONFIG.HEALTH_BAR_OFFSET, 0)
        draw(record, "HealthBackground", { Position = barPosition, Size = Vector2.new(CONFIG.HEALTH_BAR_WIDTH, size.Y), Color = CONFIG.HEALTH_BAR_BACKGROUND, Filled = true, Transparency = 1 })
        draw(record, "HealthBar", { Position = barPosition + Vector2.new(1, size.Y * (1 - fraction) + 1),
            Size = Vector2.new(CONFIG.HEALTH_BAR_INNER_WIDTH, math.max(1, size.Y * fraction - 2)), Color = CONFIG.HEALTH_LOW:Lerp(CONFIG.HEALTH_HIGH, fraction), Filled = true, Transparency = 1 })
    end

    local function rootProjection(camera: Camera, position: Vector3): (Vector2, boolean)
        local point = camera:WorldToViewportPoint(position)
        local viewport = camera.ViewportSize
        return Vector2.new(point.X, point.Y), point.Z > 0 and point.X >= 0 and point.X <= viewport.X and point.Y >= 0 and point.Y <= viewport.Y
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

    local function bounds(camera: Camera, character: Model): (Vector2?, Vector2?)
        local minX, minY, maxX, maxY, projected = math.huge, math.huge, -math.huge, -math.huge, 0
        for _, name in ipairs(CONFIG.BODY_PART_NAMES) do
            local part = character:FindFirstChild(name)
            if not part or not part:IsA("BasePart") then continue end
            local size = part.Size
            for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
                local point = camera:WorldToViewportPoint((part.CFrame * CFrame.new(size.X * x / 2, size.Y * y / 2, size.Z * z / 2)).Position)
                if point.Z > 0 then
                    minX, minY, maxX, maxY = math.min(minX, point.X), math.min(minY, point.Y), math.max(maxX, point.X), math.max(maxY, point.Y)
                    projected += 1
                end
            end end end
        end
        if projected == 0 or maxX < 0 or minX > camera.ViewportSize.X or maxY < 0 or minY > camera.ViewportSize.Y then return nil, nil end
        local size = Vector2.new(maxX - minX, maxY - minY)
        if size.Y <= 0 or size.X / size.Y > CONFIG.MAX_BOX_ASPECT_RATIO then return fallbackBounds(camera, character) end
        return Vector2.new(minX, minY), size
    end

    local function cachedBounds(record: any, camera: Camera, character: Model, anchor: Vector2, now: number): (Vector2?, Vector2?)
        local stale = record.BoundsCharacter ~= character or record.BoundsCamera ~= camera or now - record.BoundsAt >= CONFIG.BOUNDS_INTERVAL
        if stale then
            local position, size = bounds(camera, character)
            record.BoundsPosition, record.BoundsSize, record.BoundsAnchor = position, size, anchor
            record.BoundsAt, record.BoundsCharacter, record.BoundsCamera = now, character, camera
        end
        if not record.BoundsPosition or not record.BoundsSize or not record.BoundsAnchor then return nil, nil end
        return record.BoundsPosition + (anchor - record.BoundsAnchor), record.BoundsSize
    end

    local function cachedVisibility(record: any, part: BasePart, character: Model, now: number): boolean
        local stale = record.VisibilityCharacter ~= character or now - record.VisibilityAt >= CONFIG.VISIBILITY_INTERVAL
        if stale then
            record.Visibility, record.VisibilityAt, record.VisibilityCharacter = filter:IsVisible(part), now, character
        end
        return record.Visibility == true
    end

    local function overlayColor(player: Player, config: any): Color3
        if config.UseTeamColor then return filter:GetTeamColor(player) end
        return config.Color
    end

    local function updateTool(record: any, character: Model, now: number)
        if record.ToolCharacter == character and now - record.ToolAt < CONFIG.TOOL_REFRESH_INTERVAL then return end
        local tool = character:FindFirstChildOfClass("Tool")
        record.ToolCharacter, record.ToolAt = character, now
        record.ToolText = if tool then `[{tool.Name}]` else "[None]"
    end

    local function chams(record: any, character: Model, color: Color3, depthMode: string)
        if not ESPController._chamsAvailable then return end
        if not record.Highlight or not record.Highlight.Parent then
            local ok, highlight = pcall(function()
                local object = Instance.new("Highlight")
                object.Name = "B0XazChams"
                record.Scope:Bind("Highlight", object)
                object.Adornee, object.Parent = character, character
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
        if object.Adornee ~= character then object.Adornee, object.Parent = character, character end
        if object.FillColor ~= color then object.FillColor = color end
        if object.OutlineColor ~= color then object.OutlineColor = color end
        if object.FillTransparency ~= CONFIG.CHAMS_FILL_TRANSPARENCY then object.FillTransparency = CONFIG.CHAMS_FILL_TRANSPARENCY end
        if object.OutlineTransparency ~= CONFIG.CHAMS_OUTLINE_TRANSPARENCY then object.OutlineTransparency = CONFIG.CHAMS_OUTLINE_TRANSPARENCY end
        local depth = if depthMode == "Occluded" then Enum.HighlightDepthMode.Occluded else Enum.HighlightDepthMode.AlwaysOnTop
        if object.DepthMode ~= depth then object.DepthMode = depth end
        if not object.Enabled then object.Enabled = true end
    end

    local function render(dt: number)
        ESPController._renderElapsed += dt
        if ESPController._renderElapsed < CONFIG.RENDER_INTERVAL then return end
        ESPController._renderElapsed %= CONFIG.RENDER_INTERVAL
        local espConfig, chamsConfig = state:Peek("ESP"), state:Peek("Chams")
        local espEnabled, chamsEnabled = pool.Available and espConfig.Enabled, chamsConfig.Enabled
        if not espEnabled and not chamsEnabled then
            if not ESPController._idle then hideAll(); ESPController._idle = true end
            return
        end
        ESPController._idle = false
        local camera, now = Workspace.CurrentCamera, os.clock()
        for player, record in pairs(ESPController._records) do
            table.clear(record.Shown)
            if not camera then hide(record); continue end
            local assets = tracker:GetPlayerAssets(player)
            if not assets or assets.Humanoid.Health <= 0 then hide(record); continue end
            local distance = (camera.CFrame.Position - assets.RootPart.Position).Magnitude
            if distance > math.max(1, espConfig.MaxDistance) then hide(record); continue end
            local color = overlayColor(player, espConfig)
            if chamsEnabled then chams(record, assets.Character, color, espConfig.DepthMode)
            elseif record.Highlight and record.Highlight.Enabled then record.Highlight.Enabled = false end
            if not espEnabled then hideDrawings(record); continue end
            local anchor, visible = rootProjection(camera, assets.RootPart.Position)
            if not visible then concealUnused(record); continue end
            if espConfig.DepthMode == "Occluded" and not cachedVisibility(record, assets.Head or assets.RootPart, assets.Character, now) then
                hideDrawings(record)
                continue
            end
            local position, size = cachedBounds(record, camera, assets.Character, anchor, now)
            if not position or not size then concealUnused(record); continue end
            local centerX, bottom = position.X + size.X / 2, position.Y + size.Y
            if espConfig.Box then
                if espConfig.BoxStyle == "Corner" then drawCornerBox(record, position, size, color)
                else draw(record, "Box", { Position = position, Size = size, Color = color, Thickness = CONFIG.BOX_THICKNESS, Filled = false, Transparency = 1 }) end
            end
            local labelY = position.Y - CONFIG.TEXT_SIZE - 3
            if espConfig.Name and espConfig.Distance then
                draw(record, "Name", { Text = player.Name, Position = Vector2.new(centerX, labelY - CONFIG.TEXT_SIZE - 1),
                    Size = CONFIG.TEXT_SIZE, Font = 2, Center = true, Outline = true, Color = color, Transparency = 1 })
                draw(record, "Distance", { Text = `[{math.floor(distance)}m]`, Position = Vector2.new(centerX, labelY),
                    Size = CONFIG.TEXT_SIZE, Font = 2, Center = true, Outline = true, Color = color, Transparency = 1 })
            elseif espConfig.Name then
                draw(record, "Name", { Text = player.Name, Position = Vector2.new(centerX, labelY),
                    Size = CONFIG.TEXT_SIZE, Font = 2, Center = true, Outline = true, Color = color, Transparency = 1 })
            elseif espConfig.Distance then
                draw(record, "Distance", { Text = `[{math.floor(distance)}m]`, Position = Vector2.new(centerX, labelY),
                    Size = CONFIG.TEXT_SIZE, Font = 2, Center = true, Outline = true, Color = color, Transparency = 1 })
            end
            local healthFraction = math.clamp(assets.Humanoid.Health / math.max(assets.Humanoid.MaxHealth, 1), 0, 1)
            if espConfig.HealthBar then drawHealthBar(record, position, size, healthFraction) end
            if espConfig.Health then
                local healthOffset = if espConfig.HealthBar then 18 else 15
                draw(record, "Health", { Text = tostring(math.max(0, math.floor(assets.Humanoid.Health))), Position = Vector2.new(position.X - healthOffset, position.Y + size.Y / 2),
                    Size = CONFIG.TEXT_SIZE, Font = 2, Center = true, Outline = true, Color = color, Transparency = 1 })
            end
            if espConfig.Tool then
                updateTool(record, assets.Character, now)
                draw(record, "Tool", { Text = record.ToolText, Position = Vector2.new(centerX, bottom + 4),
                    Size = CONFIG.TEXT_SIZE, Font = 2, Center = true, Outline = true, Color = color, Transparency = 1 })
            end
            concealUnused(record)
        end
    end

    local function syncThemeColor()
        if state:Peek("ESP.ColorFollowsTheme") ~= true then return end
        state:Set("ESP.Color", services:Get("ThemeEngine"):GetToken("Accent"))
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
        scope:Add(state:Observe("ESP.ColorFollowsTheme", function(follows: boolean)
            if follows then syncThemeColor() end
        end))
        scope:Add(bus:Subscribe("ThemeChanged", syncThemeColor))
        syncThemeColor()
        syncJob()
    end

    function ESPController:Destroy() scope:Dispose() end

    scope:Add(function() for player in pairs(table.clone(ESPController._records)) do removeRecord(player) end end)
    return ESPController
end
