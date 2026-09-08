--!nonstrict
-- Prison Life doors & world: discovers door/fence/gate parts, phases collision and applies a
-- visual glow as two independent, individually reversible layers.
return function(services: any, Prison: any?): any
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local Disposer = services:Get("Disposer")
    local TaskScheduler = services:Get("TaskScheduler")
    local workspace = game:GetService("Workspace")

    local Prison = Prison or {}
    local manifest = Prison.Manifest
    local scope = Disposer:CreateChild("PrisonLife.WorldPhase")
    local changes = scope:CreateChild("PrisonLife.WorldPhase.Changes")
    local reassert = nil :: any

    local WorldPhase = {
        _parts = {},     -- [BasePart] = { Class = "Door"|"Cell"|"Fence"|"Gate"|"Glass", Allowed = boolean }
        _folders = {},   -- discovered container names
        _doorModels = 0,
        _lastScan = 0,
    }

    local function includeEnabled(record: any): boolean
        local class = record.Class
        if class == "Cell" then return StateStore:Get("Game.DoorIncludeCells") ~= false end
        if class == "Fence" then return StateStore:Get("Game.DoorIncludeFences") == true end
        if class == "Gate" then return StateStore:Get("Game.DoorIncludeGates") == true end
        if class == "Glass" then return StateStore:Get("Game.DoorIncludeGlass") == true end
        return true
    end

    local function classify(part: BasePart, folderKind: string?): string
        local lowered = part.Name:lower()
        if lowered:find("glass", 1, true) or part.Material == Enum.Material.Glass then return "Glass" end
        if lowered:find("cell", 1, true) then return "Cell" end
        if folderKind == "Fence" or lowered:find("fence", 1, true) then return "Fence" end
        if folderKind == "Gate" then return "Gate" end
        for _, pattern in ipairs(manifest.Doors.GateNames) do
            if lowered:find(pattern:lower(), 1, true) then return "Gate" end
        end
        return "Door"
    end

    local function isDecorative(part: BasePart): boolean
        if StateStore:Get("Game.DoorIgnoreDecorative") == false then return false end
        return part.CanCollide == false and part.Transparency >= 0.5
    end

    local function trackPart(part: BasePart, folderKind: string?)
        if WorldPhase._parts[part] then return end
        if not part:IsA("BasePart") or part:IsA("Terrain") then return end
        if isDecorative(part) then return end
        local record = { Class = classify(part, folderKind), Allowed = true }
        WorldPhase._parts[part] = record
        WorldPhase:ApplyPart(part)
    end

    local function trackContainer(container: Instance, folderKind: string?)
        local models = 0
        if container:IsA("BasePart") then
            trackPart(container, folderKind)
            return 0 -- a bare part is not a door model
        end
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("BasePart") then
                trackPart(child, folderKind)
            elseif child:IsA("Model") or child:IsA("Folder") then
                models += 1
                for _, descendant in ipairs(child:GetDescendants()) do
                    if descendant:IsA("BasePart") then trackPart(descendant, folderKind) end
                end
            end
        end
        return models
    end

    local function matchesAnyPattern(name: string): boolean
        local lowered = name:lower()
        for _, pattern in ipairs(manifest.Doors.NamePatterns) do
            if lowered:find(pattern, 1, true) then return true end
        end
        return false
    end

    function WorldPhase:ScanDoors(): (number, number)
        self._parts = {}
        self._doorModels = 0
        self._folders = {}

        local function discover(folderName: string, kind: string?)
            local folder = workspace:FindFirstChild(folderName)
            if folder then
                table.insert(self._folders, folderName)
                self._doorModels += trackContainer(folder, kind)
                return true
            end
            return false
        end

        local foundDoors = false
        for _, folderName in ipairs(manifest.Doors.Folders) do
            local folder = workspace:FindFirstChild(folderName)
            if folder then
                table.insert(self._folders, folderName)
                for _, child in ipairs(folder:GetChildren()) do
                    trackContainer(child, nil)
                    if child:IsA("Model") or child:IsA("BasePart") then self._doorModels += 1 end
                end
                foundDoors = true
            end
        end
        -- Fences and named gates live in one folder; classify per child so gates never
        -- inherit the fence treatment. Each child counts as one tracked door object.
        local foundFences = false
        local fenceFolder = workspace:FindFirstChild(manifest.Doors.FenceFolder)
        if fenceFolder then
            table.insert(self._folders, manifest.Doors.FenceFolder)
            for _, child in ipairs(fenceFolder:GetChildren()) do
                local kind = if table.find(manifest.Doors.GateNames, child.Name) then "Gate" else "Fence"
                trackContainer(child, kind)
                if child:IsA("Model") or child:IsA("BasePart") then self._doorModels += 1 end
            end
            foundFences = true
        end

        -- Heuristic fallback for map updates that rename the folders.
        if not foundDoors and not foundFences then
            for _, child in ipairs(workspace:GetChildren()) do
                if (child:IsA("Model") or child:IsA("Folder")) and matchesAnyPattern(child.Name) then
                    self._doorModels += trackContainer(child, nil)
                end
            end
        end

        self._lastScan = os.clock()
        local partCount = 0
        for _ in pairs(self._parts) do partCount += 1 end
        EventBus:Publish("PrisonDoorsChanged", self:GetCounts())
        return partCount, self._doorModels
    end

    local function restoreDoorVisual(part: BasePart)
        changes:RestoreProperty(part, "CanCollide")
        changes:RestoreProperty(part, "Transparency")
        changes:RestoreProperty(part, "Material")
        changes:RestoreProperty(part, "Color")
    end

    function WorldPhase:ApplyPart(part: BasePart)
        local record = self._parts[part]
        if not record or not part.Parent then return end
        record.Allowed = includeEnabled(record)
        local phaseEnabled = StateStore:Get("Game.DoorPhase") == true and record.Allowed
        local glowEnabled = StateStore:Get("Game.DoorGlow") == true and record.Allowed

        if not phaseEnabled and not glowEnabled then
            restoreDoorVisual(part)
            return
        end

        if phaseEnabled then
            changes:SetProperty(part, "CanCollide", false)
            changes:SetProperty(part, "Transparency", math.clamp(
                tonumber(StateStore:Get("Game.PhaseTransparency")) or 0.65, 0.1, 0.95))
        else
            changes:RestoreProperty(part, "CanCollide")
            changes:RestoreProperty(part, "Transparency")
        end

        if glowEnabled then
            changes:SetProperty(part, "Material", Enum.Material.Neon)
            changes:SetProperty(part, "Color", StateStore:Get("Game.GlowColor") or Color3.fromRGB(0, 200, 220))
        else
            changes:RestoreProperty(part, "Material")
            changes:RestoreProperty(part, "Color")
        end
    end

    function WorldPhase:ApplyAll()
        for part in pairs(self._parts) do self:ApplyPart(part) end
        EventBus:Publish("PrisonDoorsChanged", self:GetCounts())
    end

    function WorldPhase:RestoreAll(): number
        for part in pairs(self._parts) do restoreDoorVisual(part) end
        EventBus:Publish("PrisonDoorsChanged", self:GetCounts())
        local count = 0
        for _ in pairs(self._parts) do count += 1 end
        return count
    end

    function WorldPhase:GetCounts(): any
        local parts, phased, glowing, doors, cells, fences, gates, glass = 0, 0, 0, 0, 0, 0, 0, 0
        for part, record in pairs(self._parts) do
            if part.Parent then
                parts += 1
                if record.Class == "Door" then doors += 1
                elseif record.Class == "Cell" then cells += 1
                elseif record.Class == "Fence" then fences += 1
                elseif record.Class == "Gate" then gates += 1
                elseif record.Class == "Glass" then glass += 1 end
                if part.CanCollide == false and record.Allowed and StateStore:Peek("Game.DoorPhase") then phased += 1 end
                if part.Material == Enum.Material.Neon and record.Allowed and StateStore:Peek("Game.DoorGlow") then glowing += 1 end
            end
        end
        return {
            Parts = parts, Phased = phased, Glowing = glowing, Doors = doors, Cells = cells,
            Fences = fences, Gates = gates, Glass = glass, Models = self._doorModels,
            Folders = table.clone(self._folders), Scanned = self._lastScan > 0,
        }
    end

    function WorldPhase:Initialize()
        self:ScanDoors()

        -- Watch the known containers for newly streamed/created doors.
        for _, folderName in ipairs(manifest.Doors.Folders) do
            local folder = workspace:FindFirstChild(folderName)
            if folder then
                scope:Connect(folder.ChildAdded, function(child: Instance)
                    task.defer(function()
                        if not scope:IsDisposed() then
                            trackContainer(child, nil)
                            EventBus:Publish("PrisonDoorsChanged", WorldPhase:GetCounts())
                        end
                    end)
                end)
            end
        end
        local fenceFolder = workspace:FindFirstChild(manifest.Doors.FenceFolder)
        if fenceFolder then
            scope:Connect(fenceFolder.ChildAdded, function(child: Instance)
                task.defer(function()
                    if not scope:IsDisposed() then
                        local kind = if table.find(manifest.Doors.GateNames, child.Name) then "Gate" else "Fence"
                        trackContainer(child, kind)
                        EventBus:Publish("PrisonDoorsChanged", WorldPhase:GetCounts())
                    end
                end)
            end)
        end
        scope:Connect(workspace.ChildAdded, function(child: Instance)
            -- A renamed map update may create the door containers late.
            task.defer(function()
                if scope:IsDisposed() then return end
                local name = child.Name
                if table.find(manifest.Doors.Folders, name) or name == manifest.Doors.FenceFolder then
                    task.wait(0.5)
                    if not scope:IsDisposed() then WorldPhase:ScanDoors(); WorldPhase:ApplyAll() end
                end
            end)
        end)

        for _, path in ipairs({
            "Game.DoorPhase", "Game.DoorGlow", "Game.PhaseTransparency", "Game.GlowColor",
            "Game.DoorIncludeFences", "Game.DoorIncludeGates", "Game.DoorIncludeGlass",
            "Game.DoorIncludeCells",
        }) do
            scope:Add(StateStore:Observe(path, function() self:ApplyAll() end))
        end

        -- The game's door scripts may flip CanCollide back while phasing; reassert while active.
        reassert = TaskScheduler:RegisterHeartbeat("Game.PrisonLifeDoors", 40, function()
            if StateStore:Peek("Game.DoorPhase") ~= true then return end
            local transparency = math.clamp(tonumber(StateStore:Peek("Game.PhaseTransparency")) or 0.65, 0.1, 0.95)
            for part, record in pairs(WorldPhase._parts) do
                if part.Parent and record.Allowed and includeEnabled(record) and part.CanCollide then
                    changes:SetProperty(part, "CanCollide", false)
                    if math.abs(part.Transparency - transparency) > 0.01 then
                        changes:SetProperty(part, "Transparency", transparency)
                    end
                end
            end
        end)
        scope:Add(reassert)
    end

    function WorldPhase:Destroy()
        self:RestoreAll()
        if reassert then reassert:Disconnect() end
        scope:Dispose()
        table.clear(self._parts)
    end

    return WorldPhase
end
