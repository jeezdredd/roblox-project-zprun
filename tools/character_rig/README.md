# character_rig

The third-person soldier body: the Mixamo "Swat Guy" (FBX Binary, T-pose, with skin,
downloaded 2026-09-28, the same character the first-person arms are cut from) split into
the fifteen R15 parts. Mixamo characters are royalty-free for commercial games
(https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html).

No Blender. `soldier.py` reuses the FBX reader, skinning and texture packing in
`tools/arms_rig`:

1. The arm chains are skinned from the bind T-pose to hang straight down (upper arm,
   forearm and hand each point down, the rest pose of Roblox's own R15), the fingers take
   the first-person grip. Linear blend skinning keeps the shoulders smooth.
2. Each triangle goes to the R15 part whose bones carry most of its weight. A triangle
   with a vertex that has at least `SEAM_WEIGHT` (0.4) on another part goes to both, so a
   bent elbow or knee does not open a gap.
3. Four texture groups (head, torso, arms, legs) are repacked into 1024 atlases from the
   two 4096 Mixamo materials: colour, normal and roughness (1 - glossiness).

Scale: 0.03 studs per cm, a 5.45-stud soldier (the stock R15 is about 5.2).

    python3 tools/character_rig/soldier.py

Writes `assets/character/soldier/source/`: `<Part>.glb` (bounding-box centred, in the
Mixamo axes, because Roblox's glTF importer turns meshes 180 degrees about Y and that
lands them facing -Z), `<Group>_<Map>.png` and `rig.json` (part centres and sizes, joint
pivots, hip height and each fist's grip point, in character space: feet at y = 0,
facing -Z).

After the upload and the mesh-id read-back, `python3 scripts/build_soldier_rig.py`
writes the Rojo template `assets/character/soldier.model.json` and
`src/shared/config/SoldierRigConfig.luau`.

`studio_preview.py` writes the parts and quarter-size colour atlases as Luau data
modules into `src/shared/_SoldierPreview` (git-ignored) for an Edit-mode look through
`EditableMesh` before anything is uploaded; delete the folder afterwards. The FBX is
115 MB and git-ignored (`assets/viewmodels/arms/source/swat_guy.fbx`); download it again
from Mixamo if it is missing.
