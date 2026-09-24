return function(services: any, tab: any): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)
    local hitbox = section:Create(tab.LeftCol, "Hitbox expansion", "Extras.Hitbox")
    toggle(hitbox, "Expand other root parts", "Extras.Hitbox.Enabled", nil)
    slider(hitbox, "Expanded root size", "Extras.Hitbox.Size", 2, 20, 0.5, " studs", nil)
    local spin = section:Create(tab.LeftCol, "Spin bot", "Extras.SpinBot")
    toggle(spin, "Enable spin", "Extras.SpinBot.Enabled", nil)
    slider(spin, "Spin rate", "Extras.SpinBot.Speed", -1440, 1440, 15, " deg/s", nil)
    local guard = section:Create(tab.RightCol, "Fling defense", "Extras.AntiFling")
    toggle(guard, "Enable anti-fling", "Extras.AntiFling.Enabled", nil)
    slider(guard, "Impossible-speed threshold", "Extras.AntiFling.Threshold", 350, 2500, 25, " studs/s", nil)
    toggle(guard, "Snap back after an impulse", "Extras.AntiFling.SnapBack", nil)
    local session = section:Create(tab.RightCol, "Session utilities", "Settings")
    toggle(session, "Prevent idle kick", "Settings.AntiAfk", nil)
    toggle(session, "Auto-rejoin on disconnect", "Settings.AutoRejoin", nil)
    textbox:CreateButton(session, "Rejoin this server", function() return services:Get("HotkeyService"):Rejoin() end)
    textbox:CreateButton(session, "Find another public server", function() return services:Get("HotkeyService"):ServerHop() end)
    if not services:Get("Environment").Capabilities.QueueTeleport then
        section:Info(session, "Teleport queue is unavailable. Re-run the loader after changing servers.")
    end
    return { Name = tab.Name }
end
