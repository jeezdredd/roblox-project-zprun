# Prebuilt Maps

Large static scenes (GLB or glTF) split into upload-sized cells and placed as streamed
Models under `Workspace.PrebuiltMaps/<map>`. Branch `cloud/city-import` (2026-10-01);
the command, the flags, the upload and the Studio checks are in
`docs/environment/prebuilt-maps.md`. Related: [[Environment]], [[Assets Pipeline]],
[[Performance]].

## Files

| File | Role |
| --- | --- |
| `tools/city_import/split_scene.py` | Flattens the node tree to world space in studs (`--scale`, default 1 / 0.28), cells of `--cell` studs, merges small meshes per material, splits (or simplifies with locked borders) meshes over `--max-tris`, shrinks textures to `--texture`, writes one GLB per cell and `layout.json`; with `--map`, pending manifest rows and the Luau layout |
| `tools/city_import/gltf_io.py` | glTF 2.0 reading and GLB writing, numpy and Pillow only |
| `tools/city_import/emit_layout.py` | `layout.json` to the server-side `src/server/prebuilt/<map>.luau` (`--all`, `--check`) |
| `src/shared/config/PrebuiltMapsConfig.luau` | The maps (origin, yaw, enabled), load concurrency, the importer turn, budgets |
| `src/shared/world/PrebuiltMapMath.luau` | Pure: layout check, placement, collision hints, budget lines. `luau tests/cityimport/run.luau` |
| `src/server/systems/PrebuiltMaps.luau` | Server stage "PrebuiltMaps": `InsertService:LoadAsset` per cell, meshes placed by name from the layout, collision from the hint, one Atomic-streamed Model per cell, budget lines in Studio |

## Rules

- Cell names `c_<x>_<z>` (`p`/`m` sign), meshes `<cell>_<nnn>`; the manifest key is
  `model/maps/<map>/<cell>`, the id reaches `AssetIds.model.maps.<map>.<cell>`.
- A wide mesh is cut by triangle centroid and a mesh over the cap is halved; both keep
  the shared vertices, so cells meet without cracks. Simplification locks open borders
  and carries UVs and normals over from the original triangles.
- Collision hint, decided on the whole source mesh and kept by every cut piece: `none`
  for clutter, `default` (near-planar) or `precise` (relief) for meshes wider than a
  cell, `box` for near-planar meshes within a cell (PCA thickness), `hull` otherwise.
- Shared vertex buffers are compacted per primitive; buffers are read through
  memoryview; `KHR_texture_transform` is baked; Draco, meshopt, GPU instancing and
  Basis textures are refused with what to do; Luau keywords are refused as map names.
- Geometry is written turned 180 degrees about Y for the importer;
  `MESH_TURN_DEGREES` corrects it if Studio shows otherwise.
- All of `assets/maps/` is gitignored (`--out` is checked with `git check-ignore`); the
  server-side Luau module is the committed record. Cells load through a fixed worker
  pool, each in `pcall`. No map is listed in the config yet.
- FBX is not read yet: the FBX reader parses the node tree but builds no static
  meshes; export to glTF.

## Tests

`python3 tests/cityimport/run.py` (a synthetic city generated in the test: world-space
flattening, cells, cap, merge, hints, texture cap, winding, simplification without
cracks, UV transfer, `.gltf`, manifest rows, Luau module) and
`luau tests/cityimport/run.luau`.
