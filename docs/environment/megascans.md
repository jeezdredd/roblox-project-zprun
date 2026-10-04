# Megascans surfaces

The owner's free Quixel Megascans surfaces from Fab replace and extend the project's
PBR material sets (the CC0 ambientCG and Poly Haven sets in `MaterialUtil.sets`, see
`docs/world/environment.md`). `tools/megascans/import_surface.py` turns one downloaded
surface into the maps of a Roblox MaterialVariant named `TFZ_MS_<Slot>`.

## The licence rule

Megascans on Fab come under the Fab Standard License, which allows use in a shipped
game (Unreal or not) but not making the content available any other way. This
repository is public, so **no Fab-derived file is ever committed, processed maps
included** (Development Policy, section 4).

| What | Where | Committed |
| --- | --- | --- |
| The downloaded zip or folder | anywhere outside the repository (or under `assets/fab/`) | never |
| The processed 1024 px maps | `assets/fab/textures/<slot>_{color,normal,roughness,metalness}.png` | never (gitignored) |
| The generated material list (asset ids and settings) | `src/shared/config/MegascansMaterials.luau` | yes |
| Manifest rows: asset ids, licence, a note, the variant settings | `assets/manifest.json` | yes |
| The `TFZ_MS_*` MaterialVariants (asset ids and studs per tile only) | `default.project.json`, MaterialService | yes |
| The ids in `AssetIds`, `LICENSES.md`, `NEEDED.md` | generated as usual | yes |

The importer refuses a source inside the repository outside `assets/fab/`, and reads a
zip by extracting it to the system temp directory, which it removes afterwards.
`scripts/fab_files.py` holds the rules both pipeline scripts apply:

- a row whose licence starts with `Fab ` must point under `assets/fab/`;
- a row under `assets/fab/` may have no file (every clone but the owner's) once it has
  an asset id; `upload_assets.py` skips it and `sync_configs.py` accepts it;
- a row under `assets/fab/` with no asset id and no file stops `sync_configs.py`, so
  upload a surface on the owner's machine before committing its rows.

## Downloading a surface on Fab

1. Sign in on fab.com with the Epic account that owns the library.
2. Find the surface (filter by Megascans and by material or surface), open its listing
   and press **Add to My Library** (free for Megascans).
3. Press **Download** on the listing (or from My Library), pick a format that gives
   plain image files rather than an Unreal project, and pick **2K** quality: the
   importer resizes to 1024 px, so 4K and 8K only make the download bigger.
4. Keep the zip outside the repository, for example `~/Downloads/Megascans/`. There is
   no need to unzip it.

A surface exported from the old Quixel Bridge (a folder `<name>_<id>/` holding
`<id>.json` and `<id>_2K_Albedo.jpg` and so on) works the same way.

## The command

```
python3 tools/megascans/import_surface.py ~/Downloads/Megascans/Cracked_Asphalt_2K.zip \
    --slot asphalt_cracked --replaces TFZ_AsphaltCracked --pattern Organic
```

| Flag | Meaning |
| --- | --- |
| `--slot <name>` | Required. Lower snake case; the manifest keys are `texture/surface/megascans/<slot>_<map>`, the variant `TFZ_MS_<Slot>` (`asphalt_cracked` gives `TFZ_MS_AsphaltCracked`) |
| `--base-material <Enum.Material>` | The variant's BaseMaterial. Guessed from whole words of the JSON's name, categories and tags when left out (asphalt, concrete, gravel to Pebble, rust to CorrodedMetal, plurals count, "sand" inside "sandstone" does not); the run stops if nothing fits. Required with `--override` |
| `--studs-per-tile N` | Overrides the size read from the JSON |
| `--replaces TFZ_<Set>` | `MaterialUtil.apply(part, "TFZ_<Set>")` uses this variant instead, once it is registered; must name a set in `MaterialUtil.sets` |
| `--override` | Makes the variant its base material's override (`MaterialService:SetBaseMaterialOverride`), so every part of that material without a variant uses it. Needs `--base-material`: an override is never left to a guess |
| `--pattern Regular\|Organic` | MaterialPattern. `Organic` breaks up visible tiling on ground, grass and sand |
| `--ao-strength 0..1` | How much of the AO map darkens the colour map (default 0.5) |
| `--normal-convention opengl\|directx` | Forces the normal map's convention when detection gets it wrong |
| `--source-url URL` | The Fab listing for the manifest row (default: the Megascans page from the JSON's id) |
| `--replace` | Import a slot again after it was uploaded; its rows go back to pending |
| `--allow-non-square` | Import maps that are not square (they are stretched to 1024 x 1024); without it a non-square map stops the run |
| `--no-sync` | Skip running `sync_configs.py` and `sync_needed.py` afterwards |

The run prints the layout it read, the base material, the studs per tile, the normal
convention and how it was decided, and each file written.

## What the importer does

- **Finding the files.** It reads the surface's JSON (the one with the most Megascans
  keys: `id`, `name`, `meta`, `categories`, `tags`, `physicalSize`) and finds the maps
  by the end of the file name, ignoring case, separators and a trailing resolution or
  LOD (`_2K`, `_LOD0`): Albedo, BaseColor, Diffuse or Color; Normal, NormalGL or
  NormalDX (also `Normal_GL`, `Normal_DirectX`); Roughness, Gloss or a packed ORM/ARM
  map; AO; Displacement or Height; Metalness or Metallic. Previews and thumbnails are
  skipped, as are maps the game does not use (Cavity, Specular, Translucency). With two
  sizes of one map, the smallest at least 1024 px wide is used. If the colour, the
  normal or the roughness is missing it stops and lists every file it found and what
  it recognised.
- **Colour:** the albedo multiplied by the AO map in linear light,
  `albedo * (1 - strength * (1 - ao))`, then back to sRGB. Roblox does not take an AO
  map, so this is the only place the scan's occlusion survives.
- **Normal:** Roblox's NormalMap is OpenGL convention (tangent space, green pointing
  up, +Y). A DirectX map (green pointing down, the Unreal convention) gets its green
  channel inverted; every vector is renormalised. Which convention a map is in:
  1. a name that says it (`NormalGL`, `Normal_DX`, ...) is trusted;
  2. an unlabelled `Normal` is compared with the displacement map: in OpenGL the green
     channel rises where the height rises down the image, in DirectX where it falls,
     and the red channel (the same in both) must agree before the answer is used;
  3. with no displacement map (or an inconclusive one), OpenGL, the convention raw
     Megascans scans ship in (Unreal-format downloads are DirectX and are labelled as
     such), with a printed WARNING to check the bumps in Studio;
  4. `--normal-convention` overrides all of it.
- **Roughness:** the Roughness map, or `1 - Gloss`, or the green channel of an ORM map.
- **Metalness:** only for a metal base material (Metal, CorrodedMetal, DiamondPlate,
  Foil), from the Metalness map or the blue channel of an ORM map. Other surfaces get
  no metalness map, so a stray one cannot make concrete shine.
- Every map is written 1024 x 1024 as an 8-bit RGB PNG (Pillow and numpy only); 16-bit
  height and roughness maps keep their precision until then.
- **Studs per tile:** the scan's physical width in metres times the project's metre,
  `WorldMeshConfig`'s `METRE = 1 / 0.28` (1 stud = 0.28 m, 3.571 studs per metre),
  rounded to 0.01. A 2 x 2 m scan is 7.14 studs per tile. The size comes from a
  top-level `physicalSize` (text such as `2x2 m` or `200 x 200 cm`, a list, or
  `{width, height, unit}`) or Bridge's `meta` list (`scanArea`); a non-square scan
  uses its width. A width outside 0.05 to 50 m (a unitless `200` meant as cm reads as
  200 m) stops the run and asks for `--studs-per-tile`.
- **Refusals before any map is written:** an already uploaded slot without
  `--replace`, and a slot whose variant name another slot already has
  (`concrete_damaged_2` and `concrete_damaged2` are both `TFZ_MS_ConcreteDamaged2`).
  The maps are processed in a temp dir and moved into `assets/fab/textures/` only
  after the manifest is saved; a failed sync afterwards is reported as such.
- **Manifest rows:** one per map, `status` `pending`, `assetId` 0, licence
  `Fab Standard License (Quixel Megascans)`, the source page, a note with the asset's
  name and id. The colour row also carries `material`: variant name, base material,
  studs per tile, pattern, override and replaces.

## Upload and use

```
python3 scripts/upload_assets.py --only texture/surface/megascans/
python3 scripts/refresh_status.py
python3 scripts/sync_configs.py && python3 scripts/sync_needed.py
```

Once all maps of a set have usable ids (not 0, not rejected), `sync_configs.py`:

- declares `TFZ_MS_<Slot>` under MaterialService in `default.project.json`
  (BaseMaterial, the maps, StudsPerTile, MaterialPattern);
- lists the set in `src/shared/config/MegascansMaterials.luau` (committed; `return {}`
  when no set is ready).

A pending set is in neither, so a half-uploaded surface never blanks a material.

`MaterialUtil` (server, the "Materials" stage) requires
`ReplicatedStorage.Shared.config.MegascansMaterials` inside `pcall`. Each entry is
checked field by field (`MaterialSets.validate`), and a bad entry or an unknown base
material is skipped with a warning. The valid sets are appended after the built-in
ones; with an empty list nothing changes.
`--replaces` and `--override` only take effect once the variant has registered, so a
missing variant falls back to the set it was meant to replace. Commit the manifest and
the generated files as usual once every row has its id: `sync_configs.py --check`
fails on a Fab row without one, file or not (no other clone could upload it).
`git status` never shows `assets/fab/`.

## Which surface replaces what

| Megascans surface (search on Fab) | Slot | Base material | Flags | Replaces |
| --- | --- | --- | --- | --- |
| Asphalt (plain road) | `asphalt` | Asphalt | `--replaces TFZ_Asphalt` | the desert base road (`DesertBase`) |
| Cracked asphalt | `asphalt_cracked` | Asphalt | `--replaces TFZ_AsphaltCracked --pattern Organic` | City floor (`DressingConfig`) |
| Concrete floor | `concrete` | Concrete | `--replaces TFZ_Concrete` | the hangar floor |
| Dirty or stained concrete | `concrete_dirty` | Concrete | `--replaces TFZ_ConcreteDirty` | aprons, sidewalks, dividers, ruins |
| Dry dirt or soil | `dirt_dry` | Ground | `--replaces TFZ_DirtDry --pattern Organic` | Farmstead and Cornfield floors, the Forest undergrowth floor, Wasteland aprons |
| Burned ground | `ground_burned` | Ground | `--replaces TFZ_GroundBurned --pattern Organic` | patches under burned cars |
| Grass | `grass` | Grass | `--replaces TFZ_Grass --override --pattern Organic` | the Forest floor, the Forest, Farmstead and Cornfield aprons, and every Grass part (TFZ_Grass is the Grass override now) |
| Sand | `sand` | Sand | `--replaces TFZ_Sand --pattern Organic` | the desert base ground, Wasteland berms |
| Gravel | `gravel` | Pebble | `--override --pattern Organic` | nothing yet: a new set, on Pebble parts |
| Bricks | `bricks` | Brick | `--override` | the flat `TexturesConfig.BRICKS` texture has no variant; this gives every Brick part one |
| Rusty metal | `metal_rusty` | CorrodedMetal | `--replaces TFZ_MetalRusty --override` | Wasteland poles, barn roofs, and every CorrodedMetal part (taking over from TFZ_Rust) |

The old sets stay in `MaterialUtil.sets` and in `default.project.json` as the fallback.

## Checks

- `python3 tests/megascans/run.py`: the importer on synthetic surfaces generated in the
  test, never real Megascans maps. Covers both layouts (a Bridge folder and a Fab zip),
  the suffix matching, the 1024 px outputs, the DirectX to OpenGL conversion and its
  detection, the AO multiply, the studs per tile maths, the manifest rows, the
  generated variant and list, the Fab file rules and the gitignore.
- `luau tests/megascans/run.luau`: `MaterialSets` (entry checks, merge, replacements,
  overrides).

In Studio, after importing and uploading one surface:

1. `rojo build` and open the place: the Output shows no `MaterialVariant ... missing`
   warning, and `MaterialService` holds `TFZ_MS_<Slot>`.
2. The test yard's texture wall (`Sandbox.buildTextureWall`) shows the new variant
   beside the one it replaces: the bumps light from the same side as on the old set
   (if they look inverted, re-import with `--normal-convention` set the other way).
3. A run through the biome whose set was replaced: the floor uses the new variant, and
   the tiling size matches the props (a 2 m scan is about 7 studs).
4. In a fresh clone (no `assets/fab/`), `rojo build` and the checks pass and the place
   loads with the Megascans variants from their ids.
