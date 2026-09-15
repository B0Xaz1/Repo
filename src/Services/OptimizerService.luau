--!strict
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
    -- The disposer already journals each property's original value. Keeping a
    -- second original-value cache per instance only duplicated memory and reads.
    -- This small revision map records writes for the current pass, so a repeated
    -- DescendantAdded notification cannot write the same property again.
    local OptimizerService = { _writeRevisions = {}, _revision = 0, _initialized = false }

    local function cacheWrite(object: Instance, property: string, value: any)
        local revisions = OptimizerService._writeRevisions[object]
        if not revisions then revisions = {}; OptimizerService._writeRevisions[object] = revisions end
        if revisions[property] == OptimizerService._revision then return end
        revisions[property] = OptimizerService._revision
        changes:SetProperty(object, property, value)
    end

    local function processInstance(object: Instance, performance: any)
        if scope:IsDisposed() then return end
        -- Hoisted once per instance instead of re-indexing the settings table per branch.
        local noTextures, lowMaterials = performance.NoTextures, performance.LowMaterials
        local noShadows, noParticles = performance.NoShadows, performance.NoParticles
        local noPostProcessing, optimizeTerrain = performance.NoPostProcessing, performance.OptimizeTerrain
        if not (noTextures or lowMaterials or noShadows or noParticles or noPostProcessing or optimizeTerrain) then return end
        if noTextures then
            if object:IsA("Decal") or object:IsA("Texture") then cacheWrite(object, "Texture", "")
            elseif object:IsA("MeshPart") then cacheWrite(object, "TextureID", "")
            elseif object:IsA("SpecialMesh") then cacheWrite(object, "TextureId", "")
            elseif object:IsA("SurfaceAppearance") then
                for _, property in ipairs(CONFIG.SURFACE_APPEARANCE_MAPS) do cacheWrite(object, property, "") end
            end
        end
        if object:IsA("BasePart") then
            if lowMaterials then
                cacheWrite(object, "Material", Enum.Material.SmoothPlastic)
                cacheWrite(object, "MaterialVariant", "")
            end
            if noShadows then cacheWrite(object, "CastShadow", false) end
        end
        if noParticles and (object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
            or object:IsA("Smoke") or object:IsA("Fire") or object:IsA("Sparkles")) then
            cacheWrite(object, "Enabled", false)
        end
        -- The lighting service owns its own effects; never borrow them for optimization.
        if noPostProcessing and object:IsA("PostEffect") and not object.Name:match(CONFIG.OWNED_EFFECT_PREFIX) then
            cacheWrite(object, "Enabled", false)
        end
        if object:IsA("Terrain") and optimizeTerrain then
            for property, value in pairs(CONFIG.TERRAIN_TWEAKS) do cacheWrite(object, property, value) end
        end
        if object == Lighting and noShadows then cacheWrite(object, "GlobalShadows", false) end
    end

    function OptimizerService:RestoreAll()
        self._revision += 1
        changes:RestoreProperties()
        table.clear(self._writeRevisions)
    end

    -- Walks one tree in place. Both trees used to be concatenated into a single
    -- array first, which allocated (and grew) a second copy of every descendant
    -- reference before any of them was processed.
    local function processTree(root: Instance, performance: any, revision: number, counter: number): (boolean, number)
        for _, object in ipairs(root:GetDescendants()) do
            if revision ~= OptimizerService._revision or scope:IsDisposed() then return false, counter end
            processInstance(object, performance)
            counter += 1
            -- Stream large maps in bounded chunks so a toggle cannot monopolize the executor thread.
            if counter % CONFIG.STREAM_CHUNK_SIZE == 0 then task.wait(0.001) end
        end
        return true, counter
    end

    function OptimizerService:Apply()
        self:RestoreAll()
        local revision = self._revision
        local performance = state:Get("Performance")
        if not (performance.NoTextures or performance.LowMaterials or performance.NoShadows or performance.NoParticles
            or performance.OptimizeTerrain or performance.NoPostProcessing) then return end
        processInstance(Lighting, performance)
        local ok, counter = processTree(Workspace, performance, revision, 0)
        if not ok then return end
        processTree(Lighting, performance, revision, counter)
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
        -- processInstance bails on its own when every flag is off.
        local function onAdded(object: Instance)
            processInstance(object, state:Peek("Performance"))
        end
        scope:ConnectImmediate(Workspace.DescendantAdded, onAdded)
        scope:ConnectImmediate(Lighting.DescendantAdded, onAdded)
    end

    function OptimizerService:Destroy() scope:Dispose() end

    scope:Add(function() OptimizerService:RestoreAll(); environment:SetFpsCap(0) end)
    return OptimizerService
end
