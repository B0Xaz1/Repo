--!nonstrict
-- Prison Life Game tab: a lean control center.
-- Left: Armory (MP5 / Remington 870 / AK-47 buttons) / Weapon mods.
-- Right: Doors & obstacles / Weapon macro / Map locations.
return function(services: any, Prison: any?): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)
    local keybind = load("src/UI/Components/Keybind.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)

    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local ThemeEngine, DOM = services:Get("ThemeEngine"), services:Get("DOM")
    local TaskScheduler = services:Get("TaskScheduler")

    local Prison = Prison or {}
    local manifest = Prison.Manifest
    local scope = services:Get("Disposer"):CreateChild(manifest.Name .. ".UI")

    local UI = {}

    -- Status lines use the compact code-face style from the design brief.
    local function createInfoLabel(parent: Instance, text: string): TextLabel
        return DOM:Create("TextLabel", {
            Text = "  " .. text,
            Font = Enum.Font.Code,
            TextSize = 11,
            TextColor3 = ThemeEngine:GetToken("TextDim"),
            TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -8, 0, 18),
            Parent = parent,
        }) :: TextLabel
    end

    -- Every TextLabel write cascades up through the AutomaticSize chain (label -> section
    -- -> column -> page canvas), so writes are change-detected: identical text is skipped.
    local function setLabel(label: TextLabel, text: string)
        if not label.Parent then return end
        local nextText = "  " .. text
        if label.Text ~= nextText then label.Text = nextText end
    end

    local function fmtDistance(distance: number?): string
        if distance == nil then return "?" end
        return string.format("%d studs", distance)
    end

    function UI:Build(tab: any)
        -- Shared state for the low-rate refresh job.
        local labels = {}

        ------------------------------------------------------------------
        -- 1. Armory (left): three giver buttons, one per ranged guest gun.
        -- Pickup is requested through the game's own ITEMPICKUP flow first; if the
        -- invoke comes back rejected the player is teleported to the giver spawn and
        -- the same request is repeated once at ground level.
        ------------------------------------------------------------------
        local armorySec = section:Create(tab.LeftCol, "Armory")
        labels.armory = createInfoLabel(armorySec, "Inventory: ...")
        labels.armory.TextWrapped = true
        local function obtainWeapon(name: string): (boolean, string)
            if not Prison.Armory then return false, "Armory unavailable" end
            local ok, message = Prison.Armory:Pickup(name)
            if ok then return true, message end
            local traveled, travelMessage = Prison.Armory:GoToWeapon(name)
            if not traveled then return false, travelMessage end
            return Prison.Armory:Pickup(name)
        end
        textbox:CreateButton(armorySec, "Get MP5", function()
            return obtainWeapon("MP5")
        end)
        textbox:CreateButton(armorySec, "Get Remington 870", function()
            return obtainWeapon("Remington 870")
        end)
        textbox:CreateButton(armorySec, "Get AK-47", function()
            return obtainWeapon("AK-47")
        end)
        textbox:CreateButton(armorySec, "Arm all three", function()
            return Prison.Armory and Prison.Armory:ArmAll()
        end)
        section:Info(armorySec, "Request runs through the game's own ITEMPICKUP flow; a rejected invoke falls back to the spawn teleport plus a second request. Granted guns land in the backpack.")

        ------------------------------------------------------------------
        -- 2. Weapon Mods (left)
        ------------------------------------------------------------------
        local modsSec = section:Create(tab.LeftCol, "Weapon Mods")
        toggle(modsSec, "No spread", "Game.NoSpread")
        toggle(modsSec, "Fast fire rate", "Game.FastFire")
        toggle(modsSec, "Force full-auto", "Game.ForceAuto")
        toggle(modsSec, "Force infinite range", "Game.ForceRange")
        slider(modsSec, "Fast fire delay", "Game.FastFireDelay", 0.001, 0.5, 0.001, "s")
        slider(modsSec, "Force range value", "Game.ForceRangeValue", 500, 10000, 100, " studs")
        labels.weapons = createInfoLabel(modsSec, "Weapons: ...")
        textbox:CreateButton(modsSec, "Restore weapon values", function()
            for _, path in ipairs({ "Game.NoSpread", "Game.FastFire", "Game.ForceAuto", "Game.ForceRange" }) do
                StateStore:Set(path, false)
            end
            return true, "Weapon values restored"
        end)
        textbox:CreateButton(modsSec, "Re-scan current weapons", function()
            if Prison.WeaponMods then Prison.WeaponMods:Reapply() return true, "Weapon re-scan complete" end
            return false, "Weapon mods unavailable"
        end)
        section:Info(modsSec, "Disabling a switch restores the captured gun values immediately. Client-side gun changes are testing behavior; a server-authoritative experience may reject them.")

        ------------------------------------------------------------------
        -- 3. Doors and Obstacles (right)
        ------------------------------------------------------------------
        local doorsSec = section:Create(tab.RightCol, "Doors and Obstacles")
        toggle(doorsSec, "Phase doors & fences", "Game.DoorPhase")
        slider(doorsSec, "Phase transparency", "Game.PhaseTransparency", 0.1, 0.95, 0.05)
        labels.doors = createInfoLabel(doorsSec, "Doors: ...")
        textbox:CreateButton(doorsSec, "Scan doors", function()
            if Prison.WorldPhase then
                Prison.WorldPhase:ScanDoors()
                Prison.WorldPhase:ApplyAll()
                return true, "Door scan complete"
            end
            return false, "World phase unavailable"
        end)
        textbox:CreateButton(doorsSec, "Restore door originals", function()
            StateStore:Set("Game.DoorPhase", false)
            if Prison.WorldPhase then Prison.WorldPhase:RestoreAll() end
            return true, "Door properties restored"
        end)
        section:Info(doorsSec, "Phases every obstacle inside the legacy containers (doors, glass, celldoors, prison_fences, prison_gate). Turning it off restores collision and transparency.")

        ------------------------------------------------------------------
        -- 4. Weapon Macro (right)
        ------------------------------------------------------------------
        local macroSec = section:Create(tab.RightCol, "Weapon Macro")
        toggle(macroSec, "Weapon switch macro", "Game.FakeMacro")
        keybind(macroSec, "Macro key", "Game.FakeMacroKey")
        dropdown(macroSec, "Macro mode", "Game.FakeMacroMode", { "Toggle", "Hold" })
        slider(macroSec, "Switch delay", "Game.FakeMacroDelay", 0.03, 0.5, 0.01, "s")
        labels.macro = createInfoLabel(macroSec, "Macro: Idle")
        textbox:CreateButton(macroSec, "Stop macro", function()
            if Prison.Macro then Prison.Macro:Stop("user request") return true, "Macro stopped" end
            return false, "Macro unavailable"
        end)
        section:Info(macroSec, "Cycles the guns you hold; needs at least two. Stops on death, respawn, focus loss, weapon loss, and unload. Hold mode runs only while the key is down.")

        ------------------------------------------------------------------
        -- 5. Map Locations (right)
        ------------------------------------------------------------------
        local routesSec = section:Create(tab.RightCol, "Map Locations")
        labels.nearest = createInfoLabel(routesSec, "Nearest: ...")
        local favoriteHost = DOM:Create("Frame", {
            Parent = routesSec, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
        })
        DOM:Create("UIListLayout", { Parent = favoriteHost, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
        local function rebuildFavoriteButtons()
            for _, child in ipairs(favoriteHost:GetChildren()) do
                if child:IsA("GuiObject") then DOM:DestroyInstance(child) end
            end
            if not Prison.Locations then return end
            for index, name in ipairs(Prison.Locations:GetFavoriteNames()) do
                textbox:CreateButton(favoriteHost, "Go: " .. name, function()
                    return Prison.Locations:TeleportToName(name)
                end).Row.LayoutOrder = 100 + index
            end
        end
        rebuildFavoriteButtons()
        scope:Add(StateStore:Observe("Game.FavoriteLocations", rebuildFavoriteButtons))

        local locationPicker = dropdown(routesSec, "Location", nil, Prison.Locations and Prison.Locations:GetLocationNames("All") or {})
        local categoryPicker
        local function refreshLocations()
            if not Prison.Locations then return end
            locationPicker:Refresh(Prison.Locations:GetLocationNames(categoryPicker and categoryPicker:Get() or "All"), true)
        end
        -- The dropdown callback fires only on user selection, so this never loops.
        categoryPicker = dropdown(routesSec, "Location category", nil, { "All", table.unpack(manifest.LocationCategories) }, function()
            task.defer(refreshLocations)
        end)
        textbox:CreateButton(routesSec, "Teleport to location", function()
            return Prison.Locations and Prison.Locations:TeleportToName(locationPicker:Get() or "")
        end)
        textbox:CreateButton(routesSec, "Save position as waypoint", function()
            return Prison.Locations and Prison.Locations:SaveWaypoint()
        end)
        textbox:CreateButton(routesSec, "Toggle favorite", function()
            if not Prison.Locations then return false, "Location service unavailable" end
            return Prison.Locations:ToggleFavorite(Prison.Locations:GetLocationByName(locationPicker:Get() or ""))
        end)
        labels.favorites = createInfoLabel(routesSec, "Favorites: none")
        local waypointPicker = dropdown(routesSec, "Waypoint", nil, {})
        textbox:CreateButton(routesSec, "Go to waypoint", function()
            return Prison.Locations and Prison.Locations:GoToWaypoint(waypointPicker:Get() or "")
        end)
        textbox:CreateButton(routesSec, "Delete waypoint", function()
            return Prison.Locations and Prison.Locations:DeleteWaypoint(waypointPicker:Get() or "")
        end)
        labels.waypoints = createInfoLabel(routesSec, "Waypoints: 0")
        local function refreshWaypoints()
            if not Prison.Locations then return end
            waypointPicker:Refresh(Prison.Locations:ListWaypoints(), true)
            setLabel(labels.waypoints, "Waypoints: " .. tostring(#Prison.Locations:ListWaypoints()))
        end
        scope:Add(EventBus:Subscribe("PrisonWaypointsChanged", refreshWaypoints))
        section:Info(routesSec, "Locations resolve from tagged map objects first, then named map objects, then manifest coordinates. Waypoints are session-only.")

        ------------------------------------------------------------------
        -- Low-rate refresh job for every dynamic label. Rendering is gated to run only
        -- while the menu is open AND the Game tab is the active page: each label write
        -- cascades through the AutomaticSize layout chain, so painting an invisible or
        -- background tab is pure waste. Returning to the tab forces one immediate paint.
        ------------------------------------------------------------------
        local REFRESH_INTERVAL = 0.5
        local armorySignature = ""
        local menuVisible = StateStore:Get("Settings.MenuVisible") ~= false
        local gameTabActive = false
        local forceRender = false
        scope:Add(StateStore:Observe("Settings.MenuVisible", function(value: any)
            menuVisible = value == true
            if menuVisible then forceRender = true end
        end))
        scope:Add(EventBus:Subscribe("TabSelected", function(name: string)
            local active = name == "Game"
            if active and not gameTabActive then forceRender = true end
            gameTabActive = active
        end))

        local function renderStatus()
            if Prison.Armory then
                local inventory = Prison.Armory:GetInventory()
                local localPosition = Prison.Locations and Prison.Locations:GetLocalPosition() or nil
                local lines = {}
                for _, entry in ipairs(inventory) do
                    if #lines < 10 then
                        -- Weapon spawns are plain Vector3 positions; measure them directly
                        -- instead of routing through the location resolver.
                        local distance = ""
                        if entry.Weapon.Spawn and localPosition then
                            distance = "  " .. fmtDistance((entry.Weapon.Spawn - localPosition).Magnitude)
                        end
                        table.insert(lines, string.format("[%s] %s%s", entry.Weapon.Name, entry.Status, distance))
                    end
                end
                local signature = table.concat(lines, "|") .. "#" .. tostring(#inventory)
                if signature ~= armorySignature then
                    armorySignature = signature
                    labels.armory.Text = "  Inventory:\n  " .. table.concat(lines, "\n  ")
                    labels.armory.Size = UDim2.new(1, -8, 0, 16 * (#lines + 1))
                end
            end

            if Prison.WeaponMods then
                local stats = Prison.WeaponMods:GetStats()
                setLabel(labels.weapons, "Weapons: " .. tostring(stats.Scanned) .. " tracked"
                    .. (if #stats.Names > 0 then " (" .. table.concat(stats.Names, ", ") .. ")" else ""))
            end

            if Prison.WorldPhase then
                local counts = Prison.WorldPhase:GetCounts()
                setLabel(labels.doors, "Doors: " .. tostring(counts.Containers) .. " containers, " .. tostring(counts.Parts) .. " parts"
                    .. "  Phased: " .. tostring(counts.Phased)
                    .. (if #counts.Folders > 0 then "  [" .. table.concat(counts.Folders, ", ") .. "]" else "  [heuristic scan]"))
            end

            if Prison.Macro then
                local status = Prison.Macro:GetStatus()
                setLabel(labels.macro, "Macro: " .. status.State:upper()
                    .. "  Next: " .. status.NextTool
                    .. string.format("  Delay: %dms", status.Delay * 1000)
                    .. "  Cycles: " .. tostring(status.Cycles)
                    .. (if status.StopReason then "  Reason: " .. status.StopReason else "  Reason: -"))
            end

            if Prison.Locations then
                local nearest = Prison.Locations:GetNearestSummary()
                if nearest then
                    setLabel(labels.nearest, "Nearest: " .. nearest.Name .. " (" .. fmtDistance(nearest.Distance) .. ")")
                end
                local favorites = Prison.Locations:GetFavoriteNames()
                setLabel(labels.favorites, "Favorites: " .. (if #favorites > 0 then table.concat(favorites, ", ") else "none"))
            end
        end

        local function paint()
            local ok, err = pcall(renderStatus)
            if not ok then warn("[B0Xaz][" .. manifest.Name .. ":UI] " .. tostring(err)) end
        end
        local accumulator = 0
        local job = TaskScheduler:RegisterHeartbeat("Game." .. manifest.Name:gsub("%s+", "") .. "UI", 45, function(dt: number)
            if not menuVisible or not gameTabActive then
                accumulator = 0
                return
            end
            if forceRender then
                accumulator = REFRESH_INTERVAL
            else
                accumulator += dt
            end
            if accumulator < REFRESH_INTERVAL then return end
            accumulator, forceRender = 0, false
            paint()
        end)
        scope:Add(job)
        scope:Spawn(function()
            task.wait(0.1)
            if not scope:IsDisposed() then paint() end
        end)
    end

    function UI:Destroy() scope:Dispose() end

    return UI
end
