--!nonstrict
return function(services: any, tab: any): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)
    local keybind = load("src/UI/Components/Keybind.luau", services)
    local aim = section:Create(tab.LeftCol, "Aim assist")
    toggle(aim, "Enable aimbot", "Aimbot.Enabled", nil, 3)
    toggle(aim, "Camera correction", "Aimbot.UseCamera", nil, 3)
    keybind(aim, "Activation key", "Aimbot.Keybind", nil, 3)
    dropdown(aim, "Lock mode", "Aimbot.LockMode", { "Hold", "Toggle" }, nil, 3)
    dropdown(aim, "Hit part", "Aimbot.Hitpart", { "Head", "Torso", "HumanoidRootPart", "UpperTorso", "LowerTorso" }, nil, 3)
    slider(aim, "Smoothness", "Aimbot.Smoothness", 1, 50, 0.5, "", nil, 3)
    dropdown(aim, "Movement mode", "Aimbot.MovementMode", { "Linear", "WindMouse" }, nil, 3)
    slider(aim, "Wind strength", "Aimbot.WindStrength", 0, 30, 0.1, "", nil, 3)
    slider(aim, "Wind damping", "Aimbot.WindDamping", 0, 0.99, 0.01, "", nil, 3)
    section:Info(aim, if services:Get("Environment"):IsMobile() then "Touch: enabling aim assist engages it at the viewport centre. Camera correction is recommended."
        else "Hold or toggle the activation key. Linear disables wind. Missing relative mouse input falls back to camera correction.")
    local lock = section:Create(tab.LeftCol, "Prediction & lock safety")
    slider(lock, "Horizontal prediction", "Aimbot.Prediction.Horizontal", 0, 1, 0.01, " s", nil, 3)
    slider(lock, "Vertical prediction", "Aimbot.Prediction.Vertical", 0, 1, 0.01, " s", nil, 3)
    slider(lock, "Shake intensity", "Aimbot.ShakeIntensity", 0, 3, 0.05, "", nil, 3)
    toggle(lock, "Unlock on death", "Aimbot.UnlockOnDeath", nil, 3)
    toggle(lock, "Break on manual pull", "Aimbot.BreakOnPull", nil, 3)
    slider(lock, "Maximum lock radius", "Aimbot.MaxLockRadius", 10, 1000, 5, " px", nil, 3)
    local filters = section:Create(tab.RightCol, "Target filters")
    for _, entry in ipairs({ { "Team check", "TeamCheck" }, { "Friend check", "FriendCheck" }, { "Whitelist check", "WhitelistCheck" }, { "Force-field check", "ForceFieldCheck" }, { "Visibility check", "VisCheck" } }) do
        toggle(filters, entry[1], "Aimbot." .. entry[2], nil, 3)
    end
    slider(filters, "Maximum aim distance", "Aimbot.MaxDistance", 50, 10000, 50, " studs", nil, 3)
    local fov = section:Create(tab.RightCol, "FOV circle")
    toggle(fov, "Show FOV", "Aimbot.FOV.Show", nil, 3)
    slider(fov, "FOV radius", "Aimbot.FOV.Size", 10, 700, 1, " px", nil, 3)
    toggle(fov, "Filled circle", "Aimbot.FOV.Filled", nil, 3)
    slider(fov, "Circle thickness", "Aimbot.FOV.Thickness", 1, 8, 1, " px", nil, 3)
    slider(fov, "Circle sides", "Aimbot.FOV.Sides", 16, 128, 1, "", nil, 3)
    toggle(fov, "Rainbow", "Aimbot.FOV.Rainbow", nil, 3)
    toggle(fov, "Pulse", "Aimbot.FOV.Pulse", nil, 3)
    local trigger = section:Create(tab.RightCol, "Triggerbot")
    toggle(trigger, "Enable triggerbot", "Aimbot.Triggerbot.Enabled", nil, 3)
    slider(trigger, "Trigger delay", "Aimbot.Triggerbot.Delay", 0, 2, 0.01, " s", nil, 3)
    slider(trigger, "Trigger distance", "Aimbot.Triggerbot.MaxDistance", 50, 10000, 50, " studs", nil, 3)
    for _, entry in ipairs({ { "Trigger team check", "TeamCheck" }, { "Trigger friend check", "FriendCheck" }, { "Trigger whitelist check", "WhitelistCheck" }, { "Trigger force-field check", "ForceFieldCheck" }, { "Trigger visibility check", "VisCheck" } }) do
        toggle(trigger, entry[1], "Aimbot.Triggerbot." .. entry[2], nil, 3)
    end
    return { Name = tab.Name }
end
