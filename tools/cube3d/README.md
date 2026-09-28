# Cube 3D weapon mesh pipeline

Turns a `GenerationService` (Cube 3D) weapon into a persistent mesh set that
`ViewmodelBuilder` can mount. `AssetService:CreateAssetAsync` cannot upload meshes
(the Studio binary says so), so geometry leaves Studio over localhost HTTP, becomes
GLB, goes up through Open Cloud as `Model` assets, and comes back into Studio with
`InsertService:LoadAsset` to read the real mesh ids.

All Studio scripts run from the command bar or as local plugin scripts in a place
that is published (generation refuses to run in an unsaved local file). Edit the
config block at the top of each script before running it.

## Flow

1. `tools/cube3d/GenerateWeapon.server.luau` in Studio.
   Set `WEAPON.name`, `prompt`, `groups`. Group names double as part names; `Main`
   is mandatory. Use `Bolt` for the reciprocating part of a rifle or SMG (Cube reads
   the word better than `Slide`); it is renamed on import. A shotgun uses `Pump`
   as the group name and keeps it: `MESH_BONES` binds `Pump` to the pump bone, and
   the support hand rides it when `HandLMount` is placed on the pump. Output lands in
   `Workspace.<name>_VM`. Small-part grouping is a dice roll: check that `Bolt`
   really is the bolt before continuing, and re-roll otherwise.

2. `python3 scripts/mesh_pipeline.py serve <name>` in a terminal. Leaves a receiver
   on `127.0.0.1:8973` writing into `assets/viewmodels/source/<name>/`.

3. `tools/cube3d/ExtractMeshes.server.luau` in Studio.
   Posts every MeshPart under `Workspace.<MODEL_NAME>` as OBJ plus its albedo as raw
   RGBA chunks (Studio caps a POST at 1 MB).

4. `python3 scripts/mesh_pipeline.py convert <name>`.
   OBJ to GLB, RGBA chunks to PNG, and manifest rows
   `viewmodel/<name>/model_<part>` and `viewmodel/<name>/tex_<part>` with `assetId 0`.

5. `python3 scripts/upload_assets.py --only viewmodel/<name>/`.
   Uploads the GLBs as `Model` assets and the PNGs as `Image` assets, writes the ids
   back into the manifest. Needs `.opencloud.key`.

6. `tools/cube3d/ImportMeshes.server.luau` in Studio, receiver still running.
   Reads the manifest through the receiver, `LoadAsset`s each model, assembles
   `Workspace.<name>_VM_import` next to the source with the textures applied, and
   posts `<name>_meshids.json` back. Roblox's glTF importer turns meshes 180
   degrees about Y, which is why the offsets are mirrored in X and Z here; do not
   bake a compensating rotation into the GLB. `SCALE` resizes the whole set (the
   rifle shipped at 1.7 so it reads larger than the pistol).

7. `python3 scripts/mesh_pipeline.py finalize <name>`.
   Writes `viewmodel/<name>/mesh_<part>` rows holding the mesh ids that
   `build_viewmodel.py` consumes. Add matching rows to `assets/LICENSES.md`.

8. In Studio add the marker parts to `<name>_VM_import` by hand: `Muzzle`,
   `CasingEject`, `HandRMount`, `HandLMount`, each a 0.05 stud part with
   `Transparency 1`, `CanCollide false`. The builder reads all four: the flash and
   tracer spawn at `Muzzle`, casings at `CasingEject`, and each hand is placed at its
   mount (orientation still comes from code). Without hand mounts the hands fall
   back to pistol-shaped constants near the grip. Then run `tools/cube3d/DumpRig.server.luau`
   and paste its output into `assets/viewmodels/<name>.rig.txt`.

9. `python3 scripts/build_viewmodel.py <name>` and mount the result in
   `default.project.json` under `ReplicatedStorage.ViewModels.<Class>`.

## Conventions

- Muzzle faces `-Z` in the template; `Main` is the PrimaryPart and every offset is
  measured from it.
- Part names are the bone contract in `ViewmodelBuilder.MESH_BONES`; unknown names
  weld statically instead of animating.
- `assets/viewmodels/source/<name>/` keeps the GLBs in git for re-upload; PNGs and
  intermediates are ignored because they are regenerable from the uploaded ids.
