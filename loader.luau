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

    -- The launcher intentionally uses the same neutral, rounded-panel language as Midnight.
    -- It is self-contained because the ThemeEngine is not available until after selection.
    local shade = Instance.new("Frame")
    shade.Active, shade.BorderSizePixel, shade.ZIndex = true, 0, 1
    shade.BackgroundColor3, shade.BackgroundTransparency = Color3.fromRGB(0, 0, 0), 0.34
    shade.Size, shade.Parent = UDim2.fromScale(1, 1), gui

    local panel = Instance.new("Frame")
    panel.AnchorPoint, panel.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
    panel.Size, panel.BackgroundColor3, panel.BorderSizePixel, panel.ZIndex = UDim2.new(0.9, 0, 0, 342), Color3.fromRGB(12, 12, 14), 0, 2
    panel.Parent = shade
    local constraint = Instance.new("UISizeConstraint")
    constraint.MinSize, constraint.MaxSize, constraint.Parent = Vector2.new(300, 342), Vector2.new(536, 342), panel
    makeCorner(panel, 12)
    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color, panelStroke.Transparency, panelStroke.Thickness, panelStroke.Parent = Color3.fromRGB(67, 67, 73), 0.12, 1, panel

    local topRule = Instance.new("Frame")
    topRule.BackgroundColor3, topRule.BorderSizePixel, topRule.Position, topRule.Size, topRule.ZIndex = Color3.fromRGB(238, 238, 240), 0, UDim2.fromOffset(20, 18), UDim2.new(0, 28, 0, 2), 3
    topRule.Parent = panel
    makeCorner(topRule, 2)
    local eyebrow = makeLabel(panel, "B0XAZ UNIVERSAL  /  LAUNCH EDITION", UDim2.fromOffset(56, 13), UDim2.new(1, -76, 0, 14), Enum.Font.GothamMedium, 9, Color3.fromRGB(148, 148, 154))
    eyebrow.ZIndex, eyebrow.TextYAlignment = 3, Enum.TextYAlignment.Center
    local title = makeLabel(panel, "Choose your Command Deck", UDim2.fromOffset(20, 35), UDim2.new(1, -40, 0, 27), Enum.Font.GothamMedium, 19, Color3.fromRGB(250, 250, 252))
    title.ZIndex, title.TextYAlignment = 3, Enum.TextYAlignment.Center
    local summary = makeLabel(panel, "Full includes everything. Lite keeps universal controls.", UDim2.fromOffset(20, 65), UDim2.new(1, -40, 0, 18), Enum.Font.Gotham, 11, Color3.fromRGB(182, 182, 188))
    summary.ZIndex, summary.TextYAlignment, summary.TextWrapped, summary.TextTruncate = 3, Enum.TextYAlignment.Center, false, Enum.TextTruncate.AtEnd
    local divider = Instance.new("Frame")
    divider.BackgroundColor3, divider.BorderSizePixel, divider.Position, divider.Size, divider.ZIndex = Color3.fromRGB(44, 44, 49), 0, UDim2.fromOffset(20, 95), UDim2.new(1, -40, 0, 1), 3
    divider.Parent = panel

    local function choiceCard(kind: string, titleText: string, body: string, footer: string, position: UDim2): TextButton
        local button = Instance.new("TextButton")
        button.AutoButtonColor, button.Selectable, button.BorderSizePixel, button.ZIndex = false, true, 0, 4
        button.BackgroundColor3, button.Position, button.Size, button.Text = Color3.fromRGB(23, 23, 26), position, UDim2.new(0.5, -29, 0, 114), ""
        button.Parent = panel
        makeCorner(button, 8)
        local border = Instance.new("UIStroke")
        border.Color, border.Transparency, border.Thickness, border.Parent = Color3.fromRGB(67, 67, 73), 0.24, 1, button
        local kindLabel = makeLabel(button, kind, UDim2.fromOffset(13, 10), UDim2.new(1, -26, 0, 12), Enum.Font.GothamMedium, 9, Color3.fromRGB(150, 150, 156))
        kindLabel.ZIndex, kindLabel.TextYAlignment = 5, Enum.TextYAlignment.Center
        local choiceTitle = makeLabel(button, titleText, UDim2.fromOffset(13, 26), UDim2.new(1, -26, 0, 22), Enum.Font.GothamMedium, 15, Color3.fromRGB(248, 248, 250))
        choiceTitle.ZIndex, choiceTitle.TextYAlignment = 5, Enum.TextYAlignment.Center
        local description = makeLabel(button, body, UDim2.fromOffset(13, 52), UDim2.new(1, -26, 0, 33), Enum.Font.Gotham, 10, Color3.fromRGB(188, 188, 194))
        description.ZIndex, description.TextYAlignment = 5, Enum.TextYAlignment.Top
        local capability = makeLabel(button, footer, UDim2.fromOffset(13, 91), UDim2.new(1, -26, 0, 12), Enum.Font.GothamMedium, 8, Color3.fromRGB(142, 142, 148))
        capability.ZIndex, capability.TextYAlignment = 5, Enum.TextYAlignment.Center
        button.MouseEnter:Connect(function()
            button.BackgroundColor3, border.Color, border.Transparency = Color3.fromRGB(32, 32, 36), Color3.fromRGB(216, 216, 220), 0.08
        end)
        button.MouseLeave:Connect(function()
            button.BackgroundColor3, border.Color, border.Transparency = Color3.fromRGB(23, 23, 26), Color3.fromRGB(67, 67, 73), 0.24
        end)
        return button
    end

    local lite = choiceCard("LEAN SETUP", "Lite", "Core shell + tools.\nNo Game or Commands.", "NO GAME / COMMANDS", UDim2.fromOffset(20, 112))
    local full = choiceCard("COMPLETE SETUP", "Full", "Every workspace.\nAdapters + Commands.", "FULL COMMAND DECK", UDim2.new(0.5, 9, 0, 112))
    local remember = Instance.new("TextButton")
    local canRemember, remembered = type(readFile) == "function" and type(writeFile) == "function", false
    remember.AutoButtonColor, remember.Selectable, remember.BorderSizePixel, remember.ZIndex = false, true, 0, 4
    remember.BackgroundColor3, remember.Position, remember.Size = Color3.fromRGB(18, 18, 21), UDim2.fromOffset(20, 244), UDim2.new(1, -40, 0, 36)
    remember.Font, remember.TextSize, remember.TextXAlignment, remember.Parent = Enum.Font.GothamMedium, 10, Enum.TextXAlignment.Left, panel
    makeCorner(remember, 7)
    local rememberStroke = Instance.new("UIStroke")
    rememberStroke.Color, rememberStroke.Transparency, rememberStroke.Parent = Color3.fromRGB(52, 52, 58), 0.28, remember
    local rememberPadding = Instance.new("UIPadding")
    rememberPadding.PaddingLeft, rememberPadding.PaddingRight, rememberPadding.Parent = UDim.new(0, 12), UDim.new(0, 12), remember
    local function renderRemember()
        if canRemember then
            remember.Text = if remembered then "REMEMBER THIS CHOICE     ON" else "REMEMBER THIS CHOICE     OFF"
            remember.TextColor3 = if remembered then Color3.fromRGB(244, 244, 246) else Color3.fromRGB(178, 178, 184)
        else
            remember.Text, remember.TextColor3 = "REMEMBERING IS UNAVAILABLE IN THIS EXECUTOR", Color3.fromRGB(136, 136, 142)
        end
    end
    renderRemember()
    if canRemember then
        remember.Activated:Connect(function()
            remembered = not remembered
            renderRemember()
        end)
    end
    local hint = makeLabel(panel, "You can change the next-launch preference later in Settings.", UDim2.fromOffset(20, 298), UDim2.new(1, -40, 0, 18), Enum.Font.Gotham, 10, Color3.fromRGB(135, 135, 141))
    hint.ZIndex, hint.TextYAlignment, hint.TextXAlignment, hint.TextWrapped, hint.TextTruncate = 3, Enum.TextYAlignment.Center, Enum.TextXAlignment.Center, false, Enum.TextTruncate.AtEnd

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
