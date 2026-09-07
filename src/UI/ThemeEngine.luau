--!nonstrict
local TOKEN_NAMES = { "Bg", "Panel", "Elem", "ElemHover", "Side", "Accent", "AccentDark", "AccentDim", "Text", "TextDim", "TextMuted",
    "Border", "BorderDim", "ToggleOn", "ToggleOff", "Success", "Danger", "Warning" }
local PRESET_NAMES = { "Midnight", "Graphite", "Ocean", "Rose", "Forest", "Paper" }

return function(services: any): any
    local state, bus = services:Get("StateStore"), services:Get("EventBus")
    local scope = services:Get("Disposer"):CreateChild("ThemeEngine")
    local base: any = {
        Bg = Color3.fromRGB(16, 16, 18), Panel = Color3.fromRGB(22, 22, 26), Elem = Color3.fromRGB(30, 30, 34),
        ElemHover = Color3.fromRGB(40, 40, 46), Side = Color3.fromRGB(14, 14, 16), Accent = Color3.fromRGB(64, 176, 196),
        AccentDark = Color3.fromRGB(40, 118, 134), AccentDim = Color3.fromRGB(28, 64, 74), Text = Color3.fromRGB(226, 226, 230),
        TextDim = Color3.fromRGB(160, 162, 170), TextMuted = Color3.fromRGB(102, 104, 112), Border = Color3.fromRGB(48, 48, 54),
        BorderDim = Color3.fromRGB(36, 36, 40), ToggleOn = Color3.fromRGB(64, 176, 196), ToggleOff = Color3.fromRGB(44, 44, 50),
        Success = Color3.fromRGB(106, 220, 169), Danger = Color3.fromRGB(248, 109, 137), Warning = Color3.fromRGB(244, 193, 111),
    }
    local presets: any = { Midnight = table.clone(base) }
    local accents = { Graphite = Color3.fromRGB(188, 195, 212), Ocean = Color3.fromRGB(87, 198, 229), Rose = Color3.fromRGB(240, 139, 178), Forest = Color3.fromRGB(124, 204, 153) }
    local ThemeEngine = { _palette = table.clone(base), _bindings = setmetatable({}, { __mode = "k" }), _roots = setmetatable({}, { __mode = "k" }), _initialized = false }

    function ThemeEngine:DeriveAccentTones(color: Color3): (Color3, Color3)
        return color:Lerp(Color3.new(0, 0, 0), 0.4), color:Lerp(Color3.new(0, 0, 0), 0.76)
    end
    for name, accent in pairs(accents) do
        local palette = table.clone(base)
        palette.Accent, palette.ToggleOn = accent, accent
        palette.AccentDark, palette.AccentDim = ThemeEngine:DeriveAccentTones(accent)
        presets[name] = palette
    end
    local paper = table.clone(base)
    for token, rgb in pairs({ Bg = { 236, 239, 247 }, Panel = { 249, 250, 255 }, Elem = { 228, 233, 244 }, ElemHover = { 214, 223, 240 },
        Side = { 219, 225, 238 }, Text = { 24, 32, 52 }, TextDim = { 64, 78, 105 }, TextMuted = { 98, 113, 143 },
        Border = { 183, 195, 218 }, BorderDim = { 210, 218, 233 }, Accent = { 75, 101, 213 }, ToggleOn = { 75, 101, 213 } }) do
        paper[token] = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
    end
    paper.AccentDark, paper.AccentDim = ThemeEngine:DeriveAccentTones(paper.Accent)
    presets.Paper = paper

    local function refreshUnbound(previous: any)
        local reverse = {}
        for _, token in ipairs(TOKEN_NAMES) do if not reverse[previous[token]] then reverse[previous[token]] = token end end
        for root in pairs(ThemeEngine._roots) do
            local ok, descendants = pcall(function() return root:GetDescendants() end)
            if not ok then ThemeEngine._roots[root] = nil; continue end
            table.insert(descendants, root)
            for _, instance in ipairs(descendants) do
                for _, property in ipairs({ "BackgroundColor3", "TextColor3", "ImageColor3", "Color" }) do
                    if ThemeEngine._bindings[instance] and ThemeEngine._bindings[instance][property] then continue end
                    pcall(function()
                        local token = reverse[instance[property]]
                        if token then instance[property] = ThemeEngine._palette[token] end
                    end)
                end
            end
        end
    end
    local function applyFromState()
        local palette = table.clone(presets[state:Get("Theme.ActivePreset")] or presets.Midnight)
        local overrides = state:Get("Theme.CustomTokens") or {}
        for token, color in pairs(overrides) do if palette[token] and typeof(color) == "Color3" then palette[token] = color end end
        local previous, changed = ThemeEngine._palette, false
        for _, token in ipairs(TOKEN_NAMES) do if previous[token] ~= palette[token] then changed = true; break end end
        if not changed then return end
        ThemeEngine._palette = palette
        refreshUnbound(previous)
        ThemeEngine:UpdateAllBindings()
        bus:Publish("ThemeChanged")
    end
    function ThemeEngine:GetToken(name: string): Color3 return assert(self._palette[name], "Unknown theme token '" .. name .. "'") end
    function ThemeEngine:GetTokenNames(): { string } return table.clone(TOKEN_NAMES) end
    function ThemeEngine:GetPresetNames(): { string } return table.clone(PRESET_NAMES) end
    function ThemeEngine:BindToken(instance: Instance, property: string, token: string): any
        assert(self._palette[token], "Unknown theme token '" .. token .. "'")
        if not self._bindings[instance] then self._bindings[instance] = {} end
        self._bindings[instance][property] = token
        pcall(function() (instance :: any)[property] = self._palette[token] end)
        return instance
    end
    function ThemeEngine:RegisterRoot(root: Instance) self._roots[root] = true end
    function ThemeEngine:SetPreset(name: string): boolean
        if not presets[name] then return false end
        state:Set("Theme.CustomTokens", {})
        state:Set("Theme.ActivePreset", name)
        applyFromState()
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
        applyFromState()
    end
    function ThemeEngine:UpdateAllBindings()
        for instance, properties in pairs(self._bindings) do
            for property, token in pairs(properties) do
                local ok = pcall(function() (instance :: any)[property] = self._palette[token] end)
                if not ok then self._bindings[instance] = nil; break end
            end
        end
    end
    function ThemeEngine:Initialize()
        if self._initialized then return end
        self._initialized = true
        scope:Add(state:Observe("Theme.ActivePreset", applyFromState))
        scope:Add(state:Observe("Theme.CustomTokens", applyFromState))
        applyFromState()
    end
    function ThemeEngine:Destroy() scope:Dispose(); table.clear(self._bindings); table.clear(self._roots) end
    return ThemeEngine
end
