# B0Xaz Universal

A streamed, dependency-injected client-side Roblox Luau suite with searchable controls, scoped cleanup, configuration profiles, and reversible property ownership.

**Version:** `2.1.6` · **Default source ref:** `main`

> Use only in places you own or where you have permission. Client changes can be rejected by server authority and may violate an experience's rules.

## Access model

Every included control is available immediately after the suite starts. There is no license-key entry, account check, hardware identifier, remote validation request, or gated feature level in this build.

The repository is governed by the [B0Xaz Universal Use-Only License](LICENSE). It grants use of the software, but does **not** grant permission to copy, modify, publish, share, mirror, or redistribute the software or its documentation. The narrow exception for temporary copies needed by a device to load or run the authorized software is defined in the license text.

## Load

### Prerequisites

1. Publish the selected source ref so it is available from the raw GitHub URL. Local workspace edits are not available to a runtime loader until published.
2. Use an executor that supports Luau `loadstring` and `game:HttpGet`. Optional executor APIs degrade gracefully when unavailable.

Paste this four-line bootstrap. It downloads `loader.luau`, which owns readiness checks, launch locking, retries, and entry-point execution:

```luau
local g: any = _G; if type(getgenv) == "function" then local ok, env = pcall(getgenv); if ok and type(env) == "table" then g = env end end; g.B0XazRef = "main"
local url: string = "https://raw.githubusercontent.com/B0Xaz1/Repo/" .. g.B0XazRef .. "/loader.luau"
local source: string? = nil; for attempt = 1, 5 do local ok, body = pcall(function() return game:HttpGet(url .. "?t=" .. os.time() .. "_" .. attempt) end); if ok and type(body) == "string" and #body > 0 and not body:match("^%s*404") then source = body; break end; if attempt < 5 then task.wait(0.7 * attempt) end end
assert(source, "[B0Xaz] Loader download failed"); local chunk, err = loadstring(source :: string, "@B0XazLoader"); assert(chunk, err); chunk()
```

You can instead paste the contents of `loader.luau` directly. The selected ref must contain `init.luau` and `src/`.

### Default controls

- **Right Shift:** show or hide the menu.
- **End:** unload and restore session-owned changes.
- **F:** toggle flight.
- **Right mouse:** activate aim correction when enabled; hold/toggle behavior is configurable.
- **Ctrl + click:** teleport when enabled; touch uses a world tap.
- Flight: **WASD**, **Space** up, and **Left Shift** down. Touch uses the thumbstick plus up/down toggles.

Hotkeys ignore focused textboxes and active key capture. Escape while recording a bind cancels and unbinds it.

Public lifecycle APIs use `getgenv()` when available and `_G` otherwise:

```luau
local g: any = _G
if type(getgenv) == "function" then g = getgenv() end
g.B0XazUnload()     -- disposes the current session and attempts console clearing
-- g.B0XazRelaunch() -- disposes first, then downloads the same normalized init URL
```

Repeated loader executions are refused while a launch is in flight. Use `B0XazRelaunch()` for an intentional reload.

## Interface

| Tab | Contents |
| --- | --- |
| Combat | Camera/mouse aim, R6/R15 hit parts, hold/toggle locks, exponential smoothing, WindMouse, prediction, target filters, FOV circle, and triggerbot. |
| Visuals | Boxes, names, health, distance, tools/backpacks, tracers, skeletons, head dots/look direction, chams, optimization, lighting, telemetry, and speed lines. |
| Movement | Humanoid overrides, sprint/air jump, touch fling, displacement, flight, gravity/FOV, bookmarks, and click/tap teleport. |
| Players | Live name filter, teleport, spectate, copy name, whitelist, and bounded fling controls. |
| Utility | Hitboxes, spin, pre-physics anti-fling, idle prevention, auto-rejoin, and public server hop. |
| Game | Place/universe information and an active adapter, or an explicit Universal Mode panel. |
| Settings | Profiles, launch behavior, JSON import/export, scale/hotkeys, theme tokens, and lifecycle actions. |

The window is a charcoal two-column suite: **B0Xaz Universal Suite** in the title bar, version at the bottom-right of the frame, a compact `search...` field on the right, text tabs with an underline, square checkboxes, stacked dropdowns, and knobless sliders. In-game labels use ASCII so they render on every executor font. Search is case-insensitive and matches controls, sections, and tab names. Clearing search restores the original parent and layout order for every row. The menu includes six theme presets and 18 live color tokens.

## Settings and profiles

`src/Core/StateStore.luau` is the authoritative default schema. Feature switches ship off; display and filter options retain practical defaults. Speed, jump, gravity, and camera-FOV overrides use **0 = leave the game's value alone** rather than guessing a Roblox default.

Owned runtime files:

```text
B0XazUniversal/
└── Configs/
    ├── _autoload.json
    └── <sanitized-profile>.json
```

- Filesystem wrappers constrain paths to this root and reject traversal.
- `Default` is a read-only reset profile; it cannot be saved or deleted.
- Profiles serialize `Color3` and `EnumItem` values recursively. Imports are JSON data, never executable code.
- Older profiles deep-merge over new defaults, preserving new settings.
- Dirty sessions autosave every 1.5 seconds and at cleanup. Bookmarks and runtime transients are not serialized.
- Launch order is **restore disabled → pinned profile → autosaved session → defaults**.

## Architecture and cleanup

```text
executor → loader.luau → init.luau → src/**/*.luau

Disposer → Environment → EventBus → StateStore → TaskScheduler → ServiceContainer → DOM
  → quick-unload listener
  → services / combat / locomotion / visuals / plugin manager / theme / UI
  → InitializeAll → ConstructInterface → ApplyLaunchState
```

There is no `require()`, Rojo synchronization, package manager, bundler, or application build step. Application source is fetched as `.luau`; its paths are part of the runtime API.

`init.luau` normalizes module paths and uses per-session source, compiled-factory, and initialized-singleton caches. Fetches have cache busters and retries; concurrent requests for a module are single-flight. Every boot stage emits `[B0Xaz][Trace]` diagnostics.

Cleanup is centralized through `Disposer` scopes:

- Keyed entries clean first; ordinary entries clean in reverse registration order.
- Children own feature cycles, event subscriptions, tasks, instances, and Drawing objects.
- Late additions to a disposed scope clean immediately.
- Property and attribute leases capture originals before the first write and restore them when ownership ends.
- Scheduler jobs are isolated and disabled after five consecutive failures without interrupting unrelated jobs.
- Drawings are hidden before removal, camera render bindings are unbound, and optional FPS-cap support is reset to uncapped on unload.

### Restoration limits

The suite restores cached client-side properties and disposes the resources it owns. It cannot undo completed server-side effects, fired input, teleports, a destroyed character, or a streamed-out instance. A queued teleport payload may still run after local unload if the executor offers no revocation API.

## Game plugins

`src/Plugins/PluginRegistry.luau` maps place or universe IDs to adapters, with a place ID taking precedence. The registry is intentionally empty until a verified game adapter is registered.

`src/Plugins/ExampleGame/` is an opt-in test-place adapter. Its frozen manifest describes tagged doors and explicitly named tools, while its mechanics track and restore client-side changes through a child disposer. It is not registered for any live experience.

## Validation

`tests/Run.luau` returns a test-runner factory that accepts a repository source map. The tests use deterministic Roblox/executor mocks; production execution does not need a compiler toolchain.

Before publishing, manually verify representative desktop and touch executors, repeated launch/relaunch/unload cycles, respawns, optional executor APIs, visual layout, and restoration of all touched values.

## License

Use is governed by the [B0Xaz Universal Use-Only License](LICENSE). You may use the software under its terms, but copying or redistributing it is prohibited.
