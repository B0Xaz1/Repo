--!nonstrict
export type Connection = { Connected: boolean, Disconnect: (Connection) -> () }

return function(disposer: any): any
    local EventBus = { _lists = {}, _scope = disposer:CreateChild("EventBus") }

    function EventBus:Subscribe(name: string, callback: (...any) -> ()): Connection
        assert(type(name) == "string" and type(callback) == "function", "Invalid event subscription")
        local list = self._lists[name]
        if not list then list = { Head = nil, Tail = nil }; self._lists[name] = list end
        local node: any = { Connected = true, Callback = callback, Previous = list.Tail, Next = nil }
        if list.Tail then list.Tail.Next = node else list.Head = node end
        list.Tail = node
        function node:Disconnect()
            if not self.Connected then return end
            self.Connected = false
            if self.Previous then self.Previous.Next = self.Next else list.Head = self.Next end
            if self.Next then self.Next.Previous = self.Previous else list.Tail = self.Previous end
            self.Previous, self.Next = nil, nil
            EventBus._scope:Forget(self)
            self.Callback = nil
            -- Both list removal and disposer removal are O(1); disconnected UI rows retain no callbacks.
        end
        self._scope:Add(node)
        return node
    end

    function EventBus:Publish(name: string, ...: any)
        if self._scope:IsDisposed() then return end
        local list = self._lists[name]
        if not list then return end
        -- Synchronous dispatch: every UI interaction and per-frame state write publishes, and
        -- spending a coroutine spawn per handler per event was the suite's biggest steady-state
        -- cost. Handlers must therefore never yield (none in this codebase do; engine signals
        -- keep owned threads via Disposer:Spawn instead).
        local snapshot = {}
        local node = list.Head
        while node do table.insert(snapshot, node); node = node.Next end
        local args = table.pack(...)
        -- Snapshot first because a handler may disconnect itself or its neighbour mid-dispatch.
        for _, handler in ipairs(snapshot) do
            if handler.Connected and handler.Callback then
                local ok, err = pcall(handler.Callback, table.unpack(args, 1, args.n))
                if not ok then warn("[B0Xaz][Event:" .. name .. "] " .. tostring(err)) end
            end
        end
    end

    function EventBus:Destroy()
        self._scope:Dispose()
        table.clear(self._lists)
    end

    EventBus._scope:Add(function() table.clear(EventBus._lists) end)
    return EventBus
end
