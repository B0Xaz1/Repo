--!strict
local Players = game:GetService("Players")

return function(services: any): any
    local state, bus = services:Get("StateStore"), services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("CommandService")
    local CommandService = { _commands = {}, _history = {}, _initialized = false }

    local function normalizeName(value: string): string
        return tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[/!]+", "")
    end

    local function pushHistory(entry: string)
        table.insert(CommandService._history, 1, entry)
        if #CommandService._history > 20 then table.remove(CommandService._history) end
    end

    local function parseOnOff(args: { string }, defaultValue: boolean): boolean
        if #args == 0 then return not defaultValue end
        local value = tostring(args[1]):lower()
        if value == "on" or value == "true" or value == "1" then return true end
        if value == "off" or value == "false" or value == "0" then return false end
        return not defaultValue
    end

    local function makeOutput(source: string?, text: string): string
        local prefix = if type(source) == "string" and source ~= "" then source else "menu"
        return `{prefix}: {text}`
    end

    function CommandService:Register(name: string, category: string, description: string, usage: string, handler: (string, { string }, string) -> (boolean, string))
        local key = normalizeName(name)
        local entry = { Name = tostring(name), Category = tostring(category), Description = tostring(description), Usage = tostring(usage), Handler = handler }
        self._commands[key] = entry
        return entry
    end

    function CommandService:Alias(name: string, alias: string)
        local key = normalizeName(name)
        local aliasKey = normalizeName(alias)
        local entry = self._commands[key]
        if not entry then return end
        self._commands[aliasKey] = entry
    end

    function CommandService:Find(name: string): any
        local key = normalizeName(name)
        local match = self._commands[key]
        if match then return match end
        for _, entry in pairs(self._commands) do
            if entry and type(entry) == "table" and entry.Name then
                local sourceName = normalizeName(entry.Name)
                if sourceName == key then return entry end
            end
        end
        return nil
    end

    function CommandService:GetCommandList(): { any }
        local list = {}
        for _, entry in pairs(self._commands) do
            if entry and entry.Name then table.insert(list, { Name = entry.Name, Category = entry.Category, Description = entry.Description, Usage = entry.Usage }) end
        end
        table.sort(list, function(a: any, b: any)
            if a.Category ~= b.Category then return a.Category < b.Category end
            return a.Name < b.Name
        end)
        return list
    end

    function CommandService:GetRecentHistory(): { string }
        return table.clone(self._history)
    end

    function CommandService:Execute(input: string, source: string?): (boolean, string)
        local raw = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if raw == "" then return false, "No command entered" end

        local parts = {}
        for token in raw:gmatch("%S+") do table.insert(parts, token) end
        local commandName = normalizeName(parts[1])
        local arguments = {}
        for index = 2, #parts do table.insert(arguments, parts[index]) end
        local command = self:Find(commandName)
        if not command then
            local message = `Unknown command '{commandName}'. Type /help for a list of commands.`
            pushHistory(makeOutput(source, message))
            bus:Publish("CommandOutput", makeOutput(source, message))
            return false, message
        end

        local ok, result = pcall(function()
            return command.Handler(raw, arguments, source or "menu")
        end)

        if not ok then
            local message = `Command failed: {tostring(result)}`
            pushHistory(makeOutput(source, message))
            bus:Publish("CommandOutput", makeOutput(source, message))
            return false, message
        end

        local success, message
        if type(result) == "table" then
            success = result[1] ~= false
            message = tostring(result[2] or if success then "Command executed" else "Command failed")
        elseif type(result) == "boolean" then
            success = result
            message = if success then "Command executed" else "Command failed"
        else
            success = true
            message = tostring(result)
        end

        pushHistory(makeOutput(source, message))
        bus:Publish("CommandOutput", makeOutput(source, message))
        return success, message
    end

    function CommandService:HandleChat(message: string): boolean
        if type(message) ~= "string" then return false end
        local stripped = message:match("^%s*(.-)%s*$")
        if stripped == "" then return false end
        local prefix = stripped:match("^[/!]")
        if not prefix then return false end
        self:Execute(stripped, "chat")
        return true
    end

    function CommandService:HandleIncomingChatMessage(message: any): boolean
        local ok, text, userId = pcall(function()
            local source = message.TextSource
            return message.Text, if source then source.UserId else nil
        end)
        if not ok then return false end
        if type(text) ~= "string" then return false end
        local localPlayer = Players.LocalPlayer
        if not localPlayer then return false end
        if userId and tostring(userId) ~= tostring(localPlayer.UserId) then return false end
        return self:HandleChat(text)
    end

    function CommandService:BuildDefaultCommands()
        self:Register("help", "Utility", "Lists available commands and examples.", "/help", function(_raw: string, args: { string }, source: string)
            local names = {}
            local byCategory = {}
            for _, entry in ipairs(self:GetCommandList()) do
                local key = tostring(entry.Category)
                if not byCategory[key] then byCategory[key] = {} end
                table.insert(byCategory[key], entry.Name)
            end
            local sectionNames = {}
            for _, entry in ipairs(self:GetCommandList()) do
                if not table.find(sectionNames, entry.Category) then table.insert(sectionNames, entry.Category) end
            end
            table.sort(sectionNames)
            local output = {}
            for _, category in ipairs(sectionNames) do
                local namesForCategory = byCategory[category]
                table.sort(namesForCategory)
                table.insert(output, `{category}: {table.concat(namesForCategory, ", ")}`)
            end
            return true, table.concat(output, " | ")
        end)

        self:Register("fly", "Movement", "Toggle flight mode.", "/fly [on|off]", function(_raw: string, args: { string }, _source: string)
            local enabled = state:Get("Movement.FlyEnabled") == true
            local desired = parseOnOff(args, enabled)
            local ok, message = state:Set("Movement.FlyEnabled", desired)
            return ok, if ok then if desired then "Flight enabled" else "Flight disabled" else message or "Flight toggle failed"
        end)
        self:Register("unfly", "Movement", "Disable flight instantly.", "/unfly", function(_raw: string, _args: { string }, _source: string)
            local ok, message = state:Set("Movement.FlyEnabled", false)
            return ok, if ok then "Flight disabled" else message or "Flight disable failed"
        end)
        self:Register("togglefly", "Movement", "Toggle flight mode.", "/togglefly", function(_raw: string, _args: { string }, _source: string)
            local enabled = state:Get("Movement.FlyEnabled") == true
            local ok, message = state:Set("Movement.FlyEnabled", not enabled)
            return ok, if ok then if not enabled then "Flight enabled" else "Flight disabled" else message or "Flight toggle failed"
        end)

        self:Register("esp", "Visuals", "Toggle the ESP overlay.", "/esp [on|off]", function(_raw: string, args: { string }, _source: string)
            local enabled = state:Get("ESP.Enabled") == true
            local desired = parseOnOff(args, enabled)
            local ok, message = state:Set("ESP.Enabled", desired)
            return ok, if ok then if desired then "ESP enabled" else "ESP disabled" else message or "ESP toggle failed"
        end)

        self:Register("menu", "Utility", "Toggle the B0Xaz menu.", "/menu [on|off]", function(_raw: string, args: { string }, _source: string)
            local visible = state:Get("Settings.MenuVisible") ~= false
            local desired = parseOnOff(args, visible)
            local ok, message = state:Set("Settings.MenuVisible", desired)
            return ok, if ok then if desired then "Menu opened" else "Menu hidden" else message or "Menu toggle failed"
        end)

        self:Register("status", "Utility", "Print key feature states.", "/status", function(_raw: string, _args: { string }, _source: string)
            local pairs = {
                { "Aimbot", state:Get("Aimbot.Enabled") == true }, { "ESP", state:Get("ESP.Enabled") == true },
                { "Flight", state:Get("Movement.FlyEnabled") == true }, { "Menu", state:Get("Settings.MenuVisible") ~= false },
            }
            local output = {}
            for _, item in ipairs(pairs) do table.insert(output, `{item[1]}={if item[2] then "on" else "off"}`) end
            return true, table.concat(output, ", ")
        end)

        self:Register("fullbright", "Visuals", "Toggle fullbright mode.", "/fullbright [on|off]", function(_raw: string, args: { string }, _source: string)
            local enabled = state:Get("Visuals.Fullbright") == true
            local desired = parseOnOff(args, enabled)
            local ok, message = state:Set("Visuals.Fullbright", desired)
            return ok, if ok then if desired then "Fullbright enabled" else "Fullbright disabled" else message or "Fullbright toggle failed"
        end)

        self:Register("lighting", "Visuals", "Set the lighting mode.", "/lighting <off|day|night|dynamic>", function(_raw: string, args: { string }, _source: string)
            if #args < 1 then return false, "Usage: /lighting <off|day|night|dynamic>" end
            local mapping = { off = "Off", day = "Static Day", night = "Static Night", dynamic = "Dynamic" }
            local mode = mapping[args[1]:lower()]
            if not mode then return false, "Usage: /lighting <off|day|night|dynamic>" end
            local ok, message = services:Get("LightingService"):SetMode(mode)
            return ok, if ok then `Lighting mode set to {mode}` else message or "Lighting update failed"
        end)

        self:Register("rejoin", "Utility", "Rejoin the current server.", "/rejoin", function(_raw: string, _args: { string }, _source: string)
            local ok, message = services:Get("HotkeyService"):Rejoin()
            return ok, message or "Rejoining..."
        end)

        self:Register("serverhop", "Utility", "Find another public server.", "/serverhop", function(_raw: string, _args: { string }, _source: string)
            local ok, message = services:Get("HotkeyService"):ServerHop()
            return ok, message or "Server hopping..."
        end)

        self:Register("unload", "Utility", "Unload and restore the current session.", "/unload", function(_raw: string, _args: { string }, _source: string)
            local env = services:Get("Environment")
            if type(env.Globals) ~= "table" or type(env.Globals.B0XazUnload) ~= "function" then
                return false, "Unload API is unavailable in this environment"
            end
            env.Globals.B0XazUnload()
            return true, "Session unload requested"
        end)

        self:Register("relaunch", "Utility", "Relaunch the current build.", "/relaunch", function(_raw: string, _args: { string }, _source: string)
            local env = services:Get("Environment")
            if type(env.Globals) ~= "table" or type(env.Globals.B0XazRelaunch) ~= "function" then
                return false, "Relaunch API is unavailable in this environment"
            end
            env.Globals.B0XazRelaunch()
            return true, "Relaunch requested"
        end)

        self:Register("spectate", "Players", "Spectate a player by name.", "/spectate <player>", function(_raw: string, args: { string }, _source: string)
            if #args < 1 then return false, "Usage: /spectate <player>" end
            local target = services:Get("PlayerTracker"):GetPlayerByName(args[1])
            if not target then return false, `Player '{args[1]}' was not found` end
            local ok, message = services:Get("PlayerTracker"):StartSpectate(target)
            return ok, message or `Spectating {target.Name}`
        end)

        self:Register("stopspectate", "Players", "Stop spectating the current target.", "/stopspectate", function(_raw: string, _args: { string }, _source: string)
            services:Get("PlayerTracker"):StopSpectate()
            return true, "Spectate stopped"
        end)

        self:Register("whitelist", "Players", "Manage the shared player whitelist.", "/whitelist <add|remove|clear> <player>", function(_raw: string, args: { string }, _source: string)
            local tracker = services:Get("PlayerTracker")
            if #args < 1 then return false, "Usage: /whitelist <add|remove|clear> <player>" end
            local action = args[1]:lower()
            if action == "clear" then
                local ok, message = state:Set("Settings.Whitelist", {})
                return ok, if ok then "Whitelist cleared" else message or "Whitelist clear failed"
            end
            if #args < 2 then return false, "Usage: /whitelist <add|remove|clear> <player>" end
            local target = tracker:GetPlayerByName(args[2])
            if not target then return false, `Player '{args[2]}' was not found` end
            if action == "add" then
                return tracker:AddWhitelist(target)
            elseif action == "remove" then
                return tracker:RemoveWhitelist(target)
            end
            return false, "Usage: /whitelist <add|remove|clear> <player>"
        end)

        self:Register("clear", "Utility", "Clear the recent command log.", "/clear", function(_raw: string, _args: { string }, _source: string)
            table.clear(self._history)
            return true, "Command history cleared"
        end)

        self:Register("profile", "Settings", "Load or save a profile.", "/profile load <name> | /profile save <name>", function(raw: string, args: { string }, _source: string)
            if #args < 2 then return false, "Usage: /profile load <name> or /profile save <name>" end
            local action = args[1]:lower()
            local name = args[2]
            if action == "load" then
                local config = services:Get("ConfigService")
                local ok, message = config:Load(name)
                return ok, message or `Loaded {name}`
            elseif action == "save" then
                local config = services:Get("ConfigService")
                local ok, message = config:Save(name)
                return ok, message or `Saved {name}`
            else
                return false, "Usage: /profile load <name> or /profile save <name>"
            end
        end)

        self:Register("tp", "Players", "Teleport to a nearby or selected player by name.", "/tp <player>", function(_raw: string, args: { string }, _source: string)
            if #args < 1 then return false, "Usage: /tp <player>" end
            local player = services:Get("PlayerTracker"):GetPlayerByName(args[1])
            if not player then return false, `Player '{args[1]}' was not found` end
            local ok, message = services:Get("LocomotionService"):TeleportToPlayer(player)
            return ok, if ok then `Teleported to {player.Name}` else tostring(message)
        end)
    end

    function CommandService:Initialize()
        if self._initialized then return end
        self._initialized = true
        self:BuildDefaultCommands()

        local player = Players.LocalPlayer
        if player then
            scope:Connect(player.Chatted, function(message: string)
                self:HandleChat(message)
            end)
        else
            scope:Connect(Players.PlayerAdded, function(candidate: Player)
                if candidate == Players.LocalPlayer then
                    scope:Connect(candidate.Chatted, function(message: string)
                        self:HandleChat(message)
                    end)
                end
            end)
        end
    end

    function CommandService:Destroy() scope:Dispose() end

    return CommandService
end
