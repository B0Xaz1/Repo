# B0Xaz Universal

A Roblox utility suite with a searchable menu, customizable themes, saved profiles, and controls for supported experiences.

**Version:** `2.4.9`

> Use only in places you own or where you have permission. Features may be limited by the experience or your execution environment, and use may violate an experience's rules.

## Getting started

1. Open the [official loader](https://raw.githubusercontent.com/B0Xaz1/Repo/main/loader.luau).
2. Copy its contents into a compatible Roblox Luau execution environment and run it after joining an authorized experience. Internet access is required.
3. Use the menu to enable the features you need and adjust their settings.

Use the official distribution only. Compatibility varies by device and execution environment; some features may be unavailable. For release notes, see the [changelog](CHANGELOG.md).

## Default controls

| Control | Action |
| --- | --- |
| Right Shift | Show or hide the menu. |
| End | Unload the suite. |
| F | Toggle flight. |
| Right mouse button | Activate aim assistance when enabled. |
| Ctrl + click | Teleport when enabled; touch devices use a world tap. |
| WASD / Space / Ctrl | Move horizontally / up / down during flight. |
| Shift | Boost flight speed. |

Touch flight supports the thumbstick and on-screen vertical controls. Hotkeys can be changed in Settings. They are ignored while typing or recording another keybind; Escape cancels key recording and clears that bind. Hiding the menu, changing tabs, or switching away from the game cancels an active recording without changing the existing bind.

## Menu

Use the search box to find controls by feature, section, or tab name.

| Tab | Contents |
| --- | --- |
| Combat | Aim assistance, targeting preferences, FOV display, and triggerbot controls. |
| Visuals | Player overlays, visual preview, lighting, performance options, and on-screen information. |
| Movement | Movement settings, flight, freecam, wall walk, bookmarks, and teleport controls. |
| Players | Player search, spectating, whitelist, and player actions. |
| Game | Experience information and supported game-specific controls. |
| Commands | Searchable command list, usage information, console, and recent commands. |
| Utility | Hitbox options, spin, anti-fling, idle prevention, rejoin, and server switching. |
| Settings | Profiles, backups, launch preferences, themes, menu scale, compact mode, hotkeys, and session controls. |

Themes include built-in presets and custom colors. Available controls depend on the active experience and execution environment.

## Profiles and preferences

- Save and load named profiles from Settings. The built-in Default profile resets settings and cannot be overwritten or deleted.
- Use the Default, Legit, and Rage presets as starting points, then adjust individual controls.
- Assign a profile to an experience to keep its saved session separate from other experiences. Later changes do not overwrite the assigned named profile.
- Choose whether to restore settings on launch, select a startup profile, or clear an experience's assignment in Settings.
- Use the backup and import/export controls to manage your configurations. Local saving requires file support in your execution environment.
- Bookmarks are session-only.
- For speed, jump power, gravity, and camera FOV overrides, **0 leaves the experience's value unchanged**.

## Supported experiences

Game-specific controls are available for:

- **Prison Life:** armory, weapon options, doors and obstacles, weapon macro, map locations, and player watch.
- **Prison Fight:** door controls and weapon macro.
- **Murderers VS Sheriffs DUELS:** enemy visuals, combat controls, and automatic queue options.
- **Zombie Attack, including Hardmode:** kill aura, auto farm, auto equip, and status displays.

Other experiences use Universal Mode. Game updates may affect compatibility. Manually selecting a game plugin does not guarantee that it will work in a different experience.

### Zombie Attack notes

Auto farm uses the target and firing preferences in the kill aura section. Stopping it leaves your character at the current location rather than returning to the starting point. Anti-fling protection is temporarily unavailable while auto farm is active. Auto equip is intended for guns, not knives.

## Ending a session

Press **End** or use the unload action in Settings. The suite attempts to restore changes it can undo, but unloading cannot reverse completed actions such as teleports or server-side effects. A pending action associated with a teleport may still run after unloading.

## Troubleshooting

- **The suite does not start:** check internet access, use the official loader, and confirm your execution environment is compatible.
- **The menu is hidden:** press Right Shift, your configured menu key, or the on-screen menu button if enabled.
- **A feature is unavailable:** check its settings, the active experience, and any displayed warning. The experience may reject client-side changes.
- **Settings do not persist:** confirm that local file access is supported and review your launch and profile preferences.
- **The layout is too large:** reduce menu scale or enable compact mode in Settings.

## License

Use is governed by the [B0Xaz Universal Use-Only License](LICENSE). It permits use under its terms but does not grant permission to copy, modify, publish, share, mirror, or redistribute the software or documentation, except for the limited temporary copies expressly allowed by the license.
