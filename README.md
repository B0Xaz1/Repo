# B0Xaz Universal

B0Xaz Universal is a configurable Roblox utility suite with a searchable menu, saved profiles, and controls for several supported experiences.

**Version:** `2.4.9`

AI tools were used during development, including for code and documentation. The project author is responsible for the final published content.

> Use this only in experiences where you have permission. Using third-party tools may violate an experience's or platform's rules.

## Getting started

1. Open the [loader](https://raw.githubusercontent.com/B0Xaz1/Repo/main/loader.luau).
2. Copy it into a compatible Roblox Luau execution environment and run it after joining an authorized experience. Internet access is required.
3. Open the menu with **Right Shift** and enable the features you want.

Compatibility depends on the experience and execution environment. Use the official loader. See the [changelog](CHANGELOG.md) for recent changes.

### Try the Da Hood development branch

To run the version on `arena/60a84a4d-repo` rather than `main`, use this branch-specific loadstring in a compatible Luau execution environment:

```lua
local env = (type(getgenv) == "function" and getgenv()) or _G
if type(env.B0XazUnload) == "function" then env.B0XazUnload() end
env.B0XazRef = "arena/60a84a4d-repo"
loadstring(game:HttpGet("https://raw.githubusercontent.com/B0Xaz1/Repo/arena/60a84a4d-repo/loader.luau"))()
```

The branch reference is also used for the plugin modules; setting it before running the loader is necessary. This snippet is for testing the development branch, not the stable `main` release.

## Menu and profiles

The menu has tabs for Combat, Visuals, Movement, Players, Game, Commands, Utility, and Settings. Use search to find a control; star a control to keep it at the top of its tab. Most settings are saved in named profiles. The built-in Default, Legit, and Rage presets are available as starting points.

The Default profile restores default settings and cannot be overwritten. Local saving and configuration import/export depend on file support in your execution environment. Bookmarks last for the current session.

## Supported experiences

Game-specific controls are available for:

- **Da Hood (place 2788229376):** glide-inspired fake macro with an adjustable ground speed cap. **Hold** mode requires the activation key (V by default) and S together; **Toggle** mode lets V arm/disarm the macro, but S is still required to move. V alone does not boost. While S is held, the grounded boost goes **forward relative to the camera**, and the character turns to face that direction. The speed slider now ranges from 16 to 400 (new default 180); existing saved profiles keep their chosen value. Turn the camera to steer; inclines weaken the push, and airborne velocity is untouched. This is not the game's animation/zoom glitch, and the server may override local motion.
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