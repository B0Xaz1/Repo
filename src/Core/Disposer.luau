--!nonstrict
export type Scope = {
    Name: string,
    Add: (Scope, any, string?) -> any,
    Spawn: (Scope, (...any) -> (), ...any) -> thread?,
    Delay: (Scope, number, (...any) -> (), ...any) -> thread?,
    Bind: (Scope, string, any, string?) -> any,
    Unbind: (Scope, string) -> (),
    CreateChild: (Scope, string) -> Scope,
    ReleaseProperty: (Scope, any, string) -> (),
    ReleaseObject: (Scope, any) -> (),
    ReleaseProperties: (Scope) -> (),
    Dispose: (Scope) -> (),
}

return function(): any
    local Disposer = {}
    local methods = {}
    methods.__index = methods

    local function cleanup(item: any, customMethod: string?)
        local ok, err = pcall(function()
            local kind = typeof(item)
            if customMethod then
                if customMethod == "Remove" then pcall(function() item.Visible = false end) end
                item[customMethod](item)
            elseif kind == "thread" then
                -- Unload is often called by one of our own handlers; cancelling it would interrupt teardown.
                if item ~= coroutine.running() and coroutine.status(item) ~= "dead" then task.cancel(item) end
            elseif kind == "RBXScriptConnection" then
                item:Disconnect()
            elseif kind == "Instance" then
                item:Destroy()
            elseif kind == "function" then
                item()
            elseif kind == "table" or kind == "userdata" then
                local method = item.Dispose or item.Destroy or item.Disconnect or item.Remove
                if method then
                    -- Some Drawing implementations throw in Remove; hide first even on that path.
                    if item.Remove then pcall(function() item.Visible = false end) end
                    method(item)
                end
            end
        end)
        if not ok then warn("[B0Xaz][Dispose] " .. tostring(err)) end
    end

    function Disposer.new(name: string?, parent: any?): any
    local scope = setmetatable({
        Name = name or "Scope", _disposed = false, _items = {}, _nextId = 0,
        _keys = {}, _itemSlots = {}, _leases = {}, _parent = parent,
    }, methods)
        scope._root = if parent then parent._root else scope
        if not parent then scope._journal = {} end
        return scope
    end

    function methods:IsDisposed(): boolean return self._disposed end

    function methods:Add(item: any, customMethod: string?): any
        if item == nil then return nil end
        if self._disposed then cleanup(item, customMethod); return item end
        self._nextId += 1
        self._items[self._nextId] = { Item = item, Method = customMethod }
        if not self._itemSlots[item] then self._itemSlots[item] = {} end
        self._itemSlots[item][self._nextId] = true
        return item
    end

    function methods:Forget(item: any)
        local slots = self._itemSlots[item]
        if not slots then return end
        for id in pairs(slots) do self._items[id] = nil end
        self._itemSlots[item] = nil
        while self._nextId > 0 and self._items[self._nextId] == nil do self._nextId -= 1 end
    end

    local function schedule(scope: any, seconds: number?, callback: (...any) -> (), ...: any): thread?
        if scope._disposed then return nil end
        local args = table.pack(...)
        local worker: thread
        worker = coroutine.create(function()
            if not scope._disposed then
                local ok, err = pcall(callback, table.unpack(args, 1, args.n))
                if not ok then warn("[B0Xaz][Handler:" .. scope.Name .. "] " .. tostring(err)) end
            end
            scope:Forget(worker)
        end)
        -- Register before starting: task.spawn can finish (or unload) before returning.
        scope:Add(worker)
        if seconds then task.delay(seconds, worker) else task.spawn(worker) end
        return worker
    end

    function methods:Spawn(callback: (...any) -> (), ...: any): thread?
        return schedule(self, nil, callback, ...)
    end

    function methods:Delay(seconds: number, callback: (...any) -> (), ...: any): thread?
        return schedule(self, math.max(seconds, 0), callback, ...)
    end

    function methods:Connect(signal: any, callback: (...any) -> ()): any
        local scope = self
        return scope:Add(signal:Connect(function(...: any) scope:Spawn(callback, ...) end))
    end
    -- High-rate engine signals (RenderStepped, InputChanged, DescendantAdded) cannot afford a thread per event.
    function methods:ConnectImmediate(signal: any, callback: (...any) -> ()): any
        local scope = self
        return scope:Add(signal:Connect(function(...: any)
            if scope._disposed then return end
            local ok, err = pcall(callback, ...)
            if not ok then warn("[B0Xaz][Handler:" .. scope.Name .. "] " .. tostring(err)) end
        end))
    end

    function methods:Bind(key: string, item: any, customMethod: string?): any
        self:Unbind(key)
        if self._disposed then cleanup(item, customMethod) else self._keys[key] = { Item = item, Method = customMethod } end
        return item
    end

    function methods:Unbind(key: string)
        local entry = self._keys[key]
        self._keys[key] = nil
        if entry then cleanup(entry.Item, entry.Method) end
    end

    function methods:CreateChild(name: string): any
        local child = Disposer.new(name, self)
        self:Add(child)
        return child
    end

    function methods:GetOriginal(object: any, property: string): (boolean, any)
        local properties = self._root._journal[object]
        if properties and properties[property] then return true, properties[property].Original end
        return pcall(function() return object[property] end)
    end

    function methods:SetProperty(object: any, property: string, value: any, dynamic: boolean?): boolean
        if self._disposed or object == nil then return false end
        local journal = self._root._journal
        local properties = journal[object]
        if not properties then properties = {}; journal[object] = properties end
        local entry = properties[property]
        if not entry then
            local ok, original = pcall(function() return object[property] end)
            if not ok then if next(properties) == nil then journal[object] = nil end; return false end
            entry = { Original = original, Owners = {} }
            properties[property] = entry
        end
        local owned = self._leases[object]
        if not owned then owned = {}; self._leases[object] = owned end
        local lease = owned[property]
        local newLease = lease == nil
        if not lease then
            lease = { Scope = self, Value = value }
            owned[property] = lease
            table.insert(entry.Owners, lease)
        end
        lease.Value = value
        if dynamic then
            -- Integrators (teleport, spin, flight) share a live transform; they need last-write composition, not a frozen overlay.
            for index, candidate in ipairs(entry.Owners) do
                if candidate == lease then table.remove(entry.Owners, index); break end
            end
            table.insert(entry.Owners, lease)
        end
        -- Static first-touch ownership order is stable; a reassertion cannot steal a newer overlay's priority.
        local ok = pcall(function() object[property] = entry.Owners[#entry.Owners].Value end)
        if not ok and newLease then
            -- Readable does not imply writable (terrain and surface maps vary by client). A failed first write owns nothing.
            owned[property] = nil
            if next(owned) == nil then self._leases[object] = nil end
            for index, candidate in ipairs(entry.Owners) do if candidate == lease then table.remove(entry.Owners, index); break end end
            if #entry.Owners == 0 then
                properties[property] = nil
                if next(properties) == nil then journal[object] = nil end
            end
        end
        return ok
    end

    function methods:RestoreProperty(object: any, property: string)
        local owned = self._leases[object]
        local lease = owned and owned[property]
        if not lease then return end
        owned[property] = nil
        if next(owned) == nil then self._leases[object] = nil end
        local properties = self._root._journal[object]
        local entry = properties and properties[property]
        if not entry then return end
        for index, candidate in ipairs(entry.Owners) do
            if candidate == lease then table.remove(entry.Owners, index); break end
        end
        local top = entry.Owners[#entry.Owners]
        local ok, err = pcall(function() object[property] = if top then top.Value else entry.Original end)
        if not ok then warn("[B0Xaz][Restore:" .. self.Name .. "] " .. property .. ": " .. tostring(err)) end
        if not top then
            properties[property] = nil
            if next(properties) == nil then self._root._journal[object] = nil end
        end
    end

    function methods:SetAttribute(object: Instance, attribute: string, value: any): boolean
        local root = self._root
        if not root._attributeProxies then root._attributeProxies = {} end
        local proxy = root._attributeProxies[object]
        if not proxy then
            proxy = setmetatable({}, {
                __index = function(_proxy: any, key: string): any return object:GetAttribute(key) end,
                __newindex = function(_proxy: any, key: string, nextValue: any) object:SetAttribute(key, nextValue) end,
            })
            root._attributeProxies[object] = proxy
        end
        return self:SetProperty(proxy, attribute, value)
    end

    function methods:RestoreAttribute(object: Instance, attribute: string)
        local proxies = self._root._attributeProxies
        if proxies and proxies[object] then self:RestoreProperty(proxies[object], attribute) end
    end

    function methods:RestoreObject(object: any)
        local properties = self._leases[object]
        if not properties then return end
        for property in pairs(table.clone(properties)) do self:RestoreProperty(object, property) end
    end

    function methods:RestoreProperties()
        for object in pairs(table.clone(self._leases)) do self:RestoreObject(object) end
    end

    -- Lease removal WITHOUT a write. Live transforms (CFrame, velocities) must be released this
    -- way: restoring their cached original snaps the object back to a stale position or speed.
    -- If another scope still owns the property, its overlay simply remains in effect.
    function methods:ReleaseProperty(object: any, property: string)
        local owned = self._leases[object]
        local lease = owned and owned[property]
        if not lease then return end
        owned[property] = nil
        if next(owned) == nil then self._leases[object] = nil end
        local properties = self._root._journal[object]
        local entry = properties and properties[property]
        if not entry then return end
        for index, candidate in ipairs(entry.Owners) do
            if candidate == lease then table.remove(entry.Owners, index); break end
        end
        if #entry.Owners == 0 then
            properties[property] = nil
            if next(properties) == nil then self._root._journal[object] = nil end
        end
    end

    function methods:ReleaseObject(object: any)
        local properties = self._leases[object]
        if not properties then return end
        for property in pairs(table.clone(properties)) do self:ReleaseProperty(object, property) end
    end

    function methods:ReleaseProperties()
        for object in pairs(table.clone(self._leases)) do self:ReleaseObject(object) end
    end

    function methods:Dispose()
        if self._disposed then return end
        self._disposed = true
        local keys = self._keys
        self._keys = {}
        for _, entry in pairs(keys) do cleanup(entry.Item, entry.Method) end
        for id = self._nextId, 1, -1 do
            local entry = self._items[id]
            self._items[id] = nil
            if entry then cleanup(entry.Item, entry.Method) end
        end
        table.clear(self._itemSlots)
        self:RestoreProperties()
        if self == self._root and self._attributeProxies then table.clear(self._attributeProxies) end
        if self._parent then self._parent:Forget(self) end
    end

    return Disposer
end
