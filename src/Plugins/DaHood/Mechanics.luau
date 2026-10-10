return function(services: any): any
    local load = services:Get("Require")
    local state = services:Get("StateStore")
    local manifest = load("src/Plugins/DaHood/Manifest.luau", services)
    local scope = services:Get("Disposer"):CreateChild("Plugin Da Hood")
    local macro = load("src/Plugins/DaHood/SpeedMacroService.luau", services, manifest)
    local Plugin = { Name = manifest.Name, _initialized = false }

    function Plugin:Initialize(_container: any)
        if self._initialized then return end
        self._initialized = true
        -- These are profile settings, not Da Hood's own MacroKey/MacroSpeed attributes.
        if state:Get("Game.DaHoodMacroEnabled") == nil then state:Set("Game.DaHoodMacroEnabled", false) end
        if state:Get("Game.DaHoodMacroKey") == nil then state:Set("Game.DaHoodMacroKey", manifest.Macro.DefaultKey) end
        if state:Get("Game.DaHoodMacroSpeed") == nil then state:Set("Game.DaHoodMacroSpeed", manifest.Macro.DefaultSpeed) end
        macro:Initialize()
    end

    function Plugin:BuildUI(tab: any)
        local section = load("src/UI/Components/Section.luau", services)
        local toggle = load("src/UI/Components/Toggle.luau", services)
        local keybind = load("src/UI/Components/Keybind.luau", services)
        local slider = load("src/UI/Components/Slider.luau", services)
        local panel = section:Create(tab.LeftCol, "Da Hood - Fake Macro")
        toggle(panel, "Enable fake macro", "Game.DaHoodMacroEnabled")
        keybind(panel, "Hold key", "Game.DaHoodMacroKey")
        slider(panel, "Ground speed", "Game.DaHoodMacroSpeed", manifest.Macro.MinSpeed, manifest.Macro.MaxSpeed, 1)
        section:Info(panel, "Hold to accelerate along the ground. Steep slopes reduce the boost; in the air, no velocity is added or removed. The server may override local motion.")
    end

    function Plugin:Destroy()
        macro:Destroy()
        scope:Dispose()
    end

    return Plugin
end
