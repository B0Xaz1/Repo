--!nonstrict
export type Container = {
    Register: (Container, string, any) -> any,
    Get: (Container, string) -> any,
    Has: (Container, string) -> boolean,
    InitializeAll: (Container) -> (),
    DestroyAll: (Container) -> (),
}

return function(disposer: any?): any
    local ServiceContainer = { _instances = {}, _order = {}, _initialized = {}, _destroyed = false }
    function ServiceContainer:Register(name: string, instance: any): any
        assert(not self._destroyed, "Container is destroyed")
        assert(instance ~= nil, "Cannot register nil service '" .. name .. "'")
        if self._instances[name] ~= nil then
            warn("[B0Xaz][Container] Overwrite '" .. name .. "'")
        else
            table.insert(self._order, name)
        end
        self._instances[name] = instance
        return instance
    end
    function ServiceContainer:Get(name: string): any
        local value = self._instances[name]
        assert(value ~= nil, "Missing dependency '" .. name .. "'")
        return value
    end
    function ServiceContainer:Has(name: string): boolean return self._instances[name] ~= nil end
    function ServiceContainer:InitializeAll()
        for _, name in ipairs(self._order) do
            if self._destroyed then return end
            local instance = self._instances[name]
            if type(instance) == "table" and type(instance.Initialize) == "function" and not self._initialized[name] then
                -- No boot tracing here: executor consoles serialise prints, and InitializeAll runs once anyway.
                instance:Initialize()
                self._initialized[name] = true
            end
        end
    end
    function ServiceContainer:DestroyAll()
        if self._destroyed then return end
        self._destroyed = true
        for index = #self._order, 1, -1 do
            local instance = self._instances[self._order[index]]
            if type(instance) == "table" and type(instance.Destroy) == "function" then
                local ok, err = pcall(function() instance:Destroy() end)
                if not ok then warn("[B0Xaz][Destroy:" .. self._order[index] .. "] " .. tostring(err)) end
            end
        end
        table.clear(self._instances)
        table.clear(self._order)
        table.clear(self._initialized)
    end
    if disposer then disposer:Add(function() ServiceContainer:DestroyAll() end) end
    return ServiceContainer
end
