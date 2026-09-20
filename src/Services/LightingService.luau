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
    BRIGHT_PART_THRESHOLD = 0.78,
    BRIGHT_REFLECTANCE_CAP = 0.015,
    DARK_REFLECTANCE_CAP = 0.1,
    VIGNETTE_EDGES = {
        { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.15), Rotation = 90 },
        { Position = UDim2.fromScale(0, 0.85), Size = UDim2.fromScale(1, 0.15), Rotation = 270 },
        { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(0.1, 1), Rotation = 0 },
        { Position = UDim2.fromScale(0.9, 0), Size = UDim2.fromScale(0.1, 1), Rotation = 180 },
    },
    REFRESH_PATHS = { "Lighting.Mode", "Lighting.PresetBrightness", "Lighting.Vignette", "Visuals.Fullbright", "Performance.NoShadows", "Performance.NoPostProcessing" },
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
        bloom.Name, bloom.Intensity, bloom.Size, bloom.Threshold = "B0XazBloom", 0.12, 18, 2.2
        effectsScope:Add(bloom); bloom.Parent = Lighting
        local grade = Instance.new("ColorCorrectionEffect")
        grade.Name, grade.Contrast, grade.Saturation = "B0XazGrade", 0.035, -0.035
        effectsScope:Add(grade); grade.Parent = Lighting
        LightingService._effects = { bloom, grade }
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
        clearVignette()
    end

    local function reconcile()
        if scope:IsDisposed() then return end
        local config = state:Get("Lighting")
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
        local profile = if config.Mode == "Dynamic" then dynamicProfile(LightingService._clock) else table.clone(if config.Mode == "Static Night" then CONFIG.NIGHT else CONFIG.DAY)
        if config.Mode ~= "Dynamic" then profile.ClockTime = config.TimeOfDay end
        profile.Brightness *= math.clamp(config.PresetBrightness, CONFIG.BRIGHTNESS_MIN, CONFIG.BRIGHTNESS_MAX)
        if state:Get("Performance.NoShadows") then profile.GlobalShadows = false end
        applyProfile(profile, modeChanges, LightingService._modeApplied)
        ensureEffects()
        for _, effect in ipairs(LightingService._effects) do effect.Enabled = not state:Get("Performance.NoPostProcessing") end
        if config.Vignette then ensureVignette() else clearVignette() end
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

    function LightingService:SetMode(mode: string): (boolean, string?)
        if not table.find(CONFIG.MODES, mode) then return false, "Unknown lighting mode" end
        local ok, message = state:Set("Lighting.Mode", mode)
        if ok and mode == "Static Day" then self:SetTime(CONFIG.STATIC_DAY_TIME) elseif ok and mode == "Static Night" then self:SetTime(CONFIG.STATIC_NIGHT_TIME) end
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
            if mode == "Off" and not state:Peek("Visuals.Fullbright") then return end
            if mode == "Dynamic" and not state:Peek("Lighting.Paused") and not state:Peek("Visuals.Fullbright") then
                LightingService._clock = (LightingService._clock + dt * 24 / math.max(CONFIG.MIN_CYCLE_DURATION, state:Peek("Lighting.CycleDuration"))) % 24
            end
            LightingService._elapsed += dt
            if LightingService._elapsed < CONFIG.REASSERT_INTERVAL then return end
            LightingService._elapsed = 0
            reconcile()
            state:SetTransient("LightingHour", LightingService._clock)
        end)
        local function syncLighting()
            job.Enabled = state:Peek("Lighting.Mode") ~= "Off" or state:Peek("Visuals.Fullbright") == true
        end
        scope:Add(state:Observe("Lighting.Mode", syncLighting))
        scope:Add(state:Observe("Visuals.Fullbright", syncLighting))
        syncLighting()
    end

    function LightingService:Destroy() scope:Dispose() end

    scope:Add(function() LightingService:Restore() end)
    return LightingService
end
