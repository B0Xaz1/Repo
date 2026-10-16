# Changelog

Release notes summarize user-visible additions, fixes, and compatibility changes.

## Unreleased

- Added a Full-edition, whitelist-gated chat relay for target-only actions. A player explicitly added to the existing target whitelist can type `!b tp`, `!b follow`, `!b unfollow`, `!b spectate`, `!b stopspectate`, `!b target`, or `!b cleartarget`; the action always targets that speaker on the local suite client. It cannot run general menu commands, change settings, or act on another named player. Local `!b` chat echoes are ignored rather than producing an unknown-command error.
- Fixed a Full-box ESP runtime override that referenced a removed native-box function and could stop the overlay render job entirely. The intended native Full-box renderer is now the only Full-box renderer.
- Selected-player Highlight now reattaches to a target's newly resolved character after death/respawn. Its retries are limited to the respawn handoff and it continues to follow theme changes.
- Moved common Full-box ESP geometry and the optional health bar into the existing shared native ScreenGui, eliminating the per-target executor Drawing path for the default mode. Each Full-box outline has four opaque native edges under an almost-transparent container, avoiding executor GUI hosts that cull fully transparent containers while reducing each moving box to one position write and one size write. Corner boxes retain their line-based style. ESP still renders synchronously rather than on a visual timer.
- Reworked the Player ESP hot path without any visual timer or Hz cap: camera state is shared per render, screen bounds use scalar caches, native labels rebuild text only when their source values change, and Drawing primitives only receive changed scalar geometry. Cached occlusion rays now reuse their exclusion data instead of allocating it per ray. Rendering remains frame-synchronous.
- Player ESP, readouts, and chams now hide while the suite menu is open, so executor Drawing primitives cannot bleed through the menu. Its render job and activity watches resume when the menu closes.
- Added a **Show self ESP** toggle, off by default, so the compact player ESP can also render the local character when wanted.
- Added a selected-player **Follow** control in Players → Player utilities. It repeatedly performs the same offset teleport as the existing Teleport-to-player action while active, changes to **Stop following**, survives a brief target respawn gap, and stops if that player leaves or an incompatible movement mode is enabled.
- Added an optional Player ESP activity row. It shows **Active** or estimated **AFK** after 60 seconds without replicated movement, relevant Humanoid activity, or tool changes. Roblox does not expose another player's window-focus state to a client, so this deliberately labels an idle/activity estimate rather than claiming to detect remote window focus.
- Strengthened standard Humanoid movement compatibility: configured Jump Power now temporarily enables `UseJumpPower` where an experience uses `JumpHeight`; Sprint recognizes both Shift keys; and active WalkSpeed, JumpPower, and UseJumpPower overrides reassert only when that Humanoid property is changed. Infinite Jump still requests Roblox's normal jumping state first, then has a conservative vertical-velocity fallback that preserves horizontal motion when that state is immediately rejected or overwritten.
- Restored the automatic, internal repair for executors that fall back to 60 FPS after Roblox GUI focus or a fresh scene render. It requests a high executor ceiling at launch, after menu-open settlement and coalesced camera motion, and on unload; its guarded scheduler-target companion is reapplied on each repair so a later player-visibility reset is not left at 60. There is no frame-rate slider, button, setting, polling loop, or ESP visual throttle.
- Returned the compact per-player status readout to the single shared ScreenGui route after per-target billboards reintroduced a player-visibility cap. It keeps one lightweight native TextLabel per target while removing costly glyph strokes and shrinking the label surface; name, range, numeric health, and tool remain independently switchable. The default Full-box overlay remains one executor Drawing box per target (the optional health bar adds one line). When an ESP Drawing, status label, or chams highlight transitions visible, the existing high-frame-rate repair is coalesced into two finite delayed writes so executors that reset at overlay visibility do not remain at 60.

- Rebuilt Performance around reversible, incremental rendering changes that avoid full-world restoration and repeated scans whenever an individual toggle changes.
- Added Balanced and Maximum performance presets, a visual-quality restore action, dynamic-light and highlight reduction, and expanded atmosphere, clouds, terrain, particle, shadow, texture, and material optimization.
- Added complete custom-lighting scenes: Neutral, Golden Hour, Overcast, Moonlight, and Neon. Each scene applies coordinated environment, fog, bloom, and color-grade settings; changing mode, time, brightness, or vignette returns to Custom while preserving manual values.
- Removed the manual Performance maintenance panel and its reapply/forced-collection functions. Telemetry & motion now lives as a disclosure row inside Player ESP.
- Removed frame-rate cap and uncapping controls entirely. The menu no longer calls executor FPS-cap or scheduler settings APIs.
- Running a newly copied loader now cleanly replaces an active older session and selects the new loader's immutable build, rather than silently relaunching the old session revision.
- The visible menu now prefers Roblox's engine-owned `PlayerGui` over executor GUI hosts, avoiding executor-host-specific composition behavior while the menu is open.
- Rebuilt player ESP as a classic full or corner-box readout: independent player-name and distance labels above the box, numeric health with an optional bar on the left, equipped tool (or `[None]`) below, and an optional native chams layer. Added a configurable render-distance limit.
- Reworked ESP performance without visual rate caps: overlays now follow the render frame, while body-only bounds rebase only after meaningful spatial, depth, viewport, or rig changes and scale smoothly from the projected root each frame. Tool and rig cache invalidation is event-driven; occlusion and chams only reconcile when their geometry or appearance changes. Malformed-rig fallback, color behavior, and the single top-level ESP node remain intact.
- Reduced default full-box ESP executor primitive pressure from seven Drawing objects per player to three: name and range share one two-line identity drawing, the optional health bar is one colored line, and numeric health plus tool text use native Roblox labels. Individual name/range toggles, numeric health, tool placement, and full/corner box choices remain available.
- Replaced the per-target native-label route after it regressed visible-player headroom. Default full-box ESP now uses two Drawing primitives per player—a box and a compact multi-line readout containing the independently switchable name, range, numeric health, and tool label. The graphical health bar remains available as a third primitive but is off by default (including built-in ESP presets). ESP still follows every render frame without a visual timer cap.
- Reduced the default executor-side full-box ESP footprint again: the box is now the only executor Drawing object per target, while the complete compact readout is one managed native label per target. This specifically removes the remaining second Drawing object without restoring the earlier two-native-label layout. The optional health bar remains off by default and adds one Drawing line only when enabled.
- Added a full-width selected-target card to Players with an avatar, identity, account age, status, and Teleport, Spectate, Select as Target, and Highlight actions. An explicit target is transient and takes priority over FOV scoring only while it passes the active target filters.
- Restored client-contained virtual mouse movement for input-driven features. Virtual-input features now pause only when Roblox is not the focused window (or client-contained virtual input is unavailable); UI, text, and keybind state no longer globally suppress active player-input automation.
- Aimbot now accepts its configured aim bind even when Roblox marks it processed (including the default right mouse button), so the player’s explicit mouse-lock input reaches the selected target part.
- Added an explicitly authorized real relative-cursor mouse-aim path: when the executor exposes `mousemoverel`, mouse mode moves the player’s cursor toward the selected target part while Roblox is focused; camera correction remains the fallback when it is unavailable.
- Stabilized native mouse aim at low smoothness by bounding its delayed feedback, limiting relative steps, adding a small settle zone, and preventing generated mouse movement from tripping Break On Mouse Pull.
- Added sticky aim lock: the selected target stays locked through an off-screen interval and is cleared immediately when the Hold bind is released (or when a Toggle lock is turned off).
- FPS and ping telemetry now use the active menu accent and the same typography as the watermark.
- Simplified the in-game Full/Lite edition picker into a straightforward menu with clear option rows and a normal checkbox-style remember choice.
- The entire menu top bar is now a drag surface except for its controls. The X button now asks for confirmation before fully unloading and restoring the session, with a high-contrast confirmation label.
- Added a lightweight in-game Full/Lite edition picker. It can remember a Full or Lite choice locally, or leave the player to choose on each loader launch.
- Added the **Edition next launch** setting with Ask every launch, Lite, and Full choices. Edition preferences are separate from profiles; relaunches and queued teleports retain the active edition.
- Lite keeps the menu shell and universal controls while omitting Commands, the Game workspace, and all game-specific plugin adapter discovery and UI. Full preserves the complete existing experience.
- Continued the menu revamp: touch devices now use a horizontal workspace picker, desktop search supports Ctrl/Cmd + K and Escape, and focused controls are selectable for keyboard and gamepad navigation.
- Made Compact the default interface density, added profile-apply status feedback and recovery controls for interface layout, Midnight, and confirmed full defaults.
- Overview now loads every current patch-note bullet directly from the immutable build's CHANGELOG.md under “What changed in this revamp,” while Workspace sits below Pinned controls.
- Removed Overview quick actions and moved the Full-edition Game workspace to the end of the navigation order.
- Refined the monochrome Midnight theme and removed the floating ESP preview window.

- Reworked the suite into a menu workspace with a navigation rail, command bar, Overview dashboard, contextual page headings, and dedicated minimize and unload controls. The visual system, themes, profiles, search, favorites, and existing controls remain compatible.

- Hardened automated input: removed executor-native mouse clicks and cursor movement, so automated clicks now use Roblox virtual input only. Automated combat input pauses while the suite menu, a text field, keybind recording, Roblox UI under the pointer, or a non-focused Roblox window would make input unsafe.
- Added a gameplay-only mouse capture toggle in Movement. It centers the cursor while Roblox gameplay is focused and releases it for the suite menu, Roblox UI, text entry, keybind capture, or another desktop window.
- Reduced idle and per-frame overhead across Murderers VS Sheriffs, Zombie Attack, no-clip, Wall Walk, ESP, and performance optimization. Queue retry delay now controls automatic requeue attempts.
- Improved property restoration for one-shot teleports, temporary attacks, freecam, and Prison Life door rescans.
- Hardened remote loading and queued relaunches by pinning downloads to immutable full commit IDs instead of mutable branch or base-URL overrides.

- Added a Da Hood (place 2788229376) fake macro: configurable activation key (default V), Hold/Toggle mode, and ground-velocity speed slider in the Game tab. S is required for a boost in either mode; V alone never changes velocity. S pushes forward relative to the camera and the character turns to face the glide. Acceleration is quicker, the speed slider reaches 400 (new default 180), and turns retain momentum. Inclines weaken the push, and airborne velocity remains untouched. This does not reproduce the game's macro glitch.

- Switched to the MIT License, which permits use, modification, and redistribution subject to retaining the copyright and permission notice.
- Documented the use of AI tools during development.
- Removed tooltip overlays and help markers from controls.
- Removed per-game profile auto-load and the compatibility checker from Settings.

- Removed the lighting-mode hotkey; lighting remains adjustable in the Visuals tab.
- Removed dropdown option outlines and selection bars, keeping hover feedback and selected-text highlighting.

- Added favorites that pin controls at the top of their own tab and restore with saved configurations.
- Removed profile comparisons from Settings.
- Added Off, Subtle, and Full animation styles with adjustable playback speed.

- Removed the "Turn everything off" action from Config profiles.

- Refined control feedback with animated checkmarks, responsive slider thumbs, dropdown selection highlighting, and a gliding tab indicator.
- Added softer notification fades and clearer feedback for busy actions and keybind recording.

- Added subtle hover, press, and focus feedback across menu controls.
- Added snappy transitions for windows, tabs, dropdowns, color pickers, and notifications.
- Improved responsiveness during search, command filtering, and visual previews.
- Fixed recovery from interrupted menu searches and keybind recording.
- Improved mixed mouse/touch handling and cancellation of color previews.
- Improved reliability when restarting background tasks and cleaning up closed controls or ended sessions.

- Added per-experience profile assignments in Settings, with separate saved sessions for assigned experiences.
- Changes in an assigned experience no longer overwrite its named profile or the general saved session. Launch preferences remain shared; clearing an assignment stops restoring that experience's saved session.
- Updated the README and release history to focus on usage and user-visible changes.

## 2.4.9 — 2026-09-20

- Added Zombie Attack auto farm, with status information and a stop action.
- Auto farm follows a target until it is defeated or unavailable, then selects another.
- Auto farm shares target and firing preferences with kill aura.
- Stopping auto farm leaves the character at its current location. Anti-fling protection is temporarily unavailable while auto farm is active.
- Reorganized the Zombie Attack Game tab.

## 2.4.8 — 2026-09-20

- Added Zombie Attack auto equip for guns, plus an "Equip gun now" action.
- Added equip status information and failure reporting.
- Improved handling of weapons already equipped and newly acquired guns. Knives are not automatically equipped.

## 2.4.7 — 2026-09-20

- Maintenance release with no intended feature changes.
- Corrected outdated documentation.

## 2.4.6 — 2026-09-20

- Added Zombie Attack support, including Hardmode.
- Added kill aura with configurable firing, target part, and range preferences.
- Added live status information, a manual test action, and a stop action.
- Integrated Zombie Attack controls with profiles and menu search.

## 2.4.5 — 2026-09-15

- Fixed disabling a game plugin making the rest of the menu unresponsive.
- Improved reliability when toggling game plugins.
- Corrected the displayed mode when a game plugin is disabled.

## 2.4.4 — 2026-09-15

- Fixed a critical issue that prevented the suite from starting.
- Improved error reporting for startup, relaunch, and interrupted features.

## 2.4.3 — 2026-09-11

- Improved responsiveness when using toggles, sliders, dropdowns, and menu search.
- Reduced startup overhead and unnecessary interface updates.
- Improved responsiveness when adjusting lighting and Prison Life door settings.

## 2.4.2 — 2026-09-11

- Fixed unwanted position, movement, and camera snap-back when stopping features.
- Improved keybind compatibility with older profiles.
- An unavailable tab no longer prevents the rest of the suite from starting.
- Loading or importing a profile now saves it promptly for the next launch.
- Improved recovery when re-enabling an interrupted feature.
- Fixed dropdowns closing unnecessarily during list refreshes.
- Improved session cleanup reliability.

## 2.4.1 — 2026-09-08

- Improved menu responsiveness, especially in the Prison Life Game tab.
- Fixed missing or outdated Game-tab status information.
- Reduced background overhead when the Game tab is not in use.
- Improved door-control and menu-search performance.

## 2.4.0 — 2026-09-08

- Simplified the Prison Life command center around armory, weapon options, doors, weapon macro, map locations, and player watch.
- Removed loadouts, role filters, weapon profiles, door glow and mode options, melee controls, route runner, diagnostics, and join/leave notifications.
- Simplified player watch and door controls.

## 2.3.0 — 2026-09-08

- Expanded Prison Life map locations and supported weapons.
- Improved compatibility and restoration for weapon options.
- Updated melee behavior and weapon macro requirements.
- Improved door coverage and handling of newly available obstacles.

## 2.2.0 — 2026-09-08

- Added the Prison Life command center with game-specific combat, armory, navigation, door, macro, and player-watch controls.
- Added role-aware targeting and visual preferences.
- Added profile support for game-specific settings.
- Improved game-plugin error reporting.

## 2.1.10 — 2026-09-07

- Refined the menu's cyan styling, compact controls, and Combat-tab organization.

## 2.1.9 — 2026-09-07

- Reduced idle performance overhead when features are disabled.

## 2.1.8 — 2026-09-07

- Refreshed the charcoal-and-cyan theme, section styling, slider labels, and menu title.

## 2.1.7 — 2026-09-07

- Theme presets now update the full menu palette.
- Added Default, Legit, and Rage configuration presets.
- Added a live visual preview and rainbow/team-color options.

## 2.1.6 — 2026-09-07

- Added touch fling to the Movement tab.

## 2.1.5 — 2026-09-07

- Removed the jump-height override. Jump-power controls remain available.

## 2.1.4 — 2026-09-07

- Fixed unsupported characters appearing in menu labels.
- Refined corners, borders, colors, and typography.

## 2.1.3 — 2026-09-07

- Corrected cursor alignment for aim assistance, triggerbot, and the FOV circle.
- Fixed title-bar clipping and repositioned the version label.

## 2.1.2 — 2026-09-07

- Corrected visual-overlay alignment.
- Fixed the menu jumping when dragging begins.
- Made visual depth preferences more consistent across overlays.

## 2.1.1 — 2026-09-07

- Introduced the charcoal two-column menu with title-bar search, cyan tab accents, and refreshed controls.

## 2.1.0 — 2026-09-07

- Removed key entry and feature-tier restrictions; included controls became available without an access gate.
- Adopted the B0Xaz Universal Use-Only License, replacing MIT. See [LICENSE](LICENSE) for terms.

## 2.0.0 — 2026-09-07

- Released B0Xaz Universal for general use.
- Updated the default launch instructions for the release.

## 2.0.0-dev.1 — 2026-09-07

- Introduced the Universal development preview.
- Added profiles, combat, movement, flight, visual, lighting, optimization, and utility controls.
- Added seven searchable tabs, six theme presets, and configuration sharing.
- Added launch, relaunch, and unload support.
