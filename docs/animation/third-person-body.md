# Third-person body: weapon handling, aim and gestures on the visible soldier

Written 2026-09-29. Stage 3a of the character work: teammates
(and the local player in the test yard's third-person view, key V) hold the weapon with
both hands per class, aim where the player aims, kick on fire, gesture through reloads
and equips, and lower the gun in a sprint, all layered over the locomotion that already
runs. This document is the design, the research it rests on, the budgets, and the
Studio test plan the owner runs in the yard.

References for the look: Call of Duty: Modern Warfare (2019) and later, Battlefield, Hunt:
Showdown; on Roblox, Blackhawk Rescue Mission 5 and Frontlines.

**Status 2026-09-30: on** (`ThirdPersonConfig.ENABLED = true`), holds being tuned. The
place keeps `StarterPlayer.AvatarJointUpgrade = Disabled` so characters have the
`Motor6D`s this design writes; the aim is now taken from the root's upright frame
instead of the torso (the run clip leans the chest about 37 degrees), which replaces the
aim spread in section 3.1 below; see the vault page Third-Person Body for the findings.

## 1. What exists today

Every place the third-person body is touched, before this work:

| Piece | File | What it does | Runs on |
| --- | --- | --- | --- |
| World weapon | `src/server/systems/WorldWeapon.luau` | Welds a five-part gun (grip, receiver, barrel, stock and handguard for long guns, magazine for SMG and rifle) to `RightHand` with one hand offset `CFrame.new(0, -0.9, -0.2) * CFrame.Angles(-80 deg, 0, 0)`, rebuilt on `WeaponId` and on `CharacterAppearanceLoaded` | server |
| Locomotion clips | `src/client/controllers/AnimationController.luau`, `src/shared/config/AnimationsConfig.luau` | `Run` (Core, looped, speed scaled to `speed / 24` in 0.8..1.45), `StrafeLeft` / `StrafeRight` (Movement, ids still 0), `Stumble` (Action), `Death` (Action4). Client-owned `Animator`, so the tracks replicate to every client | local character; replicated |
| Weapon clips | `AnimationsConfig.weaponClips` | `Fire`, `Reload`, `Equip`, `Inspect`, `Sprint` slots, all id 0 (unused since the pack viewmodels) | nowhere |
| Body lean | `src/client/controllers/BodyMotionController.luau` | `Waist.C0` (R15) or `Neck.C0` (R6) lean with speed, roll with the lateral axis, stride bob, glance impulses; `RenderStepped` after the character | local character only (`C0` replicates to the server, not `Transform`) |
| Foot IK | `src/client/controllers/FootPlanting.luau` | Two `IKControl`s (`Position`, chain `LowerTorso` to each foot) raycasting the ground, hub only, weight faded on `Stepped` | local character only |
| Glance | `src/client/controllers/GlanceController.luau` | `PlayerGlanced` remote fans out to run shove, camera, body impulse, `Stumble` clip | local |
| Camera and body hiding | `src/client/controllers/CameraController.luau` | First person: everything above the waist and the `WorldWeapon` model get `LocalTransparencyModifier = 1`; third person (`DevConfig.THIRD_PERSON_VIEW` or the `DevThirdPerson` workspace attribute from the yard's V key) hands the camera to the stock orbit controller and unhides the character | local |
| Run driver | `src/client/controllers/RunController.luau` | `Humanoid:Move` along the run direction; `Humanoid.AutoRotate` turns the root to the move direction | local |
| Skins | `src/server/systems/SkinService.luau` | `HumanoidDescription` with body colours only (no clothing, accessories or scales), applied on spawn | server |
| Weapon state | `src/server/systems/WeaponService.luau` | Player attributes `WeaponId`, `AmmoMag`, `AmmoReserve`, `Reloading`, `ReloadScale`; reload jobs on the `WeaponsConfig` timeline | server, replicated to all |
| Fire to other clients | `WeaponService.onFire` -> `Remotes.Event.WeaponHit` `FireAllClients("Shot", origin, hits, player, weaponId)` | already reaches every client with the shooter and the weapon; `WeaponController.onWeaponHit` draws tracers and impacts from it | all clients |
| Reload to other clients | the `Reloading` attribute flips true at the start and false at the end (or cancel); `AmmoMag` ticks per shell | already reaches every client | all clients |
| Equip to other clients | the `WeaponId` attribute; `WorldWeapon` rebuilds on it | already reaches every client | all clients |
| Zombie cross-fades | `src/server/systems/ZombieAnimator.luau` | tracks per priority (`Core` base idle, `Idle`, `Movement` walk/run, `Action` attack, `Action4` death), `Play(fade)` and `AdjustSpeed`; `Transform` only for the hit boxes | server |
| Death | `src/server/systems/DeathService.luau`, `src/client/controllers/DeathController.luau`, `DeathGore.luau` | anchors the root, plays the `Death` clip (Action4) through `AnimationController.playOneShot`, runs the death camera, gore and results; no joint writes | server and local |
| Squad | `src/server/systems/SquadService.luau`, `HangarConfig.SQUAD_CAPACITY = 3` | at most two teammates to draw | server |
| Test yard | `src/server/systems/Sandbox.luau`, `SandboxInput.luau` (V third person) | free area for a body gallery: relative to `SandboxOrigin`, x 60..250 and z -265..-415 is empty (the first pick, z -150..-300, runs into the props at real size; weapon gallery at (-140, 40) toward -X and -Z, zombie gallery at (110, 40) toward +X to z -44, material walls at z -150 x -150..-50, props at (-330, -210) toward +X, sound lane at x 300) | Studio |

What is missing: nothing points the weapon where the player looks, the left hand hangs
free, fire and reload are invisible on a teammate, equips snap, and the weapon offset
is the same for a pistol and a rifle.

## 2. Research

### 2.1 The Roblox API in 2026

Read from the class reference source in `Roblox/creator-docs` (branch `main`,
`content/en-us/reference/engine/classes/*.yaml`, 2026-09-29) and cross-checked against
the `@rbxts/types` 1.0.955 typings (generated from the API dump, 2026-09-25); the
verification method is in section 2.3.

**`IKControl`** (parent: a `Humanoid` or an `AnimationController` with an `Animator`).
`Type` (`IKControlType`: `Transform` "full 6-DoF", `Position`, `Rotation`, `LookAt`),
`ChainRoot` ("must be a `BasePart` or `Bone` ancestor of `EndEffector`"), `EndEffector`
(a `BasePart`, `Motor6D`, `Bone` or `Attachment` whose pivot moves to the target),
`Target` ("anything that has a position in the world"), `Pole` (optional bend direction;
"auto-detects Arm or Leg when unset for standard limbs"), `Weight` (0..1, blends with the
underlying animation), `SmoothTime` ("critically-damped spring", default 0.05 s, 0
disables), `Priority` (integer; higher solves later and can override), `Offset` and
`EndEffectorOffset` (`CFrame`), `Enabled`; `GetChainLength`, `GetChainCount`,
`GetNodeWorldCFrame`, `GetRawFinalTarget`, `GetSmoothedFinalTarget`. "IKControl will
override the animation for all the parts between the ChainRoot and the EndEffector";
`Workspace.IKControlConstraintSupport` (not scriptable, default enabled) makes it honour
`HingeConstraint` and `BallSocketConstraint` limits, and the IK guide
(`content/en-us/animation/inverse-kinematics.md`) recommends a hinge at the elbow and a
ball socket of about 80 degrees at the wrist for realistic arms.

**Animator layering.** `AnimationTrack.Priority` (`Core` 1000 lowest, `Idle`,
`Movement`, `Action`, `Action2`, `Action3`, `Action4` highest): "where two playing
animations direct the target to move the same limb in different ways, the AnimationTrack
with the highest priority will show"; equal priorities blend by `WeightCurrent`
("weighted average of all the Poses"). `Play(fadeTime, weight, speed)`, `Stop(fadeTime)`,
`AdjustWeight(weight, fadeTime)`, `AdjustSpeed`, `GetMarkerReachedSignal`,
`GetTimeOfKeyframe`, `Length` (0 until loaded), `TimePosition`, `Looped`, `Ended`,
`Stopped`, `DidLoop`. `Animator.PreferLodEnabled` (default true) lets the engine throttle
evaluation by distance and screen coverage, `Animator.EvaluationThrottled` says whether
this frame's pose was reused, and `Workspace.ClientAnimatorThrottling` sets the mode for
remotely simulated models. Client-owned animators (the player's own character) replicate
the tracks they play; locally loaded tracks on other models do not replicate.

**`Motor6D.Transform`** (`CFrame`, hidden, not replicated): "the current animation
offset of the joint", "recommended for custom animations over C0/C1"; "when an Animator
is present, Transform gets overwritten each frame after PreAnimation", and writes land
"in batch after PreSimulation, before physics steps". So the body layer writes
`Transform` in `RunService.PreSimulation` (the frame order in the `RunService` reference:
`PreRender`, `PreAnimation`, `PreSimulation`, physics, `PostSimulation`, `Heartbeat`),
multiplying what the animator left there, which is the project's existing convention
("`Motor6D.Transform` written in `RunService.Stepped` lands on top of the `Animator`
pass", asset policy rule 2). `Stepped` and `RenderStepped` are documented as superseded
by `PreSimulation` and `PreRender`.

**`Bone`** (`Transform`, `TransformedCFrame`, `TransformedWorldCFrame`) is the skinned
counterpart; the player characters are R15 `Motor6D` rigs, so it is not used here.

**`UnreliableRemoteEvent`** (`FireServer`, `FireClient`, `FireAllClients`,
`OnServerEvent`, `OnClientEvent`): payload at most 1000 bytes, delivery and order not
guaranteed ("to maintain optimal engine performance"), recommended for "continuously
changing data" and "ephemeral events with short-term relevance"; rate limit about 500
requests per second per client shared with reliable remotes.

**Newer things checked and not used:** `AnimationTrack.SetParameter` /
`GetParameter` (animation parameters), `Animator.RegisterEvaluationParallelCallback`,
`Workspace.Retargeting` (`AnimatorRetargetingMode`); none replaces procedural IK plus
springs for this work. `Players:CreateHumanoidModelFromDescriptionAsync` exists (the
non-async form is deprecated) but is not needed: the yard clones the local character.

### 2.2 How shooters handle the third-person weapon

Read on 2026-09-29; the publishers' documentation sites (Epic, Unity, Valve wiki, GDC
Vault) are blocked from this workstation, so those facts come from search excerpts and
are marked "(excerpt)"; everything marked "(source)" was read in full from GitHub.

**Aim offsets.** Unreal's aim offset is a blend space of additive poses with yaw and
pitch axes clamped to -90..90 before they feed it, and for third person "spine 1, 2 and 3
are the bones modified so the skeleton faces where the player aims" (excerpt,
`https://dev.epicgames.com/documentation/en-us/unreal-engine/aim-offset-in-unreal-engine`).
Lyra layers the additive from Spine1 up to the arms with per-bone weights climbing to 1,
clamps because large offsets "over twist the spine", and keeps the feet planted with a
root yaw offset until a turn-in-place plays (excerpt,
`https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-in-lyra-sample-game-in-unreal-engine`).
The open-source ALS-Community controller is the one production-grade reference with
numbers (source, `https://github.com/dyanikoglu/ALS-Community`,
`Source/ALSV4_CPP/Private/Character/Animation/ALSCharacterAnimInstance.cpp` and
`Public/Library/ALSAnimationStructLibrary.h`): aim yaw split evenly over four pelvis
and spine bones (`SpineRotation.Yaw = AimingAngle.X / 4`), pitch as a sweep over -90..90,
`SmoothedAimingRotationInterpSpeed = 10`, turn-in-place from 45 degrees of torso offset
(`TurnCheckMinAngle`), the 180 clip past 130, no turn while the aim yaw rate exceeds 50
deg/s, and the body clamped within 100 degrees of the camera when stationary. Unity's
Animation Rigging multi-aim constraint stacks on chest, spine1 and spine with weights
about 0.3 / 0.4 / 0.3 and 45..60 degree limits per bone "to avoid owl neck" (excerpt,
`https://mocaponline.com/blogs/mocap-news/unity-animation-rigging-guide`; constraint
reference, source, `https://github.com/needle-mirror/com.unity.animation.rigging`,
`Documentation~/constraints/MultiAimConstraint.md`). DICE's approach is described as
additive aim poses that recruit spine, shoulders and arms rather than pure spine
rotation (excerpt, `https://gamedev.net/forums/topic/655859-rotate-character-spine-so-weapon-aims-at-target/`).
No published pitch split exists for MW2019 beyond its "Active Idle" marketing.

**Hand IK to weapon sockets.** Lyra attaches the arms to the weapon with two-bone IK
nodes and corrects the left arm's over-extension with a hand IK retargeting node
(excerpt, Lyra page above and
`https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-blueprint-hand-ik-retargeting-in-unreal-engine`).
On the Epic mannequin the weapon lives on an `ik_hand_gun` helper and both hands follow
it, the "weapon-first" rig: attaching to the hand bone "looks right in the viewport but
wrong once weapon sets play" (excerpt, `https://cosindra.ai/guides/ue5-manny-skeleton`).
Unity's two-bone IK has a target, an optional hint for the bend direction and separate
position, rotation and hint weights (source, same repository,
`Documentation~/constraints/TwoBoneIKConstraint.md`). IK is switched off for sprint and
reload through a per-constraint weight driven by an animation curve (ALS `Enable_FootIK`
curves, source above), which on Roblox is `IKControl.Weight`; the reference notes that
weight 0 still lets `SmoothTime` and `Pole` act, so `Enabled = false` is the full stop.

**Recoil.** Valve's Source engine models the view punch as a damped spring with
`PUNCH_SPRING_CONSTANT 65` and `PUNCH_DAMPING 9`, pitch clamped to 89 degrees (source,
`https://github.com/ValveSoftware/source-sdk-2013`, `src/game/shared/gamemovement.cpp`);
CS separates the aim punch (the flinch when hit) from the view punch (your own recoil)
(excerpt, `https://totalcsgo.com/commands/weaponrecoilviewpunchextra`). CryEngine's
procedural weapon animation is "a car suspension": a spring toward neutral with a damper,
plus additive layers for sway, idle and sprint (excerpt,
`https://docs.cryengine.com/display/SDKDOC2/Procedural+Weapon+Animations`). Quenty's
Roblox spring module and Ryan Juckett's reference use the same damping-ratio regimes
(source, `https://github.com/Quenty/NevermoreEngine`, `src/spring/src/Shared/Spring.lua`;
excerpt, `https://www.ryanjuckett.com/damped-springs/`). No source publishes per-class
third-person kick magnitudes; this project already tunes them per weapon in
`WeaponsConfig` (`recoilKick`, `recoilSnap`, `recoilStiffness`, `recoilDamping`).

**Aim over the network.** Unreal replicates `APawn::RemoteViewPitch` as one byte
(`CompressAxisToByte`, 1.41 degree steps) with the actor (excerpt,
`https://dev.to/roasted-kaju/pitch-replication-and-axis-compression-in-unreal-engine-285k`);
ALS replicates the control rotation with `COND_SkipOwner` and remote clients interpolate
it with `RInterpTo(..., 30)` (source, `Source/ALSV4_CPP/Private/Character/ALSBaseCharacter.cpp`).
Overwatch clients received updates at 20.8 Hz before the 62.5 Hz upgrade (excerpt,
`https://nelsonslog.wordpress.com/2017/01/10/overwatch-netcode/`); Halo Reach's minimum
packet rate was 10 Hz (excerpt,
`https://edgegap.com/blog/game-backend-deep-dive-halo-reach-netcode-host-migration`).
Roblox replicates physics at 20 Hz (excerpt,
`https://devforum.roblox.com/t/in-depth-information-about-robloxs-remoteevents-instance-replication-and-physics-replication-w-sources/1847340`);
`Motor6D.Transform` does not replicate, so the community pattern is a remote every few
frames with the receiver lerping (excerpt,
`https://devforum.roblox.com/t/what-is-the-most-effective-way-to-replicate-motor6dtransform/2156012`);
a benchmark found two per-frame `SetAttribute` calls costing 23 fps (excerpt,
`https://devforum.roblox.com/t/why-storing-constantly-changing-data-on-parts-using-attributes-is-a-bad-idea/2617565`);
the measured `UnreliableRemoteEvent` cap is 908 bytes (excerpt,
`https://devforum.roblox.com/t/incorrect-size-of-data-being-sent-limit-specified-when-using-unreliableremoteevent/3048788`).

**LOD.** Unreal's update-rate optimisation evaluates animation every Nth tick by screen
size and interpolates the skipped frames (excerpt,
`https://docs.unrealengine.com/4.27/en-US/AnimatingObjects/SkeletalMeshAnimation/Optimization`);
Unity's `CullUpdateTransforms` skips bones, IK and `OnAnimatorIK` when the renderer is
invisible (excerpt, `https://docs.unity3d.com/ScriptReference/AnimatorCullingMode.html`).
Roblox throttles remotely simulated animators by distance, screen coverage and frame
budget (`Animator.PreferLodEnabled`, on by default since 2022) and exposes
`Animator.EvaluationThrottled` so procedural layers can skip the frames whose pose was
reused (source, `Animator.yaml` in `Roblox/creator-docs`). None publishes distance
bands. Blackhawk Rescue Mission 5's wiki notes its IK rigs were reworked to affect only
the local character and that third-person bullets go from the muzzle to the screen
centre (excerpt, `https://roblox-blackhawk-rescue-mission-5.fandom.com/wiki/Generations_and_Operations`);
Phantom Forces and Frontlines publish nothing on their arms.

**What this design takes from it.** Weapon-first hands on two IK chains; the aim as an
additive twist spread over the torso joints with clamps well inside the reference
ranges; ALS's smoothing speed (a 0.08 s time constant is speed 12.5); a critically
damped spring per weapon for the kick; one-degree quantised pitch and yaw at 20 Hz on an
unreliable remote with interpolation on the receiver; and `EvaluationThrottled` plus
distance bands for the LOD.

### 2.3 API verification

`tools/validate_api.py` downloads the dump from `raw.githubusercontent.com`, which this
workstation's network policy denies, so the check ran against a dump-shaped JSON built
from `@rbxts/types` 1.0.955 (the roblox-ts typings generated from the same dump), and
every class, property, method and enum below was also read in the official reference
YAML. Run the validator with the real dump before merging. Members used, present in both:

| Class | Members |
| --- | --- |
| `IKControl` | `Type`, `ChainRoot`, `EndEffector`, `Target`, `Weight`, `SmoothTime`, `Priority`, `Enabled` |
| `Motor6D` | `Transform`, `Part0`, `Part1`, `C0` (read) |
| `Attachment` | `CFrame`, `WorldCFrame`, `WorldPosition`, `Parent` |
| `AnimationTrack` | `Play`, `Stop`, `AdjustSpeed`, `AdjustWeight`, `Priority`, `Looped`, `IsPlaying` |
| `Animator` | `LoadAnimation` |
| `Humanoid` | `Health`, `RigType`, `RootPart`, `WalkSpeed` (yard only) |
| `UnreliableRemoteEvent` | `FireServer`, `FireAllClients`, `OnServerEvent`, `OnClientEvent` |
| `RunService` | `PreSimulation`, `Heartbeat`, `IsStudio` |
| `Model` | `PivotTo`, `GetPivot`, `Archivable`, `Clone` (yard) |
| `BasePart` | `CFrame`, `Position`, `AssemblyLinearVelocity`, `Anchored`, `CanCollide`, `CanQuery`, `CanTouch`, `Massless`, `Size`, `Color`, `Material` |
| `Weld` | `Part0`, `Part1`, `C0` |
| Enums | `IKControlType.Transform`, `HumanoidRigType.R15`, `AnimationPriority.Core`, `RaycastFilterType.Exclude` |

## 3. Design

### 3.1 Layer stack

Per character, on every client, in `RunService.PreSimulation` after the animator has
written its pose (skipped on frames where `Animator.EvaluationThrottled` says the pose
was reused, so the layer never multiplies a stale offset twice):

```
1  Locomotion      Animator tracks (Run, Strafe, Stumble, Death), BodyMotionController lean
                   (local only), FootPlanting (local, hub)              -- unchanged
2  Aim spread      Waist.Transform  *= yaw 0.55 * twist, pitch 0.35 * aim
                   Neck.Transform   *= yaw 0.45 * twist, pitch 0.25 * aim  -- the head looks
3  Weapon hold     a per-class hold frame in UpperTorso space, pitched by the remaining
                   0.40 of the aim about a pivot between the shoulders, lowered in sprint
4  Recoil          a spring (kick back, pitch up) added to the hold frame, a smaller
                   pitch impulse into the waist
5  Gestures        reload, equip, pump and sprint move the hold frame and the support
                   hand target on a timeline from WeaponsConfig
6  Hands           two IKControls (Transform): RightHand to hold * gripSocket^-1,
                   LeftHand to hold * supportSocket, both targets attachments on the
                   UpperTorso; the welded WorldWeapon follows the right hand
```

The weapon leads and the hands follow ("weapon-first"): the code decides where the gun
is, both IK chains resolve the arms, and nothing in the arm joints is hand-authored. The
run clip keeps the legs, the hips and the torso; the aim layer twists the torso on top
of its lean; the arm chains are owned by IK while a weapon is held, and the IK weights
fade to zero when the character dies, has no weapon, or is far enough for the LOD to
drop them (then the run clip's arm swing shows again).

### 3.2 Modules

| Module | Owns |
| --- | --- |
| `src/shared/config/ThirdPersonConfig.luau` | data: per-class hold frames and sockets, aim spread and clamps, smoothing, recoil scale, sprint pose, gesture keyframes, replication rate and quantisation, LOD bands and budgets |
| `src/shared/util/WorldWeaponModel.luau` | the gun model builder moved out of `WorldWeapon` so the yard can build one on the client; adds `GripSocket`, `SupportSocket`, `MagazineSocket`, `PumpSocket`, `ChargeSocket` and `Muzzle` attachments per class |
| `src/server/systems/WorldWeapon.luau` | calls the shared builder; otherwise unchanged |
| `src/shared/util/BodyMath.luau` | pure math, no Roblox services: aim smoothing, pitch and yaw spread with clamps, recoil spring, the reload and equip timelines from `WeaponsConfig` numbers, sprint blend, LOD cadence, quantisation for the wire; tested by `luau tests/body/run.luau` |
| `src/client/body/BodyRig.luau` | one character: binds the R15 joints, creates the two IKControls and the two target attachments, reads the weapon sockets, holds the state (aim, speed, sprint, gesture, recoil) and writes joints and targets in `update(dt)` |
| `src/client/body/BodyController.luau` | finds every other player's character (and the local one when the third-person view is on), feeds each rig from the `WeaponId` / `Reloading` / `AmmoMag` / `ReloadScale` attributes, the `WeaponHit` shots and the aim packets, schedules updates by LOD, runs the `PreSimulation` loop |
| `src/client/body/AimReplicator.luau` | the local player's aim pitch and yaw offset onto the wire at most 20 times a second |
| `src/server/systems/BodyAimRelay.luau` | validates, rate-limits and relays the aim packets |
| `src/client/systems/SandboxBodyGallery.luau` | the yard station (section 6) |
| `src/shared/net/Remotes.luau` | `Remotes.Unreliable.BodyAim` and `getUnreliableEvent` |

### 3.3 Aim replication

The owner's client samples the camera each frame: `pitch` = the camera look vector's
elevation, `yawOffset` = the signed angle between the root's flat look vector and the
camera's flat look vector. Both are quantised to whole degrees and sent through
`Remotes.Unreliable.BodyAim` (`UnreliableRemoteEvent:FireServer(pitch, yaw)`) when
either changed by a degree since the last send and at least 50 ms passed, plus a
keepalive every second. `BodyAimRelay` checks both are numbers, clamps pitch to -89..89
and yaw to -179..179, drops anything under 45 ms from the same player, and
`FireAllClients(player, pitch, yaw)`. The receiving `BodyController` ignores its own
player, stores the target, and the rig approaches it with a 0.08 s time constant (five
updates of lag at 20 Hz read as continuous). A late joiner has a rig at pitch 0 for at
most one second.

Why an unreliable remote and not an attribute: an attribute write is reliable and
ordered, replicates to every client on every change and is stored on the instance;
twenty writes a second per player is exactly the traffic the docs steer to
`UnreliableRemoteEvent` ("continuously changing data", "ephemeral"), a lost packet is
replaced 50 ms later, and the relay can rate-limit and validate in one place. Bandwidth
per client with a full squad: 2 senders x 20 Hz x about 30 bytes, under 1.5 KB/s.

Fire, reload and equip need nothing new on the wire: `WeaponHit` "Shot" already carries
the shooter and weapon, `Reloading` and `AmmoMag` already replicate, `WeaponId` already
rebuilds the weapon. The rig reads `AmmoMag == 0` at reload start for the empty variant
and `min(magSize - AmmoMag, AmmoReserve)` for the shell count.

### 3.4 Per-class parameters

Studs, degrees, seconds. The hold frame is the grip socket's CFrame in `UpperTorso`
space at aim pitch 0 (position, then pitch / yaw / roll); the support socket is where the
left hand goes, in the weapon's grip frame (x right, y up, -z forward along the barrel).
Recoil uses the weapon's own `recoilKick` (studs back) and `recoilSnap` (degrees up) from
`WeaponsConfig` times the class factor here; the spring is `recoilStiffness` /
`recoilDamping` from the same entry.

| Class | Hold position | Hold angles | Support socket | Recoil factor (kick, snap) | Sprint | Reload gesture |
| --- | --- | --- | --- | --- | --- | --- |
| Pistol | (0.35, 0.55, -1.15) | (0, 0, 0) | grip front, both hands on the grip: (-0.18, -0.25, 0.12) rot (0, 0, 40) | 0.6, 1.2 | held low across the chest, pitched down 35 | magazine: left hand to belt (0.55 s), to the mag well at ammo-add - 0.2, seat at ammo-add; empty adds the slide release: right thumb, a 0.2 s pull-back of the hold frame |
| SMG | (0.30, 0.45, -0.95) | (0, -4, 0) | front of the receiver: (0, 0.35, -0.85) | 0.8, 0.9 | pitched down 40, pulled 0.2 in | magazine; empty adds the bolt: left hand to the charge socket (top rear), pull 0.18 s, release 0.1 s |
| Rifle | (0.28, 0.40, -0.90) | (0, -6, 0) | handguard: (0, 0.45, -1.55) | 1.0, 1.0 | pitched down 45, pulled 0.25 in, rolled 10 | magazine; empty adds the charging handle rack (right side): left hand crosses to the charge socket |
| Shotgun | (0.28, 0.40, -0.90) | (0, -6, 0) | pump: (0, 0.40, -1.35), travels 0.35 back on the stroke | 1.3, 1.5 | as rifle | shells: left hand to belt then to the loading port under the receiver per shell (`shellReload.perShell`, seat at `addAt`), the pump stroke after the last shell when the reload started empty (`chamber`), and after every shot (`ejectOnFire = false`) |

Aim: pitch clamp -70..+70, yaw twist clamp +-60 (beyond it the torso holds the limit
until the feet turn), spread waist 0.35 / neck 0.25 / arms 0.40 of the pitch and waist
0.55 / neck 0.45 of the yaw. Equip: the hold frame rises from 0.6 studs down and 50
degrees pitched down over `drawTime`, IK weight from 0.3 to 1. Sprint: speed at or over
36 studs/s (the run's `BASE_RUN_SPEED` is 24, `MAX_RUN_SPEED` 60) blends the sprint pose
in over 0.25 s and halves the arm pitch share.

### 3.5 Budgets

| Item | Desktop | Mobile |
| --- | --- | --- |
| Rigs updated per frame | all within 60 studs, every 2nd frame to 150, every 4th to 300, none beyond | full to 40, every 2nd to 100, every 4th to 200 |
| IK weights | on to 150 studs, faded to 0 beyond (arms back to the clip) | on to 100 |
| Updates per frame cap | 6 rigs | 4 rigs |
| Aim packets sent | 20 Hz, 1 s keepalive | same |
| Per rig per update | about 30 CFrame multiplies, 3 `Transform` writes, 2 attachment `CFrame` writes, 2 IK weight writes | same |

A full squad is two remote rigs plus the local one in the yard's third-person view; the
gallery adds up to 44 mannequins, so the cap and the bands matter there. No tables are
created per frame: the rig state, the timelines and the springs are allocated at bind.

### 3.6 First person stays the same

`BodyController` never binds the local character unless the third-person view is on
(`DevConfig.THIRD_PERSON_VIEW` or the `DevThirdPerson` workspace attribute, both Studio
only). `CameraController`, `Viewmodel`, `BodyMotionController` and `FootPlanting` are not
changed; the only edits outside new files are `WorldWeapon.luau` (builder moved, sockets
added), `Remotes.luau` (the unreliable event) and `init.server.luau` (the relay stage).
`init.client.luau` calls `BodyController.init()` after `WeaponController.init()`, and
`SandboxInput.init()` calls `SandboxBodyGallery.init()`.

### 3.7 Death

A rig stops writing when its humanoid's health reaches zero: the IK weights fade to zero
in 0.15 s and the `Transform` writes stop, so the `Death` clip at Action4 and the corpse
pose from `DeathService` are untouched; `DeathGore` and `DeathController` read positions
only. On respawn the character model is new and the rig is rebound.

## 4. Assets

None required: the whole layer is procedural (IK plus springs plus timelines). Optional polish clips that would improve it later, for the owner
to upload through `assets/manifest.json` if wanted (CC0 / CC BY only): Quaternius
Universal Animation Library (CC0, `https://quaternius.com/packs/universalanimationlibrary.html`,
already used for the death and stumble clips) has rifle idle, aim and reload clips that
could replace the procedural reload gesture; Mixamo clips are royalty-free for games per
its FAQ but not CC, so they stay out of this list.

## 5. Checks

Before every commit:

```
selene src/                       # std from selene generate-roblox-std (roblox.yml is git-ignored)
python3 tools/validate_api.py
rojo build -o build.rbxlx         # ServerPackages (wally install) must exist
luau tests/body/run.luau          # pure math, standalone Luau CLI
```

## 6. Studio test plan

The yard (`DevConfig.SANDBOX.enabled = true`, `ThirdPersonConfig.ENABLED = true`).
Mannequins stand at `SandboxOrigin + (80, 0, -300)`, one row per class (Pistol, SMG, Rifle,
Shotgun, 14 studs apart toward -Z) and one column per station 9 studs apart toward +X:
idle, walk, run, strafe, sprint, aim sweep, fire burst, tactical reload, empty reload,
shells, equip. Each has a label with the station name and, where it matters, the live
timeline value. Press V for the third-person view of your own character.

1. **Grip.** Every mannequin holds its gun with both hands: right hand on the grip,
   left on the handguard (rifle), receiver front (SMG), pump (shotgun) or cupping the
   grip (pistol); no hand floats, no elbow bends backwards. Knob: the class row in
   `ThirdPersonConfig.classes` (`hold`, `support`); the overlay label prints the IK
   weights. If an elbow bends the wrong way add a `Pole` per the IK guide (a part
   behind and below the elbow).
2. **Aim sweep.** The sweep station pitches from -60 to +60 and back over 4 s: the
   torso leans, the head follows, the arms carry the rest, the gun stays in both hands
   through the sweep and the feet never move. Knob: `AIM.spread`, `AIM.pitchClamp`.
3. **Twist.** Stand in third person (V), run and look 45 degrees left: the torso
   twists before the root turns; past 60 it holds. Knob: `AIM.yawClamp`.
4. **Fire burst.** The burst station fires eight shots at each class's `fireRate`:
   the gun kicks back and up and settles without wobble; the shotgun kicks hardest,
   the SMG least; a small waist pitch is visible. Knob: `RECOIL.factor` per class,
   `recoilStiffness` / `recoilDamping` in `WeaponsConfig`.
5. **Tactical reload.** Left hand to the belt, back to the mag well, seats at the
   weapon's `ammoAddTactical`, hands back on the gun by `reloadTime`; the label counts
   the timeline. Knob: `GESTURES.magazine`.
6. **Empty reload.** As above plus the class's chambering action after the seat: pistol
   slide (a pull of the hold frame), SMG top bolt, rifle charging handle, and the total
   matches `reloadTimeEmpty`. Knob: `GESTURES.charge`.
7. **Shells.** The shotgun station loads four shells one by one (`shellReload.perShell`
   apart, each seated at `addAt`), then pumps once because it started empty; the other
   rows show "n/a". Knob: `GESTURES.shell`, `GESTURES.pump`.
8. **Equip.** The gun rises from low over the class's `drawTime`; the IK weight fades in
   with it. Knob: `EQUIP.*`.
9. **Sprint.** The sprint station runs the clip at 1.3x with the gun lowered across the
   chest and the aim share halved; walk / run stations hold the gun up. Knob: `SPRINT.*`.
10. **Teammate.** With a second client (Studio's local server, two players): the
    teammate's gun follows their aim within about 0.1 s, kicks on their shots, gestures
    through their reloads and equips, and lowers in their sprint; their own first-person
    view is unchanged. Overlay: the yard label under a real player prints the last
    packet age.
11. **LOD.** Walk 200 studs from the gallery: the far rows drop IK (arms follow the run
    clip) and update less often without popping; walk back and they rejoin smoothly.
    Knob: `LOD.*`.
12. **Death.** Let a wave kill you in third person: the death clip and camera play as
    before; respawn rebinds the rig.
13. **First person.** Turn V off: the viewmodel, camera and body hiding are exactly as
    before this work (the local rig is unbound the moment the view switches back).
14. **Frame time.** The gallery's 44 mannequins in view: the FPS counter (settings)
    holds; on the phone emulator the far rows update at the mobile bands.

## 7. Decisions made here (the owner's calls)

1. Weapon-first hands: both hands are IK-driven from a per-class hold frame instead of
   hand-authored shoulder angles, because nothing here can be eyeballed without Studio
   and the hold frame is four numbers per class.
2. Aim on an `UnreliableRemoteEvent` relayed by the server at 20 Hz, not a player
   attribute (section 3.3).
3. Pitch spread 35 / 25 / 40 across waist, neck and arms; yaw 55 / 45 across waist and
   neck; clamps 70 and 60. Starting values from the practice in section 2.2; the sweep
   station is the place to retune them.
4. Recoil reuses `WeaponsConfig`'s kick, snap, stiffness and damping with one factor per
   class, so the third-person kick and the viewmodel kick cannot drift apart.
5. Procedural gestures over clips: the reload keyframes come from the same
   `WeaponsConfig` numbers the server enforces, so a timing change moves the gesture with
   it; a clip would need re-timing.
