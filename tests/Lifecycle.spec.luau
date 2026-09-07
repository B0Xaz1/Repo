--!nonstrict
return function(sources: { [string]: string }, core: any): any
    local Test = { Passed = 0 }
    local function expect(condition: boolean, message: string) assert(condition, message); Test.Passed += 1 end
    function Test:Run(): number
        local runtime = core.Environment
        local globals, modules, requests, traces, initialized = {}, {}, {}, {}, {}
        local menuCount, peakMenus, modalCount, fakeClock = 0, 0, 0, 0
        local failures, stalls, metrics = {}, {}, { Execute = 0, Factory = 0 }
        for path, source in pairs(sources) do modules[path] = source end
        runtime._G, runtime.getgenv = globals, nil
        runtime.os = table.clone(os)
        runtime.os.clock = function() return fakeClock end
        runtime.os.time = function() return 1788775200 + math.floor(fakeClock) end
        runtime.print = function(...: any) table.insert(traces, table.concat({ ... }, " ")) end
        runtime.loadstring = function(source: string, name: string?): any
            local chunk, message = loadstring(source, name)
            if chunk then setfenv(chunk, runtime) end
            return chunk, message
        end
        runtime.task.wait = function(delay: number?): any fakeClock += delay or 0.02; return coroutine.yield() end
        local clearCalls = {}
        runtime.rconsoleclear = function() table.insert(clearCalls, "first"); error("unsupported") end
        runtime.consoleclear = function() table.insert(clearCalls, "second") end
        runtime.clearconsole = function() table.insert(clearCalls, "third") end
        runtime._lifecycle = {
            Initialized = function(name: string) table.insert(initialized, name) end,
            Menu = function(delta: number) menuCount += delta; peakMenus = math.max(peakMenus, menuCount) end,
            Modal = function(delta: number) modalCount += delta end,
            Metrics = metrics,
        }
        modules["src/UI/DOM.luau"] = "return function(services: any): any return {} end"
        local registration = {
            { "KeyService", "Services" }, { "ConfigService", "Services" }, { "PlayerTracker", "Services" },
            { "OptimizerService", "Services" }, { "LightingService", "Services" }, { "HotkeyService", "Services" },
            { "DrawingPool", "Visuals" }, { "TargetFilter", "Combat" }, { "ESPController", "Visuals" },
            { "OverlayController", "Visuals" }, { "LocomotionService", "Locomotion" }, { "FlightService", "Locomotion" },
            { "ExtrasService", "Services" }, { "AimbotService", "Combat" }, { "TriggerbotService", "Combat" },
            { "PluginManager", "Plugins" }, { "ThemeEngine", "UI" }, { "UIEngine", "UI" },
        }
        for _, entry in ipairs(registration) do
            local extra = ""
            if entry[1] == "KeyService" then extra = "function Service:VerifySavedKey() return true, 3 end" end
            if entry[1] == "ConfigService" then extra = "function Service:ApplyLaunchState() return 'defaults' end" end
            if entry[1] == "UIEngine" then extra = "function Service:ConstructInterface() _lifecycle.Menu(1); owner:Add(function() _lifecycle.Menu(-1) end) end" end
            modules["src/" .. entry[2] .. "/" .. entry[1] .. ".luau"] = string.format([[return function(services: any): any
                local owner = services:Get("Disposer"):CreateChild(%q)
                local Service = {}
                function Service:Initialize() _lifecycle.Initialized(%q) end
                function Service:Destroy() owner:Dispose() end
                %s
                return Service
            end]], entry[1], entry[1], extra)
        end
        modules["src/UI/Modals/KeyAuthModal.luau"] = [[return function(services: any): any
            local Modal = {}
            function Modal:Show(_success: any, _message: any)
                _lifecycle.Modal(1)
                services:Get("Disposer"):Add(function() _lifecycle.Modal(-1) end)
            end
            return Modal
        end]]
        local loaded = true
        function runtime.game:IsLoaded(): boolean return loaded end
        local function route(url: string): string
            return url:match("/(src/.-%.luau)%?") or (if url:find("/init.luau", 1, true) then "init.luau" else "loader.luau")
        end
        function runtime.game:HttpGet(url: string): string
            local path = route(url)
            requests[path] = (requests[path] or 0) + 1
            table.insert(traces, "url " .. url)
            if stalls[path] then coroutine.yield("http") end
            if (failures[path] or 0) > 0 then failures[path] -= 1; return "404: Not Found" end
            return modules[path] or "404: Not Found"
        end
        local function worker(source: string): thread
            local chunk, message = runtime.loadstring(source, "@LifecycleTest")
            assert(chunk, message)
            return coroutine.create(chunk)
        end
        local function resume(thread: thread)
            local ok, message = coroutine.resume(thread)
            assert(ok, message)
        end
        local function finish(thread: thread)
            for _ = 1, 100 do if coroutine.status(thread) == "dead" then return end; resume(thread) end
            error("Lifecycle coroutine exceeded its budget")
        end
        -- Leave the ref unset to exercise release defaults; the legacy URL case below covers slash-containing refs.
        stalls["init.luau"] = true
        local first = worker(sources["loader.luau"]); resume(first)
        expect(globals.B0XazLoaderBusy ~= nil and menuCount == 0, "Loader publishes its lock before its first yielding download")
        local duplicate = worker(sources["loader.luau"]); finish(duplicate)
        expect(requests["init.luau"] == 1, "A racing manual/autoexec loader is refused before another download")
        stalls["init.luau"] = nil; finish(first)
        expect(globals.B0XazRunning and globals.B0XazLoaderBusy == nil and menuCount == 1, "Cold loader reaches one running suite and clears busy")
        expect(globals.B0XazRef == "main" and globals.B0XazBaseURL == "https://raw.githubusercontent.com/B0Xaz1/Repo/main/", "The release loader defaults to main")
        expect(#initialized == #registration, "Bootstrap initializes every registered application service")
        for index, entry in ipairs(registration) do expect(initialized[index] == entry[1], "Service initialization respects dependency order: " .. entry[1]) end
        for path, count in pairs(requests) do expect(count == 1, "One HTTP request per module during successful boot: " .. path) end
        local container = globals.B0XazServiceContainer
        local load = container:Get("Require")
        modules["src/TestCache.luau"] = [[_lifecycle.Metrics.Execute += 1
            return function(services: any): any _lifecycle.Metrics.Factory += 1; return { Container = services } end]]
        local factory = load("./B0XazUniversal/src/TestCache.luau")
        expect(type(factory) == "function" and metrics.Execute == 1 and metrics.Factory == 0, "Argument-free loads return raw factories without initializing them")
        local instance = load("/src/TestCache.luau", container)
        expect(instance == load("src/TestCache.luau", {}) and metrics.Factory == 1 and requests["src/TestCache.luau"] == 1, "Normalized paths share source, compiled chunk and initialized singleton")
        expect(load("src/TestCache.luau") == factory, "A no-argument load still returns the raw factory after singleton initialization")
        modules["src/Concurrent.luau"] = "return function(value: any): any return { Value = value } end"
        stalls["src/Concurrent.luau"] = true
        local a, b = nil, nil
        local threadA = coroutine.create(function() a = load("src/Concurrent.luau", "first") end)
        local threadB = coroutine.create(function() b = load("src/Concurrent.luau", "second") end)
        resume(threadA); resume(threadB)
        stalls["src/Concurrent.luau"] = nil; finish(threadA); finish(threadB)
        expect(a == b and requests["src/Concurrent.luau"] == 1, "Concurrent module requests are single-flight through compilation and initialization")
        modules["src/SyntaxFailure.luau"] = "return function( broken syntax longer than ten bytes"
        modules["src/RuntimeFailure.luau"] = "error('chunk exploded'); return function() return {} end"
        modules["src/InitFailure.luau"] = "return function(_services: any): any error('factory exploded') end"
        for _, case in ipairs({ { "src/SyntaxFailure.luau", "Syntax Error" }, { "src/RuntimeFailure.luau", "Runtime Error" }, { "src/InitFailure.luau", "Init Error" } }) do
            local ok, message = pcall(function() load(case[1], container) end)
            expect(not ok and tostring(message):find(case[2] .. " in '" .. case[1] .. "'", 1, true) ~= nil, "Module errors retain quotable stage/path context")
        end
        local fetchError = nil
        local failed = coroutine.create(function() local ok, message = pcall(function() load("src/Missing.luau", container) end); expect(not ok, "Missing modules fail"); fetchError = message end)
        finish(failed)
        expect(requests["src/Missing.luau"] == 3 and tostring(fetchError):find("Fetch failed for 'src/Missing.luau'", 1, true), "Module fetching retries exactly three times before a named failure")
        local originalSession = globals.B0XazSessionId
        local relaunch = coroutine.create(globals.B0XazRelaunch); finish(relaunch)
        expect(globals.B0XazSessionId == originalSession + 1 and menuCount == 1 and peakMenus == 1, "Relaunch disposes before rebuilding, with no visual overlap")
        expect(requests["src/Core/Disposer.luau"] == 2, "A new session re-fetches modules instead of sharing an old source cache")
        globals.B0XazUnload()
        expect(not globals.B0XazRunning and globals.B0XazMasterDisposer == nil and globals.B0XazServiceContainer == nil and menuCount == 0, "Public unload drops globals and cleans the master")
        expect(clearCalls[1] == "first" and clearCalls[2] == "second" and not table.find(clearCalls, "third"), "Console cleanup tries candidates in order and stops at the first success")
        local input = core.Services.UserInputService
        local active = 0
        for _, connection in ipairs(input.InputBegan.Handlers) do if connection.Connected then active += 1 end end
        expect(active == 0, "No quick-unload listener survives disposal")
        modules["src/Services/KeyService.luau"] = "return function(services: any): any return { VerifySavedKey = function() return false, 0, 'test gate' end } end"
        finish(worker(sources["loader.luau"]))
        expect(modalCount == 1 and not globals.B0XazRunning, "An unverified license remains in the pre-launch gate")
        local before = requests["init.luau"]
        finish(worker(sources["loader.luau"]))
        expect(requests["init.luau"] == before and modalCount == 1, "Repeated runs do not stack auth modals")
        input.InputBegan:Fire({ KeyCode = runtime.Enum.KeyCode.End, UserInputType = runtime.Enum.UserInputType.Keyboard }, false)
        expect(modalCount == 0 and globals.B0XazMasterDisposer == nil, "The quick unload key works before authentication")
        globals.B0XazBaseURL = "https://raw.githubusercontent.com/B0Xaz1/Repo/arena/01a07b6b-repo/B0XazUniversal/init.lua?old=1#legacy"
        finish(worker(sources["init.luau"]))
        expect(globals.B0XazBaseURL == "https://raw.githubusercontent.com/B0Xaz1/Repo/arena/01a07b6b-repo/" and globals.B0XazInitURL == globals.B0XazBaseURL .. "init.luau", "URL normalization preserves slash-containing refs and removes legacy file/folder/query suffixes")
        globals.B0XazUnload()
        before = requests["init.luau"]
        failures["init.luau"] = 4
        finish(worker(sources["loader.luau"]))
        expect(requests["init.luau"] == before + 5 and modalCount == 1 and not globals.B0XazLoaderBusy, "The outer loader survives four CDN failures and succeeds on its fifth attempt")
        globals.B0XazUnload()
        failures["init.luau"] = 5; finish(worker(sources["loader.luau"]))
        expect(globals.B0XazLoaderBusy == nil and globals.B0XazMasterDisposer == nil, "Exhausted downloads clear busy on their failure exit")
        local oldSource = modules["init.luau"]
        modules["init.luau"] = "not valid syntax"
        finish(worker(sources["loader.luau"]))
        expect(globals.B0XazLoaderBusy == nil, "Compile failure clears the loader lock")
        modules["init.luau"] = "error('init runtime failure')"
        finish(worker(sources["loader.luau"]))
        expect(globals.B0XazLoaderBusy == nil, "Init runtime failure clears the loader lock")
        modules["init.luau"] = oldSource
        loaded = false
        local slow = worker(sources["loader.luau"]); resume(slow); fakeClock += 61; finish(slow)
        expect(globals.B0XazLoaderBusy == nil, "Autoexec readiness waits are bounded and clear busy on timeout")
        local cacheBusters = 0
        for _, line in ipairs(traces) do if line:match("^url ") then expect(line:find("?t=", 1, true) ~= nil, "Every boot and module fetch carries a cache buster"); cacheBusters += 1 end end
        expect(cacheBusters > 50, "Lifecycle coverage exercised real HTTP URL construction across sessions")
        runtime.print = print
        print(string.format("PASS Lifecycle: %d assertions", Test.Passed))
        return Test.Passed
    end
    return Test
end
