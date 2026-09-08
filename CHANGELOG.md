# Changelog

## 2.4.1 — 2026-09-08

Menu performance pass. The Game tab refresh loop was the primary lag source: it
re-rendered every dynamic label four times per second whether or not the menu was
open or the Game tab was even selected, and every `TextLabel` write cascades up
through the `AutomaticSize` layout chain to the window root. On top of that, the
armory block was hitting a runtime error each pass (weapon spawns were routed
through the location resolver, which expects a location `CFrame`), so the render
aborted with a `warn` every tick — console I/O that executors make expensive.

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
