--!nonstrict
-- Test-only entry point. Supply repository file contents as a source map; no filesystem/executor library is required by the harness.
return function(sources: { [string]: string }): any
    local Runner = {}
    local function factory(path: string): any
        local chunk, message = loadstring(assert(sources[path], "Missing test source '" .. path .. "'"), "@" .. path)
        assert(chunk, message)
        return chunk()
    end
    function Runner:Run(): number
        local core = factory("tests/Core.spec.luau")(sources)
        local total = core:Run()
        for _, path in ipairs({ "tests/Services.spec.luau", "tests/Features.spec.luau", "tests/UI.spec.luau", "tests/Lifecycle.spec.luau" }) do
            total += factory(path)(sources, core):Run()
        end
        print(string.format("PASS B0Xaz: %d assertions", total))
        return total
    end
    return Runner
end
