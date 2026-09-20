local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CONFIG = table.freeze({
    DISPLAY_ORDER = 100000,
    MIN_BOX_WIDTH = 12,
    MIN_BOX_HEIGHT = 24,
    HEALTH_BAR_WIDTH = 3,
    HEALTH_BAR_OFFSET = 6,
    NAME_OFFSET_Y = 15,
    NAME_HEIGHT = 14,
    HEALTH_HUE_SPAN = 0.33,
    OUTLINE_THICKNESS = 3,
})

return function(services: any, Duel: any?): any
    local StateStore = services:Get("StateStore")
    local Disposer = services:Get("Disposer")
    local LocalPlayer = Players.LocalPlayer

    local Duel = Duel or {}
    local manifest = Duel.Manifest
    local config = manifest.Esp
    local scope = Disposer:CreateChild(`{manifest.Name}.Esp`)

    local Esp = { _gui = nil, _pool = {}, _visible = 0 }

    local function createGui(): ScreenGui
        local gui = Instance.new("ScreenGui")
        gui.Name = config.GuiName
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = CONFIG.DISPLAY_ORDER
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.Enabled = false
        return gui
    end

    local function createVisual(index: number, parent: Instance): any
        local outline = Instance.new("Frame")
        outline.Name = `Outline{index}`
        outline.BackgroundTransparency = 1
        outline.BorderColor3 = config.Outline
        outline.BorderSizePixel = CONFIG.OUTLINE_THICKNESS
        outline.Visible = false
        outline.ZIndex = 10
        outline.Parent = parent

        local box = Instance.new("Frame")
        box.Name = `Box{index}`
        box.BackgroundTransparency = 1
        box.BorderColor3 = config.Accent
        box.BorderSizePixel = 1
        box.Visible = false
        box.ZIndex = 11
        box.Parent = parent

        local healthBack = Instance.new("Frame")
        healthBack.Name = `HealthBack{index}`
        healthBack.BackgroundColor3 = config.Outline
        healthBack.BorderSizePixel = 0
        healthBack.Visible = false
        healthBack.ZIndex = 10
        healthBack.Parent = parent

        local health = Instance.new("Frame")
        health.Name = `Health{index}`
        health.BackgroundColor3 = config.Accent
        health.BorderSizePixel = 0
        health.Visible = false
        health.ZIndex = 11
        health.Parent = parent

        local name = Instance.new("TextLabel")
        name.Name = `Name{index}`
        name.BackgroundTransparency = 1
        name.Text = ""
        name.TextColor3 = config.Text
        name.TextSize = 9
        name.Font = Enum.Font.Code
        name.TextXAlignment = Enum.TextXAlignment.Left
        name.TextYAlignment = Enum.TextYAlignment.Center
        name.Visible = false
        name.ZIndex = 12
        name.Parent = parent

        return { Outline = outline, Box = box, HealthBack = healthBack, Health = health, Name = name }
    end

    local function hideVisual(visual: any)
        visual.Outline.Visible = false
        visual.Box.Visible = false
        visual.HealthBack.Visible = false
        visual.Health.Visible = false
        visual.Name.Visible = false
    end

    local function projectBounds(character: Model, camera: Camera): (number?, number?, number?, number?)
        local ok, cf, size = pcall(function() return character:GetBoundingBox() end)
        if not ok or not cf or not size then return nil, nil, nil, nil end
        local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
        local onScreen = false
        for sx = -1, 1, 2 do
            for sy = -1, 1, 2 do
                for sz = -1, 1, 2 do
                    local worldPoint = cf:PointToWorldSpace(Vector3.new(hx * sx, hy * sy, hz * sz))
                    local screen, visible = camera:WorldToViewportPoint(worldPoint)
                    if screen.Z > 0 then
                        onScreen = onScreen or visible
                        minX = math.min(minX, screen.X); minY = math.min(minY, screen.Y)
                        maxX = math.max(maxX, screen.X); maxY = math.max(maxY, screen.Y)
                    end
                end
            end
        end
        if not onScreen or minX == math.huge then return nil, nil, nil, nil end
        local viewport = camera.ViewportSize
        if maxX < 0 or minX > viewport.X or maxY < 0 or minY > viewport.Y then return nil, nil, nil, nil end
        return math.floor(minX), math.floor(minY), math.max(CONFIG.MIN_BOX_WIDTH, math.floor(maxX - minX)), math.max(CONFIG.MIN_BOX_HEIGHT, math.floor(maxY - minY))
    end

    local function drawVisual(visual: any, x: number, y: number, width: number, height: number, humanoid: Humanoid, displayName: string)
        local ratio = humanoid.MaxHealth > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) or 0
        visual.Outline.Position = UDim2.fromOffset(x - 1, y - 1)
        visual.Outline.Size = UDim2.fromOffset(width + 2, height + 2)
        visual.Outline.Visible = true
        visual.Box.Position = UDim2.fromOffset(x, y)
        visual.Box.Size = UDim2.fromOffset(width, height)
        visual.Box.Visible = true
        visual.HealthBack.Position = UDim2.fromOffset(x - CONFIG.HEALTH_BAR_OFFSET, y)
        visual.HealthBack.Size = UDim2.fromOffset(CONFIG.HEALTH_BAR_WIDTH, height)
        visual.HealthBack.Visible = true
        visual.Health.Position = UDim2.fromOffset(x - CONFIG.HEALTH_BAR_OFFSET, y + height * (1 - ratio))
        visual.Health.Size = UDim2.fromOffset(CONFIG.HEALTH_BAR_WIDTH, math.max(1, height * ratio))
        visual.Health.BackgroundColor3 = Color3.fromHSV(ratio * CONFIG.HEALTH_HUE_SPAN, 0.85, 0.95)
        visual.Health.Visible = true
        visual.Name.Text = string.upper(displayName)
        visual.Name.Position = UDim2.fromOffset(x, y - CONFIG.NAME_OFFSET_Y)
        visual.Name.Size = UDim2.fromOffset(width, CONFIG.NAME_HEIGHT)
        visual.Name.Visible = true
    end

    local function paint()
        local used = 0
        local camera = Workspace.CurrentCamera
        if StateStore:Get("Game.MvSEsp") == true and LocalPlayer.Team ~= nil and LocalPlayer:GetAttribute(manifest.Match.Attribute) ~= nil and camera then
            for _, enemy in ipairs(Duel.Targets:GetOpponents()) do
                if used >= #Esp._pool then break end
                local x, y, width, height = projectBounds(enemy.Character, camera)
                if x then
                    used += 1
                    drawVisual(Esp._pool[used], x, y, width, height, enemy.Humanoid, enemy.Player.DisplayName or enemy.Player.Name)
                end
            end
        end
        Esp._visible = used
        for index = used + 1, #Esp._pool do hideVisual(Esp._pool[index]) end
    end

    function Esp:Initialize()
        self._gui = createGui()
        for index = 1, config.MaxVisuals do
            self._pool[index] = createVisual(index, self._gui)
        end
        self._gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
        scope:Add(self._gui)

        local clock = 0
        scope:Add(RunService.RenderStepped:Connect(function(delta: number)
            clock += delta
            if clock < config.Interval then return end
            clock = 0
            if not self._gui then return end
            local enabled = StateStore:Get("Game.MvSEsp") == true
            if self._gui.Enabled ~= enabled then self._gui.Enabled = enabled end
            pcall(paint)
        end))

        pcall(paint)
    end

    function Esp:GetCounts(): any
        return { Enabled = StateStore:Get("Game.MvSEsp") == true, Visible = self._visible, Pool = #self._pool }
    end

    function Esp:Destroy() scope:Dispose() end

    return Esp
end
