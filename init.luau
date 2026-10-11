local Players = game:GetService("Players")

local CONFIG = table.freeze({
    VERSION = "2.4.9",
    NOT_FOUND_BODY = "404" .. ": Not Found",
    -- Keep every module request on the immutable revision selected by loader.luau.
    DEFAULT_REF = "a4057450afa0f432096748e3cefc7680155931fb",
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
    PATH_PREFIXES = { "B0XazUniversal/", "B0Xaz-Universal/", "Universal/" },
})

local runtime: any = getfenv(0)
local globals: any = _G
if type(runtime.getgenv) == "function" then
    local ok, value = pcall(runtime.getgenv)
    if ok and type(value) == "table" then globals = value end
end

-- Do not trust a previously-set base URL: it can redirect requireModule to arbitrary
-- remote code. A full commit id is immutable; anything else falls back to this build.
local function resolveRef(value: any): string
    if type(value) == "string" and #value == 40 and value:match("^[0-9a-fA-F]+$") then
        return value:lower()
    end
    return CONFIG.DEFAULT_REF
end

local function resolveEdition(value: any): string
    if type(value) == "string" and value:lower() == "lite" then return "Lite" end
    return "Full"
end

local ref = resolveRef(globals.B0XazRef)
local edition = resolveEdition(globals.B0XazEdition)
local base = `{CONFIG.REPOSITORY}{ref}/`
local initUrl = `{base}init.luau`
local loaderUrl = `{base}loader.luau`
globals.B0XazRef, globals.B0XazBaseURL = ref, base:sub(1, -2)
globals.B0XazEdition = edition
globals.B0XazInitURL, globals.B0XazLoaderURL = initUrl, loaderUrl

local consoleFns = {}
for index, name in ipairs(CONFIG.CONSOLE_CLEAR_NAMES) do consoleFns[index] = runtime[name] end

local function disposeMaster(master: any)
    if not master then return end
    local disposed, disposeError = pcall(function() master:Dispose() end)
    local reported, errors = pcall(function() return master:GetCleanupErrors() end)
    globals.B0XazLastCleanupErrors = if reported then errors else {
        { Scope = "Master", Operation = "Read cleanup errors", Error = tostring(errors) },
    }
    if not disposed then warn(`[B0Xaz] Cleanup failed: {tostring(disposeError)}`) end
    if reported and #errors > 0 then warn(`[B0Xaz] Cleanup reported {#errors} issue(s); see B0XazLastCleanupErrors`) end
end

function globals.B0XazUnload()
    local master, container = globals.B0XazMasterDisposer, globals.B0XazServiceContainer
    globals.B0XazRunning, globals.B0XazLaunching = false, nil
    globals.B0XazActiveToken, globals.B0XazLoaderBusy = nil, nil
    globals.B0XazMasterDisposer, globals.B0XazServiceContainer = nil, nil
    local environment = if container and container:Has("Environment") then container:Get("Environment") else nil
    disposeMaster(master)
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
    -- Use this session's canonical URL instead of a mutable global override.
    local url = initUrl
    local activeEdition = resolveEdition(globals.B0XazEdition)
    globals.B0XazUnload()
    -- Relaunches stay in the active edition rather than re-opening a picker mid-session.
    globals.B0XazEdition = activeEdition
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

local now = os.time()
if type(globals.B0XazLaunching) == "number" and now - globals.B0XazLaunching < CONFIG.LAUNCH_LOCK_WINDOW then return end
globals.B0XazLaunching = now
globals.B0XazSessionId = (tonumber(globals.B0XazSessionId) or 0) + 1
local sessionId: number = globals.B0XazSessionId
local sessionToken: string = `{now}_{sessionId}`
local previous = globals.B0XazMasterDisposer
globals.B0XazRunning, globals.B0XazMasterDisposer, globals.B0XazServiceContainer = false, nil, nil
if previous then disposeMaster(previous) end
globals.B0XazActiveToken = sessionId

local function assertAlive()
    assert(globals.B0XazActiveToken == sessionId, "Session cancelled")
end

local sourceCache, compiledCache, initializedCache = {}, {}, {}
local loading, initializing, failed = {}, {}, {}

-- Modules initialize per container, so a plugin's scoped container keys its own instance
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
    disposeMaster(master)
end

local booted, bootError = pcall(function()
    step(function()
        local deadline = os.clock() + CONFIG.READINESS_TIMEOUT
        while not game:IsLoaded() or not Players.LocalPlayer do
            assertAlive(); assert(os.clock() < deadline, "Game readiness timed out")
            task.wait(CONFIG.READINESS_POLL)
        end
    end)
    local Bootstrap = step(function() return requireModule("src/Core/Bootstrap.luau") end)
    step(function()
        Bootstrap({
            Globals = globals,
            SessionId = sessionId,
            Version = CONFIG.VERSION,
            Edition = edition,
            Require = requireModule,
            Step = step,
        })
    end)
end)
if not booted then
    warn(`[B0Xaz] Boot failed: {tostring(bootError)}`)
    failBoot()
end
