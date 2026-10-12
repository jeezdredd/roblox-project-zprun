# AV polish tasks

Owner: producer. Written 2026-10-12. Inputs: production/project-stage-report.md, production/claude-desktop-tasks.md (T1-T22), the producer draft and the reviewer's critique of 2026-10-12 (verdict REVISE, 31 required changes), spot checks in the repo the same day, and the verified rerun of the camera, VFX and zombie animation audits (2026-10-12).

Status: PROVISIONAL until the owner reviews the audit rerun. The rerun corrected the failed premises in the camera, VFX and zombie animation briefs, merged the confirmed gaps into the briefs they affect and added A44 to A72. What changed per brief is listed in "Audit rerun 2026-10-12" at the end. Owner calls raised by the rerun are listed there too.

Target: animation, audio and visuals at the level of Call of Duty: Modern Warfare (2019) presentation, with TTK Testing by Sable Digital as the Roblox weapon-feel benchmark. The milestone plan and exit criteria are in wiki/project-zprun/Roadmap.md; sprint 1 is production/sprints/sprint-01.md.

## Shared AV rules block (paste with every A-task, after the shared rules block from production/claude-desktop-tasks.md)

```
Asset rules: any technique is allowed (Studio MCP generate_mesh / generate_material / generate_texture, Blender MCP, licensed packs, generated audio) if the result passes a look or listen in a Studio playtest. Every asset: manifest entry with source and licence, plus "generator" and "terms" for generated assets -> scripts/upload_assets.py -> scripts/sync_configs.py -> assets/LICENSES.md. Ids only from real uploads. Nothing extracted from another game. Reference frames from MW2019 or TTK never enter the repo: cite a public video and a timestamp instead.
Line numbers: line references in older briefs predate commit 3e0ab9c (comment strip). Locate code by symbol name, never by line number.
Studio lane: only the task holding the Studio lane drives Studio MCP and rojo serve. Code lanes finish with all checks green and hand over a short verification note for the Studio lane.
Asset lane: author assets in parallel, but only one task at a time runs the ingest step (assets/manifest.json, src/shared/config/AssetIds.luau, assets/LICENSES.md, assets/NEEDED.md). Queue for it.
Viewmodel work: only in the main checkout or in a worktree made by scripts/worktree_setup.sh (A2).
Owner verdicts: every look or listen pass is recorded in its row of docs/av/vertical-slice-bar.md with the date, pass or fail, and the capture filename (or "live listen").
Captures: written under docs/av/captures/, which is gitignored. Never commit captures.
Low tier: every new VFX, light or audio voice declares its Low tier value in config next to its High value, even before A39 tunes them.
Tests: tests/<area>/run.luau runs under the standalone luau CLI with relative string requires. It has no script, Color3, Vector3, CFrame, Enum or services. Pure helpers, and any config a test reads, use plain numbers and strings. Never require ViewmodelConfig, VfxConfig, Spring or another Roblox-typed module from a test; put the tested values in a numbers-only module.
Zombie hit boxes on the client: Motor6D.Transform does not replicate, so until A63 lands every client hit box part sits at HumanoidRootPart. Client code reads bones (TransformedWorldCFrame) or the A63 mirror, never the raw Head part.
Difficulty: on Medium (default) and Hard every damaging contact kills (DifficultyConfig.grabLethal) and regen is off. Damage-amount and low-health presentation reach only Easy players; glances, grabs and the death camera carry most of the D9 value.
Run speed: a mission runs at 24..30 studs/s (BASE_RUN_SPEED plus Endurance), down to about 13 in a glance slow. No location ramps speed and there is no sprint or jump input.
```

## Measurement methods (use these wherever an accept line names them)

| Measure | Method |
| --- | --- |
| InstanceCount flat | Stats.InstanceCount sampled once per second for 30 s of sustained fire after a 10 s warm-up; max and min within 2 percent of the mean |
| Server step cost | `debug.profilebegin` label read in MicroProfiler, or an `os.clock` accumulator averaged over 600 frames; T14 picks one and every later task reuses it |
| Loudness | integrated loudness with ffmpeg loudnorm (print_format json) run from tools/audio_build; families or buses compared in LU |
| Frame-rate independence | the same motion run at 30 and 144 fps in a Luau test; amplitude within 10 percent |
| UI text size | smallest run HUD or menu text at least 24 px at 1080p in the Studio console emulator |
| Owner look or listen | verdict row in the bar document, as in the rules block |

### A41. Aim focus (D6)
```
Depends on: A44; T7a for the gamepad binding, T7b for touch.
Context: owner decision D6. The game is hip fire. Holding the aim input should read as aiming from the first-person camera without becoming full aim-down-sights. No secondary input exists in a run: WeaponController.init binds MouseButton1, R, F, 1 to 5 and the wheel; Stances binds X, Q and E; InputController binds A and D; MouseButton2 is used only by IntermissionCamera. HipAim is an auto-target: it picks a zombie in a 42 degree cone (coneDegrees 42, centreBias 0.8, fireLock 0.55) and HipAim.fireDirection steers the shot, so tightening the cone would remove aim help at the moment the player asks for precision. The Pistol and Rifle packs load G17Clips and M4Clips, which have no aim clips, so the focus is procedural. Roblox has no separate viewmodel FOV: the rig is world geometry under the camera, so every FOV change resizes the gun on screen (the run FOV sits near 79 to 82, plus per-shot kicks, the glance -2 and death +6).
Do: bind MouseButton2 through ContextActionService in WeaponController; L2 lands with T7a and a touch hold with T7b. Add ViewmodelConfig.aimFocus per class: position and rotation share toward centre with the sight line kept below screen centre, swayScale, bobScale, breathScale and driftScale; add CameraConfig.AIM_FOCUS_FOV_DELTA; blend over about 0.15 s. Keep the HipAim cone and raise centreBias while focused. Any spread change is server-validated or left out. Movement speed is unchanged. Add viewmodel FOV compensation: scale the rig's camera-space root position by lerp(1, tan(ref/2) / tan(fov/2), share) so the gun keeps its projected screen size (its angular size still changes); the function and its referenceFov and share values live in a numbers-only module, not ViewmodelConfig; check that HipAim, the muzzle and eject attachments, casings and tracers still line up when the muzzle moves. Add the matching foley (cloth and grip shuffle) through the audio engine.
Accept: in a capture the hip pose and the aim focus pose differ clearly but the sights never align with the screen centre; FOV change and blend times match config; the projected screen size test keeps the grip in the same screen box within 3 percent at FOV 70 and 82; release returns smoothly; selene, validate_api, comment check and rojo build pass.
```

### A42. Reloads by ammo state (D8)
```
Context: owner decision D8. Today a weapon has a tactical and an empty reload. The owner wants three states with their own animation and timing: empty (bolt or slide locked back), partly spent, and almost full (a quick top-off).
Do: define the states in WeaponsConfig per class with thresholds (for example empty at 0, almost full at 75 percent or more of the magazine left), select the clip and the server reload timing from the state, and make sure the server's ammo add time matches each clip's marker. For the shotgun the states map to shell count (single shell loads versus a longer loop). Author or retarget the missing clips through the animation pipeline with the asset policy gate. Add matching foley per state. Pass the state as the reload tag on Viewmodel.onPhase so the A49 camera handling table can key on it.
Accept: in the test yard each class plays a different reload for empty, partly spent and almost full magazines; the ammo counter changes exactly at the clip's insert marker; each state has its own camera handling from A49 and the empty reload reads heavier than the top-off; a server test covers the state thresholds and timings; all checks pass.
```

### A43. Visible ammo in the magazine check and inspect (D9)
```
Depends on: A42, A50 (inspect on every class).
Context: owner decision D9. The magazine check is a procedural tilt of the whole viewmodel (StanceConfig.MAG_CHECK.pose through Stances.viewmodelPose) plus a HUD TextLabel "MagCheck" filled by StanceMath.readout("exact", predictedMag, magSize). The count is text; no magazine leaves the gun and nothing on the model follows the ammo count. Slide and bolt lock-back already work: PackViewmodel.updateLockBack holds Slide_j_00 (Pistol) and Bolt_j_052 and BoltCatch_j_053 (Rifle) while rig.empty. Only the SMG pack has an inspect clip; on Rifle, Pistol and Shotgun F calls PackViewmodel.inspect, which returns false, until A50 lands. DroppedMagazines.drop clones the viewmodel magazine pieces as they are, so a tactical drop and an empty drop look the same.
Do: make the viewmodel magazine reflect the rounds left: rounds visible at the top of the magazine and the follower position change with the count, an empty magazine shows the follower, the shotgun shows shells in the tube or the carrier. Use mesh variants or toggled round parts on the viewmodel magazine, driven by the client ammo state. The magazine check pose and A50's inspect hold window present the magazine so the rounds read with the HUD hidden. DroppedMagazines.drop copies the visible round state onto the dropped magazine.
Accept: in captures at full, half, two rounds and empty magazines, the visible rounds and follower match the counter for every class with the HUD hidden; a dropped empty magazine shows its follower; no extra instances are created per frame; all checks pass.
```

## Audit rerun tasks (2026-10-12)

New tasks from the verified camera, VFX and zombie animation audits. Each names its milestone; A44 and A63 are preconditions for most camera and zombie reaction work.

### A44. Camera rig composer
```
Milestone: M2, before A14, A15, A41, A45, A46 and A49. Size: M.
Context: CameraController.updateCamera lerps the Scriptable camera from camera.CFrame toward CFrame.lookAt(eye, eye + RUN_DIRECTION * CAMERA_LOOK_AHEAD) with alpha 1 - exp(-12 * dt). camera.CFrame already holds last frame's CameraEffectsController offsets (bob, breath, sway, tilt, shake, recoil) and the AimAssist.cameraPull rotation, because CameraEffects writes them with no undo. Every layer is therefore re-integrated by the lerp: slow layers (breath, recoil, aim pull) come out about 5x the configured amplitude at 60 fps and 11 to 12x at 144 fps, the bob fundamental about 2x versus 4.4x. The bob's -abs(sin) has a mean of -0.64 times its amplitude, so fed back it lowers eye height by about 0.7 studs at 60 fps and 1.6 at 144. The same lerp smooths the forward axis, so at 24..30 studs/s the camera trails the eye by about 1.8 to 2.3 studs, roughly 1 stud behind the root. Stances.undoLean already works around the feedback for its own layer. WeaponController.tryFire takes origin = camera.CFrame.Position and the LookVector fallback from the final cosmetic camera, and WeaponService.onFire rejects origins more than ORIGIN_TOLERANCE 5 studs from the server Head. Stances.sideHit, WallPullback.update and CameraNearFade cast from the lagging cosmetic position. Viewmodel.step and ExertionState.step run on RenderStepped:Connect while every camera writer uses BindToRenderStep (Stances undo at Camera-1, CameraController at Camera, CameraEffects and DeathController at Camera+1, Stances apply and Flashlight at +2, IntermissionCamera at +5). Camera numbers are hard-coded outside CameraConfig: CameraController's eye offset (1.5, 1) and rate 12, the impulse constants in CameraEffectsController.init and GlanceController.onGlanced, and AimAssist MAX_ANGLE, PULL_PER_SECOND and PULL_ANGLE.
Do:
1. Add src/shared/util/CameraRigMath.luau on plain numbers only (yaw, pitch, roll and offsets as numbers, no CFrame or Vector3): base smoothing that snaps the forward component to the eye and smooths only lateral and vertical, layer composition, and an analytic or substepped damped spring.
2. CameraController keeps the base in module state, never reads camera.CFrame for smoothing, exposes CameraController.getBase(), and reads the eye offset and smoothing rates from CameraConfig.
3. CameraEffectsController builds its offsets as a layer table on top of getBase() and writes camera.CFrame once per frame. updateShake and updateRecoil move to the CameraRigMath spring; today they take one explicit Euler step per frame, while the shared Spring util substeps at 1/30 s, so the underdamped shake changes character on Low-tier phones.
4. AimAssist.cameraPull becomes an explicit decaying yaw and pitch offset in CameraEffects with pull and decay rates in CameraConfig, so its strength no longer depends on the feedback. Move the other hard-coded camera numbers listed above into CameraConfig.
5. Shot origin and aim: WeaponController.tryFire takes the origin and the fallback direction from the base plus the aim pull, never from the cosmetic layers. Verify the WeaponService ORIGIN_TOLERANCE margin with the forward snap under simulated latency (the server head lags about 0.13 s, roughly 4 studs at 30 studs/s) and record the result.
6. Decide per consumer whether it casts from the base or the final camera: Stances.sideHit, WallPullback.update and CameraNearFade. Keep the Stances lean working (keep undoLean or make the lean read the base). Check that IntermissionCamera, DeathController and DevCameraCFrame still own the camera when active.
7. Bind ExertionState.step before RenderPriority.Camera.Value - 1 and Viewmodel.step at RenderPriority.Camera.Value + 4 instead of RenderStepped:Connect. Viewmodel sway and lag read CameraController.getBase() with the aim pull, not the cosmetic camera, so the weapon stops re-reacting to its own bob, shake and recoil.
8. Add tests/camera/run.luau (numbers only): the same synthetic run at 30, 60 and 144 fps gives layer amplitudes within 10 percent; eye height does not change with frame rate; with every layer at zero the composed values equal the smoothed base; forward lag at 30 studs/s is under 0.1 stud.
9. Update wiki Architecture.md (render order) and wiki Stances.md.
Accept: tests/camera/run.luau passes; grep finds no camera.CFrame:Lerp in CameraController; no shot is rejected by ORIGIN_TOLERANCE in the latency check; selene src/, python3 tools/validate_api.py, python3 tools/strip_comments.py --check and rojo build pass; a Studio-lane verification note lists the run, lean, death camera and intermission checks.
```

### A45. Gait sync and cadence
```
Milestone: M2, after A44. Size: M.
Context: the bob phase is wrong across three layers. CameraEffectsController.update uses -abs(sin(phase)) for the vertical, lowest in mid-flight, while ExertionState.onStep fires at phase k*pi; its lateral and roll terms use sin(phase*0.5), a 4-step period. Viewmodel.updateChannels uses -abs(cos(stridePhase)), lowest at the footfall, so camera and weapon run 90 degrees apart. BodyMotionController uses sin(phase*0.5). Cadence at 24 studs/s is 2.58 cycles/s, 5.2 steps/s, well above a human run. The local third-person body run clip plays at LocomotionMath.playbackRatio, independent of ExertionState's stride clock. ViewmodelConfig.bob.speedReference is 16, below BASE_RUN_SPEED 24, so the viewmodel bob never changes in a run. PackViewmodel.desiredBase plays move = "Walk" at rate 1 whenever speed > 1, unsynced to the stride. Run clips exist only in the live SMG and Shotgun packs; Fab M4Clips and G17Clips have none, and the Run clips in RifleClips and PistolClips belong to unused rigs. D9: presentation follows the states that do vary in play: the glance slow (DistanceTracker.applySlow, down to about 13 studs/s), Endurance 24..30, exertion over time and the lateral juke.
Do:
1. Add src/shared/util/GaitMath.luau (numbers only): vertical, lateral and roll as functions of stride phase, with the vertical minimum shortly after phase k*pi and lateral and roll on a 2pi period, plus an optional per-material multiplier table keyed by material name (mud and water heavier, metal tighter) read from Humanoid.FloorMaterial. CameraEffectsController, Viewmodel.updateChannels and BodyMotionController all use it.
2. One clock: derive the stride phase from the local body run clip, or drive the body clip from ExertionState, so footsteps, the camera, the viewmodel and the visible body agree.
3. Retune the cadence curve in CameraConfig so 24 studs/s is not above about 3.5 steps/s, and record the numbers in wiki for owner review.
4. Set ViewmodelConfig.bob.speedReference across 13..30 so the glance slow, base speed and full Endurance read differently, and scale the bob with exertion.
5. Add an optional run field to ViewmodelPackConfig.ClassPack, set for SMG and Shotgun; PackViewmodel.desiredBase picks idle, move or run. Add ViewmodelClipPlayer support for driving a looped clip's time from an external phase, and map ExertionState.getStridePhase() onto the base locomotion loop so the clip footfall meets the footstep; packs without a footfall marker take a configured offset.
6. Tests in tests/camera/run.luau: the vertical minimum lands within 0.15 rad after each footstep phase; cadence and bob differ between 13, 24 and 30 studs/s.
Accept: tests pass; in a Studio capture at the glance slow, 24 and 30 studs/s the step cadence, bob amplitude and viewmodel clip rate visibly differ; the camera and weapon dip land on the footstep sound; Rifle on M4Clips plays Walk at a phase-driven rate with no errors; all checks pass.
```

### A46. Glance and impact reactions on camera and viewmodel
```
Milestone: M2, after A44 and A45. Size: M.
Context: the frequent impact on every difficulty is the glance. GlanceController moves the camera and BodyMotionController on PlayerGlanced(side, power), but the viewmodel does not react: impactPos is fed only by landing. CameraEffectsController.init reacts to every HealthChanged drop with a constant impulse(Vector3.new(0.4, -1, 0.2), 3.2) and BodyMotionController.impulse(-4.5, 2.5), while PostFx.damage scales by the delta, so screen and camera disagree. Non-lethal damage exists only on Easy (two fixed amounts, 27 or 18). The Humanoid Landed impulse is a constant 2.4 while Viewmodel.trackImpact scales by fall speed; landings only follow terrain drops (FlowService sets JumpHeight 0). CameraEffectsController.impulse has no source position, falloff or rotational trauma. Camera breath reads only ExertionState.get(); ViewmodelConfig.breathe (rate 1.4, amplitude 0.024) and drift are fixed; BreathingController loops are not phase-locked to the camera breath.
Do:
1. Add Viewmodel.hit(direction, strength) feeding swayRot and impactPos, and call it from GlanceController. Glance reactions on camera and viewmodel are signed by side and scaled by power, with 3 or more variants from a seeded jitter. Values in CameraConfig and ViewmodelConfig.
2. Replace the generic HealthChanged impulse with a reaction scaled by the drop relative to MaxHealth, rolled toward the PlayerDamaged source once A47 lands.
3. Share one landing signal with Viewmodel.trackImpact's fall speed and scale the camera impulse and a small FOV dip by it.
4. Add CameraEffectsController.shakeAt(position, strength, radius) with distance falloff and a short rotational trauma channel, config in CameraConfig, for supply drops, the heli crash beat and later explosions.
5. One breath phase: BreathingController loop weights follow the camera breath phase on every difficulty. Below CameraConfig.lowHealth.ratio, breath amplitude and rate rise, ViewmodelConfig.breathe and drift scale up and recoil recovery slows; this reaches only Easy, so keep it small and outside the accept.
6. Tests (numbers only): side sign correct for left and right glances; reaction monotonic in power; landing scaling bounded; breath phase shared.
Accept: tests pass; in Studio left and right glances move camera and weapon toward the correct side and repeated glances differ; a terrain drop lands harder than a small step; all checks pass.
```

### A47. PlayerDamaged event and the grab beat
```
Milestone: M2, in the ZombieAI single-writer slot after T20. Size: M.
Context: player damage is humanoid:TakeDamage in ZombieAI's catch path (ZombieAI.onTouched: a lethal grab on Medium and Hard, touchDamage * GRAB_DAMAGE_SCALE on Easy) with no remote; the client only sees Humanoid.HealthChanged in CameraEffectsController, PostFx and RunHud. onTouched sets the DeathCause attribute to "Grabbed", and nothing reads it except DistanceTracker clearing it; the stuck kill sets Health = 0 with no cause. There is no grab clip. A31, A46, A48 and A57 need a damage event with a source, and A48 needs to know which zombie made the grab.
Do:
1. Add Remotes.Event.PlayerDamaged (server to client, never client-supplied data): sourcePosition, amount, lethal. Fire it from every server path that damages a player, lethal grabs included.
2. On a grab, record the grabber in a DeathGrabber ObjectValue on the player (or an attribute with the zombie id) next to DeathCause, turn that zombie to face the player and play a grab or bite one-shot: the full-body attack clip until A34 bakes a Mixamo grab or bite. ZombieAudio plays a bite at the grabber.
3. Client handlers validate the payload with typeof checks.
4. A pure test for the payload builder.
Accept: PlayerDamaged fires for lethal and non-lethal grabs with the right source; in Studio a Medium stop with a Runner behind shows that Runner turning and biting; A31 and A48 can subscribe; all checks pass.
```

### A48. Death camera variants by cause and direction
```
Milestone: M2 for the grabbed variant (after A47 and A63); the side falls may follow in M3. Size: M.
Context: DeathController.updateDeathCam runs three fixed phases (impact to IMPACT_END 0.22 s, side fall to SIDE_END 0.95 s, lying to ROLL_END 1.75 s). It always rolls -78 degrees toward the same side, lies at FALL_PITCH 64 degrees facing RUN_DIRECTION, then tracks the nearest head at HEAD_TRACK_WEIGHT 0.22 with a +5 plus or minus 4 degree roll. The constants live in the controller. Viewmodel.step just hides the rig on death. DeathCause is only ever "Grabbed" (ZombieAI) or nil (DistanceTracker clears it; the stuck kill has no cause), and on Medium and Hard almost every death is a grab, so the grabbed variant is the main case. findNearestZombieHead reads the zombie Head part, which on clients sits at HumanoidRootPart (A63). The binding at Camera+1, the same as CameraEffects, does no harm: CameraEffects returns before writing camera.CFrame when not alive. Wiki Gameplay Systems.md still holds a stale orbit paragraph (corpsePos + (0, 1.1, 0), roll around -12 degrees) before the current "Fall-back camera" paragraph.
Do:
1. Move every constant into src/shared/config/DeathCameraConfig.luau (numbers only, so the selector test can read it) with variants grabbed (pulled down toward the grabber and facing it), fallLeft, fallRight, fallBack and collapseForward.
2. Grabbed: the first beat frames the grabber from DeathGrabber (A47) at close range for about 1 s, aimed at its head bone (TransformedWorldCFrame, bone name from ZombieSkins.head), then the sequence continues. findNearestZombieHead uses the head bone too.
3. Other deaths: pick from the PlayerDamaged source bearing, else the nearest zombie bearing, plus a spherecast for free space on the fall side; seeded random among valid variants.
4. Drop the viewmodel out of frame over a configured 0.25 to 0.4 s (pitch down and away through the pack placement) before hiding it.
5. Pure selector test: bearing angle and cause in, variant name out, for four bearings and the grabbed cause. Keep the binding priority as it is.
6. In wiki Gameplay Systems.md delete the stale orbit paragraph and extend the "Fall-back camera" paragraph.
Accept: tests pass; a grab death shows the grabber biting before the feeding ring; four non-grab deaths from different sides fall differently; the camera never ends inside geometry on a wall-side death; the weapon drops instead of vanishing; all checks pass.
```

### A49. Handling camera layer: reload phases, dry fire, last round
```
Milestone: M2 for the Rifle; other classes in the A33 feel sessions. Depends on: A44. Size: M.
Context: ShotgunClips, used by the live Shotgun pack, carries an animated CB-Head_0104 camera track in all 10 clips (2 to 15 keys each, including IdleToReload, Reload, AccionFire and Fire), and ViewmodelClipPlayer.step already computes deltas for extras, but ViewmodelClipPlayer.extraWorld is never called. Fab M4Clips and G17Clips carry the camera node only as a static extra (FPS_Camera or Camera rest row), and the SMG has no animated camera, so reloads, draws and inspects never move the camera there. Viewmodel.onPhase already emits MagOut, MagIn, BoltBack, BoltForward, SlideRelease and ShellIn with the reload tag (tactical, empty, shell, chamber; A42 adds the ammo states), and nothing camera-side listens. WeaponController.tryFire on an empty magazine only calls WeaponSfx.playDryfire. PackViewmodel.updateLockBack snaps into the locked pose. D8 and D9: each reload state and each repeated event has its own feel and variants.
Do:
1. Shotgun: drive a handling camera layer from extraWorld("CB-Head_0104") deltas, scaled in config.
2. M4, G17 and SMG: CameraConfig.handling per class, per reload tag, per phase name: an impulse {pitch, yaw, roll, fov} plus a jitter fraction for variants, on a separate handling spring layer in CameraEffectsController, not the recoil spring. Empty-state entries are heavier than tactical ones (bolt slam, slide release).
3. Viewmodel.dryFire(): a small trigger-hand twitch through recoilRot with no slide motion, plus a tiny camera nudge; call it where tryFire calls WeaponSfx.playDryfire.
4. A last-round kick multiplier in ViewmodelConfig applied in Viewmodel.onFired when the predicted magazine reaches 0, and ease updateLockBack into the locked pose over a configured time.
5. The A14 cameraMotion setting scales the whole layer.
6. Tests (numbers only): impulse lookup falls back to class defaults; jitter stays within bounds; layer amplitude is frame-rate independent.
Accept: in captures the Rifle tactical and empty reloads move the camera differently and land on MagIn and BoltForward; the Shotgun reload moves the camera along its authored track; dry fire shows a twitch; the last shot locks the bolt with an eased, heavier kick; all checks pass.
```

### A50. Inspect and holster coverage for every class
```
Milestone: M2 for the Rifle, after A18; other classes in the A33 feel sessions. Size: M.
Context: only the SMG pack has an inspect clip. On Rifle (Fab M4Clips), Pistol (G17Clips) and Shotgun, F calls PackViewmodel.inspect, which returns false, so nothing happens. Holster clips exist in M4Clips and G17Clips and Unequip in SMGClips, but none is played: WeaponController.requestEquip plays only the holster sound, and Viewmodel.setWeapon waits for the server's WeaponId change, then destroys the rig and plays Draw. The legacy procedural inspect (inspectOffset) is not used by pack rigs. A43 needs an inspect hold pose on every class. D9: repeated equips should not all look the same.
Do:
1. Add optional holster (clip name: Holster or Unequip) and inspectPose (a keyed procedural sequence of offsets and angles over time) fields to ViewmodelPackConfig.ClassPack.
2. Play the outgoing holster during the server round trip, from requestEquip until onWeaponChanged, capped at a configured duration and never as an added delay. Fire stays gated by drawTime from the moment the new rig draws.
3. In Viewmodel.toggleInspect, when PackViewmodel.inspect returns false, play inspectPose on the pack placement: show the left side, then the ejection port and magazine. Expose a hold window for A43 and cancel it on fire, reload or swap. The Luau-authored poses go through the asset policy look pass.
4. Varied equips: two or three draw speeds or angle offsets picked at random so repeated swaps differ; the first equip per life stays with A18.
5. Test the numeric sequence sampler and the holster timing cap.
Accept: F gives an inspect on all four classes; a swap shows the old weapon leaving before the new one draws, with no added swap time; fire cannot happen before the draw completes; owner look pass on the authored inspects; a Studio-lane note lists frame-step checks per class; all checks pass.
```

### A51. VFX texture baseline: no default sparkle sprites
```
Milestone: M2, before A24, A25 and A26. Size: M.
Context: most ParticleEmitters never set Texture and draw Roblox's default sparkle sprite, so blood, dust and impact debris read as glitter. Client sites: WeaponVfx buildMuzzleRig (FlashCore, FlashSparks), WeaponVfx.impact, WeaponVfx.pickupBurst, ZombieVfx burst, GoreController spawnBlood, DeathGore spawnBurst, MotionVfx makeEmitter (StepDust, JukeDust, BreathVapor), FlashlightController DustMotes, and the WorldVfx builders (buildAshLayer, attachEmbers, buildRotorWash, buildFlies, buildSparkLamp, buildExhaustHaze). Server sites: CityDiorama (2), WeaponPickups (1) and AmmoCrates (1); DesertBase is the only server file that sets Texture. Only the WeaponVfx wisp, puff and trail use smoke_main.dds through applySmokeTexture. The manifest has no texture/vfx slots. VfxConfig builds Color3 and Enum.Material at load, so a CLI test cannot require it.
Do:
1. Add a pure texture key table and resolver with no Roblox types (for example src/shared/util/VfxTextures.luau): keys smoke, dust, mist, droplet, spark, ember, ash and fly, each with a manifest key and a built-in fallback path (verify each rbxasset path in Studio content, else fall back to smoke_main.dds); it returns the rbxassetid from AssetIds when the id is above 0 and the fallback otherwise. VfxConfig re-exports it.
2. Set Texture at every emitter site above. Use Orientation VelocityParallel for spark and droplet keys, and Squash where it helps streaks.
3. Asset lane: needed rows texture/vfx/<key> in assets/manifest.json and NEEDED.md (system vfx), with no uploads.
4. tests/vfx/run.luau tests the pure resolver with and without an id.
Accept: grep shows every Instance.new("ParticleEmitter") site in src sets Texture; tests/vfx passes under the luau CLI; the Studio-lane note confirms no star sprites in impacts, blood, dust, ash or pickups; all checks pass.
```

### A52. Impact correctness: normal-aligned emission, material families, gore gate
```
Milestone: M2, WeaponVfx order T17a, A51, A52, T17b. Size: M.
Context: WeaponVfx.impact anchors at CFrame.lookAt(position, position + normal), which puts the normal on the anchor's Front, but never sets EmissionDirection, so particles leave along Top: a wall hit sprays up the wall and a floor hit degenerates the lookAt and sprays sideways. It branches only on materialName == "Flesh"; every other material gets the same grey-brown puff (Color3 140, 128, 110) plus sparks, including grass, mud, wood and water, and size ignores caliber. It never reads SettingsService, so the red flesh puff plays with Blood Effects off. WeaponAudioMath.impactFamily (src/client/audio) maps materials to concrete, metal, wood, dirt and flesh; Water maps to dirt and Glass falls through to concrete. No src module requires another by a string path and the luau CLI has no script, so moving impactFamily into a shared module would break tests/audio.
Do:
1. WeaponVfx requires the client WeaponAudioMath and calls impactFamily; the table stays where it is.
2. Orientation: set EmissionDirection = Front on the existing anchor, or build it with UpVector equal to the normal and a stable right axis when the normal is world up or down. A pure helper, if added, works on number tuples; otherwise the orientation check goes into the Studio note.
3. Add VfxConfig.impacts per family (colour, puff count, size, speed, sparksChance) and impactCaliberScale keyed by the WeaponsConfig casing. WeaponVfx.impact takes an optional weaponId, passed from WeaponController drawShot.
4. Sparks always on metal, on a chance on concrete, never on dirt, wood or flesh. Water gets an explicit material check and an upward splash.
5. Gate the flesh branch on SettingsService.get("bloodEnabled"), with a small dark neutral puff when off.
Accept: tests/audio still passes; a numbers-only test covers the family profile lookup; the Studio note confirms floor hits rise from the floor, wall hits come out of the wall, no sparks on grass or dirt, a splash on water and no red with Blood Effects off; all checks pass.
```

### A53. Per-hit zone, target and kill flag in the shot payload
```
Milestone: M2, WeaponService order T1, T3a, A53, T13. Size: M.
Context: WeaponService onFire sends each hit as {position, normal, material}. handleHit computes headshot and killed per ray, but they reach the client only combined in one Confirm per volley (HitMarkerMath.combine(outcomes)). WeaponController.predictShot drops result.Instance. Direction needs no new data: each Shot already carries the origin and every hit position. A20, A21, A22, A26 and A66 need the region, the target and the kill per hit. onWeaponHit skips drawShot for the local shooter, so the local read comes from prediction, which raycasts client hit boxes that sit at HumanoidRootPart until A63 lands.
Do:
1. Add src/shared/util/HitZone.luau (pure): classify(partName) returning "head", "body", "limb" or "none". Verify the hit box names ZombieFactory and ZombieHitboxes use for legacy and skinned zombies (Head, Chest, Hips and the eight limb segments) and cover them.
2. In WeaponService onFire add zone, part (the hit box name), model (the zombie model) and killed to each hit entry. Keep the existing fields and the Confirm argument unchanged; server validation unchanged.
3. In predictShot set zone and part from result.Instance.Name through HitZone, with killed = false. The predicted zone is cosmetic only and is trusted only after A63.
4. Add the optional fields to the WeaponSfx.Hit type, and check that HitMarkers and BodyController still work with their positional arguments.
5. Add a test group in tests/hitmarkers/run.luau for HitZone.classify.
Accept: the Luau test passes; in a Studio log a headshot on a skinned zombie reports zone head on the remote Shot event (and on local prediction once A63 is merged) and a kill reports killed true; hit markers are unchanged; all checks pass.
```

### A54. Pooled impact decals: bullet holes and blood splats
```
Milestone: M2, after A52 and T17a. Size: L.
Context: no code places a decal at a hit point; DecalsConfig and WorldDecals cover static dressing only. The dynamic blood stains are SmoothPlastic Parts at hard-coded heights with no raycast: ZombieVfx.bloodAt BloodStain at Y 0.58 and DeathGore spawnPool at Y 0.62, so they float or sink on kerbs, vehicles and prebuilt maps. D9 requires surfaces to show the fight; TTK Testing shows bullet hole decals.
Do:
1. Add src/client/systems/ImpactDecals.luau with a ring buffer per kind (hole, blood). Each entry is an anchored card Part (CanCollide, CanQuery and CanTouch false, CastShadow false, Transparency 1) with one Decal on Face Front; cards are reused and never created after warm-up.
2. place(position, normal, family, caliber): skip humanoid models and unanchored assemblies; orient to the normal with a random roll; offset by VfxConfig.decals.lift; size per family and caliber; pick 1 of 3 variants per family.
3. On a flesh hit, raycast 6 studs past the hit along the shot direction, excluding the zombie, and place a blood splat on what it hits, gated on bloodEnabled.
4. Fade Decal.Transparency over the last 2 s of the lifetime. Caps and lifetimes go in VfxConfig.decals with High and Low values (for example 64 and 16 holes).
5. Route ZombieVfx.bloodAt stains and DeathGore spawnPool through ImpactDecals.placeGround, which raycasts down.
6. Call it from WeaponController drawShot through a WeaponVfx facade function.
7. Asset lane: needed rows texture/vfx/hole_{concrete,metal,wood,dirt}_01..03 and blood_splat_01..04; with id 0, skip placement silently.
Accept: InstanceCount flat over 30 s of sustained fire after a 10 s warm-up; in Studio decals sit flush with no z-fighting on walls, the floor and car bodies; none appear on zombies or players; Blood Effects off removes the splats; all checks pass.
```

### A55. Tracers as pooled travelling beams with a low-ammo rule
```
Milestone: M2 for the local Rifle; remote tracer starts after A60. Size: M.
Context: WeaponVfx.tracer creates a 0.05 x 0.05 Neon Part spanning muzzle to hit for 0.045 s, with one TRACER_COLOR for every class. WeaponController drawShot traces every third shot on auto weapons; on the Shotgun it draws one tracer per pellet that hits, plus one full-range tracer only when nothing hit. Local tracers already start at Viewmodel.getMuzzlePosition(); remote tracers start at the server origin, the shooter's camera. drawShot's tracerCounter is shared by local and remote shots, so a teammate's fire shifts which local rounds trace. D9 asks for low ammo to read without the HUD.
Do:
1. Add VfxMath (numbers only) with tracerHead(t, speed, length, distance), returning the head and tail distance, and shouldTrace(shotIndex, everyNth, roundsLeft, lastRounds). Test both in tests/vfx/run.luau.
2. Add VfxConfig.tracers per class (speed in studs/s, length, width, colour, everyNth, lastRounds, maxPellets) with High and Low values.
3. Replace WeaponVfx.tracer with a pool of Beam rigs (two Attachments on a pooled anchor, FaceCamera, a light texture from A51, Width0 and Width1), advanced in the existing onRenderStep and returned at the target or after the miss range.
4. In drawShot keep one counter per shooter, use shouldTrace with predictedMag for the local shooter, and cap Shotgun tracers at maxPellets. Remote shooters start at BodyController.muzzlePosition(player) once A60 lands, else at the origin offset down and right.
5. Impacts are drawn at once while the tracer is in flight: either delay the impact to the head's arrival or accept the mismatch, and write the choice in the verification note.
Accept: tests pass, including tracer head timing at 30 and 144 fps within 10 percent; InstanceCount flat; in Studio the tracer visibly travels; the last rounds of a Rifle magazine all trace; teammates' fire does not change the local cadence; the Shotgun shows at most maxPellets tracers; all checks pass.
```

### A56. Weapon heat and per-class muzzle flash
```
Milestone: M2, after T17b and alongside A24. Size: M.
Context: WeaponVfx.muzzleFlash takes only an attachment and a weaponId: size from FLASH_CLASS_SCALE, shape from the shared FLASH_VARIANTS for every class. Barrel smoke fires once, a fixed max(3, 10 * DENSITY) particles, in the update loop only after 0.35 s without a shot (os.clock() - lastBurstAt > 0.35) and only when WeaponController's burstShots reached 3, on the local viewmodel only, so a 3-round burst and a full magazine look the same. Heat is not modelled. WeaponVfx.burstSmoke, shellEject and shellLandMaterial are dead exports. The last round keeps a normal flash: the empty state reads through the lock-back, dry fire (A49) and the ammo-aware playShot.
Do:
1. Add VfxMath.heatStep(heat, dt, shot, perShot, coolRate), exponential and frame-rate independent, with tests at 30 and 144 fps.
2. Keep a heat value per weapon id in WeaponVfx, with VfxConfig.muzzle[class].heatPerShot.
3. Barrel smoke follows heat: amount, opacity, size and linger time scale with it; near maximum heat a slow rising curl; smoke still curls during a reload or inspect while heat is above zero.
4. Per-class flash variant sets in VfxConfig.muzzle (petals, lengths, core): Pistol, SMG, Rifle and Shotgun each distinct.
5. A muzzle light multiplier per lighting preset in config, default 1, read through LightingDirector.getCurrent(); the owner look pass decides whether it moves.
6. Remove the dead exports if T17b has not.
Accept: tests pass; in Studio a single tap shows only a wisp, a full Rifle magazine leaves a smoke column for about 2 s, and the four class flashes are distinct side by side; all checks pass.
```

### A57. Player damage and low-health screen states
```
Milestone: M3, after A31 and A47. Size: M.
Context: PostFx buildVignette is a full-screen red Frame with a UIGradient at Rotation 90, so it is red only at the top and bottom edges; UIGradient is linear only. Low-health desaturation and a vignette pulse already ship (LOW_HEALTH_RATIO 0.3, HEARTBEAT_RATE_LOW 2.4 to HEARTBEAT_RATE_CRITICAL 3.6 Hz). PostFx has no config module; its constants are inline. GoreController plays ZombieAudio.playBite and spawns blood at the root on any health drop. The only non-lethal player damage is the zombie grab on Easy, so a damage-cause branch adds nothing; spend the effort on bite variants and side. PostFx already owns a DepthOfFieldEffect (TFZ_MenuDof).
Do:
1. Add src/shared/config/PostFxConfig.luau with stages healthy, wounded (below 0.6) and critical (below 0.3), each with vignette strength, desaturation, blur size and pulse rate, High and Low. Move the PostFx constants there.
2. Replace the gradient Frame with a radial vignette ImageLabel (asset-lane slot texture/ui/vignette_radial; the current Frame is the fallback while the id is 0).
3. Screen-edge blood splatter on bites: 3 or more variants chosen per bite and placed on the side of the PlayerDamaged source, slide and fade, gated on bloodEnabled (slots texture/ui/screen_blood_01..03).
4. At the critical stage pulse a BlurEffect with the heartbeat phase (off on Low), kept separate from TFZ_MenuDof or sharing it with one clear owner.
Accept: captures at 100, 50 and 20 percent health (Easy) show three distinct states; Blood Effects off removes the splatter; the Low tier drops the blur; all checks pass.
```

### A58. World fire flicker by light type, live density and particle fire
```
Milestone: M2 (City night), ChunkFactory order T15, A28, A29, A58. Size: M.
Context: WorldVfx stepFlicker runs every FLICKER_INTERVAL 0.09 s, calls CollectionService:GetTagged(TFZ_Flicker) each time, and toggles Light.Enabled with a 12 percent off and 55 percent back-on roll. ChunkFactory tags the fire-barrel PointLight with the same tag, so fires switch fully off and on at about 11 Hz, against the one warm, steady light accent of the Into the Dead reference. WorldVfx bakes Rate = n * DENSITY when emitters are built, so the Effects Density slider has no live effect. ChunkFactory fire barrels and buildSmokeColumn use the legacy Fire and Smoke instances.
Do:
1. Set a FlickerKind attribute (fire or electric) where TFZ_Flicker is applied, in ChunkFactory and in WorldVfx buildSparkLamp.
2. In WorldVfx keep a tag set from GetInstanceAddedSignal and GetInstanceRemovedSignal, update at most at 20 Hz and only lights within FLICKER_RANGE. Fire: Brightness and Range follow math.noise with a per-light seed and never switch off. Electric keeps the stutter.
3. Add VfxConfig.onDensityChanged, fired by setDensity, and re-rate the WorldVfx continuous emitters.
4. Behind VfxConfig.PARTICLE_FIRE, replace Fire and Smoke in ChunkFactory with a ParticleEmitter flame (FlipbookLayout Grid4x4 when the texture/vfx/fire_flipbook id is above 0, else fire_main.dds) and a smoke emitter, each with High and Low rates.
Accept: barrel fires glow continuously with an organic flicker in Studio; moving the density slider changes the ash rate live; no GetTagged call per frame; light counts unchanged; all checks pass.
```

### A59. Player death gore rebuild
```
Milestone: M2, after A51 and A54 (step 1 can land at once). Size: M.
Context: DeathGore spawnGibs throws 7 collidable SmoothPlastic boxes in three flat colours with ApplyImpulse, anchors them after 2.5 s and removes them after 12 s. spawnPool tweens a cylinder Part from 0.5 to 5.5 studs at Y 0.62, although DeathController already computes groundY = groundBelow(lastCorpsePos) just before calling DeathGore.render(lastCorpsePos) and never passes it. feastTick repeats the burst and gibs during the feeding ring. Nothing is pooled. It is the last image of every run.
Do:
1. Pass groundY from DeathController into DeathGore.render and use it for the pool now.
2. Remove the box gibs. If dismemberment stays a feature, use a pooled set of at most 6 MeshParts from the asset lane (generated or licensed, with a manifest row), anchored after settling; if no mesh passes a look test, gate gibs off and keep only blood.
3. Make the pool an ImpactDecals ground placement raycast at the corpse position that grows by stepping the card size.
4. spawnBurst uses the A51 mist and droplet textures on a pooled anchor.
5. feastTick reuses pooled bursts and adds splats around the corpse within a radius. Keep the bloodEnabled and dismembermentEnabled gates.
Accept: InstanceCount flat across a 20 s feeding ring; no box gibs; the pool lies flush on a slope and on a kerb; gore toggles respected; all checks pass.
```

### A60. Teammate weapon VFX in third person
```
Milestone: M3, or M5 before the two-player session (the M2 slice is played solo). Size: M.
Context: BodyController onShot calls BodyRig.fire, which only drives the kick and snap springs and the pump timeline, so teammates show no muzzle flash, light, smoke or casings. WorldWeaponModel.addSockets (src/shared/util/WorldWeaponModel.luau) already creates a Muzzle Attachment on the Grip part plus GripSocket, SupportSocket, MagazineSocket, ChargeSocket, PortSocket and PumpSocket; only an eject point is missing. ThirdPersonConfig "port" is the hand target for shell loading, not an ejection port. Remote shots have no distance LOD.
Do:
1. Add an Eject socket in WorldWeaponModel.addSockets with per-class offsets.
2. In BodyController onShot, when the shooter is not the local player, reach grip:FindFirstChild("Muzzle") through entry.rig.weapon, call WeaponVfx.muzzleFlash on it (world-scale rig) and a new WeaponVfx.ejectWorldCasing(attachment, caliber, velocity) that skips the camera-space stage.
3. Distance LOD in VfxConfig: no casings beyond 40 studs, no flash light beyond 60 studs. Remote flash lights borrow slots from the A24 TransientLights registry, nearest shooter first.
4. Expose BodyController.muzzlePosition(player) for A55.
Accept: in a two-client Studio test a teammate's flash, light and casings are visible at 20 studs and the light is dropped past 60; live PointLights stay within the budget; InstanceCount flat with two shooters; all checks pass.
```

### A61. Footstep dust by speed and water, and teammate step dust
```
Milestone: M3. Size: S.
Context: MotionVfx onStep emits the fixed dust.count from VfxConfig.dustFor at one MotionVfxFeet attachment at the root centre, whatever ExertionState.getSpeed() is. Water only gets a bigger dust puff. MotionVfx runs only for the local player, and in first person the camera rarely sees its own feet, so left and right emission would be almost invisible; the visible gain under D9 is teammates' steps.
Do:
1. Add VfxConfig.STEP_DUST_SPEED_REF and a speed curve; scale count, size and speed by ExertionState.getSpeed() across the glance slow and 24..30.
2. Add a splash profile for Enum.Material.Water: upward droplets with a white mist, visible at the bottom of the frame.
3. Teammate step dust and splash through BodyRig footsteps at a distance LOD, reusing per-character emitters (no instances per step).
4. A pure test of the speed curve in tests/vfx/run.luau.
Accept: test passes; in Studio a glance-slowed step and a full-speed step differ; water gives a splash; a teammate's steps kick up dust in a two-client test; all checks pass.
```

### A62. Teammate damage and death blood on other clients
```
Milestone: M3, with A60. Size: S.
Context: GoreController.watchCharacter and DeathController (which calls DeathGore.render and feastTick) handle only Players.LocalPlayer, so a bitten or killed teammate shows nothing to the squad. In a 1 to 3 player co-op game this is a primary health read under D9.
Do: on remote characters' HealthChanged drops, play a world-only, gore-gated blood burst (A51 textures, pooled); on a remote death place a ground pool through ImpactDecals.placeGround; add a distance LOD and High and Low caps in VfxConfig.
Accept: in a two-client test a bitten teammate bleeds and a dead teammate leaves a pool; Blood Effects off removes both; InstanceCount flat; all checks pass.
```

### A63. Client zombie hit box mirror
```
Milestone: M2, before A20, A22, A26, A48 and the local zone in A53. Size: M.
Context: ZombieHitboxes.attach joins each box (Head, Chest, Hips and eight limb segments) to the root with C0 = C1 = identity and drives it only through Motor6D.Transform, which does not replicate. On clients all 11 boxes sit at HumanoidRootPart, about waist height. WeaponController's predicted shot, the only impact the local shooter sees, raycasts this cluster: a shot at a skinned zombie's head passes the visual head and draws a world impact behind it while the server scores a headshot. DeathController.findNearestZombieHead aims the corpse-eye camera at the root. The client Animator poses bones locally, so bone.TransformedWorldCFrame is valid on the client.
Do: add a client mirror of ZombieHitboxes for zombies within a configured range: write each box's Motor6D.Transform from its bone (ZombieSkins head, chest, hips and limbs[name].from) in PreSimulation after the Animator, the same rule the server uses. Out of range, boxes are left alone. Share the pose rule with the server module if practical. Write in wiki Architecture.md that client code reads bones or the mirrored boxes, never the raw box positions.
Accept: Studio-lane note: a local headshot on a skinned Walker, Hazmat and Ghoul draws a flesh impact at the head and predictShot hits Head; client frame time unchanged within noise with 60 alive; all checks pass.
```

### A64. Skinned zombie animation in the lure, the feeding ring and sleeper spawns
```
Milestone: M2, ZombieAI row after T20 (or folded into T20's ZombieFeeder extraction). Size: M.
Context: every run zombie is a skinned bone rig (ZombieFactory.buildSkinned) animated by ZombieAnimator.setupSkinned, which loads no rise or feeding track. (1) The lure branch in ZombieAI.aiStep calls humanoid:MoveTo(lure.pos) and continues before setMode and setSpeed, so an Idle or Aware zombie glides to the corpse on its idle clip and an Alert one keeps its last run rate. It also leaves state.faceOnly and state.moveActive as they were: a lured Aware zombie keeps faceOnly, so smoothStep rewrites root.CFrame toward its stale heading every Heartbeat, and a chasing one keeps moveActive, so smoothStep calls Humanoid:Move(heading) on top of MoveTo. (2) ZombieAI.poseFeeder anchors the root, but ZombieAnimator.playFeeding returns early with no tracks.feeding, so the move or idle track runs in place in DeathController's corpse-eye shot. (3) feeder.procedural is true on skinned rigs, so kneel slots drop the anchored root by KNEEL_DROP 0.9 into the floor, and animateFeeder writes motors that collectMotors does not find (only the UpperTorsoWeld and LowerTorsoWeld Welds exist). (4) spawnZombie with posture Dormant or Feeding falls through to a standing Idle zombie, because holdLying and hasFeedingClip are false.
Do: in the lure branch set a Lured mode, clear faceOnly and moveActive on entry, call ZombieAnimator.setMode once and ZombieAnimator.setSpeed every tick with the lure WalkSpeed (check the Move versus MoveTo precedence in Studio). Add ZombieAnimator.halt(tracks) to stop the move track and play idle. In poseFeeder, when tracks.skinned and there is no feeding track, call halt; apply KNEEL_DROP only when collectMotors found a waist motor. In releaseFeeder set state.mode = "Idle" so the next tick re-issues setMode. A reversed death clip as an interim rise (AdjustSpeed negative) pulls the body up instead of standing it up: ship it only on an owner look verdict, otherwise Dormant keeps the standing fallback until A34. Put the speed-to-rate and mode-transition decisions in a pure src/shared/util/ZombieAnimMath.luau and add tests/zombies/run.luau.
Accept: tests/zombies/run.luau passes; no code path leaves a move track playing on an anchored root. Studio-lane note: in a death on Medium every feeder is on a feeding clip or idle, none sinks below the ground and none runs in place; a lured idle zombie walks on its walk or run clip. All checks pass; wiki Gameplay Systems (Corpse lure and feeding) updated.
```

### A65. Ghoul retarget support
```
Milestone: M3, before the Ghoul parts of A21, A34, A66 and A67. Size: M.
Context: the Ghoul is the only Runner skin (ZombieSkins.byConfig.Runner), the zombie that chases from behind under D1. It was left out of the UE retarget (Decisions 2026-10-01) because every one of its clips holds Bone.009 about 3.08 studs below bind, which ZombieFactory.buildSkinned compensates with skin.offset (0, 3.077, -0.2). tools/zombie_pack/retarget_ue.py has only the MIXAMO and BIPED maps. Bone names use the importer suffixes (Bone.005_3, Bone.013.L_59 and so on) from tools/zombie_pack/roblox_bones.json. Until this lands, every new rise, flinch, death, limp or attack clip skips the Ghoul.
Do: add a GHOUL target map (Manny and Mixamo keys to the Ghoul's Bone.* names) to retarget_ue.py, plus a per-rig root offset term so baked poses keep the root bone at the same constant drop as the Sketchfab clips. Validate by retargeting the UE idle and run onto the Ghoul and comparing foot and pelvis height against the Ghoul's own idle and run; record ground speeds.
Accept: a retargeted UE run on the Ghoul plays in the test yard with feet on the ground and skin.offset unchanged (Studio-lane frame-step capture); the script self-check prints the root drop per clip and fails if it differs from the native clips by more than 0.05 studs; wiki Decisions updated.
```

### A66. Limb damage state: limping and crawling zombies (D9)
```
Milestone: M3, ZombieAI and ZombieAnimator rows after T20; after A53. Size: L.
Context: Roadmap D9 names "a limp on a crippled zombie". Bone-following limb hit boxes already exist (LeftUpperLeg, LeftLowerLeg, RightUpperLeg, RightLowerLeg from ZombieSkins.limbs), but WeaponService.handleHit only branches on part.Name == "Head". AssetIds.animation.zombie_fab.walker.crawl_ue and hazmat.crawl_ue are uploaded and unused. The server is authoritative for damage. D1 still holds: a crippled zombie may only get slower.
Do: add ZombiesConfig legCrippleDamage, crawlDamage, crippledSpeedMultiplier and crawlSpeedMultiplier. WeaponService.handleHit passes the region to a new ZombieAI.onRegionHit(model, region, damage), which accumulates per-side leg damage in ZombieState and sets a Crippled attribute (Left or Right) and, past crawlDamage or with both sides crippled, a Crawler attribute. ZombieAI applies the multipliers to state.speed. ZombieSkins gets optional limpLeft, limpRight and crawl clip lists (crawl from crawl_ue with its measured ground speed); ZombieAnimator swaps the move set when the state changes. The crawler gets a lowered touch Hitbox and blockers so the grab band stays fair. Without a limp clip, the interim is a client-side additive on the crippled side (stiff knee, hip drop) on the ZombieSkins bones. Thresholds and selection in ZombieAnimMath with tests in tests/zombies/run.luau.
Accept: tests cover thresholds, side selection and speed multipliers. Studio-lane note: shooting one leg of a Walker gives a visible limp on that side and a slower chase; enough leg damage turns Walker and Hazmat into crawlers; a crawler grabbing a stopped player still works; the Ghoul keeps its gait until A65 gives it a crawl clip. All checks pass; wiki Gameplay Systems updated.
```

### A67. Attack while moving, with a contact-timed swing
```
Milestone: M3. Size: L.
Context: ZombieAnimator.attack plays full-body Action clips while ZombieAI sets WalkSpeed = speed * ATTACK_SLOWDOWN (0.3), so the root slides under planted attack legs. Damage comes from Hitbox.Touched (ZombieAI.onTouched) whenever contact happens, unrelated to the swing. Roblox has no per-bone masks, but bones left unkeyed in a higher-priority track fall through to the lower track. bake_clip in build_zombie_anims.py marks every ancestor of a moving bone as moving (moving[parent] = True), so keying the spine also keys the pelvis with real transforms, which would override the run's pelvis and hip bob.
Do: in tools/zombie_pack add an option that writes upper-body-only variants of each skin's attack clips (spine, neck, head, clavicles and arms keyed; legs unkeyed; the pelvis written only as a container, or the mask starting at spine_01 if the container still overrides), plus each clip's contact time in clips.json, then ingest. Add attackMoving and a per-clip contact field to ZombieSkins. ZombieAnimator.attack picks the moving variant above a speed threshold and the full-body clip when near-stationary; remove ATTACK_SLOWDOWN for moving swings. D1 choice, explicit: Touched damage, glance and grab outcomes stay as in onTouched; only the presentation syncs. A swing that lands in reach emits a server ZombieSwing event at the contact time, used on the client for a whoosh and a camera impulse (A46).
Accept: Studio-lane frame-step capture: a chasing zombie swinging behind a stumbling player keeps its legs and hips on the run with no foot slide; the whoosh lands on the contact frame within one frame at 30 and 60 fps; tests cover the variant choice; all checks pass.
```

### A68. Client-side head look-at for skinned zombies
```
Milestone: M3. Size: M.
Context: ZombieAI.trackPlayerWithHead writes a Neck Motor6D found by ZombieRig.neck. On skinned rigs that motor does not exist (UpperTorso is a welded blocker), so state.neck is nil and zombies never look at the player; Aware zombies only rotate the root. The neck path still works on the R15 fallback rig, which ZombieFactory.build uses when ZombieRigs.get times out or a rig asset fails. Bone.Transform does not replicate, so this belongs on the client. ZombieAI keeps the mode in Lua state only.
Do: ZombieAI sets a ZombieMode attribute on every mode change. Add src/client/systems/ZombieLook.luau: for up to N nearest zombies in range in Aware or Alert mode, compute yaw and pitch to the local camera, spring-smooth and clamp them (60 degrees yaw, 25 degrees pitch), split them between the neck or head bone and the chest bone, and apply them as an additive rotation on Bone.Transform in PreSimulation after the Animator; fade out in Attack and Down. ZombieLook also drives the fallback Neck motor, after which the server neck path and its per-tick findNearestPlayer can go; otherwise keep the server path for the fallback rig. Math in ZombieAnimMath with tests.
Accept: clamp and spring tests are frame-rate independent (30 vs 144 fps within 10 percent); Studio-lane note: Aware zombies visibly track the player's head; no measurable client frame-time change with 60 alive; all checks pass.
```

### A69. Turn-in-place shuffle for aware zombies
```
Milestone: M3. Size: S.
Context: in ZombieAI.aiStep, Aware zombies turn by rewriting root.CFrame in smoothStep (faceOnly) at AWARE_TURN_RATE 60 deg/s while the idle clip plays, so the feet slide.
Do: while faceOnly and the remaining angle is above about 25 degrees, ZombieAnimator plays the walk move at a low rate matched to the turn speed, then returns to idle. Threshold and rate in ZombieBehaviourConfig.
Accept: Studio-lane frame-step: an Aware zombie turning 90 degrees steps instead of sliding; zombies that do not turn are unchanged; all checks pass.
```

### A70. Zombie footsteps timed from clip phase, per surface
```
Milestone: M2 (A23 depends on it). Size: L.
Context: no zombie footstep sound exists (no SfxConfig keys, nothing in ZombieAudio), yet A23 and T9 assume them. build_zombie_anims.py already finds the planted foot to compute each clip's groundSpeed but writes no contact times. Re-uploading clips with KeyframeMarkers would cost upload quota; contact phases in config need no upload. FootstepConfig and the AudioEngine classes already serve the player. The bone_rattle_01 and bone_rattle_02 zombie audio ids in AssetIds.audio.zombie are uploaded and referenced by nothing.
Do: make build_zombie_anims.py and retarget_ue.py write steps (left and right foot contact phases, 0..1) for every walk, run and crawl clip into clips.json, and copy them into ZombieSkins clip entries. ZombieAnimator sets a MoveClip attribute (the clip key) on the model when the move changes. The client reads the playing move track's TimePosition / Length for the N nearest zombies (priority behind the player) and, on each phase crossing, plays a zombie footstep chosen by the ground material under that foot (one raycast per step), with variants per surface and gait (shuffle, run, crawl drag). Use bone_rattle as a body layer on runs and falls, or remove those rows from the manifest. Source footsteps through the asset lane, three or more variants per surface family, and declare Low tier voice counts.
Accept: Studio-lane listen: a Runner closing from 40 to 10 studs behind an auto-running player is audible by its steps alone; steps land on visible foot contacts in a slowed capture; the SfxConfig voice caps hold; all checks pass.
```

### A71. Zombie vocals follow state: idle, chase, attack, pain, death
```
Milestone: M2 (A23 depends on it). Size: M.
Context: ZombieAudio.attachGrowl starts one loop per zombie for its whole life, with the same id and one random pitch, whether the zombie is Idle, Aware, Alert, Attack or Down, and keeps playing on a dead body until the model is destroyed. There are no pain or death vocals. ZombieAI keeps the mode in Lua state only. A23 covers pursuit mixing, not state variants.
Do: use the ZombieMode attribute (added by A68, or add it here if A68 has not landed). Add SfxConfig keys for idle breath, chase growl, attack snarl and pain grunt (three or more each) and death gurgle (three or more), sourced through the asset lane. In ZombieAudio crossfade the per-zombie loop by mode, play a pain grunt on a flesh hit (A53 entries) with a per-zombie cooldown, and on Down play a death gurgle and stop the loop. Respect the voice pools and class limits.
Accept: owner listen in a Medium run: idle, chase and attack zombies are distinguishable by ear; a killed zombie goes silent after its gurgle; voice caps hold; all checks pass.
```

### A72. Human victims for feeding tableaux
```
Milestone: M3, after A34. Size: M.
Context: ZombieAI.spawnCorpse builds ZombieFactory.build(pickConfig(), true), a Walker, Hazmat or Ghoul posed on a zombie death clip, plus a 7x7x0.05 SmoothPlastic Stain Part, and darkens it through BasePart.Color, which the SurfaceAppearance ColorMap overrides. Eating sleepers and feasts therefore read as zombies eating a zombie. D9 and Into the Dead's foreground storytelling call for a human or soldier victim.
Do: source a human or soldier corpse prop through the asset lane (licensed or generated; manifest row with source, licence and generator), static with its own surfaces and 2 or 3 pose variants. spawnCorpse picks a variant. Replace the Stain tile with a thin card carrying a blood splat decal (variants, random rotation and scale). The gore toggle hides the blood.
Accept: owner look pass on an eating sleeper and a feast; no zombie skin is used as a victim; budgets hold; all checks pass.
```

## Single-writer map

One task at a time per row. Everything else runs in parallel.

| Shared code | Writers, in order |
| --- | --- |
| WeaponService | T1, T3a, A53, T13, A66, A21 |
| WeaponController | A44, A52, A53, A56, A55, A54, A26, A49, A50, A41, A42 |
| DistanceTracker, RunEconomy | T2, T11, T3b |
| DeathService | T2, T4 |
| AmmoCrates | T2, T3a, A51 |
| Remotes | A47, A21 |
| ZombieAI | T9, T16, T20, A64, A47, A68, A69, A34, A66, A21, A67, A72 |
| ZombieAnimator | T16, A64, A34, A47, A69, A66, A21, A67, A70 |
| ZombieSkins | A22, A34, A68, A66, A67, A70 |
| ZombieFactory, ZombieHitboxes | A63, A66 |
| tools/zombie_pack and the zombie clips.json files | A65, A34, A21, A67, A70 (one bake at a time) |
| ZombieVfx | T17a, A51, T15, A54, A21 |
| ZombieAudio | T17a, A47, A70, A71, A67, A23 |
| WeaponVfx | T17a, A51, A52, T17b (split), T15, A24, A56, A25, A55, A54, A26, A60 |
| VfxConfig | A51, A52, T17b, A24, A56, A25, A55, A54, A26, A58, A59, A60, A61, A62 |
| ImpactDecals | A54, A26, A21, A59, A62 |
| GoreController, DeathGore, MotionVfx | A51, A54, A59, A57, A61, A62 |
| WorldVfx | A51, A58 |
| WeaponSfx, OwnGunshot class | T17a, A7b, A9, A53, A33 audio sessions |
| SfxConfig, SpatialAudioConfig, AudioBus | A7a, A8, A9, A70, A71, A23, A39 |
| CameraController, AimAssist, Stances | A44 |
| ExertionState, BodyMotionController | A44, A45 |
| CameraEffectsController, CameraConfig | A44, A45, A14, A46, A49, A41, A33 feel sessions |
| GlanceController, BreathingController | A44, A46 |
| DeathController | A59 (groundY only), A48 |
| Viewmodel, ViewmodelConfig, ViewmodelPackConfig, ViewmodelClipPlayer, PackViewmodel | A44, A45, A15, A16, A17, A18, A50, A49, A46, A48, A41, A43, A19, A32, A33 |
| BodyController, BodyRig, WorldWeaponModel | A60, A61, A62 |
| LightingConfig, LightingDirector | T15, A27, A30, A38 lighting sessions |
| ChunkFactory, DressingConfig | T15, A28, A29, A58, A38 material sessions |
| PostFx | T15, A31, A57 |
| SettingsConfig, SettingsGui | A14, T15, T7a, T7b |
| tests/camera, tests/vfx, tests/zombies run.luau | each task appends its own test group; rebase, never rewrite another group |
| docs/av/vertical-slice-bar.md | A4a, A4b, A4c (verdict rows are appended by any task) |
| assets/manifest.json and the generated files | the asset lane, one ingest at a time |

## Amendments to T briefs (apply when pasting the T brief)

- T2: owner step. The "non-Studio server" check needs a published private test. Studio-lane agents verify the clamp in Studio; the owner runs the live check.
- T3 splits in two. T3a: PerkEffects (new), PerkService, SkillEffects, PerksConfig, WeaponService, AmmoCrates, health and reload caps; accept is every perk except Sprinter measurable, reload multiplier >= 0.6, max health <= 180. T3b: the Sprinter speed path in DistanceTracker after T11, plus the caps table in wiki Run Economy.md. If T3a registers a client module in src/client/init.client.luau, it waits for T5.
- T1, T4: the live receipt and the non-Studio checks are owner steps.
- T7 splits in two. T7a gamepad and console menus (M3), including gamepad reachability of the existing credits panel in SettingsGui. T7b touch controls (M4).
- T9: read "running straight with no input" as "auto-running straight with no steering input". The game auto-runs, so this is D1's running player. No zombie footstep sound exists, so "keep footstep and growl audio" means the growl until A70 lands. Add an accept line: for every skin, difficulty and modifier, pursuit speed divided by the chosen run's groundSpeed stays within 0.8..1.7. Ground speeds: Walker run_ue 7.741, Hazmat run_ue 7.525, Walker run 12.015, Ghoul run 15.22 and run_b 20.706; MOVE_RATIO_MAX is 2.4. Keep the random single run per zombie (Decisions 2026-10-01: fitting by speed put the crowd in lockstep), but draw only from runs inside the band, and bake a faster Walker or Hazmat run where none qualifies: the Hazmat already fails at Medium (13.2 / 7.525 = 1.75). DifficultyConfig says Hard 1.15 today, not the 1.05 T9 proposes. Move the clip speeds into a pure data module so the band is testable with the luau CLI.
- T12 splits in three: T12a squad scaling, T12b spectate, T12c squad goal.
- T14: owner step for the MicroProfiler capture. T14 also fixes the server step cost method above.
- T15 moves to the first M2 sprint. It writes the light budget rule: at most 12 live PointLights on High with 6 chunks ahead, of which 2 are reserved for transient lights (muzzle flash, explosions) owned by A24. The muzzle light already exists (WeaponVfx buildMuzzleRig FlashLight on every muzzle rig) and is counted by nothing; A24 adds the TransientLights registry that it borrows from.
- T16: killed zombies are never pooled. ZombieAI.recycle destroys any model with Health <= 0 (the intact check) and a Humanoid in the Dead state cannot be revived, so "zero LoadAnimation calls per spawn" is unreachable as briefed. Disable the Dead state (Humanoid:SetStateEnabled), treat Health <= 0 as death in ZombieAI, and reset the killed model on recycle: health, unanchor, blockers, stop tracks. Cache Animation objects and tracks per pooled model. A per-skin pool is not needed: only ZombieAI.devSpawn (Studio only) passes a skinName.
- T17 splits in two. T17a: pools and client scans as briefed, with the scope widened to every per-event creator: WeaponVfx.tracer and WeaponVfx.impact (a Part per pellet), WeaponVfx.pickupBurst, ZombieVfx burst and the bloodAt BloodStain, GoreController spawnBlood, DeathGore spawnPool, spawnBurst and spawnGibs, and DroppedMagazines.drop (a Model clone per reload, MAX_MAGS 12, LIFETIME 30). A zombie death creates no VFX parts (the ZombieAI Stain belongs to spawnCorpse feeding scenes), so drop that premise. Add a distance and count cap for remote impacts and tracers in VfxConfig with High and Low values: a teammate's Shotgun shot creates up to 8 impact and 8 tracer Parts on every client today. T17b: split WeaponVfx (1133 lines) into muzzle, impact, casing and tracer modules behind the same facade, before A24; move the WeaponVfx constants (FLASH_VARIANTS, FLASH_CLASS_SCALE, FLASH_* colours and times, CALIBERS, CASING_*, TRACER_COLOR, the inline impact values) into VfxConfig with High and Low values; add a global active-emitter counter honoured by every spawn site (today only WorldVfx attachEmbers checks MAX_ACTIVE_EMITTERS); delete the dead exports burstSmoke, shellEject and shellLandMaterial.
- T20 moves to M2, right after T16 and before A20. A64 may fold into its ZombieFeeder extraction.
- T21: also strip the "never synthesized" and "generated speech is banned" wording from wiki Roadmap.md if the roadmap rewrite has not already done so. Wiki truth from the audit rerun: 34 zombie clips are uploaded (22 Sketchfab and 12 Fab UE, crawl_ue unused), not 22; the Hazmat dies on death_ue, so "A skin without a death clip (Hazmat) falls without one" in Gameplay Systems is stale; the "Corpse lure and feeding" paragraph claims a feeding clip and a procedural lean that do not run on skinned rigs, so reconcile it with the later fall-back camera paragraph in the same file.

## M1 Secure foundation

## Owner rules for every A-task (2026-10-12)

- D6 aim focus: hip fire stays the base. Holding aim pulls the weapon slightly toward centre, narrows FOV a little and calms sway. No full sight alignment.
- D7 arms: camo sleeves and gloves on every class.
- D8 reloads: separate clips and timing for empty, partly spent and almost full magazines.
- D9 visible state: nothing is generic. Presentation changes with state (ammo, health, speed, surface, distance, damage), the player can read state without the HUD, and every repeated event has variants. A brief that ships one clip, one sound or one texture where state differs is not done.

### A1. Align asset guidance with policy 2026-09-07 and record generator provenance
```
Context: docs/asset-policy.md (2026-09-07) allows generated audio, motion, models and textures. scripts/sync_needed.py still writes "Never synthesized" (hit and kill marker hints), "Never generated speech" (announcer hints) and "no synthesis" in the NEEDED.md header. The manifest has no field for the generator service or its terms.
Do: rewrite those hints and the header to match the policy, adding a generated option where it fits (announcer lines from a voice service with commercial terms, marker ticks). Add optional manifest fields "generator" and "terms" (service name and terms version or date); make scripts/sync_configs.py print them in assets/LICENSES.md. Studio MCP generate_* output is recorded as generator "Roblox AI (Studio MCP <tool>)" and terms "Roblox Terms of Use, <date read>"; do not claim ownership wording beyond what A3 confirms. Update wiki Assets Pipeline.md. Do not edit wiki Roadmap.md.
Accept: python3 scripts/sync_needed.py regenerates NEEDED.md with none of the old wording; a fixture manifest row with generator and terms renders in LICENSES.md (test in tests/credits/run.py or a new tests/ suite); every tests/*/run.luau and tests/*/run.py passes.
Est: 1 / 1.5 / 2.5 days.
```

### A2. Worktree setup that carries the gitignored Fab content
```
Context: .gitignore lists assets/fab/ and src/shared/fab/ with a trailing slash, which matches directories only. A git worktree lacks the Fab packs, and PackViewmodel loads viewmodel_clips then fab, so viewmodel work tested in a worktree falls back to the wrong rig. A symlink is a file to git, so a symlinked assets/fab would show as untracked and could be staged.
Do: add slash-less ignore patterns assets/fab and src/shared/fab next to the existing ones, and the same for any other gitignored local input the build reads. Add scripts/worktree_setup.sh <path> <branch> that creates the worktree and symlinks those inputs from the main checkout. Document it in wiki Development Policy.md.
Accept: a worktree made with the script passes rojo build; in Studio the rifle draws the Fab pack; git status --porcelain in the fresh worktree prints nothing.
Est: 0.5 / 0.5 / 1 day.
```

### A3. Generation capability probe and upload quota check
```
Context: the AV plan leans on Studio MCP generate_mesh, generate_material and generate_texture, and on about 40 audio uploads in M2. Neither has been checked in this Studio build or account.
Do (Studio lane, owner present for the account check):
- List the Studio MCP tools actually exposed. For each generate_* tool, make one throwaway asset and record whether the output gets an uploadable or persistent asset id, its resolution and format, and whether it carries alpha.
- Read the current Roblox terms for AI-generated content and record the exact wording that applies to ownership and commercial use; A1 cites it.
- Owner reads the account's audio upload allowance in the Creator Dashboard (30-day quota, ID verification state).
- If the quota is below the M2 need, write the fallback: pack variants into one file and play them as AudioPlayer playback regions.
Write the findings to docs/av/generation-capabilities.md. No production assets.
Accept: the document answers each question with a date; the M2 asset plan is marked feasible, or adjusted.
Est: 0.5 / 0.5 / 1 day.
```

### A4. Vertical slice quality bar (three sessions: A4a, A4b, A4c)
```
Context: M2 needs a checklist the owner can score in one playtest. Wiki Research AAA on Roblox.md holds a frame-by-frame TTK breakdown. Owner calls that shape the rows: D-AV2 (slice rifle pack, open), D6 aim focus (decided), D8 ammo-state reloads (decided), D9 visible state everywhere (decided).
Do: write docs/av/vertical-slice-bar.md, at most 30 rows in total, each tagged P0 or P1, each with a pass rule, the camera spot or listening spot, the reference (public video plus timestamp), the A-task that delivers it, and an empty verdict column.
- A4a: weapon feel and camera rows (draw, first raise, idle, sway, move tilt, fire, recoil and recovery, reloads tactical and empty, speed and glance-slow states (there is no sprint or jump input), wall pullback, bob, breath, shake, FOV kick, weapon surface quality).
- A4b: audio rows (close, mech, punch, tail, mid, far, impacts, casings, dry fire, low ammo, markers, zombie voices, pursuit audio, ambience, mix loudness).
- A4c: world, effects and HUD rows (City night lighting, fog, one warm accent, foreground detail, decals, muzzle, impacts, blood, zombie skin and wounds, hit reactions, deaths, grade, hit direction, HUD) and the capture list of fixed shots that A5 will script.
Sign-off waits for D-AV2. A4a includes rows for the aim focus (A41), the three reload states (A42) and the visible round count (A43).
Accept: the owner signs off the document; every row names its A-task; at most 30 rows.
Est: 0.5 / 0.5 / 1 day per session.
```

### A5. Capture harness
```
Context: before and after comparisons (A6, A27, T15 "High unchanged", A38) need repeatable shots.
Do: add a Studio-only capture mode (DevConfig switch, server gated by RunService:IsStudio()) that loads a named shot from a config module: camera CFrame, frozen ClockTime, fixed run seed and biome, scripted zombie poses and positions, weapon state. Drive it from Studio MCP and save screenshots under docs/av/captures/<set>/<shot>.png. Add docs/av/captures/ to .gitignore. Seed the shot list from A4c.
Accept: the same shot captured twice gives matching frames at a glance; switching the mode off leaves the run unchanged; no capture file is tracked by git.
Est: 1 / 1.5 / 2.5 days.
```

## M2 Vertical slice: City night, Rifle, skinned zombies

Order: T9, T15, T16, T17a and T17b come first in M2. A44 (camera rig composer) and A63 (client zombie hit boxes) come before any camera or zombie reaction task. A6 runs after T9 and A5. M2 also carries A45 to A56, A58, A59, A63, A64, A70 and A71; the other audit rerun tasks are M3.

### A6. Slice baseline capture
```
Depends on: A5, A4 signed off, T9 merged.
Do: in the Studio lane, take every A4c capture-list shot of the current build into docs/av/captures/baseline-2026-10/. Audio rows are not captured: the owner listens live and the verdict is written into the row, or the owner records at the OS level.
Accept: every capture-list shot has a baseline file; every bar row is marked pass, fail or unknown.
```

### A7. Weapon audio listening pass and legacy removal (two sessions)
```
Context: the spatial engine plays weapons behind SfxConfig.WEAPONS_ON_ENGINE (default true). The listening pass is docs/audio/spatial-audio.md section 6 plus the checks in wiki Weapon Audio.md. The v6 gunshots are still waiting for a listen. The legacy Sound-pool branches live in WeaponSfx and SandboxWeaponGallery.
A7a (Studio lane, owner present): listen at the range, an interior room and the sound lane; tune shotVolume, the sub, duck depth and the tails in config only.
A7b (after owner approval): delete the legacy branches, the switch and dead helpers; keep the tests/audio math tests.
Accept: approval recorded in wiki Weapon Audio.md and the bar; grep finds no WEAPONS_ON_ENGINE; luau tests/audio/run.luau passes; gunshots audible from all three spots.
```

### A8. Audio mix master
```
Context: AudioBus already builds an AudioLimiter from SpatialAudioConfig.LIMITER. There is no loudness target per bus and no combat state, so every new asset drifts.
Depends on: A7a.
Do: set an integrated loudness target per bus (weapons, impacts, zombies, ambience, UI, music) and record the measured value of the current assets with the loudness method; confirm the limiter and compressor settings; add a combat mix state (ambience and music down, weapons and zombies up, with attack and release) driven by recent fire and pursuit count. Config in SpatialAudioConfig or SfxConfig.
Accept: a table of target and measured loudness per bus in wiki Weapon Audio.md; the combat state is audible in an owner A/B listen; no clipping at the limiter in 60 s of sustained fire with 30 zombies.
```

### A9. Mech, punch, dry-fire and magazine handling layers (Rifle)
```
Verify first: no mech or punch layer exists in WeaponSfx or the OwnGunshot class; which dry-fire and magazine sounds exist; the low-ammo layer already ships (wiki Roadmap Done list).
Depends on: A7b.
Do: add a mechanical action layer (bolt and receiver) and a low transient punch layer for the Rifle, a dry-fire click on an empty trigger pull, and magazine out, in and tap foley on the reload markers; keys in WeaponsConfig or SfxConfig, played through the engine class with its jitter. Source from FFSL recordings or generate. Other classes follow in A33.
Accept: owner A/B listen with the layers on and off; the per-volley cap and duck behaviour unchanged (tests/audio); each layer within 3 LU of its target in the A8 table.
```

### A10. Bullet impact and ricochet audio (asset lane)
```
Context: audio/weapons/impact_{concrete,dirt,flesh,metal,wood}_{01,02} and ricochet_01 are needed; Kenney stand-ins play today. WeaponSfx.playImpacts routes by material family.
Do: source at least 3 variants per family (asset policy audio gate): freesound CC0, Sonniss GameAudioGDC, or generated with terms recorded per A1. If A3 found a tight quota, pack the variants per family into one file with playback regions. Normalise within the class; manifest, upload, sync_configs, sync_needed. Extend the variant table if a third variant needs a key.
Accept: integrated loudness of every family within 3 LU of the others; owner listen in the yard on concrete, dirt, metal, wood and zombies; LICENSES.md lists every file; the slots are gone from NEEDED.md.
```

### A11. Distant gunshot layers (asset lane)
```
Context: audio/weapons/mid_* and far_* (8 slots) feed WeaponSfx.playDistantShot (mid 40..350, far 250..1400 studs). The NEEDED.md hints name FFSL Prepared rows cut with tools/audio_build/build_shots_v6.py.
Do: cut all 8 takes with build_shots_v6.py from FFSL, or generate them; manifest, upload, sync. Add a Studio-only test script that fires a dummy remote shooter at 30, 200 and 600 studs from the player, since MCP playtests are solo.
Accept: with the dummy shooter, the rifle reads as near, mid and far at the three distances in an owner listen; the switch points match the config ranges.
```

### A12. Hit marker, kill marker and range gong sounds (asset lane)
```
Context: audio/ui/hit_marker and kill_marker are needed (HitMarkers stays silent until filled, wiki Hit Markers.md); audio/range/gong was rejected by moderation.
Do: source or generate a short tick, a kill confirm and a steel gong; manifest, upload, sync. Config only beyond that.
Accept: markers audible on confirmed hits only; the gong plays at the desert range; moderation approved after refresh_status.py.
```

### A13. City ambience and sirens (asset lane)
```
Context: audio/ambience/city_bed and audio/city/siren_ambulance are needed; the police siren was rejected. MapAmbience crossfades beds at map boundaries.
Do: source or generate the City bed (burning city at a distance: far sirens, wind, fire crackle, no music, no voices) and two siren variants; manifest, upload, sync.
Accept: the bed plays in the City and crossfades at the boundary; within 3 LU of the ambience bus target; owner listen.
```

### A14. Living camera
```
Depends on: A44, A45; A23 for the pursuit set.
Context: CameraEffectsController already has a stride-locked bob that reads ExertionState.getStridePhase(), the same clock whose pi crossings fire ExertionState.onStep for FootstepController, PlayerSfx and MotionVfx. It has an exertion-scaled breath (breathFrequency from BREATH_FREQUENCY_CALM to BREATH_FREQUENCY_EXERTED, breathScale 0.6 + exertion * 0.9), an idle sway, lateral tilt, a speed and adrenaline FOV, fovKick, a shake spring and a recoil spring (ViewmodelConfig.cameraRecoil stiffness 70, damping 17). FootPlanting is R15 foot IK that runs only outside a mission and emits no events. The visible faults are the effect feedback through the base lerp, which makes the recoil recovery the 12/s lerp rather than the spring (A44), and the bob phase and period (A45). Adrenaline is chase = 1 when the Workspace attribute ZombiesAggro is true in a mission; on Medium and Hard aggroDistance is 0, so ZombiesAggro is true from the first AI tick and adrenaline is a constant +4 FOV that says nothing (only Easy flips it, at 300 studs). CameraConfig.INTENSITY is a constant that does not scale recoilPitch, recoilYaw, fovKick or any viewmodel motion, and SettingsConfig has no camera option.
Do: once A44 and A45 land, tune the layers on the clean base. Drive adrenaline from pursuit pressure: the nearest chasing zombie's distance and the count behind the player, from the pursuit set A23 exposes (or the same query if A23 has not landed), with the curve in CameraConfig, feeding FOV, breath rate and sway. Add a cameraMotion setting (0 to 1) in SettingsConfig (comfort) that scales bob, breath, sway, shake, the A49 handling layer, FOV kicks and the viewmodel bob and drift. Pure math in CameraRigMath with numbers-only Luau tests.
Accept: the bar's camera rows pass in owner review; frame-rate independence test passes; at cameraMotion 0 the camera equals the base every frame; adrenaline changes with pursuit distance on Medium; all checks pass.
```

### A15. Procedural weapon motion layer
```
Depends on: A44.
Context: Viewmodel.updateChannels already has look sway and lag (swayRot and swayPos impulses from the per-frame camera delta, lagRot from a 3-frame history), juke impulses on lateral input, tiltRoll, driftRot, aimRot, stride bob, breathe, a landing impact (Viewmodel.trackImpact, scaled by fall speed) and recoil springs, plus the Stances high and low ready poses that already give a raise-before-fire delay (StanceConfig.raiseTime per class, Stances.requestFire, raisePending in WeaponController.tryFire) and WallPullback. The player has no look input (CameraController always looks along RUN_DIRECTION), so the sway mostly reacts to the camera's own cosmetic layers. There is no sprint (the game auto-runs at 24..30 studs/s; ViewmodelConfig.sprint is applied only on the legacy ViewmodelBuilder path in Viewmodel.step, never in stepPack) and no jump (InputController binds only A/D and arrows; FlowService sets JumpHeight 0), so the TTK rows for free-look sway, sprint in and out and jump do not apply as written. ViewmodelConfig.lag.frames = 3 gives 100 ms of lag at 30 fps and 21 ms at 144 fps. Recoil is identical shot to shot: CameraEffectsController.recoil adds kick * cameraRecoil.pitch plus a uniform random yaw, Viewmodel.onFired uses random recoilPos and recoilRot impulses, there is no pattern over shot index (WeaponController.burstShots only feeds barrel smoke), and recoilPitch ignores CameraConfig.INTENSITY. WallPullbackConfig.pose is one table for all classes (only reach is per class).
Do: in Viewmodel and ViewmodelConfig: replace the frame-count lag with a time-based critically damped spring (lag time in seconds); feed sway and lag from CameraController.getBase() with the aim pull (A44) so cosmetic layers stay out of the sway input; tune juke tilt and the raise-before-fire stances per class; add a per-class recoil profile (pitch and yaw curve over shot index, a kick spring separate from the recovery spring, a first-shot versus sustained difference, scaling by the A14 comfort setting) with the shot index fed from WeaponController; make WallPullbackConfig.pose per class with a default. One config table per class, Rifle tuned here, the other classes in A33. Stances and Wall Pullback keep priority. Springs that a test needs live in a numbers-only module.
Accept: the bar's sway, recoil and stance rows pass in owner review; frame-rate independence test passes for the lag and recoil springs; a 10-round Rifle burst shows a learnable kick shape; all checks pass.
```

### A16. One arm set (Rifle)
```
Context: black camo sleeves and gloves on the AK, pistol and shotgun packs, a bare forearm with a watch on the SMG. Owner decision D7: camo sleeves and gloves on every class, so the SMG arms are the ones to replace.
Do: re-skin or swap the arm meshes so the rifle pack uses the chosen set (tools/arms_rig pipeline, SurfaceAppearance colour, normal and roughness), through the asset lane. Other classes in A33.
Accept: rifle arms match the chosen set in the yard and on the run; no wrist seam at the cuff during either reload (frame-step capture).
```

### A17. Rifle clip polish and seam check
```
Depends on: A16.
Context: the asset policy gate requires FadeTime >= 0.15, seamless loops, Transform written after the Animator pass and marker-driven audio. Owner decision D8: reload timing follows the ammo state (A42), so this task only makes the existing clips seamless. The Rifle pack loads Fab M4Clips: Idle, Walk, Fire, Reload, ReloadEmpty, Draw and Holster (no sprint or run clip).
Do: run the gate on every rifle clip in M4Clips in the yard; fix fades, seams and marker timing in ViewmodelPackConfig and ViewmodelClipPlayer.
Accept: frame-step captures show no bone pops; reload foley lands on its markers; the empty reload decision is in wiki Decisions.md.
```

### A18. First raise
```
Depends on: A17.
Context: the Rifle pack loads Fab M4Clips (Reload, ReloadEmpty, Fire, Holster, Draw, Idle, Walk); neither it nor the unused RifleClips has an inspect or first-draw clip. Fire gating is time-based: WeaponController.tryFire returns while Viewmodel.drawElapsed() < config.drawTime.
Do: on the first equip per life, play a first raise as a Luau-authored pose sequence through AnimationSequencer layered on the Draw clip (or Draw slowed with an added look at the weapon), with its own longer draw time for that equip only; later equips use the normal draw and the A50 equip variants. Data in ViewmodelPackConfig. The authored pose goes through the asset policy look pass.
Accept: visible on the first rifle equip after spawn and after Continue, never on swaps; fire blocked until the first-raise draw time ends; owner look pass.
```

### A19. Rifle surface pass
```
Context: the TTK benchmark names weapon textures. A16 covers arms only. WeaponVfx casings are two cylinder Parts with Metal material that live CASING_LIFETIME 3 s, so sustained fire leaves no brass on the ground.
Do: give the slice rifle a SurfaceAppearance set (colour, normal, roughness, metalness) with edge wear and a light grime pass, made in Blender or a licensed texture set; ingest through the asset lane. No change to the mesh or rig. Replace the casing cylinders with a brass mesh with SurfaceAppearance, and raise the settled-casing lifetime on High under the casing pool cap so brass piles up where the fight happened.
Accept: owner look pass in the yard at the bar's weapon spot under day and City night lighting; textures within the memory note in wiki Performance.md; brass stays on the ground after a magazine on High; InstanceCount flat.
```

### A20. Zombie directional flinch
```
Depends on: T20 (ZombieAI split), T16, A53, A63.
Context: ZombieAnimator.hit only reacts on skins with a hit clip (the Ghoul), returns when speed > HIT_MAX_SPEED (4) or while attacking, and restarts the clip on every HealthChanged with no cap. A chasing Ghoul runs at about 9.6 to 12 studs/s on Medium, so it never flinches in a chase; Walker and Hazmat have no hit clip. hit() is called from Humanoid.HealthChanged in ZombieAI buildModel without direction or region. A53 puts the model, part and zone on each hit; the direction comes from the Shot origin and the hit position.
Do: rewrite the flinch as a client-side reaction. A client ZombieReactions module applies a spring-damped additive rotation to the bone that drives the hit box (ZombieSkins head, chest, hips and limbs[name].from) in PreSimulation after the Animator. Direction from the shot vector in the zombie's space, magnitude from damage and weapon class, 3 or more variants from a randomised secondary axis and delay, a per-frame budget (for example 8 zombies) and a distance cutoff. Keep the Core-priority base idle track keying every bone each frame so the additive never accumulates. The local shooter's reaction comes from prediction (valid after A63), remote shooters' from the Shot event. Heavy hits (headshot, close shotgun) add an upper-body stagger clip baked with the leg bones unkeyed (A34 and A67 tooling), so the run continues underneath. Remove the HIT_MAX_SPEED gate and the per-tick restart. Server rules unchanged.
Accept: owner look pass at 10 and 40 studs on Walker, Hazmat and a chasing Ghoul; the server step cost for zombies is unchanged (T14 method); client frame time within noise with 60 alive; all checks pass.
```

### A21. Zombie death with impulse
```
Depends on: A20, A53, A54, T17a pools, T18 (remote hardening merged).
Context: killed zombies are never pooled. ZombieAI.onDied anchors the root in place the same frame (root.Anchored = true), so a sprinting Ghoul stops dead; ZombieAnimator.playDeath picks a death clip with rng; the clip is held for GameConstants.ZOMBIE_CORPSE_LIFETIME 2 s, then ZombieAI.recycle destroys the model in one frame because a killed humanoid fails the intact check. Skinned zombies are bone-deformed MeshParts and Bones have no physics, so client physics could only tumble the whole body. Directional deaths exist: Walker death_back, death_forward and death_ue; Hazmat death_ue; Ghoul death_back and death_forward. A longer server hold is not a free substitute: recycle is the only place aliveCount goes down, so a held corpse cuts the spawn budget.
Do: choose the death in a pure ZombieReactionMath util from the last hit's direction relative to the zombie's facing (front, back, left, right), the region (head means collapse) and the speed. A zombie above half its run speed falls forward, and the server carries its root along the heading with decaying velocity for about 0.4 s before anchoring. On death the server fires one server-to-client event with the zombie id, hit position and impulse; the client builds a pooled local corpse clone by copying each Bone.Transform, lets it outlive the server destroy, places an A54 blood pool under it by a downward raycast (gore gated), then sinks and fades it under a client cap with High and Low values. Bake more Mixamo deaths (front, back, left, right, headshot collapse) for Walker and Hazmat with the A34 tool, and for the Ghoul after A65. A proxy-part ragdoll (hit-box segments plus BallSocketConstraints writing Bone.WorldCFrame) stays a later option. Hiding the head on a head kill is not possible on skinned zombies (Head is an invisible hitbox following a Bone, and Bones cannot scale); record that in wiki Gameplay Systems and leave a separate head mesh to A22.
Accept: owner look pass; no corpse disappears in a single frame; deaths follow the hit direction (test); no synchronised deaths (test); aliveCount unchanged by the client clone; InstanceCount flat; the server step cost target still holds.
```

### A22. Zombie skin and wound materials
```
Depends on: A53 (region), A63.
Context: Walker and Hazmat have full rebuilt PBR templates. ZombieSkins.Ghoul has no surfaces table and assets/zombies/sketchfab/textures has no Ghoul maps, so the Runner renders with the importer's material, which misreads metalness (Decisions 2026-10-10). Every Walker-skin zombie shares the walker_body template, and SurfaceAppearance.Color, which scripts can write, is never set. No wound or blood-state templates exist and nothing reacts to remaining health. ZombieAI.spawnCorpse darkens BasePart.Color, which the ColorMap overrides. A headshot changes damage, credits, the marker colour and DamageNumbers only. The Hazmat head is a separate MeshPart (ZombieSkins.Hazmat.surfaces ZombieHead) that nothing uses.
Do: (1) extract the Ghoul surfaces with extract_surfaces.py into SurfaceTemplates like the other two; (2) per spawn, jitter SurfaceAppearance.Color and pick from two or three grime and blood ColorMap variants per skin; (3) swap the wound state as a whole pre-built template (clean, bloodied, heavy) when health crosses 66 and 33 percent, cloned as SurfaceTemplates.dress does, since the maps are PluginSecurity; (4) client-side blood-drip emitters parented to the hit bone (a Bone is an Attachment), capped; (5) tint corpses through SurfaceAppearance.Color; (6) headshot read: the head-snap flinch (A20), a larger burst (A26) and a cracked visor template on the Hazmat's first head hit. No Decals for wounds: verify in Studio, but they project on the MeshPart and do not follow skinning. The gore toggle governs the wound templates, the drips and the blood variants.
Accept: owner look pass at 10 and 40 studs for all three skins; repeated Walkers look different; gore off removes every wound; ingest through the asset lane.
```

### A23. Pursuit audio behind the player
```
Depends on: T9, T17a, A70, A71.
Context: no zombie footstep sound exists: no SfxConfig keys, nothing in ZombieAudio, no footfall markers in the baked clips. ZombieAudio has one looping growl per zombie (AudioConfig.ZOMBIE_GROWL_ID, pitch randomised once at 0.55 to 0.85), idle moans, alert barks, bites and the horde walla. A70 adds footsteps and A71 state vocals.
Do: pick the nearest N chasing zombies behind the player as the pursuit set and guarantee their footsteps (A70) and chase vocals (A71) within the voice caps in SfxConfig, with distance-driven intensity and a rear-hemisphere mix bias. Expose the pursuit set (nearest distance, count behind) for A14's adrenaline.
Accept: in a Medium run, auto-running straight with no steering input, the owner can tell by ear that a Runner closes from 40 to 10 studs; voice caps respected.
```

### A24. Muzzle flash and muzzle light (Rifle)
```
Depends on: T17b, T15 (light budget), A3, A51.
Context: a muzzle light already exists. WeaponVfx buildMuzzleRig creates a PointLight named FlashLight on every muzzle attachment; muzzleFlash turns it on for FLASH_LIGHT_TIME (0.04 to 0.06 s) at VIEWMODEL_LIGHT_BRIGHTNESS 1.2 or FLASH_LIGHT_BRIGHTNESS 3.5, range FLASH_LIGHT_RANGE 12 times sqrt(scale), and nothing counts it against a budget. The muzzle "pool" is a per-attachment cache (muzzleRigs plus pruneMuzzleRigs). VfxConfig holds no weapon effect data until T17b moves the WeaponVfx constants there.
Do: author flipbook sheets for the rifle muzzle flash front and side views, rendered in Blender to a grid sheet (2x2, 4x4 or 8x8, at most 1024 px, alpha) or taken from a licensed pack; Studio generate_texture only if A3 showed it produces alpha sprite sheets. Add a TransientLights registry with 2 slots on High and 1 on Low (local weapon first, then the nearest teammate); the existing FlashLight borrows a slot and is retuned, and later explosion lights use the same registry. Wire through the VfxConfig surface from T17b; keep the muzzle rig cache and the casing pool.
Accept: the bar's muzzle row passes in owner review; live PointLights never exceed the T15 budget; InstanceCount flat.
```

### A25. Impact puffs and sparks
```
Depends on: A52, A24 (same module family), T17a pools.
Context: no impact pool exists today: WeaponVfx.impact creates a Part (makeGhostPart), an Attachment and 1 or 2 ParticleEmitters per hit and destroys them after 0.8 s, so a Shotgun shot creates 8. No emitter budget covers impacts: VfxConfig.MAX_ACTIVE_EMITTERS is checked only in WorldVfx attachEmbers. A52 fixes the orientation, the material families and the gore gate.
Do: flipbook impact puffs per family on the A52 profiles (concrete chips and dust, metal sparks with no dust, wood splinters, dirt clods, a water splash), same sourcing rule as A24, emitted from pooled impact anchors (T17a), with every emit counted by the global active-emitter counter from T17b.
Accept: the bar's impact rows pass; the emitter counter never exceeds its cap; InstanceCount flat.
```

### A26. Blood mist
```
Depends on: A25, A53, A54; A21 for the corpse.
Context: bullet blood on zombies is the dark-red puff in WeaponVfx.impact's Flesh branch, reached from WeaponController.drawShot; ZombieVfx.bloodAt is only used for the local player's own bite damage (GoreController.watchCharacter). So A26 belongs in the WeaponVfx family, after A25. The client has no per-hit type until A53 adds zone and killed per hit. A52 adds the gore gate. A zombie kill spawns no client effect today.
Do: blood mist flipbook for body and head hits in the WeaponVfx family, sized and shaped per zone; a pooled kill burst when killed is true (head kill: an upward mist plus droplets; body kill: a chest burst along the shot direction); an A54 blood splat behind the zombie from a short raycast past the hit. Everything gated on bloodEnabled.
Accept: the bar's blood row passes; a headshot reads differently from a body hit with the HUD hidden; gore off shows none; InstanceCount flat.
```

### A27. City night lighting
```
Depends on: T15, T14 baseline. Open owner call: whether ClockTime keeps sweeping inside map boundary blends.
Do: retune the City night preset (Atmosphere, ColorCorrection, Bloom, sun and moon, one warm accent per chunk) against the A5 shots. Config plus LightingDirector only; no new PointLights. The fire-barrel strobe is fixed in A58.
Accept: before and after captures for the City rows; owner look pass; FogBudget test passes.
```

### A28. City decals and materials
```
Context: decals still to upload and the biome strip's 25 shots are open (wiki Environment.md). Of the 15 DecalsConfig keys, AssetIds.texture.decal holds ids for only 6 (asphalt_patch_a and b, graffiti_a to c, leak_streaks); blood_trail_a, blood_pool_a, road_crack_a, oil_stain_a, scorch_a, tyre_marks_a, crosswalk_worn, manhole_a and lane_arrow_worn are absent, which the DecalsConfig resolver treats like 0. Dynamic hit decals are A54, not this task.
Do: fill the City decal and material gaps (Megascans pipeline, generate_material if A3 confirms it, ambientCG pattern); ingest through the asset lane; respect DressingConfig budgets.
Accept: the City biome strip shots captured; ChunkBudgetCounter within budget; every new asset in the manifest.
```

### A29. City hero props (cap 3)
```
Do: generate or model up to 3 City foreground hero props (generate_mesh or Blender, GLB to Open Cloud per tools/cube3d/README.md), placed through DressingConfig.
Accept: owner look pass in the City shots; budgets hold; manifest rows carry generator and terms.
```

### A30. Night run colour grade
```
Depends on: T15, A27.
Context: per-map and per-night grading already exists. LightingConfig presets (City, CityNight and every biome's Night variant) carry gradingContrast, gradingSaturation, gradingTint, bloomIntensity and bloomThreshold, and LightingDirector blends them through its own ColorCorrectionEffect on a phase or night change. PostFx owns a second ColorCorrectionEffect (TFZ_EventGrading) for damage, low health and death, plus the Bloom instance whose values it copies each frame from LightingDirector.getCurrent(). A grade added in PostFx would stack a third layer.
Do: per-phase colour grade for the City night run as LightingConfig preset data blended by LightingDirector; PostFx stays event grading only.
Accept: owner look pass against the A5 shots; Low tier keeps or drops it per T15.
```

### A31. Hit direction indicator
```
Depends on: A47 (PlayerDamaged), T15.
Context: no server damage event exists today: player damage is humanoid:TakeDamage in ZombieAI's catch path, and the client only sees Humanoid.HealthChanged. A47 adds PlayerDamaged with the source position. On Medium and Hard every damaging contact kills, so the damage indicator serves Easy; PlayerGlanced(side, power) reaches every difficulty and carries a side.
Do: a direction indicator around the crosshair, in PostFx and config driven, from PlayerDamaged (bearing of the source) and from PlayerGlanced (side); gore toggle still governs blood overlays.
Accept: owner look pass; the direction is correct for hits from four sides on Easy and for left and right glances in a Studio test.
```

## M3 Scale presentation

### A32. Known viewmodel clip defects
```
Context (wiki Progress.md): SMG ReloadEmpty magazine and rounds jump at 0.207..0.216; SMG Equip right hand and gun step at frames 18-19; shotgun shell bone slides at the loop seams.
Do: fix the keyframes or mask the joints in the clip data; verify frame by frame in the yard.
Accept: frame-step captures show no jump, step or slide.
```

### A33. Class parity (nine sessions: Pistol, SMG, Shotgun, each in three groups)
```
Context: M2 brought the Rifle to the bar.
Run per class, one group per session:
- Look: arm set (A16 method) and surface pass (A19 method).
- Feel: clip gate (A17 method), first raise (A18 method), weapon motion tuning and the per-class recoil profile (A15 config table), handling camera entries (A49 table), inspect and holster (A50).
- Sound and effects: mech, punch, dry-fire and magazine layers (A9 method), muzzle flash (A24 method) with the per-class flash set (A56).
Accept: the bar's weapon rows pass for the class in owner review; class tests pass.
```

### A34. Zombie rise, feed, scream and grab clips on the skinned rigs
```
Context: the Mixamo sources are already in tools/animation_pipeline/input (zombie_stand_up_back, zombie_stand_up_stomach and zombie_biting_ground, as .dae and .fbx; two stand-up variants, not three), and their R15 bakes are uploaded (AssetIds.animation.zombie.stand_up_back, stand_up_stomach and biting_ground), but those drive only the R15 fallback rig. ZombieAnimator.setupSkinned never sets tracks.rise or tracks.feeding, so holdLying and hasFeedingClip are false for every run zombie. retarget_mixamo.py writes R15 through Blender, the wrong tool. The bone-rig path is tools/zombie_pack: build_zombie_anims.py bakes KeyframeSequences against roblox_bones.json, and retarget_ue.py already holds the MIXAMO and BIPED maps (the Hazmat is a Mixamo skeleton). build_zombie_anims.py defaults --src to ~/Downloads/zombie_packs, which does not exist; the rig sources are assets/zombies/sketchfab/source (walker_rig.glb, hazmat_rig.glb, ghoul_rig.glb), and the UE retarget clips.json lives in the gitignored assets/fab/animation/zombie. The Hazmat already dies on a clip (AssetIds.animation.zombie_fab.hazmat.death_ue). Only the Hazmat has a spotted reaction; Walker and Ghoul go straight from idle to the run. The risers and feast patterns are in no patternSet, and every ZombieSpawnConfig section uses patternSet Corridor ({ single = 1 }), so wall, diagonal, column, clump, loiter, risers and feast never run; live sleepers come from per-section lyingChance (difficulty tier 3 ramps it to 0.3) and eatingChance through spawnAtSlot. Dormant zombies wake at section.standUpDistance (160 for tiers 1 to 3, 140 for tier 4, 120 for tier 5) while zombies spawn at ZOMBIE_SPAWN_AHEAD 200 and night fogEnd is 70 to 180, so a rise plays 1 to 2 s after spawn, mostly in the fog; formations.dormantWakeFraction and feedingWakeFraction are read by nothing. No owner download is needed, except optional Mixamo Zombie Scream and grab or bite clips. The Ghoul needs A65 first; Walker and Hazmat do not.
Do: add a Mixamo source mode to the retarget (mixamorig:* source bones mapped to the same keys as Manny). Bake rise_back, rise_stomach and feed for Hazmat and Walker into assets/animation/zombie_sf/<skin>/ with clips.json entries, an upper-body scream or lurch one-shot for Walker and Ghoul, and, if downloaded, a grab or bite for A47. Run the asset policy gate (loop seam for feed, FadeTime >= 0.15, ground contact in frame-step captures), then ingest: manifest, upload_assets.py, sync_configs.py, LICENSES.md (Mixamo terms). Add optional ZombieSkins slots rise, feed and spotted; setupSkinned loads tracks.rise (Action3) and tracks.feeding (Action2, looped), so holdLying, playRise, hasFeedingClip and playFeeding work on skinned rigs. Play the scream on the Idle or Aware to Alert transition, capped to a few zombies at once. Make the wake distance a short, config-driven, tested range (about 20 to 45 studs, tuned with the owner against D1) and wire or delete the dead wake fractions. Owner call: add risers and feast to Corridor, point some sections at Formations, or delete the dead patterns. Fix the --src default.
Accept: in a Medium City run Dormant Walker and Hazmat zombies lie on the ground and stand up inside readable range; eating sleepers and the death-ring feeders play the biting loop without seams; Walker and Ghoul react on alert; no manifest slot used is needed or placeholder; selene, validate_api, the comment check and rojo build pass; wiki Assets Pipeline and Gameplay Systems updated.
```

### A35. Third-person locomotion clips
```
Owner step: the Mixamo downloads in docs/animation/third-person-locomotion.md.
Do: retarget, ingest, sync; the yard gallery adopts clipSetFor.
Accept: in the yard gallery and in a dummy-teammate test, the class sets play with no fallback.
```

### A36. HUD and marker pass
```
Depends on: T7a.
Verify first: the current HUD element list and font sizes.
Do: restyle the run HUD to a minimal MW2019-level layout (ammo, credits, goals, squad) with UiTheme type tokens.
Accept: owner look pass at 16:9 and 4:3; smallest text meets the UI text size method.
```

### A37. Upgrade announcer lines (asset lane)
```
Context: audio/upgrade/announcer_upgrade_01, _02 and announcer_max are needed; the policy now allows a generated voice with commercial terms.
Do: source or generate the three lines; ingest; within 3 LU of the UI bus target.
Accept: lines play at the upgrade station; owner listen.
```

## M4 Every biome, every platform

### A38. Biome presentation pass (twelve sessions: Forest, Wasteland, Farmstead, Cornfield, each in three groups)
```
Run per biome, one group per session: lighting (A27 method), decals and materials (A28 method), ambience bed (A13 method; forest, wasteland and farmland beds are needed slots).
Accept: the bar's world rows pass for the biome; the bed crossfades at the boundary.
```

### A39. Low tier audiovisual budget
```
Depends on: T15 and the M2 to M4 AV content.
Context: the weapon VFX High and Low values come from T17b; WorldVfx re-rates its continuous emitters live only after A58.
Do: on Low, reduce AudioEngine voice pools and reflection rays, flipbook resolution and emitter rates, decal counts; keep pursuit audio and markers intact.
Accept: Low tier frame time beats the T14 baseline in the phone emulator; the pursuit cue is still audible.
```

## M5 Public test readiness

### A40. Placeholder release gate
```
Context: asset policy rule 5 says refresh_status.py should fail a release while placeholders remain; NEEDED.md "Used by" is prose, so there is no slot-to-system data.
Do: add a "system" field to manifest rows (populated for needed and placeholder rows first); add --release to scripts/refresh_status.py that exits non-zero on any placeholder row and on any needed row whose system ships; add it to CI as a manual job.
Accept: a fixture with one placeholder fails; the current manifest prints the exact list.
```

## Backlog (not scheduled)

- Run music intensity layer and stingers (stem sync on AudioPlayer, generated music licence).
- Low-health heartbeat audio and duck. The desaturation and vignette pulse already ship in PostFx.
- City hero props beyond 3.
- Teammate revive, only if game design adds it.

## Draft to final ID map

| Draft | Final | Change |
| --- | --- | --- |
| A1, A2 | A1, A2 | A2 gains the ignore fix |
| A3 | A4a-c | split in three, capped at 30 rows |
| A4 | A6 | needs A5 harness and T9; audio rows live |
| A5 | A7a, A7b | |
| A6, A7, A8, A20 | A10, A11, A12, A13 | asset lane; A11 uses a dummy shooter |
| A9 | A9 | gains dry-fire and magazine foley; after A7b |
| A10 | A14 | premise fixed: bob exists |
| A13, A12, A11 | A16, A17, A18 | reordered: arms, clip gate, first raise |
| A14 | A20, A21 | split; client-local corpse clone |
| A15 | A23 | accept reworded |
| A16 | A24, A25, A26 | split; flipbook sourcing changed |
| A17 | A27 | after T15 |
| A18 | A28, A29 | split; props capped at 3 |
| A19 | A30, A31 | heartbeat to backlog |
| A21 | A36 | moved to M3 after T7a |
| A22-A25 | A32-A35 | A33 split into nine sessions |
| A26 | backlog | |
| A27, A28 | A38, A39 | A38 split into twelve sessions |
| A29 | dropped | the credits panel already exists |
| A30 | A40 | gains the "system" field |
| new | A3, A5, A8, A15, A19, A22, A37 | probe, harness, mix master, weapon motion, rifle surfaces, zombie materials, announcer |

## Rejected review notes

1. Teammate revive in the T12 split: rejected. The T12 brief scopes squad scaling, spectate and a squad goal; revive is a design addition, and Continue is the only revive today. T12 splits into scaling, spectate and squad goal. Revive sits in the backlog for game design.
2. "A15 no input contradicts D1": the conclusion is rejected, the wording fix is kept. The game auto-runs, so a player giving no steering input is a running player, which is exactly D1's case. The accept now says "auto-running straight with no steering input" so nobody reads it as standing still.
3. "Fold A28 into T15 or run it right after": the placement is rejected. Tuning Low tier budgets for VFX and audio that M2 is about to replace would be done twice. T15 keeps its own Low tier rates for today's effects; every new AV task declares its Low value in config (rules block); A39 tunes the whole set in M4.
4. "A21 and A29 depend on T7 gamepad": half accepted. The HUD pass (now A36) waits for T7a. The credits panel (draft A29) is already built (wiki Credits.md, src/shared/config/CreditsConfig.luau, tests/credits), so the task is dropped and its gamepad reachability joins T7a's accept list.
5. The rationale for A21 ("replication overwrites client Motor6D changes") is not adopted: Motor6D.Transform does not replicate, as the stage report already notes. The spec it led to (a pooled client-local corpse clone driven by a server-to-client death event) is adopted for another reason: the server recycles pooled rigs, so a death effect has to outlive the server model. Correction from the audit rerun 2026-10-12: killed zombies are not pooled, they are destroyed 2 s after death (ZombieAI.recycle fails the intact check). The client clone still stands, because it outlives that destroy without keeping the corpse in aliveCount.

## Audit rerun 2026-10-12

The camera, VFX and zombie animation audits were rerun and verified against the code. What changed:

Briefs corrected (premise rewritten, id kept):
- A14: FootPlanting emits no events and runs only outside a mission; the bob already reads the stride phase; breath and the recoil spring already exist. The real faults are the effect feedback (A44) and the bob phase (A45). Now depends on A44 and A45; gains pursuit-driven adrenaline (constant on Medium and Hard today) and the cameraMotion comfort setting.
- A15: look sway, lag, juke, landing and the raise-before-fire stances already exist; there is no look input, no sprint and no jump, and speed is 24..30. Now: time-based lag, sway from the base camera, per-class recoil profile, per-class wall pullback pose.
- A18: no inspect or first-draw clip on the Rifle; fire gating is time-based. First raise is Luau-authored with its own draw time.
- A20: client-side additive on the hit-box bone, depends on A53 and A63; the HIT_MAX_SPEED gate goes.
- A21: killed zombies are destroyed, not pooled; death chosen by direction, region and speed; client clone copies Bone.Transform; no server corpse hold (aliveCount); head hiding not possible on skinned zombies.
- A23: zombie footsteps do not exist; depends on A70 and A71; exposes the pursuit set.
- A24: the muzzle light exists; A24 adds the TransientLights registry and uses the T17b VfxConfig surface.
- A25: no impact pool and no impact emitter budget exist; depends on A52; uses the T17b emitter counter.
- A26: moved from ZombieVfx to the WeaponVfx family; needs the A53 payload; the gore gate does not exist today (A52 adds it).
- A30: the grade moves to LightingConfig and LightingDirector; PostFx stays event grading.
- A31: no damage event exists; depends on A47; also reads PlayerGlanced.
- A34: replaced. The Mixamo sources are already on disk and uploaded as R15; the bake goes through tools/zombie_pack onto the bone rigs; the Hazmat already has a death clip; the riser and feast patterns never spawn.
- A41: no secondary input exists; MB2 through ContextActionService; keep the HipAim cone and raise centreBias; procedural focus; FOV compensation folded in.
- A43: the magazine check is a tilt plus HUD text; lock-back already works; inspect on other classes comes from A50.
- Backlog: low-health desaturation already ships; only the heartbeat audio and duck remain.
- Rejected review note 5: correction appended.

Gaps merged into existing briefs:
- A4a: the sprint row became speed and glance-slow states.
- A17: clip list matches M4Clips.
- A19: brass mesh and a longer settled-casing lifetime on High.
- A22: Ghoul surfaces, colour jitter and variants, wound templates by health, bone blood drips, corpse tint, Hazmat visor crack, no wound decals.
- A27: fire flicker handed to A58.
- A28: the 9 decal keys are absent from AssetIds.
- A33: per-class recoil profile, handling entries, inspect and holster, per-class flash set.
- A39: Low tier sources for VFX values.
- A42: reload state passed to the A49 handling table; accept line for state-specific camera handling.
- A43: dropped magazines show their round state.
- Shared rules block: the luau CLI test constraint, the client hit box rule, the difficulty note and the real run speed.
- Amendments: T9 (pursuit speed band against run clips, no footsteps yet), T15 (muzzle light exists), T16 (killed zombies destroyed, disable the Dead state), T17 (widened pooling scope, remote caps, T17b config and emitter counter), T20 (A64 may fold in), T21 (34 clips, stale Hazmat death and feeding wiki lines).
- Single-writer map: new rows for WeaponController, Remotes, ZombieSkins, ZombieFactory and ZombieHitboxes, zombie bake tools, VfxConfig, ImpactDecals, gore modules, WorldVfx, camera modules, DeathController, BodyController and the test files; existing rows extended.

New tasks: A44 Camera rig composer; A45 Gait sync and cadence; A46 Glance and impact reactions on camera and viewmodel; A47 PlayerDamaged event and the grab beat; A48 Death camera variants by cause and direction; A49 Handling camera layer; A50 Inspect and holster coverage for every class; A51 VFX texture baseline; A52 Impact correctness; A53 Per-hit zone, target and kill flag in the shot payload; A54 Pooled impact decals; A55 Tracers as pooled travelling beams; A56 Weapon heat and per-class muzzle flash; A57 Player damage and low-health screen states; A58 World fire flicker, live density and particle fire; A59 Player death gore rebuild; A60 Teammate weapon VFX in third person; A61 Footstep dust by speed and water, and teammate step dust; A62 Teammate damage and death blood on other clients; A63 Client zombie hit box mirror; A64 Skinned zombie animation in the lure, feeding ring and sleeper spawns; A65 Ghoul retarget support; A66 Limb damage state; A67 Attack while moving with a contact-timed swing; A68 Client-side head look-at; A69 Turn-in-place shuffle; A70 Zombie footsteps from clip phase; A71 Zombie vocals follow state; A72 Human victims for feeding tableaux. The audit's viewmodel FOV compensation task went into A41 and its zombie kill read task into A21 and A26.

Rejected:
- Speed tiers up to 60 studs/s and the 24/40/60 captures: no location ramps speed, so a run never passes 30.
- Rebinding the death camera at Camera+2: the tie with CameraEffects does no harm, and Camera+2 is already taken.
- "Partial-weight aim clips are blocked": the Pistol and Rifle packs have no aim clips, so the focus is procedural anyway.
- A larger flash and an extra puff on the last round: not how MW2019 or real firearms behave.
- Hiding the head on a head kill for skinned zombies: Bones cannot scale.
- Moving impactFamily into a shared module: it would break tests/audio.
- Holding zombie corpses longer on the server: it would cut the spawn budget.
- A damage-cause branch and a white flash for "other damage": only grabs damage players.
- Alternating left and right step dust for the local player: the camera rarely sees its own feet.
- The reversed death clip as a rise: optional, behind an owner look verdict only.
- The wiki Performance.md wording note: not a premise any brief relies on.

Owner calls raised:
- Difficulty: on Medium and Hard every damaging contact kills, so damage and low-health presentation (A46 step 5, A57) reaches only Easy players unless the difficulty design changes.
- Cadence numbers after the A45 retune.
- Riser wake distance (about 20 to 45 studs) and the spawn pattern sets: Corridor only today (A34).
- Whether the reversed-death interim rise ships (A64).
- Whether the muzzle light gets a night multiplier (A56).
