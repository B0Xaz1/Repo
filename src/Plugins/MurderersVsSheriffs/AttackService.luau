--!nonstrict
-- MVS DUELS combat drivers: the knife killer and fast aim revolver ported from the
-- reference thread. Each driver teleports behind the nearest eligible enemy, waits a
-- heartbeat, fires its remote with the reference argument layout, then restores the
-- original CFrame. Per-target re-engage clocks are adjustable from the Game tab.
return function(services: any, Duel: any?): any
    local StateStore = services:Get("StateStore")
    local Disposer = services:Get("Disposer")
    local Environment = services:Get("Environment")
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local CollectionService = game:GetService("CollectionService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = Players.LocalPlayer

    local Duel = Duel or {}
    local manifest = Duel.Manifest
    local knifeConfig, gunConfig = manifest.Knife, manifest.Gun
    local scope = Disposer:CreateChild(manifest.Name .. ".Attack")

    local Attack = {
        _knifeRemote = nil, _gunRemote = nil,
        _knifeBusy = false, _gunBusy = false,
        _knifeLast = {}, _gunLast = {}, _gunNextShot = 0,
        _enemies = 0,
        _lastEquipSwap = 0,
        _equipSlot = 1,
        _lastSpamShot = 0,
        _lastSpamThrow = 0,
    }

    local function resolveRemote(path: { string }): any
        local node: any = ReplicatedStorage
        for _, name in ipairs(path) do
            node = node and node:FindFirstChild(name)
        end
        return node
    end

    -- Tool detection mirrors the reference checks: CollectionService tag first, then the
    -- animation attribute substrings as a heuristic fallback.
    local function toolMatches(tool: Instance, tag: string, field: string, needle: string): boolean
        local tagged = false
        pcall(function() tagged = CollectionService:HasTag(tool, tag) end)
        if tagged then return true end
        return string.find(tostring(tool:GetAttribute(field) or ""), needle, 1, true) ~= nil
    end

    local function iterateTools(callback: (tool: Instance) -> boolean): any
        local character = LocalPlayer.Character
        if not character then return nil end
        for _, tool in ipairs(character:GetChildren()) do
            if tool:IsA("Tool") and callback(tool) then return tool end
        end
        return nil
    end

    local function getKnife(): Tool?
        return iterateTools(function(tool: Instance)
            return toolMatches(tool, knifeConfig.Tag, knifeConfig.ActivatedField, knifeConfig.ActivatedNeedle)
                or string.find(tostring(tool:GetAttribute(knifeConfig.PulloutField) or ""), knifeConfig.PulloutNeedle, 1, true) ~= nil
        end)
    end
    local function hasKnife(): boolean
        return getKnife() ~= nil
    end
    local function getGun(): Tool?
        return iterateTools(function(tool: Instance)
            return toolMatches(tool, gunConfig.Tag, gunConfig.ActivatedField, gunConfig.ActivatedNeedle)
        end)
    end

    -- Engage pattern: blink behind the target along its look vector, simulate the click,
    -- fire, restore. The pcall keeps any remote failure contained, and the CFrame restore
    -- is raw (no tween).
    local function knifeHit(target: any)
        Attack._knifeBusy = true
        local mine = LocalPlayer.Character
        local myRoot = mine and mine:FindFirstChild("HumanoidRootPart")
        if myRoot and Attack._knifeRemote then
            local original = myRoot.CFrame
            pcall(function()
                myRoot.CFrame = CFrame.lookAt(target.Root.Position - target.Root.CFrame.LookVector * knifeConfig.BackOffset + Vector3.new(0, knifeConfig.UpOffset, 0), target.Root.Position)
                -- Simulated click: Tool:Activate() raises the knife's Activated signal the
                -- same way a real click does, but the player's actual mouse is untouched
                -- (no VirtualInputManager, no focus steal, no cursor side effects).
                if knifeConfig.SimulateClick then
                    local knife = getKnife()
                    if knife then pcall(function() knife:Activate() end) end
                end
                RunService.Heartbeat:Wait()
                Attack._knifeRemote:FireServer(target.Part)
                task.wait(knifeConfig.Settle)
            end)
            if myRoot.Parent then myRoot.CFrame = original end
        end
        Attack._knifeBusy = false
    end

    local function gunHit(target: any)
        Attack._gunBusy = true
        local mine = LocalPlayer.Character
        local myRoot = mine and mine:FindFirstChild("HumanoidRootPart")
        if myRoot and Attack._gunRemote then
            local original = myRoot.CFrame
            pcall(function()
                myRoot.CFrame = CFrame.lookAt(target.Root.Position - target.Root.CFrame.LookVector * gunConfig.BackOffset + Vector3.new(0, gunConfig.UpOffset, 0), target.Root.Position)
                RunService.Heartbeat:Wait()
                local head = mine:FindFirstChild("Head")
                local origin = if head then (head.CFrame * CFrame.new(0, head.Size.Y / 2, head.Size.Z / 2)).Position else myRoot.Position
                local hitPosition = target.Part.Position
                Attack._gunRemote:FireServer(origin, hitPosition, target.Part, hitPosition)
                task.wait(gunConfig.Settle)
            end)
            if myRoot.Parent then myRoot.CFrame = original end
        end
        Attack._gunBusy = false
    end

    local function currentCooldown(path: string, fallback: number, minimum: number): number
        local value = tonumber(StateStore:Get(path))
        if not value then return fallback end
        return math.max(value, minimum)
    end

    -- Equips the matching tool (KnifeTool or GunTool) based on which combat toggle is enabled.
    -- If both are enabled, it prioritizes keeping an active weapon equipped, or whichever is unequipped.
    local function processAutoEquip(now: number)
        if StateStore:Get("Game.MvSAutoEquip") ~= true then return end
        if now - Attack._lastEquipSwap < 0.15 then return end

        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if not char or not hum or not backpack then return end

        local useKnife = StateStore:Get("Game.MvSKnife") == true or StateStore:Get("Game.MvSKnifeSpamThrow") == true
        local useGun = StateStore:Get("Game.MvSRevolver") == true or StateStore:Get("Game.MvSGunSpamShoot") == true

        local function isToolEquipped(tool: Tool?): boolean
            return tool ~= nil and tool.Parent == char
        end

        local function findToolInContainers(tag: string, animField: string, needle: string): Tool?
            for _, item in ipairs(char:GetChildren()) do
                if item:IsA("Tool") and (toolMatches(item, tag, animField, needle)) then
                    return item
                end
            end
            for _, item in ipairs(backpack:GetChildren()) do
                if item:IsA("Tool") and (toolMatches(item, tag, animField, needle)) then
                    return item
                end
            end
            return nil
        end

        local knifeTool = findToolInContainers(knifeConfig.Tag, knifeConfig.ActivatedField, knifeConfig.ActivatedNeedle)
        local gunTool = findToolInContainers(gunConfig.Tag, gunConfig.ActivatedField, gunConfig.ActivatedNeedle)

        -- If both Knife and Revolver are active:
        if useKnife and useGun then
            -- If either tool is already equipped and held, do not oscillate back and forth
            if isToolEquipped(knifeTool) or isToolEquipped(gunTool) then
                return
            end
            -- If neither is currently equipped in hand, equip Gun if available, else Knife
            local target = gunTool or knifeTool
            if target and target.Parent ~= char then
                Attack._lastEquipSwap = now
                pcall(function() hum:EquipTool(target) end)
            end
            return
        end

        -- If only Knife is active
        if useKnife then
            if knifeTool and knifeTool.Parent ~= char then
                Attack._lastEquipSwap = now
                pcall(function() hum:EquipTool(knifeTool) end)
            end
            return
        end

        -- If only Gun is active
        if useGun then
            if gunTool and gunTool.Parent ~= char then
                Attack._lastEquipSwap = now
                pcall(function() hum:EquipTool(gunTool) end)
            end
            return
        end

        -- Fallback if user just toggled Auto Equip with neither specific combat toggle on
        if not isToolEquipped(knifeTool) and not isToolEquipped(gunTool) then
            local target = knifeTool or gunTool
            if target and target.Parent ~= char then
                Attack._lastEquipSwap = now
                pcall(function() hum:EquipTool(target) end)
            end
        end
    end

    -- Updates the Knife's "ThrowSpeed" attribute according to Game.MvSKnifeThrowSpeed setting
    local function syncKnifeThrowSpeed(knife: Tool?)
        if not knife then return end
        local targetVal = tonumber(StateStore:Get("Game.MvSKnifeThrowSpeed"))
        if targetVal and targetVal > 0 then
            pcall(function()
                if knife:GetAttribute("ThrowSpeed") ~= targetVal then
                    knife:SetAttribute("ThrowSpeed", targetVal)
                end
            end)
        end
    end

    -- Updates the Gun's "Cooldown" attribute according to Game.MvSGunAttributeCooldown setting
    local function syncGunAttributeCooldown(gun: Tool?)
        if not gun then return end
        local targetVal = tonumber(StateStore:Get("Game.MvSGunAttributeCooldown"))
        if targetVal and targetVal >= 0 then
            pcall(function()
                if gun:GetAttribute(gunConfig.CooldownAttribute) ~= targetVal then
                    gun:SetAttribute(gunConfig.CooldownAttribute, targetVal)
                end
            end)
        end
    end

    -- Gun spam shoot: left mouse rapid click at the gun's configured cooldown
    local function processGunSpamShoot(now: number, gun: Tool?)
        if StateStore:Get("Game.MvSGunSpamShoot") ~= true then return end
        if not gun or gun.Parent ~= LocalPlayer.Character then return end

        local customCd = tonumber(StateStore:Get("Game.MvSGunAttributeCooldown")) or 0
        local gunAttrCd = tonumber(gun:GetAttribute(gunConfig.CooldownAttribute)) or gunConfig.DefaultCooldown
        local shotInterval = math.max(0.03, math.min(customCd > 0 and customCd or gunAttrCd, currentCooldown("Game.MvSGunCooldown", gunConfig.DefaultCooldown, gunConfig.MinCooldown)))

        if now - Attack._lastSpamShot < shotInterval then return end
        Attack._lastSpamShot = now

        pcall(function()
            gun:Activate()
        end)
        if Environment then
            Environment:MouseClick()
        end
    end

    -- Knife spam throw: spams "E" key to throw knife repeatedly
    local function processKnifeSpamThrow(now: number, knife: Tool?)
        if StateStore:Get("Game.MvSKnifeSpamThrow") ~= true then return end
        if not knife or knife.Parent ~= LocalPlayer.Character then return end

        if now - Attack._lastSpamThrow < 0.05 then return end
        Attack._lastSpamThrow = now

        pcall(function()
            local vim = game:GetService("VirtualInputManager")
            if vim then
                vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.delay(0.02, function()
                    pcall(function()
                        vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                    end)
                end)
            end
        end)
    end

    local function tick(now: number)
        processAutoEquip(now)

        local knife = getKnife()
        if knife then
            syncKnifeThrowSpeed(knife)
            processKnifeSpamThrow(now, knife)
        end

        local gun = getGun()
        if gun then
            syncGunAttributeCooldown(gun)
            processGunSpamShoot(now, gun)
        end

        local targets = Duel.Targets:GetAttackList()
        Attack._enemies = #targets
        if #targets == 0 then return end

        if StateStore:Get("Game.MvSKnife") == true and not Attack._knifeBusy and Attack._knifeRemote and knife then
            local cooldown = currentCooldown("Game.MvSKnifeCooldown", knifeConfig.DefaultCooldown, knifeConfig.MinCooldown)
            for _, target in ipairs(targets) do
                if not Attack._knifeLast[target.Character] or now - Attack._knifeLast[target.Character] > cooldown then
                    Attack._knifeLast[target.Character] = now
                    task.spawn(knifeHit, target)
                    break
                end
            end
        end

        if StateStore:Get("Game.MvSRevolver") == true and not Attack._gunBusy and Attack._gunRemote and gun and now >= Attack._gunNextShot then
            local cooldown = currentCooldown("Game.MvSGunCooldown", gunConfig.DefaultCooldown, gunConfig.MinCooldown)
            for _, target in ipairs(targets) do
                if not Attack._gunLast[target.Character] or now - Attack._gunLast[target.Character] > cooldown then
                    Attack._gunLast[target.Character] = now
                    -- The tool's own cooldown caps the global re-fire gate, never below the floor.
                    Attack._gunNextShot = now + math.max(tonumber(gun:GetAttribute(gunConfig.CooldownAttribute)) or gunConfig.DefaultCooldown, gunConfig.MinCooldown)
                    task.spawn(gunHit, target)
                    break
                end
            end
        end
    end

    function Attack:Reset(reason: string?)
        self._knifeLast, self._gunLast, self._gunNextShot = {}, {}, 0
    end

    function Attack:Initialize()
        self._knifeRemote = resolveRemote(knifeConfig.Remote)
        self._gunRemote = resolveRemote(gunConfig.Remote)
        if not self._knifeRemote or not self._gunRemote then
            warn("[B0Xaz][" .. manifest.Name .. ":Attack] Remotes not found at ReplicatedStorage."
                .. table.concat(gunConfig.Remote, ".") .. "; drivers will idle until re-init")
        end
        scope:Add(RunService.Heartbeat:Connect(function()
            local ok, err = pcall(tick, os.clock())
            if not ok then warn("[B0Xaz][" .. manifest.Name .. ":Attack] " .. tostring(err)) end
        end))
        -- A fresh character clears in-flight state so no blink/restore straddles a respawn.
        scope:Add(LocalPlayer.CharacterAdded:Connect(function()
            self._knifeBusy, self._gunBusy = false, false
            self:Reset("respawn")
        end))
    end

    function Attack:GetStatus(): any
        return {
            Enemies = self._enemies,
            Knife = if StateStore:Get("Game.MvSKnife") == true then (if hasKnife() then "armed" else "no knife") else "off",
            Gun = if StateStore:Get("Game.MvSRevolver") == true then (if getGun() then "armed" else "no revolver") else "off",
        }
    end

    function Attack:Destroy() scope:Dispose() end

    return Attack
end
