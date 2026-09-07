# Changelog

## 2.0.0 — 2026-09-07

- Prepared the complete Universal implementation for `main`.
- Changed the loader, direct entry point, and documented four-line bootstrap to default to `main`, while preserving explicit development-ref overrides.
- Bumped the displayed application version and added regression assertions for the release defaults.
- Retained fail-closed licensing and the unregistered example plugin; publishing does not replace backend configuration or Roblox/executor acceptance testing.

## 2.0.0-dev.1 — 2026-09-07

- Replaced the `.lua` placeholder scaffold with the streamed `.luau` public module layout.
- Added guarded boot/relaunch, session-local single-flight module caches, trace diagnostics, and pre-auth quick unload.
- Added scoped disposal, layered property/attribute restoration, linked-list events, permission-aware state, and protected frame pipelines.
- Implemented license and profile adapters, tracking, optimization, lighting, hotkeys, combat, movement, flight, extras, and pooled visuals.
- Added an unregistered, frozen-manifest example game adapter; no live game IDs or license backend were invented.
- Added seven searchable tabs, six theme presets, shared controls, and authentication/config-sharing modals.
- Added deterministic Luau tests for core, services, features, UI, and loader lifecycle contracts.

License backend configuration and Roblox/executor integration acceptance remain required before production deployment.
