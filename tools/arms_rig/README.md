# arms_rig

First-person arms cut from the Mixamo "Swat Guy" character (FBX Binary, T-pose, with skin),
downloaded 2026-09-28. Mixamo characters are royalty-free for commercial games
(https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html).

No Blender. `fbx.py` reads the binary FBX, `pose.py` curls the finger bones into a grip
with linear blend skinning, `build.py` cuts each arm into two rigid parts and writes:

- `Hand{R,L}.glb`: hand with baked grip pose. Local frame: fingers toward -Z, back of the
  hand +Y, origin at the grip axis (the point the weapon mount should sit on).
- `Forearm{R,L}.glb`: forearm plus 6 cm past the elbow. Local frame: origin at the wrist,
  forearm running toward +Z.
- `Arm{R,L}_{Color,Normal,Roughness}.png`: one 1024 atlas per arm, repacked from the two
  4096 Mixamo materials (roughness = 1 - glossiness).
- `rig.json`: part centres and sizes (studs, meshes are bbox-centred as Roblox imports
  them), the wrist position in the hand frame and the forearm rotation in the hand frame.

Scale is 0.041 studs per cm, which matches the M4A1 viewmodel (about 3.25 studs for an
80 cm rifle).

Run from the repo root (numpy + Pillow):

    python3 tools/arms_rig/build.py assets/viewmodels/arms/source

Grip poses live in `GRIPS` in `build.py` (degrees per finger joint). `preview.py` and
`verify.py` render quick software previews to check a pose before uploading.

The FBX is 115 MB and git-ignored; download it again from Mixamo if it is missing.
