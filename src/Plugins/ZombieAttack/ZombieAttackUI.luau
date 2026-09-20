local CONFIG = table.freeze({
    REFRESH_INTERVAL = 0.5,
    FIRST_PAINT_DELAY = 0.1,
    LABEL_INDENT = "  ",
})

return function(services: any, Aura: any?): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)

    local StateStore, EventBus = services:Get("StateStore"), services:Get("EventBus")
    local ThemeEngine, DOM = services:Get("ThemeEngine"), services:Get("DOM")
    local TaskScheduler = services:Get("TaskScheduler")

    local Aura = Aura or {}
    local manifest = Aura.Manifest
    local auraConfig = manifest.Aura
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

        local auraSec = section:Create(tab.LeftCol, "Kill Aura")
        toggle(auraSec, "Enable kill aura", "Game.ZombieAura")
        slider(auraSec, "Fire rate", "Game.ZombieAuraRate", auraConfig.MinRate, auraConfig.MaxRate, auraConfig.RateStep, "s")
        dropdown:Create(auraSec, "Target part", "Game.ZombieAuraPart", table.clone(manifest.Aim.Parts))
        slider(auraSec, "Target range (0 = unlimited)", "Game.ZombieAuraRange", 0, auraConfig.MaxRange, auraConfig.RangeStep, " studs")
        labels.aura = createInfoLabel(auraSec, "Aura: off")
        section:Info(auraSec, `Fires the game's own {manifest.Gun.Remote[#manifest.Gun.Remote]} remote at the nearest live zombie on every tick, gated by the fire rate. The payload keeps the standalone script's shape: Normal, Direction, Name (your equipped tool), Hit, Origin, Pos.`)

        local farmSec = section:Create(tab.LeftCol, "Auto Farm")
        toggle(farmSec, "Auto farm", "Game.ZombieFarm")
        labels.farm = createInfoLabel(farmSec, "Farm: off")
        labels.farmStats = createInfoLabel(farmSec, "Targets: 0")
        textbox:CreateButton(farmSec, "Stop auto farm", function()
            StateStore:Set("Game.ZombieFarm", false)
            if Aura.AutoFarm then Aura.AutoFarm:Reset("user request") end
            return true, "Auto farm stopped"
        end)
        section:Info(farmSec, `Locks the nearest live zombie, holds you {manifest.Farm.UpOffset} studs above and {manifest.Farm.BackOffset} studs behind its facing, and drives the kill aura's own gun payload at it until it dies, then moves on to the next. Target part, range, and fire rate come from the kill aura section. While the farm runs it owns targeting, so the aura loop stands down; leave auto equip on or the shots go out with a knife in hand.`)

        local equipSec = section:Create(tab.RightCol, "Auto Equip")
        toggle(equipSec, "Auto equip gun", "Game.ZombieAutoEquip")
        labels.equip = createInfoLabel(equipSec, "Auto equip: off")
        textbox:CreateButton(equipSec, "Equip gun now", function()
            if Aura.AutoFarm then
                local farm = Aura.AutoFarm:GetStatus()
                setLabel(labels.farm, `Farm: {farm.State}`)
                setLabel(labels.farmStats, `Targets: {farm.Targets}  Last lock: {math.floor(farm.LockDistance)} studs  Placed: {farm.Placements}  Failed: {farm.Failures}`)
            end
            if Aura.AutoEquip then return Aura.AutoEquip:EquipNow() end
            return false, "Auto equip service is not loaded"
        end)
        section:Info(equipSec, `Equips the first Tool carrying a {manifest.Weapons.GunControllers[1]} child, searching your character and then your backpack, and leaves it alone while a gun is already in hand. Tools carrying {manifest.Weapons.KnifeControllers[1]} are counted but never equipped. Turning this on is what clears the kill aura's "No weapon equipped" miss.`)

        local statsSec = section:Create(tab.RightCol, "Statistics")
        labels.zombies = createInfoLabel(statsSec, "Live zombies: ...")
        labels.shots = createInfoLabel(statsSec, "Shots: ...")
        labels.target = createInfoLabel(statsSec, "Last target: ...")
        labels.weapon = createInfoLabel(statsSec, "Weapon / remote: ...")
        textbox:CreateButton(statsSec, "Fire once at nearest", function()
            if Aura.KillAura then return Aura.KillAura:FireOnce() end
            return false, "Kill aura service is not loaded"
        end)
        textbox:CreateButton(statsSec, "Stop kill aura", function()
            StateStore:Set("Game.ZombieAura", false)
            if Aura.KillAura then Aura.KillAura:Reset("user request") end
            return true, "Kill aura stopped"
        end)
        section:Info(statsSec, "Misses climb when the remote, a weapon, or the enemy container is missing, so a silent aura is diagnosable instead of invisible.")

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
        scope:Add(StateStore:Observe("Game.ZombieAura", function()
            forceRender = true
        end))
        scope:Add(StateStore:Observe("Game.ZombieAutoEquip", function()
            forceRender = true
        end))
        scope:Add(StateStore:Observe("Game.ZombieFarm", function()
            forceRender = true
        end))

        local function renderStatus()
            if Aura.Targets then
                local alive = Aura.Targets:CountAlive()
                local scanned = Aura.Targets:GetScanned()
                setLabel(labels.zombies, `Live zombies: {alive}  ({Aura.Targets:GetContainerName()}, {scanned} scanned)`)
            end
            if Aura.KillAura then
                local status = Aura.KillAura:GetStatus()
                setLabel(labels.aura, `Aura: {if status.Enabled then "active" else "off"}  Misses: {status.Misses}`)
                setLabel(labels.shots, `Shots fired: {status.Shots}`)
                setLabel(labels.target, `Last target: {status.Target}`)
                setLabel(labels.weapon, `Weapon / remote: {status.Weapon}  {status.Remote}`)
            end
            if Aura.AutoFarm then
                local farm = Aura.AutoFarm:GetStatus()
                setLabel(labels.farm, `Farm: {farm.State}`)
                setLabel(labels.farmStats, `Targets: {farm.Targets}  Last lock: {math.floor(farm.LockDistance)} studs  Placed: {farm.Placements}  Failed: {farm.Failures}`)
            end
            if Aura.AutoEquip then
                local equip = Aura.AutoEquip:GetStatus()
                setLabel(labels.equip, `Auto equip: {equip.State}  Guns: {equip.Guns}  Knives: {equip.Knives}  Swaps: {equip.Equips}  Failed: {equip.Failures}`)
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
