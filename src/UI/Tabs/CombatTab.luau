--!nonstrict
return function(services: any, tab: any): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)
    local keybind = load("src/UI/Components/Keybind.luau", services)
    local aim = section:Create(tab.LeftCol, "Aim assist")
    toggle(aim, "Enable aimbot", "Aimbot.Enabled", nil)
    toggle(aim, "Camera correction", "Aimbot.UseCamera", nil)
    keybind(aim, "Activation key", "Aimbot.Keybind", nil)
    dropdown(aim, "Lock mode", "Aimbot.LockMode", { "Hold", "Toggle" }, nil)
    dropdown(aim, "Hit part", "Aimbot.Hitpart", { "Head", "Torso", "HumanoidRootPart", "UpperTorso", "LowerTorso" }, nil)
    slider(aim, "Smoothness", "Aimbot.Smoothness", 1, 50, 0.5, "", nil)
    dropdown(aim, "Movement mode", "Aimbot.MovementMode", { "Linear", "WindMouse" }, nil)
    slider(aim, "Wind strength", "Aimbot.WindStrength", 0, 30, 0.1, "", nil)
    slider(aim, "Wind damping", "Aimbot.WindDamping", 0, 0.99, 0.01, "", nil)
    section:Info(aim, if services:Get("Environment"):IsMobile() then "Touch: enabling aim assist engages it at the viewport centre. Camera correction is recommended."
        else "Hold or toggle the activation key. Linear disables wind. Missing relative mouse input falls back to camera correction.")
    local lock = section:Create(tab.LeftCol, "Prediction & lock safety")
    slider(lock, "Horizontal prediction", "Aimbot.Prediction.Horizontal", 0, 1, 0.01, " s", nil)
    slider(lock, "Vertical prediction", "Aimbot.Prediction.Vertical", 0, 1, 0.01, " s", nil)
    slider(lock, "Shake intensity", "Aimbot.ShakeIntensity", 0, 3, 0.05, "", nil)
    toggle(lock, "Unlock on death", "Aimbot.UnlockOnDeath", nil)
    toggle(lock, "Break on manual pull", "Aimbot.BreakOnPull", nil)
    slider(lock, "Maximum lock radius", "Aimbot.MaxLockRadius", 10, 1000, 5, " px", nil)
    local filters = section:Create(tab.RightCol, "Target filters")
    for _, entry in ipairs({ { "Team check", "TeamCheck" }, { "Friend check", "FriendCheck" }, { "Whitelist check", "WhitelistCheck" }, { "Force-field check", "ForceFieldCheck" }, { "Visibility check", "VisCheck" } }) do
        toggle(filters, entry[1], "Aimbot." .. entry[2], nil)
    end
    slider(filters, "Maximum aim distance", "Aimbot.MaxDistance", 50, 10000, 50, " studs", nil)
    local fov = section:Create(tab.RightCol, "FOV circle")
    toggle(fov, "Show FOV", "Aimbot.FOV.Show", nil)
    slider(fov, "FOV radius", "Aimbot.FOV.Size", 10, 700, 1, " px", nil)
    toggle(fov, "Filled circle", "Aimbot.FOV.Filled", nil)
    slider(fov, "Circle thickness", "Aimbot.FOV.Thickness", 1, 8, 1, " px", nil)
    slider(fov, "Circle sides", "Aimbot.FOV.Sides", 16, 128, 1, "", nil)
    toggle(fov, "Rainbow", "Aimbot.FOV.Rainbow", nil)
    toggle(fov, "Pulse", "Aimbot.FOV.Pulse", nil)
    local trigger = section:Create(tab.RightCol, "Triggerbot")
    toggle(trigger, "Enable triggerbot", "Aimbot.Triggerbot.Enabled", nil)
    slider(trigger, "Trigger delay", "Aimbot.Triggerbot.Delay", 0, 2, 0.01, " s", nil)
    slider(trigger, "Trigger distance", "Aimbot.Triggerbot.MaxDistance", 50, 10000, 50, " studs", nil)
    for _, entry in ipairs({ { "Trigger team check", "TeamCheck" }, { "Trigger friend check", "FriendCheck" }, { "Trigger whitelist check", "WhitelistCheck" }, { "Trigger force-field check", "ForceFieldCheck" }, { "Trigger visibility check", "VisCheck" } }) do
        toggle(trigger, entry[1], "Aimbot.Triggerbot." .. entry[2], nil)
    end
    return { Name = tab.Name }
end
