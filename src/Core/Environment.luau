--!nonstrict
local ROOT: string = "B0XazUniversal/"
local ALPHABET: string = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

return function(disposer: any): any
    local scope = disposer:CreateChild("Environment")
    local runtime: any = getfenv(0)
    local function probe(name: string): any
        local ok, value = pcall(function() return runtime[name] end)
        return if ok then value else nil
    end
    local function member(object: any, name: string): any
        local ok, value = pcall(function() return object[name] end)
        return if ok then value else nil
    end
    local getGlobal = probe("getgenv")
    local globals: any = _G
    if type(getGlobal) == "function" then
        local ok, value = pcall(getGlobal)
        if ok and type(value) == "table" then globals = value end
    end
    local syn, fluxus, http, crypt = probe("syn"), probe("fluxus"), probe("http"), probe("crypt")
    local function first(...: any): any
        for index = 1, select("#", ...) do
            local candidate = select(index, ...)
            if type(candidate) == "function" then return candidate end
        end
        return nil
    end
    -- Keep references, not repeated lookups: capability identity is fixed for the lifetime of a session.
    local getHui = first(probe("gethui"))
    local write, read, exists = first(probe("writefile")), first(probe("readfile")), first(probe("isfile"))
    local list, mkdir, delete = first(probe("listfiles")), first(probe("makefolder")), first(probe("delfile"))
    local move = first(probe("mousemoverel"))
    local clipSet, clipGet = first(probe("setclipboard")), first(probe("getclipboard"))
    local queue = first(probe("queue_on_teleport"), member(syn, "queue_on_teleport"), member(fluxus, "queue_on_teleport"))
    local fps = first(probe("setfpscap"), probe("set_fps_cap"), probe("setfps"))
    local click = first(probe("mouse1click"))
    local requestFn = first(probe("request"), probe("http_request"), member(syn, "request"), member(http, "request"))
    local drawingNew = first(member(probe("Drawing"), "new"))
    local drawing = if drawingNew then { new = drawingNew } else nil
    local nativeEncode = first(member(crypt, "base64encode"), member(crypt, "base64_encode"), member(member(crypt, "base64"), "encode"))
    local nativeDecode = first(member(crypt, "base64decode"), member(crypt, "base64_decode"), member(member(crypt, "base64"), "decode"))
    local consoleClear = { probe("rconsoleclear"), probe("consoleclear"), probe("clearconsole"), probe("clearoutput") }
    local httpService = game:GetService("HttpService")
    local players = game:GetService("Players")
    local input = game:GetService("UserInputService")
    local keyLookup: { [string]: any } = {}
    for _, enumType in ipairs({ Enum.KeyCode, Enum.UserInputType }) do
        for _, item in ipairs(enumType:GetEnumItems()) do
            keyLookup[string.lower(item.Name)] = item
            keyLookup[string.lower(tostring(item))] = item
            keyLookup[string.lower(tostring(enumType) .. "." .. item.Name)] = item
        end
    end
    keyLookup.mb1, keyLookup.mb2, keyLookup.mb3 = Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseButton3
    keyLookup.none, keyLookup.unbound = Enum.KeyCode.Unknown, Enum.KeyCode.Unknown
    local cachedParent: Instance? = nil
    local deviceId: string? = nil
    local virtualInput: any = nil
    pcall(function() virtualInput = game:GetService("VirtualInputManager") end)
    local mousePressed = false
    local Environment = {
        Globals = globals, Root = ROOT, Drawing = drawing,
        Capabilities = table.freeze({
            Files = write ~= nil and read ~= nil, WriteFile = write ~= nil, ReadFile = read ~= nil,
            ListFiles = list ~= nil, DeleteFile = delete ~= nil, MouseMove = move ~= nil,
            ClipboardWrite = clipSet ~= nil, ClipboardRead = clipGet ~= nil,
            QueueTeleport = queue ~= nil, FpsCap = fps ~= nil, NativeClick = click ~= nil,
            Drawing = type(drawing) == "table" and type(drawing.new) == "function",
        }),
    }

    local function safePath(path: string): string?
        path = tostring(path):gsub("\\", "/"):gsub("^/+", "")
        if path:sub(1, #ROOT) == ROOT then path = path:sub(#ROOT + 1) end
        if path == "" or path:find("[%z\1-\31:*?<>|\"]") then return nil end
        for segment in path:gmatch("[^/]+") do if segment == ".." or segment == "." then return nil end end
        return ROOT .. path
    end

    if mkdir then pcall(mkdir, ROOT:sub(1, -2)); pcall(mkdir, ROOT .. "Configs") end

    function Environment:WriteFile(path: string, data: string): (boolean, string?)
        local resolved = safePath(path)
        if not resolved then return false, "Unsafe file path" end
        if not write then return false, "This executor cannot write files" end
        local ok, err = pcall(write, resolved, data)
        return ok, if ok then nil else tostring(err)
    end
    function Environment:ReadFile(path: string): (string?, string?)
        local resolved = safePath(path)
        if not resolved then return nil, "Unsafe file path" end
        if not read then return nil, "This executor cannot read files" end
        if exists then
            local ok, present = pcall(exists, resolved)
            if ok and not present then return nil, "File not found" end
        end
        local ok, data = pcall(read, resolved)
        if ok and type(data) == "string" then return data, nil end
        return nil, tostring(data)
    end
    function Environment:ListFiles(path: string?): { string }
        local resolved = safePath(path or "Configs")
        if not list or not resolved then return {} end
        local ok, results = pcall(list, resolved)
        if not ok or type(results) ~= "table" then return {} end
        local files = {}
        for _, file in ipairs(results) do
            if type(file) == "string" then
                local normalized = file:gsub("\\", "/")
                local start = normalized:find(ROOT, 1, true)
                if start then normalized = normalized:sub(start + #ROOT) end
                if safePath(normalized) then table.insert(files, normalized) end
            end
        end
        return files
    end
    function Environment:DeleteFile(path: string): (boolean, string?)
        local resolved = safePath(path)
        if not resolved then return false, "Unsafe file path" end
        if not delete then return false, "This executor cannot delete files" end
        local ok, err = pcall(delete, resolved)
        return ok, if ok then nil else tostring(err)
    end

    function Environment:GetSafeGuiParent(): Instance?
        if cachedParent then
            local ok, parent = pcall(function() return cachedParent.Parent end)
            if ok and parent ~= nil then return cachedParent end
            cachedParent = nil
        end
        local candidates = {}
        if getHui then local ok, parent = pcall(getHui); if ok and typeof(parent) == "Instance" then table.insert(candidates, parent) end end
        pcall(function() table.insert(candidates, game:GetService("CoreGui")) end)
        if players.LocalPlayer then
            local parent = players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if parent then table.insert(candidates, parent) end
        end
        for _, parent in ipairs(candidates) do
            local folder = Instance.new("Folder")
            local ok = pcall(function() folder.Parent = parent end)
            folder:Destroy()
            if ok then cachedParent = parent; return parent end
        end
        return nil
    end

    function Environment:GetDeviceId(): string
        if deviceId then return deviceId end
        local raw = self:ReadFile("_device.json")
        if raw then
            local ok, data = pcall(httpService.JSONDecode, httpService, raw)
            local id = if ok and type(data) == "table" then data.Id else if ok then data else nil
            if type(id) == "string" and #id >= 16 then deviceId = id; return id end
        end
        local cached = globals.B0XazDeviceId
        if type(cached) == "string" and #cached >= 16 then deviceId = cached end
        if not deviceId then
            local ok, id = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
            if ok and type(id) == "string" and #id >= 16 then deviceId = id end
        end
        if not deviceId then deviceId = httpService:GenerateGUID(false) end
        globals.B0XazDeviceId = deviceId
        self:WriteFile("_device.json", httpService:JSONEncode({ Id = deviceId }))
        return deviceId :: string
    end

    function Environment:Base64Encode(data: string): string
        if nativeEncode then local ok, result = pcall(nativeEncode, data); if ok and type(result) == "string" then return result end end
        local output = {}
        for index = 1, #data, 3 do
            local a, b, c = string.byte(data, index, index + 2)
            local value = a * 65536 + (b or 0) * 256 + (c or 0)
            local x = math.floor(value / 262144) % 64
            local y = math.floor(value / 4096) % 64
            local z = math.floor(value / 64) % 64
            table.insert(output, ALPHABET:sub(x + 1, x + 1) .. ALPHABET:sub(y + 1, y + 1)
                .. (if b then ALPHABET:sub(z + 1, z + 1) else "=")
                .. (if c then ALPHABET:sub(value % 64 + 1, value % 64 + 1) else "="))
        end
        return table.concat(output)
    end

    local decodeLookup = {}
    for index = 1, #ALPHABET do decodeLookup[ALPHABET:sub(index, index)] = index - 1 end
    function Environment:Base64Decode(data: string): string
        data = data:gsub("%s", "")
        assert(#data % 4 == 0 and not data:find("[^%w+/=]"), "Invalid base64")
        local output = {}
        for index = 1, #data, 4 do
            local a, b, c, d = data:sub(index, index), data:sub(index + 1, index + 1), data:sub(index + 2, index + 2), data:sub(index + 3, index + 3)
            assert(decodeLookup[a] ~= nil and decodeLookup[b] ~= nil, "Invalid base64 quartet")
            assert((c ~= "=" or d == "=") and (index + 3 == #data or (c ~= "=" and d ~= "=")), "Invalid base64 padding")
            local cv, dv = if c == "=" then 0 else decodeLookup[c], if d == "=" then 0 else decodeLookup[d]
            assert(cv ~= nil and dv ~= nil, "Invalid base64 alphabet")
            local value = decodeLookup[a] * 262144 + decodeLookup[b] * 4096 + cv * 64 + dv
            table.insert(output, string.char(math.floor(value / 65536) % 256))
            if c ~= "=" then table.insert(output, string.char(math.floor(value / 256) % 256)) end
            if d ~= "=" then table.insert(output, string.char(value % 256)) end
        end
        -- Validate with the fallback first; permissive native decoders otherwise accept corrupt saved keys.
        if nativeDecode then local ok, result = pcall(nativeDecode, data); if ok and type(result) == "string" then return result end end
        return table.concat(output)
    end

    function Environment:XorCipher(data: string, key: string): string
        assert(#key > 0, "XOR key cannot be empty")
        local output = table.create(#data)
        for index = 1, #data do output[index] = string.char(bit32.bxor(data:byte(index), key:byte((index - 1) % #key + 1))) end
        return table.concat(output)
    end
    function Environment:MouseMove(x: number, y: number): boolean
        if not move then return false end
        return pcall(move, math.round(x), math.round(y))
    end
    function Environment:SetClipboard(text: string): (boolean, string?)
        if not clipSet then return false, "Clipboard writing is unavailable" end
        local ok, err = pcall(clipSet, text)
        return ok, if ok then nil else tostring(err)
    end
    function Environment:GetClipboard(): string?
        if not clipGet then return nil end
        local ok, text = pcall(clipGet)
        return if ok and type(text) == "string" then text else nil
    end
    function Environment:QueueTeleport(source: string): boolean
        if not queue then return false end
        return pcall(queue, source)
    end
    function Environment:HasFpsCap(): boolean return fps ~= nil end
    function Environment:SetFpsCap(value: number): boolean
        if not fps then return false end
        -- 0 is the executor convention for uncapped; preserve it rather than clamping it to one.
        return pcall(fps, if value == 0 then 0 else math.clamp(math.round(value), 15, 1000))
    end
    function Environment:IsMobile(): boolean return input.TouchEnabled and not input.KeyboardEnabled end
    function Environment:ParseKeybind(value: any): EnumItem?
        if typeof(value) == "EnumItem" then
            if value.EnumType == Enum.KeyCode or value.EnumType == Enum.UserInputType then return value end
            return nil
        end
        if type(value) == "table" and value.__type == "EnumItem" then value = "Enum." .. tostring(value.enum):gsub("^Enum%.", "") .. "." .. tostring(value.name) end
        if type(value) ~= "string" then return nil end
        return keyLookup[string.lower((value:gsub("^%s+", ""):gsub("%s+$", "")))]
    end
    function Environment:FormatKeybindName(value: any): string
        local item = self:ParseKeybind(value)
        if not item or item == Enum.KeyCode.Unknown then return "Unbound" end
        if item == Enum.UserInputType.MouseButton1 then return "MB1" end
        if item == Enum.UserInputType.MouseButton2 then return "MB2" end
        if item == Enum.UserInputType.MouseButton3 then return "MB3" end
        return item.Name
    end
    function Environment:MatchesInput(event: InputObject, value: any): boolean
        local item = self:ParseKeybind(value)
        return item ~= nil and item ~= Enum.KeyCode.Unknown and (event.KeyCode == item or event.UserInputType == item)
    end
    function Environment:GetGuiInset(): Vector2
        local ok, inset = pcall(function() return game:GetService("GuiService"):GetGuiInset() end)
        return if ok then inset else Vector2.zero
    end
    function Environment:GetAimPoint(camera: Camera): Vector2
        return if self:IsMobile() then camera.ViewportSize / 2 else input:GetMouseLocation() - self:GetGuiInset()
    end
    function Environment:Request(options: any): (any?, string?)
        local ok, result = pcall(function()
            if requestFn then return requestFn(options) end
            return httpService:RequestAsync(options)
        end)
        if not ok or type(result) ~= "table" then return nil, tostring(result) end
        return result, nil
    end
    function Environment:MouseClick(): boolean
        if click then return pcall(click) end
        if not virtualInput or mousePressed then return false end
        local point = input:GetMouseLocation()
        local ok = pcall(function() virtualInput:SendMouseButtonEvent(point.X, point.Y, 0, true, game, 0) end)
        if not ok then return false end
        mousePressed = true
        scope:Delay(0.03, function()
            -- Leave the flag armed if release throws, so unload still makes a final release attempt.
            virtualInput:SendMouseButtonEvent(point.X, point.Y, 0, false, game, 0)
            mousePressed = false
        end)
        return true
    end
    function Environment:ClearConsole()
        for index = 1, 4 do
            local fn = consoleClear[index]
            if type(fn) == "function" and pcall(fn) then return end
        end
    end
    function Environment:Destroy() scope:Dispose() end
    scope:Add(function()
        if mousePressed and virtualInput then
            mousePressed = false
            pcall(function() virtualInput:SendMouseButtonEvent(0, 0, 0, false, game, 0) end)
        end
        if fps then pcall(fps, 0) end
    end)
    return Environment
end
