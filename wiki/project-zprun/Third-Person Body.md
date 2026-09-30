# Third-Person Body

The visible soldier: how teammates (and the local player in the yard's third-person
view, key V) hold the weapon, aim, kick, reload, draw and sprint on top of the
locomotion that already runs. Built on its own branch on 2026-09-29 and brought in on
2026-09-30; the full design, research and Studio test plan are in
`docs/animation/third-person-body.md`.

## Status (2026-09-30): on

`ThirdPersonConfig.ENABLED` is true. What it took, in the order the yard showed it:

- **Motor6D joints.** The avatars Studio built had kinematic `AnimationConstraint`
  joints (the avatar joint upgrade) and no `Motor6D`, so the waist and neck writes found
  nothing. The place now has `StarterPlayer.AvatarJointUpgrade = Disabled`: set by hand
  in Studio and saved, and in `default.project.json` for `rojo build` (the Rojo plugin
  cannot write the property on a live sync). A character in Play has fifteen `Motor6D`s.
- **`FuzzyEq` on the joint read-back.** `Motor6D.Transform` does not read back
  bit-exact, so the rig's "did the animator rewrite this joint" check (an exact `==`)
  stacked the twist every frame on a joint no track drives. It compares with `FuzzyEq`
  (1e-4).
- **The mannequins fold over.** They are clones of the local character, and the clone
  carried `FootPlanting`'s two foot `IKControl`s (chain root `LowerTorso`, targets on the
  real character, weight 0). With the body layer's arm IK on and no animator track
  rewriting the joints each frame, the combined solve turned `Root` and the hips a little
  every frame until the body lay folded. The yard drops every `IKControl` (and the body
  layer's own target attachments) from the clone and stops the clone's state machine;
  with that, a reset mannequin stays upright.
- **The run clip's lean tipped the gun at the ground.** The run clip leans the chest
  about 37 degrees forward (`Root` about -24, `Waist` about -14), and the hold frame was
  in `UpperTorso` space, so every running teammate pointed the gun down. The chest, the
  head and the gun are now aimed from the root's upright frame, worked out down the
  joint chain for the frame's pose (see the layer stack): measured in the gallery, a
  running mannequin's chest leans 15 degrees, its head and gun are level.
- **The gun was not in the hands.** `WorldWeaponModel.HAND_OFFSET` put the grip part 0.9
  studs past the right hand, so with the hands on the IK targets the right hand held the
  underside of the stock and the grip floated ahead of it, and the rifle's handguard
  ended 2.8 studs ahead of the chest while the default R15 arm reaches 1.8 from the
  shoulder joint. The grip now sits in the fist (0.3 past the hand), the long guns are
  shorter (`WorldWeaponModel` `LENGTHS`: the old rifle was 83 % of the avatar's height),
  the holds keep the gun in front of the chest's middle, and a hand target past its
  arm's reach slides back along the gun (the gun itself for the right hand, the support
  socket for the left, never closer than 0.3 to the right hand), so both hands land on
  the gun on any avatar. Measured on the default R15: every station within 0.07 studs of
  its targets.
- The station stood among the props at real size; it moved to `SandboxOrigin + (80, 0,
  -300)`, clear ground.

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

1. Locomotion: the weapon class's gait set (idle, walk, run, sprint, strafes) from
   [[Third-Person Locomotion]], or the `Run` / `Strafe` tracks while its slots are empty,
   plus `Stumble` / `Death`, `BodyMotionController`'s lean (local, `C0`), `FootPlanting`
   (local, hub).
2. Aim: the rig works out this frame's `LowerTorso` and `UpperTorso` in world space
   from the root and the joints (`C0 * Transform * C1^-1`), and the root's rotation is
   the upright frame. `Waist.Transform` turns the chest to 35 % of the pitch and 55 % of
   the yaw over that frame, keeping 40 % of the clip's lean while a gun is held
   (`chestStabilize` 0.6, scaled by the IK weight); `Neck.Transform` puts the head on the
   whole aim with 10 % of the clip's motion left (`headStabilize` 0.9). Both are
   multiplied onto the animator's pose, and a joint the animator did not rewrite starts
   from the same base instead of stacking.
3. Weapon frame: the class's `hold` (the grip part in `UpperTorso` space when upright),
   lowered for the draw and the sprint, placed from the point between the shoulders
   along the whole aim over the upright frame (half the pitch in a sprint), kicked by
   the recoil springs, then taken into `UpperTorso` space for the hand targets.
4. Gestures: the reload, pump, draw and cancel timelines move the support hand between
   the gun's sockets and the belt.
5. Hands: `IKControl` (`Transform`) on `RightUpperArm -> RightHand` to `hold *
   GripSocket` and on `LeftUpperArm -> LeftHand` to the gesture pose, both targets
   attachments on the `UpperTorso`. The welded `WorldWeapon` follows the right hand.
   Weights fade out when the character dies, drops the weapon or is beyond the IK
   range, and `Enabled` goes false at zero. Before the targets are written both are
   brought inside their arm's reach (95 % of the straight arm, read from the joints each
   update): the gun slides back along its axis for the right hand (at most 1 stud), the
   support target slides back along the gun for the left.

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
| Pistol | (0.15, 0.45, -1.35) | cupping the grip | slide: the weapon itself pulls back 0.12 | 0.6, 1.2 |
| SMG | (0.1, 0.35, -1.1) | receiver front, (0, 0.25, -0.8) | top bolt, 0.3 back | 0.8, 0.9 |
| Rifle | (0, 0.35, -0.95) | handguard rear, (0, 0.3, -1.45); on the default R15 it lands on the receiver | charging handle, right rear, 0.35 back | 1.0, 1.0 |
| Shotgun | (0, 0.35, -0.95) | pump, (0, 0.3, -1.55) | port under the receiver per shell; the pump travels 0.5 after a shot and after an empty reload | 1.3, 1.5 |

The gun model (`WorldWeaponModel`): grip part in the fist, 0.3 past the right hand;
receiver 1.6 long on the rifle and the shotgun, 1.2 on the SMG, 0.9 on the pistol;
barrel 1.1, 1.3, 0.5 and 0.4; stock 0.6, 0.65 and 0.5 (none on the pistol).

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
- **The chest takes 35 % of the pitch and 55 % of the yaw, the head and the gun the
  whole aim, clamps 70 and 60.** The first version split the pitch 35 / 25 / 40 over
  waist, neck and arms as if they were one chain, but the head and the arms both hang
  off the chest, so the head ended on 60 % of the aim and the gun on 75 %. Aiming them
  from the upright frame puts both on the aim whatever the chest and the clip do.
- **Aim from the root's upright frame, not from the torso.** The run clip every
  teammate plays leans the chest far forward; a hold in torso space follows the lean.
  The rig takes 60 % of the lean out of the chest while a gun is held and aims the head
  and the gun from the upright frame (2026-09-30).
- **Recoil reuses `WeaponsConfig`'s kick, snap, stiffness and damping** with one factor
  per class, so the third-person kick and the viewmodel's cannot drift apart. The spring
  is stepped in closed form, so any frame time lands on the exact curve.
- **Procedural gestures, not clips.** A timing change in `WeaponsConfig` moves the
  gesture with it; a clip would need re-timing. Clips remain an option (Quaternius, CC0)
  for later polish.

## Open

- Run the rest of the test plan: the reload, pump, sprint and equip stations, and V on
  the local character (`FootPlanting`'s foot IK is on it in the yard).
- `AnimationConstraint` rigs are not supported: the place keeps the joint upgrade off.
- A `Pole` per elbow is not set; add one if an elbow bends the wrong way in the yard.
- Strafe clips are still id 0, so the gallery's strafe station shows the run clip with
  a yaw twist.
