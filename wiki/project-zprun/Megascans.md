# Megascans

The owner's free Quixel Megascans surfaces from Fab, imported as `TFZ_MS_<Slot>`
MaterialVariants that replace and extend the built-in PBR sets. Branch
`cloud/megascans-import` (2026-10-01); the full procedure (download on Fab, the command,
the upload, the replacement table, the Studio checks) is in
`docs/environment/megascans.md`. Related: [[Environment]], [[Assets Pipeline]],
[[Development Policy]].

## Licence rule

Fab Standard License: use in the shipped game only. The repository is public, so no
Fab-derived file is committed, processed maps included. The maps live in
`assets/fab/textures/` and the generated list in `src/shared/fab/MegascansMaterials.luau`,
both gitignored and present on the owner's machine only. Committed: the manifest rows
(ids, licence, note, variant settings), the `TFZ_MS_*` entries in `default.project.json`
(ids and studs per tile), the usual generated files.

## Files

| File | Role |
| --- | --- |
| `tools/megascans/import_surface.py` | The command: zip or folder, `--slot`, `--base-material`, `--studs-per-tile`, `--replaces`, `--override`, `--pattern`, `--ao-strength`, `--normal-convention`; writes the maps and the manifest rows, then runs both sync scripts |
| `tools/megascans/surface.py` | Reading both layouts by map suffix, the AO multiply, the DirectX to OpenGL normal conversion and its detection from the displacement map, studs per tile, the rows |
| `scripts/fab_files.py` | The Fab file rules: Fab licence only under `assets/fab/`; a missing file is fine once the row has an id |
| `scripts/sync_configs.py` | Declares a `TFZ_MS_*` variant and lists it in the local Luau file once every map has a usable id |
| `scripts/upload_assets.py`, `scripts/sync_needed.py` | Skip uploaded Fab rows without their file; a NEEDED row pointing at the upload |
| `src/shared/util/MaterialSets.luau` | Pure: entry checks, merge, replacements, overrides. `luau tests/megascans/run.luau` |
| `src/shared/util/MaterialUtil.luau` | Loads the list with `FindFirstChild` and `pcall`, keeps the built-in sets without it, `apply` resolves `--replaces`, the last registered override wins |

## Rules

- Roblox normal maps are OpenGL (green up). A DirectX map gets its green channel
  inverted. Which one a map is: its name, else the displacement map, else OpenGL
  (raw Megascans scans); `--normal-convention` overrides.
- Colour = albedo times AO in linear light at `--ao-strength` (default 0.5).
- Metalness only on a metal base material.
- Studs per tile = the scan's width in metres times 1 / 0.28 (`WorldMeshConfig.METRE`).
- A set reaches the place only when all its maps have ids; until then, and in any
  clone without the local list, the built-in sets are used.

## Tests

`python3 tests/megascans/run.py` (synthetic surfaces generated in the test: both
layouts, sizes, normal conversion, AO multiply, studs maths, rows, generated variants,
Fab rules, gitignore) and `luau tests/megascans/run.luau`.
