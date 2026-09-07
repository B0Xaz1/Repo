--!nonstrict
local globals: any = _G
if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok and type(value) == "table" then globals = value end
end
local BRANCH: string = if type(globals.B0XazRef) == "string" then globals.B0XazRef else "main"
local BASE: string = "https://raw.githubusercontent.com/B0Xaz1/Repo/" .. BRANCH
if globals.B0XazLoaderBusy or globals.B0XazRunning
    or (type(globals.B0XazLaunching) == "number" and os.time() - globals.B0XazLaunching < 90) then
    warn("[B0Xaz][Loader] Already running or launching; use B0XazRelaunch() for an intentional reload")
    return
end
local ticket = {}
globals.B0XazLoaderBusy = ticket
globals.B0XazRef, globals.B0XazBaseURL = BRANCH, BASE
local stage = "Readiness"
local ok, err = pcall(function()
    local deadline = os.clock() + 60
    while not game:IsLoaded() do
        if globals.B0XazLoaderBusy ~= ticket then return end
        assert(os.clock() < deadline, "game did not load within 60 seconds")
        task.wait(0.1)
    end
    local players = game:GetService("Players")
    while not players.LocalPlayer do
        if globals.B0XazLoaderBusy ~= ticket then return end
        assert(os.clock() < deadline, "LocalPlayer did not appear within 60 seconds")
        task.wait(0.1)
    end
    stage = "Download"
    local source: string? = nil
    local lastError: any = "Empty response"
    for attempt = 1, 5 do
        if globals.B0XazLoaderBusy ~= ticket then return end
        local fetched, body = pcall(function()
            return game:HttpGet(BASE .. "/init.luau?t=" .. os.time() .. "_" .. attempt)
        end)
        if fetched and type(body) == "string" and #body > 0 and not body:match("^%s*404") then source = body; break end
        lastError = body
        if attempt < 5 then task.wait(attempt * 0.7) end
    end
    assert(source, tostring(lastError))
    if globals.B0XazLoaderBusy ~= ticket then return end
    stage = "Compile"
    assert(type(loadstring) == "function", "This executor does not provide loadstring")
    local chunk, compileError = loadstring(source :: string, "@B0XazInit")
    assert(chunk, compileError)
    stage = "Run"
    local ran, runError = pcall(chunk)
    assert(ran, runError)
end)
-- Ticket identity prevents a cancelled, slow HTTP response from clearing a newer loader's lock.
if globals.B0XazLoaderBusy == ticket then globals.B0XazLoaderBusy = nil end
if not ok then warn("[B0Xaz][Loader] " .. stage .. " failure: " .. tostring(err)) end
