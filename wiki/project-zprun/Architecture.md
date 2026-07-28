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

- `src/shared` — data and pure helpers only. Nothing in here connects an event or builds an instance at require time.
- `src/server` — all authority: world construction, run state, damage, currency, persistence.
- `src/client` — presentation and input only. The client predicts, but never decides.

## World coordinate split

Two disjoint regions share one DataModel, far enough apart that streaming culls one while the player is in the other.

| Region | Anchor | Value | Built by |
| --- | --- | --- | --- |
| Hub | `HangarConfig.HUB_CENTER` | `(300, 0, 0)` | `HangarBuilder`, `VendorRooms`, `DesertBase`, `CityDiorama` |
| Run | `GameConstants.RUN_ORIGIN` | `(-4000, 0, 0)` | `ChunkSpawner` via `ChunkFactory` |

The two anchors are 4300 studs apart. Every hub builder places geometry relative to `HUB_CENTER`, so moving the hub moves the hangar, the vendor rooms, the desert plane, the shooting range and the burning-city diorama together. `ChunkSpawner` pivots chunk `i` to `RUN_ORIGIN + RUN_DIRECTION * (START_PLATFORM_LENGTH + i * CHUNK_LENGTH + CHUNK_LENGTH / 2)`, and `MissionService` spawns the squad at `HangarConfig.RUN_START_CFRAME` = `(-4000, 5, 0)`, spaced laterally.

`RUN_DIRECTION` is `(0, 0, -1)`. Two consequences worth remembering:

- `RunController` clamps the player's X against `RUN_ORIGIN.X` plus or minus `LANE_WIDTH / 2 - 2`, so lane clamping is origin-relative.
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
| `ChunkSpawner.luau` | The streaming director: plans the biome route from `LocationsConfig`, spawns ahead of `DistanceTracker.getMaxDistance()`, pools non-blended chunks, culls behind, sets `Workspace.Biome`, forwards zombie and ammo spawning |
| `TrackBuilder.luau` | The fixed start platform |
| `AmmoCrates.luau` | Per-chunk ammo crates and the proximity poll that grants reserve rounds |

### Run loop and flow

| Module | Owns |
| --- | --- |
| `FlowService.luau` | The authoritative `FlowPhase` player attribute (`Hub` or `Mission`) and everything that follows from it: humanoid config, hub teleport, ammo refill on entering a mission |
| `SquadService.luau` | The helicopter lobby state machine: one record per pad, boarding, privacy gating, leader-only config, countdown, handoff to `MissionService` with a fresh seed |
| `FriendCache.luau` | Memoised pairwise `IsFriendsWithAsync` used by the FriendsOnly privacy mode |
| `MissionService.luau` | Starting and stopping a squad run, including world teardown when the last participant leaves |
| `MissionState.luau` | In-memory run state: active flag, participant set, modifier ids |
| `MissionConfig.luau` | The active difficulty, mirrored to the `Workspace.Difficulty` attribute |
| `MissionGoals.luau` | Per-run objective tracking and bonus credits |
| `DistanceTracker.luau` | Run distance per player, the `leaderstats.Distance` mirror, and speed ramping |
| `DeathService.luau` | The whole death flow: corpse pose, zombie lure, reward computation, `DeathBegan`, and the return/continue choice |

### Combat

| Module | Owns |
| --- | --- |
| `WeaponService.luau` | Authoritative gunplay: per-player magazine and reserve state, per-weapon ammo snapshots across swaps, fire-intent validation, raycast damage with headshots, kill XP, token-guarded reload |
| `WorldWeapon.luau` | The third-person weapon model welded onto the character, rebuilt whenever the `WeaponId` attribute changes |
| `ZombieAI.luau` | The horde brain on a 0.2s tick: weighted spawning, server-pinned network ownership, touch damage, aggro gating, delayed-position chasing, corpse lure and feeding |
| `ZombieFactory.luau` | Building the part-based zombie rig from a `ZombiesConfig` entry |
| `ZombieAnimator.luau` | Loading and cross-fading zombie AnimationTracks, degrading silently when asset ids are 0 |

### Economy

| Module | Owns |
| --- | --- |
| `ShopService.luau` | Vendor catalogs and purchases: weapons and upgrades, loadout slots, skills, skins; validates that the item is actually sold by the vendor that was named |
| `SkillEffects.luau` | Translating purchased skill levels into gameplay numbers (health, speed, reload scale, ammo scale) |
| `SkinService.luau` | HumanoidDescription skins: default grants, equip validation, re-application on character load |
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
- `RunController.luau` drives auto-run with `Humanoid:Move` and clamps the lane; `InputController.luau` is the only run input, a ContextAction-bound lateral axis.
- `CameraController.luau` is the mission camera; `CameraEffectsController.luau` layers FOV, shake, bob, sway, tilt and breathing on top of it.
- `ExertionState.luau` is the shared movement clock. Speed, grounded state, a 0-1 exertion accumulator and a stride phase that fires step listeners twice per cycle. Footsteps, breathing, dust and camera bob all read from it rather than recomputing speed.
- `BodyMotionController.luau`, `FootPlanting.luau` and `AnimationController.luau` pose the character; `FirstPersonController.luau` is a bootstrap that starts `CursorMode` and disables the reset button.

### Weapons

- `WeaponController.luau` owns input and prediction: fire, reload, slot swaps, the predicted magazine, and replication of `WeaponHit` into visible effects.
- `Viewmodel.luau` builds and poses the first-person weapon rig every RenderStepped, including recoil, sway, bob, equip and the multi-stage reload.
- `WeaponVfx.luau` and `WeaponSfx.luau` are the muzzle/tracer/impact and shot/reload/reverb layers.

### Audio

`MusicController.luau` owns the SoundGroup tree and the mute/duck/volume controls everything else routes through. `PlayerSfx.luau`, `FootstepController.luau`, `BreathingController.luau`, `WorldSfx.luau`, `CityAmbience.luau`, `ZombieAudio.luau` and `UiSfx.luau` are the per-domain layers; `SfxPlayer.luau` is the shared pooled playback helper; `DefaultSoundMuter.luau` silences Roblox's stock character sounds so the custom layer is the only one heard.

### VFX and post

`MotionVfx.luau` (step dust, juke bursts, breath vapour), `WorldVfx.luau` (ash, embers, rotor wash), `ZombieVfx.luau`, `GoreController.luau` and `DeathGore.luau` (both gated on the blood settings), `PostFx.luau` (damage tint, low-health desaturation, death fade, bloom), `LightingDirector.luau` (lerps toward the `LightingConfig` preset for the current phase, night flag and biome), `FlashlightController.luau`.

### UI

`UiTheme.luau` holds the shared constants and helpers. `HudGui.luau` is the persistent hub HUD, `RunHud.luau` the mission HUD, `SquadConfigGui.luau` the lobby panel, `ShopGui.luau` the vendor window, `SettingsGui.luau` the settings panel built from `SettingsConfig`, `GoreWarningGui.luau` the one-shot content warning, `DeathController.luau` the death cinematic and results screen. `CursorMode.luau` arbitrates between them: a reference-counted modal stack that frees the mouse and freezes the camera while any panel is open, and re-locks first person when the last one closes.

## Shared modules

`src/shared/config/` is data only, one module per system, mostly `table.freeze`d. Tuning happens here, not in the systems that read it. The set covers world constants (`GameConstants`, `HangarConfig`), content tables (`LocationsConfig`, `MapsConfig`, `ZombiesConfig`, `WeaponsConfig`, `SkillsConfig`, `SkinsConfig`, `VendorsConfig`, `ModifiersConfig`, `MissionGoalsConfig`, `DifficultyConfig`, `ProductsConfig`), and presentation tuning (`AudioConfig`, `SfxConfig`, `VfxConfig`, `CameraConfig`, `LightingConfig`, `FootstepConfig`, `BreathingConfig`, `AnimationsConfig`, `TexturesConfig`, `SettingsConfig`).

Two config modules are special. `AssetIds.luau` is generated by `scripts/sync_configs.py` from `assets/manifest.json` and must not be hand edited; every consumer guards on `id > 0` so an unuploaded asset is silence, not an error. `VfxConfig.luau` is deliberately not frozen, because `SettingsApply` mutates `VfxConfig.DENSITY` at runtime through `setDensity`.

The remaining shared trees are small: `net/Remotes.luau`, `types/Flow.luau` and `types/Squad.luau` (type-only modules that return an empty table), and `util/` with `LaneSectionFactory` (lane geometry shared by the start platform and chunks), `MaterialUtil` (registers the `TFZ_Asphalt`, `TFZ_Concrete` and `TFZ_Sand` MaterialVariants), `TextureUtil` (face texture application) and `RewardMultiplier` (difficulty multiplier composed with de-duplicated modifier multipliers, used by both the lobby readout and the server payout so the number the player is shown is the number they get).

## Networking

`src/shared/net/Remotes.luau` is the only place remote instances are named. It exports two frozen name tables and creates instances lazily inside a `ReplicatedStorage.Remotes` folder: on the server by `FindFirstChild` then `Instance.new`, on the client by `WaitForChild`. Nothing else in the codebase calls `Instance.new("RemoteEvent")`.

Fifteen events:

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
| `WeaponHit` | Server to all clients | `WeaponService` |
| `ShopSync` | Server to client | `ShopService` |
| `PromptPurchase` | Client to server | `MonetizationService` |

Two RemoteFunctions, both owned by `ShopService` and both invoked only from `src/client/ui/ShopGui.luau`: `ShopCatalog` (vendor id in, catalog out) and `ShopPurchase` (vendor id, entry id, kind in; a result table with `ok` and `message` out).

Every remote validates its arguments server-side, without exception, and the pattern is uniform: `typeof` the argument, look it up in the owning config, and return early on any mismatch. Examples of the shape:

- `SquadUpdateConfig` checks `typeof(value) == "string"` and then `MapsConfig.isValid(value)` or `DifficultyConfig[value]`, on top of the leader and state checks.
- `WeaponFire` checks that origin and direction are Vector3s and that the direction magnitude is within 0.9 to 1.1, before it gets anywhere near fire rate, magazine count, muzzle-origin distance and the line-of-sight raycast.
- `ShopPurchase` rejects non-string ids, throttles at 0.25s per player, rebuilds the catalog server-side, and only accepts an entry id that is present in the catalog for the vendor that was named.
- `PromptPurchase` checks both `kind` and `id` are strings, then routes to the product or pass path.

There is no remote that trusts a client-supplied number, id or amount. `RemoteFunction` handlers always return a table rather than erroring, so a rejected request produces a message in the UI instead of an unhandled invoke on the client.

## Startup order

### Server

`src/server/init.server.luau` requires every service at the top, then runs each initialiser through a `runStage(name, fn)` helper that wraps the call in `pcall` and `warn`s on failure. A system that throws during init degrades the game instead of killing the boot.

Order is: `MaterialUtil.register`, then `ProfileManager`, `SettingsPersistence`, `MissionConfig`, `FlowService`, `DistanceTracker`, `ZombieAI`, `ChunkSpawner`, `MissionService`, `DeathService`, `SkinService`, `WeaponService`, `ShopService`, `MonetizationService`, `AmmoCrates`, `MissionGoals`, `WorldWeapon`. World builders run last, in their own stages: the `Hangar` stage calls `HangarBuilder.build()` and passes the returned helicopters straight into `SquadService.init(helicopters)`, then `VendorRooms.build`, `CityDiorama.build`, `DesertBase.build`.

Two ordering facts matter. `ProfileManager` is first among the services because most others hang their behaviour off `ProfileManager.onLoaded`. And `SquadService.init` is the only caller of `Remotes.init()`, so every remote instance in the game is created as a side effect of the `Hangar` stage succeeding.

### Client

`src/replicatedfirst/Boot.client.luau` runs first, removes the default loading screen, draws the title and loading sequence from `BootConfig`, and calls `BootState.setReady()` when it finishes or is skipped.

`src/client/init.client.luau` blocks on `BootState.awaitReady(BootConfig.READY_TIMEOUT)` (8 seconds) and then initialises in a fixed order:

1. Settings and audio foundation — `SettingsService`, `MusicController`, `FpsCounter`, `SettingsApply`, then `GoreController`, `DefaultSoundMuter`, `LightingDirector`, `CityAmbience`, `ZombieAudio`, `FlashlightController`, `FirstPersonController`.
2. Feel layer — `ExertionState` first, because `BodyMotionController`, `FootPlanting`, `CameraEffectsController`, `MotionVfx`, `WorldVfx`, `PostFx`, `PlayerSfx`, `WorldSfx`, `UiSfx`, `ZombieVfx`, `AnimationController`, `FootstepController` and `BreathingController` all read from it.
3. Features — `FlowController`, `SquadController`, `DeathController`, `WeaponController`, `ShopGui`, `VendorInteraction`.
4. HUD — `HudGui`, `RunHud`, then `GoreWarningGui.showOnce()` last so the content warning sits above everything already on screen.

Unlike the server, the client entry point has no `pcall` isolation: an error in an early init aborts the rest of the sequence.
