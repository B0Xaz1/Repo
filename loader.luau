local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local CONFIG = table.freeze({
    -- A full Git object id makes the download immutable. The loader intentionally
    -- does not follow a mutable branch such as main.
    DEFAULT_REF = "4146495170a4f3c260b086b85bc9424db851d11a",
    BASE_URL = "https://raw.githubusercontent.com/B0Xaz1/Repo/",
    READINESS_TIMEOUT = 60,
    READINESS_POLL = 0.1,
    DOWNLOAD_ATTEMPTS = 5,
    RETRY_BACKOFF = 0.7,
    LAUNCH_LOCK_WINDOW = 90,
    MIN_SOURCE_LENGTH = 10,
    NOT_FOUND_BODY = "404" .. ": Not Found",
    EDITION_PREFERENCE_FILE = "B0XazUniversal/edition-preference.json",
    EDITION_PREFERENCE_FOLDER = "B0XazUniversal",
    MAX_EDITION_PREFERENCE_BYTES = 4096,
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

local function normalizeEdition(value: any): string?
    if type(value) ~= "string" then return nil end
    local normalized = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if normalized == "lite" then return "Lite" end
    if normalized == "full" then return "Full" end
    return nil
end

local readFile = runtime.readfile
local writeFile = runtime.writefile
local isFile = runtime.isfile
local makeFolder = runtime.makefolder

local function readRememberedEdition(): string?
    if type(readFile) ~= "function" then return nil end
    if type(isFile) == "function" then
        local checked, present = pcall(isFile, CONFIG.EDITION_PREFERENCE_FILE)
        if checked and not present then return nil end
    end
    local read, raw = pcall(readFile, CONFIG.EDITION_PREFERENCE_FILE)
    if not read or type(raw) ~= "string" or #raw > CONFIG.MAX_EDITION_PREFERENCE_BYTES then return nil end
    local decoded, payload = pcall(function() return HttpService:JSONDecode(raw) end)
    if not decoded or type(payload) ~= "table" then return nil end
    return normalizeEdition(payload.Edition)
end

local function saveRememberedEdition(edition: string): (boolean, string?)
    if type(writeFile) ~= "function" then return false, "File persistence is unavailable" end
    if type(makeFolder) == "function" then pcall(makeFolder, CONFIG.EDITION_PREFERENCE_FOLDER) end
    local encoded, payload = pcall(function() return HttpService:JSONEncode({ Format = 1, Edition = edition }) end)
    if not encoded then return false, tostring(payload) end
    local written, writeError = pcall(writeFile, CONFIG.EDITION_PREFERENCE_FILE, payload)
    return written, if written then nil else tostring(writeError)
end

local function getGuiParent(): Instance?
    local candidates = {}
    if type(runtime.gethui) == "function" then
        local ok, parent = pcall(runtime.gethui)
        if ok and typeof(parent) == "Instance" then table.insert(candidates, parent) end
    end
    pcall(function() table.insert(candidates, game:GetService("CoreGui")) end)
    local player = Players.LocalPlayer
    if player then
        local playerGui = player:FindFirstChildOfClass("PlayerGui")
        if playerGui then table.insert(candidates, playerGui) end
    end
    for _, parent in ipairs(candidates) do
        local probe = Instance.new("Folder")
        local writable = pcall(function() probe.Parent = parent end)
        probe:Destroy()
        if writable then return parent end
    end
    return nil
end

local function makeCorner(parent: Instance, radius: number)
    local corner = Instance.new("UICorner")
    corner.CornerRadius, corner.Parent = UDim.new(0, radius), parent
end

local function makeLabel(parent: Instance, text: string, position: UDim2, size: UDim2, font: any, textSize: number, color: Color3): TextLabel
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency, label.BorderSizePixel = 1, 0
    label.Position, label.Size = position, size
    label.Text, label.Font, label.TextSize, label.TextColor3 = text, font, textSize, color
    label.TextXAlignment, label.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
    label.TextWrapped, label.Parent = true, parent
    return label
end

local function showEditionPicker(): string?
    local parent = getGuiParent()
    if not parent then
        warn("[B0Xaz] Edition picker could not be shown; starting Full for this launch")
        return "Full"
    end

    local gui = Instance.new("ScreenGui")
    gui.Name, gui.IgnoreGuiInset, gui.ResetOnSpawn = "B0XazEditionPicker", true, false
    gui.ZIndexBehavior, gui.DisplayOrder = Enum.ZIndexBehavior.Sibling, 1000000
    local parented = pcall(function() gui.Parent = parent end)
    if not parented then
        gui:Destroy()
        warn("[B0Xaz] Edition picker could not be mounted; starting Full for this launch")
        return "Full"
    end

    local shade = Instance.new("Frame")
    shade.BackgroundColor3, shade.BackgroundTransparency, shade.BorderSizePixel = Color3.fromRGB(0, 0, 0), 0.25, 0
    shade.Size, shade.Parent = UDim2.fromScale(1, 1), gui
    local card = Instance.new("Frame")
    card.AnchorPoint, card.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
    card.Size, card.BackgroundColor3, card.BorderSizePixel = UDim2.new(0.86, 0, 0, 286), Color3.fromRGB(15, 16, 20), 0
    card.Parent = shade
    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.MaxSize, sizeConstraint.Parent = Vector2.new(430, 286), card
    makeCorner(card, 10)
    local stroke = Instance.new("UIStroke")
    stroke.Color, stroke.Transparency, stroke.Parent = Color3.fromRGB(67, 71, 82), 0.25, card

    makeLabel(card, "B0Xaz Universal", UDim2.fromOffset(20, 18), UDim2.new(1, -40, 0, 24), Enum.Font.GothamMedium, 18, Color3.fromRGB(242, 244, 248))
    makeLabel(card, "Choose how this Command Deck launch should run.", UDim2.fromOffset(20, 47), UDim2.new(1, -40, 0, 32), Enum.Font.Gotham, 11, Color3.fromRGB(168, 174, 186))

    local function choiceButton(text: string, position: UDim2, accent: Color3): TextButton
        local button = Instance.new("TextButton")
        button.AutoButtonColor, button.BorderSizePixel = false, 0
        button.Position, button.Size = position, UDim2.new(0.5, -25, 0, 86)
        button.BackgroundColor3, button.TextColor3 = Color3.fromRGB(28, 30, 37), Color3.fromRGB(236, 238, 244)
        button.Font, button.TextSize, button.TextWrapped = Enum.Font.GothamMedium, 12, true
        button.TextXAlignment, button.TextYAlignment, button.Text = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top, text
        button.Parent = card
        makeCorner(button, 7)
        local buttonStroke = Instance.new("UIStroke")
        buttonStroke.Color, buttonStroke.Transparency, buttonStroke.Parent = accent, 0.3, button
        local padding = Instance.new("UIPadding")
        padding.PaddingTop, padding.PaddingRight = UDim.new(0, 11), UDim.new(0, 10)
        padding.PaddingBottom, padding.PaddingLeft = UDim.new(0, 9), UDim.new(0, 10)
        padding.Parent = button
        return button
    end

    local lite = choiceButton("LITE\nUniversal shell and controls.\nNo adapters, Game, or Commands.", UDim2.fromOffset(20, 91), Color3.fromRGB(118, 184, 255))
    local full = choiceButton("FULL\nAll workspaces, adapters,\nand Commands.", UDim2.new(0.5, 5, 0, 91), Color3.fromRGB(187, 135, 255))
    local remember = Instance.new("TextButton")
    local canRemember, remembered = type(readFile) == "function" and type(writeFile) == "function", false
    remember.AutoButtonColor, remember.BorderSizePixel = false, 0
    remember.Position, remember.Size = UDim2.fromOffset(20, 191), UDim2.new(1, -40, 0, 32)
    remember.BackgroundColor3, remember.TextColor3 = Color3.fromRGB(31, 34, 41), Color3.fromRGB(205, 209, 218)
    remember.Font, remember.TextSize, remember.TextXAlignment = Enum.Font.Gotham, 11, Enum.TextXAlignment.Center
    remember.Parent = card
    makeCorner(remember, 6)
    local rememberStroke = Instance.new("UIStroke")
    rememberStroke.Color, rememberStroke.Transparency, rememberStroke.Parent = Color3.fromRGB(75, 80, 92), 0.4, remember
    local function renderRemember()
        if canRemember then
            remember.Text = if remembered then "Remember this choice: On" else "Remember this choice: Off"
            remember.TextColor3 = if remembered then Color3.fromRGB(156, 211, 255) else Color3.fromRGB(205, 209, 218)
        else
            remember.Text, remember.TextColor3 = "Remembering is unavailable in this executor", Color3.fromRGB(143, 148, 160)
        end
    end
    renderRemember()
    if canRemember then
        remember.Activated:Connect(function()
            remembered = not remembered
            renderRemember()
        end)
    end
    makeLabel(card, "You can change this next-launch preference later in Settings.", UDim2.fromOffset(20, 238), UDim2.new(1, -40, 0, 30), Enum.Font.Gotham, 10, Color3.fromRGB(143, 148, 160))

    local selection: string? = nil
    local function selectEdition(edition: string)
        if selection or isCancelled() then return end
        selection = edition
        if remembered then
            local saved, saveError = saveRememberedEdition(edition)
            if not saved then warn(`[B0Xaz] Could not remember edition: {tostring(saveError)}`) end
        end
    end
    lite.Activated:Connect(function() selectEdition("Lite") end)
    full.Activated:Connect(function() selectEdition("Full") end)
    while not selection and not isCancelled() do task.wait() end
    pcall(function() gui:Destroy() end)
    return if isCancelled() then nil else selection
end

local function chooseEdition(): string?
    -- A teleport can carry the active edition once without changing the saved preference.
    local override = normalizeEdition(globals.B0XazEditionOverride)
    globals.B0XazEditionOverride = nil
    if override then return override end
    local remembered = readRememberedEdition()
    if remembered then return remembered end
    return showEditionPicker()
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
    local edition = chooseEdition()
    if not edition or isCancelled() then return end
    globals.B0XazEdition = edition
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
