# Third-Person Locomotion

Per-class locomotion clips for the visible soldier: a rifle set and a pistol set from
Mixamo, retargeted onto R15 through `tools/animation_pipeline/retarget_mixamo.py`, chosen
by the weapon class and the movement state, with the generic `Run` as the fallback while
a slot is empty. Branch `cloud/third-person-locomotion` (2026-09-30); the design and the
owner's steps are `docs/animation/third-person-locomotion.md`. See [[Third-Person Body]]
for the layer that sits on top and [[Assets Pipeline]] for the slot rule.

## Files

| File | Role |
| --- | --- |
| `src/shared/util/LocomotionMath.luau` | Pure: set by class, gait by movement, clip weights with fallbacks, playback rate. `luau tests/animation/run.luau` |
| `src/shared/config/AnimationsConfig.luau` | `locomotionClips` (gaits `Core`, reload and hit `Action`), `locomotionSets`, `GAIT_REFERENCE`, `WALK_SPEED_MAX`, `STRAFE_AXIS` |
| `src/client/controllers/AnimationController.luau` | Loads both clip tables, picks the set from `WeaponId`, blends the gait; `clipSetFor(class)`, `playAction(kind)`, `currentGait()` |
| `src/server/systems/ZombieAnimator.luau` | Dormant rise from `stand_up_back` / `stand_up_stomach`, Feeding pose from `biting_ground`, each when non-zero |
| `tools/animation_pipeline/retarget_mixamo.py`, `README.md` | The new loop slots and the search phrases |
| `assets/manifest.json`, `assets/NEEDED.md`, `scripts/sync_needed.py` | Sixteen `needed` slots with Mixamo provenance |

## Slots

`animation/player/`: `rifle_idle`, `rifle_walk`, `rifle_run`, `rifle_sprint`,
`rifle_strafe_left`, `rifle_strafe_right`, `rifle_reload`, `pistol_idle`, `pistol_walk`,
`pistol_run`, `pistol_strafe_left`, `pistol_strafe_right`, `hit_rifle`.
`animation/zombie/`: `stand_up_back`, `stand_up_stomach`, `biting_ground`. All 0 until
the owner downloads, retargets and uploads; `AnimationController.clipSetFor(class)`
returns the ids per gait so the yard gallery can adopt them.

## Rules

- Set: `Pistol` -> pistol; rifle, SMG, shotgun and no weapon -> rifle.
- Gait: idle when still; sprint by `BodyMath.sprintTarget` against
  `ThirdPersonConfig.SPRINT` (36, hysteresis 4) and never strafing; strafe at lateral
  input 0.5 and beyond; walk under 12 studs/s; run otherwise.
- Fallback: the set's clip, else the set's run, else `Run` with the additive legacy
  strafe when it exists; idle without a clip plays nothing. Sets never borrow.
- Rate: speed over the gait reference (walk 10, run 24, sprint 36), clamped 0.8..1.45.
- The body layer is untouched: `BodyRig` writes after the `Animator` in
  `PreSimulation`, so the arms land on the gun over any gait.

## Owner's steps

Mixamo export: FBX Binary, Without Skin, 30 fps, no keyframe reduction, In Place on for
loops and off for the one-shots; files named `player_<slot>.fbx` / `zombie_<slot>.fbx`
in `tools/animation_pipeline/input/`; `blender -b -P retarget_mixamo.py`; publish from
Studio; ids into the manifest; `sync_configs.py`, `sync_needed.py`.

## Trade-offs (owner's calls made here)

- No pistol sprint slot: the pistol run speeds up instead.
- The zombie clips sit under `animation/zombie/`, with the clips `ZombieAnimator` reads.
- The one-shots (`RifleReload`, `HitRifle`) are loaded and callable but not wired: the
  body layer's reload gesture stays the reload the game shows.
