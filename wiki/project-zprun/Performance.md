# Performance

Budgets, the config constants that hold them, and how to measure. Everything here is enforced structurally — by a cap, a pool, a density multiplier or a build-time flag — rather than by a runtime watchdog. See [[Architecture]] for the module layout the budgets apply to and [[Decisions]] for why particular limits were chosen.

## Budgets

| Budget | Target | Held by |
| --- | --- | --- |
| Active `ParticleEmitter` attachments | 40 | `VfxConfig.MAX_ACTIVE_EMITTERS`, counted in `src/client/systems/WorldVfx.luau` |
| Particle density | scalable 0.4 – 1.0 | `VfxConfig.DENSITY`, driven by the `effectsQuality` setting |
| Live run chunks | 6 ahead + 1 behind | `SPAWN_AHEAD_DISTANCE` 768 / `CHUNK_LENGTH` 128, `DESPAWN_BEHIND_DISTANCE` 160 |
| Streamed geometry radius | 1024 studs | `Workspace.StreamingTargetRadius` in `default.project.json` |
| Point lights per hub area | 9 hangar ceiling lamps, 9 city fire lights of 22 fires, 3 flicker lamps | `HangarBuilder`, `HangarConfig.CITY_FIRE_LIGHTS`, `WorldVfx` lamp counter |
| Light `Range` | 60 studs (engine cap) | ranges clamped in `CityDiorama`, `HangarBuilder`, `VendorRooms` |
| Server AI tick | 5 Hz | `GameConstants.ZOMBIE_AI_TICK` 0.2, accumulator in `ZombieAI.init` |
| Ammo crate pickup poll | 5 Hz | `task.wait(0.2)` loop in `src/server/systems/AmmoCrates.luau` |
| 2D SFX voices | 10, round-robin | `SfxPlayer.POOL_SIZE` |
| Footstep voices | 6 local + 3 per teammate | `FootstepConfig.POOL_SIZE`, `createPool(root, 3, ...)` |
| Fire crackle loops | 10 | `SfxConfig.FIRE_MAX_SOURCES` (22 fire anchors exist) |
| Zombie idle / alert voices | 6 / 5 | `SfxConfig.ZOMBIE_IDLE_MAX_VOICES`, `ZOMBIE_ALERT_MAX_VOICES` |
| Ground decal lifetime | 25 s blood stain, 12 s gibs | `Debris:AddItem` in `ZombieVfx.bloodAt` and `DeathGore` |

No MicroProfiler capture has been taken yet — the profiler is Studio-only. The numbers above are design limits, not measured costs; see [Measuring](#measuring) for the checklist that turns them into real figures.

## Streaming and chunk pooling

`default.project.json` sets `Workspace.StreamingEnabled = true` and `StreamingTargetRadius = 1024`. The hub and the run live 4300 studs apart (`HangarConfig.HUB_CENTER` at `(300, 0, 0)`, `GameConstants.RUN_ORIGIN` at `(-4000, 0, 0)`), so streaming culls one region entirely while the player is in the other. That split is the single largest structural saving and is described in [[Architecture]].

`src/server/systems/ChunkSpawner.luau` keeps the live set small:

- A chunk is spawned when `START_PLATFORM_LENGTH + index * CHUNK_LENGTH` falls inside `DistanceTracker.getMaxDistance() + SPAWN_AHEAD_DISTANCE` — 768 studs ahead of the lead player, i.e. six 128-stud chunks.
- A chunk is despawned once its far edge is behind `DistanceTracker.getMinDistance() - DESPAWN_BEHIND_DISTANCE` (160 studs), so the trailing squad member never loses ground under their feet.
- Despawn is a pool return, not a destroy: the model is unparented and pushed onto `pools[locationId]`. `spawnChunk` pops from that pool before falling back to `ChunkFactory.build`.
- **Transition chunks are never pooled.** When `blend ~= nil` the chunk carries a unique per-alpha colour/material/prop mix, so `pooled = false` and the model is destroyed on despawn. With `TRANSITION_CHUNKS = 2` that is at most two throwaway builds per biome change.
- `ChunkSpawner.configure(seed, locationIds)` destroys every pooled model at the start of a run, so a route change cannot leak stale biome geometry.

Per-chunk geometry cost is bounded inside `src/server/systems/ChunkFactory.luau`:

| Limit | Value | Constant |
| --- | --- | --- |
| Window bands per building | 4 | `MAX_WINDOW_BANDS` |
| Lane obstacles | `obstacleDensity * rng(0.6, 1.4) * 3.2` | `DifficultyConfig.obstacleDensity`, `GameConstants.FIELD_OBSTACLE_SCALE` |
| Obstacle lanes | `max(3, LANE_WIDTH / 46)` = 5, 75 % fill chance | inline in `ChunkFactory.build` |
| Blood stains per chunk | 2 – 5 | inline |
| Edge prop spacing | 22 – 34 studs (trees), 34 – 52 (everything else) | `edgeStep` |
| Telegraph pole spacing | 58 studs | `buildWireRun` |
| Zombies per chunk | 2 – 5 depending on biome | `LocationsConfig` `zombiesMin` / `zombiesMax` |

Obstacle density is the difficulty dial that moves the part count most: Easy 0.8, Medium 1.6, Hard 2.6, all multiplied by `FIELD_OBSTACLE_SCALE = 3.2`.

## Particles and emitter caps

`src/shared/config/VfxConfig.luau` is the only config module deliberately **not** `table.freeze`d, because `SettingsApply` mutates `VfxConfig.DENSITY` at runtime through `VfxConfig.setDensity(value)` when the player moves the Effects Density slider (`min 0.4`, `max 1`, `step 0.2`, default `1`).

Two different multiplication points exist and they behave differently:

- **Burst emitters** multiply at emit time. `MotionVfx` computes `max(1, floor(count * DENSITY + 0.5))` on every `Emit`, so step dust (2 – 8 particles per material), the 10-particle juke burst and the 4-particle breath vapour respond to the slider immediately.
- **Continuous emitters** multiply at build time. `WorldVfx` bakes `Rate = 9 * DENSITY` (ash), `7 * DENSITY` (embers), `6 * DENSITY` (rotor wash), `12 * DENSITY` (flies and exhaust haze) when the emitter is created. Changing the slider after the hub has been built does not re-rate those; it takes effect on the next session.

`VfxConfig.MAX_ACTIVE_EMITTERS = 40` is checked in exactly one place: `WorldVfx.attachEmbers` increments `emberCount` and returns early once the cap is reached. Other attachment sites are bounded by construction instead — three spark lamps (`lampCount < 3`), rotor wash only on `PadHBar` parts, flies on 40 % of `FuelDrum` parts.

Per-character emitters are created once and reused. `MotionVfx.setupCharacter` builds three emitters (`StepDust`, `JukeDust`, `BreathVapor`) with `Rate = 0` and `Enabled = false`, then drives them purely through `Emit()`. The ash layer is a single emitter on one invisible part that is repositioned to `camera.CFrame.Position + LookVector * 30 + (0, 14, 0)` every Heartbeat, and is disabled in Mission phase unless the biome is City.

Transient VFX self-destruct on a short clock rather than accumulating: muzzle light 0.05 s, muzzle flash 0.4 s, tracer beam 0.045 s, shell 1.2 s, impact anchor 0.8 s, barrel smoke 2 s (`src/client/systems/WeaponVfx.luau`). Blood stains land only on a 30 % roll and are removed after 25 s.

## Lights

Roblox caps `PointLight`, `SpotLight` and `SurfaceLight` `Range` at **60 studs**; larger values are silently clamped by the engine, so a 220-stud searchlight costs the same as a 60-stud one while looking wrong in the editor. The review pass in commit `0191d0d` clamped the offenders:

| Light | Before | After |
| --- | --- | --- |
| City fire glow (`CityDiorama`) | 110 | 60 |
| Patrol chopper searchlight (`CityDiorama`) | 220 | 60 |

Current ranges, all at or under the cap: hangar ceiling lamps 40 – 52, city street lamps 60, chopper beacon 40, vendor room lamps 30 / 34 / 16 / 14, ammo crate glow 26, spark lamp 22, muzzle flash 12 × weapon scale.

One outlier remains: `FlashlightController` sets `spot.Range = 90`. The engine clamps it to 60. It is harmless but misleading, and should be written as 60 the next time that file is touched.

Light counts are fixed by config, not by prop count:

- Hangar: 9 `CeilingLamp` fixtures (3 over the helipads at range 52, 6 across the floor at 40 – 46).
- City diorama: `CITY_BLOCKS = 72` blocks, `CITY_FIRES = 22` fires, but only `CITY_FIRE_LIGHTS = 9` of those fires carry a `PointLight`. The other 13 are particle-only.
- `CITY_CHOPPERS = 4` patrol helicopters, each with one beacon and one searchlight.
- `WorldVfx` adds at most 3 flickering spark lamps.

## Shadows

`default.project.json` sets `Lighting.Technology = "Future"` with `ShadowSoftness = 0.35` and `GlobalShadows = true`. The Shadows setting in the settings menu maps straight to `Lighting.GlobalShadows` (`SettingsApply`), which is the single largest client-side lever.

The policy for geometry is: **small decor does not cast.** `ChunkFactory` has a `noShadow(part)` helper and sets `CastShadow = false` on window bands, roof boxes, farm roofs, dry grass, corn stalks, road markings, blood stains and the invisible lane barriers. The same is applied across `HangarBuilder` (glass, roof, trusses, lamp fixtures, helipad markings, rotor blades, nav lights, grime, containment barriers), `DesertBase`, `CityDiorama`, `VendorRooms`, `ZombieFactory` (eyes), `WeaponVfx`, `Viewmodel` and `ZombieVfx`.

Two deliberate exceptions:

- `ChunkFactory.buildBuilding` sets `tower.CastShadow = true` on the optional rooftop tower — it is the one silhouette element that reads as depth against the fog.
- `FlashlightController` sets `spot.Shadows = true`. It is a single light that exists only when `Workspace.NightMission` is set and the phase is Mission, so it never overlaps the hub lamps.

Hangar ceiling lamps set `light.Shadows = false` explicitly: nine shadow-casting lights in one enclosed interior is the worst case the Future renderer handles, and the fixtures are `Neon` parts that already read as light sources.

## Audio

Every sound goes through the `TFZ_Master` → `TFZ_Music` / `TFZ_Sfx` SoundGroup tree built by `src/client/systems/MusicController.luau`, so master volume, music volume, mute and the chase duck are property writes on three objects rather than a walk over live sounds.

Pooling by layer:

| Layer | Strategy |
| --- | --- |
| 2D one-shots (`SfxPlayer.play2D`) | 10 `Sound` objects parented to `SoundService`, round-robin index, `SoundId` rewritten per call |
| 3D one-shots (`SfxPlayer.play3D`) | created per event, destroyed on `Ended`, plus a hard `task.delay(8, ...)` sweep so a sound whose asset fails to load cannot leak |
| Local footsteps | pool of 6 on the `HumanoidRootPart`, rebuilt on `CharacterAdded` |
| Teammate footsteps | pool of 3 per player, keyed on the player and dropped on `CharacterRemoving` |
| Zombie growls | one looped `Sound` per body, attached on spawn and destroyed with the model |
| Ambience loops | one each: hangar roomtone, horde walla, breath layers, wind, heartbeat |

Extra guards worth knowing:

- Footstep clips are sliced: if `TimeLength` exceeds `FootstepConfig.MAX_SLICE = 0.32` the sound is stopped early, which keeps overlapping strides from stacking into mud.
- Teammate footsteps are simulated on `Heartbeat` from a stride phase (`ExertionState.strideFrequencyFor`), not from replicated events, and skip any player under 2 studs/s or airborne.
- `ZombieAudio` walks `Workspace.Zombies` on Heartbeat but stops collecting once it hits `limit` (`ZOMBIE_IDLE_MAX_VOICES = 6`, `ZOMBIE_ALERT_MAX_VOICES = 5`). The walla volume pass counts bodies inside 160 studs without allocating.
- `WorldSfx` attaches fire crackle to the first `FIRE_MAX_SOURCES = 10` anchors only; the remaining anchors are still registered as distant-boom hosts, which cost nothing until a boom fires (one every 30 – 60 s).
- `SoundService.AmbientReverb` is switched by phase rather than per-sound; the interior/exterior weapon tail uses `AcousticSpace`-tagged zone parts read by `WeaponSfx`.

## The anti-blur pass

Textures were originally tiled far too coarsely — a single 1K texture stretched over 12 – 40 studs per tile, which reads as blur at first-person eye height. Commit `f7c72c7` retiled every surface to a target texel density and tightened bloom, which was masking the same problem as glow.

Targets: roughly **4 – 6 studs per tile for concrete and metal panelling**, **2 – 3 studs for brick**, 6 – 8 for ground and sand where the player is moving fast and the surface is low-frequency.

| Surface | File | Before | After |
| --- | --- | --- | --- |
| Hangar floor concrete | `HangarBuilder` | 16 | 6 |
| Hangar corrugated wall bands | `HangarBuilder` | 14 | 6 |
| City diorama asphalt ground | `CityDiorama` | 40 | 12 |
| Desert sand ground | `DesertBase` | 10 | 8 |
| Shooting range pad | `DesertBase` | 8 | 6 |
| Run chunk floor (fallback) | `ChunkFactory` | 12 | 8 |
| Run chunk apron | `ChunkFactory` | 10 | 7 |
| Building brick face | `ChunkFactory` | 8 | 2.5 |

The floor and hangar values are fallbacks: `MaterialUtil.apply` is tried first and installs a `MaterialVariant` with its own `StudsPerTile` — `TFZ_Concrete` 6, `TFZ_Sand` 8, `TFZ_Asphalt` 12. The literal `Texture` path only runs when the PBR maps are missing or the variant failed to register, which is the normal state while manifest entries are still unuploaded (see [[Assets Pipeline]]).

Bloom limits in `src/client/systems/PostFx.luau`:

| Property | Before | After |
| --- | --- | --- |
| `Intensity` | 0.4 | 0.34 |
| `Size` | 24 | 20 |
| `Threshold` | 1.1 | 1.25 |

The rule is **Intensity ≤ 0.4 and Threshold ≥ 1.2** for normal play. The one exception is Forest during the day, where the sun sits in frame through the canopy and the scene needs the glare to read as sunlight rather than as fog:

```lua
local sunInFrame = biome == "Forest" and Workspace:GetAttribute("Night") ~= true
bloom.Intensity = (if sunInFrame then 0.62 else 0.34) + deathFade * 1.6 + damagePulse * 0.5
bloom.Threshold = if sunInFrame then 1 else 1.25
```

`deathFade` and `damagePulse` push intensity above the limit on purpose — both are short, event-driven and intended to blow the image out.

## Measuring

MicroProfiler is `Ctrl+F6` in Studio. Compare these four scenes; they cover the distinct cost profiles.

| Scene | Setup | What it stresses |
| --- | --- | --- |
| Hub | standing at the hangar gate, city and choppers visible | lights, city diorama, ambience loops, `WorldVfx` |
| Day run | City map, Hard, past ~1500 m | chunk build cost, obstacle density, building count |
| Night run | City map with the Night modifier | flashlight shadows, dust motes, `LightingDirector` lerp |
| Horde | Hard, post-aggro, 10+ zombies inside 60 studs | `ZombieAI` tick, growl voices, music duck, blood VFX |

Labels to watch:

- `RenderStepped` — `CameraEffectsController`, `BodyMotionController`, `Viewmodel`, `FootPlanting`, `FlashlightController`.
- `Heartbeat` — every audio and VFX system, `ChunkSpawner.step`, `ZombieAI` (the 0.2 s accumulator means four out of five frames cost nothing).
- `Particles`, `Lighting`, `Physics/Step`.

The in-game FPS counter (`src/client/systems/FpsCounter.luau`, half-second average, toggled by the `fpsCounter` setting) is the coarse check for live sessions where the profiler is unavailable.

## Knobs when it drops

| Symptom | Turn |
| --- | --- |
| General frame drop | Effects Density → 0.4; Shadows off (`Lighting.GlobalShadows`) |
| Hub / city drop | `HangarConfig.CITY_BLOCKS`, `CITY_FIRES`, `CITY_FIRE_LIGHTS`, `CITY_CHOPPERS` |
| Run drop | `GameConstants.SPAWN_AHEAD_DISTANCE`, `FIELD_OBSTACLE_SCALE`, `ChunkFactory.MAX_WINDOW_BANDS`, `DifficultyConfig.obstacleDensity` |
| Shadows too expensive | `Lighting.Technology` → `ShadowMap` in `default.project.json` |
| Audio eating the frame | `SfxConfig.FIRE_MAX_SOURCES`, `ZOMBIE_IDLE_MAX_VOICES`, `SfxPlayer.POOL_SIZE` |
| Streaming hitches | `Workspace.StreamingTargetRadius` in `default.project.json` |

## Known gaps

- No measured MicroProfiler figures exist yet; the checklist above has never been run against a build.
- `VfxConfig.MAX_ACTIVE_EMITTERS` is only honoured by the ember path in `WorldVfx`. Every other emitter site is bounded by construction, so the global count is a design intent rather than an enforced ceiling.
- Zombie growl loops scale one-to-one with horde size and are not pooled or capped.
- Continuous emitter rates are baked at build time, so the Effects Density slider only partially applies mid-session.
- `FlashlightController` still requests `Range = 90` against a hard engine cap of 60.

Related: [[Overview]] · [[Architecture]] · [[Gameplay Systems]] · [[Assets Pipeline]] · [[Decisions]] · [[Roadmap]]
