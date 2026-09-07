--!nonstrict
return function(services: any): any
    local environment = services:Get("Environment")
    local scope = services:Get("Disposer"):CreateChild("DrawingPool")
    local drawing = environment.Drawing
    local DrawingPool = { Available = false, _all = {}, _inUse = {}, _free = { Line = {}, Text = {}, Square = {}, Circle = {} } }
    if environment.Capabilities.Drawing then
        local probe = nil
        local ok = pcall(function() probe = drawing.new("Line"); probe.Visible = false; probe:Remove() end)
        if not ok and probe then pcall(function() probe.Visible = false; probe:Remove() end) end
        DrawingPool.Available = ok
    end
    local function reset(primitive: any, kind: string)
        local defaults: any = { Visible = false, Color = Color3.new(1, 1, 1), Transparency = 1, ZIndex = 2 }
        if kind == "Line" then defaults.From, defaults.To, defaults.Thickness = Vector2.zero, Vector2.zero, 1
        elseif kind == "Text" then defaults.Text, defaults.Size, defaults.Center, defaults.Outline, defaults.Font = "", 13, true, true, 2
        elseif kind == "Square" then defaults.Position, defaults.Size, defaults.Filled, defaults.Thickness = Vector2.zero, Vector2.zero, false, 1
        elseif kind == "Circle" then defaults.Position, defaults.Radius, defaults.Filled, defaults.NumSides, defaults.Thickness = Vector2.zero, 1, false, 64, 1 end
        for property, value in pairs(defaults) do pcall(function() primitive[property] = value end) end
    end
    function DrawingPool:Acquire(kind: string): any?
        if not self.Available or scope:IsDisposed() then return nil end
        local free = self._free[kind]
        assert(free, "Unsupported Drawing kind '" .. kind .. "'")
        local primitive = table.remove(free)
        if not primitive then
            local ok, result = pcall(drawing.new, kind)
            if not ok or not result then
                self.Available = false
                for object in pairs(self._all) do pcall(function() object.Visible = false end) end
                services:Get("EventBus"):Publish("Notify", "Drawing unavailable", "The executor could not create " .. kind .. "; native chams remain available")
                return nil
            end
            primitive = result; self._all[primitive] = kind
        end
        reset(primitive, kind)
        self._inUse[primitive] = true
        return primitive
    end
    function DrawingPool:Release(primitive: any)
        if not primitive or not self._inUse[primitive] then return end
        pcall(function() primitive.Visible = false end)
        self._inUse[primitive] = nil
        local kind = self._all[primitive]
        if kind then table.insert(self._free[kind], primitive) end
    end
    function DrawingPool:DestroyAll()
        for primitive in pairs(self._all) do
            pcall(function() primitive.Visible = false end)
            local ok, err = pcall(function() primitive:Remove() end)
            if not ok then warn("[B0Xaz][Drawing cleanup] " .. tostring(err)) end
        end
        table.clear(self._all); table.clear(self._inUse)
        for _, free in pairs(self._free) do table.clear(free) end
    end
    function DrawingPool:GetStats(): any
        local total, active = 0, 0
        for _ in pairs(self._all) do total += 1 end
        for _ in pairs(self._inUse) do active += 1 end
        return { Total = total, Active = active, Free = total - active }
    end
    function DrawingPool:Initialize() end
    function DrawingPool:Destroy() scope:Dispose() end
    scope:Add(function() DrawingPool:DestroyAll() end)
    return DrawingPool
end
