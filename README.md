# B0Xaz Universal

B0Xaz Universal is a configurable Roblox utility suite with a searchable menu, saved profiles, and controls for several supported experiences.

**Version:** `2.4.9`

AI tools were used during development, including for code and documentation. The project author is responsible for the final published content.

> Use this only in experiences where you have permission. Using third-party tools may violate an experience's or platform's rules.

## Getting started

1. Open the [loader](https://raw.githubusercontent.com/B0Xaz1/Repo/main/loader.luau).
2. Copy it into a compatible Roblox Luau execution environment and run it after joining an authorized experience. Internet access is required.
3. Open the menu with **Right Shift** and enable the features you want.

Compatibility depends on the experience and execution environment. Use the official loader, and check **Settings → Compatibility checker** if a feature is unavailable. See the [changelog](CHANGELOG.md) for recent changes.

## Menu and profiles

The menu has tabs for Combat, Visuals, Movement, Players, Game, Commands, Utility, and Settings. Use search to find a control; star a control to keep it at the top of its tab. Most settings are saved in named profiles. You can compare profiles, use the built-in Default, Legit, and Rage presets, or assign a profile to a specific experience.

The Default profile restores default settings and cannot be overwritten. **Turn everything off** resets values and disables toggles without deleting saved profiles. Local saving and configuration import/export depend on file support in your execution environment. Bookmarks last for the current session.

## Supported experiences

Game-specific controls are available for:

- **Prison Life:** armory, weapon options, doors, macros, map locations, and player watch.
- **Prison Fight:** door controls and weapon macros.
- **Murderers VS Sheriffs DUELS:** enemy visuals, combat controls, and queue options.
- **Zombie Attack, including Hardmode:** kill aura, auto farm, auto equip, and status displays.

Other experiences use Universal Mode. Game updates can affect compatibility, and selecting a plugin manually does not guarantee it will work in another experience.

## Troubleshooting

- If the menu is hidden, press **Right Shift** or use the on-screen menu button if enabled.
- If settings do not persist, check that your environment supports local file access and review your profile preferences.
- If the layout feels too large, adjust menu scale or enable compact mode in Settings.
- Before unloading, remember that completed actions such as teleports cannot be undone. Use **End** or the unload action in Settings.

## License

This project is licensed under the [MIT License](LICENSE). You may use, copy, modify, and redistribute it, including for commercial purposes, provided you include the copyright and permission notice with copies or substantial portions of the software.