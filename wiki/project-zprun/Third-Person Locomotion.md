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
| `src/shared/config/AnimationsConfig.luau` | `locomotionClips` (gaits `Core`, reload and hit `Action`), `locomotionSets`, `GAIT_REFERENCE`, `SET_GAIT_REFERENCE`, `WALK_SPEED_MAX`, `STRAFE_AXIS`, `SPRINT_SPEED`, `SPRINT_HYSTERESIS` |
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

- Set: `Pistol` -> pistol; rifle, SMG, shotgun and no weapon -> rifle. Only the pistol
  has its own set.
- Gait (`AnimationsConfig`): idle when still; walk under 6 studs/s (`WALK_SPEED_MAX`);
  run turns to sprint at 14 studs/s (`SPRINT_SPEED`) and drops back only below 12
  (`SPRINT_HYSTERESIS` 2), separate from the body layer's `ThirdPersonConfig.SPRINT`;
  run otherwise.
- Strafe: `STRAFE_AXIS` 0.7 on the sideways share of the ground velocity in the
  character's frame (-1 all left, 1 all right). Set so the auto-run swerving at 24 with
  a full A/D (share about 0.55) keeps its run. Moving mostly sideways side-steps at any
  speed and overrides sprint, since a forward-facing run clip would glide.
- Fallback: the set's clip, else the set's run, else `Run` with the additive legacy
  strafe when it exists; idle without a clip plays nothing. Sets never borrow.
- Rate: speed over the set's gait reference, clamped 0.6..2 (the pistol run covers 13.4
  studs/s and the game's 24 needs about 1.8).
- `SET_GAIT_REFERENCE` is the ground speed each Mixamo clip covers at its recorded rate
  on the soldier: rifle walk 3.3, run 8.6, sprint 18.9; pistol walk 7.2, run 13.4.
  Measured 2026-09-30 as the planted foot's speed in the X Bot In Place clip, scaled by
  leg length (soldier hips 93.9 cm against the X Bot's 104, at 0.03 studs per cm).
  The game's 24 is a hard run for these clips, so the rifle plays its sprint there and
  the pistol speeds its run up. `GAIT_REFERENCE` (walk 10, run 24, sprint 36) now
  applies only to the legacy `Run` clip.
- The body layer is untouched: `BodyRig` writes after the `Animator` in
  `PreSimulation`, so the arms land on the gun over any gait.

## Owner's steps

Done on 2026-09-30: all sixteen clips exported from the Mixamo X Bot as Collada (With
Skin, 30 fps, no keyframe reduction, In Place on the loops, off the one-shots) and
converted by `tools/animation_pipeline/dae_to_keyframes.py` into `assets/animation/`
(the arm rest offset fixed on the way, see [[Decisions]]). Uploaded and approved the same day;
the gallery's soldier mannequins run on the new pistol gait.

## Trade-offs (owner's calls made here)

- No pistol sprint slot: the pistol run speeds up instead.
- The zombie clips sit under `animation/zombie/`, with the clips `ZombieAnimator` reads.
- The one-shots (`RifleReload`, `HitRifle`) are loaded and callable but not wired: the
  body layer's reload gesture stays the reload the game shows.
