local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local CONFIG = table.freeze({
    -- A full Git object id makes the download immutable. The loader intentionally
    -- does not follow a mutable branch such as main.
    DEFAULT_REF = "705883ef863bef3c2366a4b2a80e2e611747876d",
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

    -- Keep this small launcher plain: it is a one-time choice, not another workspace.
    local shade = Instance.new("Frame")
    shade.Active, shade.BorderSizePixel, shade.ZIndex = true, 0, 1
    shade.BackgroundColor3, shade.BackgroundTransparency = Color3.fromRGB(0, 0, 0), 0.38
    shade.Size, shade.Parent = UDim2.fromScale(1, 1), gui
    local panel = Instance.new("Frame")
    panel.AnchorPoint, panel.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
    panel.Size, panel.BackgroundColor3, panel.BorderSizePixel, panel.ZIndex = UDim2.new(0.9, 0, 0, 318), Color3.fromRGB(14, 14, 16), 0, 2
    panel.Parent = shade
    local constraint = Instance.new("UISizeConstraint")
    constraint.MinSize, constraint.MaxSize, constraint.Parent = Vector2.new(300, 318), Vector2.new(520, 318), panel
    makeCorner(panel, 10)
    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color, panelStroke.Transparency, panelStroke.Parent = Color3.fromRGB(64, 64, 70), 0.12, panel

    local brand = makeLabel(panel, "B0Xaz Universal", UDim2.fromOffset(20, 16), UDim2.new(1, -40, 0, 23), Enum.Font.GothamMedium, 17, Color3.fromRGB(248, 248, 250))
    brand.ZIndex, brand.TextYAlignment = 3, Enum.TextYAlignment.Center
    local prompt = makeLabel(panel, "Choose an edition for this launch.", UDim2.fromOffset(20, 42), UDim2.new(1, -40, 0, 18), Enum.Font.Gotham, 11, Color3.fromRGB(176, 176, 182))
    prompt.ZIndex, prompt.TextYAlignment = 3, Enum.TextYAlignment.Center
    local divider = Instance.new("Frame")
    divider.BackgroundColor3, divider.BorderSizePixel, divider.Position, divider.Size, divider.ZIndex = Color3.fromRGB(46, 46, 51), 0, UDim2.fromOffset(20, 70), UDim2.new(1, -40, 0, 1), 3
    divider.Parent = panel

    local function editionOption(title: string, description: string, position: UDim2): TextButton
        local button = Instance.new("TextButton")
        button.AutoButtonColor, button.Selectable, button.BorderSizePixel, button.ZIndex = false, true, 0, 4
        button.BackgroundColor3, button.Position, button.Size, button.Text = Color3.fromRGB(24, 24, 27), position, UDim2.new(1, -40, 0, 70), ""
        button.Parent = panel
        makeCorner(button, 7)
        local border = Instance.new("UIStroke")
        border.Color, border.Transparency, border.Parent = Color3.fromRGB(62, 62, 68), 0.24, button
        local optionTitle = makeLabel(button, title, UDim2.fromOffset(13, 9), UDim2.new(1, -64, 0, 18), Enum.Font.GothamMedium, 14, Color3.fromRGB(247, 247, 249))
        optionTitle.ZIndex, optionTitle.TextYAlignment = 5, Enum.TextYAlignment.Center
        local optionDetail = makeLabel(button, description, UDim2.fromOffset(13, 30), UDim2.new(1, -64, 0, 28), Enum.Font.Gotham, 10, Color3.fromRGB(182, 182, 188))
        optionDetail.ZIndex, optionDetail.TextYAlignment = 5, Enum.TextYAlignment.Top
        local arrow = makeLabel(button, "›", UDim2.new(1, -34, 0.5, -14), UDim2.fromOffset(20, 28), Enum.Font.GothamMedium, 22, Color3.fromRGB(166, 166, 172))
        arrow.ZIndex, arrow.TextXAlignment, arrow.TextYAlignment = 5, Enum.TextXAlignment.Center, Enum.TextYAlignment.Center
        button.MouseEnter:Connect(function()
            button.BackgroundColor3, border.Color, border.Transparency = Color3.fromRGB(32, 32, 36), Color3.fromRGB(204, 204, 208), 0.08
        end)
        button.MouseLeave:Connect(function()
            button.BackgroundColor3, border.Color, border.Transparency = Color3.fromRGB(24, 24, 27), Color3.fromRGB(62, 62, 68), 0.24
        end)
        return button
    end

    local lite = editionOption("Lite", "Universal tools only. Game adapters and Commands stay off.", UDim2.fromOffset(20, 86))
    local full = editionOption("Full", "Everything enabled: workspaces, game adapters, and Commands.", UDim2.fromOffset(20, 163))
    local remember = Instance.new("TextButton")
    local canRemember, remembered = type(readFile) == "function" and type(writeFile) == "function", false
    remember.AutoButtonColor, remember.Selectable, remember.BackgroundTransparency, remember.BorderSizePixel, remember.ZIndex = false, true, 1, 0, 4
    remember.Position, remember.Size, remember.Parent = UDim2.fromOffset(20, 248), UDim2.new(1, -40, 0, 25), panel
    local box = Instance.new("Frame")
    box.BackgroundColor3, box.BorderSizePixel, box.Position, box.Size, box.ZIndex, box.Parent = Color3.fromRGB(31, 31, 35), 0, UDim2.fromOffset(0, 3), UDim2.fromOffset(18, 18), 5, remember
    makeCorner(box, 4)
    local boxStroke = Instance.new("UIStroke")
    boxStroke.Color, boxStroke.Transparency, boxStroke.Parent = Color3.fromRGB(79, 79, 86), 0.25, box
    local check = makeLabel(remember, "✓", UDim2.fromOffset(0, 2), UDim2.fromOffset(18, 18), Enum.Font.GothamMedium, 12, Color3.fromRGB(246, 246, 248))
    check.ZIndex, check.TextXAlignment, check.TextYAlignment = 6, Enum.TextXAlignment.Center, Enum.TextYAlignment.Center
    local rememberText = makeLabel(remember, "Remember my choice", UDim2.fromOffset(27, 0), UDim2.new(1, -27, 1, 0), Enum.Font.Gotham, 11, Color3.fromRGB(190, 190, 196))
    rememberText.ZIndex, rememberText.TextYAlignment = 5, Enum.TextYAlignment.Center
    local function renderRemember()
        check.Visible = canRemember and remembered
        if canRemember then
            rememberText.Text, rememberText.TextColor3 = "Remember my choice", Color3.fromRGB(190, 190, 196)
            box.BackgroundColor3 = if remembered then Color3.fromRGB(218, 218, 222) else Color3.fromRGB(31, 31, 35)
            check.TextColor3 = if remembered then Color3.fromRGB(18, 18, 21) else Color3.fromRGB(246, 246, 248)
        else
            rememberText.Text, rememberText.TextColor3 = "Remembering is unavailable in this executor", Color3.fromRGB(134, 134, 140)
            box.BackgroundColor3 = Color3.fromRGB(31, 31, 35)
        end
    end
    renderRemember()
    if canRemember then
        remember.Activated:Connect(function()
            remembered = not remembered
            renderRemember()
        end)
    end
    local hint = makeLabel(panel, "You can change this later in Settings.", UDim2.fromOffset(20, 281), UDim2.new(1, -40, 0, 17), Enum.Font.Gotham, 10, Color3.fromRGB(134, 134, 140))
    hint.ZIndex, hint.TextXAlignment, hint.TextYAlignment = 3, Enum.TextXAlignment.Center, Enum.TextYAlignment.Center

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
