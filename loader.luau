local Players = game:GetService("Players")

local CONFIG = table.freeze({
    -- A full Git object id makes the download immutable. The loader intentionally
    -- does not follow a mutable branch such as main.
    DEFAULT_REF = "ed45c8c6f00b8ee7fdb2ddb3101eaa1a8cddd157",
    BASE_URL = "https://raw.githubusercontent.com/B0Xaz1/Repo/",
    READINESS_TIMEOUT = 60,
    READINESS_POLL = 0.1,
    DOWNLOAD_ATTEMPTS = 5,
    RETRY_BACKOFF = 0.7,
    LAUNCH_LOCK_WINDOW = 90,
    MIN_SOURCE_LENGTH = 10,
    NOT_FOUND_BODY = "404" .. ": Not Found",
})

local runtime: any = getfenv(0)
local globals: any = _G
if type(runtime.getgenv) == "function" then
    local ok, value = pcall(runtime.getgenv)
    if ok and type(value) == "table" then globals = value end
end

-- Custom revisions are allowed only as immutable, full commit ids. Never interpolate
-- a branch, path, query, or caller-provided host into a code-download URL.
local function resolveRef(value: any): string
    if type(value) == "string" and #value == 40 and value:match("^[0-9a-fA-F]+$") then
        return value:lower()
    end
    return CONFIG.DEFAULT_REF
end

local ref = resolveRef(globals.B0XazRef)
local baseUrl = CONFIG.BASE_URL .. ref

if globals.B0XazLoaderBusy or globals.B0XazRunning
    or (type(globals.B0XazLaunching) == "number" and os.time() - globals.B0XazLaunching < CONFIG.LAUNCH_LOCK_WINDOW) then
    return
end

local ticket = {}
globals.B0XazLoaderBusy = ticket
globals.B0XazRef = ref
globals.B0XazBaseURL = baseUrl
globals.B0XazInitURL = `{baseUrl}/init.luau`
globals.B0XazLoaderURL = `{baseUrl}/loader.luau`

-- A later loader run replaces the ticket, which cancels this run at its next checkpoint
local function isCancelled(): boolean
    return globals.B0XazLoaderBusy ~= ticket
end

local function waitForReadiness(): boolean
    local deadline = os.clock() + CONFIG.READINESS_TIMEOUT
    while not game:IsLoaded() do
        if isCancelled() then return false end
        assert(os.clock() < deadline, "Game did not load within the readiness window")
        task.wait(CONFIG.READINESS_POLL)
    end
    while not Players.LocalPlayer do
        if isCancelled() then return false end
        assert(os.clock() < deadline, "LocalPlayer did not appear within the readiness window")
        task.wait(CONFIG.READINESS_POLL)
    end
    return true
end

local function fetchSource(): string?
    local lastError: any = "Empty response"
    for attempt = 1, CONFIG.DOWNLOAD_ATTEMPTS do
        if isCancelled() then return nil end
        local fetched, body = pcall(function()
            return game:HttpGet(`{baseUrl}/init.luau?t={os.time()}_{attempt}`)
        end)
        if fetched and type(body) == "string" and #body >= CONFIG.MIN_SOURCE_LENGTH
            and not body:find(CONFIG.NOT_FOUND_BODY, 1, true) then
            return body
        end
        lastError = body
        if attempt < CONFIG.DOWNLOAD_ATTEMPTS then task.wait(attempt * CONFIG.RETRY_BACKOFF) end
    end
    error(tostring(lastError))
end

local booted, bootError = pcall(function()
    if not waitForReadiness() then return end
    local source = fetchSource()
    if not source or isCancelled() then return end
    assert(type(runtime.loadstring) == "function", "This executor does not provide loadstring")
    local chunk, compileError = runtime.loadstring(source, "@B0XazInit")
    assert(chunk, compileError)
    local ran, runError = pcall(chunk)
    assert(ran, runError)
end)
if not booted then
    warn(`[B0Xaz] Loader failed: {tostring(bootError)}`)
end
if globals.B0XazLoaderBusy == ticket then globals.B0XazLoaderBusy = nil end
