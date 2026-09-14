--!nonstrict
-- MVS DUELS Game tab: combat drivers on the left, the ESP overlay and live status on the
-- right. Status lines refresh on the same gated half-second job the other adapters use so
-- the AutomaticSize layout chain only pays while the tab is visible.
return function(services: any, Duel: any?): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)

    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local ThemeEngine, DOM = services:Get("ThemeEngine"), services:Get("DOM")
    local TaskScheduler = services:Get("TaskScheduler")

    local Duel = Duel or {}
    local manifest = Duel.Manifest
    local scope = services:Get("Disposer"):CreateChild(manifest.Name .. ".UI")

    local UI = {}

    -- Status lines use the compact code-face style from the design brief.
    local function createInfoLabel(parent: Instance, text: string): TextLabel
        return DOM:Create("TextLabel", {
            Text = "  " .. text,
            Font = Enum.Font.Code,
            TextSize = 11,
            TextColor3 = ThemeEngine:GetToken("TextDim"),
            TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -8, 0, 18),
            Parent = parent,
        }) :: TextLabel
    end

    -- Every TextLabel write cascades up through the AutomaticSize chain (label -> section
    -- -> column -> page canvas), so writes are change-detected: identical text is skipped.
    local function setLabel(label: TextLabel, text: string)
        if not label.Parent then return end
        local nextText = "  " .. text
        if label.Text ~= nextText then label.Text = nextText end
    end

    function UI:Build(tab: any)
        local labels = {}

        ------------------------------------------------------------------
        -- 1. Combat drivers (left)
        ------------------------------------------------------------------
        local combatSec = section:Create(tab.LeftCol, "Combat")
        toggle(combatSec, "Knife killer", "Game.MvSKnife")
        slider(combatSec, "Knife reengage delay", "Game.MvSKnifeCooldown", 0.15, 1.5, 0.05, "s")
        toggle(combatSec, "Fast aim revolver", "Game.MvSRevolver")
        slider(combatSec, "Revolver reengage delay", "Game.MvSGunCooldown", 0.5, 5, 0.05, "s")
        labels.combat = createInfoLabel(combatSec, "Drivers: ...")
        textbox:CreateButton(combatSec, "Stop combat drivers", function()
            StateStore:Set("Game.MvSKnife", false)
            StateStore:Set("Game.MvSRevolver", false)
            if Duel.Attack then Duel.Attack:Reset("user request") end
            return true, "Combat drivers stopped"
        end)
        section:Info(combatSec, "Each engage blinks behind the nearest enemy in your match, fires the game's own remote, and restores your position. Only players with the same Match attribute on the enemy team are targets.")

        ------------------------------------------------------------------
        -- 2. Player ESP (right)
        ------------------------------------------------------------------
        local espSec = section:Create(tab.RightCol, "Player ESP")
        toggle(espSec, "Enemy ESP", "Game.MvSEsp")
        labels.esp = createInfoLabel(espSec, "ESP: off")
        section:Info(espSec, "2D boxes, health bars, and names for match-scoped enemies, refreshed at ~30 fps with a hard cap of sixteen on-screen targets.")

        ------------------------------------------------------------------
        -- Low-rate refresh job, gated to run only while the menu is open and the Game tab
        -- is active: label writes cascade through the AutomaticSize layout chain.
        ------------------------------------------------------------------
        local REFRESH_INTERVAL = 0.5
        local menuVisible = StateStore:Get("Settings.MenuVisible") ~= false
        local gameTabActive = false
        local forceRender = false
        scope:Add(StateStore:Observe("Settings.MenuVisible", function(value: any)
            menuVisible = value == true
            if menuVisible then forceRender = true end
        end))
        scope:Add(EventBus:Subscribe("TabSelected", function(name: string)
            local active = name == "Game"
            if active and not gameTabActive then forceRender = true end
            gameTabActive = active
        end))

        local function renderStatus()
            if Duel.Esp then
                local counts = Duel.Esp:GetCounts()
                setLabel(labels.esp, "ESP: " .. (if counts.Enabled then (tostring(counts.Visible) .. "/" .. tostring(counts.Pool) .. " enemies on screen") else "off"))
            end
            if Duel.Attack then
                local status = Duel.Attack:GetStatus()
                setLabel(labels.combat, "Drivers: knife " .. status.Knife .. ", revolver " .. status.Gun
                    .. "  Enemies in match: " .. tostring(status.Enemies))
            end
        end

        local function paint()
            local ok, err = pcall(renderStatus)
            if not ok then warn("[B0Xaz][" .. manifest.Name .. ":UI] " .. tostring(err)) end
        end
        local accumulator = 0
        local job = TaskScheduler:RegisterHeartbeat("Game." .. manifest.Name:gsub("%s+", "") .. "UI", 45, function(dt: number)
            if not menuVisible or not gameTabActive then
                accumulator = 0
                return
            end
            if forceRender then
                accumulator = REFRESH_INTERVAL
            else
                accumulator += dt
            end
            if accumulator < REFRESH_INTERVAL then return end
            accumulator, forceRender = 0, false
            paint()
        end)
        scope:Add(job)
        scope:Spawn(function()
            task.wait(0.1)
            if not scope:IsDisposed() then paint() end
        end)
    end

    function UI:Destroy() scope:Dispose() end

    return UI
end
