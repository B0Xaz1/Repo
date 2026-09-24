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
            Bg = Color3.fromRGB(12, 14, 20), Panel = Color3.fromRGB(19, 22, 30), Elem = Color3.fromRGB(27, 31, 42), ElemHover = Color3.fromRGB(37, 42, 56),
            Side = Color3.fromRGB(15, 17, 24), Accent = Color3.fromRGB(168, 142, 255), Text = Color3.fromRGB(242, 241, 248), TextDim = Color3.fromRGB(177, 179, 195),
            TextMuted = Color3.fromRGB(125, 130, 150), Border = Color3.fromRGB(50, 54, 70), BorderDim = Color3.fromRGB(37, 41, 54), ToggleOff = Color3.fromRGB(43, 47, 61),
        },
        Graphite = {
            Bg = Color3.fromRGB(20, 22, 25), Panel = Color3.fromRGB(28, 31, 35), Elem = Color3.fromRGB(38, 42, 47), ElemHover = Color3.fromRGB(49, 54, 60),
            Side = Color3.fromRGB(24, 26, 29), Accent = Color3.fromRGB(157, 182, 208), Text = Color3.fromRGB(239, 241, 244), TextDim = Color3.fromRGB(179, 184, 191),
            TextMuted = Color3.fromRGB(130, 137, 146), Border = Color3.fromRGB(62, 67, 74), BorderDim = Color3.fromRGB(46, 50, 56), ToggleOff = Color3.fromRGB(49, 54, 60),
        },
        Ocean = {
            Bg = Color3.fromRGB(12, 20, 29), Panel = Color3.fromRGB(17, 29, 41), Elem = Color3.fromRGB(25, 40, 55), ElemHover = Color3.fromRGB(34, 53, 71),
            Side = Color3.fromRGB(14, 24, 35), Accent = Color3.fromRGB(99, 190, 211), Text = Color3.fromRGB(230, 241, 246), TextDim = Color3.fromRGB(166, 194, 207),
            TextMuted = Color3.fromRGB(115, 150, 166), Border = Color3.fromRGB(45, 75, 91), BorderDim = Color3.fromRGB(32, 55, 69), ToggleOff = Color3.fromRGB(35, 57, 71),
        },
        Rose = {
            Bg = Color3.fromRGB(25, 17, 23), Panel = Color3.fromRGB(36, 24, 33), Elem = Color3.fromRGB(49, 32, 45), ElemHover = Color3.fromRGB(64, 41, 57),
            Side = Color3.fromRGB(29, 19, 26), Accent = Color3.fromRGB(232, 151, 180), Text = Color3.fromRGB(248, 237, 242), TextDim = Color3.fromRGB(202, 174, 188),
            TextMuted = Color3.fromRGB(151, 119, 135), Border = Color3.fromRGB(83, 55, 72), BorderDim = Color3.fromRGB(62, 41, 54), ToggleOff = Color3.fromRGB(61, 42, 54),
        },
        Forest = {
            Bg = Color3.fromRGB(15, 22, 19), Panel = Color3.fromRGB(22, 32, 27), Elem = Color3.fromRGB(31, 45, 37), ElemHover = Color3.fromRGB(42, 59, 48),
            Side = Color3.fromRGB(18, 27, 22), Accent = Color3.fromRGB(137, 202, 158), Text = Color3.fromRGB(235, 244, 237), TextDim = Color3.fromRGB(177, 204, 185),
            TextMuted = Color3.fromRGB(122, 153, 132), Border = Color3.fromRGB(53, 77, 61), BorderDim = Color3.fromRGB(39, 57, 46), ToggleOff = Color3.fromRGB(42, 60, 48),
        },
        Paper = {
            Bg = Color3.fromRGB(239, 237, 231), Panel = Color3.fromRGB(250, 249, 246), Elem = Color3.fromRGB(232, 230, 223), ElemHover = Color3.fromRGB(221, 219, 211),
            Side = Color3.fromRGB(232, 230, 222), Accent = Color3.fromRGB(119, 91, 66), Text = Color3.fromRGB(39, 40, 38), TextDim = Color3.fromRGB(78, 79, 75),
            TextMuted = Color3.fromRGB(111, 112, 106), Border = Color3.fromRGB(197, 194, 184), BorderDim = Color3.fromRGB(216, 213, 204), ToggleOff = Color3.fromRGB(213, 210, 201),
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
