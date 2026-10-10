local registry = require("../src/Plugins/PluginRegistry")()
local match = registry:Resolve(2788229376, 0)
assert(match and match.Name == "Da Hood")
assert(match.PluginModule == "src/Plugins/DaHood/Mechanics.luau")
local daHoodEntries = 0
for _, entry in ipairs(registry:GetRegistrations()) do
    if entry.Name == "Da Hood" then daHoodEntries += 1 end
end
assert(daHoodEntries == 1, "only one Da Hood adapter should be registered")
assert(registry:Resolve(1, 0) == nil)
print("Da Hood registry scenarios passed")
