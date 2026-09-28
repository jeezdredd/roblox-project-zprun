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

Animation, audio and models follow [docs/asset-policy.md](docs/asset-policy.md). Since 2026-09-07 it judges results, not methods: any technique is allowed (clips, mocap, AI generation, Luau-authored poses, procedural layers, generated audio) as long as it passes a look or a listen in a Studio playtest. What stays fixed is provenance: every asset has a manifest entry with a source and a licence, ids only come from real uploads, and nothing extracted from another game ever enters the project. Placeholders are allowed only when marked `"status": "placeholder"` and listed in `assets/NEEDED.md`.

## Hard rules

- Server is authoritative for ammo, damage, credits and purchase grants. Every remote validates its arguments.
- No pay-to-win. Credits, weapons, weapon upgrades, skills and perk slots are never sold for Robux — only cosmetics and the post-death Continue.
- Every new asset goes through `assets/manifest.json` → `scripts/upload_assets.py` → `scripts/sync_configs.py`, and is listed in `assets/LICENSES.md` with a licence we can show. Extracted third-party game assets are never allowed.
- Run `selene src/`, `python3 tools/validate_api.py` and `rojo build` before committing.
- Commits are authored by the user only — no co-author trailer, no mention of Claude.

## Studio MCP

`.mcp.json` registers Roblox Studio's built-in MCP server (`Roblox_Studio`, stdio, `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`). It only responds while Studio is open with **Assistant → … → Manage MCP Servers → Enable Studio as MCP server** turned on; without that the proxy starts but returns no tools. Once connected it exposes script read/edit/search, data model exploration, Luau execution, playtest control and input simulation against the live session.

## Layout

- `src/shared/config/` — data-only config modules, one per system
- `src/server/systems/` — authoritative services, each with an `init()` called from `init.server.luau` behind `runStage`
- `src/client/systems/`, `src/client/controllers/`, `src/client/ui/` — presentation
- `wiki/project-zprun/` — Obsidian vault tracked in git; update it after each significant change
