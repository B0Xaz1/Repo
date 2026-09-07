--!nonstrict
return function(services: any, tab: any): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)
    local color = load("src/UI/Components/ColorPicker.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)
    local environment, lighting = services:Get("Environment"), services:Get("LightingService")
    local esp = section:Create(tab.LeftCol, "ESP features")
    section:Info(esp, if services:Get("DrawingPool").Available then "Drawing available · pooled per-player overlays" else "Drawing is unavailable. ESP and telemetry overlays will not render; native chams can still work.")
    toggle(esp, "Enable ESP", "ESP.Enabled", nil, 2)
    for _, entry in ipairs({ { "Boxes", "Box" }, { "Names", "Name" }, { "Health bars", "Health" }, { "Distance", "Distance" }, { "Equipped tools", "Tool" },
        { "Backpack contents", "Backpack" }, { "Tracers", "Tracers" }, { "Skeleton", "Skeleton" }, { "Head dots", "HeadDot" }, { "Look direction", "LookDir" }, { "Hide teammates", "TeamCheck" } }) do
        toggle(esp, entry[1], "ESP." .. entry[2], nil, 2)
    end
    local espStyle = section:Create(tab.LeftCol, "ESP style")
    slider(espStyle, "ESP distance limit", "ESP.MaxDist", 50, 10000, 50, " studs", nil, 2)
    dropdown(espStyle, "Overlay font", "ESP.Font", { "Plex", "UI", "System", "Monospace" }, nil, 2)
    toggle(espStyle, "Text outlines", "ESP.Outline", nil, 2)
    toggle(espStyle, "Distance auto-scaling", "ESP.AutoScaling", nil, 2)
    color(espStyle, "ESP color", "ESP.Color", nil, 2)
    local chams = section:Create(tab.LeftCol, "Native chams")
    toggle(chams, "Enable chams", "Chams.Enabled", nil, 2)
    toggle(chams, "Use team color", "Chams.UseTeamColor", nil, 2)
    dropdown(chams, "Depth mode", "Chams.DepthMode", { "AlwaysOnTop", "Occluded" }, nil, 2)
    color(chams, "Fill color", "Chams.FillColor", nil, 2)
    color(chams, "Outline color", "Chams.OutlineColor", nil, 2)
    local performance = section:Create(tab.RightCol, "Performance")
    for _, entry in ipairs({ { "Remove textures", "NoTextures" }, { "Simple materials", "LowMaterials" }, { "Disable shadows", "NoShadows" },
        { "Disable particles", "NoParticles" }, { "Optimize terrain", "OptimizeTerrain" }, { "Disable post-processing", "NoPostProcessing" } }) do
        toggle(performance, entry[1], "Performance." .. entry[2], nil, 1)
    end
    slider(performance, "FPS cap · 0 uncaps", "Performance.FpsCap", 0, 360, 15, " FPS", nil, 1)
    section:Info(performance, if environment:HasFpsCap() then "FPS-cap wrapper available. Unload always requests an uncapped limit." else "FPS cap is unsupported by this executor. Other optimizations remain available.")
    textbox:CreateButton(performance, "Request memory collection", function() return services:Get("OptimizerService"):FlushMemory() end, 1)
    local light = section:Create(tab.RightCol, "Cinematic lighting")
    toggle(light, "Fullbright", "Visuals.Fullbright", nil, 1)
    dropdown(light, "Lighting mode", "Lighting.Mode", { "Off", "Static Day", "Static Night", "Dynamic" }, function(value: string) lighting:SetMode(value) end, 1)
    slider(light, "Time of day", "Lighting.TimeOfDay", 0, 24, 0.1, " h", function(value: number) lighting:SetTime(value) end, 1)
    slider(light, "Day-cycle duration", "Lighting.CycleDuration", 30, 1800, 10, " s", nil, 1)
    toggle(light, "Pause dynamic cycle", "Lighting.Paused", nil, 1)
    slider(light, "Preset brightness", "Lighting.PresetBrightness", 0.25, 2, 0.05, "×", nil, 1)
    toggle(light, "Soft vignette", "Lighting.Vignette", nil, 1)
    toggle(light, "Remaster materials", "Lighting.RemasterMaterials", nil, 1)
    section:Info(light, "Time and grade apply when a lighting mode is active. Fullbright takes precedence; the game's own effects are never borrowed.")
    local telemetry = section:Create(tab.RightCol, "Telemetry & motion")
    toggle(telemetry, "Watermark", "Settings.Watermark", nil, 0)
    toggle(telemetry, "FPS counter", "Settings.ShowFPS", nil, 0)
    toggle(telemetry, "Ping monitor", "Settings.ShowPing", nil, 0)
    toggle(telemetry, "Radial speed lines", "Extras.SpeedLines", nil, 1)
    return { Name = tab.Name }
end
