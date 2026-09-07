--!nonstrict
local MAX_JSON_BYTES: number = 1024 * 1024

return function(services: any): any
    local environment, state = services:Get("Environment"), services:Get("StateStore")
    local bus, scope = services:Get("EventBus"), services:Get("Disposer"):CreateChild("ConfigService")
    local http = game:GetService("HttpService")
    local ConfigService = { Dirty = false, _isLoading = false, _initialized = false, _activeProfile = "Default" }

    local function serialize(value: any, depth: number?): any
        local level = depth or 0
        assert(level < 40, "Config nesting limit exceeded")
        local kind = typeof(value)
        if kind == "Color3" then return { __type = "Color3", r = value.R, g = value.G, b = value.B } end
        if kind == "EnumItem" then return { __type = "EnumItem", enum = tostring(value.EnumType):gsub("^Enum%.", ""), name = value.Name } end
        if type(value) ~= "table" then return value end
        local result = {}
        for key, child in pairs(value) do result[key] = serialize(child, level + 1) end
        return result
    end
    local function deserialize(value: any, depth: number?): any
        local level = depth or 0
        assert(level < 40, "Config nesting limit exceeded")
        if type(value) ~= "table" then return value end
        if value.__type == "Color3" then
            for _, key in ipairs({ "r", "g", "b" }) do
                assert(type(value[key]) == "number" and value[key] == value[key] and math.abs(value[key]) < math.huge, "Invalid Color3")
            end
            return Color3.new(math.clamp(value.r, 0, 1), math.clamp(value.g, 0, 1), math.clamp(value.b, 0, 1))
        elseif value.__type == "EnumItem" then
            local name = tostring(value.enum):gsub("^Enum%.", "")
            local ok, item = pcall(function() return (Enum :: any)[name][value.name] end)
            assert(ok and typeof(item) == "EnumItem", "Invalid EnumItem")
            return item
        end
        local result = {}
        for key, child in pairs(value) do result[key] = deserialize(child, level + 1) end
        return result
    end
    local function decode(json: string): any
        assert(#json <= MAX_JSON_BYTES, "Config exceeds the 1 MiB safety limit")
        local value = http:JSONDecode(json)
        assert(type(value) == "table", "Config must be a JSON object")
        if value.Format == 1 then assert(type(value.Settings) == "table", "Config is missing Settings"); value = value.Settings end
        return deserialize(value)
    end
    local function encode(snapshot: any): string
        return http:JSONEncode({ Format = 1, Version = services.Version, Settings = serialize(snapshot) })
    end
    local function sanitize(name: string): string
        return (tostring(name):gsub('[/\\%.:%*%?<>|"%z\1-\31\127]', ""):gsub("^%s+", ""):gsub("%s+$", "")):sub(1, 64)
    end
    local function pathFor(name: string): (string?, string)
        name = sanitize(name)
        if name == "" or name:sub(1, 1) == "_" then return nil, "Choose a non-empty profile name that does not start with '_'" end
        if string.lower(name) == "default" then return nil, "Default is a read-only pseudo-profile" end
        return "Configs/" .. name .. ".json", name
    end
    local function hydrate(snapshot: any)
        ConfigService._isLoading = true
        local ok, err = pcall(function() state:LoadSettingsSnapshot(snapshot) end)
        ConfigService._isLoading = false
        if not ok then error(err) end
        ConfigService.Dirty = false
    end

    function ConfigService:SanitizeName(name: string): string return sanitize(name) end
    function ConfigService:Save(name: string): (boolean, string)
        local path, clean = pathFor(name)
        if not path then return false, clean end
        local ok, json = pcall(encode, state:GetSettingsSnapshot())
        if not ok then return false, tostring(json) end
        local written, message = environment:WriteFile(path, json)
        if written then self._activeProfile = clean; bus:Publish("ProfilesChanged") end
        return written, message or ("Saved " .. clean)
    end
    function ConfigService:Load(name: string): (boolean, string)
        if string.lower(sanitize(name)) == "default" then
            hydrate(state:GetDefaultSettings()); self._activeProfile = "Default"
            return true, "Loaded fresh defaults"
        end
        local path, clean = pathFor(name)
        if not path then return false, clean end
        local raw, readError = environment:ReadFile(path)
        if not raw then return false, readError or "Profile not found" end
        local ok, snapshot = pcall(decode, raw)
        if not ok then return false, "Invalid profile: " .. tostring(snapshot) end
        hydrate(snapshot); self._activeProfile = clean
        return true, "Loaded " .. clean
    end
    function ConfigService:Delete(name: string): (boolean, string)
        local path, clean = pathFor(name)
        if not path then return false, clean end
        local ok, message = environment:DeleteFile(path)
        if ok then bus:Publish("ProfilesChanged") end
        return ok, message or ("Deleted " .. clean)
    end
    function ConfigService:ListProfiles(): { string }
        local names, seen = {}, {}
        for _, file in ipairs(environment:ListFiles("Configs")) do
            local name = file:match("([^/]+)%.json$")
            if name and name:sub(1, 1) ~= "_" and string.lower(name) ~= "default" and not seen[name] then
                table.insert(names, name); seen[name] = true
            end
        end
        table.sort(names, function(a: string, b: string) return a:lower() < b:lower() end)
        table.insert(names, 1, "Default")
        return names
    end
    function ConfigService:ProfileExists(name: string): boolean
        if string.lower(sanitize(name)) == "default" then return true end
        local path = pathFor(name)
        return path ~= nil and environment:ReadFile(path) ~= nil
    end
    function ConfigService:Export(): (string?, string?)
        local ok, json = pcall(encode, state:GetSettingsSnapshot())
        if not ok then return nil, tostring(json) end
        local copied, message = environment:SetClipboard(json)
        return json, if copied then "Copied config JSON" else message
    end
    function ConfigService:Import(json: string?): (boolean, string)
        if not json or json:match("^%s*$") then json = environment:GetClipboard() end
        if not json then return false, "Clipboard reading is unavailable; paste JSON into the editor" end
        local ok, snapshot = pcall(decode, json)
        if not ok then return false, "Invalid config JSON: " .. tostring(snapshot) end
        hydrate(snapshot); self._activeProfile = "Imported"
        return true, "Imported config"
    end
    function ConfigService:ReadRawAutoload(): any?
        local raw = environment:ReadFile("Configs/_autoload.json")
        if not raw then return nil end
        local ok, snapshot = pcall(decode, raw)
        return if ok then snapshot else nil
    end
    function ConfigService:Flush(): (boolean, string?)
        local ok, json = pcall(encode, state:GetSettingsSnapshot())
        if not ok then return false, tostring(json) end
        local written, message = environment:WriteFile("Configs/_autoload.json", json)
        if written then self.Dirty = false end
        return written, message
    end
    function ConfigService:ApplyLaunchState(): string
        local raw = self:ReadRawAutoload()
        local preferences = if type(raw) == "table" and type(raw.Settings) == "table" then raw.Settings else {}
        local startup = if type(preferences.StartupProfile) == "string" then preferences.StartupProfile else ""
        if preferences.RestoreOnLaunch == false then
            local defaults = state:GetDefaultSettings()
            defaults.Settings.RestoreOnLaunch, defaults.Settings.StartupProfile = false, startup
            hydrate(defaults)
            self:Flush()
            return "disabled"
        end
        if startup ~= "" and self:ProfileExists(startup) then
            local loaded = self:Load(startup)
            if loaded then
                -- Profile contents must not unpin the launch selector that selected them.
                local current = state:GetSettingsSnapshot()
                current.Settings.RestoreOnLaunch, current.Settings.StartupProfile = true, startup
                hydrate(current)
                return "profile:" .. startup
            end
        end
        if raw then hydrate(raw); self._activeProfile = "Autosaved session"; return "autoload" end
        hydrate(state:GetDefaultSettings())
        return "defaults"
    end
    function ConfigService:PinStartupProfile(name: string): (boolean, string)
        if not self:ProfileExists(name) then return false, "Save the profile before pinning it" end
        state:Set("Settings.StartupProfile", sanitize(name))
        self.Dirty = true
        self:Flush()
        return true, "Pinned " .. sanitize(name) .. " for launch"
    end
    function ConfigService:GetActiveProfile(): string return self._activeProfile end
    function ConfigService:Initialize()
        if self._initialized then return end
        self._initialized = true
        scope:Add(bus:Subscribe("StateChanged", function(_path: string, _new: any, _old: any, metadata: any)
            -- Events are spawned: the hydration marker travels with the event, not only a short-lived guard.
            if not ConfigService._isLoading and not (metadata and metadata.Hydrating) then ConfigService.Dirty = true end
        end))
        scope:Spawn(function()
            while not scope:IsDisposed() do
                task.wait(1.5)
                if not scope:IsDisposed() and ConfigService.Dirty and not ConfigService._isLoading then ConfigService:Flush() end
            end
        end)
    end
    function ConfigService:Destroy() scope:Dispose() end
    scope:Add(function() if ConfigService.Dirty and ConfigService._initialized then ConfigService:Flush() end end)
    return ConfigService
end
