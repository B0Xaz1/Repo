local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local CONFIG = table.freeze({
    STREAM_CHUNK_SIZE = 160,
    RECONCILE_DELAY = 0.12,
    -- Menu construction/focus can reset a few executors to 60 after their first GUI frame.
    -- These one-shot settles are not a visual update cadence or an FPS menu setting.
    FRAME_RATE_REPAIR_DELAYS = { 0.15, 0.6 },
    OWNED_EFFECT_PREFIX = "^B0Xaz",
    SURFACE_APPEARANCE_MAPS = { "ColorMap", "MetalnessMap", "NormalMap", "RoughnessMap" },
    TERRAIN_TWEAKS = { WaterWaveSize = 0, WaterWaveSpeed = 0, WaterReflectance = 0, WaterTransparency = 1, Decoration = false },
    FLAGS = { "NoTextures", "LowMaterials", "NoShadows", "NoParticles", "OptimizeTerrain", "NoPostProcessing", "NoLights", "NoHighlights" },
    PRESETS = {
        Balanced = { NoTextures = false, LowMaterials = false, NoShadows = true, NoParticles = true, OptimizeTerrain = true,
            NoPostProcessing = true, NoLights = false, NoHighlights = true },
        Maximum = { NoTextures = true, LowMaterials = true, NoShadows = true, NoParticles = true, OptimizeTerrain = true,
            NoPostProcessing = true, NoLights = true, NoHighlights = true },
    },
})

return function(services: any): any
    local state, bus, environment = services:Get("StateStore"), services:Get("EventBus"), services:Get("Environment")
    local scope = services:Get("Disposer"):CreateChild("OptimizerService")
    local changes = scope:CreateChild("Optimizations")
    local OptimizerService = { _caches = {}, _applied = {}, _revision = 0, _initialized = false,
        _applyRequested = false, _applyWorkerActive = false, _frameRateRepairRevision = 0 }

    for _, flag in ipairs(CONFIG.FLAGS) do OptimizerService._caches[flag] = {} end

    local function cacheWrite(cache: any, object: Instance, property: string, value: any)
        local known = cache[object]
        if known and known[property] then
            changes:SetProperty(object, property, value)
            return
        end
        if not changes:SetProperty(object, property, value) then return end
        if not known then known = {}; cache[object] = known end
        known[property] = true
    end

    local function restoreCache(cache: any)
        for object, properties in pairs(cache) do
            for property in pairs(properties) do changes:RestoreProperty(object, property) end
        end
        table.clear(cache)
    end

    local function applyToInstance(object: Instance, active: any)
        if active.NoTextures then
            local cache = OptimizerService._caches.NoTextures
            -- Decals and textures are hidden rather than repeatedly removing/reloading their assets.
            if object:IsA("Decal") or object:IsA("Texture") then cacheWrite(cache, object, "Transparency", 1)
            elseif object:IsA("MeshPart") then cacheWrite(cache, object, "TextureID", "")
            elseif object:IsA("SpecialMesh") then cacheWrite(cache, object, "TextureId", "")
            elseif object:IsA("SurfaceAppearance") then
                for _, property in ipairs(CONFIG.SURFACE_APPEARANCE_MAPS) do cacheWrite(cache, object, property, "") end
            end
        end
        if active.LowMaterials and object:IsA("BasePart") then
            local cache = OptimizerService._caches.LowMaterials
            cacheWrite(cache, object, "Material", Enum.Material.SmoothPlastic)
            cacheWrite(cache, object, "MaterialVariant", "")
        end
        if active.NoShadows then
            local cache = OptimizerService._caches.NoShadows
            if object:IsA("BasePart") then cacheWrite(cache, object, "CastShadow", false) end
            if object:IsA("Light") then cacheWrite(cache, object, "Shadows", false) end
            if object == Lighting then cacheWrite(cache, object, "GlobalShadows", false) end
        end
        if active.NoParticles and (object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
            or object:IsA("Smoke") or object:IsA("Fire") or object:IsA("Sparkles")) then
            cacheWrite(OptimizerService._caches.NoParticles, object, "Enabled", false)
        end
        if active.NoPostProcessing then
            local cache = OptimizerService._caches.NoPostProcessing
            if object:IsA("PostEffect") and not object.Name:match(CONFIG.OWNED_EFFECT_PREFIX) then
                cacheWrite(cache, object, "Enabled", false)
            elseif object:IsA("Atmosphere") then
                cacheWrite(cache, object, "Density", 0)
                cacheWrite(cache, object, "Haze", 0)
                cacheWrite(cache, object, "Glare", 0)
            elseif object:IsA("Clouds") then
                cacheWrite(cache, object, "Cover", 0)
                cacheWrite(cache, object, "Density", 0)
            end
        end
        if active.NoLights and object:IsA("Light") then cacheWrite(OptimizerService._caches.NoLights, object, "Enabled", false) end
        if active.NoHighlights and object:IsA("Highlight") then cacheWrite(OptimizerService._caches.NoHighlights, object, "Enabled", false) end
        if active.OptimizeTerrain and object:IsA("Terrain") then
            for property, value in pairs(CONFIG.TERRAIN_TWEAKS) do cacheWrite(OptimizerService._caches.OptimizeTerrain, object, property, value) end
        end
    end

    local function activeFeatures(): any
        local result = {}
        for _, flag in ipairs(CONFIG.FLAGS) do if OptimizerService._applied[flag] then result[flag] = true end end
        return result
    end

    local function anyActive(active: any): boolean return next(active) ~= nil end

    function OptimizerService:RestoreAll()
        self._revision += 1
        changes:RestoreProperties()
        for _, cache in pairs(self._caches) do table.clear(cache) end
        table.clear(self._applied)
    end

    -- A refresh streams one shared traversal for every newly enabled feature. It never restores
    -- and reapplies unrelated categories just because one toggle changed.
    function OptimizerService:Reconcile()
        local revision = self._revision
        local performance = state:Peek("Performance")
        local newlyEnabled = {}
        for _, flag in ipairs(CONFIG.FLAGS) do
            local desired = performance[flag] == true
            if desired == (self._applied[flag] == true) then continue end
            if desired then
                self._applied[flag], newlyEnabled[flag] = true, true
            else
                restoreCache(self._caches[flag])
                self._applied[flag] = nil
            end
        end
        if not anyActive(newlyEnabled) then return end

        applyToInstance(Lighting, newlyEnabled)
        local processed = 0
        for _, root in ipairs({ Workspace, Lighting }) do
            for _, object in ipairs(root:GetDescendants()) do
                if revision ~= self._revision or scope:IsDisposed() then return end
                applyToInstance(object, newlyEnabled)
                processed += 1
                if processed % CONFIG.STREAM_CHUNK_SIZE == 0 then task.wait() end
            end
        end
    end

    -- Several profile fields can change together. Debouncing turns that burst into one pass and
    -- a revision invalidates an in-flight pass before it can keep competing for frame time.
    function OptimizerService:RequestApply()
        self._revision += 1
        self._applyRequested = true
        if self._applyWorkerActive then return end
        self._applyWorkerActive = true
        scope:Spawn(function()
            while not scope:IsDisposed() and self._applyRequested do
                task.wait(CONFIG.RECONCILE_DELAY)
                self._applyRequested = false
                local applied, applyError = pcall(function() self:Reconcile() end)
                if not applied then warn(`[B0Xaz] Optimizer apply failed: {tostring(applyError)}`) end
            end
            self._applyWorkerActive = false
        end)
    end

    function OptimizerService:ApplyPreset(name: string): (boolean, string)
        local preset = CONFIG.PRESETS[name]
        if not preset then return false, "Unknown performance preset" end
        for _, flag in ipairs(CONFIG.FLAGS) do state:Set(`Performance.{flag}`, preset[flag] == true) end
        return true, if name == "Balanced" then "Balanced performance preset applied" else "Maximum performance preset applied"
    end

    function OptimizerService:RestoreVisualQuality(): (boolean, string)
        for _, flag in ipairs(CONFIG.FLAGS) do state:Set(`Performance.{flag}`, false) end
        self:RequestApply()
        return true, "Performance visual changes are being restored"
    end

    -- A repair has no user-facing control and never runs in a frame loop. It exists solely to
    -- correct executor state that can otherwise fall back to 60 when the menu gains focus.
    function OptimizerService:RepairFrameRate()
        environment:RepairFrameRate()
    end

    function OptimizerService:RepairFrameRateAfterMenuTransition()
        self._frameRateRepairRevision += 1
        local revision = self._frameRateRepairRevision
        local function repair()
            if scope:IsDisposed() or revision ~= self._frameRateRepairRevision or state:Peek("Settings.MenuVisible") ~= true then return end
            self:RepairFrameRate()
        end
        repair()
        for _, delay in ipairs(CONFIG.FRAME_RATE_REPAIR_DELAYS) do scope:Delay(delay, repair) end
    end

    function OptimizerService:Initialize()
        if self._initialized then return end
        self._initialized = true
        for _, flag in ipairs(CONFIG.FLAGS) do scope:Add(state:Observe(`Performance.{flag}`, function() OptimizerService:RequestApply() end)) end
        scope:Add(state:Observe("Settings.MenuVisible", function(visible: boolean)
            if visible then OptimizerService:RepairFrameRateAfterMenuTransition() end
        end))
        scope:Add(bus:Subscribe("SettingsHydrated", function()
            OptimizerService:RequestApply()
            OptimizerService:RepairFrameRate()
            if state:Peek("Settings.MenuVisible") then OptimizerService:RepairFrameRateAfterMenuTransition() end
        end))
        scope:ConnectImmediate(Workspace.DescendantAdded, function(object: Instance)
            local active = activeFeatures()
            if anyActive(active) then applyToInstance(object, active) end
        end)
        scope:ConnectImmediate(Lighting.DescendantAdded, function(object: Instance)
            local active = activeFeatures()
            if anyActive(active) then applyToInstance(object, active) end
        end)
        self:RequestApply()
        self:RepairFrameRate()
        if state:Peek("Settings.MenuVisible") then self:RepairFrameRateAfterMenuTransition() end
    end

    function OptimizerService:Destroy() scope:Dispose() end

    scope:Add(function()
        OptimizerService:RestoreAll()
        OptimizerService:RepairFrameRate()
    end)
    return OptimizerService
end
