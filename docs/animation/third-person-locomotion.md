# Third-person weapon locomotion

Companion to [third-person-body.md](third-person-body.md). The body layer puts the
weapon, the aim and the hand IK on top of whatever the `Animator` plays; until now that
was the generic `Run` clip for every weapon, so a teammate with a pistol ran like a
teammate with a shotgun, arms swinging under the gun. This adds per-class locomotion
clip slots from Mixamo, retargeted onto R15 through the pipeline the project already
has, and the client code that plays them. Every slot is empty (`assetId` 0) until the
owner downloads and uploads; the code falls back to the clips that play today.

## 1. What changes

| Piece | Before | After |
| --- | --- | --- |
| Clip slots | `player/run`, `strafe_left`, `strafe_right`, `stumble`, `death` | plus `rifle_idle`, `rifle_walk`, `rifle_run`, `rifle_sprint`, `rifle_strafe_left`, `rifle_strafe_right`, `rifle_reload`, `pistol_idle`, `pistol_walk`, `pistol_run`, `pistol_strafe_left`, `pistol_strafe_right`, `hit_rifle` under `animation/player/`; `stand_up_back`, `stand_up_stomach`, `biting_ground` under `animation/zombie/` (they are read by `ZombieAnimator` from `AssetIds.animation.zombie`, so they sit with the other zombie clips) |
| `AnimationsConfig` | five clips | `locomotionClips` (gaits at `Core` priority like `Run`, the reload and the hit at `Action`), `locomotionSets` (`Rifle`, `Pistol`), the gait reference speeds, the walk ceiling and the strafe input threshold |
| `AnimationController` | plays `Run` when moving, the additive `StrafeLeft` / `StrafeRight` by input sign, speed-scaled | picks the set from the local player's `WeaponId` class (`Pistol` -> pistol set, everything else -> rifle set), the gait from the movement state, the clip weights from what is loaded, the playback rate from the gait's reference speed; exposes `clipSetFor(class)`, `playAction(kind)` and `currentGait()` |
| `ZombieAnimator` | the Dormant rise is `idle_c`, the Feeding pose is `feeding` | the rise picks one of the two stand-up clips and the Feeding pose takes the biting clip, each only when its id is non-zero |
| Pipeline | `retarget_mixamo.py` slot list | the new loop slots added so the seam and root-motion checks run on them; README slot table extended |

Nothing in `src/client/body` changes: `BodyRig` still writes the waist and neck twist,
the weapon frame and the hand IK in `PreSimulation` after the `Animator`, so the arms
land on the gun whichever gait plays underneath.

## 2. Gait selection

`src/shared/util/LocomotionMath.luau` (pure, tested by `tests/animation/run.luau`):

- `setFor(class)`: `Pistol` -> `Pistol`; `Rifle`, `SMG`, `Shotgun` and no weapon ->
  `Rifle` (the SMG and the shotgun are carried two-handed).
- `gaitFor(moving, speed, lateral, sprinting)`: not moving -> `idle`; the sprint
  decision wins (`BodyMath.sprintTarget` against `ThirdPersonConfig.SPRINT.speed` 36
  with its 4-stud hysteresis, the same rule the body layer uses for the sprint pose);
  lateral input at or beyond 0.5 -> `strafe_left` / `strafe_right`; below
  `WALK_SPEED_MAX` 12 -> `walk`; else `run`. A sprint never strafes.
- `targets(set, gait, available)`: the set's own clip; else the set's fallback gait
  (`walk`, `sprint` and the strafes fall to the set's `run`); else the generic `Run`,
  with the legacy additive `StrafeLeft` / `StrafeRight` on top when they exist. `idle`
  without an idle clip plays nothing, as today. A set never borrows the other set's
  clips.
- `playbackRatio(gait, speed)`: speed over the gait's reference (`walk` 10, `run` 24,
  `sprint` 36 studs/s; strafes use the run reference), clamped to the existing
  0.8..1.45, so the feet match the ground at every ramp speed.

The controller blends weights with the existing `BLEND_SPEED` and 0.15 s play /
0.2 s stop fades; a clip whose weight falls under 0.01 stops. The one-shots
(`RifleReload`, `HitRifle`) are loaded at `Action` and played through
`AnimationController.playAction("reload" | "hit")` or `playOneShot(id)`; nothing calls
them yet, since the body layer's reload gesture is the reload the game shows today.

## 3. What the owner runs

Done on 2026-09-30 for all sixteen slots, without Blender:

1. Each clip exported from Mixamo on the X Bot: **Format** Collada (.dae), **Skin**
   With Skin (the retarget needs the bind pose), **FPS** 30, **Keyframe Reduction**
   none, **In Place** on for every loop (idle, walk, run, sprint, strafes, biting), off
   for the one-shots (reload, hit reaction, the two stand-ups, whose root travel is part
   of the move). Saved as `tools/animation_pipeline/input/player_rifle_run.dae`,
   `zombie_stand_up_back.dae` and so on (git-ignored: Mixamo clips are not
   redistributed).
2. `python3 tools/animation_pipeline/dae_to_keyframes.py --output assets/animation
   --clip "tools/animation_pipeline/input/player_rifle_run.dae=player/rifle_run:loop"
   ...` (`:once` for the one-shots): writes `assets/animation/<slot>.rbxmx`, which Rojo
   mirrors into `ReplicatedStorage.AnimationClips` for an Edit-mode look.
3. What is left for the owner: `python3 scripts/upload_assets.py --only animation/`,
   then `python3 scripts/refresh_status.py`, `python3 scripts/sync_configs.py` and
   `python3 scripts/sync_needed.py`. No code change follows: every consumer reads
   `AssetIds` at load.

The retarget fix of 2026-09-30: R15 rests with the arms hanging down, the Mixamo bind
is a T-pose, and the converter took every arm rotation from the T-pose as if it started
from arms-down, so the Mixamo arms came out folded against the chest (a pistol aim with
the hands at the collar). The arm, forearm and hand now carry a rest offset (straight
down onto the bone's bind direction) before the parent-relative step; the upper and
lower arm directions of `pistol_idle`, `rifle_idle` and `rifle_reload` match the source
to 0.0 degrees. If a clip's stride reads too long or too short at speed, the lever is
`AnimationsConfig.GAIT_REFERENCE`.

## 4. Studio check list

- Yard, rifle in hand, walk (below 12 studs/s), run, sprint (above 36): with the slots
  still empty the generic `Run` plays at every speed, exactly as before this change.
- Upload `rifle_run` alone: the run replaces `Run` while any of the rifle, SMG or
  shotgun is held, `Run` comes back with the pistol; walk and sprint play the rifle run
  slowed and sped up (0.8..1.45).
- Upload the strafes: strafing left and right cross-fades from the run within
  `BLEND_SPEED`; a sprint with lateral input stays a sprint.
- Upload the pistol set: switch to the pistol mid-run; the gait changes with the
  weapon; `clipSetFor("Pistol").sprint` is nil and the pistol run speeds up instead.
- Third person (V) and a second player: the aim twist and the hand IK sit on the gun
  over every gait; the support hand stays on the handguard through the strafes; the
  sprint pose from `ThirdPersonConfig.SPRINT` lands on top of the sprint clip.
- Zombies: with `stand_up_back` / `stand_up_stomach` uploaded the risers use them and
  wake after the clip length; without them `idle_c` as before. With `biting_ground`
  uploaded the feeders hold it; without it `feeding`. Skinned zombies keep their own
  clips either way.
- The K overlay and the Animator track list: at most one gait at full weight plus the
  cross-fading one; no `Run` and set clip both at 1.

## 5. Decisions made here

- The stand-up and biting clips live under `animation/zombie/`, next to the clips
  `ZombieAnimator` already reads, rather than under `animation/player/`.
- A pistol sprint slot is not planned; the pistol run speeds up to the sprint speed.
- The SMG and the shotgun use the rifle set.
- Sets never borrow from each other; the fallback is inside the set and then `Run`.
