# Animation pipeline — Mixamo to Roblox R15

Owner-facing steps. Claude Code maintains the slot list and the script; downloading, running Blender and uploading are manual.

## 1. What to download

Every slot below is currently empty (`assetId = 0`). The Mixamo search phrase is exact — paste it into the Mixamo search box.

### Zombies — `AssetIds.animation.zombie`

| Slot | Mixamo search | Notes |
| --- | --- | --- |
| `idle_a` | `Zombie Idle` | loop |
| `idle_b` | `Zombie Neck Bite` (idle portion) | loop, pick the calmer variant |
| `idle_c` | `Zombie Stand Up` | non-loop, used as a rise-from-ground beat |
| `walk_shuffle` | `Zombie Walk` | loop, in-place |
| `run_ragged` | `Zombie Running` | loop, in-place |
| `attack_lunge` | `Zombie Attack` | non-loop |
| `feeding` | `Zombie Feeding` (or `Eating`) | loop |

### Player body — `AssetIds.animation.player`

| Slot | Mixamo search | Notes |
| --- | --- | --- |
| `run` | `Running` | loop, in-place, hands must suit a rifle carry |
| `strafe_left` | `Left Strafe` | loop, in-place |
| `strafe_right` | `Right Strafe` | loop, in-place |
| `stumble` | `Stumble Backwards` | non-loop |
| `death` | `Falling Back Death` | non-loop, lands on the back — the death cam expects a supine pose |

### Weapon viewmodel — `AssetIds.animation.weapon`

These come from the Universal Viewmodel Template rather than Mixamo, because they must match the viewmodel rig rather than R15. Slots: `fire`, `reload`, `equip`, `inspect`, `sprint`.

**Before converting our viewmodel to Motor6D, send Claude Code the template's joint dump** — the Motor6D names and hierarchy. Roblox binds animation by joint name, so our rig has to match the template or carry a mapping table.

## 2. Mixamo export settings

For every clip: **Format** FBX Binary, **Skin** `Without Skin`, **Frames per Second** 30, **Keyframe Reduction** none. Enable `In Place` for every loop clip (run, strafes, walk, shamble) so the root does not drift.

Save the FBX files into `tools/animation_pipeline/input/`, named after the slot: `zombie_walk_shuffle.fbx`, `player_run.fbx`, and so on. The script uses the file name to label the output.

## 3. Blender setup

1. Blender 4.x.
2. Install the official Roblox Blender animation add-on (Roblox → Blender Animation Exporter) so Studio can read the result.
3. Verify Blender is on PATH: `blender --version`.

## 4. Run the retarget

```bash
cd tools/animation_pipeline
blender -b -P retarget_mixamo.py -- --input input --output output
```

Options:

- `--input DIR` — folder of Mixamo FBX files (default `input`)
- `--output DIR` — where the retargeted `.blend` and `.fbx` files land (default `output`)
- `--fps 30` — expected frame rate; anything else is reported as a warning
- `--loop-threshold 0.02` — how far the first and last frame may differ before a loop clip is flagged

The script prints one block per clip and exits non-zero if any clip failed hard. Warnings it raises:

- a Mixamo bone with no R15 mapping (the bone is skipped, the clip still converts)
- a loop-slot clip whose first and last frame disagree beyond the threshold
- a clip whose frame rate is not 30
- root motion left in an in-place clip (the root travels more than a stud over the clip)

## 5. Import and upload

1. Open each output `.blend` (or import the `.fbx`) in Blender, confirm it plays cleanly on the R15 rig.
2. Export through the Roblox add-on into Studio, or import the FBX with the Studio Animation Editor.
3. Publish each animation from the Animation Editor and copy its asset id.
4. Record the ids in `assets/manifest.json` under the matching key (`animation/zombie/walk_shuffle` and so on) with `"status": "approved"`.
5. Run `python3 scripts/sync_configs.py` — this regenerates `src/shared/config/AssetIds.luau` and `assets/LICENSES.md`.

Every `Animator:LoadAnimation` in the codebase reads its id from `AssetIds`, so no code changes are needed once the ids land.

## 6. Licensing note

Mixamo animations are free to use in games under Adobe's licence, including commercial ones, with no attribution required. Record `https://www.mixamo.com/` as the manifest source and `Mixamo (Adobe) free licence` as the licence so `LICENSES.md` stays accurate.

## 7. CC0 libraries without Mixamo: `glb_to_keyframes.py`

Since the 2026-09-07 policy revision the zombie and player clips come from the
Quaternius Universal Animation Library 1 and 2 (CC0), downloaded from OpenGameArt
as `universal_animation_librarystandard.zip` and
`universal_animation_library_2standard.zip`. Their GLB files carry every clip as a
named action on one Unreal-mannequin (UAL2) or Rigify (UAL1) rig. The script samples an
action at 30 fps, expresses each R15 joint as the child bone's world rotation relative
to its parent's, converts Blender Z-up to Roblox Y-up (`X -> -X`, `Y -> Z`, `Z -> Y`,
which also turns Blender's -Y facing into Roblox's -Z) and writes a `KeyframeSequence`
`.rbxmx` straight into `assets/animation/<slot>.rbxmx`, ready for `upload_assets.py`.

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --python tools/animation_pipeline/glb_to_keyframes.py -- \
  --library "path/to/UAL2_Standard.glb" --output assets/animation \
  --clip "Zombie_Walk_Fwd_Loop=zombie/walk_shuffle:loop" \
  --clip "Zombie_Scratch=zombie/attack_lunge:once"
```

Flags per clip: `loop` (seamless, horizontal pelvis travel stripped, `Priority`
Movement), `once` (root translation kept, Priority Action), `priority=idle|movement|
action|action2|action3|action4`. `--scale` is studs per metre (3.2 fits the 1.65 m
mannequin to a 5.3-stud R15). `ReplicatedStorage.AnimationClips` mirrors the folder
through Rojo, so a clip can be previewed in Edit mode before upload with
`KeyframeSequenceProvider:RegisterKeyframeSequence` plus `Animator:StepAnimations`.

Slot to clip map used on 2026-09-07:

| Slot | Library | Action |
| --- | --- | --- |
| `zombie/idle_a` | UAL2 | `Zombie_Idle_Loop` |
| `zombie/idle_b` | UAL1 | `Idle_Loop` |
| `zombie/idle_c` | UAL2 | `LayToIdle` (one-shot, not in the idle rotation) |
| `zombie/walk_shuffle` | UAL2 | `Zombie_Walk_Fwd_Loop` |
| `zombie/run_ragged` | UAL1 | `Jog_Fwd_Loop` |
| `zombie/attack_lunge` | UAL2 | `Zombie_Scratch` |
| `zombie/feeding` | UAL1 | `Fixing_Kneeling` |
| `player/death` | UAL1 | `Death01` |
| `player/stumble` | UAL2 | `Hit_Knockback` |

The standard tiers carry no strafe loops, so `player/strafe_left` and
`player/strafe_right` stay open.
