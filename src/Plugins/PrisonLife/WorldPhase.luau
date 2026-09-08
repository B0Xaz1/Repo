--!nonstrict
-- Prison Life doors & world: discovers obstacle parts from the map's known container
-- folders (doors, glass, celldoors, prison_fences, prison_gate — matched case-insensitively
-- against workspace children) and phases their collision with a transparency preview.
-- Everything inside a known container is phaseable, matching the legacy toggle.
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
        _parts = {},          -- [BasePart] = true
        _containers = {},     -- matched workspace container names
        _containerCount = 0,
        _lastScan = 0,
    }

    -- Legacy truth: these folders hold every phaseable obstacle.
    local function isObstacleFolder(name: any): boolean
        return table.find(manifest.Doors.Folders, tostring(name):lower()) ~= nil
    end

    -- Decorative parts (never collidable, mostly invisible) are skipped on scan.
    local function isDecorative(part: BasePart): boolean
        return part.CanCollide == false and part.Transparency >= 0.5
    end

    local function trackPart(part: BasePart)
        if WorldPhase._parts[part] then return end
        if not part:IsA("BasePart") or part:IsA("Terrain") then return end
        if isDecorative(part) then return end
        WorldPhase._parts[part] = true
        WorldPhase:ApplyPart(part)
    end

    local function trackContainer(container: Instance)
        for _, descendant in ipairs(container:GetDescendants()) do
            if descendant:IsA("BasePart") then trackPart(descendant) end
        end
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
        self._containerCount = 0
        self._containers = {}

        -- Legacy containers first: doors, glass, celldoors, prison_fences, prison_gate.
        for _, child in ipairs(workspace:GetChildren()) do
            if isObstacleFolder(child.Name) then
                table.insert(self._containers, child.Name)
                trackContainer(child)
                self._containerCount += 1
            end
        end
        -- Heuristic fallback for map updates that rename every known container.
        if self._containerCount == 0 then
            for _, child in ipairs(workspace:GetChildren()) do
                if (child:IsA("Model") or child:IsA("Folder")) and matchesAnyPattern(child.Name) then
                    table.insert(self._containers, child.Name)
                    trackContainer(child)
                    self._containerCount += 1
                end
            end
        end

        self._lastScan = os.clock()
        local partCount = 0
        for _ in pairs(self._parts) do partCount += 1 end
        EventBus:Publish("PrisonDoorsChanged", self:GetCounts())
        return partCount, self._containerCount
    end

    function WorldPhase:ApplyPart(part: BasePart)
        if not part.Parent then return end
        if StateStore:Get("Game.DoorPhase") == true then
            changes:SetProperty(part, "CanCollide", false)
            changes:SetProperty(part, "Transparency", math.clamp(
                tonumber(StateStore:Get("Game.PhaseTransparency")) or 0.65, 0.1, 0.95))
        else
            changes:RestoreProperty(part, "CanCollide")
            changes:RestoreProperty(part, "Transparency")
        end
    end

    function WorldPhase:ApplyAll()
        for part in pairs(self._parts) do self:ApplyPart(part) end
        EventBus:Publish("PrisonDoorsChanged", self:GetCounts())
    end

    function WorldPhase:RestoreAll(): number
        for part in pairs(self._parts) do
            changes:RestoreProperty(part, "CanCollide")
            changes:RestoreProperty(part, "Transparency")
        end
        EventBus:Publish("PrisonDoorsChanged", self:GetCounts())
        local count = 0
        for _ in pairs(self._parts) do count += 1 end
        return count
    end

    function WorldPhase:GetCounts(): any
        local parts, phased = 0, 0
        local phaseOn = StateStore:Peek("Game.DoorPhase") == true
        for part in pairs(self._parts) do
            if part.Parent then
                parts += 1
                if phaseOn and part.CanCollide == false then phased += 1 end
            end
        end
        return {
            Parts = parts, Phased = phased, Containers = self._containerCount,
            Folders = table.clone(self._containers), Scanned = self._lastScan > 0,
        }
    end

    function WorldPhase:Initialize()
        self:ScanDoors()

        -- New parts anywhere under a known container are picked up live while phasing.
        scope:Add(scope:ConnectImmediate(workspace.DescendantAdded, function(descendant: Instance)
            if StateStore:Peek("Game.DoorPhase") ~= true then return end
            if not descendant:IsA("BasePart") then return end
            task.defer(function()
                if scope:IsDisposed() or WorldPhase._parts[descendant] then return end
                local current = descendant.Parent
                while current and current ~= workspace do
                    if isObstacleFolder(current.Name) then
                        trackPart(descendant)
                        EventBus:Publish("PrisonDoorsChanged", WorldPhase:GetCounts())
                        return
                    end
                    current = current.Parent
                end
            end)
        end))

        -- A renamed map update may create the containers late.
        scope:Add(scope:ConnectImmediate(workspace.ChildAdded, function(child: Instance)
            task.defer(function()
                if scope:IsDisposed() then return end
                if isObstacleFolder(child.Name) then
                    task.wait(0.5)
                    if not scope:IsDisposed() then WorldPhase:ScanDoors(); WorldPhase:ApplyAll() end
                end
            end)
        end))

        for _, path in ipairs({ "Game.DoorPhase", "Game.PhaseTransparency" }) do
            scope:Add(StateStore:Observe(path, function() self:ApplyAll() end))
        end

        -- The game's door scripts may flip CanCollide back (doors closing); reassert while active.
        reassert = TaskScheduler:RegisterHeartbeat("Game.PrisonLifeDoors", 40, function()
            if StateStore:Peek("Game.DoorPhase") ~= true then return end
            local transparency = math.clamp(tonumber(StateStore:Peek("Game.PhaseTransparency")) or 0.65, 0.1, 0.95)
            for part in pairs(WorldPhase._parts) do
                if part.Parent and part.CanCollide then
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
