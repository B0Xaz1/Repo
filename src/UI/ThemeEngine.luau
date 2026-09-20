local CONFIG = table.freeze({
    ATTRIBUTE_PREFIX = "B0XazTheme_",
    ACCENT_DARK_BLEND = 0.4,
    ACCENT_DIM_BLEND = 0.76,
    FALLBACK_SUCCESS = Color3.fromRGB(106, 220, 169),
    FALLBACK_DANGER = Color3.fromRGB(248, 109, 137),
    FALLBACK_WARNING = Color3.fromRGB(244, 193, 111),
    TOKEN_NAMES = { "Bg", "Panel", "Elem", "ElemHover", "Side", "Accent", "AccentDark", "AccentDim", "Text", "TextDim", "TextMuted",
        "Border", "BorderDim", "ToggleOn", "ToggleOff", "Success", "Danger", "Warning" },
    PRESET_NAMES = { "Midnight", "Graphite", "Ocean", "Rose", "Forest", "Paper" },
    COLOR_PROPERTIES = { "BackgroundColor3", "TextColor3", "ImageColor3", "Color", "ScrollBarImageColor3", "PlaceholderColor3" },
    PRESET_SPECS = {
        Midnight = {
            Bg = Color3.fromRGB(4, 4, 6), Panel = Color3.fromRGB(9, 9, 12), Elem = Color3.fromRGB(15, 15, 19), ElemHover = Color3.fromRGB(24, 24, 29),
            Side = Color3.fromRGB(2, 2, 3), Accent = Color3.fromRGB(0, 220, 235), Text = Color3.fromRGB(236, 236, 240), TextDim = Color3.fromRGB(160, 166, 174),
            TextMuted = Color3.fromRGB(112, 116, 124), Border = Color3.fromRGB(28, 31, 38), BorderDim = Color3.fromRGB(20, 22, 27), ToggleOff = Color3.fromRGB(24, 24, 29),
        },
        Graphite = {
            Bg = Color3.fromRGB(28, 28, 30), Panel = Color3.fromRGB(38, 38, 42), Elem = Color3.fromRGB(50, 50, 56), ElemHover = Color3.fromRGB(64, 64, 72),
            Side = Color3.fromRGB(22, 22, 24), Accent = Color3.fromRGB(198, 204, 220), Text = Color3.fromRGB(236, 236, 240), TextDim = Color3.fromRGB(176, 178, 186),
            TextMuted = Color3.fromRGB(120, 122, 130), Border = Color3.fromRGB(72, 72, 80), BorderDim = Color3.fromRGB(56, 56, 62), ToggleOff = Color3.fromRGB(58, 58, 64),
        },
        Ocean = {
            Bg = Color3.fromRGB(8, 18, 32), Panel = Color3.fromRGB(12, 28, 48), Elem = Color3.fromRGB(16, 40, 64), ElemHover = Color3.fromRGB(22, 54, 84),
            Side = Color3.fromRGB(6, 14, 26), Accent = Color3.fromRGB(64, 196, 230), Text = Color3.fromRGB(220, 236, 248), TextDim = Color3.fromRGB(140, 176, 198),
            TextMuted = Color3.fromRGB(84, 122, 148), Border = Color3.fromRGB(28, 64, 92), BorderDim = Color3.fromRGB(18, 42, 64), ToggleOff = Color3.fromRGB(20, 46, 68),
        },
        Rose = {
            Bg = Color3.fromRGB(24, 12, 18), Panel = Color3.fromRGB(36, 18, 28), Elem = Color3.fromRGB(52, 26, 40), ElemHover = Color3.fromRGB(70, 34, 52),
            Side = Color3.fromRGB(18, 8, 14), Accent = Color3.fromRGB(236, 128, 168), Text = Color3.fromRGB(246, 226, 234), TextDim = Color3.fromRGB(196, 150, 168),
            TextMuted = Color3.fromRGB(140, 96, 112), Border = Color3.fromRGB(84, 40, 58), BorderDim = Color3.fromRGB(58, 28, 40), ToggleOff = Color3.fromRGB(58, 30, 42),
        },
        Forest = {
            Bg = Color3.fromRGB(12, 20, 16), Panel = Color3.fromRGB(18, 30, 24), Elem = Color3.fromRGB(26, 42, 34), ElemHover = Color3.fromRGB(34, 56, 44),
            Side = Color3.fromRGB(8, 14, 10), Accent = Color3.fromRGB(120, 196, 148), Text = Color3.fromRGB(226, 238, 230), TextDim = Color3.fromRGB(156, 184, 166),
            TextMuted = Color3.fromRGB(96, 124, 108), Border = Color3.fromRGB(40, 64, 50), BorderDim = Color3.fromRGB(28, 44, 34), ToggleOff = Color3.fromRGB(32, 48, 38),
        },
        Paper = {
            Bg = Color3.fromRGB(236, 239, 247), Panel = Color3.fromRGB(249, 250, 255), Elem = Color3.fromRGB(228, 233, 244), ElemHover = Color3.fromRGB(214, 223, 240),
            Side = Color3.fromRGB(219, 225, 238), Accent = Color3.fromRGB(75, 101, 213), Text = Color3.fromRGB(24, 32, 52), TextDim = Color3.fromRGB(64, 78, 105),
            TextMuted = Color3.fromRGB(98, 113, 143), Border = Color3.fromRGB(183, 195, 218), BorderDim = Color3.fromRGB(210, 218, 233), ToggleOff = Color3.fromRGB(210, 216, 230),
        },
    },
})

local function deriveAccentTones(color: Color3): (Color3, Color3)
    return color:Lerp(Color3.new(0, 0, 0), CONFIG.ACCENT_DARK_BLEND), color:Lerp(Color3.new(0, 0, 0), CONFIG.ACCENT_DIM_BLEND)
end

local function finishPreset(spec: any): any
    local palette = {}
    for _, token in ipairs(CONFIG.TOKEN_NAMES) do palette[token] = spec[token] end
    palette.AccentDark, palette.AccentDim = deriveAccentTones(spec.Accent)
    if not spec.ToggleOn then palette.ToggleOn = spec.Accent end
    if not spec.Success then palette.Success = CONFIG.FALLBACK_SUCCESS end
    if not spec.Danger then palette.Danger = CONFIG.FALLBACK_DANGER end
    if not spec.Warning then palette.Warning = CONFIG.FALLBACK_WARNING end
    return palette
end

return function(services: any): any
    local state, bus = services:Get("StateStore"), services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("ThemeEngine")
    local ThemeEngine = { _palette = {}, _bindings = setmetatable({}, { __mode = "k" }), _roots = setmetatable({}, { __mode = "k" }), _initialized = false }

    local presets: any = {}
    for _, name in ipairs(CONFIG.PRESET_NAMES) do presets[name] = finishPreset(CONFIG.PRESET_SPECS[name]) end
    ThemeEngine._palette = table.clone(presets.Midnight)

    function ThemeEngine:DeriveAccentTones(color: Color3): (Color3, Color3)
        return deriveAccentTones(color)
    end

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
        pcall(function() instance:SetAttribute(CONFIG.ATTRIBUTE_PREFIX .. property, token) end)
    end

    -- Instances that were colored by the previous palette but never bound are re-tagged by
    -- matching their old color, so a preset change still reaches them
    local function refreshUnbound(previous: any)
        local reverse = {}
        for _, token in ipairs(CONFIG.TOKEN_NAMES) do
            local key = colorKey(previous[token])
            if not reverse[key] then reverse[key] = token end
        end
        for root in pairs(ThemeEngine._roots) do
            local ok, descendants = pcall(function() return root:GetDescendants() end)
            if not ok then ThemeEngine._roots[root] = nil; continue end
            table.insert(descendants, root)
            for _, instance in ipairs(descendants) do
                for _, property in ipairs(CONFIG.COLOR_PROPERTIES) do
                    if ThemeEngine._bindings[instance] and ThemeEngine._bindings[instance][property] then continue end
                    local tagged = nil
                    pcall(function() tagged = instance:GetAttribute(CONFIG.ATTRIBUTE_PREFIX .. property) end)
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

    local function applyFromState(force: boolean?, refreshUnboundInstances: boolean?)
        local palette = table.clone(presets[state:Get("Theme.ActivePreset")] or presets.Midnight)
        local overrides = state:Get("Theme.CustomTokens") or {}
        for token, color in pairs(overrides) do if palette[token] and typeof(color) == "Color3" then palette[token] = color end end
        local previous, changed, changedTokens = ThemeEngine._palette, false, {}
        for _, token in ipairs(CONFIG.TOKEN_NAMES) do
            if previous[token] ~= palette[token] then changed, changedTokens[token] = true, true end
        end
        if force == true and not changed then
            for _, token in ipairs(CONFIG.TOKEN_NAMES) do changedTokens[token] = true end
            changed = true
        end
        if not changed then return end
        ThemeEngine._palette = palette
        ThemeEngine:UpdateAllBindings(changedTokens)
        if refreshUnboundInstances ~= false then refreshUnbound(previous) end
        bus:Publish("ThemeChanged")
    end

    function ThemeEngine:GetToken(name: string): Color3 return assert(self._palette[name], `Unknown theme token '{name}'`) end

    function ThemeEngine:GetTokenNames(): { string } return table.clone(CONFIG.TOKEN_NAMES) end

    function ThemeEngine:GetPresetNames(): { string } return table.clone(CONFIG.PRESET_NAMES) end

    function ThemeEngine:BindToken(instance: Instance, property: string, token: string): any
        assert(self._palette[token], `Unknown theme token '{token}'`)
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
        assert(self._palette[name] and typeof(color) == "Color3")
        local overrides = state:Get("Theme.CustomTokens")
        overrides[name] = color
        if name == "Accent" then
            overrides.AccentDark, overrides.AccentDim = self:DeriveAccentTones(color)
            overrides.ToggleOn = color
        end
        state:Set("Theme.CustomTokens", overrides)
        applyFromState(true)
    end

    function ThemeEngine:UpdateAllBindings(tokens: { [string]: boolean }?)
        for instance, properties in pairs(self._bindings) do
            for property, token in pairs(properties) do
                if tokens and not tokens[token] then continue end
                local applied = pcall(function() applyInstance(instance, property, token) end)
                if not applied then self._bindings[instance] = nil; break end
            end
        end
    end

    function ThemeEngine:Initialize()
        if self._initialized then return end
        self._initialized = true
        scope:Add(state:Observe("Theme.ActivePreset", function() applyFromState(true) end))
        scope:Add(state:Observe("Theme.CustomTokens", function() applyFromState(true, false) end))
        applyFromState(true)
    end

    function ThemeEngine:Destroy() scope:Dispose(); table.clear(self._bindings); table.clear(self._roots) end
    return ThemeEngine
end
