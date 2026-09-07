--!nonstrict
local VERSION: string = "2.1.10"
-- Split the CDN error sentinel so this entry point cannot reject its own source during relaunch.
local NOT_FOUND_BODY: string = "404" .. ": Not Found"
local DEFAULT_REF: string = "main"
local REPOSITORY: string = "https://raw.githubusercontent.com/B0Xaz1/Repo/"
local globals: any = _G
if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok and type(value) == "table" then globals = value end
end
local runtime = getfenv(0)
local consoleNames = { "rconsoleclear", "consoleclear", "clearconsole", "clearoutput" }
local consoleFns = {}
for index, name in ipairs(consoleNames) do consoleFns[index] = runtime[name] end

-- Public cleanup is deliberately independent of a particular closure's master; it remains valid during a reload.
function globals.B0XazUnload()
    local master, container = globals.B0XazMasterDisposer, globals.B0XazServiceContainer
    globals.B0XazRunning, globals.B0XazLaunching = false, nil
    globals.B0XazActiveToken, globals.B0XazLoaderBusy = nil, nil
    globals.B0XazMasterDisposer, globals.B0XazServiceContainer = nil, nil
    local environment = if container and container:Has("Environment") then container:Get("Environment") else nil
    if master then
        local ok, err = pcall(function() master:Dispose() end)
        if not ok then warn("[B0Xaz][Unload] " .. tostring(err)) end
    end
    if environment then environment:ClearConsole() else
        for index = 1, #consoleNames do
            local fn = consoleFns[index]
            if type(fn) == "function" and pcall(fn) then break end
        end
    end
end

function globals.B0XazRelaunch()
    if globals.B0XazLoaderBusy then warn("[B0Xaz][Relaunch] A loader is already in flight"); return end
    local url = globals.B0XazInitURL
    globals.B0XazUnload()
    local ticket = {}
    globals.B0XazLoaderBusy = ticket
    local ok, err = pcall(function()
        assert(type(url) == "string", "Missing normalized init URL")
        local source: string? = nil
        for attempt = 1, 5 do
            if globals.B0XazLoaderBusy ~= ticket then return end
            local fetched, body = pcall(function() return game:HttpGet(url .. "?t=" .. os.time() .. "_relaunch" .. attempt) end)
            if fetched and type(body) == "string" and #body >= 10 and not body:find(NOT_FOUND_BODY, 1, true) then source = body; break end
            if attempt < 5 then task.wait(attempt * 0.7) end
        end
        assert(source, "Download failure during relaunch")
        if globals.B0XazLoaderBusy ~= ticket then return end
        local chunk, compileError = loadstring(source :: string, "@B0XazInit")
        assert(chunk, "Compile failure: " .. tostring(compileError))
        local ran, runError = pcall(chunk)
        assert(ran, "Run failure: " .. tostring(runError))
    end)
    if globals.B0XazLoaderBusy == ticket then globals.B0XazLoaderBusy = nil end
    if not ok then warn("[B0Xaz][Relaunch] " .. tostring(err)) end
end

globals.B0XazRunning = globals.B0XazRunning == true
local base: string = if type(globals.B0XazBaseURL) == "string" then globals.B0XazBaseURL
    else REPOSITORY .. (if type(globals.B0XazRef) == "string" then globals.B0XazRef else DEFAULT_REF)
base = base:gsub("[?#].*$", ""):gsub("/+$", "")
-- Older loaders published a file URL or a suite-folder URL; never strip arbitrary branch segments (refs may contain '/').
local changed = true
while changed do
    changed = false
    for _, suffix in ipairs({ "/init.luau", "/loader.luau", "/init.lua", "/loader.lua", "/B0XazUniversal", "/B0Xaz-Universal", "/Universal" }) do
        if base:sub(-#suffix) == suffix then base = base:sub(1, -#suffix - 1):gsub("/+$", ""); changed = true end
    end
end
base ..= "/"
globals.B0XazBaseURL, globals.B0XazInitURL = base, base .. "init.luau"

local now = os.time()
if type(globals.B0XazLaunching) == "number" and now - globals.B0XazLaunching < 90 then
    warn("[B0Xaz][Init] Refused duplicate launch in progress")
    return
end
globals.B0XazLaunching = now
globals.B0XazSessionId = (tonumber(globals.B0XazSessionId) or 0) + 1
local sessionId: number = globals.B0XazSessionId
local sessionToken: string = tostring(now) .. "_" .. sessionId
local previous = globals.B0XazMasterDisposer
globals.B0XazRunning, globals.B0XazMasterDisposer, globals.B0XazServiceContainer = false, nil, nil
if previous then
    local ok, err = pcall(function() previous:Dispose() end)
    if not ok then warn("[B0Xaz][Previous session cleanup] " .. tostring(err)) end
end
globals.B0XazActiveToken = sessionId

local function trace(message: string) print("[B0Xaz][Trace] " .. message) end
local function assertAlive()
    assert(globals.B0XazActiveToken == sessionId, "Session cancelled")
end
local sourceCache, compiledCache, initializedCache = {}, {}, {}
local loading, initializing, failed = {}, {}, {}
local function normalize(path: string): string
    path = path:gsub("\\", "/"):gsub("[?#].*$", "")
    local before = ""
    while before ~= path do
        before = path
        path = path:gsub("^%./", ""):gsub("^/+", "")
        for _, prefix in ipairs({ "B0XazUniversal/", "B0Xaz-Universal/", "Universal/" }) do
            if path:sub(1, #prefix) == prefix then path = path:sub(#prefix + 1) end
        end
    end
    assert(path:match("%.luau$") and not path:find(":", 1, true), "Invalid module path '" .. path .. "'")
    for segment in path:gmatch("[^/]+") do assert(segment ~= ".." and segment ~= ".", "Unsafe module path") end
    return path
end
local function fetch(path: string): string
    if sourceCache[path] then trace("source cache hit " .. path); return sourceCache[path] end
    local lastError: any = "empty body"
    for attempt = 1, 3 do
        assertAlive()
        trace("fetch attempt " .. attempt .. " " .. path)
        local ok, body = pcall(function() return game:HttpGet(base .. path .. "?t=" .. sessionToken .. "_" .. attempt) end)
        assertAlive()
        if ok and type(body) == "string" and #body >= 10 and not body:find(NOT_FOUND_BODY, 1, true) then
            sourceCache[path] = body
            return body
        end
        lastError = body
        if attempt < 3 then task.wait(attempt * 0.5) end
    end
    error("Fetch failed for '" .. path .. "': " .. tostring(lastError), 0)
end
local function requireModule(rawPath: string, ...: any): any
    local path, argumentCount = normalize(rawPath), select("#", ...)
    assertAlive()
    local currentThread = coroutine.running()
    while loading[path] do
        assert(loading[path] ~= currentThread, "Circular module dependency '" .. path .. "'")
        task.wait(); assertAlive()
    end
    if failed[path] then error(failed[path], 0) end
    if not compiledCache[path] then
        loading[path] = currentThread
        local ok, result = pcall(function()
            local source = fetch(path)
            trace("compile " .. path)
            local chunk, compileError = loadstring(source, "@" .. path)
            if not chunk then error("Syntax Error in '" .. path .. "': " .. tostring(compileError), 0) end
            trace("execute " .. path)
            local ran, factory = pcall(chunk)
            if not ran or type(factory) ~= "function" then error("Runtime Error in '" .. path .. "': " .. tostring(factory), 0) end
            assertAlive()
            return factory
        end)
        loading[path] = nil
        if not ok then failed[path] = tostring(result); error(result, 0) end
        compiledCache[path] = result
    else trace("compiled cache hit " .. path) end
    if argumentCount == 0 then return compiledCache[path] end
    while initializing[path] do
        assert(initializing[path] ~= currentThread, "Circular factory dependency '" .. path .. "'")
        task.wait(); assertAlive()
    end
    if initializedCache[path] then trace("initialized cache hit " .. path); return initializedCache[path].Value end
    initializing[path] = currentThread
    trace("factory init " .. path)
    local ok, value = pcall(compiledCache[path], ...)
    initializing[path] = nil
    assertAlive()
    if not ok then error("Init Error in '" .. path .. "': " .. tostring(value), 0) end
    initializedCache[path] = { Value = value }
    return value
end

local function step(name: string, callback: () -> any): any
    assertAlive(); trace("step start " .. name)
    local value = callback()
    assertAlive(); trace("step end " .. name)
    return value
end
local function fail(err: any)
    if globals.B0XazActiveToken ~= sessionId then return end
    warn("[B0Xaz][Boot] " .. tostring(err))
    -- Preserve the diagnostic on failed boots; explicit user unloads still clear the console.
    local master = globals.B0XazMasterDisposer
    globals.B0XazRunning, globals.B0XazLaunching, globals.B0XazActiveToken = false, nil, nil
    globals.B0XazMasterDisposer, globals.B0XazServiceContainer = nil, nil
    if master then master:Dispose() end
end
local ok, bootError = pcall(function()
    step("readiness", function()
        local deadline = os.clock() + 15
        local players = game:GetService("Players")
        while not game:IsLoaded() or not players.LocalPlayer do
            assertAlive(); assert(os.clock() < deadline, "Game readiness timed out after 15 seconds")
            task.wait(0.1)
        end
    end)
    local Disposer = step("Disposer", function() return requireModule("src/Core/Disposer.luau")() end)
    local master = Disposer.new("Master " .. sessionId)
    globals.B0XazMasterDisposer = master
    local environment = step("Environment", function() return requireModule("src/Core/Environment.luau", master) end)
    local bus = step("EventBus", function() return requireModule("src/Core/EventBus.luau", master) end)
    local state = step("StateStore", function() return requireModule("src/Core/StateStore.luau", bus, master) end)
    local scheduler = step("TaskScheduler", function() return requireModule("src/Core/TaskScheduler.luau", master) end)
    local services = step("ServiceContainer", function() return requireModule("src/Core/ServiceContainer.luau", master) end)
    services.Version = VERSION
    services:Register("Disposer", master)
    services:Register("Environment", environment)
    services:Register("EventBus", bus)
    services:Register("StateStore", state)
    services:Register("TaskScheduler", scheduler)
    services:Register("Require", requireModule)
    services:Register("DOM", step("DOM", function() return requireModule("src/UI/DOM.luau", services) end))
    globals.B0XazServiceContainer = services
    master:Connect(game:GetService("UserInputService").InputBegan, function(input: InputObject, _processed: boolean)
        if state:GetTransient("IsBindingKey") or game:GetService("UserInputService"):GetFocusedTextBox() then return end
        if environment:MatchesInput(input, state:Get("Settings.UnloadKeybind")) then globals.B0XazUnload() end
    end)
    local registration = {
        { "ConfigService", "src/Services/ConfigService.luau" }, { "PlayerTracker", "src/Services/PlayerTracker.luau" },
        { "OptimizerService", "src/Services/OptimizerService.luau" },
        { "LightingService", "src/Services/LightingService.luau" }, { "HotkeyService", "src/Services/HotkeyService.luau" },
        { "DrawingPool", "src/Visuals/DrawingPool.luau" }, { "TargetFilter", "src/Combat/TargetFilter.luau" },
        { "ESPController", "src/Visuals/ESPController.luau" }, { "OverlayController", "src/Visuals/OverlayController.luau" },
        { "LocomotionService", "src/Locomotion/LocomotionService.luau" }, { "FlightService", "src/Locomotion/FlightService.luau" },
        { "ExtrasService", "src/Services/ExtrasService.luau" }, { "AimbotService", "src/Combat/AimbotService.luau" },
        { "TriggerbotService", "src/Combat/TriggerbotService.luau" }, { "PluginManager", "src/Plugins/PluginManager.luau" },
        { "ThemeEngine", "src/UI/ThemeEngine.luau" }, { "UIEngine", "src/UI/UIEngine.luau" },
    }
    for _, entry in ipairs(registration) do
        step(entry[1], function() services:Register(entry[1], requireModule(entry[2], services)) end)
    end
    local launched = false
    local function launch()
        if globals.B0XazActiveToken ~= sessionId or launched then return end
        launched = true
        local ran, err = pcall(function()
            step("InitializeAll", function() services:InitializeAll() end)
            step("ConstructInterface", function() services:Get("UIEngine"):ConstructInterface() end)
            local branch = step("ApplyLaunchState", function() return services:Get("ConfigService"):ApplyLaunchState() end)
            trace("launch state " .. tostring(branch))
            globals.B0XazLaunching, globals.B0XazRunning = nil, true
        end)
        if not ran then fail(err) end
    end
    launch()
end)
if not ok then fail(bootError) end
