local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CONFIG = table.freeze({
    TICK_INTERVAL = 0.25,
    SWAP_INTERVAL = 0.5,
    MAX_TOOLS = 64,
    CONTROLLER_SCAN_LIMIT = 160,
})

return function(services: any, Aura: any?): any
    local StateStore = services:Get("StateStore")
    local Disposer = services:Get("Disposer")
    local LocalPlayer = Players.LocalPlayer

    local Aura = Aura or {}
    local manifest = Aura.Manifest
    local weaponConfig = manifest.Weapons
    local scope = Disposer:CreateChild(`{manifest.Name}.AutoEquip`)

    local AutoEquip = {
        _lastTick = -math.huge,
        _lastSwap = -math.huge,
        _guns = 0,
        _knives = 0,
        _scanned = 0,
        _equips = 0,
        _failures = 0,
        _lastEquipped = "none",
        _state = "off",
    }

    -- Exact names resolve recursively without allocating; the bounded walk behind it
    -- only has to catch a controller whose casing differs
    local function hasController(tool: Instance, names: { string }): boolean
        for _, name in ipairs(names) do
            if tool:FindFirstChild(name, true) then return true end
        end
        local wanted = {}
        for _, name in ipairs(names) do wanted[name:lower()] = true end
        local queue, seen = { tool }, 0
        while #queue > 0 do
            local node = table.remove(queue, 1)
            for _, child in ipairs(node:GetChildren()) do
                seen += 1
                if seen > CONFIG.CONTROLLER_SCAN_LIMIT then return false end
                if wanted[child.Name:lower()] then return true end
                table.insert(queue, child)
            end
        end
        return false
    end

    -- Character before backpack, so a gun already in hand is never re-equipped over
    local function forEachTool(callback: (tool: Tool) -> ()): number
        local containers = {}
        local character = LocalPlayer.Character
        if character then table.insert(containers, character) end
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if backpack then table.insert(containers, backpack) end

        local scanned = 0
        for _, container in ipairs(containers) do
            for _, item in ipairs(container:GetChildren()) do
                if scanned >= CONFIG.MAX_TOOLS then return scanned end
                if item:IsA("Tool") then
                    scanned += 1
                    callback(item)
                end
            end
        end
        return scanned
    end

    local function scan(): { Tool }
        local guns: { Tool } = {}
        local knives = 0
        AutoEquip._scanned = forEachTool(function(tool: Tool)
            if hasController(tool, weaponConfig.GunControllers) then
                table.insert(guns, tool)
            elseif hasController(tool, weaponConfig.KnifeControllers) then
                knives += 1
            end
        end)
        AutoEquip._guns, AutoEquip._knives = #guns, knives
        return guns
    end

    local function equippedGun(guns: { Tool }, character: Instance): Tool?
        for _, tool in ipairs(guns) do
            if tool.Parent == character then return tool end
        end
        return nil
    end

    local function assets(): (Humanoid?, Instance?)
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not character or not humanoid then return nil, nil end
        return humanoid, character
    end

    local function attempt(humanoid: Humanoid, character: Instance, guns: { Tool }, now: number): (boolean, string)
        local held = equippedGun(guns, character)
        if held then return true, `Already holding {held.Name}` end
        if #guns == 0 then
            return false, `No tool with a {weaponConfig.GunControllers[1]} child ({AutoEquip._knives} knife tools skipped)`
        end

        -- Stamped on the attempt, so a server that refuses the swap is not asked again immediately
        AutoEquip._lastSwap = now
        local target = guns[1]
        local ok, err = pcall(function() humanoid:EquipTool(target) end)
        if not ok then
            AutoEquip._failures += 1
            return false, `Equip failed: {tostring(err)}`
        end
        AutoEquip._equips += 1
        AutoEquip._lastEquipped = target.Name
        return true, `Equipped {target.Name}`
    end

    local function tick(now: number)
        if StateStore:Get("Game.ZombieAutoEquip") ~= true then
            AutoEquip._state = "off"
            return
        end
        if now - AutoEquip._lastTick < CONFIG.TICK_INTERVAL then return end
        AutoEquip._lastTick = now

        local humanoid, character = assets()
        if not humanoid or not character or humanoid.Health <= 0 then
            AutoEquip._state = "no character"
            return
        end

        local guns = scan()
        local held = equippedGun(guns, character)
        if held then
            AutoEquip._state = `holding {held.Name}`
            return
        end
        -- Re-arming on an interval leaves a deliberate unequip alone for that long
        if now - AutoEquip._lastSwap < CONFIG.SWAP_INTERVAL then return end
        local _, message = attempt(humanoid, character, guns, now)
        AutoEquip._state = message
    end

    function AutoEquip:EquipNow(): (boolean, string)
        local humanoid, character = assets()
        if not humanoid or not character then return false, "Your character is not ready" end
        if humanoid.Health <= 0 then return false, "You are dead" end

        local now = os.clock()
        AutoEquip._lastTick = now
        local ok, message = attempt(humanoid, character, scan(), now)
        AutoEquip._state = message
        return ok, message
    end

    function AutoEquip:GetGunTools(): { Tool }
        return scan()
    end

    function AutoEquip:GetStatus(): any
        return {
            Enabled = StateStore:Get("Game.ZombieAutoEquip") == true,
            State = self._state,
            Guns = self._guns,
            Knives = self._knives,
            Scanned = self._scanned,
            Equips = self._equips,
            Failures = self._failures,
            Equipped = self._lastEquipped,
        }
    end

    function AutoEquip:Reset(_reason: string?)
        self._lastTick, self._lastSwap = -math.huge, -math.huge
        self._state = if StateStore:Get("Game.ZombieAutoEquip") == true then "idle" else "off"
    end

    function AutoEquip:Initialize()
        scope:Add(RunService.Heartbeat:Connect(function()
            pcall(tick, os.clock())
        end))
        scope:Add(LocalPlayer.CharacterAdded:Connect(function()
            self:Reset("respawn")
        end))
        self:Reset("initialize")
    end

    function AutoEquip:Destroy()
        scope:Dispose()
    end

    return AutoEquip
end
