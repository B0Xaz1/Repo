--!strict
local CONFIG = table.freeze({
    TEXT_DEFAULT_SIZE = 13,
    TEXT_DEFAULT_FONT = 2,
    CIRCLE_DEFAULT_SIDES = 64,
})

-- Defaults are built and frozen once, at load. Acquire() runs every time an ESP
-- record or overlay object is created, and the old reset() rebuilt this table (and
-- re-ran the kind branch chain) per primitive, then pushed every property through
-- its own pcall.
local DEFAULTS = table.freeze({
    Line = table.freeze({
        Visible = false, Color = Color3.new(1, 1, 1), Transparency = 1, ZIndex = 2,
        From = Vector2.zero, To = Vector2.zero, Thickness = 1,
    }),
    Text = table.freeze({
        Visible = false, Color = Color3.new(1, 1, 1), Transparency = 1, ZIndex = 2,
        Text = "", Size = CONFIG.TEXT_DEFAULT_SIZE, Center = true, Outline = true, Font = CONFIG.TEXT_DEFAULT_FONT,
    }),
    Square = table.freeze({
        Visible = false, Color = Color3.new(1, 1, 1), Transparency = 1, ZIndex = 2,
        Position = Vector2.zero, Size = Vector2.zero, Filled = false, Thickness = 1,
    }),
    Circle = table.freeze({
        Visible = false, Color = Color3.new(1, 1, 1), Transparency = 1, ZIndex = 2,
        Position = Vector2.zero, Radius = 1, Filled = false, NumSides = CONFIG.CIRCLE_DEFAULT_SIDES, Thickness = 1,
    }),
})

-- Reused constantly, so these must not allocate a closure per call.
local function hide(primitive: any) primitive.Visible = false end
local function remove(primitive: any) primitive:Remove() end

-- One protected call for the whole batch instead of one per property, and reads
-- gate the writes so a warm primitive only pays for the properties its previous
-- owner actually changed (callers diff their own writes, so most are untouched).
local function applyDefaults(primitive: any, defaults: any)
    -- Hide first: a pooled primitive can still be on screen from its previous owner.
    if primitive.Visible then primitive.Visible = false end
    for property, value in pairs(defaults) do
        if property ~= "Visible" and primitive[property] ~= value then primitive[property] = value end
    end
end

-- Fallback for primitives whose index/newindex throws: isolate each property so
-- one unreadable member cannot leave the rest of the primitive stale.
local function applyDefaultsIsolated(primitive: any, defaults: any)
    pcall(function() if primitive.Visible then primitive.Visible = false end end)
    for property, value in pairs(defaults) do
        if property == "Visible" then continue end
        pcall(function()
            if primitive[property] ~= value then primitive[property] = value end
        end)
    end
end

return function(services: any): any
    local environment, bus = services:Get("Environment"), services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("DrawingPool")
    local drawing = environment.Drawing
    local DrawingPool = { Available = false, _all = {}, _inUse = {}, _free = { Line = {}, Text = {}, Square = {}, Circle = {} } }

    if environment.Capabilities.Drawing then
        local probe = nil
        local created = pcall(function() probe = drawing.new("Line"); probe.Visible = false; probe:Remove() end)
        if not created and probe then pcall(function() probe.Visible = false; probe:Remove() end) end
        DrawingPool.Available = created
    end

    local function reset(primitive: any, kind: string)
        local defaults: any = DEFAULTS[kind]
        if not pcall(applyDefaults, primitive, defaults) then applyDefaultsIsolated(primitive, defaults) end
    end

    function DrawingPool:Acquire(kind: string): any?
        if not self.Available or scope:IsDisposed() then return nil end
        local free = self._free[kind]
        assert(free, `Unsupported Drawing kind '{kind}'`)
        local primitive = table.remove(free)
        if not primitive then
            local ok, result = pcall(drawing.new, kind)
            if not ok or not result then
                self.Available = false
                for object in pairs(self._all) do pcall(hide, object) end
                bus:Publish("Notify", "Drawing unavailable", `The executor could not create {kind}; native chams remain available`)
                return nil
            end
            primitive = result; self._all[primitive] = kind
        end
        -- Fresh primitives need the defaults written once; reused ones need them
        -- restored, because a caller only repaints the properties it knows about.
        reset(primitive, kind)
        self._inUse[primitive] = true
        return primitive
    end

    function DrawingPool:Release(primitive: any)
        if not primitive or not self._inUse[primitive] then return end
        pcall(hide, primitive)
        self._inUse[primitive] = nil
        local kind = self._all[primitive]
        if kind then table.insert(self._free[kind], primitive) end
    end

    function DrawingPool:DestroyAll()
        for primitive in pairs(self._all) do
            pcall(hide, primitive)
            pcall(remove, primitive)
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
