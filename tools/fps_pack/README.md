# fps_pack

First-person weapon packs (arms + weapon + animations, glTF from Sketchfab) to Roblox,
without Blender and without uploading Animation assets.

1. `gltf_anim.py report <scene.gltf>`: meshes, triangle counts, materials, textures, the
   skin's joint tree and every animation with its length.
2. `gltf_anim.py bake <scene.gltf> <baked.json> [--fps 30]`: samples every animation and
   stores, per joint, the animated local transform relative to its rest transform
   (what Bone.Transform expects). Joints a clip never moves are dropped.
3. `emit_luau.py <baked.json> <out.luau> --scale <studs per metre> [--rename Old=New]
   [--skip REGEX]`: key reduction (0.002 stud, 0.25 degree) and int16 packing into a
   ModuleScript, one base64 string per joint track.
4. `src/client/systems/ViewmodelClipPlayer.luau` decodes those tracks and writes
   Bone.Transform each frame, with crossfades and duration stretching.

The skinned mesh itself (arms + weapon with its bones) goes through the normal asset
pipeline: `assets/manifest.json` -> `scripts/upload_assets.py` -> `scripts/sync_configs.py`,
and the pack's author is credited in `assets/LICENSES.md` (CC-BY 4.0).

Broken skins: some Sketchfab exports share one skin between several meshes but keep the
inverse bind matrices of only one of them (the Uzi pack's are the background plane's),
so the mesh imports thousands of units wide next to bones in metres. `skin_fixes/<class>.json`
holds the vertex and inverse-bind corrections solved from the pack's source FBX;
`strip_glb.py --skin-fix` writes the repaired rig and `build_clips.py` bakes with the same
file (`gltf_anim.py bake --skin-fix`).
