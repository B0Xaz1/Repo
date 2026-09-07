--!nonstrict
return function(services: any): any
    local state, environment = services:Get("StateStore"), services:Get("Environment")
    local scope = services:Get("Disposer"):CreateChild("OptimizerService")
    local changes = scope:CreateChild("Optimizations")
    local workspace, lighting = game:GetService("Workspace"), game:GetService("Lighting")
    local OptimizerService = { _textureCache = {}, _materialCache = {}, _shadowCache = {}, _particleCache = {},
        _postFxCache = {}, _terrainDefaults = {}, _revision = 0, _initialized = false }
    local flags = { "NoTextures", "LowMaterials", "NoShadows", "NoParticles", "OptimizeTerrain", "NoPostProcessing" }

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
                for _, property in ipairs({ "ColorMap", "MetalnessMap", "NormalMap", "RoughnessMap" }) do cacheWrite(OptimizerService._textureCache, object, property, "") end
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
        -- The lighting service owns its own effects and honors the same flag without borrowing game effects.
        if performance.NoPostProcessing and object:IsA("PostEffect") and not object.Name:match("^B0Xaz") then
            cacheWrite(OptimizerService._postFxCache, object, "Enabled", false)
        end
        if object:IsA("Terrain") and performance.OptimizeTerrain then
            for property, value in pairs({ WaterWaveSize = 0, WaterWaveSpeed = 0, WaterReflectance = 0, WaterTransparency = 1, Decoration = false }) do
                cacheWrite(OptimizerService._terrainDefaults, object, property, value)
            end
        end
        if object == lighting and performance.NoShadows then cacheWrite(OptimizerService._shadowCache, object, "GlobalShadows", false) end
    end
    function OptimizerService:RestoreAll()
        self._revision += 1
        changes:RestoreProperties()
        for _, cache in ipairs({ self._textureCache, self._materialCache, self._shadowCache, self._particleCache, self._postFxCache, self._terrainDefaults }) do table.clear(cache) end
    end
    function OptimizerService:Apply()
        self:RestoreAll()
        local revision = self._revision
        local performance = state:Get("Performance")
        processInstance(lighting, performance)
        local descendants = workspace:GetDescendants()
        for _, object in ipairs(lighting:GetDescendants()) do table.insert(descendants, object) end
        for index, object in ipairs(descendants) do
            if revision ~= self._revision or scope:IsDisposed() then return end
            processInstance(object, performance)
            -- Stream large maps in bounded chunks so a UI toggle cannot monopolize the executor thread.
            if index % 250 == 0 then task.wait() end
        end
    end
    function OptimizerService:ApplyFpsCap(value: number): (boolean, string)
        if not environment:HasFpsCap() then return false, "FPS-cap support is unavailable on this executor" end
        local ok = environment:SetFpsCap(value)
        return ok, if ok then (if value == 0 then "FPS uncapped" else "FPS cap applied") else "The executor rejected the FPS cap"
    end
    function OptimizerService:FlushMemory(): (boolean, string)
        local ok = pcall(function() collectgarbage("collect") end)
        return ok, if ok then "Garbage collection requested" else "This client restricts forced collection; Lua will collect automatically"
    end
    function OptimizerService:Initialize()
        if self._initialized then return end
        self._initialized = true
        for _, flag in ipairs(flags) do scope:Add(state:Observe("Performance." .. flag, function() OptimizerService:Apply() end)) end
        scope:Add(state:Observe("Performance.FpsCap", function(value: number)
            local ok, message = OptimizerService:ApplyFpsCap(value)
            if not ok and value ~= 0 then services:Get("EventBus"):Publish("Notify", "Performance", message) end
        end))
        scope:Connect(workspace.DescendantAdded, function(object: Instance) processInstance(object, state:Get("Performance")) end)
        scope:Connect(lighting.DescendantAdded, function(object: Instance) processInstance(object, state:Get("Performance")) end)
    end
    function OptimizerService:Destroy() scope:Dispose() end
    scope:Add(function() OptimizerService:RestoreAll(); environment:SetFpsCap(0) end)
    return OptimizerService
end
