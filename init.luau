--!strict
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local CONFIG = table.freeze({
    VERSION = "2.4.5",
    NOT_FOUND_BODY = "404" .. ": Not Found",
    DEFAULT_REF = "main",
    REPOSITORY = "https://raw.githubusercontent.com/B0Xaz1/Repo/",
    READINESS_TIMEOUT = 15,
    READINESS_POLL = 0.1,
    FETCH_ATTEMPTS = 3,
    FETCH_BACKOFF = 0.5,
    RELAUNCH_ATTEMPTS = 5,
    RELAUNCH_BACKOFF = 0.7,
    MIN_SOURCE_LENGTH = 10,
    LAUNCH_LOCK_WINDOW = 90,
    CONSOLE_CLEAR_NAMES = { "rconsoleclear", "consoleclear", "clearconsole", "clearoutput" },
    LAUNCH_GUARD_SUFFIXES = { "/init.luau", "/loader.luau", "/init.lua", "/loader.lua", "/B0XazUniversal", "/B0Xaz-Universal", "/Universal" },
    PATH_PREFIXES = { "B0XazUniversal/", "B0Xaz-Universal/", "Universal/" },
})

local runtime: any = getfenv(0)
local globals: any = _G
if type(runtime.getgenv) == "function" then
    local ok, value = pcall(runtime.getgenv)
    if ok and type(value) == "table" then globals = value end
end

local consoleFns = {}
for index, name in ipairs(CONFIG.CONSOLE_CLEAR_NAMES) do consoleFns[index] = runtime[name] end

function globals.B0XazUnload()
    local master, container = globals.B0XazMasterDisposer, globals.B0XazServiceContainer
    globals.B0XazRunning, globals.B0XazLaunching = false, nil
    globals.B0XazActiveToken, globals.B0XazLoaderBusy = nil, nil
    globals.B0XazMasterDisposer, globals.B0XazServiceContainer = nil, nil
    local environment = if container and container:Has("Environment") then container:Get("Environment") else nil
    if master then pcall(function() master:Dispose() end) end
    if environment then
        environment:ClearConsole()
    else
        for index = 1, #CONFIG.CONSOLE_CLEAR_NAMES do
            local fn = consoleFns[index]
            if type(fn) == "function" and pcall(fn) then break end
        end
    end
end

function globals.B0XazRelaunch()
    if globals.B0XazLoaderBusy then return end
    local url = globals.B0XazInitURL
    globals.B0XazUnload()
    local ticket = {}
    globals.B0XazLoaderBusy = ticket
    local relaunched, relaunchError = pcall(function()
        assert(type(url) == "string", "Missing normalized init URL")
        local source: string? = nil
        for attempt = 1, CONFIG.RELAUNCH_ATTEMPTS do
            if globals.B0XazLoaderBusy ~= ticket then return end
            local fetched, body = pcall(function() return game:HttpGet(`{url}?t={os.time()}_relaunch{attempt}`) end)
            if fetched and type(body) == "string" and #body >= CONFIG.MIN_SOURCE_LENGTH and not body:find(CONFIG.NOT_FOUND_BODY, 1, true) then source = body; break end
            if attempt < CONFIG.RELAUNCH_ATTEMPTS then task.wait(attempt * CONFIG.RELAUNCH_BACKOFF) end
        end
        assert(source, "Download failure during relaunch")
        if globals.B0XazLoaderBusy ~= ticket then return end
        local chunk, compileError = runtime.loadstring(source :: string, "@B0XazInit")
        assert(chunk, `Compile failure: {tostring(compileError)}`)
        local ran, runError = pcall(chunk)
        assert(ran, `Run failure: {tostring(runError)}`)
    end)
    if not relaunched then
        warn(`[B0Xaz] Relaunch failed: {tostring(relaunchError)}`)
    end
    if globals.B0XazLoaderBusy == ticket then globals.B0XazLoaderBusy = nil end
end

globals.B0XazRunning = globals.B0XazRunning == true
local base: string = if type(globals.B0XazBaseURL) == "string" then globals.B0XazBaseURL
    else CONFIG.REPOSITORY .. (if type(globals.B0XazRef) == "string" then globals.B0XazRef else CONFIG.DEFAULT_REF)
base = base:gsub("[?#].*$", ""):gsub("/+$", "")
local changed = true
while changed do
    changed = false
    for _, suffix in ipairs(CONFIG.LAUNCH_GUARD_SUFFIXES) do
        if base:sub(-#suffix) == suffix then base = base:sub(1, -#suffix - 1):gsub("/+$", ""); changed = true end
    end
end
base ..= "/"
globals.B0XazBaseURL, globals.B0XazInitURL = base, `{base}init.luau`

local now = os.time()
if type(globals.B0XazLaunching) == "number" and now - globals.B0XazLaunching < CONFIG.LAUNCH_LOCK_WINDOW then return end
globals.B0XazLaunching = now
globals.B0XazSessionId = (tonumber(globals.B0XazSessionId) or 0) + 1
local sessionId: number = globals.B0XazSessionId
local sessionToken: string = `{now}_{sessionId}`
local previous = globals.B0XazMasterDisposer
globals.B0XazRunning, globals.B0XazMasterDisposer, globals.B0XazServiceContainer = false, nil, nil
if previous then pcall(function() previous:Dispose() end) end
globals.B0XazActiveToken = sessionId

local function assertAlive()
    assert(globals.B0XazActiveToken == sessionId, "Session cancelled")
end

local sourceCache, compiledCache, initializedCache = {}, {}, {}
local loading, initializing, failed = {}, {}, {}

-- A module instance belongs to the service container that first loaded it.
-- Containers advertise a stable `ContainerId`; anything else falls back to its
-- identity, so a plugin's scoped container can never hand its own (short-lived)
-- instance of a shared module back to the rest of the suite.
local function scopeOf(container: any): string
    if type(container) == "table" then
        local id = rawget(container, "ContainerId")
        if type(id) == "string" and id ~= "" then return id end
        return `instance:{tostring(container)}`
    end
    return "bare"
end

local function normalize(path: string): string
    path = path:gsub("\\", "/"):gsub("[?#].*$", "")
    local before = ""
    while before ~= path do
        before = path
        path = path:gsub("^%./", ""):gsub("^/+", "")
        for _, prefix in ipairs(CONFIG.PATH_PREFIXES) do
            if path:sub(1, #prefix) == prefix then path = path:sub(#prefix + 1) end
        end
    end
    assert(path:match("%.luau$") and not path:find(":", 1, true), `Invalid module path '{path}'`)
    for segment in path:gmatch("[^/]+") do assert(segment ~= ".." and segment ~= ".", "Unsafe module path") end
    return path
end

local function fetch(path: string): string
    if sourceCache[path] then return sourceCache[path] end
    local lastError: any = "empty body"
    for attempt = 1, CONFIG.FETCH_ATTEMPTS do
        assertAlive()
        local ok, body = pcall(function() return game:HttpGet(`{base}{path}?t={sessionToken}_{attempt}`) end)
        assertAlive()
        if ok and type(body) == "string" and #body >= CONFIG.MIN_SOURCE_LENGTH and not body:find(CONFIG.NOT_FOUND_BODY, 1, true) then
            sourceCache[path] = body
            return body
        end
        lastError = body
        if attempt < CONFIG.FETCH_ATTEMPTS then task.wait(attempt * CONFIG.FETCH_BACKOFF) end
    end
    error(`Fetch failed for '{path}': {tostring(lastError)}`, 0)
end

local function requireModule(rawPath: string, ...: any): any
    local path, argumentCount = normalize(rawPath), select("#", ...)
    local key = if argumentCount > 0 then `{path}@{scopeOf((select(1, ...)))}` else path
    assertAlive()
    local currentThread = coroutine.running()
    while loading[path] do
        assert(loading[path] ~= currentThread, `Circular module dependency '{path}'`)
        task.wait(); assertAlive()
    end
    if failed[path] then error(failed[path], 0) end
    if not compiledCache[path] then
        loading[path] = currentThread
        local ok, result = pcall(function()
            local source = fetch(path)
            local chunk, compileError = runtime.loadstring(source, `@{path}`)
            if not chunk then error(`Syntax Error in '{path}': {tostring(compileError)}`, 0) end
            local ran, factory = pcall(chunk)
            if not ran or type(factory) ~= "function" then error(`Runtime Error in '{path}': {tostring(factory)}`, 0) end
            assertAlive()
            return factory
        end)
        loading[path] = nil
        if not ok then failed[path] = tostring(result); error(result, 0) end
        compiledCache[path] = result
    end
    if argumentCount == 0 then return compiledCache[path] end
    while initializing[key] do
        assert(initializing[key] ~= currentThread, `Circular factory dependency '{path}'`)
        task.wait(); assertAlive()
    end
    if initializedCache[key] then return initializedCache[key].Value end
    initializing[key] = currentThread
    local ok, value = pcall(compiledCache[path], ...)
    initializing[key] = nil
    assertAlive()
    if not ok then error(`Init Error in '{path}': {tostring(value)}`, 0) end
    initializedCache[key] = { Value = value }
    return value
end

local function step(callback: () -> any): any
    assertAlive()
    local value = callback()
    assertAlive()
    return value
end

local function failBoot()
    if globals.B0XazActiveToken ~= sessionId then return end
    local master = globals.B0XazMasterDisposer
    globals.B0XazRunning, globals.B0XazLaunching, globals.B0XazActiveToken = false, nil, nil
    globals.B0XazMasterDisposer, globals.B0XazServiceContainer = nil, nil
    if master then master:Dispose() end
end

local booted, bootError = pcall(function()
    step(function()
        local deadline = os.clock() + CONFIG.READINESS_TIMEOUT
        while not game:IsLoaded() or not Players.LocalPlayer do
            assertAlive(); assert(os.clock() < deadline, "Game readiness timed out")
            task.wait(CONFIG.READINESS_POLL)
        end
    end)
    local Disposer = step(function() return requireModule("src/Core/Disposer.luau")() end)
    local master = Disposer.new(`Master {sessionId}`)
    globals.B0XazMasterDisposer = master
    local environment = step(function() return requireModule("src/Core/Environment.luau", master) end)
    local bus = step(function() return requireModule("src/Core/EventBus.luau", master) end)
    local state = step(function() return requireModule("src/Core/StateStore.luau", bus, master) end)
    local scheduler = step(function() return requireModule("src/Core/TaskScheduler.luau", master) end)
    local services = step(function() return requireModule("src/Core/ServiceContainer.luau", master) end)
    services.Version = CONFIG.VERSION
    services.ContainerId = "root"
    services:Register("Disposer", master)
    services:Register("Environment", environment)
    services:Register("EventBus", bus)
    services:Register("StateStore", state)
    services:Register("TaskScheduler", scheduler)
    services:Register("Require", requireModule)
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
        { "ExtrasService", "src/Services/ExtrasService.luau" }, { "AimbotService", "src/Combat/AimbotService.luau" },
        { "TriggerbotService", "src/Combat/TriggerbotService.luau" }, { "PluginManager", "src/Plugins/PluginManager.luau" },
        { "ThemeEngine", "src/UI/ThemeEngine.luau" }, { "UIEngine", "src/UI/UIEngine.luau" },
    }
    for _, entry in ipairs(registration) do
        step(function() services:Register(entry[1], requireModule(entry[2], services)) end)
    end
    local launched = false
    local function launch()
        if globals.B0XazActiveToken ~= sessionId or launched then return end
        launched = true
        local ran, launchError = pcall(function()
            step(function() services:InitializeAll() end)
            step(function() services:Get("UIEngine"):ConstructInterface() end)
            step(function() return services:Get("ConfigService"):ApplyLaunchState() end)
            globals.B0XazLaunching, globals.B0XazRunning = nil, true
        end)
        if not ran then
            warn(`[B0Xaz] Launch failed: {tostring(launchError)}`)
            failBoot()
        end
    end
    launch()
end)
if not booted then
    warn(`[B0Xaz] Boot failed: {tostring(bootError)}`)
    failBoot()
end
