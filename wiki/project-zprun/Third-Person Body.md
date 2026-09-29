# Third-Person Body

The visible soldier: how teammates (and the local player in the yard's third-person
view, key V) hold the weapon, aim, kick, reload, draw and sprint on top of the
locomotion that already runs. Branch `feature/third-person-body` (2026-09-29); the full
design, research and Studio test plan are in `docs/animation/third-person-body.md`.

## Files

| File | Role |
| --- | --- |
| `src/shared/config/ThirdPersonConfig.luau` | Data: per-class hold frame and sockets, aim shares and clamps, smoothing, recoil scale, sprint pose, gesture constants, wire rate, LOD bands |
| `src/shared/util/BodyMath.luau` | Pure math: aim smoothing and spread, wire quantisation and validation, the closed-form recoil spring, the magazine / shell / pump / equip timelines, sprint hysteresis, LOD cadence. `luau tests/body/run.luau` |
| `src/shared/util/WorldWeaponModel.luau` | The five-part gun builder (moved out of `WorldWeapon`) with the grip sockets: `GripSocket`, `SupportSocket`, `MagazineSocket`, `ChargeSocket`, `PortSocket`, `PumpSocket`, `Muzzle` |
| `src/server/systems/WorldWeapon.luau` | Calls the shared builder on `WeaponId` and appearance load, as before |
| `src/server/systems/BodyAimRelay.luau` | Validates, rate-limits and relays the aim packets on `Remotes.Unreliable.BodyAim` |
| `src/client/body/BodyRig.luau` | One character: joints, two `IKControl`s, two target attachments, the state, `update(dt)` |
| `src/client/body/BodyController.luau` | Binds every other player's character (and the local one in third person), feeds the rigs, schedules by LOD in `PreSimulation` |
| `src/client/body/AimReplicator.luau` | The local aim onto the wire at most 20 times a second |
| `src/client/systems/SandboxBodyGallery.luau` | The yard station: 4 classes x 11 mannequins driven by scripted inputs |
| `src/shared/net/Remotes.luau` | `Remotes.Unreliable`, `getUnreliableEvent` |

## The layer stack

In `RunService.PreSimulation`, after the `Animator` has written its pose and skipped on
frames where `Animator.EvaluationThrottled` says the pose was reused:

1. Locomotion, unchanged: the `Run` / `Strafe` / `Stumble` / `Death` tracks,
   `BodyMotionController`'s lean (local, `C0`), `FootPlanting` (local, hub).
2. Aim spread: `Waist.Transform` gets 35 % of the pitch and 55 % of the yaw twist,
   `Neck.Transform` 25 % and 45 %, multiplied onto the animator's pose (the rig
   remembers what it wrote, so a joint the animator did not rewrite starts from the
   same base instead of stacking).
3. Weapon frame: the class's `hold` (the grip part in `UpperTorso` space), lowered for
   the draw and the sprint, pitched by the remaining 40 % of the aim about a pivot
   between the shoulders, kicked by the recoil springs.
4. Gestures: the reload, pump, draw and cancel timelines move the support hand between
   the gun's sockets and the belt.
5. Hands: `IKControl` (`Transform`) on `RightUpperArm -> RightHand` to `hold *
   GripSocket` and on `LeftUpperArm -> LeftHand` to the gesture pose, both targets
   attachments on the `UpperTorso`. The welded `WorldWeapon` follows the right hand.
   Weights fade out when the character dies, drops the weapon or is beyond the IK
   range, and `Enabled` goes false at zero.

## What reaches other clients, and how

| Signal | Wire | Read by |
| --- | --- | --- |
| Aim pitch and yaw offset | `UnreliableRemoteEvent` `BodyAim`, whole degrees, sent on a one-degree change with a 50 ms floor and a 1 s keepalive; the server clamps (89 / 179), drops under 45 ms, relays with the sender | `BodyController.onAim`, smoothed with a 0.08 s time constant |
| Shot | the existing `WeaponHit` `"Shot"` (shooter, weapon) | `BodyRig.fire`: kick and snap impulses, the pump on the shotgun |
| Reload | the existing `Reloading`, `AmmoMag`, `AmmoReserve`, `ReloadScale` attributes | `BodyRig.startReload(empty, shells, scale)` / `endReload` |
| Equip | the existing `WeaponId` attribute and the rebuilt `WorldWeapon` | `BodyRig.setWeapon` + `equip` |
| Sprint | root velocity (physics replication) | `BodyRig.setSpeed`, on at 36 studs/s with 4 of hysteresis |

## Per class

| Class | Hold (grip in torso space) | Support hand | Chambering | Recoil scale (kick, snap) |
| --- | --- | --- | --- | --- |
| Pistol | (0.3, 0.45, -1.15) | cupping the grip | slide: the weapon itself pulls back 0.12 | 0.6, 1.2 |
| SMG | (0.3, 0.3, -0.95) | receiver front | top bolt, 0.3 back | 0.8, 0.9 |
| Rifle | (0.32, 0.25, -0.9) | handguard | charging handle, right rear, 0.35 back | 1.0, 1.0 |
| Shotgun | (0.32, 0.25, -0.9) | pump | port under the receiver per shell; the pump travels 0.5 after a shot and after an empty reload | 1.3, 1.5 |

Reload keyframes come from `WeaponsConfig` (`magazineReload`, `shellReload`) so the
gesture seats the magazine at the same instant the server counts the rounds.

## Budgets

Update bands by distance from the camera: desktop full to 60 studs, every second frame
to 150, every fourth to 300, none beyond, IK on to 150, at most 6 rigs a frame; mobile
40 / 100 / 200, IK to 100, 4 a frame. Per rig per update about thirty CFrame products,
three `Transform` writes, two attachment writes and two IK weight writes; nothing
allocated per frame. Aim traffic with a full squad is under 1.5 KB/s per client.

## Decisions

- **Weapon-first hands.** Both hands are IK-driven from a per-class hold frame; no arm
  joint is posed by hand. The hold frame is a handful of numbers per class, which is
  what can be tuned in the yard without authoring poses blind.
- **An unreliable remote for the aim, not an attribute.** Twenty writes a second per
  player is exactly what `UnreliableRemoteEvent` is documented for; a lost packet is
  replaced 50 ms later, and the relay validates and rate-limits in one place. Attributes
  are reliable, ordered and stored on the instance, and a benchmark on the DevForum
  measured per-frame `SetAttribute` costing frames.
- **Pitch 35 / 25 / 40 over waist, neck and arms, yaw 55 / 45 over waist and neck,
  clamps 70 and 60.** Inside the ranges the references use (Unreal clamps its aim offset
  to 90, ALS splits the yaw evenly over four torso bones, the Unity guidance stacks
  three constraints at 0.3 / 0.4 / 0.3); the sweep station is where they get retuned.
- **Recoil reuses `WeaponsConfig`'s kick, snap, stiffness and damping** with one factor
  per class, so the third-person kick and the viewmodel's cannot drift apart. The spring
  is stepped in closed form, so any frame time lands on the exact curve.
- **Procedural gestures, not clips.** A timing change in `WeaponsConfig` moves the
  gesture with it; a clip would need re-timing. Clips remain an option (Quaternius, CC0)
  for later polish.

## Open

- Every hold, socket and share is a starting value: the gallery (test plan items 1
  and 2) is where they get tuned.
- A `Pole` per elbow is not set; add one if an elbow bends the wrong way in the yard.
- Strafe clips are still id 0, so the gallery's strafe station shows the run clip with
  a yaw twist.
