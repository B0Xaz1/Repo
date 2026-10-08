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
        assert(not self._destroyed)
        assert(type(name) == "string" and name ~= "", "Service name must be a non-empty string")
        assert(instance ~= nil, `Cannot register nil service '{name}'`)
        assert(self._instances[name] == nil, `Service '{name}' is already registered`)
        table.insert(self._order, name)
        self._instances[name] = instance
        return instance
    end

    function ServiceContainer:Get(name: string): any
        local value = self._instances[name]
        assert(value ~= nil, `Missing dependency '{name}'`)
        return value
    end

    function ServiceContainer:Has(name: string): boolean return self._instances[name] ~= nil end

    function ServiceContainer:InitializeAll()
        for _, name in ipairs(self._order) do
            if self._destroyed then return end
            local instance = self._instances[name]
            if type(instance) == "table" and type(instance.Initialize) == "function" and not self._initialized[name] then
                instance:Initialize()
                self._initialized[name] = true
            end
        end
    end

    function ServiceContainer:DestroyAll()
        if self._destroyed then return end
        self._destroyed = true
        local failures = {}
        for index = #self._order, 1, -1 do
            local name = self._order[index]
            local instance = self._instances[name]
            if type(instance) == "table" and type(instance.Destroy) == "function" then
                local ok, err = pcall(function() instance:Destroy() end)
                if not ok then table.insert(failures, `Service '{name}' failed to destroy: {tostring(err)}`) end
            end
        end
        table.clear(self._instances)
        table.clear(self._order)
        table.clear(self._initialized)
        if #failures > 0 then error(table.concat(failures, "\n"), 0) end
    end

    if disposer then disposer:Add(function() ServiceContainer:DestroyAll() end) end
    return ServiceContainer
end
