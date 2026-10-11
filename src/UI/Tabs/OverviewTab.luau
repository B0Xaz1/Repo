local CONFIG = table.freeze({
    CHANGELOG_REPOSITORY = "https://raw.githubusercontent.com/B0Xaz1/Repo/",
    MAX_CHANGELOG_BYTES = 256 * 1024,
})

return function(services: any, tab: any): any
    local dom, theme, bus = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("EventBus")
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local config, environment = services:Get("ConfigService"), services:Get("Environment")
    local plugins = if services:Has("PluginManager") then services:Get("PluginManager") else nil
    local scope = services:Get("Disposer"):CreateChild("Overview tab")

    tab.Dashboard.Visible = true

    local function createCard(title: string, value: string, detail: string, order: number): any
        local card = dom:Create("Frame", { Parent = tab.Dashboard, Name = "DashboardCard", BorderSizePixel = 0,
            Size = UDim2.new(1 / 3, -8, 0, 88), BackgroundColor3 = theme:GetToken("Panel"), LayoutOrder = order })
        theme:BindToken(card, "BackgroundColor3", "Panel")
        dom:Create("UICorner", { Parent = card, CornerRadius = UDim.new(0, 7) })
        theme:BindToken(dom:CreateStroke(card, theme:GetToken("Border")), "Color", "Border")
        dom:CreatePadding(card, 11, 12, 10, 12)
        dom:Create("UIListLayout", { Parent = card, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder })
        local heading = dom:Create("TextLabel", { Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14), Text = title,
            Font = Enum.Font.GothamMedium, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0 })
        local valueLabel = dom:Create("TextLabel", { Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), Text = value,
            Font = Enum.Font.GothamMedium, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1 })
        local detailLabel = dom:Create("TextLabel", { Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            Text = detail, Font = Enum.Font.Gotham, TextSize = 10, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2 })
        theme:BindToken(heading, "TextColor3", "TextMuted")
        theme:BindToken(valueLabel, "TextColor3", "Text")
        theme:BindToken(detailLabel, "TextColor3", "TextDim")
        return valueLabel
    end

    local readiness = createCard("SESSION", "Ready", "Your controls and profiles are available.", 0)
    local profile = createCard("CURRENT PROFILE", config:GetActiveProfile(), "Changes are saved with this workspace.", 1)
    local experience = createCard("EXPERIENCE", if plugins then plugins:GetActivePluginName() else "Universal Edition", if plugins then "Adapter selected for this place." else "Lite starts without game-specific adapters.", 2)

    local function refreshProfile()
        profile.Text = config:GetActiveProfile()
    end
    local function refreshExperience(name: string?)
        experience.Text = name or (if plugins then plugins:GetActivePluginName() else "Universal Edition")
    end
    scope:Add(bus:Subscribe("ProfilesChanged", refreshProfile))
    scope:Add(bus:Subscribe("ActiveProfileChanged", refreshProfile))
    scope:Add(bus:Subscribe("PluginChanged", refreshExperience))
    readiness.Text = "Ready"

    local pinned = section:Create(tab.LeftCol, "Pinned controls")
    section:Info(pinned, "Use ☆ beside a control to keep it at the top of its workspace. Pinned controls are saved with your configuration.")
    local workspace = section:Create(tab.LeftCol, "Workspace")
    section:Info(workspace, "Search is available from the menu bar at any time. Results stay in the current workspace so you can adjust settings without losing context.")
    section:Info(workspace, "Use the − button to minimize the menu. The × button asks before unloading the suite and restoring leased properties.")

    local changes = section:Create(tab.RightCol, "What changed in this revamp")
    local status = section:Info(changes, "Loading patch notes for this build…")

    -- Release notes stay in CHANGELOG.md. The Overview reads the same immutable revision as
    -- the running menu, so this panel never needs a duplicate, manually maintained summary.
    local function changelogUrl(): string?
        local ref = environment.Globals.B0XazRef
        if type(ref) ~= "string" or #ref ~= 40 or not ref:match("^[0-9a-fA-F]+$") then return nil end
        return `{CONFIG.CHANGELOG_REPOSITORY}{ref:lower()}/CHANGELOG.md`
    end

    local function trim(value: string): string
        return value:gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function readCurrentPatchNotes(markdown: string): { string }
        local _, sectionEnd = markdown:find("## Unreleased", 1, true)
        if not sectionEnd then return {} end
        local bodyStart = markdown:find("\n", sectionEnd, true)
        if not bodyStart then return {} end
        local nextHeading = markdown:find("\n## ", bodyStart + 1, true)
        local body = markdown:sub(bodyStart + 1, if nextHeading then nextHeading - 1 else #markdown)
        local notes = {}
        for line in body:gmatch("[^\r\n]+") do
            local note = line:match("^%s*%-%s+(.+)$")
            if note then
                note = trim(note:gsub("`", ""):gsub("%*%*", ""))
                if note ~= "" then table.insert(notes, note) end
            end
        end
        return notes
    end

    local function fetchPatchNotes(url: string): string?
        local response = environment:Request({ Url = url, Method = "GET" })
        if response and tonumber(response.StatusCode) == 200 and type(response.Body) == "string" then return response.Body end
        -- Some executors support game:HttpGet but not the generic request API. This fallback
        -- remains pinned to the validated immutable revision above.
        local ok, body = pcall(function() return game:HttpGet(url) end)
        return if ok and type(body) == "string" then body else nil
    end

    scope:Spawn(function()
        local url = changelogUrl()
        if not url then
            status:Set("Patch notes are unavailable because this build does not have an immutable revision.")
            return
        end
        local markdown = fetchPatchNotes(url)
        if scope:IsDisposed() then return end
        if type(markdown) ~= "string" or #markdown > CONFIG.MAX_CHANGELOG_BYTES then
            status:Set("Patch notes could not be loaded for this build.")
            return
        end
        local notes = readCurrentPatchNotes(markdown)
        if #notes == 0 then
            status:Set("No current patch notes were found for this build.")
            return
        end
        status:Set(`Current patch notes · {#notes} updates`)
        for _, note in ipairs(notes) do
            if scope:IsDisposed() then return end
            section:Info(changes, `•  {note}`)
        end
    end)

    return { Name = tab.Name }
end
