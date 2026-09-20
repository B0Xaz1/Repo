local CONFIG = table.freeze({
    REFRESH_INTERVAL = 0.5,
    FIRST_PAINT_DELAY = 0.1,
    LABEL_INDENT = "  ",
})

return function(services: any, Duel: any?): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)

    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local ThemeEngine, DOM = services:Get("ThemeEngine"), services:Get("DOM")
    local TaskScheduler = services:Get("TaskScheduler")

    local Duel = Duel or {}
    local manifest = Duel.Manifest
    local scope = services:Get("Disposer"):CreateChild(`{manifest.Name}.UI`)

    local UI = {}

    local function createInfoLabel(parent: Instance, text: string): TextLabel
        return DOM:Create("TextLabel", {
            Text = CONFIG.LABEL_INDENT .. text,
            Font = Enum.Font.Code,
            TextSize = 11,
            TextColor3 = ThemeEngine:GetToken("TextDim"),
            TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -8, 0, 18),
            Parent = parent,
        }) :: TextLabel
    end

    local function setLabel(label: TextLabel, text: string)
        if not label.Parent then return end
        local nextText = CONFIG.LABEL_INDENT .. text
        if label.Text ~= nextText then label.Text = nextText end
    end

    function UI:Build(tab: any)
        local labels = {}

        local combatSec = section:Create(tab.LeftCol, "Combat")
        toggle(combatSec, "Knife killer", "Game.MvSKnife")
        slider(combatSec, "Knife reengage delay", "Game.MvSKnifeCooldown", 0.15, 1.5, 0.05, "s")
        slider(combatSec, "Knife ThrowSpeed attribute", "Game.MvSKnifeThrowSpeed", 0, 1000, 25, "")
        toggle(combatSec, "Knife spam throw (E)", "Game.MvSKnifeSpamThrow")
        toggle(combatSec, "Fast aim revolver", "Game.MvSRevolver")
        slider(combatSec, "Revolver reengage delay", "Game.MvSGunCooldown", 0.5, 5, 0.05, "s")
        slider(combatSec, "Gun Cooldown attribute", "Game.MvSGunAttributeCooldown", 0.0, 3.0, 0.05, "s")
        toggle(combatSec, "Gun spam shoot (auto-click)", "Game.MvSGunSpamShoot")
        toggle(combatSec, "Auto equip active weapon", "Game.MvSAutoEquip")
        labels.combat = createInfoLabel(combatSec, "Drivers: ...")
        textbox:CreateButton(combatSec, "Stop combat drivers", function()
            StateStore:Set("Game.MvSKnife", false)
            StateStore:Set("Game.MvSRevolver", false)
            StateStore:Set("Game.MvSKnifeSpamThrow", false)
            StateStore:Set("Game.MvSGunSpamShoot", false)
            if Duel.Attack then Duel.Attack:Reset("user request") end
            return true, "Combat drivers stopped"
        end)
        section:Info(combatSec, "Each engage blinks behind the nearest enemy in your match, simulates a client-side tool click (your real mouse is untouched), fires the game's own remote, and restores your position. 'Auto equip active weapon' equips the matching tool (if both are active, it prioritizes the unequipped one or Knife). 'Gun spam shoot' auto-clicks at your configured gun cooldown, and 'Knife spam throw' spams E to throw knives.")

        local espSec = section:Create(tab.RightCol, "Player ESP")
        toggle(espSec, "Enemy ESP", "Game.MvSEsp")
        labels.esp = createInfoLabel(espSec, "ESP: off")
        section:Info(espSec, "2D boxes, health bars, and names for match-scoped enemies, refreshed at ~30 fps with a hard cap of sixteen on-screen targets.")

        local queueModes = (manifest.Queue and manifest.Queue.Modes) or { "1v1", "2v2", "3v3", "4v4" }
        local queueSec = section:Create(tab.RightCol, "Auto Queue")
        toggle(queueSec, "Auto queue", "Game.MvSAutoQueue")
        dropdown:Create(queueSec, "Queue mode", "Game.MvSQueueMode", queueModes)
        slider(queueSec, "Queue retry delay", "Game.MvSQueueDelay", 1.0, 10.0, 0.5, "s")
        labels.queue = createInfoLabel(queueSec, "AutoQueue: off")
        textbox:CreateButton(queueSec, "Queue now", function()
            if Duel.AutoQueue then
                local success, msg = Duel.AutoQueue:TriggerQueue()
                return success, msg
            end
            return false, "AutoQueue not loaded"
        end)
        section:Info(queueSec, "Automates queue entry and re-queuing between matches. Automatically pauses while you are in an active duel and queues back up upon returning to the lobby.")

        local menuVisible = StateStore:Get("Settings.MenuVisible") ~= false
        local gameTabActive = true
        local forceRender = true
        scope:Add(StateStore:Observe("Settings.MenuVisible", function(value: any)
            menuVisible = value == true
            if menuVisible then forceRender = true end
        end))
        scope:Add(EventBus:Subscribe("TabSelected", function(name: string)
            local active = name == "Game"
            if active and not gameTabActive then forceRender = true end
            gameTabActive = active
        end))

        scope:Add(StateStore:Observe("Game.MvSAutoQueue", function()
            forceRender = true
        end))
        scope:Add(StateStore:Observe("Game.MvSQueueMode", function()
            forceRender = true
        end))

        local function renderStatus()
            if Duel.Esp then
                local counts = Duel.Esp:GetCounts()
                setLabel(labels.esp, `ESP: {if counts.Enabled then `{counts.Visible}/{counts.Pool} enemies on screen` else "off"}`)
            end
            if Duel.Attack then
                local status = Duel.Attack:GetStatus()
                setLabel(labels.combat, `Drivers: knife {status.Knife}, revolver {status.Gun}  Enemies in match: {status.Enemies}`)
            end
            if Duel.AutoQueue then
                local qStatus = Duel.AutoQueue:GetStatus()
                local autoLabel = if qStatus.Enabled then qStatus.State else "Off"
                setLabel(labels.queue, `AutoQueue: {autoLabel} ({qStatus.Mode}) - {qStatus.Message}`)
            end
        end

        local function paint()
            pcall(renderStatus)
        end
        local accumulator = 0
        local job = TaskScheduler:RegisterHeartbeat(`Game.{(manifest.Name:gsub("%s+", ""))}UI`, 45, function(dt: number)
            if not menuVisible or not gameTabActive then
                accumulator = 0
                return
            end
            if forceRender then
                accumulator = CONFIG.REFRESH_INTERVAL
            else
                accumulator += dt
            end
            if accumulator < CONFIG.REFRESH_INTERVAL then return end
            accumulator, forceRender = 0, false
            paint()
        end)
        scope:Add(job)
        scope:Spawn(function()
            task.wait(CONFIG.FIRST_PAINT_DELAY)
            if not scope:IsDisposed() then paint() end
        end)
    end

    function UI:Destroy() scope:Dispose() end

    return UI
end
