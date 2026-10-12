# Development Policy

How work on Task Force Z is done, revised on 2026-10-01 after a week in which a lot
landed fast and the owner's recordings kept showing problems the checks had missed.

Related: [[Decisions]], [[Progress]], [[Roadmap]].

## 1. Server owns the outcome, the client owns the feel

The server stays authoritative for everything that changes game state: damage, kills,
ammo counts, reloads, credits, purchases, perks, pickups. It validates every remote.

Everything the shooter sees and hears about their own action is drawn by the client at
once, with no round trip: muzzle flash, recoil, casings, tracers, impact puffs, impact
sounds, hit markers. The server's reply only reconciles numbers (ammo, kills) and draws
other players' shots. The old rule drew the shooter's tracers and impacts from the
server's `Shot`, a round trip late and from wherever the viewmodel had moved to; since
2026-10-01 `WeaponController.predictShot` draws them from a client ray with the same
spread rule. The damage path is unchanged.

## 2. Motion is checked as motion

A still frame cannot show a pop, a flicker or a one-frame glitch. Every change to
animation, the camera, the viewmodel or VFX is checked as a sequence:

- in Studio: the clip at a slowed `ViewmodelTimeScale` (it slows the casing simulation
  too, so an ejection can be watched in slow motion with the clip) sampled every few
  frames, or the character driven by `Humanoid:Move` and sampled over a gait cycle,
  joint values read back where a pose is in doubt;
- from the owner's recordings: frames at the recording's own rate around every shot,
  reload, weapon switch, camera switch and death, never only one frame every few
  seconds.

A change is reported as done only after that check, and the report says what was
checked and what was not.

## 3. Who works on what

| Area | Owner |
| --- | --- |
| Camera, first-person viewmodel, third-person body, animation, weapon VFX, the soldier body, the helicopter intermission's camera | main session |
| Server systems, economy, perks, pickups, stations, UI, configs, docs for those | cloud agent |

Every task given to the cloud agent names the files it must not touch. The agent opens a
PR; the main session reviews it (correctness, server trust, placement, repo rules) and
sends the fixes; the agent fixes, merges into `main` itself and pushes. The owner pulls.

## 4. Repo rules (unchanged)

- Commits are authored by the owner; no trailers; no mention of the tools used.
- No em or en dashes in any file.
- Fab content (Fab Standard License): never committed; repo is public. Processed maps
  live in the gitignored `assets/fab/`; only manifest rows (ids, licence, a note) and
  what is generated from them are committed, and a Fab row is committed only once it
  has its asset id (`docs/environment/megascans.md`).
- Asset ids only from the manifest pipeline (manifest, `upload_assets.py`,
  `refresh_status.py`, `sync_configs.py`); never invented. No synthesized audio.
- Pure rule modules run by the `luau tests/*` suites (`IntermissionMath`,
  `LocomotionMath`, `MapMath`, `PickupPlanner`, `UpgradeStationMath`, `MaterialSets`,
  `PrebuiltMapMath`, `ChunkBudget`, `MapsConfig`) take no services, no engine types and
  no requires, so the standalone `luau` CLI can load them. Callers pass everything in:
  config tables, server time, randomness (an `Rng` that a Roblox `Random` satisfies for
  `PickupPlanner` and `UpgradeStationMath`, plain roll numbers for `MapMath`).
- Before every commit: `selene src/`, `python3 tools/validate_api.py`,
  `rojo build`, the `luau tests/*` suites, `python3 tests/credits/run.py` (every CC BY
  asset credited in the game exactly once), `python3 tests/megascans/run.py` (the
  Megascans importer on synthetic surfaces), both sync scripts' `--check`.
- The owner's commit command is one chain joined with `&&` and ends with
  `git pull --no-rebase --no-edit && git push`, so a failed check stops the commit and
  a merge never opens an editor.

## Implementation notes

### Dev switches (`DevConfig`, `DevBench`, `DevMode`)

- Every `DevConfig` switch is checked against `RunService:IsStudio()` where it is used:
  `DevBench.init` returns at once outside Studio and both `DevMode` answers are false
  there, so a published server never comes up in a debug state whatever is committed.
- `QUICK_RUN` skips hub, helicopter and lobby, so a weapon change costs one Play click
  instead of about twenty seconds of scripted boarding. Its `mapId` takes a `MapsConfig`
  id or `"Random"`; nil means `MapsConfig.DEFAULT_ID`. `QUICK_LAUNCH.intermission` sends
  the launch through the cabin, ready check and crash like a squad launch, except in the
  test yard, which always goes straight in because the cabin has nothing to test there.
  The automatic launch fires only while the player's phase is Hub, so a character reset
  inside the cabin is not a new launch.
- `FREEZE_RUN` spawns you into the run with the weapon live but holds the forward sprint
  (normal WASD steering), since the corridor otherwise drags you off whatever you are
  inspecting within a second. `DevMode`'s frozen answer is true under `FREEZE_RUN`, in
  the yard, or with the `DevFreezeRun` workspace attribute set by hand.
- The server half of the freeze is in `DistanceTracker`, which exempts a frozen run from
  the stuck check, Studio only, from `FREEZE_RUN` or `DevFreezeRun` (set by `Sandbox` in
  Yard mode, or from the server command bar). The client's `freeze` debug command stops
  only the client `RunController` and cannot reach the server tracker.
- `THIRD_PERSON_VIEW` hands the camera to Roblox's stock orbit controller, keeps the
  character visible and frees the zoom clamp, so clips can be reviewed on the real
  character. It wins over `FREEZE_RUN`'s camera handling; `FREEZE_RUN`'s movement freeze
  still applies.
- `TARGET_RANGE` places stationary dummies at fixed distances in studs along -Z from
  where the range is built (the player's position for the `targets` command, a fixed
  spot in the yard), for time-to-kill and spread checks. The row fans sideways by 4
  studs so it does not occlude itself. A dummy is a Model with a Humanoid, which
  `WeaponService.findZombieModel` accepts, and `handleHit` skips only player characters,
  so hit registration and gore work without the bench knowing about dummies.
- The Studio command bar runs in a separate Lua VM, so requiring `DevBench` there gets a
  fresh module with no shared state. `DevBench` installs a BindableEvent at
  `ReplicatedStorage.DevBench` instead, fired as `DevBench:Fire(command, argument)` with
  `launch`, `targets`, `cleartargets`, `ammo`, `weapon <id>` or `state`. `weapon` grants
  the weapon to the profile before equipping, because `WeaponService` refuses an unowned
  weapon and a bypass in the live path was rejected.

### Client inspection modes and debug commands

- `CameraController` checks the third-person review mode (`THIRD_PERSON_VIEW` or the
  `DevThirdPerson` workspace attribute, key V in Studio, yard or run) before the
  frozen-run mode: both are inspection modes and this one wants the stock orbit camera
  either way. With the run frozen the camera goes back to Roblox's first-person
  controller and `RunController` leaves the default controls on so you can walk around;
  `RunController.start(force)` is how `unfreeze` overrides that.
- The first-person lock is not forced while a menu is open: forcing it every frame
  overrode `CursorMode` and left menus unclickable.
- Fixed screenshots: set the workspace attribute `DevCameraCFrame` to a CFrame from the
  command bar (nil gives the camera back). With `DevThirdPerson` on as well the shot
  shows the local character's body.
- `ReplicatedStorage.DebugWeapon` (Studio-only BindableEvent, `WeaponController`):
  `preview_tactical` and `preview_empty` play the reload animation with no reload behind
  it, so a clip slowed with `ViewmodelTimeScale` is not cut short when the server's
  reload ends; `empty` fakes an empty magazine and holds off ammo reconciliation for
  5 s; `freeze` calls `RunController.stop` so a static target range stays in front
  (otherwise the runner leaves the dummies behind within a second), and `unfreeze`
  restarts it.

### Test yard (`Sandbox`)

- Coordinates are relative to `DevConfig.SANDBOX.origin`: the floor spans x -360..+360
  and z +60..-400. The player spawns at z +30 facing -Z (the run direction), most
  stations ahead. The zombie and weapon clip galleries start at z +40, just behind the
  spawn line and off to the sides. The client builds its galleries around the
  `SandboxOrigin` point the server sets.
- The prop row shows each world mesh at in-game size beside a 1.8 m mannequin (6.4 studs
  at 1 stud = 0.28 m). Props modelled in metres go in at real size, older meshes at the
  sizes the chunk builders give them.
- The yard has its own `LightingConfig` preset, `Sandbox`: clear afternoon light (clock
  14.5) and far fog (400 to 2500), so rigs, casings and props are judged without the
  mission grading hiding them.
- Swapping yard and run mid-run stops the run, which sends the player to the hub, and
  `DevBench`'s quick run relaunches from there: straight in for the yard, through the
  cabin for the run when `QUICK_LAUNCH` asks. A swap while in the cabin needs no
  relaunch; the launch under way lands in the new mode.
- While `SandboxActive` is true in Studio, `ZombieAI`'s `spawnStep` spawns nothing and
  `aiStep` takes the global aggro flag from `SandboxAggro` instead of the distance gate.
  The yard places its own zombies through the Studio-only `ZombieAI.devSpawn(position,
  configId, skinName, faceAt, startAlert)`. A forced `skinName` skips the model pool,
  because pools are keyed by config id and a pooled model keeps the skin it was built
  with.
- Zombie clip gallery (`SandboxGallery`): one-shots are held 0.06 s short of their end
  for 1.2 s before replaying, because a non-looped AnimationTrack that reaches its end
  stops and the rig snaps to its bind pose. Walkers stand on strips whose texture
  scrolls toward the model's back (models face +X) at the clip's measured ground speed,
  so planted feet confirm the speed data. Gallery models have no queryable parts, so
  bullets pass through and the range beside it stays usable.
- Weapon gallery (`SandboxWeaponGallery`): rigs hang at 1.6x their uploaded size with
  each rig's eye point 5.9 studs above its station, so every exhibit is framed as the
  game frames it. Clip markers flash on the label and play their sound at the station's
  post under the gun, so sound sync can be judged by eye and ear. A pack's weapon bone
  origin can sit far from the gun body, so the gallery carries the weapon mesh's rest
  centre along with the weapon bone (the rifle's `Main_j_049`, for example) to place the
  post.
- Keys (`SandboxInput`, Studio only): G sends a chasing wave, H resets the yard, J calms
  everyone, T teleports back to the start (server commands); V toggles third person
  (stock orbit camera, viewmodel hidden, body visible); Z cycles slow motion; B plays
  the sound lane; K shows the audio engine overlay; L fires a remote rifle shot 30 studs
  ahead with reflections. G H J T Z B act only in the yard. M or the top-centre dev
  button swaps yard and run (Left Alt frees the cursor), and Studio's free camera
  (Shift+P) works too.
- Z cycles 1, 1/4, 1/10 for the viewmodel, casings, both clip galleries and the
  treadmills, through the camera's `ViewmodelTimeScale`, the workspace `DevTimeScale`
  (read by the weapon gallery) and the sandbox remote (the server zombie gallery). The
  body gallery does not follow it.
