# Changelog

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
