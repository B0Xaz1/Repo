local UIS = game:GetService("UserInputService")

return function(services: any): any
    local state = services:Get("StateStore")
    local environment = services:Get("Environment")
    local scheduler = services:Get("TaskScheduler")
    local scope = services:Get("Disposer"):CreateChild("MouseLockService")
    local changes = scope:CreateChild("Gameplay mouse lock")
    local MouseLockService = { _locked = false, _initialized = false }

    local function release()
        if not MouseLockService._locked then return end
        MouseLockService._locked = false
        -- Restore the prior owner (for example Roblox camera controls or Freecam),
        -- rather than assigning Default and clobbering another feature's mouse mode.
        changes:RestoreProperties()
    end

    local function canLock(): boolean
        return state:Peek("Movement.MouseLockEnabled") == true
            and state:Peek("Settings.MenuVisible") ~= true
            and state:GetTransient("IsBindingKey") ~= true
            and not environment:IsMobile()
            and environment:CanLockPointer()
    end

    local function update()
        if not canLock() then
            release()
            return
        end
        if not MouseLockService._locked then MouseLockService._locked = true end
        -- Dynamic keeps this owner at the top only while gameplay remains safe. The
        -- cursor is constrained by Roblox to the viewport center; no OS mouse API is used.
        changes:SetProperty(UIS, "MouseBehavior", Enum.MouseBehavior.LockCenter, true)
    end

    function MouseLockService:IsLocked(): boolean
        return self._locked
    end

    function MouseLockService:Initialize()
        if self._initialized then return end
        self._initialized = true
        local job = scheduler:RegisterRender("Movement.MouseLock", 4, update)
        local function sync(enabled: boolean)
            job.Enabled = enabled == true
            if not enabled then release() else update() end
        end
        scope:Add(state:Observe("Movement.MouseLockEnabled", sync))
        scope:Add(state:Observe("Settings.MenuVisible", function()
            if job.Enabled then update() end
        end))
        -- This signal covers Alt-Tab and opening the Windows Start menu immediately,
        -- before the next RenderStepped update has a chance to run.
        scope:ConnectImmediate(UIS.WindowFocusReleased, release)
        scope:ConnectImmediate(UIS.TextBoxFocused, release)
        sync(state:Peek("Movement.MouseLockEnabled") == true)
        scope:Add(release)
    end

    function MouseLockService:Destroy()
        release()
        scope:Dispose()
    end

    return MouseLockService
end
