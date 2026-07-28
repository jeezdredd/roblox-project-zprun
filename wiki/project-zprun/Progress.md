# Progress

Development timeline, grouped by the layer that landed. Commit hashes are on `main`.

Related: [[Overview]], [[Roadmap]], [[Decisions]].

## Foundation

| Commit | What landed |
| --- | --- |
| `1020513` | Rojo / Wally / Selene / Rokit scaffold, entry points, `GameConstants` |
| `b370212` | Running prototype: auto-run, A/D strafe, wall wrap, chase camera |
| `1cadaad` | Procedural chunk generation with pooling and distance-scaled speed |
| `616877d` | Passive zombies with distance-triggered chase and touch damage |
| `7f0c1e7` | Difficulty settings driving zombie chase and speed |
| `de2bdcd` | Project renamed to Task Force Z |

## Hub and flow

| Commit | What landed |
| --- | --- |
| `646a6d3` | Hangar hub, boot and intro sequence, phase-gated mission systems |
| `35b82d6` | Helicopter squad lobby with config, privacy, modifiers and launch |
| `da0eab5` | Forced hub spawn on character added during the hub phase |
| `69721c9` | Difficulty-aware jukeable aggro, hangar visuals, vendor placeholders |
| `c95f1e9` | Large hangar with city-view windows, burning city diorama, patrol choppers, detailed vendor rooms |
| `50c9934` | Sealed hangar perimeter, human-scale vendor rooms, client lighting director with per-biome grading |

## Death, gore and content settings

| Commit | What landed |
| --- | --- |
| `c439a36` | Settings menu, menu music, gore warning and blood toggle |
| `054ca8f` | Cinematic death sequence: zombie swarm, results, revive, first-person toggle |
| `f7055af` | Stylized gore with gibs, blood pool, longer death camera |
| `3bce6f7` | Forced first-person runs and the full feeding-frenzy cutscene |
| `7f2e171` | Death flow hardening, orbit death cam, real scream and menu music assets |

## Biomes and world art

| Commit | What landed |
| --- | --- |
| `1df5e80` | Themed biome locations with props, transitions, wider lane |
| `07c116c` | First real CC0 textures via Open Cloud for roads, aprons, buildings, hangar |
| `185f247` | Wide open run field, lane-based obstacles, glazed hangar gate, textured zombies |
| `e1158f3` | Forced first person, sealed hangar, night blackout with flashlight, glowing zombie eyes |

## Asset pipeline and detail pass

| Commit | What landed |
| --- | --- |
| `d07c800` | Asset manifest pipeline: upload and sync scripts, generated `AssetIds` and `LICENSES` |
| `7e35db0` | Per-material footsteps, steps stop when idle |
| `b726767` | Living first-person camera: head bob, strafe tilt, breathing, shake, speed FOV |
| `f86b4f0` | Animation clip slots, world VFX (embers, ash, rotor wash), event post-processing, flashlight dust |
| `d8441a0` | Full audio detail pass: foley, body state, zombie voices, world ambience, music ducking |
| `e64b725` | PBR material variants, grime and blood stains, zombie hit VFX, chase adrenaline |
| `a7d5384` | Military UI pass: run HUD, reward ticker, UI sounds, effects-density setting |
| `ad408c7` | Foot-planting IK, zombie animation controller, performance budget document |

## Meta layer

| Commit | What landed |
| --- | --- |
| `3370888` | Persistent profiles via ProfileStore: credits, XP, skins, settings |
| `edbdefd` | Desert base with road and outdoor shooting range, hub light pools, city silhouette rework |
| `0191d0d` | Per-class weapon audio, animated viewmodel, security and world fixes from adversarial review |
| `7be2147` | Credit vendors: weapon unlock and upgrade, skills, skins; Robux Continue via `ProcessReceipt` |
| `a9b425b` | ITD run layer: ammo crates, loadout slots, mission goals, Farmstead and Cornfield biomes |
| `f7c72c7` | Texel density pass, bloom limits, Forest sun-in-frame exception |
| `3cbbb3d` | Layered weapon audio (short close shots, zone-aware tails), monetization test plan |
| `e021369` | Third-person world weapon model welded to the character |
| `0536d1c` | Burst smoke, tracer cadence, miss tracers |
| `0d59085` | Forest undergrowth and mushrooms inside flashlight range |

## Known gaps

- Animation clips for the player and zombies are still placeholder slots at `assetId = 0` in `src/shared/config/AnimationsConfig.luau`. The viewmodel animates procedurally; the third-person character does not animate its weapon carry yet.
- Developer Product and Game Pass ids in `src/shared/config/ProductsConfig.luau` are `0`, so Continue currently grants a free revive. Filling the ids in the Creator Dashboard switches it to the paid path with no code change.
- `MissionGoals` tracks progress and pays a credit bonus but has no HUD surface yet.
- The audio assets uploaded most recently are still in Roblox moderation review; consumers guard on `assetId > 0`, so an unapproved id degrades to silence rather than erroring.
