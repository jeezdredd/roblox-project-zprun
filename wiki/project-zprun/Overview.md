# Overview

Task Force Z is a co-op endless runner for Roblox set in a zombie apocalypse. A squad of one to three players auto-runs forward down a 240-stud lane through procedurally streamed biomes, strafing around obstacles and shooting the horde until the last runner goes down. The run is scored by distance; distance and kills convert into credits and weapon XP that are spent in the hangar hub between runs.

The project is built with Rojo + Wally + Selene in Luau `--!strict`. Server code lives in `src/server/systems/`, client presentation in `src/client/`, and data-only config modules in `src/shared/config/`.

## Player loop

1. **Boot** — `src/replicatedfirst/Boot.client.luau` replaces the default loading screen with the TASK FORCE Z title card and loading steps, then releases the client through `BootState.awaitReady`.
2. **Hangar hub** — the player spawns in the hangar at `HangarConfig.HUB_CENTER`, surrounded by five vendor rooms, a desert base with a road leading to the burning-city diorama, and an outdoor shooting range. Movement is free, jumping is enabled, and credits are spent here.
3. **Helicopter squad lobby** — boarding one of three helipad choppers opens a squad. The leader picks map, difficulty, privacy (Solo / FriendsOnly / Public) and modifiers; `HangarConfig.SQUAD_CAPACITY` is 3 and launch runs a `LAUNCH_COUNTDOWN` of 4 seconds.
4. **Run** — the squad is teleported to `HangarConfig.RUN_START_CFRAME` in the separate run world at `GameConstants.RUN_ORIGIN`. Chunks stream ahead of the furthest player, zombies and ammo crates spawn per chunk, and mission goals track distance and kills.
5. **Death and results** — the corpse is posed, zombies swarm and feed on it, and a first-person death cinematic plays before the results panel counts up the reward rows.
6. **Rewards** — credits are `floor(distance / 10 * rewardMultiplier) + goalBonus`, plus weapon XP earned from kills. One revive per run is allowed, either via the Robux Continue product or free while that product id is unconfigured.
7. **Back to hub** — the player returns to the hangar and spends the payout at the vendors.

## Design references

| Reference | What is taken from it |
| --- | --- |
| Call of Duty: Modern Warfare (2019) | Presentation: per-class weapon audio, weight and foley, living camera (bob, breath, shake) |
| Into the Dead 1/2 | Run core and biome art direction: silhouette corridors, one warm light accent, detailed foreground, fog as art |
| Call of Duty: Zombies | Risk economy and meta loop: kills pay out, perks, upgrade stations |
| TTK Testing by Sable Digital (Roblox) | Weapon feel benchmark: viewmodel animation quality, weapon textures, gunshot audio layering |

## Hard rules

- **Server authoritative.** Ammo, damage, credits, purchases and skin grants are owned by the server. Every remote validates its arguments; `src/server/systems/WeaponService.luau` additionally checks fire rate, muzzle-origin distance, line of sight and direction magnitude before accepting a shot.
- **No pay-to-win.** Credits, weapons, weapon upgrades, skills and loadout slots are never sold for Robux. Only cosmetics and the post-death Continue are monetised, and both passes in `src/shared/config/ProductsConfig.luau` are marked `cosmeticOnly`.
- **Asset manifest pipeline.** Every asset is registered in `assets/manifest.json`, uploaded by `scripts/upload_assets.py`, and written into `src/shared/config/AssetIds.luau` and `assets/LICENSES.md` by `scripts/sync_configs.py`. Audio must be real licensed files, never generated. Consumers guard on `assetId > 0` so a missing id degrades silently.
- **Luau `--!strict`** at the top of every module.
- **Pre-commit gate:** `selene src/`, `python3 tools/validate_api.py`, `rojo build`.
- **Commits are authored by the user only** — no co-author trailer, no mention of Claude.

## Pages

- [[Architecture]] — module layout, boot order, remotes, the hub/run coordinate split.
- [[Gameplay Systems]] — run streaming, zombie AI and the juke mechanic, weapons, economy, death flow.
- [[Assets Pipeline]] — manifest format, upload and sync scripts, licensing.
- [[Performance]] — streaming, chunk pooling, emitter caps, VFX density.
- [[Decisions]] — recorded technical decisions and the reasoning behind them.
- [[Roadmap]] — what is done, in progress and planned.
