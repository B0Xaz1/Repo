return function(services: any, tab: any): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)
    local color = load("src/UI/Components/ColorPicker.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)
    local environment, lighting = services:Get("Environment"), services:Get("LightingService")
    local optimizer = services:Get("OptimizerService")
    local esp = section:Create(tab.LeftCol, "ESP features", "ESP")
    if not services:Get("DrawingPool").Available then
        section:Info(esp, "Drawing is unavailable. ESP and telemetry overlays will not render; native chams can still work.")
    end
    toggle(esp, "Enable ESP", "ESP.Enabled", nil)
    for _, entry in ipairs({ { "Boxes", "Box" }, { "Names", "Name" }, { "Health bars", "Health" }, { "Distance", "Distance" }, { "Equipped tools", "Tool" },
        { "Backpack contents", "Backpack" }, { "Tracers", "Tracers" }, { "Skeleton", "Skeleton" }, { "Head dots", "HeadDot" }, { "Look direction", "LookDir" }, { "Hide teammates", "TeamCheck" } }) do
        toggle(esp, entry[1], `ESP.{entry[2]}`, nil)
    end
    local espStyle = section:Create(tab.LeftCol, "ESP style", "ESP")
    slider(espStyle, "ESP distance limit", "ESP.MaxDist", 50, 10000, 50, " studs", nil)
    dropdown(espStyle, "Overlay font", "ESP.Font", { "Plex", "UI", "System", "Monospace" }, nil)
    dropdown(espStyle, "Depth mode", "ESP.DepthMode", { "AlwaysOnTop", "Occluded" }, nil)
    toggle(espStyle, "Text outlines", "ESP.Outline", nil)
    toggle(espStyle, "Distance auto-scaling", "ESP.AutoScaling", nil)
    toggle(espStyle, "Rainbow mode", "ESP.Rainbow", nil)
    toggle(espStyle, "Use team color", "ESP.UseTeamColor", nil)
    color(espStyle, "ESP color", "ESP.Color", nil)
    local chams = section:Create(tab.LeftCol, "Native chams", "Chams")
    toggle(chams, "Enable chams", "Chams.Enabled", nil)
    toggle(chams, "Rainbow mode", "Chams.Rainbow", nil)
    toggle(chams, "Use team color", "Chams.UseTeamColor", nil)
    color(chams, "Fill color", "Chams.FillColor", nil)
    color(chams, "Outline color", "Chams.OutlineColor", nil)
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

    local frameRate = section:Create(tab.RightCol, "Frame rate")
    section:Info(frameRate, "Remove the executor frame cap. The suite requests a high ceiling rather than the executor's 60-FPS fallback.")
    textbox:CreateButton(frameRate, "Uncap FPS", function() return optimizer:UncapFps(true) end)
    if not environment:HasFpsCap() then
        section:Info(frameRate, "This executor does not expose a frame-cap API. Rendering options still work.")
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
