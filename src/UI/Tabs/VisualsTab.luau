return function(services: any, tab: any): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)
    local color = load("src/UI/Components/ColorPicker.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)
    local lighting = services:Get("LightingService")
    local optimizer = services:Get("OptimizerService")

    -- Keep the entire player-visual stack in one collapsible node. The short in-node labels
    -- preserve scanability without forcing related ESP controls into separate panels.
    local esp = section:Create(tab.LeftCol, "Player ESP")
    section:Info(esp, "Build a clean player readout from frame, label, guide, palette, and native-highlight layers. Every layer is independently optional.")
    if not services:Get("DrawingPool").Available then
        section:Info(esp, "Drawing is unavailable. Player ESP and screen overlays will not render; native chams can still work.")
    end
    toggle(esp, "Enable player ESP", "ESP.Enabled", nil)
    toggle(esp, "Hide teammates", "ESP.TeamCheck", nil)
    slider(esp, "Render distance", "ESP.MaxDist", 50, 10000, 50, " studs", nil)
    dropdown(esp, "Occlusion behavior", "ESP.DepthMode", { "AlwaysOnTop", "Occluded" }, nil)

    section:Info(esp, "FRAME & HEALTH")
    toggle(esp, "Show player frame", "ESP.Box", nil)
    dropdown(esp, "Frame style", "ESP.BoxStyle", { "Corner", "Full" }, nil)
    slider(esp, "Frame thickness", "ESP.BoxThickness", 1, 4, 0.5, " px", nil)
    toggle(esp, "Tint frame interior", "ESP.BoxFill", nil)
    slider(esp, "Frame fill opacity", "ESP.BoxFillOpacity", 0, 0.85, 0.05, nil, nil)
    toggle(esp, "Health bar", "ESP.Health", nil)
    dropdown(esp, "Health bar position", "ESP.HealthStyle", { "Left", "Bottom" }, nil)
    toggle(esp, "Head marker", "ESP.HeadDot", nil)
    toggle(esp, "Skeleton", "ESP.Skeleton", nil)

    section:Info(esp, "LABELS & INVENTORY")
    toggle(esp, "Player name", "ESP.Name", nil)
    toggle(esp, "Distance label", "ESP.Distance", nil)
    toggle(esp, "Equipped item", "ESP.Tool", nil)
    toggle(esp, "Backpack contents", "ESP.Backpack", nil)
    dropdown(esp, "Overlay font", "ESP.Font", { "Plex", "UI", "System", "Monospace" }, nil)
    slider(esp, "Label size", "ESP.TextSize", 8, 24, 1, " px", nil)
    toggle(esp, "Text outlines", "ESP.Outline", nil)
    toggle(esp, "Distance auto-scaling", "ESP.AutoScaling", nil)

    section:Info(esp, "GUIDES & AWARENESS")
    toggle(esp, "Tracers", "ESP.Tracers", nil)
    dropdown(esp, "Tracer origin", "ESP.TracerOrigin", { "Bottom", "Center", "Top" }, nil)
    toggle(esp, "Off-screen pointers", "ESP.OffscreenArrows", nil)
    slider(esp, "Pointer radius", "ESP.ArrowRadius", 80, 600, 10, " px", nil)
    slider(esp, "Pointer size", "ESP.ArrowSize", 4, 28, 1, " px", nil)
    toggle(esp, "Look direction", "ESP.LookDir", nil)

    section:Info(esp, "PALETTE")
    color(esp, "Base color", "ESP.Color", nil)
    slider(esp, "Overlay opacity", "ESP.Opacity", 0.05, 1, 0.05, nil, nil)
    toggle(esp, "Use team color", "ESP.UseTeamColor", nil)
    toggle(esp, "Rainbow mode", "ESP.Rainbow", nil)

    section:Info(esp, "NATIVE CHAMS")
    section:Info(esp, "A separate native highlight layer for character silhouettes. It works even where executor Drawing support is unavailable.")
    toggle(esp, "Enable chams", "Chams.Enabled", nil)
    color(esp, "Fill color", "Chams.FillColor", nil)
    slider(esp, "Fill transparency", "Chams.FillTransparency", 0, 1, 0.05, nil, nil)
    color(esp, "Outline color", "Chams.OutlineColor", nil)
    slider(esp, "Outline transparency", "Chams.OutlineTransparency", 0, 1, 0.05, nil, nil)
    toggle(esp, "Chams team color", "Chams.UseTeamColor", nil)
    toggle(esp, "Chams rainbow mode", "Chams.Rainbow", nil)

    local performancePresets = section:Create(tab.RightCol, "Performance presets")
    section:Info(performancePresets, "Presets apply a coordinated set of reversible visual changes. You can still adjust every option below.")
    textbox:CreateButton(performancePresets, "Use balanced performance", function() return optimizer:ApplyPreset("Balanced") end)
    textbox:CreateButton(performancePresets, "Use maximum performance", function() return optimizer:ApplyPreset("Maximum") end)
    textbox:CreateButton(performancePresets, "Restore visual quality", function() return optimizer:RestoreVisualQuality() end)

    local performance = section:Create(tab.RightCol, "Rendering performance", "Performance")
    section:Info(performance, "Changes are streamed in one pass and restore only the category you turn off, avoiding repeated full-world resets.")
    for _, entry in ipairs({ { "Hide texture detail", "NoTextures" }, { "Simple materials", "LowMaterials" }, { "Disable world shadows", "NoShadows" },
        { "Disable particles", "NoParticles" }, { "Disable post-processing", "NoPostProcessing" }, { "Reduce terrain water", "OptimizeTerrain" },
        { "Disable dynamic lights", "NoLights" }, { "Disable highlights", "NoHighlights" } }) do
        toggle(performance, entry[1], `Performance.{entry[2]}`, nil)
    end

    local maintenance = section:Create(tab.RightCol, "Performance maintenance")
    textbox:CreateButton(maintenance, "Reapply current performance settings", function() return optimizer:Refresh() end)
    textbox:CreateButton(maintenance, "Request memory collection", function() return optimizer:FlushMemory() end)

    local light = section:Create(tab.RightCol, "Cinematic lighting", "Lighting")
    toggle(light, "Fullbright", "Visuals.Fullbright", nil)
    dropdown(light, "Lighting mode", "Lighting.Mode", { "Off", "Static Day", "Static Night", "Dynamic" }, function(value: string) lighting:SetMode(value) end)
    slider(light, "Time of day", "Lighting.TimeOfDay", 0, 24, 0.1, " h", function(value: number) lighting:SetTime(value) end)
    slider(light, "Day-cycle duration", "Lighting.CycleDuration", 30, 1800, 10, " s", nil)
    toggle(light, "Pause dynamic cycle", "Lighting.Paused", nil)
    slider(light, "Preset brightness", "Lighting.PresetBrightness", 0.25, 2, 0.05, "x", nil)
    toggle(light, "Soft vignette", "Lighting.Vignette", nil)
    toggle(light, "Remaster materials", "Lighting.RemasterMaterials", nil)

    local telemetry = section:Create(tab.RightCol, "Telemetry & motion", "Settings")
    toggle(telemetry, "Watermark", "Settings.Watermark", nil)
    toggle(telemetry, "FPS counter", "Settings.ShowFPS", nil)
    toggle(telemetry, "Ping monitor", "Settings.ShowPing", nil)
    return { Name = tab.Name }
end
