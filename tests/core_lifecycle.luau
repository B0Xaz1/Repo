-- Shares the test doubles in ui_motion.luau; runs after its UI session is disposed.
local initialChecks = checks
local Disposer = factory("src/Core/Disposer.luau")()
RunService.Heartbeat, RunService.Stepped = signal(), signal()
local cameraBindings = {}
function RunService:BindToRenderStep(name, _priority, callback) cameraBindings[name] = callback end
function RunService:UnbindFromRenderStep(name) cameraBindings[name] = nil end
Enum.RenderPriority.Camera.Value = 200
local warnings = {}
mock.warn = function(message) table.insert(warnings, message) end
local root = Disposer.new("Scheduler tests")
local scheduler = factory("src/Core/TaskScheduler.luau")(root)
local calls = {}
local old = scheduler:RegisterHeartbeat("replace", 10, function() table.insert(calls, "old") end)
local replacement = scheduler:RegisterHeartbeat("replace", 10, function() table.insert(calls, "new") end)
RunService.Heartbeat:Fire(0.016)
check(table.concat(calls, ",") == "new", "replacement task remains in the live pipeline")
check(not old.Connected and replacement.Connected, "replacement disconnects old task")
local stable = scheduler:RegisterHeartbeat("stable", 20, function() table.insert(calls, "stable") end)
local inserted
scheduler:RegisterHeartbeat("insert", 0, function()
    table.insert(calls, "insert")
    if not inserted then inserted = scheduler:RegisterHeartbeat("earlier", -1, function() table.insert(calls, "earlier") end) end
end)
table.clear(calls); RunService.Heartbeat:Fire(0.016)
check(table.concat(calls, ",") == "insert,new,stable", "registration during dispatch never duplicates current-frame callbacks")
table.clear(calls); RunService.Heartbeat:Fire(0.016)
check(table.concat(calls, ",") == "earlier,insert,new,stable", "new tasks join next frame in priority order")
local selfReplacing
selfReplacing = scheduler:RegisterRender("self", 0, function()
    table.insert(calls, "first")
    scheduler:RegisterRender("self", 0, function() table.insert(calls, "second") end)
end)
table.clear(calls); RunService.RenderStepped:Fire(0.016); RunService.RenderStepped:Fire(0.016)
check(table.concat(calls, ",") == "first,second" and not selfReplacing.Connected, "self-replacement runs once per frame")
local nextJob
scheduler:RegisterPreSim("cancel-next", 0, function() nextJob:Disconnect() end)
nextJob = scheduler:RegisterPreSim("next", 1, function() error("Disconnected job ran") end)
RunService.Stepped:Fire(0,0.016)
check(not nextJob.Connected and nextJob.Strikes == 0, "disconnecting a later job skips it in the same frame")
local successes, attempts = 0, 0
local failing = scheduler:RegisterCamera("failing", 0, function() attempts += 1; error("Expected test failure") end)
scheduler:RegisterCamera("healthy", 1, function() successes += 1 end)
for _=1,7 do cameraBindings["B0XazUniversal.Camera"](0.016) end
check(attempts == 5 and successes == 7 and not failing.Enabled, "circuit breaker isolates errors without stopping healthy tasks")
check(#warnings == 1, "repeated failures warn only once per circuit opening")
failing.Enabled = true
cameraBindings["B0XazUniversal.Camera"](0.016)
check(attempts == 6 and failing.Strikes == 1, "re-enabling a failed task resets its consecutive error count")
scheduler:Destroy()
check(next(cameraBindings) == nil and connectionCount() == 0, "scheduler teardown releases engine connections")
check(not pcall(function() scheduler:RegisterHeartbeat("late", 0, function() end) end), "disposed scheduler rejects new tasks")
root:Dispose()

local busRoot = Disposer.new("Bus tests")
local events = factory("src/Core/EventBus.luau")(busRoot)
for index=1,100 do events:Subscribe(`temporary:{index}`, function() end):Disconnect() end
check(next(events._lists) == nil, "temporary event names leave no empty listener lists")
local order, second, late = {}, nil, nil
local first = events:Subscribe("event", function()
    table.insert(order, "first")
    if second then second:Disconnect() end
    if not late then late = events:Subscribe("event", function() table.insert(order, "late") end) end
end)
second = events:Subscribe("event", function() table.insert(order, "second") end)
events:Publish("event")
check(table.concat(order, ",") == "first", "event dispatch skips disconnected handlers and defers new subscriptions")
table.clear(order); events:Publish("event")
check(table.concat(order, ",") == "first,late", "new event subscriptions run on the next publication")
first:Disconnect(); late:Disconnect()
check(events._lists.event == nil, "last disconnect drops the event name")
local count = 0
local final = events:Subscribe("event", function() count += 1 end)
events:Publish("event"); final:Disconnect()
check(count == 1, "removed event names can be subscribed again")
busRoot:Dispose()
local afterDestroy = events:Subscribe("late", function() error("Must not run") end)
check(not afterDestroy.Connected and next(events._lists) == nil, "late subscriptions on a disposed bus are cleaned immediately")

local delayRoot = Disposer.new("Delay tests")
local called = false
local worker = delayRoot:Delay(30, function() called = true end)
check(waiting[worker] == true, "the owned thread is the actual delayed task, not an untracked wrapper")
delayRoot:Dispose()
check(waiting[worker] == nil and coroutine.status(worker) == "dead", "disposing cancels the delayed task before its deadline")
flushTasks()
check(not called and next(waiting) == nil, "cancelled delays leave no work queued")
local live = Disposer.new("Live delay")
local packed
local done = live:Delay(0, function(...) packed = table.pack(...) end, "a", nil, "c")
flushTasks()
check(packed and packed.n == 3 and packed[1] == "a" and packed[3] == "c", "delays preserve nil arguments")
check(live._itemSlots[done] == nil, "finished delayed work is forgotten")
local failed = live:Delay(0, function() error("Expected delayed callback failure") end)
flushTasks()
check(live._itemSlots[failed] == nil, "failed delayed work is forgotten")
live:Dispose()
check(live:Delay(0, function() end) == nil, "disposed scopes cannot schedule work")
check(connectionCount() == 0 and next(waiting) == nil, "core regressions leave no scheduled work or connections")
print(`PASS: {checks - initialChecks} core lifecycle assertions ({checks} total)`)
