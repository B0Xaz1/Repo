--!strict
local Players = game:GetService("Players")

local CONFIG = table.freeze({
    DEFAULT_BRANCH = "main",
    BASE_URL = "https://raw.githubusercontent.com/B0Xaz1/Repo/",
    READINESS_TIMEOUT = 60,
    READINESS_POLL = 0.1,
    DOWNLOAD_ATTEMPTS = 5,
    RETRY_BACKOFF = 0.7,
    LAUNCH_LOCK_WINDOW = 90,
})

local runtime: any = getfenv(0)
local globals: any = _G
if type(runtime.getgenv) == "function" then
    local ok, value = pcall(runtime.getgenv)
    if ok and type(value) == "table" then globals = value end
end

local branch: string = if type(globals.B0XazRef) == "string" then globals.B0XazRef else CONFIG.DEFAULT_BRANCH
local baseUrl: string = CONFIG.BASE_URL .. branch

if globals.B0XazLoaderBusy or globals.B0XazRunning
    or (type(globals.B0XazLaunching) == "number" and os.time() - globals.B0XazLaunching < CONFIG.LAUNCH_LOCK_WINDOW) then
    return
end

local ticket = {}
globals.B0XazLoaderBusy = ticket
globals.B0XazRef, globals.B0XazBaseURL = branch, baseUrl

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
        if fetched and type(body) == "string" and #body > 0 and not body:match("^%s*404") then return body end
        lastError = body
        if attempt < CONFIG.DOWNLOAD_ATTEMPTS then task.wait(attempt * CONFIG.RETRY_BACKOFF) end
    end
    error(tostring(lastError))
end

pcall(function()
    if not waitForReadiness() then return end
    local source = fetchSource()
    if not source or isCancelled() then return end
    assert(type(runtime.loadstring) == "function", "This executor does not provide loadstring")
    local chunk, compileError = runtime.loadstring(source, "@B0XazInit")
    assert(chunk, compileError)
    local ran, runError = pcall(chunk)
    assert(ran, runError)
end)
-- Ticket identity keeps a slow, cancelled download from clearing a newer loader's lock.
if globals.B0XazLoaderBusy == ticket then globals.B0XazLoaderBusy = nil end
