return function(services: any, tab: any): any
    local dom, theme, bus = services:Get("DOM"), services:Get("ThemeEngine"), services:Get("EventBus")
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local config = services:Get("ConfigService")
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

    local changes = section:Create(tab.RightCol, "What changed in this revamp")
    section:Info(changes, "Command Deck now uses a structured command bar, navigation workspace, and an Overview landing page.")
    section:Info(changes, "Midnight is monochrome, the main deck has visible rounded surfaces, and the old floating ESP preview was removed.")
    section:Info(changes, "Touch devices use a horizontal workspace picker and a larger floating menu control. Desktop users can press Ctrl/Cmd + K to focus search.")
    section:Info(changes, "Profile changes now defer expensive interface reflow until settings finish applying, so saved UI scale changes stay responsive.")

    local workspace = section:Create(tab.RightCol, "Workspace")
    section:Info(workspace, "Search is available from the command bar at any time. Results stay in the current workspace so you can adjust settings without losing context.")
    section:Info(workspace, "Use the − button to minimize the deck. The × button unloads the suite and restores leased properties.")

    return { Name = tab.Name }
end
