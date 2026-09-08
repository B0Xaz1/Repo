--!nonstrict
-- Prison Life Game tab: a contextual control center rather than a pile of toggles.
-- Left: Status / Role rules / Armory / Weapon profiles / Melee.
-- Right: Routes & locations / Doors & world / Macro / Player watch / Diagnostics.
return function(services: any, Prison: any?): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)
    local keybind = load("src/UI/Components/Keybind.luau", services)
    local colorpicker = load("src/UI/Components/ColorPicker.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)

    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local ThemeEngine, DOM = services:Get("ThemeEngine"), services:Get("DOM")
    local TaskScheduler = services:Get("TaskScheduler")
    local PlayerTracker = services:Get("PlayerTracker")

    local Prison = Prison or {}
    local manifest = Prison.Manifest
    local scope = services:Get("Disposer"):CreateChild("PrisonLife.UI")

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

    local function setLabel(label: TextLabel, text: string)
        if label.Parent then label.Text = "  " .. text end
    end

    local function fmtDistance(distance: number?): string
        if distance == nil then return "?" end
        return string.format("%d studs", distance)
    end

    function UI:Build(tab: any)
        -- Shared state for the low-rate refresh job.
        local labels = {}

        ------------------------------------------------------------------
        -- 1. Prison Life Status (left)
        ------------------------------------------------------------------
        local statusSec = section:Create(tab.LeftCol, "Prison Life Status")
        labels.role = createInfoLabel(statusSec, "Role: ...")
        labels.team = createInfoLabel(statusSec, "Team: ...")
        labels.alive = createInfoLabel(statusSec, "Status: ...")
        labels.health = createInfoLabel(statusSec, "Health: ...")
        labels.equipped = createInfoLabel(statusSec, "Equipped: ...")
        labels.nearest = createInfoLabel(statusSec, "Nearest: ...")
        labels.session = createInfoLabel(statusSec, "Session: 0:00")
        labels.plugin = createInfoLabel(statusSec, "Plugin: Ready")
        textbox:CreateButton(statusSec, "Refresh context", function()
            if Prison.Context then Prison.Context:Refresh() end
            return true, "Context refreshed"
        end)
        textbox:CreateButton(statusSec, "Save current position", function()
            if Prison.Locations then return Prison.Locations:SaveWaypoint() end
            return false, "Location service unavailable"
        end)
        textbox:CreateButton(statusSec, "Restore temporary world changes", function()
            if Prison.Diagnostics then return Prison.Diagnostics:RestoreAll() end
            return false, "Diagnostics unavailable"
        end)
        textbox:CreateButton(statusSec, "Stop all macros", function()
            if Prison.StopAllAutomation then Prison.StopAllAutomation("user request") end
            return true, "Macros and routes stopped"
        end)
        textbox:CreateButton(statusSec, "Re-scan tools and map objects", function()
            if Prison.Diagnostics then return Prison.Diagnostics:RescanAll() end
            return false, "Diagnostics unavailable"
        end)
        keybind(statusSec, "Panic stop key", "Game.PanicKey")

        ------------------------------------------------------------------
        -- 2. Role and Target Rules (left)
        ------------------------------------------------------------------
        local roleSec = section:Create(tab.LeftCol, "Role and Target Rules")
        dropdown(roleSec, "Role detection", "Game.RoleMode", { "Auto", "Prisoner", "Guard", "Criminal" }, function()
            if Prison.Context then Prison.Context:Refresh() end
        end)
        dropdown(roleSec, "Target role", "Game.TargetRole", { "Any", "Prisoner", "Guard", "Criminal" })
        toggle(roleSec, "Role-aware filters", "Game.RoleAware")
        toggle(roleSec, "Ignore same role", "Game.IgnoreSameRole")
        toggle(roleSec, "Ignore guards", "Game.IgnoreGuards")
        toggle(roleSec, "Ignore prisoners", "Game.IgnorePrisoners")
        toggle(roleSec, "Ignore criminals", "Game.IgnoreCriminals")
        toggle(roleSec, "Role-colored ESP", "Game.RoleColoredESP")
        toggle(roleSec, "Role-colored chams", "Game.RoleColoredChams")
        toggle(roleSec, "Role change toasts", "Game.SessionOverlay")
        section:Info(roleSec, "Role rules layer on top of the universal team, friend, whitelist, and force-field checks used by the aimbot, triggerbot, and melee.")

        ------------------------------------------------------------------
        -- 3. Armory and Loadouts (left)
        ------------------------------------------------------------------
        local armorySec = section:Create(tab.LeftCol, "Armory and Loadouts")
        labels.armory = createInfoLabel(armorySec, "Inventory: ...")
        local weaponNames = {}
        for _, weapon in ipairs(manifest.Weapons) do table.insert(weaponNames, weapon.Name) end
        local weaponPicker = dropdown(armorySec, "Weapon", nil, weaponNames)
        textbox:CreateButton(armorySec, "Go to weapon", function()
            return Prison.Armory and Prison.Armory:GoToWeapon(weaponPicker:Get() or "")
        end)
        textbox:CreateButton(armorySec, "Equip if owned", function()
            return Prison.Armory and Prison.Armory:Equip(weaponPicker:Get() or "")
        end)
        textbox:CreateButton(armorySec, "Request pickup (ItemHandler)", function()
            return Prison.Armory and Prison.Armory:Pickup(weaponPicker:Get() or "")
        end)
        textbox:CreateButton(armorySec, "Add to loadout", function()
            return Prison.Armory and Prison.Armory:AddToLoadout(weaponPicker:Get() or "")
        end)
        textbox:CreateButton(armorySec, "Remove from loadout", function()
            return Prison.Armory and Prison.Armory:RemoveFromLoadout(weaponPicker:Get() or "")
        end)
        labels.loadout = createInfoLabel(armorySec, "Loadout: empty")
        local loadoutName = textbox(armorySec, "Loadout name", "")
        local presetPicker = dropdown(armorySec, "Loadout preset", nil, Prison.Armory and Prison.Armory:GetLoadoutPresetNames() or {})
        local function refreshPresets()
            if Prison.Armory and presetPicker then presetPicker:Refresh(Prison.Armory:GetLoadoutPresetNames(), true) end
        end
        textbox:CreateButton(armorySec, "Apply loadout preset", function()
            return Prison.Armory and Prison.Armory:ApplyLoadoutPreset(presetPicker:Get() or "")
        end)
        textbox:CreateButton(armorySec, "Equip loadout", function()
            return Prison.Armory and Prison.Armory:EquipLoadout()
        end)
        textbox:CreateButton(armorySec, "Save current loadout", function()
            local ok, message = Prison.Armory and Prison.Armory:SaveCurrentLoadout(loadoutName.Box.Text) or false, "Armory unavailable"
            if ok then refreshPresets() end
            return ok, message
        end)
        textbox:CreateButton(armorySec, "Restore previous loadout", function()
            return Prison.Armory and Prison.Armory:RestorePreviousLoadout()
        end)
        textbox:CreateButton(armorySec, "Refresh weapon scan", function()
            if Prison.Armory then Prison.Armory:Scan() return true, "Weapon scan refreshed" end
            return false, "Armory unavailable"
        end)
        section:Info(armorySec, "Pickup uses the game's own ITEMPICKUP flow. Spawn coordinates are fallbacks; the armory scan reads your live backpack and character.")

        ------------------------------------------------------------------
        -- 4. Weapon Profiles (left)
        ------------------------------------------------------------------
        local profileSec = section:Create(tab.LeftCol, "Weapon Profiles")
        local profileOptions = { "Default", "Accuracy", "Rapid Fire", "Automatic", "Long Range", "Custom" }
        -- Selecting a preset writes the four switches; the WeaponMods observer applies them.
        dropdown(profileSec, "Weapon profile", "Game.WeaponProfile", profileOptions)
        -- Manual switches move the profile to Custom; observers handle the actual reapply.
        local function manualSwitch(callback: any?): any
            return function(value: any)
                if StateStore:Get("Game.WeaponProfile") ~= "Custom" then StateStore:Set("Game.WeaponProfile", "Custom") end
                if callback then callback(value) end
            end
        end
        toggle(profileSec, "No spread", "Game.NoSpread", manualSwitch())
        toggle(profileSec, "Fast fire rate", "Game.FastFire", manualSwitch())
        toggle(profileSec, "Force full-auto", "Game.ForceAuto", manualSwitch())
        toggle(profileSec, "Force infinite range", "Game.ForceRange", manualSwitch())
        slider(profileSec, "Fast fire delay", "Game.FastFireDelay", 0.001, 0.5, 0.001, "s")
        slider(profileSec, "Force range value", "Game.ForceRangeValue", 500, 10000, 100, " studs")
        labels.weapons = createInfoLabel(profileSec, "Weapons: ...")
        textbox:CreateButton(profileSec, "Restore weapon values", function()
            for _, path in ipairs({ "Game.NoSpread", "Game.FastFire", "Game.ForceAuto", "Game.ForceRange" }) do
                StateStore:Set(path, false)
            end
            return true, "Weapon values restored"
        end)
        textbox:CreateButton(profileSec, "Re-scan current weapons", function()
            if Prison.WeaponMods then Prison.WeaponMods:Reapply() return true, "Weapon re-scan complete" end
            return false, "Weapon mods unavailable"
        end)
        section:Info(profileSec, "Disabling a switch restores the captured GunStates values immediately. Client-side gun changes are visual/testing behavior; a server-authoritative experience may reject them.")

        ------------------------------------------------------------------
        -- 5. Melee Controls (left)
        ------------------------------------------------------------------
        local meleeSec = section:Create(tab.LeftCol, "Melee Controls")
        toggle(meleeSec, "Punch aura", "Game.PunchAura")
        slider(meleeSec, "Aura radius", "Game.PunchAuraRange", 5, 40, 1, " studs")
        toggle(meleeSec, "Super multi-punch", "Game.SuperPunch")
        slider(meleeSec, "Hit multiplier", "Game.SuperPunchHits", 1, 30, 1, "x")
        dropdown(meleeSec, "Melee target role", "Game.MeleeTargetRole", { "Any", "Prisoner", "Guard", "Criminal" })
        dropdown(meleeSec, "Aura targets", "Game.MeleePriority", { "Everyone", "Nearest", "Lowest Health" })
        slider(meleeSec, "Max actions per second", "Game.MeleeMaxPerSecond", 1, 30, 1, "/s")
        toggle(meleeSec, "Team check", "Game.MeleeTeamCheck")
        toggle(meleeSec, "Friend check", "Game.MeleeFriendCheck")
        toggle(meleeSec, "Whitelist check", "Game.MeleeWhitelistCheck")
        toggle(meleeSec, "Force-field check", "Game.MeleeForceFieldCheck")
        toggle(meleeSec, "Line of sight", "Game.MeleeLOS")
        labels.melee = createInfoLabel(meleeSec, "Melee: ...")
        section:Info(meleeSec, "The aura punches every valid target in radius each tick and stops while dead or typing. Super punch fires on left click while your fists are out.")

        ------------------------------------------------------------------
        -- 6. Routes and Map Locations (right)
        ------------------------------------------------------------------
        local routesSec = section:Create(tab.RightCol, "Routes and Map Locations")
        labels.routeNearest = createInfoLabel(routesSec, "Nearest: ...")
        labels.favorites = createInfoLabel(routesSec, "Favorites: none")
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
        textbox:CreateButton(routesSec, "Set as route start", function()
            if not Prison.Locations then return false, "Location service unavailable" end
            local location = Prison.Locations:GetLocationByName(locationPicker:Get() or "")
            if not location then return false, "Select a location first" end
            Prison.Locations:ClearCustomRoute()
            return Prison.Locations:AddCustomStop(location)
        end)
        textbox:CreateButton(routesSec, "Set as route end", function()
            if not Prison.Locations then return false, "Location service unavailable" end
            local location = Prison.Locations:GetLocationByName(locationPicker:Get() or "")
            if not location then return false, "Select a location first" end
            return Prison.Locations:AddCustomStop(location)
        end)
        textbox:CreateButton(routesSec, "Toggle favorite", function()
            if not Prison.Locations then return false, "Location service unavailable" end
            return Prison.Locations:ToggleFavorite(Prison.Locations:GetLocationByName(locationPicker:Get() or ""))
        end)
        dropdown(routesSec, "Route", "Game.SelectedRoute", Prison.Locations and Prison.Locations:GetRouteNames() or { "None", "Custom" })
        textbox:CreateButton(routesSec, "Run route", function()
            if not Prison.Locations then return false, "Location service unavailable" end
            return Prison.Locations:StartRoute(StateStore:Get("Game.SelectedRoute") or "None")
        end)
        textbox:CreateButton(routesSec, "Stop route", function()
            if Prison.Locations then Prison.Locations:StopRoute("user request") return true, "Route stopped" end
            return false, "Location service unavailable"
        end)
        textbox:CreateButton(routesSec, "Add location to custom route", function()
            if not Prison.Locations then return false, "Location service unavailable" end
            return Prison.Locations:AddCustomStop(Prison.Locations:GetLocationByName(locationPicker:Get() or ""))
        end)
        textbox:CreateButton(routesSec, "Clear custom route", function()
            return Prison.Locations and Prison.Locations:ClearCustomRoute()
        end)
        slider(routesSec, "Route step delay", "Game.RouteDelay", 0.25, 10, 0.25, "s")
        labels.route = createInfoLabel(routesSec, "Route: Idle")
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
        section:Info(routesSec, "Locations resolve from tagged map objects first, then named map objects, then manifest coordinates. Waypoints and custom routes are session-only.")

        ------------------------------------------------------------------
        -- 7. Doors and World Interaction (right)
        ------------------------------------------------------------------
        local doorsSec = section:Create(tab.RightCol, "Doors and World Interaction")
        dropdown(doorsSec, "Door mode", nil, { "Off", "Visual Preview", "Phase Active" }, function(value: any)
            if value == "Off" then
                StateStore:Set("Game.DoorPhase", false)
                StateStore:Set("Game.DoorGlow", false)
            elseif value == "Visual Preview" then
                StateStore:Set("Game.DoorPhase", false)
                StateStore:Set("Game.DoorGlow", true)
            elseif value == "Phase Active" then
                StateStore:Set("Game.DoorPhase", true)
                StateStore:Set("Game.DoorGlow", true)
            end
        end)
        toggle(doorsSec, "Door phase", "Game.DoorPhase")
        toggle(doorsSec, "Door glow", "Game.DoorGlow")
        slider(doorsSec, "Phase transparency", "Game.PhaseTransparency", 0.1, 0.95, 0.05)
        colorpicker(doorsSec, "Glow color", "Game.GlowColor")
        toggle(doorsSec, "Include cell doors", "Game.DoorIncludeCells")
        toggle(doorsSec, "Include fences", "Game.DoorIncludeFences")
        toggle(doorsSec, "Include gates", "Game.DoorIncludeGates")
        toggle(doorsSec, "Include glass", "Game.DoorIncludeGlass")
        toggle(doorsSec, "Ignore decorative doors", "Game.DoorIgnoreDecorative")
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
            StateStore:Set("Game.DoorGlow", false)
            if Prison.WorldPhase then Prison.WorldPhase:RestoreAll() end
            return true, "Door properties restored"
        end)
        section:Info(doorsSec, "Phasing and glow are independent layers over the legacy obstacle containers (doors, glass, celldoors, prison_fences, prison_gate); disabling either restores exactly its own properties. Decorative filtering applies on the next scan.")

        ------------------------------------------------------------------
        -- 8. Weapon Macro (right)
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
        section:Info(macroSec, "Stops on death, respawn, focus loss, weapon loss, panic key, and unload. Hold mode runs only while the key is down.")

        ------------------------------------------------------------------
        -- 9. Player Watch (right)
        ------------------------------------------------------------------
        local watchSec = section:Create(tab.RightCol, "Player Watch")
        labels.groups = createInfoLabel(watchSec, "Players: ...")
        labels.threats = createInfoLabel(watchSec, "Threats: ...")
        local watchPicker = dropdown(watchSec, "Watched player", nil, {})
        textbox:CreateButton(watchSec, "Spectate player", function()
            if not Prison.PlayerWatch then return false, "Player watch unavailable" end
            local player = Prison.PlayerWatch:ResolveWatchName(watchPicker:Get() or "")
            if not player then return false, "Select a player who is still in the server" end
            Prison.PlayerWatch._selected = player
            return PlayerTracker:StartSpectate(player)
        end)
        textbox:CreateButton(watchSec, "Stop spectating", function()
            PlayerTracker:StopSpectate()
            return true, "Camera subject restored"
        end)
        textbox:CreateButton(watchSec, "Whitelist player", function()
            if not Prison.PlayerWatch then return false, "Player watch unavailable" end
            local player = Prison.PlayerWatch:ResolveWatchName(watchPicker:Get() or "")
            return PlayerTracker:AddWhitelist(player)
        end)
        textbox:CreateButton(watchSec, "Copy username", function()
            if not Prison.PlayerWatch then return false, "Player watch unavailable" end
            local player = Prison.PlayerWatch:ResolveWatchName(watchPicker:Get() or "")
            return PlayerTracker:CopyName(player)
        end)
        labels.selected = createInfoLabel(watchSec, "Selected: ...")
        toggle(watchSec, "Join and leave alerts", "Game.WatchAlerts")
        section:Info(watchSec, "Distances, tools, and roles refresh live. Role colors feed ESP and chams through the toggles in Role and Target Rules.")

        ------------------------------------------------------------------
        -- 10. Diagnostics and Restore (right)
        ------------------------------------------------------------------
        local diagSec = section:Create(tab.RightCol, "Diagnostics and Restore")
        labels.diagnostics = createInfoLabel(diagSec, "Diagnostics: ...")
        labels.diagnostics.TextWrapped = true
        textbox:CreateButton(diagSec, "Restore all temporary changes", function()
            return Prison.Diagnostics and Prison.Diagnostics:RestoreAll()
        end)
        textbox:CreateButton(diagSec, "Re-scan map, doors, and weapons", function()
            return Prison.Diagnostics and Prison.Diagnostics:RescanAll()
        end)
        section:Info(diagSec, "Weapon values, door properties, and automations are all reversible. Last error and backup counters come from the live services.")

        ------------------------------------------------------------------
        -- Low-rate refresh job (4 Hz) for every dynamic label.
        ------------------------------------------------------------------
        local watchSignature = ""
        local armorySignature = ""
        local accumulator = 0

        local function renderStatus()
            local context = Prison.Context
            if context then
                local snapshot = context:GetSnapshot()
                setLabel(labels.role, "Role: " .. snapshot.Role .. (snapshot.Role ~= snapshot.AutoRole and " (auto: " .. snapshot.AutoRole .. ")" or ""))
                setLabel(labels.team, "Team: " .. snapshot.TeamName)
                setLabel(labels.alive, "Status: " .. (if snapshot.IsAlive then "Alive" else "Dead") .. " (" .. snapshot.CharacterStatus .. ")")
                setLabel(labels.health, "Health: " .. tostring(snapshot.Health) .. " / " .. tostring(snapshot.MaxHealth))
                setLabel(labels.equipped, "Equipped: " .. snapshot.EquippedTool)
                if snapshot.NearestLocation then
                    setLabel(labels.nearest, "Nearest: " .. snapshot.NearestLocation.Name .. " (" .. fmtDistance(snapshot.NearestLocation.Distance) .. ", " .. snapshot.NearestLocation.Source .. ")")
                else
                    setLabel(labels.nearest, "Nearest: -")
                end
                setLabel(labels.session, "Session: " .. context:FormatDuration())
            end
            if Prison.Diagnostics then
                local lastError = Prison.Diagnostics:GetLastError()
                setLabel(labels.plugin, "Plugin: " .. (if lastError then "Error - " .. lastError else "Ready"))
            end

            if Prison.Armory then
                local inventory = Prison.Armory:GetInventory()
                local lines = {}
                for index, entry in ipairs(inventory) do
                    if #lines < 9 then
                        local distance = if entry.Weapon.Spawn then Prison.Locations and fmtDistance(select(2, Prison.Locations:GetDistance(entry.Weapon))) or "" else ""
                        table.insert(lines, string.format("[%s] %s%s", entry.Weapon.Name, entry.Status, if distance ~= "" then "  " .. distance else ""))
                    end
                end
                local signature = table.concat(lines, "|") .. "#" .. tostring(#inventory)
                if signature ~= armorySignature then
                    armorySignature = signature
                    labels.armory.Text = "  Inventory:\n  " .. table.concat(lines, "\n  ")
                    labels.armory.Size = UDim2.new(1, -8, 0, 16 * (#lines + 1))
                    local loadout = Prison.Armory:GetLoadoutNames()
                    setLabel(labels.loadout, "Loadout: " .. (if #loadout > 0 then table.concat(loadout, ", ") else "empty"))
                end
            end

            if Prison.WeaponMods then
                local stats = Prison.WeaponMods:GetStats()
                setLabel(labels.weapons, "Weapons: " .. tostring(stats.Scanned) .. " tracked"
                    .. (if #stats.Names > 0 then " (" .. table.concat(stats.Names, ", ") .. ")" else "")
                    .. "  Profile: " .. tostring(stats.Profile))
            end

            if Prison.Melee then
                local status = Prison.Melee:GetStatus()
                setLabel(labels.melee, "Melee: " .. (if status.Enabled then (if status.Running then "RUNNING" else "PAUSED") else "off")
                    .. "  Ready: " .. (if status.Ready then "yes" else string.format("%.2fs", status.Cooldown))
                    .. "  Actions: " .. tostring(status.Actions)
                    .. "  Last: " .. status.LastTarget
                    .. (if status.RemoteFound then "" else "  [remote missing]"))
            end

            if Prison.Locations then
                local nearest = Prison.Locations:GetNearestSummary()
                if nearest then
                    setLabel(labels.routeNearest, "Nearest: " .. nearest.Name .. " (" .. fmtDistance(nearest.Distance) .. ")")
                end
                local favorites = Prison.Locations:GetFavoriteNames()
                setLabel(labels.favorites, "Favorites: " .. (if #favorites > 0 then table.concat(favorites, ", ") else "none"))
                local route = Prison.Locations:GetRouteStatus()
                local routeText = "Route: " .. route.State
                if route.State == "Running" then
                    routeText = "Route: RUNNING " .. tostring(route.Index) .. "/" .. tostring(route.Count) .. " - " .. tostring(route.CurrentStop or "")
                elseif route.StopReason then
                    routeText = "Route: " .. route.State .. " (" .. route.StopReason .. ")"
                end
                if #(route.CustomStops) > 0 then
                    routeText = routeText .. "  Custom: " .. tostring(#route.CustomStops) .. " stops"
                end
                setLabel(labels.route, routeText)
            end

            if Prison.WorldPhase then
                local counts = Prison.WorldPhase:GetCounts()
                setLabel(labels.doors, "Doors: " .. tostring(counts.Models) .. " models, " .. tostring(counts.Parts) .. " parts"
                    .. "  Phased: " .. tostring(counts.Phased)
                    .. "  Glowing: " .. tostring(counts.Glowing)
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

            if Prison.PlayerWatch then
                local groups = Prison.PlayerWatch:GetGroups()
                local lines = {}
                for _, group in ipairs(groups) do
                    local names = {}
                    for index, entry in ipairs(group.Entries) do
                        if index <= 4 then
                            table.insert(names, entry.Player.Name .. " " .. fmtDistance(entry.Distance))
                        end
                    end
                    if #group.Entries > 4 then table.insert(names, "+" .. tostring(#group.Entries - 4)) end
                    table.insert(lines, string.format("%s (%d): %s", string.upper(group.Role), #group.Entries, table.concat(names, ", ")))
                end
                labels.groups.Text = "  " .. (if #lines > 0 then table.concat(lines, "\n  ") else "No other players")
                labels.groups.Size = UDim2.new(1, -8, 0, 16 * math.max(1, #lines))
                local threats = Prison.PlayerWatch:GetThreats(3)
                local threatNames = {}
                for _, entry in ipairs(threats) do
                    table.insert(threatNames, entry.Player.Name .. " [" .. entry.Role .. "] " .. fmtDistance(entry.Distance))
                end
                setLabel(labels.threats, "Threats: " .. (if #threatNames > 0 then table.concat(threatNames, ", ") else "none nearby"))
                local selected = Prison.PlayerWatch:GetSelected()
                if selected and selected.Parent then
                    local detail = Prison.PlayerWatch:ResolveWatchName(selected.Name)
                    if detail then
                        local assets = PlayerTracker:GetPlayerAssets(detail)
                        local distance = nil
                        local localAssets = PlayerTracker:GetLocalAssets()
                        if assets and localAssets then distance = (assets.RootPart.Position - localAssets.RootPart.Position).Magnitude end
                        local role = Prison.Context and Prison.Context:GetPlayerRole(detail) or "Unknown"
                        local tool = "None"
                        if assets then
                            for _, child in ipairs(assets.Character:GetChildren()) do
                                if child:IsA("Tool") then tool = child.Name break end
                            end
                        end
                        setLabel(labels.selected, "Selected: " .. detail.Name .. "  " .. role .. "  " .. fmtDistance(distance) .. "  Tool: " .. tool)
                    end
                else
                    setLabel(labels.selected, "Selected: -")
                end
                -- Keep the watch list fresh (players join/leave, roles change) without spamming Refresh.
                local names = Prison.PlayerWatch:GetWatchNames()
                local signature = table.concat(names, "|")
                if signature ~= watchSignature then
                    watchSignature = signature
                    watchPicker:Refresh(names, true)
                end
            end

            if Prison.Diagnostics then
                local report = Prison.Diagnostics:Collect()
                labels.diagnostics.Text = "  " .. Prison.Diagnostics:Format(report):gsub("\n", "\n  ")
                labels.diagnostics.Size = UDim2.new(1, -8, 0, 16 * 12)
            end
        end

        local job = TaskScheduler:RegisterHeartbeat("Game.PrisonLifeUI", 45, function(dt: number)
            accumulator += dt
            if accumulator < 0.25 then return end
            accumulator = 0
            local ok, err = pcall(renderStatus)
            if not ok then warn("[B0Xaz][PrisonLife:UI] " .. tostring(err)) end
        end)
        scope:Add(job)
        scope:Spawn(function()
            task.wait(0.1)
            if not scope:IsDisposed() then
                local ok, err = pcall(renderStatus)
                if not ok then warn("[B0Xaz][PrisonLife:UI] " .. tostring(err)) end
            end
        end)

        -- Role-change toasts only fire when the role actually flips (health ticks must not spam).
        local lastToastRole = nil :: string?
        scope:Add(EventBus:Subscribe("PrisonContextChanged", function(snapshot: any)
            local role = snapshot and snapshot.Role or "Unknown"
            if role == lastToastRole then return end
            lastToastRole = role
            if StateStore:Get("Game.SessionOverlay") == true then
                EventBus:Publish("Notify", "Prison Life", "You are now a " .. role)
            end
        end))
    end

    function UI:Destroy() scope:Dispose() end

    return UI
end
