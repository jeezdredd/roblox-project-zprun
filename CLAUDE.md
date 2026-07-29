# Task Force Z — project instructions

Co-op endless runner set in a zombie apocalypse (1-3 players). Roblox, Rojo + Wally + Selene, Luau `--!strict`.

## Design references

| Reference | What we take from it |
| --- | --- |
| Call of Duty: Modern Warfare (2019) | Presentation: per-class weapon audio, weight and foley, living camera (bob, breath, shake) |
| Into the Dead 1/2 | Run core and biome art direction: silhouette corridors, one warm light accent, detailed foreground, fog as art |
| Call of Duty: Zombies | Risk economy and meta loop: kills pay out, perks, upgrade stations |
| TTK Testing by Sable Digital (Roblox) | Weapon feel benchmark: viewmodel animation quality, weapon textures, gunshot audio layering |

## Asset policy

Animation and audio follow permanent rules recorded in [docs/asset-policy.md](docs/asset-policy.md). The short version: never author artistic keyframe animation in code, never synthesise audio, leave a slot silent at `assetId = 0` and log it in `assets/NEEDED.md` rather than filling it with something unsuitable, and never invent an assetId. Unreal (Fab) and Unity Asset Store packs are forbidden even when free.

## Hard rules

- Server is authoritative for ammo, damage, credits and purchase grants. Every remote validates its arguments.
- No pay-to-win. Credits, weapons, weapon upgrades, skills and perk slots are never sold for Robux — only cosmetics and the post-death Continue.
- Every new asset goes through `assets/manifest.json` → `scripts/upload_assets.py` → `scripts/sync_configs.py`, and is listed in `assets/LICENSES.md`. Audio must be real CC0/licensed files, never generated.
- Run `selene src/`, `python3 tools/validate_api.py` and `rojo build` before committing.
- Commits are authored by the user only — no co-author trailer, no mention of Claude.

## Layout

- `src/shared/config/` — data-only config modules, one per system
- `src/server/systems/` — authoritative services, each with an `init()` called from `init.server.luau` behind `runStage`
- `src/client/systems/`, `src/client/controllers/`, `src/client/ui/` — presentation
- `wiki/project-zprun/` — Obsidian vault tracked in git; update it after each significant change
