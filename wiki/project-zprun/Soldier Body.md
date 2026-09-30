# Soldier Body

The character every player spawns as: the Mixamo "Swat Guy" (the character the
first-person arms are cut from), split into the fifteen R15 parts, instead of Roblox's
block body. Built 2026-09-30; waiting for the upload.

Related: [[Third-Person Body]], [[Third-Person Locomotion]], [[Decisions]].

## Why the body was blocky

R15 is the joint layout (fifteen parts, `Motor6D` joints), not a look. `SkinService`
applied a `HumanoidDescription` with every body part id at 0, which is Roblox's default
block body, and only recoloured it. The owner asked for human characters.

## How it is made

`tools/character_rig/soldier.py` (numpy and Pillow, no Blender; see its README):

- arms skinned from the T-pose to hang straight down, the R15 rest pose, so every R15
  clip plays unchanged; fingers in the first-person grip
- each triangle to the part its bones weigh most; seam triangles to both parts, so a
  bent joint shows no gap
- four 1024 atlases (head, torso, arms, legs) with colour, normal and roughness maps for
  a `SurfaceAppearance` per part
- 0.03 studs per cm: 5.45 studs tall, hip height 1.86

Checked in Edit before any upload, through `EditableMesh` (`studio_preview.py`): the
soldier at rest, and posed with the new rifle idle, rifle run, pistol idle, rifle
reload, the old run and the rifle strafe. Hands on a low-ready rifle, pistol arms
extended, no gaps at the elbows. `SoldierBody.apply` was run on a fresh R15 in Edit
with the preview meshes standing in for the uploads: fifteen joints on the soldier's
pivots, hip height set.

## In game

| Piece | Role |
| --- | --- |
| `src/shared/util/SoldierBody.luau` | Converts a stock R15 in place: parts swapped for the soldier meshes (`ReplicatedStorage.CharacterMeshes.Soldier` through `MeshTemplates`), rig attachments and joints moved to the pivots in `SoldierRigConfig`, other attachments scaled, block face and cages dropped, hip height set, `GripOffset` on each hand, `SoldierBody` attribute on the model; `tint` colours the uniform |
| `src/server/systems/SoldierCharacter.luau` | Once the meshes load, converts a fresh R15 and parents it as `StarterPlayer.StarterCharacter`; players who spawned on blocks before that are respawned unless they are in a run |
| `SkinService` | A soldier body gets no `HumanoidDescription` (it would swap the meshes back to blocks): accessories and clothing are removed and the skin tints the torso and legs through `SurfaceAppearance.Color` (hue of the skin's colour, 55 %) |
| `WorldWeaponModel` | A hand with `GripOffset` holds the grip at its fist, and the support sockets place the left fist, not the hand's centre, on the gun |
| `scripts/build_soldier_rig.py` | Writes the template and `SoldierRigConfig` from `rig.json` and the manifest; `ready` is false until every mesh id is filled in, and until then nothing changes |

## Owner's steps

1. `python3 scripts/upload_assets.py --only character/soldier/`: fifteen part Models and
   twelve atlases.
2. Read back each Model's MeshId in Studio (as for `zombie/walker2`) into the
   `character/soldier/meshid/<part>` rows.
3. `python3 scripts/build_soldier_rig.py`, `sync_configs.py`, `sync_needed.py`.
4. Play in Studio: the soldier spawns; then the holds are retuned on it in the yard (V),
   since `ThirdPersonConfig` holds were set on the block body's proportions.

## Open

- Skins: a tint cannot turn the grey camo white, so Field Medic reads like Recruit.
  Per-skin texture variants would fix it.
- The first-person camera still hides everything above the waist
  (`CameraController.ALWAYS_HIDDEN`); with the soldier the legs are real geometry when
  looking down.
