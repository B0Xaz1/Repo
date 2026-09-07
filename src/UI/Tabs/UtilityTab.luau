--!nonstrict
return function(services: any, tab: any): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)
    local hitbox = section:Create(tab.LeftCol, "Hitbox expansion")
    toggle(hitbox, "Expand other root parts", "Extras.Hitbox.Enabled", nil)
    slider(hitbox, "Expanded root size", "Extras.Hitbox.Size", 2, 20, 0.5, " studs", nil)
    section:Info(hitbox, "Expanded roots are semi-transparent. Original size, transparency and collision are restored on disable, respawn, leave and unload.")
    local spin = section:Create(tab.LeftCol, "Spin bot")
    toggle(spin, "Enable spin", "Extras.SpinBot.Enabled", nil)
    slider(spin, "Spin rate", "Extras.SpinBot.Speed", -1440, 1440, 15, "°/s", nil)
    local guard = section:Create(tab.RightCol, "Fling defense")
    toggle(guard, "Enable anti-fling", "Extras.AntiFling.Enabled", nil)
    slider(guard, "Impossible-speed threshold", "Extras.AntiFling.Threshold", 350, 2500, 25, " studs/s", nil)
    toggle(guard, "Snap back after an impulse", "Extras.AntiFling.SnapBack", nil)
    section:Info(guard, "Runs before physics. Ordinary falling is never rejected based on downward speed alone; our teleports and flight establish a new baseline.")
    local session = section:Create(tab.RightCol, "Session utilities")
    toggle(session, "Prevent idle kick", "Settings.AntiAfk", nil)
    toggle(session, "Auto-rejoin on disconnect", "Settings.AutoRejoin", nil)
    textbox:CreateButton(session, "Rejoin this server", function() return services:Get("HotkeyService"):Rejoin() end)
    textbox:CreateButton(session, "Find another public server", function() return services:Get("HotkeyService"):ServerHop() end)
    section:Info(session, if services:Get("Environment").Capabilities.QueueTeleport then "Teleport queue detected. Rejoin and server-hop preserve this build's exact source ref."
        else "This executor cannot queue the loader through teleport. Server travel can still work, but you must paste the loader again afterward.")
    return { Name = tab.Name }
end
