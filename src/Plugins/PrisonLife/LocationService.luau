--!nonstrict
-- Prison Life locations: tag/name discovery with manifest fallbacks, nearest tracking,
-- waypoints, and favorites.
return function(services: any, Prison: any?): any
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local Disposer = services:Get("Disposer")
    local PlayerTracker = services:Get("PlayerTracker")
    local LocomotionService = services:Get("LocomotionService")
    local CollectionService = game:GetService("CollectionService")
    local Players = game:GetService("Players")

    local Prison = Prison or {}
    local manifest = Prison.Manifest
    local scope = Disposer:CreateChild("PrisonLife.Locations")
    local workspace = game:GetService("Workspace")

    local LocationService = {
        _resolved = {},      -- [Id] = { CFrame = CFrame, Source = "Tag" | "Name" | "Fallback" }
        _nameIndex = {},     -- [lowered keyword] = Instance
        _waypoints = {},     -- ordered { Name, CFrame }
        _scanCount = 0,
    }

    local function cframeFromInstance(instance: Instance): CFrame?
        if instance:IsA("BasePart") then return instance.CFrame end
        if instance:IsA("Model") then
            local pivot = instance:GetPivot()
            return pivot + Vector3.new(0, 3, 0)
        end
        return nil
    end

    -- Preferred resolution order: tagged map object, named map object, manifest fallback.
    local function resolve(location: any): any
        local cached = LocationService._resolved[location.Id]
        if cached then return cached end

        local tag = manifest.TagPrefix .. ":" .. location.Id
        for _, instance in ipairs(CollectionService:GetTagged(tag)) do
            local frame = cframeFromInstance(instance)
            if frame then
                cached = { CFrame = frame, Source = "Tag" }
                break
            end
        end
        if not cached then
            for _, keyword in ipairs(location.Keywords or {}) do
                local instance = LocationService._nameIndex[keyword]
                if instance then
                    local frame = cframeFromInstance(instance)
                    if frame then
                        cached = { CFrame = frame, Source = "Name" }
                        break
                    end
                end
            end
        end
        if not cached then cached = { CFrame = location.CFrame, Source = "Fallback" } end
        LocationService._resolved[location.Id] = cached
        return cached
    end

    -- One workspace pass indexing models/parts by the manifest keywords (lower case, spaces stripped).
    function LocationService:ScanMapObjects(): number
        local index = {}
        local ok, count = pcall(function()
            local found = 0
            for _, instance in ipairs(workspace:GetDescendants()) do
                if instance:IsA("Model") or instance:IsA("BasePart") then
                    local key = tostring(instance.Name):lower():gsub("%s+", "")
                    local matched = false
                    for _, location in ipairs(manifest.Locations) do
                        for _, keyword in ipairs(location.Keywords or {}) do
                            if key:find(keyword, 1, true) and not index[keyword] then
                                index[keyword] = instance
                                matched = true
                                found += 1
                                break
                            end
                        end
                        if matched then break end
                    end
                end
            end
            return found
        end)
        self._nameIndex = if ok then index else {}
        self._scanCount += 1
        table.clear(self._resolved)
        return if ok then count else 0
    end

    function LocationService:GetLocations(): { any } return manifest.Locations end

    function LocationService:GetCategoryNames(): { string } return manifest.LocationCategories end

    function LocationService:GetLocationNames(category: string?): { string }
        local names = {}
        for _, location in ipairs(manifest.Locations) do
            if category == nil or category == "All" or location.Category == category then
                table.insert(names, location.Name)
            end
        end
        return names
    end

    function LocationService:GetLocationByName(name: string): any?
        local lowered = tostring(name or ""):lower()
        for _, location in ipairs(manifest.Locations) do
            if location.Name:lower() == lowered or location.Id:lower() == lowered then return location end
        end
        return nil
    end

    function LocationService:GetResolvedCFrame(location: any): (CFrame?, string)
        local resolved = resolve(location)
        return resolved.CFrame, resolved.Source
    end

    function LocationService:GetLocalPosition(): Vector3?
        local assets = PlayerTracker:GetLocalAssets()
        return assets and assets.RootPart.Position or nil
    end

    function LocationService:GetDistance(location: any): number?
        local position = self:GetLocalPosition()
        local frame = resolve(location)
        if not position then return nil end
        return (frame.CFrame.Position - position).Magnitude
    end

    function LocationService:GetNearest(): (any?, number?)
        local position = self:GetLocalPosition()
        if not position then return nil, nil end
        local best, bestDistance = nil, nil
        for _, location in ipairs(manifest.Locations) do
            local frame = resolve(location)
            local distance = (frame.CFrame.Position - position).Magnitude
            if not bestDistance or distance < bestDistance then
                best, bestDistance = location, distance
            end
        end
        return best, bestDistance
    end

    function LocationService:GetNearestSummary(): any?
        local location, distance = self:GetNearest()
        if not location then return nil end
        return { Name = location.Name, Distance = distance, Source = resolve(location).Source }
    end

    function LocationService:TeleportTo(location: any): (boolean, string)
        if not location then return false, "Select a location first" end
        local frame = resolve(location)
        local ok, message = LocomotionService:Teleport(frame.CFrame)
        return ok, if ok then ("Teleported to " .. location.Name) else message
    end

    function LocationService:TeleportToName(name: string): (boolean, string)
        return self:TeleportTo(self:GetLocationByName(name))
    end

    -- Session waypoints ------------------------------------------------------------

    function LocationService:SaveWaypoint(name: string?): (boolean, string)
        local assets = PlayerTracker:GetLocalAssets()
        if not assets then return false, "Your character is not ready" end
        local clean = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 48)
        if clean == "" then clean = "WP " .. tostring(#self._waypoints + 1) end
        table.insert(self._waypoints, { Name = clean, CFrame = assets.RootPart.CFrame })
        EventBus:Publish("PrisonWaypointsChanged")
        return true, "Saved waypoint " .. clean
    end

    function LocationService:ListWaypoints(): { string }
        local names = {}
        for _, waypoint in ipairs(self._waypoints) do table.insert(names, waypoint.Name) end
        return names
    end

    function LocationService:GoToWaypoint(name: string): (boolean, string)
        for _, waypoint in ipairs(self._waypoints) do
            if waypoint.Name == name then
                local ok, message = LocomotionService:Teleport(waypoint.CFrame)
                return ok, if ok then ("Teleported to " .. name) else message
            end
        end
        return false, "Select a saved waypoint"
    end

    function LocationService:DeleteWaypoint(name: string): (boolean, string)
        for index, waypoint in ipairs(self._waypoints) do
            if waypoint.Name == name then
                table.remove(self._waypoints, index)
                EventBus:Publish("PrisonWaypointsChanged")
                return true, "Removed waypoint " .. name
            end
        end
        return false, "Select a saved waypoint"
    end

    -- Favorites --------------------------------------------------------------------

    function LocationService:IsFavorite(location: any): boolean
        if not location then return false end
        return table.find(StateStore:Get("Game.FavoriteLocations") or {}, location.Id) ~= nil
    end

    function LocationService:ToggleFavorite(location: any): (boolean, string)
        if not location then return false, "Select a location first" end
        local favorites = StateStore:Get("Game.FavoriteLocations") or {}
        local index = table.find(favorites, location.Id)
        if index then
            table.remove(favorites, index)
            StateStore:Set("Game.FavoriteLocations", favorites)
            return true, location.Name .. " removed from favorites"
        end
        table.insert(favorites, location.Id)
        StateStore:Set("Game.FavoriteLocations", favorites)
        return true, location.Name .. " added to favorites"
    end

    function LocationService:GetFavoriteNames(): { string }
        local names = {}
        for _, location in ipairs(manifest.Locations) do
            if self:IsFavorite(location) then table.insert(names, location.Name) end
        end
        return names
    end

    function LocationService:Initialize()
        scope:Spawn(function()
            -- Defer the first map scan: the workspace can still be streaming in.
            task.wait(1)
            if not scope:IsDisposed() then self:ScanMapObjects() end
        end)
    end

    function LocationService:Destroy() scope:Dispose() end

    return LocationService
end
