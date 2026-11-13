return function(services: any, tab: any): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)
    local color = load("src/UI/Components/ColorPicker.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)
    local state, lighting = services:Get("StateStore"), services:Get("LightingService")
    local optimizer = services:Get("OptimizerService")

    -- Player ESP is organized by the decisions players make most often. The common
    -- controls stay visible; only the uncommon effects live behind a disclosure.
    local esp = section:Create(tab.LeftCol, "Player ESP")
    section:Info(esp, "Frame-synchronous player overlay with boxes, readouts, optional health, visibility controls, and native chams.")
    if not services:Get("DrawingPool").Available then
        section:Info(esp, "Drawing is unavailable. Native full boxes and readouts remain available; Corner boxes are unavailable.")
    end
    toggle(esp, "Enable player ESP", "ESP.Enabled", nil)
    toggle(esp, "Show self ESP", "ESP.ShowSelf", nil)
    slider(esp, "Render distance", "ESP.MaxDistance", 50, 10000, 50, " studs", nil)

    local labels = section:Subsection(esp, "Box & labels", true)
    toggle(labels, "Boxes", "ESP.Box", nil)
    dropdown(labels, "Box style", "ESP.BoxStyle", { "Full", "Corner" }, nil)
    toggle(labels, "Names", "ESP.Name", nil)
    dropdown(labels, "Name style", "ESP.NameStyle", { "Username", "Display name" }, nil)
    toggle(labels, "Distance", "ESP.Distance", nil)
    toggle(labels, "Tools", "ESP.Tool", nil)
    toggle(labels, "Health readout", "ESP.Health", nil)

    local visibility = section:Subsection(esp, "Colors & visibility", true)
    color(visibility, "ESP color", "ESP.Color", function() state:Set("ESP.ColorFollowsTheme", false) end)
    toggle(visibility, "Follow menu accent", "ESP.ColorFollowsTheme", nil)
    toggle(visibility, "Use team colors", "ESP.UseTeamColor", nil)
    dropdown(visibility, "Occlusion behavior", "ESP.DepthMode", { "AlwaysOnTop", "Occluded" }, nil)

    local advanced = section:Subsection(esp, "Advanced effects", false)
    toggle(advanced, "Health bar", "ESP.HealthBar", nil)
    toggle(advanced, "Estimated AFK status (60s idle)", "ESP.ActivityStatus", nil)
    toggle(advanced, "Chams", "Chams.Enabled", nil)

    local telemetry = section:Subsection(esp, "Telemetry & motion", true)
    toggle(telemetry, "Watermark", "Settings.Watermark", nil)
    toggle(telemetry, "FPS counter", "Settings.ShowFPS", nil)
    toggle(telemetry, "Ping monitor", "Settings.ShowPing", nil)

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

    local light = section:Create(tab.RightCol, "Cinematic lighting", "Lighting")
    section:Info(light, "Choose a scene for a complete grade. Adjusting mode, time, brightness, or vignette returns to Custom without discarding your values.")
    toggle(light, "Fullbright", "Visuals.Fullbright", nil)
    dropdown(light, "Scene preset", "Lighting.ScenePreset", lighting:GetScenePresetNames(), function(value: string) lighting:ApplyScenePreset(value) end)
    dropdown(light, "Lighting mode", "Lighting.Mode", { "Off", "Static Day", "Static Night", "Dynamic" }, function(value: string) lighting:SetMode(value) end)
    slider(light, "Time of day", "Lighting.TimeOfDay", 0, 24, 0.1, " h", function(value: number) lighting:SetTime(value); lighting:UseCustomScene() end)
    slider(light, "Day-cycle duration", "Lighting.CycleDuration", 30, 1800, 10, " s", nil)
    toggle(light, "Pause dynamic cycle", "Lighting.Paused", nil)
    slider(light, "Preset brightness", "Lighting.PresetBrightness", 0.25, 2, 0.05, "x", function() lighting:UseCustomScene() end)
    toggle(light, "Soft vignette", "Lighting.Vignette", function() lighting:UseCustomScene() end)
    toggle(light, "Remaster materials", "Lighting.RemasterMaterials", nil)

    local telemetry = section:Subsection(esp, "Telemetry & motion", true)
    toggle(telemetry, "Watermark", "Settings.Watermark", nil)
    toggle(telemetry, "FPS counter", "Settings.ShowFPS", nil)
    toggle(telemetry, "Ping monitor", "Settings.ShowPing", nil)
    return { Name = tab.Name }
end
