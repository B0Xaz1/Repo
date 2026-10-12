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

    local overview = section:Create(tab.LeftCol, "ESP workspace", "ESP")
    section:Info(overview, "Build a clean player readout from frame, label, guide, and palette layers. Every layer is independently optional.")
    if not services:Get("DrawingPool").Available then
        section:Info(overview, "Drawing is unavailable. Player ESP and screen overlays will not render; native chams can still work.")
    end
    toggle(overview, "Enable player ESP", "ESP.Enabled", nil)
    toggle(overview, "Hide teammates", "ESP.TeamCheck", nil)
    slider(overview, "Render distance", "ESP.MaxDist", 50, 10000, 50, " studs", nil)
    dropdown(overview, "Occlusion behavior", "ESP.DepthMode", { "AlwaysOnTop", "Occluded" }, nil)

    local frame = section:Create(tab.LeftCol, "Frame & health", "ESP")
    toggle(frame, "Show player frame", "ESP.Box", nil)
    dropdown(frame, "Frame style", "ESP.BoxStyle", { "Corner", "Full" }, nil)
    slider(frame, "Frame thickness", "ESP.BoxThickness", 1, 4, 0.5, " px", nil)
    toggle(frame, "Tint frame interior", "ESP.BoxFill", nil)
    slider(frame, "Frame fill opacity", "ESP.BoxFillOpacity", 0, 0.85, 0.05, nil, nil)
    toggle(frame, "Health bar", "ESP.Health", nil)
    dropdown(frame, "Health bar position", "ESP.HealthStyle", { "Left", "Bottom" }, nil)
    toggle(frame, "Head marker", "ESP.HeadDot", nil)
    toggle(frame, "Skeleton", "ESP.Skeleton", nil)

    local labels = section:Create(tab.LeftCol, "Labels & inventory", "ESP")
    toggle(labels, "Player name", "ESP.Name", nil)
    toggle(labels, "Distance label", "ESP.Distance", nil)
    toggle(labels, "Equipped item", "ESP.Tool", nil)
    toggle(labels, "Backpack contents", "ESP.Backpack", nil)
    dropdown(labels, "Overlay font", "ESP.Font", { "Plex", "UI", "System", "Monospace" }, nil)
    slider(labels, "Label size", "ESP.TextSize", 8, 24, 1, " px", nil)
    toggle(labels, "Text outlines", "ESP.Outline", nil)
    toggle(labels, "Distance auto-scaling", "ESP.AutoScaling", nil)

    local guides = section:Create(tab.LeftCol, "Guides & awareness", "ESP")
    toggle(guides, "Tracers", "ESP.Tracers", nil)
    dropdown(guides, "Tracer origin", "ESP.TracerOrigin", { "Bottom", "Center", "Top" }, nil)
    toggle(guides, "Off-screen pointers", "ESP.OffscreenArrows", nil)
    slider(guides, "Pointer radius", "ESP.ArrowRadius", 80, 600, 10, " px", nil)
    slider(guides, "Pointer size", "ESP.ArrowSize", 4, 28, 1, " px", nil)
    toggle(guides, "Look direction", "ESP.LookDir", nil)

    local palette = section:Create(tab.LeftCol, "Palette", "ESP")
    color(palette, "Base color", "ESP.Color", nil)
    slider(palette, "Overlay opacity", "ESP.Opacity", 0.05, 1, 0.05, nil, nil)
    toggle(palette, "Use team color", "ESP.UseTeamColor", nil)
    toggle(palette, "Rainbow mode", "ESP.Rainbow", nil)

    local chams = section:Create(tab.RightCol, "Native chams", "Chams")
    section:Info(chams, "A separate native highlight layer for character silhouettes. It works even where executor Drawing support is unavailable.")
    toggle(chams, "Enable chams", "Chams.Enabled", nil)
    color(chams, "Fill color", "Chams.FillColor", nil)
    slider(chams, "Fill transparency", "Chams.FillTransparency", 0, 1, 0.05, nil, nil)
    color(chams, "Outline color", "Chams.OutlineColor", nil)
    slider(chams, "Outline transparency", "Chams.OutlineTransparency", 0, 1, 0.05, nil, nil)
    toggle(chams, "Use team color", "Chams.UseTeamColor", nil)
    toggle(chams, "Rainbow mode", "Chams.Rainbow", nil)

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
