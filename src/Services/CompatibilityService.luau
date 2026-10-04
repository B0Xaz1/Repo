local CHECKS = table.freeze({
    { "Files", "Local profiles", "Save and restore profiles on this device.", "Use JSON import/export instead of local saves." },
    { "ListFiles", "Profile discovery", "List saved profiles in the picker.", "Saved profiles may not appear in the list." },
    { "DeleteFile", "Profile deletion", "Delete named profiles through Settings.", "Profile deletion is unavailable." },
    { "ClipboardRead", "Clipboard import", "Paste configuration data from the clipboard.", "Paste manually into the JSON editor." },
    { "ClipboardWrite", "Clipboard export", "Copy profiles and player names.", "Copy text manually from the JSON editor." },
    { "Drawing", "Drawing overlays", "Display drawing-based ESP and indicators.", "Drawing-based overlays may be unavailable; native visuals are separate." },
    { "MouseMove", "Mouse aim", "Move the mouse for mouse-based aim assistance.", "Use camera-based aim where supported." },
    { "NativeClick", "Native click input", "Provide native simulated clicks.", "A virtual-input fallback may work, but is not verified here." },
    { "VirtualInput", "Virtual input fallback", "A virtual-input service is present; permission to send input is not verified.", "Some input actions may be unavailable without native input support." },
    { "HttpRequest", "Extended HTTP requests", "An optional HTTP request API is present.", "Basic requests may use Roblox's HTTP fallback; network permissions are not verified." },
    { "FpsCap", "FPS limit control", "Apply a requested FPS cap.", "The suite cannot adjust the FPS cap in this environment." },
    { "QueueTeleport", "Reload after teleport", "Request a reload after switching servers.", "Run the loader manually after teleporting." },
})

return function(services: any): any
    local environment = services:Get("Environment")
    local CompatibilityService = {}
    function CompatibilityService:GetReport(): any
        local report = { Checks = {}, Detected = 0, Total = #CHECKS,
            Notice = "Session capability detection only: an available API can still be restricted at runtime. No network, file-write, clipboard-read, input, or teleport tests are performed." }
        local capabilities = environment.Capabilities or {}
        for _, entry in ipairs(CHECKS) do
            local present = capabilities[entry[1]] == true
            if present then report.Detected += 1 end
            table.insert(report.Checks, { Name = entry[2], Available = present, Detail = if present then entry[3] else entry[4] })
        end
        report.Game = "Universal controls; game-specific compatibility not checked."
        if services:Has("PluginManager") then
            local manager = services:Get("PluginManager")
            report.Game = if manager:IsGameSupported() then `Game controls: {manager:GetActivePluginName()}. Game updates may affect compatibility.`
                else "Universal Mode: no matching game plugin."
        end
        return report
    end
    return CompatibilityService
end
