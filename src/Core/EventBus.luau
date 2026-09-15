--!strict
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
        end
        self._scope:Add(node)
        return node
    end

    -- Synchronous dispatch: publishing happens on every UI interaction and per-frame state
    -- write, so handlers run inline and must never yield.
    function EventBus:Publish(name: string, ...: any)
        if self._scope:IsDisposed() then return end
        local list = self._lists[name]
        if not list then return end
        -- Snapshot first: a handler may disconnect itself or its neighbour mid-dispatch.
        local snapshot = {}
        local node = list.Head
        while node do table.insert(snapshot, node); node = node.Next end
        local args = table.pack(...)
        for _, handler in ipairs(snapshot) do
            if handler.Connected and handler.Callback then
                pcall(handler.Callback, table.unpack(args, 1, args.n))
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
