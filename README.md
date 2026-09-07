# B0Xaz Universal

A streamed, dependency-injected **client-side Roblox Luau suite** with license tiers, seven searchable tabs, scoped cleanup, and reversible property ownership.

**Version:** `2.0.0` · **Default source ref:** `main`

> **Main build; deployment configuration and in-game verification are still required.** The implementation and deterministic tests are included. A real license endpoint has **not** been supplied, so authentication deliberately fails closed. The example plugin is **not registered** for any live game. Roblox/executor integration, visual layout, network behavior, and physics still need in-game acceptance testing.
>
> Use only in places you own or where you have permission. Client changes may be rejected by server authority and may violate a game's rules.

## Load

### Prerequisites

1. Configure the license adapter below. There is no hard-coded test key, offline tier grant, or authentication bypass in the application.
2. Load the files published on `main`, or explicitly select another published ref for development. The repository/ref must be accessible without embedding a GitHub credential in the client. Local workspace edits are not available at a raw GitHub URL until published.
3. Use a Roblox executor that can compile Luau with `loadstring` and fetch source with `game:HttpGet`. These are essential to the requested delivery model; optional executor APIs are not.

Paste this **four-line bootstrap**. It downloads the actual `loader.luau`, which owns readiness checks, launch locking, retries, and entry-point execution:

```luau
local g: any = _G; if type(getgenv) == "function" then local ok, env = pcall(getgenv); if ok and type(env) == "table" then g = env end end; g.B0XazRef = "main"
local url: string = "https://raw.githubusercontent.com/B0Xaz1/Repo/" .. g.B0XazRef .. "/loader.luau"
local source: string? = nil; for attempt = 1, 5 do local ok, body = pcall(function() return game:HttpGet(url .. "?t=" .. os.time() .. "_" .. attempt) end); if ok and type(body) == "string" and #body > 0 and not body:match("^%s*404") then source = body; break end; if attempt < 5 then task.wait(0.7 * attempt) end end
assert(source, "[B0Xaz] Loader download failed"); local chunk, err = loadstring(source :: string, "@B0XazLoader"); assert(chunk, err); chunk()
```

You can instead paste the contents of `loader.luau` directly. The selected source ref must contain `init.luau` and `src/`.

**Default controls**

- **Right Shift:** show/hide the menu.
- **End:** unload and restore. The listener is bound before license verification.
- **F:** toggle flight, if permitted.
- **Right mouse:** aim activation when enabled; hold/toggle behavior is configurable.
- **Ctrl + click:** teleport when enabled; touch uses a world tap.
- Flight: **WASD**, **Space** up, **Left Shift** down. Touch uses the thumbstick and up/down toggles.
- A small **B0Xaz** button reopens a hidden menu; touch does not need a keyboard.

Hotkeys ignore focused textboxes and active key capture. Escape during capture cancels and unbinds that control. The auth modal always has an unload action.

Public lifecycle APIs, using `getgenv()` when available and `_G` otherwise:

```luau
local g: any = _G
if type(getgenv) == "function" then g = getgenv() end
g.B0XazUnload()   -- drops public service references, disposes the session, then attempts console clearing
-- g.B0XazRelaunch() -- disposes first, then downloads the same normalized init URL
```

Normal repeated loader executions are refused. Use `B0XazRelaunch()` for an intentional reload. The default loader and direct entry point both resolve to `main`; an explicit `B0XazRef` or `B0XazBaseURL` can still select a development ref.

## Configure licensing

Edit the named constants at the top of `src/Services/KeyService.luau`:

```luau
local LICENSE_ENDPOINT: string = "https://your-license-service.example/verify"
local PUBLIC_KEY: string = "your-public-client-identifier"
```

These are **deployment values, not secrets**. `PUBLIC_KEY` is sent as `X-B0Xaz-Public-Key` when nonempty; leave it empty if your backend does not use that header. Do not put a private signing key, database credential, GitHub token, or administrative API key in this public client.

The adapter sends an HTTPS `POST` with JSON:

```json
{ "key": "user-entered-license", "hwid": "stable-device-id" }
```

Expected successful 2xx response:

```json
{ "success": true, "tier": "Full", "message": "License verified." }
```

Tier names are case-insensitive: `Entry`, `Normal`, `Full`. A success flag and a recognized tier are both required. A genuine rejection should return a nontransient status and a user-facing `message`, for example:

```json
{ "success": false, "message": "This license is assigned to another device." }
```

- Unreachable, 5xx, 408, and 429 responses receive **three total attempts** with increasing backoff.
- Other failures are shown immediately. Backend messages are rendered literally, not as rich text.
- Saved keys are **reverified** on every boot; the client does not trust an on-disk tier.
- Key storage is `base64(xor(json, public_salt))`: **obfuscation, not encryption**. Legacy plain-JSON key files remain readable.
- Clearing a license revokes the session tier immediately. If the executor cannot erase its saved file, the UI reports that limitation.

**Security boundary:** an executor user controls this entire client, including the state store and downloaded source. Client-side licensing is a product gate, **not tamper-proof authorization**. Any valuable server-side capability must be independently authorized by your backend. The backend must handle license issuance, HWID policy, expiration, revocation, rate limiting, and transport security; none of those are fabricated here.

## Tier matrix

The longest matching state-path prefix determines the requirement. Controls derive their locks from that same map; hydration and tier changes enforce it before dependent observers run.

| Tier | Name | Available tooling |
| --- | --- | --- |
| 0 | No Access | Settings only after logout: profiles, JSON editor, themes, binds, license, unload/relaunch. Cold boot remains at the auth gate. |
| 1 | Entry | Flight, CFrame speed, infinite jump, speed/jump/sprint overrides, gravity and camera FOV, hitbox expansion, spin, anti-fling, fullbright, cinematic lighting, speed lines, click teleport, bookmarks, player utilities, performance controls, anti-AFK and server travel. |
| 2 | Normal | Everything in Entry, plus Drawing ESP and native Highlight chams. |
| 3 | Full | Everything in Normal, plus aimbot, triggerbot, FOV overlay, fling attack and `Game.*` plugins. |

Feature binds can be configured in Settings at any tier. A bind cannot enable a locked feature. An active tab that becomes locked falls back to the first accessible tab. Search does not expose controls from inaccessible tabs.

## Interface

| Tab | Contents |
| --- | --- |
| Combat | Camera/mouse aim, R6/R15 hit parts, hold/toggle locks, exponential smoothing, WindMouse, prediction, independent target filters, FOV circle and triggerbot. |
| Visuals | Boxes, names, health, distance, tools/backpacks, tracers, skeletons, head dots/look direction, chams, optimization, lighting, telemetry and speed lines. |
| Movement | Humanoid overrides, sprint/air jump, displacement, flight, gravity/FOV, bookmarks and click/tap teleport. |
| Players | Live name filter, exact-first lookup, whitelist, teleport, spectate, copy name and bounded fling. |
| Utility | Hitboxes, spin, pre-physics anti-fling, idle prevention, auto-rejoin and public server hop. |
| Game | Place/universe information and the active adapter, or an explicit Universal Mode panel. |
| Settings | Profiles, launch precedence, JSON editor, scale/hotkeys, six themes with 18 live tokens, license and lifecycle actions. |

Search is case-insensitive and matches words across a control's label, section, and tab. Matching a section/tab brings in its group. Results keep group headers and move to the currently selected page. Clearing search restores every row's original parent and layout order; a filter error rolls the operation back.

Desktop pages use two columns. Narrow touch layouts stack them while retaining the same sections and search behavior. Theme presets: **Midnight, Graphite, Ocean, Rose, Forest, Paper**. Custom token colors are persisted; changing the accent derives its darker tones.

## Settings and profiles

`src/Core/StateStore.luau` is the authoritative, fully enumerated default schema. Feature switches ship off; filter/display suboptions have useful defaults. Speed, jump, gravity and camera-FOV overrides use **0 = leave the game's value alone**, not a guessed Roblox default. Watermark and menu visibility default on.

Small schema additions needed by the controls are explicit there: `Movement.JumpHeight`, `Movement.WorldGravity`, `Movement.Fling`, `Settings.MenuVisible`, and `Theme.CustomTokens`. `Movement.FlyKeybind` and `Settings.Binds.Fly` are synchronized legacy/current aliases; the menu bind has the same alias treatment.

Owned disk layout:

```text
B0XazUniversal/
├── _device.json
├── _key.json
└── Configs/
    ├── _autoload.json
    └── <sanitized-profile>.json
```

- All filesystem wrappers force paths under this root and reject traversal.
- `Default` is a read-only pseudo-profile: loading it resets settings; saving/deleting it is refused.
- Names are sanitized, and underscore-prefixed internal profile names are reserved.
- Profiles wrap `Color3` and `EnumItem` recursively. Imports are JSON data, never executed code.
- Loading deep-merges over defaults, so older profiles inherit new settings. Hydration markers prevent a load from immediately autosaving itself.
- Dirty sessions flush after 1.5 seconds and at cleanup. Bookmarks and runtime transients are not serialized.
- Launch precedence: **restore disabled → valid pinned profile → autosaved session → defaults**. The disabled-restore branch retains that preference and the pinned name.
- Without filesystem/clipboard support, the JSON editor still provides a manual copy/paste route. Files, keys, and device IDs are intentionally not deleted on unload.

## Architecture and cleanup

```text
executor → loader.luau → init.luau → src/**/*.luau

Disposer → Environment → EventBus → StateStore → TaskScheduler → ServiceContainer → DOM
  → quick-unload listener
  → services / combat / locomotion / visuals / plugin manager / theme / UI
  → saved-key verification or auth modal
  → InitializeAll → ConstructInterface → ApplyLaunchState
```

There is **no `require()`**, Rojo synchronization, package manager, bundler, or application build step. All application source is `.luau`. Paths are a public API: update every reference when changing a filename.

`init.luau` normalizes paths and uses per-session source, compiled-factory, and initialized-singleton caches. Fetches have cache busters and retries; concurrent requests for a module are single-flight. Calling a factory module with no arguments returns its raw factory, which is how tabs and plugin instances are mounted. Every boot stage emits `[B0Xaz][Trace]` diagnostics with fetch/compile/execute/init/cache boundaries.

Cleanup is centralized:

- Keyed disposer entries clean first; array entries clean in reverse order.
- Children own feature cycles. Completed tasks and disconnected subscriptions are removed from their owners.
- Late additions to a disposed owner are cleaned immediately.
- A shared property ledger captures before first write and layers overlapping owners. Static overlays preserve ownership precedence; live transform integrations compose in write order.
- Attribute leases restore both old values and original absence. Plugin and UI lifetimes use the same ownership rules.
- Ordinary event handlers are spawned and protected. The four scheduler signal dispatchers remain synchronous to preserve their engine phase; each individual job is protected.
- A job is permanently disabled after **five consecutive failures**; success resets its strikes. Other jobs continue.
- Drawing objects are hidden before removal, the camera render-step binding is unbound, and optional FPS-cap support receives `0` on unload.

### Restoration limits to understand

The implementation restores cached **client property values** and disposes owned connections, jobs, threads, Instances, constraints and Drawing objects. It cannot make an advancing multiplayer world literally become the hypothetical world in which the script never ran:

- A destroyed character, camera subject, or streamed-out Instance cannot be resurrected. Spectate falls back to the current local humanoid when its original subject is gone.
- Fired input, physics interactions, server-side consequences, backend license registration and completed teleports cannot be undone by a client disposer.
- Teleport queue APIs commonly provide no way to revoke one queued payload. A loader already queued for an initiated teleport may execute at the destination even after local unload. Persistent executor state is not an absolute cleanup guarantee.
- Most FPS-cap APIs have no getter. As specified, cleanup requests **uncapped (`0`)**, not an unknowable earlier cap.
- A game may legitimately change a property while an override is active. Cleanup restores the captured baseline, not a counterfactual future value.

These limits are reasons to run the manual acceptance checks below, not claims of perfect rollback of external effects.

## Game plugins

`src/Plugins/PluginRegistry.luau` is a flat place/universe map, with place ID taking precedence. It is intentionally empty until a specific game is supplied and verified.

`src/Plugins/ExampleGame/` is a working **opt-in test-place adapter**, not support for an unnamed commercial game. Its frozen manifest describes:

- Parts tagged `B0XazExampleDoor` through `CollectionService`.
- A tool named `ExampleBlaster` with `Spread` and `FireDelay` attributes.
- An illustrative lobby coordinate that must be replaced for your place.

Mechanics use property/attribute listeners to reassert changes, track newly tagged doors and re-equipped tools, and restore originals through a child disposer. They do not poll every frame. To integrate a real game, replace/verify its manifest and mechanics, then add one registry entry for its universe (or a place-specific entry). All plugin state belongs under `Game.*` and requires Full. Tier revocation destroys the active instance; reauthorization constructs a fresh one from the cached factory.

## Validation

The sandbox validation uses the **official Luau compiler/CLI 0.737**, not a Lua syntax approximation. Test source maps load real modules with deterministic Roblox/executor mocks. Application execution itself requires no compiler toolchain.

`tests/Run.luau` returns a runner factory taking `{ [repositoryPath] = sourceText }`. A host can provide this map from checked-out files or HTTP, compile the runner with `loadstring`, and call `:Run()`. The tests never fetch a live license or grant an application tier; their fake services exist only inside test environments.

For an executor with a **local checkout accessible via `readfile`**, this test launcher supplies the map without a package manager or application build:

```luau
local sources: { [string]: string } = {}
local function collect(folder: string)
    for _, path in ipairs(listfiles(folder)) do
        if isfolder(path) then collect(path)
        elseif path:match("%.luau$") then
            local normalized = path:gsub("\\", "/"):gsub("^%./", "")
            sources[normalized] = readfile(path)
        end
    end
end
collect("src"); collect("tests")
sources["loader.luau"], sources["init.luau"] = readfile("loader.luau"), readfile("init.luau")
local runner = assert(loadstring(sources["tests/Run.luau"], "@B0XazTests"))()(sources)
runner:Run()
```

That launcher is **test tooling**, not the production loader: its host must provide `readfile`, `listfiles` and `isfolder`, or otherwise inject an equivalent source map. The Luau CLI was exercised here with an ephemeral assembled source-map harness; no generated binary/harness is committed.

The final validation run passed **835 assertions**. All application and test files compiled successfully. Standalone analysis reports Roblox/executor globals and types as unknown without Roblox definitions; this is not a claim of a clean Roblox-aware type check.

Covered contracts include:

- Reverse/keyed/idempotent disposal, late cleanup, property layering, nil-valued attributes and thread cancellation.
- Linked-list disconnects, event isolation, schema cloning/merging, permission enforcement and aliasing.
- Five-strike circuit breaking, pipeline delta/priority semantics, weak-executor wrappers and RFC 4648 base64 vectors.
- License transient/rejection distinctions, saved-key reverification, profiles, reserved names and all launch branches.
- Late-streamed optimizer restoration, lighting/Fullbright/shadow overlap and bright-material grading.
- Friendship caching, independent filters, exact-first player lookup, Drawing reuse, flight cycles/respawn and tier revocation.
- The production exponential smoothing function at 30, 60 and 240 FPS.
- All seven actual UI tab factories: 190 controls, 115 bound paths, tier-map agreement, search restoration/rollback, shared key capture, themes, modals and zero owned UI Instances after cleanup.
- The complete real production construction graph reaches the unconfigured auth gate with engine APIs mocked, then unloads cleanly.
- Real loader/init control flow with stub application services: duplicate runs, concurrent module loading, cache boundaries, named errors, retries, bounded waits, URL normalization, pre-auth unload and non-overlapping relaunch.

### Required Roblox/executor acceptance — not yet performed

- [ ] Configure and test a real HTTPS license backend with Entry/Normal/Full, rejection, outage and revocation cases.
- [ ] Cold-load/autoexec the published `main` build from GitHub on representative executors.
- [ ] Verify desktop, touch, high-DPI layout, dragging, color controls, dropdowns, search and the auth gate in-game.
- [ ] Measure real aim/mouse feel at 30 and 240 FPS; inspect R6/R15 and unusual rigs.
- [ ] Exercise flight, repeated respawns, falling, teleports, hitboxes, spin and anti-fling against actual physics.
- [ ] Snapshot live humanoid, camera, gravity, Lighting, materials, terrain, particles and post-effects; compare after disable/unload.
- [ ] Inspect actual Drawing/Instance/connection/render-binding counts through repeated enable/disable/relaunch cycles.
- [ ] Validate both disconnect signals and executor-specific teleport queue behavior.
- [ ] Register and verify a concrete game's manifest before claiming game support.

Publishing to `main` is not evidence that these in-game checks have passed. Complete them before treating the build as production-ready. Develop subsequent changes on a separate working ref, validate them before merging, and bump `VERSION` in `init.luau` on each release. Keep the loader and entry-point default refs in agreement.

## License

MIT. See [LICENSE](LICENSE).
