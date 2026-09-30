# Architecture

Code map for Task Force Z. Every gameplay rule lives in a module under `src/`; there is no code in the place file itself. For what the systems do in play, see [[Gameplay Systems]]; for why they are shaped this way, see [[Decisions]].

## Project layout

`default.project.json` is the Rojo sourcemap for the whole place. It maps four source trees and sets two engine properties that the game depends on.

| Rojo target | Source | Notes |
| --- | --- | --- |
| `ServerScriptService.Server` | `src/server` | Server entry point plus `systems/` |
| `ServerScriptService.Packages` | `ServerPackages` | Wally server-realm dependencies |
| `ReplicatedStorage.Shared` | `src/shared` | `config/`, `net/`, `types/`, `util/` |
| `ReplicatedFirst` | `src/replicatedfirst` | Boot/title screen |
| `StarterPlayer.StarterPlayerScripts.Client` | `src/client` | Client entry point plus `controllers/`, `systems/`, `ui/` |

The same file sets `Lighting.Technology = Future` (with shadow softness, exposure and environment scales) and `Workspace.StreamingEnabled = true` with `StreamingTargetRadius = 1024`. Streaming is load-bearing: it is what lets the hub and the run world coexist in one DataModel.

Dependencies come from Wally. `wally.toml` declares the package realm as `shared` but has exactly one entry, under `[server-dependencies]`: `ProfileStore` (`ddashdev/profilestore@1.1.0`). Server-realm packages install into `ServerPackages/`, which is why the Rojo mapping points at `ServerScriptService.Packages` and not at `ReplicatedStorage`. Only `ProfileManager` requires it. Toolchain versions are pinned in `rokit.toml`: rojo 7.7.0, wally 0.3.2, selene 0.31.0.

The three trees have strict roles:

- `src/shared`: data and pure helpers only. Nothing in here connects an event or builds an instance at require time.
- `src/server`: all authority (world construction, run state, damage, currency, persistence).
- `src/client`: presentation and input only. The client predicts, but never decides.

## World coordinate split

Two disjoint regions share one DataModel, far enough apart that streaming culls one while the player is in the other.

| Region | Anchor | Value | Built by |
| --- | --- | --- | --- |
| Hub | `HangarConfig.HUB_CENTER` | `(300, 0, 0)` | `HangarBuilder`, `VendorRooms`, `DesertBase`, `CityDiorama` |
| Run | `GameConstants.RUN_ORIGIN` | `(-4000, 0, 0)` | `ChunkSpawner` via `ChunkFactory` |

The two anchors are 4300 studs apart. Every hub builder places geometry relative to `HUB_CENTER`, so moving the hub moves the hangar, the vendor rooms, the desert plane, the shooting range and the burning-city diorama together. `ChunkSpawner` pivots chunk `i` to `RUN_ORIGIN + RUN_DIRECTION * (START_PLATFORM_LENGTH + i * CHUNK_LENGTH + CHUNK_LENGTH / 2)`, and `MissionService` spawns the squad at `HangarConfig.RUN_START_CFRAME` = `(-4000, 5, 0)`, spaced laterally.

`RUN_DIRECTION` is `(0, 0, -1)`. Two consequences worth remembering:

- `RunController` clamps the player's X against `RUN_ORIGIN.X` plus or minus `PLAYABLE_HALF_WIDTH` (45), so lane clamping is origin-relative and narrower than the 240-stud geometry.
- `DistanceTracker` measures progress as `root.Position:Dot(RUN_DIRECTION)`, which is absolute world space. That works only because `RUN_ORIGIN.Z` is 0. Moving the run world along Z would silently offset every distance reading and every distance-based goal.

`TrackBuilder` is the one exception and is currently inconsistent: it pivots the start platform to `CFrame.new(RUN_DIRECTION * (length / 2))`, which is absolute `(0, 0, -32)` and therefore 4000 studs away from where the squad actually spawns.

## Server systems

All under `src/server/systems/`.

### World building

| Module | Owns |
| --- | --- |
| `HangarBuilder.luau` | The hangar shell: floor, walls with window bands, gate glass, ceiling lamps, props, grime, invisible containment barriers, an `AcousticSpace` interior zone, the `HubSpawn` SpawnLocation, and the three boardable helicopters it returns to `SquadService` |
| `VendorRooms.luau` | The five themed vendor rooms from `VendorsConfig`, each with a `VendorPrompt` ProximityPrompt carrying a `VendorId` attribute |
| `DesertBase.luau` | Desert ground plane, the road out to the city, and the outdoor shooting range with gong targets behind the hangar |
| `CityDiorama.luau` | Non-collidable burning-city backdrop plus four orbiting patrol helicopters driven on Heartbeat |
| `ChunkFactory.luau` | Pure geometry factory for a single run chunk: floor and PBR surface, side barriers, aprons, road markings, edge props, obstacles, and the cross-fade toward the next biome |
| `WorldFlanks.luau` | Decoration beside the corridor per biome in near, middle and silhouette bands; called from `ChunkFactory.build`, no collision or queries |
| `WorldMeshes.luau` | Mesh templates for world props, created at server start with `AssetService:CreateMeshPartAsync` from `WorldMeshConfig`; `place`/`placeFrom`/`placeByLength` clone and scale them, returning nil so builders can fall back to primitives |
| `ChunkOccupancy.luau` | Ground footprints already taken in the chunk being built; `ChunkFactory.build` resets it and every prop placement claims a circle or box or retries, so props never spawn inside each other |
| `world/WorldDressing.luau`, `world/WorldDecals.luau` | The environment pass's road dressing (clusters planned by the pure `src/shared/world/DressingPlanner.luau` from `DressingConfig`) and decal cards; called from `ChunkFactory.build` after the lane obstacles. See [[Environment]] |
| `world/ChunkBudgetCounter.luau` | Studio only: counts every built chunk against the budgets in `DressingConfig` (arithmetic in `src/shared/world/ChunkBudget.luau`), prints and stores the line as the `BudgetLine` attribute; `checkFog` (from `ChunkSpawner.init`) warns about lighting presets that would show a chunk spawning (`src/shared/world/FogBudget.luau`) |
| `SandboxBiomeStrip.luau` | Studio yard station: one chunk per biome side by side at `SandboxOrigin + (0, 0, -560)` and 25 fixed screenshot cameras (`BiomeStripShot`) |
| `ChunkSpawner.luau` | The streaming director: builds chunks along the route from `RoutePlan`, spawns ahead of `DistanceTracker.getMaxDistance()`, pools non-blended chunks, culls behind, sets `Workspace.Biome`, forwards ammo spawning (zombies no longer spawn per chunk) |
| `RoutePlan.luau` | The seeded biome route extracted from `ChunkSpawner`: `entryAt`, `entryForDistance`, `locationForDistance`, and `sectionAt(distance, sections)` which maps a run distance onto a spawn section and its 0..1 progress; shared by `ChunkSpawner` and `ZombieAI` without a require cycle |
| `TrackBuilder.luau` | The fixed start platform |
| `AmmoCrates.luau` | Per-chunk ammo crates and the proximity poll that grants reserve rounds |

### Run loop and flow

| Module | Owns |
| --- | --- |
| `FlowService.luau` | The authoritative `FlowPhase` player attribute (`Hub` or `Mission`) and everything that follows from it: humanoid config, hub teleport, ammo refill on entering a mission |
| `SquadService.luau` | The helicopter lobby state machine: one record per pad, boarding, privacy gating, leader-only config, countdown, handoff to `MissionService` with a fresh seed |
| `FriendCache.luau` | Memoised pairwise `IsFriendsWithAsync` used by the FriendsOnly privacy mode |
| `ForkService.luau` | Route forks: builds the centre divider and signs before a fork boundary, closes the physical vote when the lead runner crosses the vote line and hands the choice to `RoutePlan`; see [[Route Forks]] |
| `MissionService.luau` | Starting and stopping a squad run, including world teardown when the last participant leaves |
| `MissionState.luau` | In-memory run state: active flag, participant set, modifier ids |
| `MissionConfig.luau` | The active difficulty, mirrored to the `Workspace.Difficulty` attribute |
| `MissionGoals.luau` | Per-run objective tracking and bonus credits |
| `DistanceTracker.luau` | Run distance per player as a `RunState`, the `leaderstats.Distance` mirror, the constant-by-default speed model with per-location time ramps and `applySlow`, and the anti-stuck watchdog (sideways relocation, then death) |
| `DeathService.luau` | The whole death flow: corpse pose, zombie lure, reward computation, `DeathBegan`, and the return/continue choice |

### Combat

| Module | Owns |
| --- | --- |
| `WeaponService.luau` | Authoritative gunplay: per-player magazine and reserve state, per-weapon ammo snapshots across swaps, fire-intent validation, raycast damage with headshots, kill XP, reload jobs on the shared `WeaponsConfig` timeline (ammo-add, per-shell counting, `WeaponReloadCancel`), fire and reload blocked during the draw |
| `WorldWeapon.luau` | The third-person weapon model welded onto the character, rebuilt whenever the `WeaponId` attribute changes |
| `ZombieAI.luau` | The horde brain on a 0.2s tick: distance-driven section spawner (`spawnStep`), model pool with distance reaping, `Idle/Aware/Alert/Attack` mode machine with LOD, server-pinned network ownership, death/glance/miss collision bands, delayed-position chasing, corpse lure and feeding |
| `ZombieFactory.luau` | Building a zombie from a `ZombiesConfig` entry: the skinned Sketchfab rig picked by `ZombieSkins` (`buildSkinned`: root Motor6D, bone-driven hit boxes, static torso blockers, touch `Hitbox`), else the walker2 mesh rig, else the reduced primitive R15 rig |
| `ZombieRigs.luau` | Loads the skinned rig Models listed in `ZombieSkins` into `ServerStorage.ZombieRigs` with `InsertService` at require time and prepares them (Bone holder renamed `Rig`, importer controllers removed, visual parts non-colliding and massless) |
| `ZombieHitboxes.luau` | Keeps the invisible hit boxes of skinned zombies on their bones: one Motor6D per box whose `Transform` is written every `PreSimulation` from `bone.TransformedWorldCFrame`; zombies beyond 220 studs of every player are skipped |
| `ZombieAnimator.luau` | Zombie AnimationTracks. Skinned rigs: every clip of the skin, walk/run chosen by ground speed and played at `speed / groundSpeed`, attack swing, spotted scream, hit flinch, held death pose, `poseCorpse` for corpse props. Fallback rigs: seeded variant arrays with per-zombie phase and speed jitter. Degrades silently when asset ids are 0 |
| `ViewmodelPacks.luau` | Loads the four first-person pack rigs (`viewmodel/fps/<class>/rig`) into `ReplicatedStorage.ViewModelPacks` with `InsertService` for the client to clone |

### Economy

| Module | Owns |
| --- | --- |
| `ShopService.luau` | Vendor catalogs and purchases: weapons and upgrades, loadout slots, skills, skins; validates that the item is actually sold by the vendor that was named |
| `SkillEffects.luau` | Translating purchased skill levels into gameplay numbers (health, speed, reload scale, ammo scale) |
| `SkinService.luau` | Skins: default grants, equip validation, re-application on character load; a `HumanoidDescription` on the block body, a uniform tint on the soldier body |
| `SoldierCharacter.luau` | Builds `StarterPlayer.StarterCharacter` from a stock R15 converted by `SoldierBody` once the soldier meshes load (off while `SoldierRigConfig.ready` is false); see [[Soldier Body]] |
| `MonetizationService.luau` | The MarketplaceService wrapper: `ProcessReceipt` with idempotency, product and pass prompts, cached pass ownership |

### Persistence

| Module | Owns |
| --- | --- |
| `ProfileManager.luau` | ProfileStore-backed player data, the `ProfileData` template, version migration, the Credits and XP attributes, and the `onLoaded` fan-out every other system subscribes to |
| `SettingsPersistence.luau` | Pushing saved settings to the client on load and sanitising every incoming key against `SettingsConfig` |

## Client systems

`src/client/controllers/` holds anything that runs per frame or owns character state; `src/client/systems/` holds feature layers; `src/client/ui/` holds ScreenGui builders.

### Flow, camera and motion

- `FlowController.luau` mirrors the `FlowPhase` attribute into client mode, starting and stopping the run controllers.
- `RunController.luau` drives auto-run with `Humanoid:Move`, clamps the lane, and applies the decaying lateral shove and input lock from `applyGlance`; `InputController.luau` is the only run input, a ContextAction-bound lateral axis. `GlanceController.luau` listens for `PlayerGlanced` and fans it out to `RunController`, camera, body and animation reactions.
- `CameraController.luau` is the mission camera; `CameraEffectsController.luau` layers FOV, shake, bob, sway, tilt and breathing on top of it. `systems/CameraNearFade.luau` runs after every camera and hides (LocalTransparencyModifier) any part the camera is inside: the local character, zombies within 10 studs, props.
- `ExertionState.luau` is the shared movement clock. Speed, grounded state, a 0-1 exertion accumulator and a stride phase that fires step listeners twice per cycle. Footsteps, breathing, dust and camera bob all read from it rather than recomputing speed.
- `BodyMotionController.luau`, `FootPlanting.luau` and `AnimationController.luau` pose the character (`AnimationController` loads the generic clips and the weapon locomotion sets, picks the set by weapon class and the gait by speed, lateral input and the sprint threshold, falls back inside the set and then to `Run`, and exposes `clipSetFor(class)` for the yard; the gait feeds the `Animator` and `BodyRig` writes the aim, the weapon frame and the hand IK after it in `PreSimulation`, see [[Third-Person Locomotion]]); `FirstPersonController.luau` is a bootstrap that starts `CursorMode` and disables the reset button.

### Weapons

- `WeaponController.luau` owns input and prediction: fire, reload on the same `WeaponsConfig` timeline as the server (with the shell-reload fire cancel), slot swaps, the predicted magazine, and replication of `WeaponHit` into visible effects.
- `Viewmodel.luau` owns the first-person rig every RenderStepped: the procedural layer (recoil springs, sway, bob, drift, hip aim, equip) for both rig kinds, and the choice between a pack rig (`PackViewmodel`) and the procedural or mesh fallback (`ViewmodelBuilder`, `AnimationSequencer`, `PoseLibrary`).
- `PackViewmodel.luau` builds a rig from `ReplicatedStorage.ViewModelPacks` and runs its clips: the idle/walk base loop, a one-shot queue, reload plans, the fire cancel, the shotgun's pump follow and the phase markers. `ViewmodelClipPlayer.luau` decodes the baked tracks in `src/shared/viewmodel_clips/` and writes `Bone.Transform` each frame.
- `WeaponVfx.luau` (reused muzzle flash rigs, pooled casings, tracers, impacts, smoke) and `WeaponSfx.luau` (shot takes and tails on `OwnGunshot`, teammates' shots on `GunshotRemote`, marker-driven foley, low-ammo layer, casing landings on `Casing`, bullet impacts on `Impact`, the reflection fan; legacy pools behind the switch) are the effect layers.

### Third-person body

`src/client/body/` (`BodyController`, `BodyRig`, `AimReplicator`) layers weapon handling on the visible characters: the chest, head and gun aimed from the root's upright frame on the waist and neck `Motor6D`s, a weapon frame with recoil and gestures, and two `IKControl`s for the hands; `src/server/systems/BodyAimRelay.luau` relays the aim over an `UnreliableRemoteEvent`; data in `ThirdPersonConfig`, pure math in `src/shared/util/BodyMath.luau`, the gun builder in `WorldWeaponModel`. On (`ThirdPersonConfig.ENABLED`); it needs the place's `StarterPlayer.AvatarJointUpgrade` off, so characters have `Motor6D` joints (see [[Third-Person Body]]).

### Audio

`src/client/audio/` is the spatial audio engine (2026-09-29; design, research and Studio test plan in `docs/audio/spatial-audio.md`), built on the Roblox audio API (`AudioPlayer`, `AudioEmitter`, `AudioListener`, `Wire`, the `Audio*` effects) behind `SfxConfig.SPATIAL_AUDIO`:

- `AudioMath.luau` is the pure propagation math (attenuation curves, air-absorption cutoff, speed-of-sound delay, layer crossfades, occlusion smoothing, reflection timing), with no Roblox services so `luau tests/audio/run.luau` runs it outside Studio.
- `AudioBus.luau` builds the bus graph once under `SoundService.TFZ_Audio`: one `AudioListener` per 3D bus (weapons, sfx, voices, ambience; interaction groups `TFZ_<bus>`) on the camera, faders, environment reverb and street slapback on the weapons, sfx and voices buses, a shared duck group for ambience and music under a sidechain `AudioCompressor`, the ui bus after it, a master fader and `AudioLimiter` into one `AudioDeviceOutput`.
- `AudioEnvironment.luau` resolves a position into `Hangar`, `Interior`, `Street`, `Forest` or `Open` from the `AcousticSpace` zones, the biome and the flow phase, holds the material table, and runs the occlusion raycasts inside a per-frame budget.
- `AudioEngine.luau` owns the voice pool (48 desktop, 24 mobile; each voice is `AudioPlayer -> AudioFilter -> AudioEmitter` for 3D, the emitter on the voice's own `Attachment` in `Terrain`, or the bus fader for 2D), the one play API (`AudioEngine.play(spec): Handle`), priorities and class limits, distance layers, loops that hand their voice back out of range and take one again when the source returns, and the per-frame propagation update (curve, absorption, occlusion, doorway loss, delay via `AudioPlayer:Play(mixerTime + delay)`).
- `AudioReflections.luau` casts a ray fan from gunshots and explosions and plays delayed, filtered reflections from the hit points; `AudioDebug.luau` is the overlay (K in the test yard) and the test shot (L).

Classes, environments, materials and platform budgets are data in `src/shared/config/SpatialAudioConfig.luau`.
- `WeaponAudioMath.luau` is the pure part of the weapon sounds on the engine (tail choice by environment, the reflection fan's rate limit, the distance layer keys, the impact family per material), used by `src/client/systems/WeaponSfx.luau`, which plays the shooter's gun, teammates' shots, casings, the gong and bullet impacts through the engine's classes while `SfxConfig.WEAPONS_ON_ENGINE` is on and keeps its `Sound`-pool path for the switch off (see [[Weapon Audio]]).

`MusicController.luau` still owns the legacy SoundGroup tree, which `WeaponSfx` plays through only while `SfxConfig.WEAPONS_ON_ENGINE` is off (see [[Weapon Audio]]), and mirrors every volume, mute and duck change onto the engine's buses. `PlayerSfx.luau`, `FootstepController.luau`, `BreathingController.luau`, `WorldSfx.luau`, `CityAmbience.luau`, `ZombieAudio.luau`, `DeathController.luau` and `UiSfx.luau` are the per-domain layers, each playing through the engine when the flag is on and through its old `Sound`s when it is off; `SfxPlayer.luau` is the shared helper whose `play2D` / `play3D` forward to the engine's `Generic2D` / `Generic3D` classes; `DefaultSoundMuter.luau` silences Roblox's stock character sounds so the custom layer is the only one heard.

### VFX and post

`MotionVfx.luau` (step dust, juke bursts, breath vapour), `WorldVfx.luau` (ash, embers, rotor wash), `ZombieVfx.luau`, `GoreController.luau` and `DeathGore.luau` (both gated on the blood settings), `PostFx.luau` (damage tint, low-health desaturation, death fade, bloom), `LightingDirector.luau` (lerps toward the `LightingConfig` preset for the current phase, night flag and biome, including bloom, sun rays and shadow softness; a night mission takes the biome's own night preset; `getCurrent()` feeds `PostFx`), `EnvironmentQuality.luau` (on a touch-only device removes the `TFZ_Detail` props and stops `TFZ_ShadowNear` casting, on streamed chunks too; in Studio prints the scene's triangles and draw calls per biome), `FlashlightController.luau`.

### UI

`UiTheme.luau` holds the shared constants and helpers. `HudGui.luau` is the persistent hub HUD, `RunHud.luau` the mission HUD, `ForkHud.luau` the route-fork prompt, `SquadConfigGui.luau` the lobby panel, `ShopGui.luau` the vendor window, `SettingsGui.luau` the settings panel built from `SettingsConfig`, `GoreWarningGui.luau` the one-shot content warning, `DeathController.luau` the death cinematic and results screen. `CursorMode.luau` arbitrates between them: a reference-counted modal stack that frees the mouse and freezes the camera while any panel is open, and re-locks first person when the last one closes.

## Shared modules

`src/shared/config/` is data only, one module per system, mostly `table.freeze`d. Tuning happens here, not in the systems that read it. The set covers world constants (`GameConstants`, `HangarConfig`), content tables (`LocationsConfig`, `MapsConfig`, `ZombiesConfig`, `ZombieSpawnConfig` (spawn sections: density and difficulty tiers, clump presets, `Ramp` curves), `WeaponsConfig`, `SkillsConfig`, `SkinsConfig`, `VendorsConfig`, `ModifiersConfig`, `MissionGoalsConfig`, `DifficultyConfig`, `ProductsConfig`), and presentation tuning (`AudioConfig`, `SfxConfig`, `VfxConfig`, `CameraConfig`, `LightingConfig`, `FootstepConfig`, `BreathingConfig`, `AnimationsConfig`, `TexturesConfig`, `SettingsConfig`). Added since the first pass: `ZombieSkins` (skinned zombie rigs, their bones and clips with ground speeds), `ViewmodelPackConfig` (first-person packs: clip cuts, pump follow, phase markers), `ViewmodelConfig` and `PoseLibrary` (the procedural viewmodel), `WorldMeshConfig` (Cube 3D world props), `ForkConfig` (route forks), and `ZombieRigConfig` / `ArmRigConfig` (generated by `scripts/build_zombie_rig.py` and `scripts/build_arms.py`).

`src/shared/viewmodel_clips/` holds four generated clip modules (`PistolClips`, `RifleClips`, `ShotgunClips`, `SMGClips`, about 0.5 to 0.75 MB of base64 track data each), written by `tools/fps_pack/build_clips.py` and never edited by hand.

Two config modules are special. `AssetIds.luau` is generated by `scripts/sync_configs.py` from `assets/manifest.json` and must not be hand edited; every consumer guards on `id > 0` so an unuploaded asset is silence, not an error. `VfxConfig.luau` is deliberately not frozen, because `SettingsApply` mutates `VfxConfig.DENSITY` at runtime through `setDensity`.

The remaining shared trees are small: `net/Remotes.luau`, `types/Flow.luau` and `types/Squad.luau` (type-only modules that return an empty table), and `util/` with `LaneSectionFactory` (lane geometry shared by the start platform and chunks), `LocomotionMath` (pure gait rules: set by class, gait by movement, clip weights with fallbacks, playback rate; `luau tests/animation/run.luau`), `MaterialUtil` (registers the `TFZ_Asphalt`, `TFZ_Concrete`, `TFZ_Sand`, `TFZ_Metal`, `TFZ_Rust`, `TFZ_MetalPlates` and `TFZ_DarkRust` MaterialVariants and sets the Metal and CorrodedMetal base-material overrides), `TextureUtil` (face texture application), `MeshTemplates` (loads each MeshId once through `AssetService:CreateMeshPartAsync` so Rojo-mounted MeshParts render at their part size), `SoldierBody` (turns a stock R15 into the soldier from `ReplicatedStorage.CharacterMeshes.Soldier` and `SoldierRigConfig`), `ZombieRig` (the only sanctioned way to find a zombie's torso or neck, so no consumer hardcodes a part name) and `RewardMultiplier` (difficulty multiplier composed with de-duplicated modifier multipliers, used by both the lobby readout and the server payout so the number the player is shown is the number they get).

## Networking

`src/shared/net/Remotes.luau` is the only place remote instances are named. It exports two frozen name tables and creates instances lazily inside a `ReplicatedStorage.Remotes` folder: on the server by `FindFirstChild` then `Instance.new`, on the client by `WaitForChild`. Nothing else in the codebase calls `Instance.new("RemoteEvent")`.

Eighteen events:

| Event | Direction | Owner |
| --- | --- | --- |
| `SquadSnapshot` | Server to client | `SquadService` |
| `SquadUpdateConfig` | Client to server | `SquadService` |
| `SquadToggleModifier` | Client to server | `SquadService` |
| `SquadLaunch` | Client to server | `SquadService` |
| `SquadLeave` | Client to server | `SquadService` |
| `DeathBegan` | Server to client | `DeathService` |
| `DeathChoice` | Client to server | `DeathService` |
| `SettingsSync` | Server to client | `SettingsPersistence` |
| `SettingsSave` | Client to server | `SettingsPersistence` |
| `WeaponEquip` | Client to server | `WeaponService` |
| `WeaponFire` | Client to server | `WeaponService` |
| `WeaponReload` | Client to server | `WeaponService` |
| `WeaponReloadCancel` | Client to server | `WeaponService` |
| `WeaponHit` | Server to all clients | `WeaponService` |
| `ShopSync` | Server to client | `ShopService` |
| `PromptPurchase` | Client to server | `MonetizationService` |
| `AmmoPickup` | Server to client | `AmmoCrates` |
| `PlayerGlanced` | Server to client | `ZombieAI` |

Two RemoteFunctions, both owned by `ShopService` and both invoked only from `src/client/ui/ShopGui.luau`: `ShopCatalog` (vendor id in, catalog out) and `ShopPurchase` (vendor id, entry id, kind in; a result table with `ok` and `message` out).

Every remote validates its arguments server-side, without exception, and the pattern is uniform: `typeof` the argument, look it up in the owning config, and return early on any mismatch. Examples of the shape:

- `SquadUpdateConfig` checks `typeof(value) == "string"` and then `MapsConfig.isValid(value)` or `DifficultyConfig[value]`, on top of the leader and state checks.
- `WeaponFire` checks that origin and direction are Vector3s and that the direction magnitude is within 0.9 to 1.1, before it gets anywhere near fire rate, magazine count, muzzle-origin distance and the line-of-sight raycast.
- `ShopPurchase` rejects non-string ids, throttles at 0.25s per player, rebuilds the catalog server-side, and only accepts an entry id that is present in the catalog for the vendor that was named.
- `PromptPurchase` checks both `kind` and `id` are strings, then routes to the product or pass path.
- `WeaponReloadCancel` takes no arguments and only acts on a reload job the server itself started; the new shell limit and ready time are computed server-side by `WeaponsConfig.shellCancel`.

There is no remote that trusts a client-supplied number, id or amount. `RemoteFunction` handlers always return a table rather than erroring, so a rejected request produces a message in the UI instead of an unhandled invoke on the client.

## Data flow: skinned zombies and pack weapons (2026-09-29)

A skinned zombie, from asset to hit:

```
Sketchfab glb -> tools/fps_pack/strip_glb.py (animations stripped, UnitScale node) -> Model asset zombie/sketchfab/<skin>/rig
              -> tools/zombie_pack/build_zombie_anims.py -> assets/animation/zombie_sf/<skin>/*.rbxmx + clips.json (ground speeds)
              -> Animation assets animation/zombie_sf/<skin>/<slot> -> AssetIds -> ZombieSkins
server start: ZombieFactory requires ZombieRigs -> InsertService -> ServerStorage.ZombieRigs.<skin>
spawn:        ZombieAI.spawnZombie -> ZombieFactory.build -> ZombieSkins.pick -> buildSkinned -> ZombieHitboxes.attach
AI tick 5 Hz: ZombieAI mode and speed -> ZombieAnimator.setMode / setSpeed / attack / spotted
every frame:  Animator poses the Bones -> PreSimulation: ZombieHitboxes writes the box Transforms -> physics
shot:         WeaponService raycast -> hit box (Head = headshot) -> Humanoid:TakeDamage
              -> HealthChanged -> ZombieAnimator.hit | Died -> ZombieAnimator.playDeath, root anchored upright
```

A pack weapon, from asset to reload and shot:

```
Sketchfab glb -> strip_glb.py (--skin-fix for the Uzi) -> Model asset viewmodel/fps/<class>/rig
              -> ViewmodelPacks (server boot) -> ReplicatedStorage.ViewModelPacks.<class>
              -> build_clips.py (gltf_anim.py bake, emit_luau.py) -> src/shared/viewmodel_clips/<Class>Clips.luau
equip:        WeaponEquip -> WeaponService (drawUntil) | Viewmodel.setWeapon -> PackViewmodel.build -> Equip clip
R:            WeaponController.tryReload -> ReloadState on the WeaponsConfig timeline -> WeaponReload -> WeaponService ReloadJob
              -> Viewmodel.playReload -> PackViewmodel.reload -> ViewmodelClipPlayer (Bone.Transform) -> phase markers -> WeaponSfx.playPhase
ammo-add:     predictedMag on the client and AmmoMag on the server change at the same point of the timeline
fire mid-reload: magazine past ammo-add -> the shot cuts the tail on both sides
              shell loop -> WeaponReloadCancel -> WeaponsConfig.shellCancel on both sides -> buffered shot after the fast exit
shot:         WeaponFire -> WeaponService validation -> WeaponHit to all clients -> tracers, impacts, distant shots
              local: WeaponSfx.playShot (close take, sub, tail by environment, low-ammo layer, reflection fan from the muzzle) -> WeaponVfx.muzzleFlash + ejectCasing
              hit -> WeaponVfx.impact + WeaponSfx.playImpacts
              -> casing lands -> WeaponVfx.onCasingLanded -> WeaponSfx.playCasingLand
```

## Startup order

### Server

`src/server/init.server.luau` requires every service at the top, then runs each initialiser through a `runStage(name, fn)` helper that wraps the call in `pcall` and `warn`s on failure. A system that throws during init degrades the game instead of killing the boot.

Order is: `MaterialUtil.register`, `ViewmodelPacks` (starts the pack rig loads as early as possible), then `ProfileManager`, `SettingsPersistence`, `MissionConfig`, `FlowService`, `DistanceTracker`, `ZombieAI`, `WorldMeshes`, `ChunkSpawner`, `ForkService`, `MissionService`, `DeathService`, `SkinService`, `SoldierCharacter`, `WeaponService`, `ShopService`, `MonetizationService`, `AmmoCrates`, `MissionGoals`, `WorldWeapon`, `BodyAimRelay`. World builders run last, in their own stages: the `Hangar` stage calls `HangarBuilder.build()` and passes the returned helicopters straight into `SquadService.init(helicopters)`, then `VendorRooms.build`, `CityDiorama.build`, `DesertBase.build`, the Studio test bench `DevBench`, the Studio test yard `Sandbox`, which does nothing unless `DevConfig.SANDBOX.enabled` (then it builds the yard at x 3000 and moves each player into it while the run stays frozen; its client half is `SandboxInput`, started after `WeaponController`), and last the yard's `SandboxBiomeStrip`, under the same switch. `ZombieRigs` has no stage: it starts loading the skinned rigs as soon as `ZombieFactory` requires it, when the entry script requires `ZombieAI`.

Two ordering facts matter. `ProfileManager` is first among the services because most others hang their behaviour off `ProfileManager.onLoaded`. And `SquadService.init` is the only caller of `Remotes.init()`, so every remote instance in the game is created as a side effect of the `Hangar` stage succeeding.

### Client

`src/replicatedfirst/Boot.client.luau` runs first, removes the default loading screen, draws the title and loading sequence from `BootConfig`, and calls `BootState.setReady()` when it finishes or is skipped.

`src/client/init.client.luau` blocks on `BootState.awaitReady(BootConfig.READY_TIMEOUT)` (8 seconds) and then initialises in a fixed order:

1. Settings and audio foundation: `SettingsService`, `AudioEngine` (the bus graph and voice pool, before anything plays), `MusicController`, `FpsCounter`, `SettingsApply`, then `GoreController`, `DefaultSoundMuter`, `LightingDirector`, `EnvironmentQuality`, `CityAmbience`, `ZombieAudio`, `FlashlightController`, `FirstPersonController`.
2. Feel layer: `ExertionState` first, because `BodyMotionController`, `FootPlanting`, `CameraEffectsController`, `MotionVfx`, `WorldVfx`, `PostFx`, `PlayerSfx`, `WorldSfx`, `UiSfx`, `ZombieVfx`, `AnimationController`, `FootstepController` and `BreathingController` all read from it.
3. Features: `GlanceController`, `FlowController`, `SquadController`, `DeathController`, `WeaponController`, `BodyController`, `SandboxInput`, `ShopGui`, `VendorInteraction`.
4. HUD: `HudGui`, `RunHud`, `ForkHud`, then `GoreWarningGui.showOnce()` last so the content warning sits above everything already on screen (skipped in Studio while `DevConfig.SKIP_GORE_WARNING` is on).

Unlike the server, the client entry point has no `pcall` isolation: an error in an early init aborts the rest of the sequence.
