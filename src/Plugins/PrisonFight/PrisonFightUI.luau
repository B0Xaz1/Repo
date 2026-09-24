local CONFIG = table.freeze({
    REFRESH_INTERVAL = 0.5,
    FIRST_PAINT_DELAY = 0.1,
    LABEL_INDENT = "  ",
})

return function(services: any, Prison: any?): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)
    local keybind = load("src/UI/Components/Keybind.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)

    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local ThemeEngine, DOM = services:Get("ThemeEngine"), services:Get("DOM")
    local TaskScheduler = services:Get("TaskScheduler")

    local Prison = Prison or {}
    local manifest = Prison.Manifest
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

        local doorsSec = section:Create(tab.LeftCol, "Doors and Obstacles")
        toggle(doorsSec, "Phase doors & fences", "Game.DoorPhase")
        slider(doorsSec, "Phase transparency", "Game.PhaseTransparency", 0.1, 0.95, 0.05)
        labels.doors = createInfoLabel(doorsSec, "Doors: ...")
        textbox:CreateButton(doorsSec, "Scan doors", function()
            if Prison.WorldPhase then
                Prison.WorldPhase:ScanDoors()
                Prison.WorldPhase:ApplyAll()
                return true, "Door scan complete"
            end
            return false, "World phase unavailable"
        end)
        textbox:CreateButton(doorsSec, "Restore door originals", function()
            StateStore:Set("Game.DoorPhase", false)
            if Prison.WorldPhase then Prison.WorldPhase:RestoreAll() end
            return true, "Door properties restored"
        end)

        local macroSec = section:Create(tab.RightCol, "Weapon Macro")
        toggle(macroSec, "Weapon switch macro", "Game.FakeMacro")
        keybind(macroSec, "Macro key", "Game.FakeMacroKey")
        dropdown(macroSec, "Macro mode", "Game.FakeMacroMode", { "Toggle", "Hold" })
        slider(macroSec, "Switch delay", "Game.FakeMacroDelay", 0.03, 0.5, 0.01, "s")
        labels.macro = createInfoLabel(macroSec, "Macro: Idle")
        textbox:CreateButton(macroSec, "Stop macro", function()
            if Prison.Macro then Prison.Macro:Stop("user request") return true, "Macro stopped" end
            return false, "Macro unavailable"
        end)

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
            if Prison.WorldPhase then
                local counts = Prison.WorldPhase:GetCounts()
                setLabel(labels.doors, `Doors: {counts.Containers} containers, {counts.Parts} parts  Phased: {counts.Phased}{if #counts.Folders > 0 then `  [{table.concat(counts.Folders, ", ")}]` else "  [heuristic scan]"}`)
            end
            if Prison.Macro then
                local status = Prison.Macro:GetStatus()
                setLabel(labels.macro, `Macro: {status.State:upper()}  Next: {status.NextTool}  Delay: {string.format("%d", status.Delay * 1000)}ms  Cycles: {status.Cycles}{if status.StopReason then `  Reason: {status.StopReason}` else "  Reason: -"}`)
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
