# Task Force Z

Co-op endless runner set in a zombie apocalypse, built for Roblox. One to three players form a squad in a military hangar, configure a mission inside a helicopter, then run a procedurally generated route through burning cities, forests and wastelands while the infected close in.

> **Proprietary project.** The concept, design and code are the original work of Sevastyan (`jeezdredd`). Copying, redistribution or derivative use is not permitted. See [LICENSE](LICENSE).

## Gameplay

**Hangar hub.** A lit military hangar with window bands looking out over a burning city — fires, patrol helicopters with searchlights, distant sirens. Themed vendor rooms line the walls: medbay, gunsmith with an indoor shooting range, weapon dealer, canteen and a bubblegum stand (all placeholders for the upcoming economy).

**Squad lobby.** Board one of three parked helicopters. The first player aboard leads and picks the map, difficulty, privacy (solo / friends only / public) and mission modifiers. Reward multipliers stack from difficulty and modifiers. A countdown launches the whole squad on a shared world seed.

**The run.** Forced first person. The soldier runs forward automatically; you steer left and right and wrap around the lane edges. Speed climbs with distance. Locations stream in as themed biomes several hundred metres long with blended transitions — city streets with wrecked cars, buses and crash sites, open forest you weave through under a canopy, and ruined wasteland. Obstacle density scales with difficulty. Zombies chase a delayed prediction of your position, so sudden zig-zags can throw them off.

**Death.** No instant respawn. The soldier falls, the horde closes in and feeds while the camera stays in his eyes, then the screen goes black — `YOU ARE DEAD` — followed by run results and a choice: return to the hangar or continue from the spot where you fell.

## Tech

- **Luau**, `--!strict` in every module
- **Rojo** for filesystem ↔ Studio sync (`default.project.json`)
- **Wally** for packages, **Selene** for linting, **Rokit** for pinned tool versions
- Server authoritative: distance, damage, squad state, mission config and rewards are all computed server side; client input is validated at the boundary
- Data driven: locations, zombies, difficulties, modifiers, vendors, skins, textures and audio all live in `src/shared/config`
- All `RemoteEvent` names are centralised in `src/shared/net/Remotes.luau`

## Layout

```
src/
├── server/systems/      hangar, city diorama, vendor rooms, squad, mission,
│                        chunk generation, zombie AI, death, skins, distance
├── client/
│   ├── controllers/     input, camera, run, squad, death, first person
│   ├── systems/         settings, audio, ambience, gore, flashlight, fps
│   └── ui/              squad lobby, settings, hud, content warning
├── replicatedfirst/     boot loader and title sequence
└── shared/
    ├── config/          all tunable content and constants
    ├── net/             remote event registry
    ├── types/           shared type definitions
    └── util/            texture, reward and geometry helpers
tools/validate_api.py    static check of Roblox class and property usage
wiki/project-zprun/      design notes, architecture, progress, roadmap
```

## Development

Install the toolchain (versions are pinned in `rokit.toml`):

```bash
rokit install
```

Sync into Studio:

```bash
rojo serve          # then connect from the Rojo plugin in Studio
```

Checks before committing:

```bash
selene src/                                  # lint
python3 tools/validate_api.py                # verify Roblox class/property names
rojo build default.project.json -o build.rbxlx
```

`validate_api.py` downloads the official Roblox API dump and fails on any `Instance.new` class or property assignment that does not exist — the failure mode that silently kills a server script at runtime.

## Assets

Third party assets are CC0 or public domain, re-uploaded to Roblox and referenced by asset id in `src/shared/config/TexturesConfig.luau` and `AudioConfig.luau`:

- Textures — [ambientCG](https://ambientcg.com) (CC0)
- Audio — [OpenGameArt](https://opengameart.org) (CC0) and [Wikimedia Commons](https://commons.wikimedia.org) (public domain)

Uploaded audio is private to its owner. Audio only plays once the place is published under the account that owns the assets.

## Status

Playable end to end in Studio: boot sequence, hangar, squad lobby, mission launch, procedural run, zombies, death sequence and return. In progress: credits economy, weapons, the three soldier lives system and vendor functionality. See [wiki/project-zprun/Роадмап.md](wiki/project-zprun/Роадмап.md).
