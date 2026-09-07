# Changelog

## 2.1.3 — 2026-09-07

- Aimbot, triggerbot, and the FOV circle now use `GetMouseLocation` directly so they sit on the cursor again. Subtracting GuiInset had been raising the aim point by the topbar after the ESP inset fix.

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
- Added deterministic Luau tests for core, services, features, UI, and loader lifecycle contracts.
