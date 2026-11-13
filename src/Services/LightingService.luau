local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local CONFIG = table.freeze({
    REASSERT_INTERVAL = 0.2,
    STREAM_CHUNK_SIZE = 250,
    MIN_CYCLE_DURATION = 30,
    BRIGHTNESS_MIN = 0.25,
    BRIGHTNESS_MAX = 2,
    STATIC_DAY_TIME = 14,
    STATIC_NIGHT_TIME = 0.5,
    MODES = { "Off", "Static Day", "Static Night", "Dynamic" },
    SCENE_PRESET_NAMES = { "Custom", "Neutral", "Golden Hour", "Overcast", "Moonlight", "Neon" },
    PROPERTIES = { "Ambient", "OutdoorAmbient", "Brightness", "ClockTime", "ExposureCompensation",
        "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "GlobalShadows", "ShadowSoftness", "FogStart", "FogEnd", "FogColor" },
    DAY = { Ambient = Color3.fromRGB(139, 145, 159), OutdoorAmbient = Color3.fromRGB(163, 170, 184), Brightness = 1.8,
        ClockTime = 14, ExposureCompensation = -0.15, EnvironmentDiffuseScale = 0.55, EnvironmentSpecularScale = 0.15,
        GlobalShadows = true, ShadowSoftness = 0.6, FogStart = 1500, FogEnd = 10000, FogColor = Color3.fromRGB(194, 207, 224) },
    NIGHT = { Ambient = Color3.fromRGB(91, 99, 131), OutdoorAmbient = Color3.fromRGB(111, 120, 149), Brightness = 1.25,
        ClockTime = 0.5, ExposureCompensation = 0.05, EnvironmentDiffuseScale = 0.45, EnvironmentSpecularScale = 0.08,
        GlobalShadows = true, ShadowSoftness = 0.8, FogStart = 1200, FogEnd = 8000, FogColor = Color3.fromRGB(87, 100, 135) },
    DAWN = { Ambient = Color3.fromRGB(137, 117, 135), OutdoorAmbient = Color3.fromRGB(161, 142, 157), Brightness = 1.4,
        ClockTime = 6, ExposureCompensation = -0.05, EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.1,
        GlobalShadows = true, ShadowSoftness = 0.7, FogStart = 1200, FogEnd = 9000, FogColor = Color3.fromRGB(203, 171, 165) },
    FULLBRIGHT_AMBIENT = Color3.fromRGB(210, 210, 210),
    FULLBRIGHT_FOG_END = 100000,
    DEFAULT_EFFECTS = { BloomIntensity = 0.12, BloomSize = 18, BloomThreshold = 2.2,
        Contrast = 0.035, Saturation = -0.035, TintColor = Color3.new(1, 1, 1) },
    BRIGHT_PART_THRESHOLD = 0.78,
    BRIGHT_REFLECTANCE_CAP = 0.015,
    DARK_REFLECTANCE_CAP = 0.1,
    VIGNETTE_EDGES = {
        { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.15), Rotation = 90 },
        { Position = UDim2.fromScale(0, 0.85), Size = UDim2.fromScale(1, 0.15), Rotation = 270 },
        { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(0.1, 1), Rotation = 0 },
        { Position = UDim2.fromScale(0.9, 0), Size = UDim2.fromScale(0.1, 1), Rotation = 180 },
    },
    REFRESH_PATHS = { "Lighting.Mode", "Lighting.ScenePreset", "Lighting.PresetBrightness", "Lighting.Vignette", "Visuals.Fullbright", "Performance.NoShadows", "Performance.NoPostProcessing" },
})

-- Scene presets are complete grades rather than small time-of-day tweaks, so choosing one gives
-- a predictable look regardless of the experience's original Lighting values.
local SCENE_PRESETS = table.freeze({
    Neutral = {
        Profile = { Ambient = Color3.fromRGB(139, 145, 159), OutdoorAmbient = Color3.fromRGB(163, 170, 184), Brightness = 1.8,
            ClockTime = 14, ExposureCompensation = -0.15, EnvironmentDiffuseScale = 0.55, EnvironmentSpecularScale = 0.15,
            GlobalShadows = true, ShadowSoftness = 0.6, FogStart = 1500, FogEnd = 10000, FogColor = Color3.fromRGB(194, 207, 224) },
        Vignette = false,
        Effects = { BloomIntensity = 0.12, BloomSize = 18, BloomThreshold = 2.2, Contrast = 0.035, Saturation = -0.035, TintColor = Color3.new(1, 1, 1) },
    },
    ["Golden Hour"] = {
        Profile = { Ambient = Color3.fromRGB(163, 126, 96), OutdoorAmbient = Color3.fromRGB(211, 161, 112), Brightness = 1.7,
            ClockTime = 17.35, ExposureCompensation = 0.02, EnvironmentDiffuseScale = 0.62, EnvironmentSpecularScale = 0.18,
            GlobalShadows = true, ShadowSoftness = 0.68, FogStart = 850, FogEnd = 7200, FogColor = Color3.fromRGB(229, 171, 121) },
        Vignette = false,
        Effects = { BloomIntensity = 0.18, BloomSize = 24, BloomThreshold = 1.9, Contrast = 0.075, Saturation = 0.09, TintColor = Color3.fromRGB(255, 236, 210) },
    },
    Overcast = {
        Profile = { Ambient = Color3.fromRGB(112, 124, 139), OutdoorAmbient = Color3.fromRGB(130, 143, 157), Brightness = 1.15,
            ClockTime = 12, ExposureCompensation = -0.1, EnvironmentDiffuseScale = 0.42, EnvironmentSpecularScale = 0.04,
            GlobalShadows = true, ShadowSoftness = 0.9, FogStart = 400, FogEnd = 3600, FogColor = Color3.fromRGB(165, 181, 194) },
        Vignette = false,
        Effects = { BloomIntensity = 0.045, BloomSize = 12, BloomThreshold = 2.5, Contrast = 0.025, Saturation = -0.24, TintColor = Color3.fromRGB(224, 236, 246) },
    },
    Moonlight = {
        Profile = { Ambient = Color3.fromRGB(67, 79, 121), OutdoorAmbient = Color3.fromRGB(79, 95, 142), Brightness = 1.1,
            ClockTime = 0.5, ExposureCompensation = 0.1, EnvironmentDiffuseScale = 0.38, EnvironmentSpecularScale = 0.08,
            GlobalShadows = true, ShadowSoftness = 0.86, FogStart = 700, FogEnd = 6500, FogColor = Color3.fromRGB(71, 87, 135) },
        Vignette = true,
        Effects = { BloomIntensity = 0.14, BloomSize = 20, BloomThreshold = 2.1, Contrast = 0.11, Saturation = -0.15, TintColor = Color3.fromRGB(207, 222, 255) },
    },
    Neon = {
        Profile = { Ambient = Color3.fromRGB(82, 47, 113), OutdoorAmbient = Color3.fromRGB(105, 64, 142), Brightness = 1.3,
            ClockTime = 21, ExposureCompensation = 0.08, EnvironmentDiffuseScale = 0.48, EnvironmentSpecularScale = 0.24,
            GlobalShadows = true, ShadowSoftness = 0.72, FogStart = 600, FogEnd = 5200, FogColor = Color3.fromRGB(79, 43, 119) },
        Vignette = true,
        Effects = { BloomIntensity = 0.3, BloomSize = 32, BloomThreshold = 1.55, Contrast = 0.16, Saturation = 0.2, TintColor = Color3.fromRGB(237, 211, 255) },
    },
})

return function(services: any): any
    local state, scheduler = services:Get("StateStore"), services:Get("TaskScheduler")
    local environment, dom = services:Get("Environment"), services:Get("DOM")
    local scope = services:Get("Disposer"):CreateChild("LightingService")
    local modeChanges, fullbrightChanges, materials = scope:CreateChild("Grade"), scope:CreateChild("Fullbright"), scope:CreateChild("Remaster")
    local LightingService = { _original = nil, _effectsScope = nil, _effects = {}, _materialCache = {}, _vignette = nil,
        _clock = CONFIG.STATIC_DAY_TIME, _elapsed = 0, _initialized = false, _modeApplied = {}, _fullbrightApplied = {} }

    local KEYFRAMES = table.freeze({
        { Hour = 0, Profile = CONFIG.NIGHT }, { Hour = 5, Profile = CONFIG.NIGHT }, { Hour = 7, Profile = CONFIG.DAWN },
        { Hour = 12, Profile = CONFIG.DAY }, { Hour = 17, Profile = CONFIG.DAY }, { Hour = 19, Profile = CONFIG.DAWN },
        { Hour = 21, Profile = CONFIG.NIGHT }, { Hour = 24, Profile = CONFIG.NIGHT },
    })

    local function snapshot()
        if LightingService._original then return end
        LightingService._original = {}
        for _, property in ipairs(CONFIG.PROPERTIES) do
            local ok, value = modeChanges:GetOriginal(Lighting, property)
            if ok then LightingService._original[property] = { Value = value } end
        end
    end

    local function smoothStep(value: number): number return value * value * (3 - 2 * value) end

    local function dynamicProfile(hour: number): any
        local first, second = KEYFRAMES[1], KEYFRAMES[#KEYFRAMES]
        for index = 1, #KEYFRAMES - 1 do
            if hour >= KEYFRAMES[index].Hour and hour <= KEYFRAMES[index + 1].Hour then first, second = KEYFRAMES[index], KEYFRAMES[index + 1]; break end
        end
        local alpha = smoothStep(math.clamp((hour - first.Hour) / (second.Hour - first.Hour), 0, 1))
        local profile = {}
        for _, property in ipairs(CONFIG.PROPERTIES) do
            local a, b = first.Profile[property], second.Profile[property]
            if typeof(a) == "Color3" then profile[property] = a:Lerp(b, alpha)
            elseif type(a) == "number" then profile[property] = a + (b - a) * alpha
            else profile[property] = if alpha < 0.5 then a else b end
        end
        profile.ClockTime = hour
        return profile
    end

    -- The 5 Hz re-assert skips values it already applied, so it does not churn properties
    local function applyProfile(profile: any, owner: any, applied: any)
        snapshot()
        for _, property in ipairs(CONFIG.PROPERTIES) do
            if LightingService._original[property] and profile[property] ~= nil and applied[property] ~= profile[property] then
                if owner:SetProperty(Lighting, property, profile[property]) then applied[property] = profile[property]
                else applied[property] = nil end
            end
        end
    end

    local function ensureEffects()
        if LightingService._effectsScope then return end
        local effectsScope = scope:CreateChild("Owned post effects")
        LightingService._effectsScope = effectsScope
        local bloom = Instance.new("BloomEffect")
        bloom.Name = "B0XazBloom"
        effectsScope:Add(bloom); bloom.Parent = Lighting
        local grade = Instance.new("ColorCorrectionEffect")
        grade.Name = "B0XazGrade"
        effectsScope:Add(grade); grade.Parent = Lighting
        LightingService._effects = { bloom, grade }
    end

    local function applyEffects(style: any)
        ensureEffects()
        local bloom, grade = LightingService._effects[1], LightingService._effects[2]
        local effects = style or CONFIG.DEFAULT_EFFECTS
        if bloom.Intensity ~= effects.BloomIntensity then bloom.Intensity = effects.BloomIntensity end
        if bloom.Size ~= effects.BloomSize then bloom.Size = effects.BloomSize end
        if bloom.Threshold ~= effects.BloomThreshold then bloom.Threshold = effects.BloomThreshold end
        if grade.Contrast ~= effects.Contrast then grade.Contrast = effects.Contrast end
        if grade.Saturation ~= effects.Saturation then grade.Saturation = effects.Saturation end
        if grade.TintColor ~= effects.TintColor then grade.TintColor = effects.TintColor end
    end

    local function clearVignette()
        local gui = LightingService._vignette
        LightingService._vignette = nil
        if gui then pcall(function() dom:DestroyInstance(gui) end) end
    end

    local function ensureVignette()
        if LightingService._vignette then return end
        local parent = environment:GetSafeGuiParent()
        if not parent then return end
        local gui = dom:Create("ScreenGui", { Name = "B0XazVignette", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 800, Parent = parent })
        LightingService._vignette = gui
        for _, edge in ipairs(CONFIG.VIGNETTE_EDGES) do
            local frame = dom:Create("Frame", { Parent = gui, BorderSizePixel = 0, BackgroundColor3 = Color3.new(0, 0, 0), Position = edge.Position, Size = edge.Size })
            dom:Create("UIGradient", { Parent = frame, Rotation = edge.Rotation,
                Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }) })
        end
    end

    local function remaster(object: Instance)
        if not object:IsA("BasePart") or object:IsA("Terrain") then return end
        if LightingService._materialCache[object] == nil then
            local _, material = materials:GetOriginal(object, "Material")
            local _, reflectance = materials:GetOriginal(object, "Reflectance")
            LightingService._materialCache[object] = { Material = material, Reflectance = reflectance }
        end
        local original = LightingService._materialCache[object]
        local color = object.Color
        local bright = math.min(color.R, color.G, color.B) > CONFIG.BRIGHT_PART_THRESHOLD
        if not state:Get("Performance.LowMaterials") and (original.Material == Enum.Material.Plastic or (bright and original.Material == Enum.Material.Neon)) then
            materials:SetProperty(object, "Material", Enum.Material.SmoothPlastic)
        else materials:RestoreProperty(object, "Material") end
        materials:SetProperty(object, "Reflectance", if bright then math.min(original.Reflectance, CONFIG.BRIGHT_REFLECTANCE_CAP) else math.min(original.Reflectance, CONFIG.DARK_REFLECTANCE_CAP))
    end

    local function restoreMode()
        modeChanges:RestoreProperties()
        materials:RestoreProperties()
        table.clear(LightingService._materialCache)
        table.clear(LightingService._modeApplied)
        if LightingService._effectsScope then LightingService._effectsScope:Dispose(); LightingService._effectsScope = nil end
        table.clear(LightingService._effects)
    end

    local function reconcile()
        if scope:IsDisposed() then return end
        local config = state:Get("Lighting")
        local scene = SCENE_PRESETS[config.ScenePreset]
        if (scene and scene.Vignette) or (not scene and config.Vignette) then ensureVignette() else clearVignette() end
        local fullbright = state:Get("Visuals.Fullbright")
        if fullbright then
            restoreMode()
            local profile = table.clone(CONFIG.DAY)
            profile.Ambient, profile.OutdoorAmbient = CONFIG.FULLBRIGHT_AMBIENT, CONFIG.FULLBRIGHT_AMBIENT
            profile.GlobalShadows, profile.ClockTime, profile.FogEnd = false, CONFIG.STATIC_DAY_TIME, CONFIG.FULLBRIGHT_FOG_END
            applyProfile(profile, fullbrightChanges, LightingService._fullbrightApplied)
            return
        end
        fullbrightChanges:RestoreProperties()
        table.clear(LightingService._fullbrightApplied)
        if config.Mode == "Off" then
            restoreMode(); LightingService._original = nil; return
        end
        local profile = if scene then table.clone(scene.Profile)
            elseif config.Mode == "Dynamic" then dynamicProfile(LightingService._clock)
            else table.clone(if config.Mode == "Static Night" then CONFIG.NIGHT else CONFIG.DAY)
        if not scene and config.Mode ~= "Dynamic" then profile.ClockTime = config.TimeOfDay end
        profile.Brightness *= math.clamp(config.PresetBrightness, CONFIG.BRIGHTNESS_MIN, CONFIG.BRIGHTNESS_MAX)
        if state:Get("Performance.NoShadows") then profile.GlobalShadows = false end
        applyProfile(profile, modeChanges, LightingService._modeApplied)
        applyEffects(if scene then scene.Effects else CONFIG.DEFAULT_EFFECTS)
        for _, effect in ipairs(LightingService._effects) do effect.Enabled = not state:Get("Performance.NoPostProcessing") end
        if not config.RemasterMaterials then materials:RestoreProperties(); table.clear(LightingService._materialCache) end
    end

    local function updateMaterials()
        if scope:IsDisposed() then return end
        if state:Get("Lighting.Mode") == "Off" or state:Get("Visuals.Fullbright") or not state:Get("Lighting.RemasterMaterials") then
            materials:RestoreProperties(); table.clear(LightingService._materialCache); return
        end
        for index, object in ipairs(Workspace:GetDescendants()) do
            if scope:IsDisposed() or not state:Get("Lighting.RemasterMaterials") or state:Get("Visuals.Fullbright") or state:Get("Lighting.Mode") == "Off" then return end
            remaster(object)
            if index % CONFIG.STREAM_CHUNK_SIZE == 0 then task.wait(0.001) end
        end
    end

    function LightingService:GetScenePresetNames(): { string } return table.clone(CONFIG.SCENE_PRESET_NAMES) end

    function LightingService:UseCustomScene()
        if state:Peek("Lighting.ScenePreset") ~= "Custom" then state:Set("Lighting.ScenePreset", "Custom") end
    end

    function LightingService:ApplyScenePreset(name: string): (boolean, string?)
        if name == "Custom" then
            self:UseCustomScene()
            return true, "Manual lighting controls restored"
        end
        local scene = SCENE_PRESETS[name]
        if not scene then return false, "Unknown scene preset" end
        state:Set("Lighting.ScenePreset", name)
        state:Set("Lighting.Mode", "Static Day")
        state:Set("Lighting.TimeOfDay", scene.Profile.ClockTime)
        state:Set("Lighting.PresetBrightness", 1)
        state:Set("Lighting.Vignette", scene.Vignette == true)
        self._clock = scene.Profile.ClockTime
        return true, `{name} lighting applied`
    end

    function LightingService:SetMode(mode: string): (boolean, string?)
        if not table.find(CONFIG.MODES, mode) then return false, "Unknown lighting mode" end
        local ok, message = state:Set("Lighting.Mode", mode)
        if ok then
            self:UseCustomScene()
            if mode == "Static Day" then self:SetTime(CONFIG.STATIC_DAY_TIME)
            elseif mode == "Static Night" then self:SetTime(CONFIG.STATIC_NIGHT_TIME) end
        end
        return ok, message
    end

    function LightingService:ApplyStatic(name: string): (boolean, string?) return self:SetMode(if name == "Night" or name == "Static Night" then "Static Night" else "Static Day") end

    function LightingService:ApplyDynamic(): (boolean, string?) return self:SetMode("Dynamic") end

    function LightingService:SetTime(hour: number)
        state:Set("Lighting.TimeOfDay", hour % 24)
        self._clock = hour % 24
        reconcile()
    end

    function LightingService:Restore()
        restoreMode(); fullbrightChanges:RestoreProperties()
        clearVignette()
        table.clear(self._fullbrightApplied); self._original = nil
    end

    function LightingService:Initialize()
        if self._initialized then return end
        self._initialized = true
        -- Coalesces a burst of state changes into one deferred pass, keyed by the flag name
        local function scheduleForward(flag: string, body: () -> ())
            if LightingService[flag] then return end
            LightingService[flag] = true
            task.defer(function()
                LightingService[flag] = nil
                if not scope:IsDisposed() then body() end
            end)
        end
        local function scheduleReconcile() scheduleForward("_reconcileQ", reconcile) end
        local function scheduleModeRefresh() scheduleForward("_modeRefreshQ", function() reconcile(); updateMaterials() end) end
        for _, path in ipairs(CONFIG.REFRESH_PATHS) do scope:Add(state:Observe(path, scheduleModeRefresh)) end
        scope:Add(state:Observe("Lighting.TimeOfDay", function(value: number) LightingService._clock = value % 24; scheduleReconcile() end))
        scope:Add(state:Observe("Lighting.RemasterMaterials", updateMaterials))
        scope:Add(state:Observe("Performance.LowMaterials", updateMaterials))
        scope:ConnectImmediate(Workspace.DescendantAdded, function(object: Instance)
            if state:Peek("Lighting.Mode") ~= "Off" and state:Peek("Lighting.RemasterMaterials") and not state:Peek("Visuals.Fullbright") then remaster(object) end
        end)
        local job = scheduler:RegisterHeartbeat("Lighting.Reassert", 70, function(dt: number)
            local mode = state:Peek("Lighting.Mode")
            local fullbright, vignette = state:Peek("Visuals.Fullbright"), state:Peek("Lighting.Vignette")
            if mode == "Off" and not fullbright and not vignette then return end
            if mode == "Dynamic" and not state:Peek("Lighting.Paused") and not fullbright then
                LightingService._clock = (LightingService._clock + dt * 24 / math.max(CONFIG.MIN_CYCLE_DURATION, state:Peek("Lighting.CycleDuration"))) % 24
            end
            LightingService._elapsed += dt
            if LightingService._elapsed < CONFIG.REASSERT_INTERVAL then return end
            LightingService._elapsed = 0
            reconcile()
            state:SetTransient("LightingHour", LightingService._clock)
        end)
        local function syncLighting()
            job.Enabled = state:Peek("Lighting.Mode") ~= "Off" or state:Peek("Visuals.Fullbright") == true or state:Peek("Lighting.Vignette") == true
        end
        scope:Add(state:Observe("Lighting.Mode", syncLighting))
        scope:Add(state:Observe("Visuals.Fullbright", syncLighting))
        scope:Add(state:Observe("Lighting.Vignette", syncLighting))
        syncLighting()
    end

    function LightingService:Destroy() scope:Dispose() end

    scope:Add(function() LightingService:Restore() end)
    return LightingService
end
