--!nonstrict
-- Prison Life diagnostics: one place that can answer "what did the plugin touch, and can it
-- all be put back?" plus the last plugin error captured by the PluginManager.
return function(services: any, Prison: any?): any
    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local Disposer = services:Get("Disposer")
    local Environment = services:Get("Environment")
    local PlayerTracker = services:Get("PlayerTracker")

    local Prison = Prison or {}
    local manifest = Prison.Manifest
    local scope = Disposer:CreateChild("PrisonLife.Diagnostics")

    local DiagnosticsService = { _lastError = nil :: string? }

    function DiagnosticsService:SetLastError(message: string?)
        self._lastError = message and tostring(message) or nil
    end

    function DiagnosticsService:GetLastError(): string?
        if self._lastError then return self._lastError end
        if services:Has("PluginManager") then
            local managerError = services:Get("PluginManager"):GetLastError()
            if managerError then return managerError end
        end
        return nil
    end

    function DiagnosticsService:Collect(): any
        local doorCounts = Prison.WorldPhase and Prison.WorldPhase:GetCounts() or {}
        local weaponStats = Prison.WeaponMods and Prison.WeaponMods:GetStats() or {}
        local macro = Prison.Macro and Prison.Macro:GetStatus() or {}
        local route = Prison.Locations and Prison.Locations:GetRouteStatus() or {}
        local context = Prison.Context and Prison.Context:GetSnapshot() or {}
        local capabilities = Environment.Capabilities
        local capabilityNames = {}
        for name, supported in pairs(capabilities) do
            if supported then table.insert(capabilityNames, name) end
        end
        table.sort(capabilityNames)
        return {
            Plugin = "Ready",
            PlaceId = game.PlaceId,
            UniverseId = game.GameId,
            Role = context.Role or "Unknown",
            Tier = StateStore:GetTier(),
            MapObjects = Prison.Locations and #(Prison.Locations:GetLocations()) or 0,
            DoorFolders = doorCounts.Folders or {},
            DoorParts = doorCounts.Parts or 0,
            DoorModels = doorCounts.Models or 0,
            PhasedParts = doorCounts.Phased or 0,
            WeaponsScanned = weaponStats.Scanned or 0,
            WeaponBackups = weaponStats.Backups or 0,
            MacroState = macro.State or "Idle",
            RouteState = route.State or "Idle",
            Capabilities = capabilityNames,
            LastError = self:GetLastError(),
            SessionDuration = Prison.Context and Prison.Context:FormatDuration() or "0:00",
            SessionOnly = {
                "Waypoints", "Loadouts", "Custom route", "Player watch selection",
            },
        }
    end

    function DiagnosticsService:Format(report: any): string
        local lines = {
            "Plugin: " .. tostring(report.Plugin),
            "Place: " .. tostring(report.PlaceId) .. "  /  Universe: " .. tostring(report.UniverseId),
            "Role: " .. tostring(report.Role) .. "   Tier: " .. tostring(report.Tier),
            "Map locations: " .. tostring(report.MapObjects),
            "Door models: " .. tostring(report.DoorModels) .. "   Parts: " .. tostring(report.DoorParts) .. "   Phased: " .. tostring(report.PhasedParts),
            "Weapons scanned: " .. tostring(report.WeaponsScanned) .. "   Backups: " .. tostring(report.WeaponBackups),
            "Macro: " .. tostring(report.MacroState) .. "   Route: " .. tostring(report.RouteState),
            "Session: " .. tostring(report.SessionDuration),
            "Capabilities: " .. (#report.Capabilities > 0 and table.concat(report.Capabilities, ", ") or "none"),
            "Last error: " .. tostring(report.LastError or "-"),
            "Session-only: " .. table.concat(report.SessionOnly, ", "),
        }
        return table.concat(lines, "\n")
    end

    -- Everything the plugin changed gets reversed: world visuals/collision, weapon modules,
    -- and every running automation. Feature switches flip off so nothing re-applies itself.
    function DiagnosticsService:RestoreAll(): (boolean, string)
        local flags = {
            "Game.NoSpread", "Game.FastFire", "Game.ForceAuto", "Game.ForceRange",
            "Game.DoorPhase", "Game.DoorGlow", "Game.FakeMacro", "Game.PunchAura", "Game.SuperPunch",
        }
        for _, path in ipairs(flags) do
            if StateStore:Peek(path) == true then StateStore:Set(path, false) end
        end
        if Prison.Macro then Prison.Macro:Stop("restore all") end
        if Prison.Locations then Prison.Locations:StopRoute("restore all") end
        if Prison.Melee then Prison.Melee:StopLoop() end
        if Prison.WorldPhase then Prison.WorldPhase:RestoreAll() end
        if Prison.WeaponMods then Prison.WeaponMods:RestoreAll() end
        EventBus:Publish("Notify", "Prison Life", "Restored weapon, door, and automation changes")
        return true, "All temporary changes restored"
    end

    function DiagnosticsService:RescanAll(): (boolean, string)
        local mapObjects = 0
        if Prison.Locations then mapObjects = Prison.Locations:ScanMapObjects() end
        if Prison.WorldPhase then Prison.WorldPhase:ScanDoors(); Prison.WorldPhase:ApplyAll() end
        if Prison.WeaponMods then Prison.WeaponMods:Reapply() end
        if Prison.Armory then Prison.Armory:Scan() end
        return true, "Re-scanned map (" .. tostring(mapObjects) .. " matches), doors, weapons, and tools"
    end

    function DiagnosticsService:Initialize()
        scope:Add(EventBus:Subscribe("PluginError", function(_name: string, message: string)
            DiagnosticsService:SetLastError(message)
        end))
    end

    function DiagnosticsService:Destroy() scope:Dispose() end

    return DiagnosticsService
end
