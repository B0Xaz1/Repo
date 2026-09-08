--!nonstrict
local FONTS: { [string]: number } = { UI = 0, System = 1, Plex = 2, Monospace = 3 }
local R15 = { { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" }, { "UpperTorso", "LeftUpperArm" },
    { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" }, { "UpperTorso", "RightUpperArm" },
    { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" }, { "LowerTorso", "LeftUpperLeg" },
    { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" }, { "LowerTorso", "RightUpperLeg" },
    { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" } }
local R6 = { { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" }, { "Torso", "Left Leg" }, { "Torso", "Right Leg" } }
local BASE_DRAWINGS: { [string]: string } = { Box = "Square", HealthBackground = "Square", Health = "Square", Name = "Text", Distance = "Text",
    Tool = "Text", Backpack = "Text", Tracer = "Line", HeadDot = "Circle", LookDir = "Line" }

return function(services: any): any
    local state, tracker, pool, filter = services:Get("StateStore"), services:Get("PlayerTracker"), services:Get("DrawingPool"), services:Get("TargetFilter")
    local scheduler, bus = services:Get("TaskScheduler"), services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("ESPController")
    local players, workspace = game:GetService("Players"), game:GetService("Workspace")
    local ESPController = { _records = {}, _initialized = false, _chamsAvailable = true, _idle = true, _job = nil }

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
        if player == players.LocalPlayer or ESPController._records[player] then return end
        local owner = scope:CreateChild("ESP " .. player.UserId)
        local record = { Player = player, Scope = owner, Drawings = {}, Highlight = nil, Signature = "", InventoryText = "", ToolText = "",
            InventoryAt = -math.huge, Shown = {}, Last = {}, Bones = false, Rig = nil, BoneParts = nil }
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
    local function ensureDrawings(record: any)
        if not pool.Available or record.Drawings.Box then return end
        for name, kind in pairs(BASE_DRAWINGS) do record.Drawings[name] = pool:Acquire(kind) end
    end
    local function ensureBones(record: any)
        if not pool.Available or record.Bones then return end
        for index = 1, #R15 do record.Drawings["Bone" .. index] = pool:Acquire("Line") end
        record.Bones = true
    end
    local function draw(record: any, name: string, properties: any)
        local object = record.Drawings[name]
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
    -- Drawing primitives live in WorldToViewportPoint space. Adding GuiInset drops every overlay by the topbar height.
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
    local function updateInventory(record: any, character: Model)
        if os.clock() - record.InventoryAt < 0.25 then return end
        record.InventoryAt = os.clock()
        local equipped, backpack = {}, {}
        for _, tool in ipairs(character:GetChildren()) do if tool:IsA("Tool") then table.insert(equipped, tool.Name) end end
        local bag = record.Player:FindFirstChildOfClass("Backpack")
        if bag then for _, tool in ipairs(bag:GetChildren()) do if tool:IsA("Tool") then table.insert(backpack, tool.Name) end end end
        table.sort(equipped); table.sort(backpack)
        local signature = table.concat(equipped, "\0") .. "\1" .. table.concat(backpack, "\0")
        if signature ~= record.Signature then
            record.Signature, record.ToolText, record.InventoryText = signature, table.concat(equipped, ", "), table.concat(backpack, ", ")
        end
    end
    local function rainbowColor(): Color3
        return Color3.fromHSV((os.clock() * 0.15) % 1, 0.75, 1)
    end
    local function overlayColor(player: Player, config: any, fallback: Color3, source: string?): Color3
        if config.Rainbow then return rainbowColor() end
        -- Game plugins (for example Prison Life role colors) can resolve player colors
        -- through this transient hook; returning nil falls through to the standard logic.
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
                object.Name, object.FillTransparency, object.OutlineTransparency = "B0XazChams", 0.55, 0.1
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
        local outline = if config.Rainbow then fill:Lerp(Color3.new(1, 1, 1), 0.35) else config.OutlineColor
        if object.OutlineColor ~= outline then object.OutlineColor = outline end
        local depth = if state:Peek("ESP.DepthMode") == "Occluded" then Enum.HighlightDepthMode.Occluded else Enum.HighlightDepthMode.AlwaysOnTop
        if object.DepthMode ~= depth then object.DepthMode = depth end
        if not object.Enabled then object.Enabled = true end
    end
    local function boneParts(record: any, assets: any): any
        if record.Rig == assets.Character and record.BoneParts then return record.BoneParts end
        record.Rig = assets.Character
        local pairsForRig = if assets.Humanoid.RigType == Enum.HumanoidRigType.R15 then R15 else R6
        local parts = {}
        for index, pair in ipairs(pairsForRig) do
            local first, second = assets.Character:FindFirstChild(pair[1]), assets.Character:FindFirstChild(pair[2])
            parts[index] = { first, second }
        end
        record.BoneParts = parts
        return parts
    end
    local function render(_dt: number)
        local config, chamsConfig = state:Peek("ESP"), state:Peek("Chams")
        local espEnabled = pool.Available and config.Enabled
        local chamsEnabled = chamsConfig.Enabled
        if not espEnabled and not chamsEnabled then
            if not ESPController._idle then hideAll(); ESPController._idle = true end
            return
        end
        ESPController._idle = false
        local camera = workspace.CurrentCamera
        local occluded = config.DepthMode == "Occluded"
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
            if occluded and not filter:IsVisible(assets.Head or assets.RootPart) then hideDrawings(record); continue end
            ensureDrawings(record)
            local position, size = bounds(camera, assets.Character)
            if not position or not size then hideDrawings(record); continue end
            local centerX, bottom = position.X + size.X / 2, position.Y + size.Y
            local color = overlayColor(player, config, config.Color, "ESP")
            local scale = if config.AutoScaling then math.clamp(1.25 - distance / 1500, 0.7, 1.25) else 1
            local textSize, font = math.round(13 * scale), FONTS[config.Font] or 2
            if config.Box then draw(record, "Box", { Position = position, Size = size, Color = color, Thickness = 1, Filled = false }) end
            if config.Name then draw(record, "Name", { Text = player.DisplayName .. (if player.DisplayName ~= player.Name then " (@" .. player.Name .. ")" else ""),
                Position = Vector2.new(centerX, position.Y - textSize - 3), Size = textSize, Font = font, Outline = config.Outline, Color = color }) end
            if config.Health then
                local fraction = math.clamp(assets.Humanoid.Health / math.max(assets.Humanoid.MaxHealth, 1), 0, 1)
                draw(record, "HealthBackground", { Position = position - Vector2.new(7, 0), Size = Vector2.new(4, size.Y), Color = Color3.fromRGB(15, 19, 25), Filled = true })
                draw(record, "Health", { Position = position - Vector2.new(6, -size.Y * (1 - fraction)), Size = Vector2.new(2, size.Y * fraction),
                    Color = Color3.fromRGB(247, 87, 105):Lerp(Color3.fromRGB(79, 222, 157), fraction), Filled = true })
            end
            local textY = bottom + 3
            if config.Distance then
                draw(record, "Distance", { Text = math.floor(distance) .. " studs", Position = Vector2.new(centerX, textY), Size = textSize, Font = font, Outline = config.Outline, Color = color })
                textY += textSize + 1
            end
            if config.Tool or config.Backpack then updateInventory(record, assets.Character) end
            if config.Tool and record.ToolText ~= "" then
                draw(record, "Tool", { Text = record.ToolText, Position = Vector2.new(centerX, textY), Size = textSize, Font = font, Outline = config.Outline, Color = color }); textY += textSize + 1
            end
            if config.Backpack and record.InventoryText ~= "" then
                draw(record, "Backpack", { Text = "Bag: " .. record.InventoryText, Position = Vector2.new(centerX, textY), Size = textSize, Font = font, Outline = config.Outline, Color = color })
            end
            if config.Tracers then draw(record, "Tracer", { From = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y), To = Vector2.new(centerX, bottom), Color = color }) end
            local head, headVisible = nil, false
            if config.HeadDot or config.LookDir then head, headVisible = project(camera, assets.Head.Position) end
            if config.HeadDot and headVisible then draw(record, "HeadDot", { Position = head, Radius = math.clamp(size.X / 8, 2, 7), Filled = true, Color = color }) end
            if config.LookDir and headVisible then
                local endpoint, visible = project(camera, assets.Head.Position + assets.Head.CFrame.LookVector * 5)
                if visible then draw(record, "LookDir", { From = head, To = endpoint, Color = color }) end
            end
            if config.Skeleton then
                ensureBones(record)
                for index, pair in ipairs(boneParts(record, assets)) do
                    local first, second = pair[1], pair[2]
                    if first and second and first:IsA("BasePart") and second:IsA("BasePart") then
                        local a, aVisible = project(camera, first.Position)
                        local b, bVisible = project(camera, second.Position)
                        if aVisible and bVisible then draw(record, "Bone" .. index, { From = a, To = b, Color = color, Thickness = 1 }) end
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
        for _, player in ipairs(players:GetPlayers()) do createRecord(player) end
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
