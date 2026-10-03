# Stances

Tactical-shooter weapon handling on the first-person rig: three carry stances, a
manual lean and a magazine check. Branch `cloud/stances` (2026-10-03). All visual: the
server's rules, hit detection and ammo are unchanged. Related: [[Wall Pullback]],
[[Third-Person Body]], [[Gameplay Systems]].

## Controls

| Key | Does |
| --- | --- |
| X | Cycles mid, high ready (muzzle up), low ready (muzzle down) |
| Q / E | Lean left / right while held (`StanceConfig.LEAN.mode = "toggle"` makes them toggles). E does not lean while a ProximityPrompt is on screen (E is the prompt key) |
| R, short press | Reload, on release (released before `MAG_CHECK.holdTime`, 0.3 s) |
| R, held | Magazine check: the weapon tips toward the camera, the count shows while it is in; shown for at least 0.9 s |
| Mouse wheel | Loadout quick swap (was Q) |

Keys are item names in `StanceConfig.keys`.

## Files

| File | Role |
| --- | --- |
| `src/shared/config/StanceConfig.luau` | Keys, the cycle, the poses (hold space, degrees), easing, raise time per class, the stay-up time, lean numbers, magazine check numbers and readout |
| `src/shared/util/StanceMath.luau` | Pure: stance weights and easing, the raise a shot waits for, the check's hold, minimum show and readout, the lean's camera offset, wall room, viewmodel counter-pose, body roll, the lean on the wire. `luau tests/stances/run.luau` |
| `src/client/systems/Stances.luau` | Input (X, Q, E), the state, the pose for the viewmodel, the camera lean, the fire gate |
| `PackViewmodel.setStancePose` | A pose slot after the wall pose: `placement * hold * wallPose * stancePose * eyeInverse` |
| `Viewmodel.stepPack` | Asks Stances for the pose every frame; a reload, the draw or an inspect eases it out |
| `WeaponController` | `Stances.requestFire` before a shot; hold R as the check; the count label; quick swap on the wheel |
| `BodyRig.setLean`, `BodyController`, `AimReplicator`, `BodyAimRelay` | The third-person waist roll; the lean (tenths) as a third value on the BodyAim packet, clamped by the relay |

## Rules

- **Stances** are poses in the pack viewmodel's hold space, eased exponentially (in at
  9/s, out at 12/s), the same channel style as the wall pull-back. Mid is the class's
  own hold.
- **Firing from high or low ready** starts a raise. The time per class comes from
  `raiseTime` (Pistol 0.10/0.12 s up to Shotgun 0.19/0.24 s for high/low), scaled by
  how far in the stance is. The shot leaves when the gun is up: a press during the
  raise fires at its end. The gun then stays up for `RETURN_AFTER` (1.4 s) after the
  last shot, and eases back to the chosen stance.
- **A reload, the draw or an inspect** eases the stance out. The stance stays chosen
  and comes back after.
- **Lean.** The camera rolls 13 degrees and moves 1.05 studs sideways and 0.12 down.
  A sphere cast at the side shortens the offset so the camera stays 0.25 studs off a
  wall. The lean goes on the camera after the camera's own steps (render priority
  Camera + 2), and comes off before them (Camera - 1) only if nothing else moved the
  camera, so the runner camera's lerp never sees it. Outside a live run (death, cabin,
  menus) it drops at once.
- **The viewmodel** rolls with the camera and takes 55 percent of the roll back
  (`viewmodelCounterRoll`), nudged toward the lean.
- **Third person:** the upper torso rolls up to 16 degrees at the waist (`bodyRoll`).
  Other clients get the lean on the BodyAim packet.
- **Magazine check.** The pose replaces the stance while it is held. The count (from
  the client's predicted magazine) shows once the pose is 80 percent in.
  `readout = "estimate"` shows Full, Almost full, About half, Almost empty or Empty
  instead of the number. `hideAmmoCounter = true` hides the corner counter outside a
  check. A shot during the check ends it and raises first (0.14 s); a reload or a
  weapon change ends it at once.
- **Pack viewmodel only.** Without a pack rig (the legacy rig, the hub, death) there
  are no stance poses and every shot is allowed at once; a held R still reloads on
  release.

## Studio checks (owner)

Checked as motion, per [[Development Policy]] section 2: `ViewmodelTimeScale` 0.2,
frames sampled every few frames. Under a locked cursor the Studio hook drives it from
the command bar: `game.ReplicatedStorage.DebugWeapon:Fire("stance")` (also `"magcheck"`,
`"magcheck_end"`, `"lean_left"`, `"lean_right"`, `"lean_off"`, `"fire"`).

1. X through the three stances on each class: the poses read as high ready and low
   ready. Each transition has no pop, and the walk and idle clips still play
   underneath.
2. From low ready, one click with the rifle: the gun comes up, the shot leaves at the
   top (muzzle flash on the frame the raise ends), and the gun returns to low ready
   about 1.4 s later. Hold the trigger on the SMG: one raise, then continuous fire.
3. Lean against a wall on each side: the view stops short of the wall, with no
   clipping. The gun cants less than the view. Release: back with no snap.
4. A second client (or the test yard's third-person view, V) sees the upper body lean
   to the same side.
5. Tap R: reload as before. Hold R: the weapon tips, the count appears near the bottom
   centre, and it disappears as the weapon goes back. Click during the check: the gun
   comes up, then fires.
6. Next to a pickup or vendor prompt, E takes the prompt and does not lean.
7. The mouse wheel swaps loadout slots, and Q no longer does.

Not checked yet: the pose numbers are first guesses in the hold space (same scale as
the wall pull-back) and need tuning on screen.
