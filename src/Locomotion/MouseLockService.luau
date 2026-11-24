local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

return function(services: any): any
    local state = services:Get("StateStore")
    local environment = services:Get("Environment")
    local scheduler = services:Get("TaskScheduler")
    local bus = services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("MouseLockService")
    local changes = scope:CreateChild("Gameplay mouse lock")
    local MouseLockService = { _locked = false, _applying = false, _initialized = false }

    local function isRobloxMenuOpen(): boolean
        local ok, open = pcall(function() return GuiService.MenuIsOpen end)
        return ok and open == true
    end

    local function release()
        if not MouseLockService._locked then return end
        MouseLockService._locked = false
        -- Restore the prior owner (for example Roblox camera controls or Freecam),
        -- rather than assigning Default and clobbering another feature's mouse mode.
        MouseLockService._applying = true
        changes:RestoreProperties()
        MouseLockService._applying = false
    end

    local function canLock(): boolean
        local focusedTextBox = false
        pcall(function() focusedTextBox = UIS:GetFocusedTextBox() ~= nil end)
        return state:Peek("Movement.MouseLockEnabled") == true
            and state:Peek("Movement.FreecamEnabled") ~= true
            and state:Peek("Settings.MenuVisible") ~= true
            and state:GetTransient("IsBindingKey") ~= true
            and not focusedTextBox
            and not isRobloxMenuOpen()
            and not environment:IsMobile()
            and environment:CanLockPointer()
    end

    local function update()
        if not canLock() then
            release()
            return
        end
        if MouseLockService._locked then
            local ok, behavior = pcall(function() return UIS.MouseBehavior end)
            if ok and behavior == Enum.MouseBehavior.LockCenter then return end
        end
        MouseLockService._locked = true
        -- Dynamic keeps this owner at the top only while gameplay remains safe. The
        -- cursor is constrained by Roblox to the viewport center; no OS mouse API is used.
        MouseLockService._applying = true
        changes:SetProperty(UIS, "MouseBehavior", Enum.MouseBehavior.LockCenter, true)
        MouseLockService._applying = false
    end

    function MouseLockService:IsLocked(): boolean
        return self._locked
    end

    function MouseLockService:Initialize()
        if self._initialized then return end
        self._initialized = true
        -- Enforce across every engine phase (Render, Camera/after PlayerModule, PreSim, Heartbeat)
        -- plus an immediate MouseBehavior property watcher so camera scripts, gun recoil, tool
        -- equips, or click events cannot leave the pointer unlocked between frames.
        local jobs = {
            scheduler:RegisterRender("Movement.MouseLock", 4, update),
            scheduler:RegisterCamera("Movement.MouseLock", 4, update),
            scheduler:RegisterPreSim("Movement.MouseLock", 4, update),
            scheduler:RegisterHeartbeat("Movement.MouseLock", 4, update),
        }
        local active = false
        local function sync(enabled: boolean)
            active = enabled == true
            for _, job in ipairs(jobs) do job.Enabled = active end
            if not active then release() else update() end
        end
        local function refreshIfActive()
            if active then update() end
        end
        scope:Add(state:Observe("Movement.MouseLockEnabled", sync))
        scope:Add(state:Observe("Movement.FreecamEnabled", refreshIfActive))
        scope:Add(state:Observe("Settings.MenuVisible", refreshIfActive))
        scope:Add(bus:Subscribe("TransientChanged:IsBindingKey", refreshIfActive))
        -- Reassert immediately when another controller overwrites MouseBehavior mid-frame.
        pcall(function()
            scope:ConnectImmediate(UIS:GetPropertyChangedSignal("MouseBehavior"), function()
                if MouseLockService._applying or not active then return end
                local ok, behavior = pcall(function() return UIS.MouseBehavior end)
                if not ok or behavior ~= Enum.MouseBehavior.LockCenter then update() end
            end)
        end)
        -- These signals cover Alt-Tab, chat/text focus, and the Roblox Escape menu immediately,
        -- before the next frame pipeline step has a chance to run.
        scope:ConnectImmediate(UIS.WindowFocusReleased, release)
        scope:ConnectImmediate(UIS.WindowFocused, refreshIfActive)
        scope:ConnectImmediate(UIS.TextBoxFocused, release)
        scope:ConnectImmediate(UIS.TextBoxFocusReleased, refreshIfActive)
        pcall(function()
            scope:ConnectImmediate(GuiService.MenuOpened, release)
            scope:ConnectImmediate(GuiService.MenuClosed, refreshIfActive)
        end)
        sync(state:Peek("Movement.MouseLockEnabled") == true)
        scope:Add(release)
    end

    function MouseLockService:Destroy()
        release()
        scope:Dispose()
    end

    return MouseLockService
end
