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

    -- Keep every player visual, including native chams, in one short node. The readout mirrors
    -- the classic full-box layout: name and range above, numeric health on the left, and tool below.
    local esp = section:Create(tab.LeftCol, "Player ESP")
    section:Info(esp, "A clean menu-accent readout: full box, name with range, numeric health, equipped tool, and optional native chams.")
    if not services:Get("DrawingPool").Available then
        section:Info(esp, "Drawing is unavailable. Boxes, names, tools, and health will not render; native chams can still work.")
    end
    toggle(esp, "Enable player ESP", "ESP.Enabled", nil)
    toggle(esp, "Boxes", "ESP.Box", nil)
    toggle(esp, "Names", "ESP.Name", nil)
    toggle(esp, "Tools", "ESP.Tool", nil)
    toggle(esp, "Health", "ESP.Health", nil)
    toggle(esp, "Chams", "Chams.Enabled", nil)
    color(esp, "ESP color", "ESP.Color", function() state:Set("ESP.ColorFollowsTheme", false) end)
    toggle(esp, "Follow menu accent", "ESP.ColorFollowsTheme", nil)
    toggle(esp, "Use team colors", "ESP.UseTeamColor", nil)
    dropdown(esp, "Occlusion behavior", "ESP.DepthMode", { "AlwaysOnTop", "Occluded" }, nil)

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
