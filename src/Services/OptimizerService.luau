local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local CONFIG = table.freeze({
    STREAM_CHUNK_SIZE = 250,
    OWNED_EFFECT_PREFIX = "^B0Xaz",
    SURFACE_APPEARANCE_MAPS = { "ColorMap", "MetalnessMap", "NormalMap", "RoughnessMap" },
    TERRAIN_TWEAKS = { WaterWaveSize = 0, WaterWaveSpeed = 0, WaterReflectance = 0, WaterTransparency = 1, Decoration = false },
    FLAGS = { "NoTextures", "LowMaterials", "NoShadows", "NoParticles", "OptimizeTerrain", "NoPostProcessing" },
})

return function(services: any): any
    local state, environment = services:Get("StateStore"), services:Get("Environment")
    local scope = services:Get("Disposer"):CreateChild("OptimizerService")
    local changes = scope:CreateChild("Optimizations")
    local OptimizerService = { _textureCache = {}, _materialCache = {}, _shadowCache = {}, _particleCache = {},
        _postFxCache = {}, _terrainDefaults = {}, _revision = 0, _initialized = false }

    local function cacheWrite(cache: any, object: Instance, property: string, value: any)
        if not cache[object] then cache[object] = {} end
        if cache[object][property] == nil then
            local ok, original = changes:GetOriginal(object, property)
            if not ok then return end
            cache[object][property] = { Value = original }
        end
        changes:SetProperty(object, property, value)
    end

    local function processInstance(object: Instance, performance: any)
        if scope:IsDisposed() then return end
        if performance.NoTextures then
            if object:IsA("Decal") or object:IsA("Texture") then cacheWrite(OptimizerService._textureCache, object, "Texture", "")
            elseif object:IsA("MeshPart") then cacheWrite(OptimizerService._textureCache, object, "TextureID", "")
            elseif object:IsA("SpecialMesh") then cacheWrite(OptimizerService._textureCache, object, "TextureId", "")
            elseif object:IsA("SurfaceAppearance") then
                for _, property in ipairs(CONFIG.SURFACE_APPEARANCE_MAPS) do cacheWrite(OptimizerService._textureCache, object, property, "") end
            end
        end
        if object:IsA("BasePart") then
            if performance.LowMaterials then
                cacheWrite(OptimizerService._materialCache, object, "Material", Enum.Material.SmoothPlastic)
                cacheWrite(OptimizerService._materialCache, object, "MaterialVariant", "")
            end
            if performance.NoShadows then cacheWrite(OptimizerService._shadowCache, object, "CastShadow", false) end
        end
        if performance.NoParticles and (object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
            or object:IsA("Smoke") or object:IsA("Fire") or object:IsA("Sparkles")) then
            cacheWrite(OptimizerService._particleCache, object, "Enabled", false)
        end
        -- The suite's own post effects are skipped; it owns and restores those itself
        if performance.NoPostProcessing and object:IsA("PostEffect") and not object.Name:match(CONFIG.OWNED_EFFECT_PREFIX) then
            cacheWrite(OptimizerService._postFxCache, object, "Enabled", false)
        end
        if object:IsA("Terrain") and performance.OptimizeTerrain then
            for property, value in pairs(CONFIG.TERRAIN_TWEAKS) do cacheWrite(OptimizerService._terrainDefaults, object, property, value) end
        end
        if object == Lighting and performance.NoShadows then cacheWrite(OptimizerService._shadowCache, object, "GlobalShadows", false) end
    end

    function OptimizerService:RestoreAll()
        self._revision += 1
        changes:RestoreProperties()
        for _, cache in ipairs({ self._textureCache, self._materialCache, self._shadowCache, self._particleCache, self._postFxCache, self._terrainDefaults }) do table.clear(cache) end
    end

    -- Chunked so a full pass cannot stall a frame, and aborted as soon as a newer pass starts
    function OptimizerService:Apply()
        self:RestoreAll()
        local revision = self._revision
        local performance = state:Get("Performance")
        processInstance(Lighting, performance)
        local descendants = {}
        for _, object in ipairs(Workspace:GetDescendants()) do table.insert(descendants, object) end
        for _, object in ipairs(Lighting:GetDescendants()) do table.insert(descendants, object) end
        for index, object in ipairs(descendants) do
            if revision ~= self._revision or scope:IsDisposed() then return end
            processInstance(object, performance)
            if index % CONFIG.STREAM_CHUNK_SIZE == 0 then task.wait(0.001) end
        end
    end

    function OptimizerService:ApplyFpsCap(value: number): (boolean, string)
        if not environment:HasFpsCap() then return false, "FPS-cap support is unavailable on this executor" end
        local ok = environment:SetFpsCap(value)
        return ok, if ok then (if value == 0 then "FPS uncapped" else "FPS cap applied") else "The executor rejected the FPS cap"
    end

    function OptimizerService:FlushMemory(): (boolean, string)
        local collected = pcall(function() collectgarbage("collect") end)
        return collected, if collected then "Garbage collection requested" else "This client restricts forced collection; Lua will collect automatically"
    end

    function OptimizerService:Initialize()
        if self._initialized then return end
        self._initialized = true
        for _, flag in ipairs(CONFIG.FLAGS) do scope:Add(state:Observe(`Performance.{flag}`, function() OptimizerService:Apply() end)) end
        scope:Add(state:Observe("Performance.FpsCap", function(value: number)
            local ok, message = OptimizerService:ApplyFpsCap(value)
            if not ok and value ~= 0 then services:Get("EventBus"):Publish("Notify", "Performance", message) end
        end))
        local function onAdded(object: Instance)
            local performance = state:Peek("Performance")
            if not (performance.NoTextures or performance.LowMaterials or performance.NoShadows or performance.NoParticles
                or performance.OptimizeTerrain or performance.NoPostProcessing) then return end
            processInstance(object, performance)
        end
        scope:ConnectImmediate(Workspace.DescendantAdded, onAdded)
        scope:ConnectImmediate(Lighting.DescendantAdded, onAdded)
    end

    function OptimizerService:Destroy() scope:Dispose() end

    scope:Add(function() OptimizerService:RestoreAll(); environment:SetFpsCap(0) end)
    return OptimizerService
end
