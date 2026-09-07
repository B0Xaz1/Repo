--!nonstrict
local TOKEN_NAMES = { "Bg", "Panel", "Elem", "ElemHover", "Side", "Accent", "AccentDark", "AccentDim", "Text", "TextDim", "TextMuted",
    "Border", "BorderDim", "ToggleOn", "ToggleOff", "Success", "Danger", "Warning" }
local PRESET_NAMES = { "Midnight", "Graphite", "Ocean", "Rose", "Forest", "Paper" }
local COLOR_PROPERTIES = { "BackgroundColor3", "TextColor3", "ImageColor3", "Color", "ScrollBarImageColor3", "PlaceholderColor3" }

local function rgb(r: number, g: number, b: number): Color3
    return Color3.fromRGB(r, g, b)
end

return function(services: any): any
    local state, bus = services:Get("StateStore"), services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("ThemeEngine")
    local ThemeEngine = { _palette = {}, _bindings = setmetatable({}, { __mode = "k" }), _roots = setmetatable({}, { __mode = "k" }), _initialized = false }

    function ThemeEngine:DeriveAccentTones(color: Color3): (Color3, Color3)
        return color:Lerp(Color3.new(0, 0, 0), 0.4), color:Lerp(Color3.new(0, 0, 0), 0.76)
    end
    local function finish(spec: any): any
        local palette = {}
        for _, token in ipairs(TOKEN_NAMES) do palette[token] = spec[token] end
        palette.AccentDark, palette.AccentDim = ThemeEngine:DeriveAccentTones(spec.Accent)
        if not spec.ToggleOn then palette.ToggleOn = spec.Accent end
        if not spec.Success then palette.Success = rgb(106, 220, 169) end
        if not spec.Danger then palette.Danger = rgb(248, 109, 137) end
        if not spec.Warning then palette.Warning = rgb(244, 193, 111) end
        return palette
    end
    local presets: any = {
        Midnight = finish({
            Bg = rgb(12, 12, 14), Panel = rgb(18, 18, 22), Elem = rgb(26, 26, 30), ElemHover = rgb(36, 36, 42),
            Side = rgb(10, 10, 12), Accent = rgb(0, 220, 235), Text = rgb(236, 236, 240), TextDim = rgb(160, 166, 174),
            TextMuted = rgb(112, 116, 124), Border = rgb(38, 42, 50), BorderDim = rgb(30, 32, 38), ToggleOff = rgb(36, 36, 42),
        }),
        Graphite = finish({
            Bg = rgb(28, 28, 30), Panel = rgb(38, 38, 42), Elem = rgb(50, 50, 56), ElemHover = rgb(64, 64, 72),
            Side = rgb(22, 22, 24), Accent = rgb(198, 204, 220), Text = rgb(236, 236, 240), TextDim = rgb(176, 178, 186),
            TextMuted = rgb(120, 122, 130), Border = rgb(72, 72, 80), BorderDim = rgb(56, 56, 62), ToggleOff = rgb(58, 58, 64),
        }),
        Ocean = finish({
            Bg = rgb(8, 18, 32), Panel = rgb(12, 28, 48), Elem = rgb(16, 40, 64), ElemHover = rgb(22, 54, 84),
            Side = rgb(6, 14, 26), Accent = rgb(64, 196, 230), Text = rgb(220, 236, 248), TextDim = rgb(140, 176, 198),
            TextMuted = rgb(84, 122, 148), Border = rgb(28, 64, 92), BorderDim = rgb(18, 42, 64), ToggleOff = rgb(20, 46, 68),
        }),
        Rose = finish({
            Bg = rgb(24, 12, 18), Panel = rgb(36, 18, 28), Elem = rgb(52, 26, 40), ElemHover = rgb(70, 34, 52),
            Side = rgb(18, 8, 14), Accent = rgb(236, 128, 168), Text = rgb(246, 226, 234), TextDim = rgb(196, 150, 168),
            TextMuted = rgb(140, 96, 112), Border = rgb(84, 40, 58), BorderDim = rgb(58, 28, 40), ToggleOff = rgb(58, 30, 42),
        }),
        Forest = finish({
            Bg = rgb(12, 20, 16), Panel = rgb(18, 30, 24), Elem = rgb(26, 42, 34), ElemHover = rgb(34, 56, 44),
            Side = rgb(8, 14, 10), Accent = rgb(120, 196, 148), Text = rgb(226, 238, 230), TextDim = rgb(156, 184, 166),
            TextMuted = rgb(96, 124, 108), Border = rgb(40, 64, 50), BorderDim = rgb(28, 44, 34), ToggleOff = rgb(32, 48, 38),
        }),
        Paper = finish({
            Bg = rgb(236, 239, 247), Panel = rgb(249, 250, 255), Elem = rgb(228, 233, 244), ElemHover = rgb(214, 223, 240),
            Side = rgb(219, 225, 238), Accent = rgb(75, 101, 213), Text = rgb(24, 32, 52), TextDim = rgb(64, 78, 105),
            TextMuted = rgb(98, 113, 143), Border = rgb(183, 195, 218), BorderDim = rgb(210, 218, 233), ToggleOff = rgb(210, 216, 230),
        }),
    }
    ThemeEngine._palette = table.clone(presets.Midnight)

    local function colorKey(color: Color3): string
        local ok, key = pcall(function()
            return string.format("%.3f:%.3f:%.3f", color.R, color.G, color.B)
        end)
        return if ok then key else tostring(color)
    end
    local function applyInstance(instance: Instance, property: string, token: string)
        local color = ThemeEngine._palette[token]
        if not color then return end
        pcall(function() (instance :: any)[property] = color end)
        pcall(function() instance:SetAttribute("B0XazTheme_" .. property, token) end)
    end
    local function refreshUnbound(previous: any)
        local reverse = {}
        for _, token in ipairs(TOKEN_NAMES) do
            local key = colorKey(previous[token])
            if not reverse[key] then reverse[key] = token end
        end
        for root in pairs(ThemeEngine._roots) do
            local ok, descendants = pcall(function() return root:GetDescendants() end)
            if not ok then ThemeEngine._roots[root] = nil; continue end
            table.insert(descendants, root)
            for _, instance in ipairs(descendants) do
                for _, property in ipairs(COLOR_PROPERTIES) do
                    if ThemeEngine._bindings[instance] and ThemeEngine._bindings[instance][property] then continue end
                    local tagged = nil
                    pcall(function() tagged = instance:GetAttribute("B0XazTheme_" .. property) end)
                    if type(tagged) == "string" and ThemeEngine._palette[tagged] then
                        applyInstance(instance, property, tagged)
                        continue
                    end
                    pcall(function()
                        local token = reverse[colorKey(instance[property])]
                        if token then applyInstance(instance, property, token) end
                    end)
                end
            end
        end
    end
    local function applyFromState(force: boolean?)
        local palette = table.clone(presets[state:Get("Theme.ActivePreset")] or presets.Midnight)
        local overrides = state:Get("Theme.CustomTokens") or {}
        for token, color in pairs(overrides) do if palette[token] and typeof(color) == "Color3" then palette[token] = color end end
        local previous, changed = ThemeEngine._palette, force == true
        for _, token in ipairs(TOKEN_NAMES) do if previous[token] ~= palette[token] then changed = true; break end end
        if not changed then return end
        ThemeEngine._palette = palette
        ThemeEngine:UpdateAllBindings()
        refreshUnbound(previous)
        bus:Publish("ThemeChanged")
    end
    function ThemeEngine:GetToken(name: string): Color3 return assert(self._palette[name], "Unknown theme token '" .. name .. "'") end
    function ThemeEngine:GetTokenNames(): { string } return table.clone(TOKEN_NAMES) end
    function ThemeEngine:GetPresetNames(): { string } return table.clone(PRESET_NAMES) end
    function ThemeEngine:BindToken(instance: Instance, property: string, token: string): any
        assert(self._palette[token], "Unknown theme token '" .. token .. "'")
        if not self._bindings[instance] then self._bindings[instance] = {} end
        self._bindings[instance][property] = token
        applyInstance(instance, property, token)
        return instance
    end
    function ThemeEngine:RegisterRoot(root: Instance) self._roots[root] = true end
    function ThemeEngine:SetPreset(name: string): boolean
        if not presets[name] then return false end
        state:Set("Theme.CustomTokens", {})
        state:Set("Theme.ActivePreset", name)
        applyFromState(true)
        return true
    end
    function ThemeEngine:UpdateToken(name: string, color: Color3)
        assert(self._palette[name] and typeof(color) == "Color3", "Invalid theme token update")
        local overrides = state:Get("Theme.CustomTokens")
        overrides[name] = color
        if name == "Accent" then
            overrides.AccentDark, overrides.AccentDim = self:DeriveAccentTones(color)
            overrides.ToggleOn = color
        end
        state:Set("Theme.CustomTokens", overrides)
        applyFromState(true)
    end
    function ThemeEngine:UpdateAllBindings()
        for instance, properties in pairs(self._bindings) do
            for property, token in pairs(properties) do
                local ok = pcall(function() applyInstance(instance, property, token) end)
                if not ok then self._bindings[instance] = nil; break end
            end
        end
    end
    function ThemeEngine:Initialize()
        if self._initialized then return end
        self._initialized = true
        scope:Add(state:Observe("Theme.ActivePreset", function() applyFromState(true) end))
        scope:Add(state:Observe("Theme.CustomTokens", function() applyFromState(true) end))
        applyFromState(true)
    end
    function ThemeEngine:Destroy() scope:Dispose(); table.clear(self._bindings); table.clear(self._roots) end
    return ThemeEngine
end
