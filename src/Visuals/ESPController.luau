--!nonstrict
local FONTS: { [string]: number } = { UI = 0, System = 1, Plex = 2, Monospace = 3 }
local R15 = { { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" }, { "UpperTorso", "LeftUpperArm" },
    { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" }, { "UpperTorso", "RightUpperArm" },
    { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" }, { "LowerTorso", "LeftUpperLeg" },
    { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" }, { "LowerTorso", "RightUpperLeg" },
    { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" } }
local R6 = { { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" }, { "Torso", "Left Leg" }, { "Torso", "Right Leg" } }

return function(services: any): any
    local state, tracker, pool, filter = services:Get("StateStore"), services:Get("PlayerTracker"), services:Get("DrawingPool"), services:Get("TargetFilter")
    local scheduler, bus, environment = services:Get("TaskScheduler"), services:Get("EventBus"), services:Get("Environment")
    local scope = services:Get("Disposer"):CreateChild("ESPController")
    local players, workspace = game:GetService("Players"), game:GetService("Workspace")
    local ESPController = { _records = {}, _initialized = false, _chamsAvailable = true }

    local function hide(record: any)
        for _, object in pairs(record.Drawings) do object.Visible = false end
        if record.Highlight then record.Highlight.Enabled = false end
    end
    local function createRecord(player: Player)
        if player == players.LocalPlayer or ESPController._records[player] then return end
        local owner = scope:CreateChild("ESP " .. player.UserId)
        local record = { Player = player, Scope = owner, Drawings = {}, Highlight = nil, Signature = "", InventoryText = "", ToolText = "", InventoryAt = -math.huge }
        ESPController._records[player] = record
        if pool.Available then
            for name, kind in pairs({ Box = "Square", HealthBackground = "Square", Health = "Square", Name = "Text", Distance = "Text",
                Tool = "Text", Backpack = "Text", Tracer = "Line", HeadDot = "Circle", LookDir = "Line" }) do
                record.Drawings[name] = pool:Acquire(kind)
            end
            for index = 1, #R15 do record.Drawings["Bone" .. index] = pool:Acquire("Line") end
        end
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
    local function draw(record: any, name: string, properties: any)
        local object = record.Drawings[name]
        if not object then return end
        for property, value in pairs(properties) do object[property] = value end
        object.Visible = true
    end
    local function project(camera: Camera, position: Vector3, inset: Vector2): (Vector2, boolean)
        local point, visible = camera:WorldToViewportPoint(position)
        return Vector2.new(point.X, point.Y) + inset, visible and point.Z > 0
    end
    local function bounds(camera: Camera, character: Model, inset: Vector2): (Vector2?, Vector2?)
        local frame, size = character:GetBoundingBox()
        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
        for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
            local point = camera:WorldToViewportPoint((frame * CFrame.new(size.X * x / 2, size.Y * y / 2, size.Z * z / 2)).Position)
            if point.Z <= 0 then return nil, nil end
            minX, minY, maxX, maxY = math.min(minX, point.X), math.min(minY, point.Y), math.max(maxX, point.X), math.max(maxY, point.Y)
        end end end
        if maxX < 0 or minX > camera.ViewportSize.X or maxY < 0 or minY > camera.ViewportSize.Y then return nil, nil end
        return Vector2.new(minX, minY) + inset, Vector2.new(maxX - minX, maxY - minY)
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
        object.Adornee, object.Parent = assets.Character, assets.Character
        object.FillColor = if config.UseTeamColor then filter:GetTeamColor(record.Player) else config.FillColor
        object.OutlineColor = config.OutlineColor
        object.DepthMode = if config.DepthMode == "Occluded" then Enum.HighlightDepthMode.Occluded else Enum.HighlightDepthMode.AlwaysOnTop
        object.Enabled = true
    end
    local function render(_dt: number)
        local camera = workspace.CurrentCamera
        local config, chamsConfig = state:Get("ESP"), state:Get("Chams")
        local espEnabled = pool.Available and config.Enabled and state:HasPermission("ESP.Enabled")
        local chamsEnabled = chamsConfig.Enabled and state:HasPermission("Chams.Enabled")
        local inset = environment:GetGuiInset()
        for player, record in pairs(ESPController._records) do
            hide(record)
            if not camera or (not espEnabled and not chamsEnabled) then continue end
            local assets = tracker:GetPlayerAssets(player)
            if not assets or assets.Humanoid.Health <= 0 then continue end
            if config.TeamCheck and filter:IsTeammate(player) then continue end
            local distance = (camera.CFrame.Position - assets.RootPart.Position).Magnitude
            if distance > math.max(1, config.MaxDist) then continue end
            if chamsEnabled then chams(record, assets, chamsConfig) end
            if not espEnabled then continue end
            local position, size = bounds(camera, assets.Character, inset)
            if not position or not size then continue end
            local centerX, bottom = position.X + size.X / 2, position.Y + size.Y
            local color = config.Color
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
            if config.Tracers then draw(record, "Tracer", { From = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y) + inset, To = Vector2.new(centerX, bottom), Color = color }) end
            local head, headVisible = project(camera, assets.Head.Position, inset)
            if config.HeadDot and headVisible then draw(record, "HeadDot", { Position = head, Radius = math.clamp(size.X / 8, 2, 7), Filled = true, Color = color }) end
            if config.LookDir and headVisible then
                local endpoint, visible = project(camera, assets.Head.Position + assets.Head.CFrame.LookVector * 5, inset)
                if visible then draw(record, "LookDir", { From = head, To = endpoint, Color = color }) end
            end
            if config.Skeleton then
                local bones = if assets.Humanoid.RigType == Enum.HumanoidRigType.R15 then R15 else R6
                for index, pair in ipairs(bones) do
                    local first, second = assets.Character:FindFirstChild(pair[1]), assets.Character:FindFirstChild(pair[2])
                    if first and second and first:IsA("BasePart") and second:IsA("BasePart") then
                        local a, aVisible = project(camera, first.Position, inset)
                        local b, bVisible = project(camera, second.Position, inset)
                        if aVisible and bVisible then draw(record, "Bone" .. index, { From = a, To = b, Color = color, Thickness = 1 }) end
                    end
                end
            end
        end
    end
    function ESPController:Initialize()
        if self._initialized then return end
        self._initialized = true
        for _, player in ipairs(players:GetPlayers()) do createRecord(player) end
        scope:Add(bus:Subscribe("PlayerJoined", createRecord))
        scope:Add(bus:Subscribe("PlayerLeft", removeRecord))
        scope:Add(scheduler:RegisterRender("Visuals.ESP", 10, render))
    end
    function ESPController:Destroy() scope:Dispose() end
    scope:Add(function() for player in pairs(table.clone(ESPController._records)) do removeRecord(player) end end)
    return ESPController
end
