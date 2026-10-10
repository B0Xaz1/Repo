# Changelog

Release notes summarize user-visible additions, fixes, and compatibility changes.

## Unreleased

- Added a Da Hood (place 2788229376) fake macro: configurable hold key and ground-velocity speed slider in the Game tab. Steering now pushes into existing momentum for a sliding arc instead of snapping to the input direction. Inclines weaken the push, and airborne momentum remains untouched; this does not reproduce the game's macro glitch.

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
