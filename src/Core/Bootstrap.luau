return function(context: any)
    local globals, requireModule, step = context.Globals, context.Require, context.Step
    local UIS = game:GetService("UserInputService")

    local Disposer = step(function() return requireModule("src/Core/Disposer.luau")() end)
    local master = Disposer.new(`Master {context.SessionId}`)
    globals.B0XazMasterDisposer = master
    local environment = step(function() return requireModule("src/Core/Environment.luau", master) end)
    local bus = step(function() return requireModule("src/Core/EventBus.luau", master) end)
    local state = step(function() return requireModule("src/Core/StateStore.luau", bus, master) end)
    local scheduler = step(function() return requireModule("src/Core/TaskScheduler.luau", master) end)
    local services = step(function() return requireModule("src/Core/ServiceContainer.luau", master) end)
    services.Version = context.Version
    services.ContainerId = "root"
    services:Register("Disposer", master)
    services:Register("Environment", environment)
    services:Register("EventBus", bus)
    services:Register("StateStore", state)
    services:Register("TaskScheduler", scheduler)
    services:Register("Require", requireModule)
    services:Register("Motion", step(function() return requireModule("src/UI/Motion.luau", services) end))
    services:Register("DOM", step(function() return requireModule("src/UI/DOM.luau", services) end))
    globals.B0XazServiceContainer = services

    local lastInputCheck = 0
    local inputCheckInterval = 0.05
    master:Connect(UIS.InputBegan, function(input: InputObject, _processed: boolean)
        local now = os.clock()
        if now - lastInputCheck < inputCheckInterval then return end
        lastInputCheck = now
        if state:GetTransient("IsBindingKey") or UIS:GetFocusedTextBox() then return end
        if environment:MatchesInput(input, state:Get("Settings.UnloadKeybind")) then globals.B0XazUnload() end
    end)

    local registration = {
        { "ConfigService", "src/Services/ConfigService.luau" }, { "PlayerTracker", "src/Services/PlayerTracker.luau" },
        { "OptimizerService", "src/Services/OptimizerService.luau" },
        { "LightingService", "src/Services/LightingService.luau" }, { "HotkeyService", "src/Services/HotkeyService.luau" },
        { "CommandService", "src/Services/CommandService.luau" },
        { "DrawingPool", "src/Visuals/DrawingPool.luau" }, { "TargetFilter", "src/Combat/TargetFilter.luau" },
        { "ESPController", "src/Visuals/ESPController.luau" }, { "OverlayController", "src/Visuals/OverlayController.luau" },
        { "LocomotionService", "src/Locomotion/LocomotionService.luau" }, { "FlightService", "src/Locomotion/FlightService.luau" },
        { "FreecamService", "src/Locomotion/FreecamService.luau" }, { "WallWalkService", "src/Locomotion/WallWalkService.luau" },
        { "ExtrasService", "src/Services/ExtrasService.luau" }, { "AimbotService", "src/Combat/AimbotService.luau" },
        { "TriggerbotService", "src/Combat/TriggerbotService.luau" }, { "PluginManager", "src/Plugins/PluginManager.luau" },
        { "ThemeEngine", "src/UI/ThemeEngine.luau" },
        { "UIEngine", "src/UI/UIEngine.luau" },
    }
    for _, entry in ipairs(registration) do
        step(function() services:Register(entry[1], requireModule(entry[2], services)) end)
    end

    step(function()
        services:InitializeAll()
        services:Get("UIEngine"):ConstructInterface()
        services:Get("ConfigService"):ApplyLaunchState()
        globals.B0XazLaunching, globals.B0XazRunning = nil, true
    end)
end
