# Changelog

## 2.4.9 — 2026-09-20

Zombie Attack auto farm.

- **Added:** `src/Plugins/ZombieAttack/AutoFarmService.luau`, mounted behind a new
  `Game.ZombieFarm` toggle in an Auto Farm section of the Game tab. It locks the nearest live
  zombie, holds the player 2 studs above and 2 studs behind that zombie's own facing, keeps
  firing at it until it dies, then takes the next nearest one. Both offsets live in
  `Manifest.Farm` alongside the suite's other engage offsets rather than in the service.
- **Added:** the hold is measured against the zombie's `LookVector`, not the camera's, so
  standing behind it stays true as it turns, and the frame is rebuilt every heartbeat so a
  zombie that walks off is followed rather than left. Placement goes through
  `LocomotionService:Teleport`, which zeroes assembly velocity and suppresses anti-fling, so
  the character sits firm instead of sagging between frames. Turning the toggle off stops
  placing and leaves the player where they were; nothing snaps back. The trade-off is that
  the teleport path suppresses anti-fling for 1.5 s per placement, so anti-fling stays
  suppressed for as long as the farm holds a position — continuous rather than one-shot, and
  unavoidable, since anti-fling would otherwise read the farm's own placement as an attack.
- **Changed:** target retention is sticky, matching the alive-then-next rule. Staying on a
  locked zombie costs a three-field validity read (`Model.Parent`, `Root.Parent`,
  `Humanoid.Health`), and the capped container scan runs only when that read fails — so a
  dead, despawned, or unparented zombie releases the lock and the next nearest is acquired
  without rescanning on every frame in between.
- **Changed:** the farm fires through the kill aura rather than around it. `KillAura` gained a
  public `FireAtTarget(target)` that shares the existing remote lookup, payload builder, and
  rate gate, so a second driver cannot outrun the configured fire rate. Its third return value
  separates "waited for the gate" from "tried and missed", which lets the farm's status line
  name a real problem (`No weapon equipped`) without reporting the normal rate-limit case.
- **Changed:** the kill aura's own loop stands down while `Game.ZombieFarm` is on. Both drivers
  share one rate gate, so leaving the aura looping would have alternated shots between the
  nearest zombie and the one the farm is standing on. Target part, range, and fire rate stay
  single-sourced from the kill aura section instead of gaining duplicate controls.
- **Changed:** `TargetService` resolves a body anchor (`Root`) alongside the aim part and
  exports it on `ZombieTarget`. The aim part defaults to `Head`, and standing two studs above
  a head is not standing two studs above a zombie; `Root` prefers `HumanoidRootPart`, falls
  back to `PrimaryPart`, then to the aim part. The change is additive — the kill aura still
  aims at `Part` and its payload is unchanged.
- **Changed:** the Auto Equip section moved to the right column so the Game tab reads as two
  combat drivers on the left and the support toggle above the statistics on the right.
- **Verified:** all 74 modules pass the structural check (Luau lexer plus block and bracket
  balance) that reported the pre-existing modules clean before this change. The Luau compiler
  was still not reachable from the build environment, so this is not a compiler pass.
- **Verified:** the farm, the kill aura, and the target service were transpiled to plain Lua
  and executed against a stubbed Roblox API with working `Vector3`/`CFrame` math — 34 farm
  checks, 23 aura and target checks, and the 29 auto equip checks re-run unchanged. The farm
  checks assert the exact placement (a zombie at the origin facing +Z puts the player at
  `(0, 2, -2)` turned toward it), lock retention across ticks, following a moving zombie,
  advancing on death, nearest-wins selection, a despawned lock, an empty field, the shared
  part and range settings, a dead or missing character, the rate-limit and failure reporting,
  respawn resets, and no snap-back on disable. The aura checks confirm all six payload fields,
  the `Origin` root-plus-1.5 offset, and the direction still normalized to 1000 studs.

## 2.4.8 — 2026-09-20

Zombie Attack auto equip.

- **Added:** `src/Plugins/ZombieAttack/AutoEquipService.luau`, mounted behind a new
  `Game.ZombieAutoEquip` toggle in an Auto Equip section of the Game tab. While it is on, the
  service equips the first Tool carrying a `GunController` child through `Humanoid:EquipTool`,
  searching the character before the backpack. Weapons are identified by that controller child
  rather than by tool name, so a new or renamed gun in the game needs no manifest change.
- **Added:** a gun already in hand is left alone, which keeps the loop from re-triggering an
  equip animation every tick, and a swap re-arms on a half-second interval so a server that
  refuses the equip, or a player who deliberately puts the gun away, is not fought per frame.
  The whole tick is rate-limited to four scans a second rather than running per frame.
- **Added:** controller matching resolves the manifest name recursively with
  `FindFirstChild(name, true)` — no descendant array is allocated — then falls back to a bounded
  case-insensitive walk, so a tool that nests the controller under a folder or spells it with
  different casing still counts. Both scans are capped, at 64 tools and 160 nodes per tool.
- **Added:** knives stay out of scope. A Tool carrying `KnifeController` is counted but never
  equipped, and the count is surfaced on the section's status line, which makes the naming
  assumption checkable in-game instead of taken on faith.
- **Added:** an `Equip gun now` button that runs the same detection and equip path once, with the
  toggle off, so a player can confirm what the adapter sees before arming the loop. The status
  line reports the state, guns, knives, swaps, and failures.
- **Fixed:** the swap throttle now stamps on an attempted equip rather than on every tick that
  reaches it. Stamping earlier meant a tick with no gun to take consumed the window, so a player
  who picked one up right after waited out an interval for nothing.
- **Changed:** the plugin's ready notification and its `Destroy` path cover auto equip alongside
  the kill aura, and `Game.ZombieAutoEquip` is registered in `GAME_BOOLEAN_FLAGS`, so a tier
  downgrade switches it off with the other game flags. The kill aura itself is untouched: its
  payload still reports the tool that is actually equipped, and auto equip is what keeps that
  tool a gun rather than a knife.
- **Verified:** all 73 modules pass a structural check (a Luau lexer plus block and bracket
  balance) that was calibrated to report the 72 pre-existing modules clean before this change.
  The Luau compiler itself was not reachable from the build environment, so this is not a
  compiler pass.
- **Verified:** the new service's control flow was transpiled to plain Lua and executed against a
  stubbed Roblox API, passing 29 behavioral checks: the off state, gun-over-knife selection,
  nested and mis-cased controllers, an unrelated tool ignored, the scan and swap windows, a dead
  character, respawn resets, the manual button, and the tool cap.

## 2.4.7 — 2026-09-20

Repository hygiene pass.

- **Changed:** the `--!strict` directive was dropped from all 72 modules, so the suite runs in
  Luau's default nonstrict mode. Type annotations stay; only the strict-mode checking is gone.
- **Changed:** comments were reduced to the mechanisms a reader cannot infer from the code.
  59 lines across 32 files, one or two lines each, placed above what they describe. Nothing that
  restates a name, a constant, or a literal survives.
- **Hygiene:** assertion messages that only repeated their own condition were dropped
  (`assert(type(snapshot) == "table", "Settings snapshot must be a table")`). Messages that name
  a value, path, or operation — and therefore explain a failure the condition does not — were
  kept, and every guard still runs.
- **Removed:** dead code found while reading: an unused `Players` service and a duplicated `UIS`
  local in `WallWalkService`, an unused `names` table in the `/help` handler, an unused
  `maxPerStrand` local in `AutoQueueService`, the write-only `_mode`, `_match`, `_thread`,
  `_lastWeapon`, and `_visualsPreview` fields, and the duplicated touch handler in
  `LocomotionService`.
- **Fixed:** misindented blocks in `HotkeyService` and `LocomotionService`.
- **Fixed (docs):** the README claimed every boot stage emits `[B0Xaz][Trace]` diagnostics. Boot
  tracing has not existed since 2.4.3.
- **Verified:** all 72 modules compile and load under the Luau compiler.

## 2.4.6 — 2026-09-20

Zombie Attack adapter.

- **Added:** `src/Plugins/ZombieAttack/` — a kill aura adapter for Zombie Attack by Zombie
  Attack Official, registered under place `1240123653` plus the `1632210982` Hardmode place
  in the same game. It is a port of a standalone Rayfield script: `TargetService` scans the
  game's `enemies` container for live zombie models sorted by distance, `KillAuraService`
  fires the game's own `ReplicatedStorage.Gun` remote at the nearest one on a rate gate, and
  `ZombieAttackUI` mounts both columns of the Game tab through the suite's own components.
  No Rayfield loader, window, tab, or notification call survives, and the script's `_G`
  settings are now `Game.ZombieAura*` state paths, so they save into profiles, reset with
  the section, and show up in menu search. The gun payload keeps the original shape exactly:
  `Normal`, `Direction`, `Name` (equipped tool), `Hit`, `Origin` (HumanoidRootPart + 1.5
  studs), `Pos`, with the direction still normalized to 1000 studs.
- **Changed:** the fire-rate timer advances on an attempted shot rather than only a
  successful one. The standalone script advanced it after success, so a player with no
  weapon equipped re-scanned every enemy on every frame indefinitely.
- **Added:** a hit-part fallback chain (`Head` → `UpperTorso` → `Torso` →
  `HumanoidRootPart`) so an R6 rig without the selected part is still engaged instead of
  silently skipped; a target range gate defaulting to `0` (unlimited, the original
  behavior); a bounded named sweep for the gun remote when `ReplicatedStorage.Gun` is
  absent, throttled to one scan every two seconds; and a miss counter with live status
  labels, so an aura that is not firing says why instead of looking idle.
- **Verified:** every `.luau` in the repository parses, and the adapter's modules —
  manifest, target scan, aura loop, payload builder, and plugin lifecycle — were executed
  against a stubbed Roblox environment with 61 assertions covering the payload keys and
  values, the rate gate, the part fallback, the failure paths, container streaming, and
  teardown.

## 2.4.5 — 2026-09-15

Game-plugin switch hotfix.

- **Fixed (critical):** turning off **Enable game plugin** in the Game tab killed the whole
  menu, not just that tab. `PluginManager` hands a plugin a service container whose
  `Disposer` resolves to the plugin's lifetime scope, and `InitializeAll()` activates the
  plugin *before* `UIEngine` builds any tab — so the shared UI components (`Section`,
  `Toggle`, `Slider`, `Keybind`, `Textbox`, `Dropdown`) were first instantiated through
  that plugin-scoped container. The loader cached modules by path alone, so every later tab
  received that same instance and **every** control in the suite hung off the plugin's
  disposer scope. Disabling the plugin disposed that scope and took the controls with it:
  state observers, input connections, and theme bindings were severed for all seven tabs,
  and the switch went inert, so the adapter could never be mounted again without a full
  reload. Modules are now cached per service container, so the root container keeps its own
  instances of the shared components and only the plugin's controls die with the plugin.
- **Fixed:** one click on the switch rebuilt the Game tab twice — once from the
  `Settings.PluginEnabled` observer and once from the control's callback — discarding the
  panel it had just built. `SetEnabled` now ignores a request for the state it is already in.
- **Fixed:** the Game tab kept advertising the matched adapter after it was switched off
  (`Active adapter: Prison Life` with no adapter running) and the Universal Mode panel never
  said why. The disabled state now reports `Universal Mode` and the panel names the adapter
  the switch would mount.

## 2.4.4 — 2026-09-15

Boot failure visibility hotfix.

- **Fixed (critical):** `init.luau` no longer compiled. The `if not ran then` guard in the boot
  `launch()` routine was deleted (fallout of the 2.4.3 print-removal pass), leaving an orphaned
  `failBoot()` and an unmatchable `end` — a guaranteed syntax error in the downloaded init chunk.
  Every load attempt died at `loadstring` and never reached the service registration.
- **Fixed (major):** the loader then swallowed the evidence: `if not booted then end` discarded
  the captured `bootError`, so a dead init compiled-or-not produced zero console output. The
  loader now warns `[B0Xaz] Loader failed: …` with the underlying error, and `init.luau` warns
  `[B0Xaz] Boot failed: …` / `[B0Xaz] Launch failed: …` on its two capture points. `B0XazRelaunch`
  also no longer discards its pcall result (`[B0Xaz] Relaunch failed: …`).
- **Fixed:** the task scheduler's circuit breaker silently disabled erroring jobs after 5 strikes
  (a feature would simply stop with no output). It now warns once with the job name and the last
  error when the circuit opens; strike/reset behaviour is unchanged.

## 2.4.3 — 2026-09-11

Menu responsiveness pass.

- **Performance (major):** the event bus now dispatches synchronously. Every toggle, slider tick,
  and per-frame state write publishes — previously each publish spawned one coroutine *per handler,
  per event* (plus two disposer registrations), so dragging a slider at 100+ events/sec produced a
  continuous coroutine/disposer churn. Handlers all run inline now (they never yielded anyway).
- **Performance:** dropdown option buttons are built lazily on first open instead of eagerly at menu
  construction, removing several hundred instances (plus strokes, hovers, and connections) from
  menu-open cost across the ~40 dropdowns in the suite.
- **Performance:** UI text/layout writes are change-detected (slider fill/value, toggle box,
  keybind button, dropdown button, textbox) — every `Text`/`Size` write on an `AutomaticSize`
  ancestor chain forces a full layout recompute, so identical writes are now skipped.
- **Performance:** the menu search box is debounced to one full cross-tab search per window instead
  of one reparenting pass per typed character.
- **Performance:** the lighting engine's 5 Hz reassert now skips property writes whose values did
  not change (a static preset was re-writing all 12 Lighting properties 5× per second, and slider
  drags re-ran materials scans per mouse move; observers are coalesced to one pass per resumption).
- **Performance:** same coalescing for the Prison Life door reapply — the phase-transparency slider
  applied ~1,000 parts per mouse move, now at most once per resumption window.
- **Hygiene:** boot tracing is gated behind an explicit flag (executor consoles serialise prints,
  and the module loader traced every fetch/compile), and per-tab boot prints were removed.

## 2.4.2 — 2026-09-11

Correctness pass from a full code review.

- **Fixed (major):** live transforms (CFrame, assembly velocities) were journaled like plain
  properties and *restored* on feature shutdown, rubber-banding the player. Disabling CFrame
  speed snapped you back to where you enabled it; any later override flush yanked you to a
  pre-teleport spot; stopping flight restored a long-stale fall speed; stopping spinbot and
  releasing an aim lock snapped the pose/camera backwards. The disposer gains
  `ReleaseProperty`/`ReleaseObject`/`ReleaseProperties` (drop a lease with no write) and every
  transform writer now releases on stop. Plain properties (`WalkSpeed`, `JumpPower`, gravity,
  FOV, `PlatformStand`, `AutoRotate`, door/weapon values, …) still restore exactly as before;
  the fling cycle keeps its intentional snap-back through its own scope.
- **Fixed:** loading an older profile no longer clobbers a customised legacy fly/menu keybind
  with the current default — the legacy↔current lockstep now mirrors only the representation
  the profile did not actually store; when a profile stores both representations, the current
  `Settings.Binds` entry wins and the legacy field follows it (applied symmetrically to the
  fly bind and the menu bind).
- **Fixed:** a runtime error in any single tab no longer fails the whole boot; the tab page now
  shows an inline "failed to load" section and the rest of the suite starts normally.
- **Fixed:** loading or importing a profile persists it to `_autoload.json` immediately, so a
  relaunch restores what you actually loaded instead of the previous autosaved session.
- **Fixed:** the scheduler circuit breaker no longer disables a job until restart — re-enabling
  the owning feature closes the circuit and resets the strike count.
- **Fixed:** refreshing a dropdown with unchanged options no longer closes an open menu
  (player/roster/bookmark refreshes were collapsing live dropdowns).
- **Hygiene:** stopped accumulating dead disposer entries — replaced scheduler jobs now remove
  themselves from both the pipeline and the scope; the macro stops via a generation tag instead
  of cancelling its worker; the viewport resize connection no longer double-registers on camera
  swaps; the Prison Life phase/macro signal connections no longer double-register; the vignette
  screen gui is now also forgotten from the master bag when cleared. Removed the dead
  `_parentSlot` field and the unused `_bypass` parameter on `StateStore:Set`.

## 2.4.1 — 2026-09-08

Menu performance pass. The Game tab refresh loop was the primary lag source: it
re-rendered every dynamic label four times per second whether or not the menu was
open or that tab was selected, and every `TextLabel` write cascades up through the
`AutomaticSize` layout chain to the window root. The armory block also errored each
pass (weapon spawns went through the location resolver, which expects a location
`CFrame`), so the render aborted with a `warn` every tick — console I/O that
executors make expensive.

- **Fixed:** the Game-tab render loop no longer errors on weapon distances —
  spawn positions are measured directly as `Vector3` (this also means the
  inventory, weapons, doors, macro, watch and status labels actually render now).
- **Performance:** Game-tab rendering is gated to run only while the menu is open
  *and* the Game tab is the active page; returning to the tab forces one
  immediate paint so nothing feels stale.
- **Performance:** refresh rate reduced 4 Hz → 2 Hz and every label write is
  change-detected (identical text is skipped), cutting the AutomaticSize layout
  cascades to a minimum.
- **Performance:** the door/obstacle reassert pass while phasing is throttled to
  ~5 Hz instead of every heartbeat — per-frame cost now stays flat regardless of
  how many obstacle parts are tracked.
- **Performance:** the search filter no longer rewrites page visibility across
  all seven tabs on every keystroke when no search is actually active.

## 2.4.0 — 2026-09-08

- Slimmed the Prison Life command center to the core toolkit. Removed: loadouts, role and target rules, weapon profiles, door glow and door mode, the status card, melee controls (punch aura and super punch), diagnostics, join/leave notifications, and the route runner.
- The Game tab is now: Armory and Weapon Mods on the left; Doors and Obstacles (phase + transparency only), Weapon Macro, Map Locations, and Player Watch on the right.
- Door phasing keeps the legacy include-everything behavior across all five obstacle containers; the per-class include filters, glow layer, and color picker are gone along with their state keys.
- State schema trimmed to the remaining features; the tier permission list now covers only the six surviving boolean flags. Player watch is role-free: a plain distance-sorted list with spectate, whitelist, and copy actions.

## 2.3.0 — 2026-09-08

- Ported the legacy Prison Life plugin's ground truth into the command center. The manifest now carries the legacy coordinates (Cafeteria, Prison Yard, Parking Lot, Roof, Secret Room, Tunnels, and the MP5 spawn), the seven-gun set (adding M4A1, M700, and Revolver), and the obstacle containers `doors`/`glass`/`celldoors`/`prison_fences`/`prison_gate`, matched case-insensitively.
- Weapon mods now honor both gun-stat mechanisms the game has used: instance attributes (`SpreadRadius`, `FireRate`, `AutoFire`, `Range`) on the tool or its children and the `GunStates` ModuleScript table, each backed up and restored independently. Legacy targets return: fire rate 0.001 and range 10000.
- Melee matches legacy behavior: the punch aura punches every valid target in radius each tick (~10/s) instead of only the nearest, and super punch fires on left click with fists out, bursting no-argument melee fires (~6 clicks/s cap, 1–30 hits).
- The weapon macro cycles only real guns (shared detection across the armory, macro, and weapon mods) and requires at least two, matching the legacy rule.
- Door phase defaults now include every obstacle class (cells, fences, gates, glass), matching the legacy "phase everything" toggle; the per-class filters narrow it.
- New parts under a known obstacle container are tracked live through `Workspace.DescendantAdded` while phasing or glow is active.

## 2.2.0 — 2026-09-08

- Added the Prison Life (place 155615604) command center plugin. The Game tab becomes a two-column control center: status, role and target rules, armory and loadouts, weapon profiles, and melee on the left; routes and map locations, doors and world interaction, weapon macro, player watch, and diagnostics with restore on the right.
- Role-aware targeting: team-based role detection with manual override, target-role dropdowns, and ignore rules that layer on top of the universal team/friend/whitelist/force-field/LOS checks used by the aimbot, triggerbot, and melee. ESP and chams can color players by role.
- Weapon profiles tune each gun's `GunStates` module; disabling a switch restores the captured originals immediately (restore-first reapply), and pickup uses the game's own ITEMPICKUP flow.
- Door phasing and glow are independent layers over `Doors`/`Prison_Fences` with per-class filters (cells, fences, gates, glass, decorative); either layer restores exactly its own properties when disabled.
- Locations resolve from CollectionService tags first, then named map objects, then manifest coordinates, with waypoints, favorites, and a stop-conditioned route runner. The melee and macro loops stop on death, respawn, focus loss, panic key, and unload.
- Game plugin settings now carry explicit `Game.*` defaults in the state schema. Tier downgrades disable only the boolean feature flags; numbers, strings, colors, and keybinds keep their values.
- Plugin activation and UI-mount failures are captured and surfaced (`PluginManager:GetLastError`, a plugin error panel, and the diagnostics card) instead of being swallowed.

## 2.1.10 — 2026-09-07

- Tightened the live menu toward the Combat-tab screenshot: cyan window frame, denser groupboxes/controls, compact title/tabs, and Combat laid out as Aimbot Controls / Aimbot FOV / Target Settings.

## 2.1.9 — 2026-09-07

- Cut idle frame cost: disabled ESP/chams/aimbot/flight/extras no longer run every frame, drawings are allocated lazily, and high-rate engine signals no longer spawn a thread per event.

## 2.1.8 — 2026-09-07

- Restyled the menu to the charcoal cyan suite: accent groupbox titles and borders, brighter Midnight cyan, `value/max` sliders, and the `B0Xaz Universal` title.

## 2.1.7 — 2026-09-07

- Theme presets now swap the full palette (backgrounds, panels, buttons, borders, and accents), not only the accent color.
- Added built-in Default, Legit, and Rage config presets for one-click load.
- Visuals tab opens a live ESP/chams preview. ESP and chams each have Rainbow and team-color toggles.

## 2.1.6 — 2026-09-07

- Added Movement touch fling: the Heartbeat / RenderStepped / Stepped velocity pulse, gated by a suite toggle. No third-party UI.

## 2.1.5 — 2026-09-07

- Removed the Jump Height override and its Movement-tab slider. Jump power remains.

## 2.1.4 — 2026-09-07

- Replaced unsupported Unicode in the live menu (close, chevrons, units, separators, toasts) with ASCII so labels no longer tofu.
- Tightened corners, borders, and type: 6px window, 3px panels/controls, softer teal accent, smaller Gotham labels.

## 2.1.3 — 2026-09-07

- Aimbot, triggerbot, and the FOV circle now use `GetMouseLocation` directly so they sit on the cursor again. Subtracting GuiInset had been raising the aim point by the topbar after the ESP inset fix.
- Gave the title bar tag room so it no longer clips, and moved the version label to the bottom-right of the menu frame.

## 2.1.2 — 2026-09-07

- Stopped adding GuiInset to Drawing ESP/FOV, which had dropped boxes, names, and skeletons below the player by the topbar height.
- Window dragging now applies mouse delta to the live UDim2 instead of mixing InputObject and AbsolutePosition spaces, so the first click no longer jumps the menu.
- Depth mode now applies to boxes, names, skeletons, and other ESP drawings as well as native chams.

## 2.1.1 — 2026-09-07

- Restyled the menu to a charcoal two-column suite: title-bar search, text tabs with a cyan underline, square checkboxes, stacked dropdowns, and knobless cyan sliders.

## 2.1.0 — 2026-09-07

- Removed the remote key-authentication flow, saved-key/device-ID storage, and gated feature levels.
- All included tabs, controls, hotkeys, services, and registered game adapters now initialize and operate without an access gate.
- Simplified the state store, UI controls, bootstrap graph, plugins, and runtime checks to remove access-level enforcement.
- Replaced MIT with the B0Xaz Universal Use-Only License: use is allowed, while copying and redistribution are prohibited.

## 2.0.0 — 2026-09-07

- Prepared the complete Universal implementation for `main`.
- Changed the loader, direct entry point, and documented four-line bootstrap to default to `main`, while preserving explicit development-ref overrides.
- Bumped the displayed application version and added regression assertions for the release defaults.

## 2.0.0-dev.1 — 2026-09-07

- Replaced the `.lua` placeholder scaffold with the streamed `.luau` public module layout.
- Added guarded boot/relaunch, session-local single-flight module caches, trace diagnostics, and pre-launch quick unload.
- Added scoped disposal, layered property/attribute restoration, linked-list events, and protected frame pipelines.
- Implemented profile adapters, tracking, optimization, lighting, hotkeys, combat, movement, flight, extras, and pooled visuals.
- Added an unregistered, frozen-manifest example game adapter; no live game IDs were invented.
- Added seven searchable tabs, six theme presets, shared controls, and configuration-sharing modal.
