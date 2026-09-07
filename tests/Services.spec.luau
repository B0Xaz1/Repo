--!nonstrict
return function(sources: { [string]: string }, core: any): any
    local Test = { Passed = 0 }
    local function expect(condition: boolean, message: string) assert(condition, message); Test.Passed += 1 end
    local function instance(class: string, properties: any?): any
        local object = properties or {}
        object.ClassName, object.Name = class, object.Name or class
        object.Children, object.DescendantAdded = object.Children or {}, core.Signal()
        function object:IsA(name: string): boolean
            return name == class or (name == "BasePart" and (class == "Part" or class == "MeshPart"))
                or (name == "PostEffect" and (class == "BloomEffect" or class == "ColorCorrectionEffect"))
        end
        function object:GetDescendants(): any return self.Children end
        function object:Destroy() self.Destroyed = true; self.Parent = nil end
        return object
    end
    function Test:Run(): number
        local runtime = core.Environment
        local initialFiles = table.clone(core.Files)
        core.EnumType("Material", { "Plastic", "SmoothPlastic", "Neon", "Metal" })
        local material = runtime.Enum.Material
        local world = instance("Workspace")
        local lighting = instance("Lighting", { Ambient = runtime.Color3.new(0.1, 0.2, 0.3), OutdoorAmbient = runtime.Color3.new(0.2, 0.3, 0.4),
            Brightness = 3.75, ClockTime = 9.5, ExposureCompensation = 0.4, EnvironmentDiffuseScale = 1,
            EnvironmentSpecularScale = 1, GlobalShadows = true, ShadowSoftness = 0.3, FogStart = 2, FogEnd = 400, FogColor = runtime.Color3.new(1, 1, 1) })
        core.Services.Workspace, core.Services.Lighting = world, lighting
        runtime.Instance = { new = function(class: string) return instance(class) end }
        local master = core.Load("src/Core/Disposer.luau")().new("ServicesTest")
        local bus = core.Load("src/Core/EventBus.luau")(master)
        local state = core.Load("src/Core/StateStore.luau")(bus, master)
        local environment = core.Load("src/Core/Environment.luau")(master)
        local scheduler = core.Load("src/Core/TaskScheduler.luau")(master)
        local services = core.Load("src/Core/ServiceContainer.luau")(master)
        services.Version = "test"
        for name, value in pairs({ Disposer = master, Environment = environment, StateStore = state, EventBus = bus, TaskScheduler = scheduler,
            DOM = { Create = function(_dom: any, class: string, props: any) return instance(class, props) end } }) do services:Register(name, value) end
        local storageUnchanged = true
        for path, value in pairs(core.Files) do
            if initialFiles[path] ~= value then storageUnchanged = false; break end
            initialFiles[path] = nil
        end
        if next(initialFiles) then storageUnchanged = false end
        expect(storageUnchanged, "Boot services do not create obsolete authentication storage")
        local configs = core.Load("src/Services/ConfigService.luau")(services)
        configs:Initialize()
        state:Set("Movement.FlySpeed", 77)
        expect(configs.Dirty, "A user state change marks autosave dirty")
        expect(configs:Save(" ../my:profile? "), "Profile filenames are sanitized")
        expect(core.Files["B0XazUniversal/Configs/myprofile.json"] ~= nil, "Sanitized profile remains inside Configs")
        expect(not configs:Save("Default") and not configs:Delete("default") and not configs:Save("_autoload"), "Pseudo/default and internal names cannot be overwritten")
        state:Set("Movement.FlySpeed", 22)
        expect(configs:Load("myprofile") and state:Get("Movement.FlySpeed") == 77 and not configs.Dirty, "Loading hydrates without immediately autosaving itself")
        local json, clipboardMessage = configs:Export()
        expect(json ~= nil and clipboardMessage ~= nil, "Export still returns editable JSON without a clipboard capability")
        local decoded = core.Http:JSONDecode(json)
        expect(decoded.Settings.ESP.Color.__type == "Color3" and decoded.Settings.Aimbot.Keybind.__type == "EnumItem", "Config wrappers are applied recursively")
        state:Set("Movement.FlySpeed", 11)
        expect(configs:Import(json) and state:Get("Movement.FlySpeed") == 77, "Export/import is a two-way round-trip")
        local old = core.Http:JSONEncode({ Movement = { FlySpeed = 19 } })
        configs:Import(old)
        expect(state:Get("Movement.FlySpeed") == 19 and state:Get("Movement.FlySpeed") ~= nil and state:Get("Movement.SprintSpeed") == 28, "Legacy profiles inherit new defaults")
        state:Set("Settings.RestoreOnLaunch", false); state:Set("Settings.StartupProfile", "myprofile"); configs:Flush()
        expect(configs:ApplyLaunchState() == "disabled" and state:Get("Movement.FlySpeed") == 50, "RestoreOnLaunch=false applies no old feature state")
        expect(state:Get("Settings.RestoreOnLaunch") == false and state:Get("Settings.StartupProfile") == "myprofile", "Disabled restore preserves itself and the pinned profile")
        state:Set("Settings.RestoreOnLaunch", true); configs:Flush()
        expect(configs:ApplyLaunchState() == "profile:myprofile" and state:Get("Movement.FlySpeed") == 77, "Pinned profile wins over autosave")
        state:Set("Settings.StartupProfile", "missing"); state:Set("Movement.FlySpeed", 66); configs:Flush()
        expect(configs:ApplyLaunchState() == "autoload" and state:Get("Movement.FlySpeed") == 66, "Missing pinned profile falls back to autosave")
        expect(table.find(configs:ListProfiles(), "Legit") and table.find(configs:ListProfiles(), "Rage"), "Built-in Legit and Rage presets are listed")
        expect(not configs:Save("Legit") and not configs:Save("Rage"), "Built-in presets cannot be overwritten")
        expect(configs:Load("Legit") and state:Get("ESP.Enabled") and not state:Get("Aimbot.Enabled") and state:Get("ESP.UseTeamColor"), "Legit loads quiet ESP without aimbot")
        expect(configs:Load("Rage") and state:Get("Aimbot.Enabled") and state:Get("Chams.Enabled") and state:Get("Aimbot.Triggerbot.Enabled"), "Rage loads aimbot, triggerbot, and chams")
        expect(configs:Load("Default") and not state:Get("ESP.Enabled") and not state:Get("Aimbot.Enabled"), "Default restores a clean feature set")
        local part = instance("Part", { Material = material.Metal, MaterialVariant = "Custom", CastShadow = true, Reflectance = 0.5, Color = runtime.Color3.new(1, 1, 1) })
        local decal = instance("Decal", { Texture = "original-texture" })
        local particle = instance("ParticleEmitter", { Enabled = true })
        local terrain = instance("Terrain", { WaterWaveSize = 0.5, WaterWaveSpeed = 10, WaterReflectance = 0.9, WaterTransparency = 0.2, Decoration = true })
        local post = instance("BloomEffect", { Enabled = true })
        world.Children, lighting.Children = { part, decal, particle, terrain }, { post }
        local optimizer = core.Load("src/Services/OptimizerService.luau")(services); optimizer:Initialize()
        for _, flag in ipairs({ "NoTextures", "LowMaterials", "NoParticles", "NoShadows", "OptimizeTerrain", "NoPostProcessing" }) do state:Set("Performance." .. flag, true) end
        expect(decal.Texture == "" and part.Material == material.SmoothPlastic and not part.CastShadow, "Optimizer initial scan applies texture, material and shadow flags")
        expect(not particle.Enabled and terrain.WaterTransparency == 1 and not post.Enabled, "Particles, terrain and post effects are optimized")
        local late = instance("Decal", { Texture = "late-original" }); table.insert(world.Children, late); world.DescendantAdded:Fire(late)
        expect(late.Texture == "", "Late streamed objects use the same optimization path")
        state:Set("Performance.NoTextures", false)
        expect(decal.Texture == "original-texture" and late.Texture == "late-original" and not part.CastShadow, "Turning any flag off restores then reapplies remaining flags")
        optimizer:RestoreAll()
        expect(part.Material == material.Metal and part.MaterialVariant == "Custom" and part.CastShadow and terrain.WaterReflectance == 0.9 and post.Enabled, "All optimizer caches restore pre-touch values")
        for _, flag in ipairs({ "NoTextures", "LowMaterials", "NoParticles", "NoShadows", "OptimizeTerrain", "NoPostProcessing" }) do state:Set("Performance." .. flag, false) end
        local grade = core.Load("src/Services/LightingService.luau")(services); grade:Initialize()
        grade:SetMode("Static Day")
        expect(lighting.Brightness ~= 3.75 and lighting.ClockTime == 14, "Static lighting applies")
        grade:SetMode("Static Night")
        expect(lighting.ClockTime == 0.5, "Static mode switches without replacing the original snapshot")
        state:Set("Lighting.RemasterMaterials", true)
        expect(part.Reflectance <= 0.015, "Near-white materials reduce reflectance")
        state:Set("Performance.NoShadows", true)
        expect(not lighting.GlobalShadows, "Lighting yields GlobalShadows to optimization")
        state:Set("Visuals.Fullbright", true)
        expect(lighting.ClockTime == 14 and not lighting.GlobalShadows, "Fullbright owns the grade while active")
        state:Set("Visuals.Fullbright", false); grade:SetMode("Off"); state:Set("Performance.NoShadows", false)
        expect(lighting.Brightness == 3.75 and lighting.ClockTime == 9.5 and lighting.GlobalShadows, "Lighting and optimizer unwind to the real baseline in either order")
        expect(part.Reflectance == 0.5 and post.Enabled, "Remaster restoration does not destroy the game's post effect")
        master:Dispose()
        print(string.format("PASS Services: %d assertions", Test.Passed))
        return Test.Passed
    end
    return Test
end
