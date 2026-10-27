local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local CONFIG = table.freeze({
    -- A full Git object id makes the download immutable. The loader intentionally
    -- does not follow a mutable branch such as main.
    DEFAULT_REF = "d884f8ca2059bb3ea2789e3440b7a2c399e6ddac",
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

-- A pasted current loader must replace an already-running older build instead of inheriting
-- that build's B0XazRef. Retaining it made updates silently reload the same old implementation.
local replacingRunningSession = globals.B0XazRunning == true
local ref = resolveRef(if replacingRunningSession then CONFIG.DEFAULT_REF else globals.B0XazRef)
local baseUrl = CONFIG.BASE_URL .. ref

if globals.B0XazLoaderBusy then return end
if replacingRunningSession then
    local unload = globals.B0XazUnload
    if type(unload) ~= "function" then return end
    pcall(unload)
    if globals.B0XazRunning == true then return end
end
if type(globals.B0XazLaunching) == "number" and os.time() - globals.B0XazLaunching < CONFIG.LAUNCH_LOCK_WINDOW then return end

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

    -- The edition picker is deliberately self-contained: it should feel like a
    -- short launch step, not a second version of the main workspace.
    local shade = Instance.new("Frame")
    shade.Active, shade.BorderSizePixel, shade.ZIndex = true, 0, 1
    shade.BackgroundColor3, shade.BackgroundTransparency = Color3.fromRGB(3, 5, 10), 0.28
    shade.Size, shade.Parent = UDim2.fromScale(1, 1), gui

    local panel = Instance.new("Frame")
    panel.Name = "LaunchSetup"
    panel.AnchorPoint, panel.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
    panel.Size, panel.BackgroundColor3, panel.BorderSizePixel, panel.ZIndex = UDim2.new(0.9, 0, 0, 340), Color3.fromRGB(14, 17, 25), 0, 3
    panel.Parent = shade
    local constraint = Instance.new("UISizeConstraint")
    constraint.MinSize, constraint.MaxSize, constraint.Parent = Vector2.new(304, 340), Vector2.new(540, 340), panel
    makeCorner(panel, 12)
    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color, panelStroke.Transparency, panelStroke.Thickness, panelStroke.Parent = Color3.fromRGB(104, 122, 175), 0.38, 1, panel
    local panelGradient = Instance.new("UIGradient")
    panelGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 24, 37)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 14, 21)),
    })
    panelGradient.Rotation, panelGradient.Parent = 90, panel

    local accent = Instance.new("Frame")
    accent.BorderSizePixel, accent.BackgroundColor3, accent.Position, accent.Size, accent.ZIndex = 0, Color3.fromRGB(115, 132, 255), UDim2.fromOffset(20, 20), UDim2.fromOffset(4, 49), 4
    accent.Parent = panel
    makeCorner(accent, 2)
    local accentGradient = Instance.new("UIGradient")
    accentGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(142, 157, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(97, 109, 228)),
    })
    accentGradient.Rotation, accentGradient.Parent = 90, accent

    local eyebrow = makeLabel(panel, "B0XAZ UNIVERSAL", UDim2.fromOffset(35, 17), UDim2.new(1, -150, 0, 14), Enum.Font.GothamBold, 10, Color3.fromRGB(160, 174, 255))
    eyebrow.ZIndex, eyebrow.TextYAlignment = 4, Enum.TextYAlignment.Center
    local title = makeLabel(panel, "Choose your workspace", UDim2.fromOffset(35, 33), UDim2.new(1, -55, 0, 25), Enum.Font.GothamBold, 18, Color3.fromRGB(246, 248, 255))
    title.ZIndex, title.TextYAlignment = 4, Enum.TextYAlignment.Center
    local subtitle = makeLabel(panel, "Select the toolset for this launch. You can change it later.", UDim2.fromOffset(35, 58), UDim2.new(1, -55, 0, 16), Enum.Font.Gotham, 10, Color3.fromRGB(166, 174, 194))
    subtitle.ZIndex, subtitle.TextYAlignment = 4, Enum.TextYAlignment.Center
    local setupLabel = makeLabel(panel, "LAUNCH SETUP", UDim2.new(1, -118, 0, 23), UDim2.fromOffset(98, 15), Enum.Font.GothamBold, 8, Color3.fromRGB(114, 126, 162))
    setupLabel.ZIndex, setupLabel.TextXAlignment, setupLabel.TextYAlignment = 4, Enum.TextXAlignment.Right, Enum.TextYAlignment.Center

    local divider = Instance.new("Frame")
    divider.BackgroundColor3, divider.BackgroundTransparency, divider.BorderSizePixel, divider.Position, divider.Size, divider.ZIndex = Color3.fromRGB(100, 113, 150), 0.72, 0, UDim2.fromOffset(20, 86), UDim2.new(1, -40, 0, 1), 4
    divider.Parent = panel

    local function editionOption(titleText: string, badgeText: string, description: string, position: UDim2, tint: Color3): TextButton
        local option = Instance.new("TextButton")
        option.Name = `{titleText}Edition`
        option.AutoButtonColor, option.Selectable, option.BorderSizePixel, option.ZIndex = false, true, 0, 4
        option.BackgroundColor3, option.Position, option.Size, option.Text = Color3.fromRGB(24, 29, 42), position, UDim2.new(1, -40, 0, 64), ""
        option.Parent = panel
        makeCorner(option, 9)
        local border = Instance.new("UIStroke")
        border.Color, border.Transparency, border.Thickness, border.Parent = Color3.fromRGB(74, 84, 113), 0.52, 1, option

        local mark = Instance.new("Frame")
        mark.BackgroundColor3, mark.BorderSizePixel, mark.Position, mark.Size, mark.ZIndex, mark.Parent = tint, 0, UDim2.fromOffset(12, 12), UDim2.fromOffset(40, 40), 5, option
        makeCorner(mark, 8)
        local markText = makeLabel(mark, if titleText == "Lite" then "L" else "F", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.Font.GothamBold, 15, Color3.fromRGB(247, 249, 255))
        markText.ZIndex, markText.TextXAlignment, markText.TextYAlignment = 6, Enum.TextXAlignment.Center, Enum.TextYAlignment.Center

        local optionTitle = makeLabel(option, titleText, UDim2.fromOffset(64, 10), UDim2.new(1, -170, 0, 19), Enum.Font.GothamBold, 14, Color3.fromRGB(247, 249, 255))
        optionTitle.ZIndex, optionTitle.TextYAlignment = 5, Enum.TextYAlignment.Center
        local detail = makeLabel(option, description, UDim2.fromOffset(64, 31), UDim2.new(1, -170, 0, 21), Enum.Font.Gotham, 9, Color3.fromRGB(168, 177, 199))
        detail.ZIndex, detail.TextYAlignment = 5, Enum.TextYAlignment.Center

        local badge = makeLabel(option, badgeText, UDim2.new(1, -106, 0, 12), UDim2.fromOffset(70, 15), Enum.Font.GothamBold, 8, tint)
        badge.ZIndex, badge.TextXAlignment, badge.TextYAlignment = 5, Enum.TextXAlignment.Right, Enum.TextYAlignment.Center
        local indicator = Instance.new("Frame")
        indicator.BackgroundColor3, indicator.BorderSizePixel, indicator.Position, indicator.Size, indicator.ZIndex, indicator.Parent = Color3.fromRGB(55, 64, 89), 0, UDim2.new(1, -28, 0.5, -8), UDim2.fromOffset(16, 16), 5, option
        makeCorner(indicator, 8)
        local indicatorStroke = Instance.new("UIStroke")
        indicatorStroke.Color, indicatorStroke.Transparency, indicatorStroke.Parent = tint, 0.35, indicator
        local dot = Instance.new("Frame")
        dot.BackgroundColor3, dot.BackgroundTransparency, dot.BorderSizePixel, dot.AnchorPoint, dot.Position, dot.Size, dot.ZIndex, dot.Parent = tint, 1, 0, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(6, 6), 6, indicator
        makeCorner(dot, 3)

        option.MouseEnter:Connect(function()
            option.BackgroundColor3, border.Color, border.Transparency = Color3.fromRGB(31, 37, 54), tint, 0.08
            indicator.BackgroundColor3, dot.BackgroundTransparency = tint, 0
        end)
        option.MouseLeave:Connect(function()
            option.BackgroundColor3, border.Color, border.Transparency = Color3.fromRGB(24, 29, 42), Color3.fromRGB(74, 84, 113), 0.52
            indicator.BackgroundColor3, dot.BackgroundTransparency = Color3.fromRGB(55, 64, 89), 1
        end)
        return option
    end

    local lite = editionOption("Lite", "CORE", "Universal tools only. Adapters and Commands stay off.", UDim2.fromOffset(20, 101), Color3.fromRGB(111, 196, 173))
    local full = editionOption("Full", "ALL FEATURES", "Everything enabled: workspaces, adapters, and Commands.", UDim2.fromOffset(20, 172), Color3.fromRGB(142, 157, 255))

    local remember = Instance.new("TextButton")
    local canRemember, remembered = type(readFile) == "function" and type(writeFile) == "function", false
    remember.Name = "RememberChoice"
    remember.AutoButtonColor, remember.Selectable, remember.BackgroundTransparency, remember.BorderSizePixel, remember.ZIndex, remember.Text = false, true, 1, 0, 4, ""
    remember.Position, remember.Size, remember.Parent = UDim2.fromOffset(20, 248), UDim2.new(1, -40, 0, 24), panel
    local box = Instance.new("Frame")
    box.BackgroundColor3, box.BorderSizePixel, box.Position, box.Size, box.ZIndex, box.Parent = Color3.fromRGB(28, 34, 49), 0, UDim2.fromOffset(0, 2), UDim2.fromOffset(20, 20), 5, remember
    makeCorner(box, 6)
    local boxStroke = Instance.new("UIStroke")
    boxStroke.Color, boxStroke.Transparency, boxStroke.Parent = Color3.fromRGB(85, 97, 131), 0.38, box
    local check = makeLabel(remember, "✓", UDim2.fromOffset(0, 2), UDim2.fromOffset(20, 20), Enum.Font.GothamBold, 12, Color3.fromRGB(14, 17, 25))
    check.ZIndex, check.TextXAlignment, check.TextYAlignment = 6, Enum.TextXAlignment.Center, Enum.TextYAlignment.Center
    local rememberText = makeLabel(remember, "Remember my choice", UDim2.fromOffset(30, 0), UDim2.new(1, -30, 1, 0), Enum.Font.GothamMedium, 10, Color3.fromRGB(201, 207, 225))
    rememberText.ZIndex, rememberText.TextYAlignment = 5, Enum.TextYAlignment.Center
    local function renderRemember()
        check.Visible = canRemember and remembered
        if canRemember then
            rememberText.Text, rememberText.TextColor3 = "Remember my choice", Color3.fromRGB(201, 207, 225)
            box.BackgroundColor3 = if remembered then Color3.fromRGB(142, 157, 255) else Color3.fromRGB(28, 34, 49)
        else
            rememberText.Text, rememberText.TextColor3 = "Remembering is unavailable in this executor", Color3.fromRGB(126, 136, 161)
            box.BackgroundColor3 = Color3.fromRGB(28, 34, 49)
        end
    end
    renderRemember()
    if canRemember then
        remember.Activated:Connect(function()
            remembered = not remembered
            renderRemember()
        end)
    end

    local footerLine = Instance.new("Frame")
    footerLine.BackgroundColor3, footerLine.BackgroundTransparency, footerLine.BorderSizePixel, footerLine.Position, footerLine.Size, footerLine.ZIndex = Color3.fromRGB(100, 113, 150), 0.8, 0, UDim2.fromOffset(20, 283), UDim2.new(1, -40, 0, 1), 4
    footerLine.Parent = panel
    local hint = makeLabel(panel, "Your choice only affects this launch · Change it anytime in Settings", UDim2.fromOffset(20, 296), UDim2.new(1, -40, 0, 17), Enum.Font.Gotham, 9, Color3.fromRGB(126, 136, 161))
    hint.ZIndex, hint.TextXAlignment, hint.TextYAlignment = 4, Enum.TextXAlignment.Center, Enum.TextYAlignment.Center

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
