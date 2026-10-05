# Prebuilt maps

Large static scenes (a city block, a district, a level kit laid out in a DCC tool) are
split into upload-sized cells by `tools/city_import/split_scene.py` and placed at run
time by `PrebuiltMaps` under `Workspace.PrebuiltMaps/<map>`, one streamed Model per
cell. Uploads go through the normal manifest pipeline. The procedural run world, the
material variants and the viewmodels are untouched.

## Why cells

A Roblox MeshPart takes at most 20,000 triangles, an uploaded texture is resized to
1024 px at most, and a place streams by instance, so one huge mesh is not an option.
Cutting the scene on a ground grid gives:

- meshes under the cap;
- textures at the size Roblox keeps anyway;
- a unit the engine can stream in and out (`ModelStreamingMode = Atomic`, so a cell
  arrives whole);
- a budget line per cell like the run chunks have.

## The command

```
python3 tools/city_import/split_scene.py ~/Downloads/city/scene.glb --out assets/maps/city \
    --map city --license "CC BY 4.0, \"Old Town\" by Someone, https://..." --source "https://..."
```

| Flag | Meaning |
| --- | --- |
| `--out <dir>` | Output folder. With `--map` it must be inside the repository (the manifest rows point at it); `assets/maps/<map>` is the convention |
| `--max-tris N` | Triangle cap per mesh, default 18000 (under the 20k MeshPart limit) |
| `--texture N` | Longest texture side in px, default 1024 |
| `--cell N` | Cell size in studs on the ground plane, default 64 |
| `--scale S` | Studs per scene unit. Default: the project's metre, `WorldMeshConfig.METRE = 1 / 0.28` (glTF is in metres) |
| `--over-cap split\|decimate` | What happens to a mesh over the cap: split into pieces (lossless, default) or simplified first |
| `--decimate R` | Simplify every mesh to R of its triangles (0 < R <= 1, default 1: no simplification) |
| `--merge-size N` | Meshes smaller than N studs that share a material in a cell become one mesh, default 4 |
| `--map <name>` | Lower snake name: adds the manifest rows and writes the Luau layout module |
| `--license`, `--source` | Required with `--map`: every asset has a licence and a source |
| `--replace` | Split a map again after its cells were uploaded (the rows go back to pending) |

Python 3 with numpy and Pillow; simplification also needs `pip install pyfqmr scipy`.

## What it does

1. **Flatten.** It reads the default scene of a `.glb` or `.gltf` (embedded,
   external or data-URI buffers and images) and multiplies every node's matrix down
   the tree, so every triangle is in world space. Mirrored nodes (negative
   determinant) get their winding flipped, so faces still point out. Then it scales to
   studs.
2. **Cells.** A mesh no wider than a cell goes whole to the cell of its centre. A
   wider one (roads, terrain, long walls) is cut along its triangles: each triangle
   goes to the cell its centroid is in. A cut edge keeps the same vertices on both
   sides, so neighbouring cells meet exactly.
3. **Merge.** In each cell, meshes smaller than `--merge-size` that share a material
   become one mesh (clutter: cans, debris, signs). Bigger meshes stay their own, so
   collision and culling stay per object.
4. **Cap.** A mesh over `--max-tris` is cut in half along the longest axis of its
   triangle centroids until every piece fits. This is lossless, and the halves share
   the cut's vertices.
5. **Simplification** (`--decimate`, `--over-cap decimate`) uses pyfqmr's quadric
   simplifier on the mesh welded by position, with borders locked. Open edges never
   move: a cell's cut, a material boundary, a real hole. So cells still meet without
   cracks. Each corner's UV and normal are then carried over from the nearest original
   triangle (barycentric in that triangle's plane), so textures stay put and a UV seam
   keeps both its UVs. Anything still over the cap is then split.
6. **Textures.** Every image is resized so its longest side is at most `--texture`
   (LANCZOS). JPEGs stay JPEG at quality 90; everything else becomes PNG. A texture
   used by several meshes of a cell is stored once in that cell. Each cell carries its
   own copy, so a texture used across 30 cells is uploaded 30 times; that is the cost
   of independent cells.
7. **Output.**
   - `<out>/cells/<cell>.glb`: one node per mesh, named `<cell>_<nnn>`, its geometry
     about the mesh's own centre and turned 180 degrees about Y, because the Roblox
     glTF importer turns meshes that way (the same convention as
     `tools/character_rig/soldier.py`).
   - `<out>/layout.json`: per cell, its name, position and size; per mesh, its offset
     from the cell, size, triangle count, material, a few source node names and a
     collision hint.
   - Cell names come from the grid, `c_<x>_<z>` with `p`/`m` for the sign
     (`c_p002_m001`).

Collision hints are decided once on each whole source mesh, before any cut, and every
piece cut or split from it keeps its mesh's hint (a corner of the ground is ground,
however small, and is never merged into clutter). "Near-planar" means the extent
along the direction the vertices vary least (PCA) is under 0.5 studs or 2 percent of
the largest side, whatever the orientation:

| Hint | When | In the game |
| --- | --- | --- |
| `none` | a merged clutter mesh, or a mesh under `--merge-size` | no collision, no queries |
| `default` | wider than a cell (ground, roads) and near-planar | `CollisionFidelity.Default` |
| `precise` | wider than a cell with relief (terrain, ramps) | `CollisionFidelity.PreciseConvexDecomposition` |
| `box` | within a cell and near-planar (walls, slabs, boards) | `CollisionFidelity.Box` |
| `hull` | everything else (buildings, cars, rocks) | `CollisionFidelity.Hull` |

Each primitive keeps only the vertices its triangles use, so a kit whose meshes share
one vertex buffer does not give every mesh the buffer's bounds. Buffers are read
through `memoryview` (a 59 MB GLB reads in a fraction of a second). URIs are decoded
with `urllib.parse.unquote`.

`KHR_texture_transform` on the base colour texture is baked into the UVs (offset,
rotation, scale); a different transform on another texture of the material is noted.
A required extension the reader cannot honour stops the run with what to do:
`KHR_draco_mesh_compression`, `EXT_meshopt_compression`, `EXT_mesh_gpu_instancing`,
`KHR_texture_basisu` (re-export uncompressed, instances realised, PNG or JPEG
textures).

Not read: skins (read in their bind pose), morph targets, animations, a second UV set,
vertex colours, sparse accessors (stop the run), other material extensions (dropped,
listed as notes). Only triangle primitives are kept.

**Simplification normals.** Each new triangle takes its UVs and normals from a source
triangle found in position and facing together, the one of the 8 nearest whose normal
agrees best with the new winding: on a two-sided wall the other side's triangles are
never used, even when their centroids are nearer.

**FBX.** The FBX reader in `tools/arms_rig/fbx.py` (used by `tools/character_rig`)
parses the binary node tree. It does not build static meshes with their node
transforms and axis settings, so FBX scenes are not read yet; export them to glTF
first. Adding an FBX front end means producing the same world-space `Piece` list as
`gltf_io.pieces`.

## Upload and placement

With `--map`, the splitter:

- adds one manifest row per cell, `model/maps/<map>/<cell>`, `pending`, id 0, with the
  licence, the source and a note (meshes, triangles, textures, source file);
- removes rows of cells that no longer exist;
- writes `src/server/prebuilt/<map>.luau` from the layout (no ids in it; server only,
  clients never download it);
- runs both sync scripts.

Then:

```
python3 scripts/upload_assets.py --only model/maps/<map>/
python3 scripts/refresh_status.py
python3 scripts/sync_configs.py && python3 scripts/sync_needed.py
```

Each cell `.glb` uploads as a Model asset, and its id reaches
`AssetIds.model.maps.<map>.<cell>`. A CC BY scene needs a licence string the credits
generator can read (`CC BY 4.0, "Title" by Author, URL`): `sync_configs.py` stops on
one it cannot. All of `assets/maps/` is gitignored (the cells are large and often
licensed; `--out` must be `assets/maps/<map>/` with `--map`, and any `--out` inside the
repository must be ignored, checked with `git check-ignore`); the Luau module is the
committed record. `python3 tools/city_import/emit_layout.py --all` rewrites every
module from the layouts present, and `--check` reports stale ones.

Finally list the map in `PrebuiltMapsConfig.maps`:

```lua
{ map = "city", enabled = true, origin = { 0, 0, -4000 }, yaw = 0 },
```

`PrebuiltMaps.init` (server stage "PrebuiltMaps") does the following for each enabled
map:

- requires the server's `prebuilt.<map>` module behind `FindFirstChild` and `pcall`,
  and checks it with `PrebuiltMapMath.check`;
- creates `Workspace.PrebuiltMaps/<map>`;
- loads every cell that has an id with `InsertService:LoadAsset` through a fixed pool
  of `LOAD_CONCURRENCY` workers (no thread per cell); each cell runs in `pcall`, so a
  failure never holds a slot or stops the others;
- for each mesh in the layout, finds the MeshPart of that name and places it:
  - it is anchored at the map's origin plus the cell's position plus the mesh's
    offset, turned by the map's `yaw`;
  - its size is the layout's;
  - it casts no shadow below `SHADOW_MIN_SIZE`;
  - its collision follows the hint. A Box or Hull fidelity needs a fresh mesh build
    (`AssetService:CreateMeshPartAsync` and `ApplyMesh`, as `ViewmodelPacks` does),
    because `CollisionFidelity` cannot be written at run time.
- groups the parts into one Model per cell with `ModelStreamingMode = Atomic`.

A missing layout, id or mesh is a warning; the rest of the map builds. In Studio every
cell prints a line in the chunk reports' style and keeps it as the `BudgetLine`
attribute, and the map prints a total:

```
[Prebuilt city c_p002_m001] meshes 14/60 (m 30) tris 41k/120k (m 50k) textures 5/12 (m 6)
[Prebuilt city] meshes 1830/4000 (m 2000) tris 2410k/3000k (m 1200k) textures 210/400 (m 200) | over mobile: triangles, textures
```

The budgets are in `PrebuiltMapsConfig.budgets` (per cell) and `mapBudgets` (per map).

## Files

| File | Role |
| --- | --- |
| `tools/city_import/split_scene.py` | The command: flatten, cells, merge, cap, simplify, textures, cell GLBs, `layout.json`, manifest rows |
| `tools/city_import/gltf_io.py` | glTF 2.0 reading (node tree, triangle primitives, materials, images) and GLB writing |
| `tools/city_import/emit_layout.py` | `layout.json` to `src/server/prebuilt/<map>.luau`; `--all`, `--check` |
| `src/shared/config/PrebuiltMapsConfig.luau` | The maps (none yet), concurrency, the importer turn, shadow size, budgets |
| `src/shared/world/PrebuiltMapMath.luau` | Pure: layout check, placement, collision hints, missing meshes, budget lines |
| `src/server/systems/PrebuiltMaps.luau` | Loads and places the cells |

## Checks

- `python3 tests/cityimport/run.py` uses a synthetic city generated in the test (no
  real asset): a 120 m ground grid with planar UVs and a 2048 px texture, a
  19,200-triangle tower, instanced crates (one mirrored), all under a turned and moved
  root node. It checks:
  - every triangle back in world space at the right place and scale;
  - cell membership, the cap and the lossless split, and the merge;
  - collision hints, the texture cap, winding;
  - simplification: cells meet with no unshared border vertex (the check fails with
    the border lock off), and UVs are carried over;
  - the `.gltf` reader, the manifest rows, the Luau module, and that committed layouts
    match their modules.
- `luau tests/cityimport/run.luau`: `PrebuiltMapMath` (check, placement and yaw,
  hints, missing meshes, budget lines).

Studio checks once a map is uploaded and enabled:

1. The Output shows a `[Prebuilt <map> ...]` line per cell and no `meshes not in the
   asset` warning. That confirms the importer keeps node names as MeshPart names.
2. Orientation: a landmark that reads one way (a sign, a one-sided facade) faces the
   same way as in the source. If every mesh is turned around in place, set
   `MESH_TURN_DEGREES = 180`.
3. Fly along a cell border (every 64 studs) looking for gaps or overlaps.
4. Walk on the ground (box), into a building (hull) and through clutter (no
   collision).
5. With streaming on, walk away and back: cells leave and return whole.
