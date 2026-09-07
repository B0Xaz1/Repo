--!nonstrict
local BIND_TARGETS = {
    { Key = "Fly", Label = "Flight", Path = "Movement.FlyEnabled" },
    { Key = "Fullbright", Label = "Fullbright", Path = "Visuals.Fullbright" },
    { Key = "ESP", Label = "ESP", Path = "ESP.Enabled" }, { Key = "Chams", Label = "Chams", Path = "Chams.Enabled" },
    { Key = "Aimbot", Label = "Aimbot", Path = "Aimbot.Enabled" },
    { Key = "SpeedLines", Label = "Speed lines", Path = "Extras.SpeedLines" },
    { Key = "Menu", Label = "Menu", Path = "Settings.MenuVisible" },
    { Key = "Lighting", Label = "Lighting mode", Path = "Lighting.Mode", Cycle = { "Off", "Static Day", "Static Night", "Dynamic" } },
}

return function(services: any): any
    local state, environment = services:Get("StateStore"), services:Get("Environment")
    local bus, scope = services:Get("EventBus"), services:Get("Disposer"):CreateChild("HotkeyService")
    local players, teleport = game:GetService("Players"), game:GetService("TeleportService")
    local input, guiService = game:GetService("UserInputService"), game:GetService("GuiService")
    local HotkeyService = { _rejoining = false, _initialized = false }

    function HotkeyService:GetBindTargets(): any
        local result = {}
        for _, entry in ipairs(BIND_TARGETS) do table.insert(result, table.clone(entry)) end
        return result
    end
    function HotkeyService:BuildTeleportSource(): string
        local globals = environment.Globals
        -- Keep the error sentinel split in generated source, or the streaming loader rejects this module itself.
        -- Preserve a slash-containing ref verbatim; using main here would silently change builds after teleport.
        return string.format('local g=_G;if type(getgenv)=="function" then local o,v=pcall(getgenv);if o then g=v end end;g.B0XazRef=%q;g.B0XazBaseURL=%q;local d=os.clock()+60;while not game:IsLoaded() or not game:GetService("Players").LocalPlayer do if os.clock()>d then return end;task.wait(.1) end;for a=1,5 do local o,s=pcall(function() return game:HttpGet(%q.."?t="..os.time().."_"..a) end);if o and type(s)=="string" and #s>=10 and not s:find("404"..": Not Found",1,true) then local f=loadstring(s,"@B0XazInit");if f then pcall(f);break end end;task.wait(a*.7) end',
            tostring(globals.B0XazRef or ""), tostring(globals.B0XazBaseURL or ""), tostring(globals.B0XazInitURL or ""))
    end
    function HotkeyService:QueueLoader(): boolean
        local ok = environment:QueueTeleport(self:BuildTeleportSource())
        if not ok then bus:Publish("Notify", "Teleport", "Queue-on-teleport is unavailable; paste the loader again in the next server") end
        return ok
    end
    function HotkeyService:Rejoin(): (boolean, string)
        if self._rejoining then return false, "Rejoin already in progress" end
        self._rejoining = true
        self:QueueLoader()
        local ok, message = pcall(function()
            if #players:GetPlayers() > 1 and game.JobId ~= "" then teleport:TeleportToPlaceInstance(game.PlaceId, game.JobId, players.LocalPlayer)
            else teleport:Teleport(game.PlaceId, players.LocalPlayer) end
        end)
        if not ok then self._rejoining = false end
        scope:Delay(10, function() HotkeyService._rejoining = false end)
        return ok, if ok then "Rejoining this server..." else tostring(message)
    end
    function HotkeyService:ServerHop(): (boolean, string)
        local cursor = ""
        for _ = 1, 3 do
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
            if cursor ~= "" then url ..= "&cursor=" .. game:GetService("HttpService"):UrlEncode(cursor) end
            local response = environment:Request({ Url = url, Method = "GET" })
            if scope:IsDisposed() then return false, "Cancelled" end
            if not response or tonumber(response.StatusCode) ~= 200 then return false, "Public server list is unavailable on this executor/network" end
            local ok, data = pcall(function() return game:GetService("HttpService"):JSONDecode(response.Body) end)
            if not ok or type(data) ~= "table" or type(data.data) ~= "table" then return false, "Invalid public server response" end
            for _, server in ipairs(data.data) do
                if type(server.id) == "string" and server.id ~= game.JobId and tonumber(server.playing) and tonumber(server.maxPlayers) and server.playing < server.maxPlayers then
                    self:QueueLoader()
                    local moved, errorMessage = pcall(function() teleport:TeleportToPlaceInstance(game.PlaceId, server.id, players.LocalPlayer) end)
                    return moved, if moved then "Joining another server..." else tostring(errorMessage)
                end
            end
            cursor = data.nextPageCursor or ""
            if cursor == "" then break end
        end
        return false, "No open public server was found in the first three pages"
    end
    local function onDisconnect(message: string?)
        if not state:Get("Settings.AutoRejoin") or HotkeyService._rejoining then return end
        if message == "" then return end
        local ok, text = HotkeyService:Rejoin()
        bus:Publish("Notify", if ok then "Auto-rejoin" else "Rejoin failed", text)
    end
    function HotkeyService:Initialize()
        if self._initialized then return end
        self._initialized = true
        scope:Connect(input.InputBegan, function(event: InputObject, processed: boolean)
            if input:GetFocusedTextBox() or state:GetTransient("IsBindingKey") then return end
            for _, entry in ipairs(BIND_TARGETS) do
                if (not processed or entry.Key == "Menu") and environment:MatchesInput(event, state:Get("Settings.Binds." .. entry.Key)) then
                    if entry.Cycle then
                        local index = table.find(entry.Cycle, state:Get(entry.Path)) or 0
                        services:Get("LightingService"):SetMode(entry.Cycle[index % #entry.Cycle + 1])
                    else state:Set(entry.Path, not state:Get(entry.Path)) end
                end
            end
        end)
        pcall(function()
            scope:Connect(guiService.ErrorMessageChanged, function(message: any)
                if type(message) ~= "string" then pcall(function() message = guiService:GetErrorMessage() end) end
                onDisconnect(if type(message) == "string" then message else nil)
            end)
        end)
        pcall(function()
            local coreGui = game:GetService("CoreGui")
            scope:Connect(coreGui.DescendantAdded, function(object: Instance)
                if object.Name == "ErrorPrompt" and object.Parent and object.Parent.Name == "promptOverlay" then
                    local root = object:FindFirstAncestor("RobloxPromptGui")
                    if root then onDisconnect(nil) end
                end
            end)
        end)
        pcall(function()
            scope:Connect(teleport.TeleportInitFailed, function(player: Player, _result: any, message: string)
                if player == players.LocalPlayer then HotkeyService._rejoining = false; bus:Publish("Notify", "Teleport failed", message) end
            end)
        end)
    end
    function HotkeyService:Destroy() scope:Dispose() end
    return HotkeyService
end
