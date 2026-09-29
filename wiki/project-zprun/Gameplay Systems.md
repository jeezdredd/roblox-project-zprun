# Gameplay Systems

How each feature is actually implemented, with the files that own it. For the module map, boot order and remote list see [[Architecture]]; for the reasoning behind specific choices see [[Decisions]].

Two conventions hold everywhere and are worth knowing before reading anything below:

- **The server owns state.** Ammo, damage, credits, purchases, skin grants, squad config and difficulty all live on the server. Clients get attributes and remote events, never authority.
- **Configs are data-only.** Anything under `src/shared/config/` is a frozen table plus lookup helpers. Changing a number there changes gameplay without touching a system.

---

## Flow and phases

Files: `src/server/systems/FlowService.luau`, `src/client/controllers/FlowController.luau`, `src/shared/types/Flow.luau`

There are exactly two phases, stored on the player instance as the `FlowPhase` attribute with values `"Hub"` and `"Mission"`. The attribute replicates automatically, so the client never asks for the phase: it watches the attribute.

`FlowService.setPhase(player, phase)` is the only sanctioned writer. It:

1. Writes the attribute.
2. Calls `applyHumanoidConfig` on the current character.
3. On a `Hub -> Mission` transition only, calls `WeaponService.refillAmmo(player)`.

`applyHumanoidConfig` always sets `BreakJointsOnDeath = false` (the death sequence needs an intact corpse to pose) and recomputes `MaxHealth` as `GameConstants.PLAYER_MAX_HEALTH` (100) plus `SkillEffects.bonusHealth`, preserving the current health ratio. Then:

| Phase | WalkSpeed | Jump |
| --- | --- | --- |
| Hub | `HUB_WALK_SPEED` = 16 | `JumpHeight` = 7.2, `UseJumpPower = false` |
| Mission | left to `DistanceTracker` | `JumpHeight` = 0 (jumping disabled) |

`onCharacterAdded` re-derives the phase from `MissionState.isParticipant(player)` rather than trusting the old attribute, and if the result is Hub it force-teleports the character to `HangarConfig.HUB_SPAWN_CFRAME`. This exists because the `HubSpawn` SpawnLocation alone was not reliable across respawn paths.

**Gotcha:** `onCharacterAdded` calls `applyHumanoidConfig(character, phase)` without the `player` argument, so a freshly spawned character does not get the Toughness health bonus until the next `setPhase` call. If you add skill-derived humanoid properties, apply them here too.

Client side, `FlowController` mirrors the attribute into controller lifecycle: on `Mission` it starts `InputController`, `CameraController` and `RunController`; on `Hub` it stops them and hands the camera back to Roblox.

---

## Hub

The hub is a single static build produced once at server start. `src/server/init.server.luau` runs the four builders last, after all services are initialised, each inside a `runStage` pcall so a broken builder warns instead of killing boot.

All hub geometry is placed relative to `HangarConfig.HUB_CENTER` = `(300, 0, 0)`. The run world is 4300 studs away at `GameConstants.RUN_ORIGIN`; see [[Architecture]] for why.

### Hangar

File: `src/server/systems/HangarBuilder.luau` (691 lines), returns `{ Helicopter }`

Builds, in order: floor (`HUB_FLOOR_SIZE` 360x320, `TFZ_Concrete` PBR material with a plain texture fallback), four walls with glass window bands, the front gate (glass at 62% transparency plus 6 metal mullions, `GATE_HALF_WIDTH` 62, `GATE_HEIGHT` 34), ceiling and lamps, props, floor grime, then the three helicopters.

Two invisible layers matter functionally:

- **Containment barriers**: five black transparent walls at `wallHeight + 30`, sized to the floor plus 8 studs, with a `RANGE_DOOR_HALF_WIDTH` = 10 gap in the back wall so players can walk out to the shooting range. These are what actually keep players inside; the visible walls are decoration.
- **`HangarInteriorZone`**: a non-colliding part covering the whole hangar volume with the attribute `AcousticSpace = "Interior"`. `WeaponSfx` reads it (see [Weapons](#weapons)).

`HubSpawn` is a `SpawnLocation` with `Duration = 0`, `Neutral = true`, sunk 3 studs below `HUB_SPAWN_CFRAME`.

Each helicopter is returned as `{ index, model, prompt, statusLabel, padCFrame }`. The prompt is a `ProximityPrompt` named `BoardPrompt`, hold 0.3s, `MaxActivationDistance = BOARD_PROMPT_DISTANCE` (14), `RequiresLineOfSight = false`. The status label is a `BillboardGui` TextLabel 16 studs above the cabin. `SquadService` consumes both.

Pads are fixed in `HangarConfig.HELICOPTER_PADS`: `(210, 0.5, -108)`, `(300, 0.5, -108)`, `(390, 0.5, -108)`.

### Vendor rooms

File: `src/server/systems/VendorRooms.luau` (506 lines), config `src/shared/config/VendorsConfig.luau`

Five rooms, each built from a `VendorConfig` giving a hub-relative `offset`, `rotationY`, `size` and two colours. All five are 56x18x44 except the Bubblegum stand (52x18x40).

| Vendor id | Display name | Offset from hub centre | Sells |
| --- | --- | --- | --- |
| `Medbay` | Medbay | `(-152, 0, -52)` | Skills |
| `SodaMachine` | Canteen | `(-152, 0, 56)` | Skins |
| `WeaponDealer` | Weapon Dealer | `(152, 0, -52)` | Weapons and weapon upgrades |
| `Gunsmith` | Gunsmith | `(152, 0, 62)` | Weapons, upgrades and loadout slots |
| `BubblegumMachine` | Bubblegum Stand | `(0, 0, 132)` | Skins |

Each room builds a shell, signage, a counter and a themed interior. The interaction hook is small and specific: a `ProximityPrompt` named `VendorPrompt` (ActionText "Browse", hold 0.2s, range 14) parented to the counter, and the attribute `VendorId` set on that same counter part. `src/client/systems/VendorInteraction.luau` listens on `ProximityPromptService.PromptTriggered`, filters by prompt name, reads `VendorId` off `prompt.Parent`, and opens `ShopGui`.

The `subtitle` strings in `VendorsConfig` still end in "SOON" even though all five vendors have working catalogs. That text is cosmetic only.

### Desert base, road and shooting range

File: `src/server/systems/DesertBase.luau`, seeded `Random.new(20260729)` so the layout is stable across restarts.

**Ground**: a 2400x2400 sand plane at y = -1.05 with `TFZ_Sand` PBR (texture fallback), 24 scattered slate boulders placed on a ring 260 studs out to `DESERT_SIZE/2 - 100`, skipping anything that would land in the city diorama. One invisible `DustAnchor` carries a slow sand-drift `ParticleEmitter`.

**Road to the city**: asphalt strip `ROAD_WIDTH` 40 running from `ROAD_START_Z` (-164) to `ROAD_END_Z` (-470) relative to hub centre, i.e. it stops just short of the diorama's `CITY_NEAR_Z` (-480). Dressing: centre markings every 18 studs, power poles every 55 studs alternating sides with `Beam` wires strung between consecutive pole-top attachments (`CurveSize` -4 for sag), 5 wrecked cars, and a sandbagged checkpoint 26 studs down the road (two concrete barriers plus a 3-row pyramid of sandbags per side).

**Shooting range**: built behind the hangar, starting at `center.Z + HUB_FLOOR_SIZE.Z/2` and reachable through the 20-stud door gap in the back containment wall.

| Element | Detail |
| --- | --- |
| Yard | `RANGE_YARD_WIDTH` 130 x `RANGE_YARD_DEPTH` 100 ground pad |
| Fencing | Chainlink-textured invisible panels on left, right and far edges, posts every ~9 studs |
| Canopy | 70x18 corrugated metal roof at y = 12 on 8 posts |
| Firing line | 4 wooden benches, 18 studs apart |
| Targets | 3 boards at `RANGE_TARGETS` = 15, 30, 50 studs downrange, each tagged with a `TargetDistance` attribute |
| Gong | Cylinder part named `RangeGong` at +42 X, 52 studs downrange |
| Backstop | A 14-stud sand berm plus invisible `RangeContainment` walls 60 studs tall |
| Acoustics | `RangeInteriorZone`, 70x14x22 under the canopy, `AcousticSpace = "Interior"` |

The gong is the only range element with gameplay wiring: `WeaponService.handleHit` special-cases `part.Name == "RangeGong"`, applies an 0.8s per-player cooldown, and broadcasts `WeaponHit("Gong", position)` to every client so everyone hears the ring.

### City diorama

File: `src/server/systems/CityDiorama.luau`

A purely visual backdrop between `CITY_NEAR_Z` -480 and `CITY_FAR_Z` -1100, `CITY_HALF_WIDTH` 420. Nothing in it is collidable or queryable. Contents: `CITY_BLOCKS` 72 building blocks, `CITY_FIRES` 22 fires each anchored on a part named `FireAnchor`, `CITY_FIRE_LIGHTS` 9 flickering PointLights, and police cars.

`CITY_CHOPPERS` 4 patrol helicopters orbit on `Heartbeat` at radii `CHOPPER_RADIUS_MIN`..`MAX` (150..260) and heights 90..170, around centres between `CHOPPER_CENTER_NEAR` -180 and `CHOPPER_CENTER_FAR` -420.

The `FireAnchor` parts are a contract, not decoration: `src/client/systems/WorldSfx.luau` attaches fire-crackle loops to them and `src/client/systems/WorldVfx.luau` attaches ember emitters. `src/client/systems/CityAmbience.luau` attaches rotor loops to the patrol choppers and stops all of it when `FlowPhase` becomes `Mission`.

---

## Squad lobby and launch

Files: `src/server/systems/SquadService.luau`, `src/server/systems/FriendCache.luau`, `src/client/controllers/SquadController.luau`, `src/client/ui/SquadConfigGui.luau`

One `SquadRecord` per helipad, created in `SquadService.init(helicopters)`, which is also the only caller of `Remotes.init()`, so every remote in the game exists because this function ran.

State machine: `Empty -> Filling -> Launching`, then back to `Empty` on launch or when the last member leaves. The leader is always `members[1]`; there is no explicit leader field.

**Boarding** (`canBoard`) requires all of: state is Empty or Filling, `#members < HangarConfig.SQUAD_CAPACITY` (3), the player is not already in a squad, and the privacy check passes. Privacy is evaluated against the leader:

| Privacy | Rule |
| --- | --- |
| `Solo` | Nobody but the leader can board. Cannot be selected while `#members > 1`. |
| `FriendsOnly` | `FriendCache.areFriends(leader.UserId, player.UserId)`: a memoised pairwise `IsFriendsWithAsync` |
| `Public` | Anyone |

**Config changes** (`updateConfig`, `toggleModifier`) require leadership, state `Filling`, and a rate check: `MAX_CONFIG_RATE` 12 events per `RATE_WINDOW` 1 second, per player. Values are validated against `MapsConfig.isValid`, `DifficultyConfig[value]` and `ModifiersConfig.isValid` respectively; anything else is silently dropped.

**Snapshots**: every mutation calls `pushSnapshot`, which fires `SquadSnapshot` to each member with `{ squadIndex, state, config, members, leaderUserId, capacity, rewardMultiplier, countdownEndsAt }` and refreshes the helicopter billboard text. Leaving fires `SquadSnapshot` with `nil` to that player so the client can close the panel.

**Launch**: `requestLaunch` is leader-only, requires state `Filling`, and refuses if `MissionState.isActive()` (only one run per server). It sets `countdownEndsAt = Workspace:GetServerTimeNow() + HangarConfig.LAUNCH_COUNTDOWN` (4s) and stores a `task.delay` thread. The countdown is broadcast as an absolute server timestamp, not a tick count, so `SquadConfigGui` renders it without drift. Anyone leaving during `Launching` calls `abortLaunch`, which cancels the thread and drops back to `Filling`.

`doLaunch` clones the member list, generates `seed = Random.new():NextInteger(1, 2147483646)`, clears the squad record, and calls `MissionService.startSquad(members, config, seed)`.

**Reward multiplier** is computed identically on both sides by `src/shared/util/RewardMultiplier.luau`: `difficulty.rewardMultiplier` times each *unique* modifier's `rewardMultiplier`. Medium + FastZombies + Night = 1.25 x 1.3 x 1.2 = 1.95.

| Modifier | Reward | Effect |
| --- | --- | --- |
| `FastZombies` | x1.3 | `zombieSpeedBonus` +0.5 (added to the difficulty multiplier) |
| `Night` | x1.2 | Sets `Workspace.NightMission`, driving `LightingDirector` and `FlashlightController` |

---

## Run generation

Files: `src/server/systems/MissionService.luau`, `ChunkSpawner.luau`, `ChunkFactory.luau`, `TrackBuilder.luau`, configs `GameConstants`, `LocationsConfig`, `MapsConfig`, `DifficultyConfig`

### Starting a run

`MissionService.startSquad` refuses if a run is already active, then filters the member list down to players with a living humanoid and aborts if none remain. Then, in order: set `MissionState` active + difficulty + modifiers, resolve `MapsConfig.get(config.mapId)` and pass its `locationIds` into `ChunkSpawner.configure(seed, ids)`, build the start platform, `ChunkSpawner.reset()`, set `Workspace.NightMission`, and finally per player: add participant, `MissionGoals.beginRun`, `DistanceTracker.beginRun`, `FlowService.setPhase(player, "Mission")`, teleport, and connect a `Died` watcher.

Spawn positions are a lateral line at `HangarConfig.RUN_START_CFRAME` `(-4000, 5, 0)`, offset `(index - (count + 1) / 2) * SQUAD_SPAWN_SPACING` (8 studs) on X, so 3 players land at -8 / 0 / +8.

`TrackBuilder.build()` places the single fixed start platform (`START_PLATFORM_LENGTH` 64, built by `src/shared/util/LaneSectionFactory.luau`) at `RUN_ORIGIN + RUN_DIRECTION * (length / 2)`, i.e. centred 32 studs ahead of the spawn line. It previously ignored `RUN_ORIGIN` and pivoted to absolute `(0, 0, -32)`, 4000 studs east of where the squad actually lands; if you add another run-world builder, pivot relative to `RUN_ORIGIN` the same way.

Teardown is refcounted: `MissionService.removeFromMission` calls `tearDownIfEmpty`, which only fires when `MissionState.countParticipants()` hits 0, and then clears chunks, zombies, the start platform and the environment attributes.

### Streaming

`ChunkSpawner.step` runs every `Heartbeat` and does nothing unless a run is active.

```
lead        = DistanceTracker.getMaxDistance()       -- furthest player
spawn while   START_PLATFORM_LENGTH + i*128 < lead + SPAWN_AHEAD_DISTANCE (768)
cull   when   START_PLATFORM_LENGTH + (i+1)*128 < DistanceTracker.getMinDistance() - 160
```

Chunk `i` is pivoted to `RUN_ORIGIN + RUN_DIRECTION * (64 + i*128 + 64)`. Culling uses the *minimum* distance so a trailing squadmate never has the ground deleted underneath them.

### Route planning and biome blending

`extendPlan` builds a list of `{ locationId, startIndex, endIndex }` runs. Each entry picks a random id from `routePool` (the map's `locationIds`, or all five if the map is invalid or unset) with one re-roll if it matches the previous biome, then a length of `rng:NextInteger(lengthChunksMin, lengthChunksMax)`.

| Biome | Chunks | Floor | Lane style | Edge props | Zombies/chunk |
| --- | --- | --- | --- | --- | --- |
| City | 4-8 | Asphalt | road (markings) | buildings | 2-4 |
| Forest | 4-8 | Grass | field | trees | 2-5 |
| Wasteland | 3-5 | Ground | road | ruins | 3-5 |
| Farmstead | 4-7 | Ground | field | farm | 2-5 |
| Cornfield | 3-6 | Ground | field | corn | 2-4 |

The last `TRANSITION_CHUNKS` (2) chunks of each biome are blended into the next. `alpha = (index - blendStart + 1) / (TRANSITION_CHUNKS + 1)`, so the two transition chunks get alpha 1/3 and 2/3. `ChunkFactory.build` then:

- **Colours** lerp continuously: `location.floorColor:Lerp(next.floorColor, alpha)`, same for the apron.
- **Materials, textures, lane style, road markings and obstacle kind** switch wholesale at `far = alpha >= 0.5`, i.e. on the second transition chunk. This avoids half-materialised surfaces at the cost of one hard switch.
- **Edge props** are rolled per prop: `if next and rng:NextNumber() < alpha then kind = next.edgeProps`, so props interleave gradually.

Blended chunks are **not pooled**: `pooled = blend == nil`. Pure chunks go back into `pools[locationId]` on despawn and are reused verbatim; blended ones are destroyed.

### Chunk contents

`ChunkFactory.build(location, blend, rng, obstacleCount)` produces one 240x128 model: floor (`LANE_WIDTH` 240 by `CHUNK_LENGTH` 128), 2-5 blood stains, two invisible `Barrier` walls 60 studs tall just outside the lane, two 110-stud aprons, optional road markings in two lanes, the biome flanks from `WorldFlanks.build` (see below), telegraph-pole wire runs for farm and corn, biome-specific field fill, and in-lane obstacles.

**Corridor (2026-09-07, second pass).** `PLAYABLE_HALF_WIDTH` is 30 (ITD2's 7.5 m) and the floor is no longer a bare 240-stud plate up to an invisible wall: `ChunkFactory.buildCorridorEdge` walks each side from `corridorEdgeX` = ±34 and lays a continuous natural boundary. City: building fronts flush with the corridor (widths 18..30, depths 14..22), chainlink fence runs (`TexturesConfig.FENCE_CHAINLINK`, poles every 8), rows of parked cars with 18% police cars (white body, blue stripe, red/blue light bar with flickering lights), single police cars, rubble piles and jersey barrier rows. Forest: a tree every 5..9 studs with boulders. Wasteland: ruin walls, rubble, crashed cars, boulders. Farmstead: rail fences with posts every 6 and a tree behind. Cornfield: corn walls. Lane obstacles now fall in three lanes inside ±26, city debris in ±16..27, lamps at ±32.5. The far apron props stay as skyline. The `Barrier` walls at ±120 are now decorative; the `RunController` clamp at ±30 is the real edge and it always meets a prop.

**Flanks (2026-09-28).** The sparse apron props are gone. `src/server/systems/WorldFlanks.luau` fills x ±34..228 of every chunk per `edgeProps` kind in depth bands: a detailed near band framing the corridor, a cheaper middle band, and silhouettes at the back that read through fog. City: sidewalk and kerb, a continuous facade row from x ±56 (shopfront, awning, ledge and window strip per storey, cornice, roof units), a taller middle row with a few lit windows, skyline blocks. Forest: dark forest floor, trees on a jittered grid to x ±94 (shadows only within ±59), bushes, a canopy wall behind. Wasteland: ruin shells, dead trees, sand berms, mesas. Farmstead: crop rows, barns (35%), hay bales, a windbreak tree line at ±134, hills. Cornfield: tall crop rows with tassels from the corridor edge, a corn mass, hills. All flank parts are anchored with CanCollide, CanQuery and CanTouch off. City corridor-edge buildings are now 12% of slots (kerb clutter in front of the facades), the Cornfield corridor edge is left to the flank rows, and the in-corridor city building (`FIELD_CLUSTER_CHANCE`) is removed.

**City dressing (2026-09-07).** Building chunks also get street lamps along both aprons every 34..44 studs (post, arm, head; 72% carry a neon bulb with a warm 30-stud `PointLight`, shadows off, 30% of those tagged `TFZ_Flicker`), one or two burning barrels at the lane edges (`Fire`, `Smoke`, a flickering orange light), a 35% chance of a traffic jam (3..5 cars queued along the lane 13..16 studs apart) and a 30% chance of a smoke column rising from a roof line. `WorldVfx.stepFlicker` on the client toggles every `TFZ_Flicker` light within 220 studs at 11 Hz (12% chance to drop while lit, 55% to relight), which is what makes the dusk city read as inhabited rather than modelled.


Obstacle count comes from difficulty: `ChunkSpawner` computes `floor(obstacleDensity * rng(0.6, 1.4) + 0.5)` and `ChunkFactory` multiplies by `FIELD_OBSTACLE_SCALE` 3.2. Obstacles are placed one per lane across `max(3, floor(240/46))` = 5 lanes with a 0.75 chance each.

`ChunkSpawner` also mirrors the biome at the lead player's position into `Workspace.Biome`, which `LightingDirector` and `PostFx` read to pick presets.

### Fog and atmosphere

`src/client/systems/LightingDirector.luau` applies a `LightingConfig` preset every Heartbeat: clock, brightness, ambient, classic fog, `Atmosphere`, colour grading. Because an `Atmosphere` instance exists, the renderer ignores `Lighting.FogStart`, `FogEnd` and `FogColor`; every visible bit of fog comes from `Atmosphere.Density` and `Atmosphere.Offset`. Density alone below about 0.5 gives no wall at all: on a pillar stand at 30..240 studs the old City preset (0.38, no offset) showed every pillar crisp, which is why fog "was not visible". Since the 2026-09-06 visual pass every preset carries `atmosphereOffset` and densities of 0.8..0.95 (Hub 0.62/0.42, City 0.86/0.66, Forest 0.9/0.7, Farmstead 0.84/0.62, Cornfield 0.95/0.8, Wasteland 0.8/0.58, Night 0.92/0.76). At 0.9/0.7 pillars fade out between 120 and 160 studs while the sky stays visible, the Into the Dead silhouette look; `ZOMBIE_SPAWN_AHEAD` 200 stays inside it. Removing the Atmosphere and relying on classic fog was tried and rejected: it darkens geometry but leaves the sky clear, so silhouettes stand against a bright backdrop instead of dissolving. The `fogStart` / `fogEnd` preset fields are kept for a future no-Atmosphere fallback.

### Running and lateral control

`src/client/controllers/RunController.luau` disables the stock PlayerModule controls and, each `RenderStepped`, calls `humanoid:Move((RUN_DIRECTION + right * axis * LATERAL_SPEED_WEIGHT).Unit)` where `axis` is the -1/0/+1 from `InputController` (A/D or arrow keys, ContextAction-bound). It also hard-clamps the root X to `RUN_ORIGIN.X ± PLAYABLE_HALF_WIDTH` = ±45 by rewriting the CFrame. The chunk geometry stays 240 wide; only the playable band narrowed. Reason: `Humanoid:Move` takes a unit vector, so lateral speed can never exceed `WalkSpeed`, and at 24 the old ±118 band took 8.6 s to cross. At ±45 it takes 3.19 s (measured). A glance (see Damage) adds a decaying lateral term `glanceLateral` and a short input lock through `RunController.applyGlance(side, power)`.

Forward speed is server-side and, since the ITD2 pass, **constant by default**. `DistanceTracker.step` keeps a per-player `RunState` (`best`, `startedAt`, `speed`, `slowFactor`, `slowUntil`, stuck-watchdog fields), measures `root.Position:Dot(RUN_DIRECTION)` (monotonic), mirrors it into `leaderstats.Distance`, and slews `WalkSpeed` toward

```
target = min(locationTargetSpeed(elapsed) + SkillEffects.bonusSpeed(player), MAX_RUN_SPEED)
target *= slowFactor while slowUntil is in the future
```

at `RUN_SPEED_SLEW` = 12 studs/s². `locationTargetSpeed` reads `Workspace.Biome` (published by `ChunkSpawner`) and returns `BASE_RUN_SPEED` = 24 unless that location sets `runSpeedInitial` / `runSpeedMax` / `runSpeedRampTime` (a ramp over run seconds, not studs, so speed cannot feed back into itself). No location sets them today. `SkillEffects.bonusSpeed` now raises the target rather than a ceiling, because against a constant base a ceiling was never reached and the paid Endurance skill would have done nothing. The presentation curves keyed on speed (`CameraConfig` FOV 14..30, stride 8..30, exertion threshold 20, `AnimationsConfig.RUN_SPEED_REFERENCE` 24, `VfxConfig.JUKE_MIN_SPEED` 20) were re-centred on 24 in the same change.

`src/client/controllers/CameraController.luau` keeps the camera `Scriptable` and rewrites its CFrame every frame toward `lookAt(eye, eye + RUN_DIRECTION * LOOK_AHEAD)`, so mouse input cannot turn it (measured 2026-09-06: yaw stayed within -0.2..0.6° across full-width mouse sweeps). All living motion comes from `CameraEffectsController` on top of that lock: bob 0.2/0.12 studs, roll 0.8°, sway 0.1, breath 0.07 studs and 0.6° pitch, hit shake, and the `AimAssist.cameraPull` nudge. If first person ever turns a full 360°, `DevConfig.THIRD_PERSON_VIEW` is on: that review-only switch hands the camera to Roblox's orbit controller.

`DistanceTracker` also runs the anti-stuck watchdog: every 2 s per participant, if `best` grew by less than 6 studs a strike is counted; 2 strikes relocate the root sideways toward the lane centre (14/28/42-stud candidates, raycast for ground, never forward, so no distance is granted), 5 strikes set `Health = 0`. Exempt for the first 3 s of a run, while dead, and under `DevConfig.FREEZE_RUN` in Studio.

### Difficulty

`src/shared/config/DifficultyConfig.luau`, held by `MissionConfig` and mirrored to the `Workspace.Difficulty` attribute (writable from the command bar for testing: `MissionConfig.init` listens for changes and validates them).

| | Easy | Medium | Hard |
| --- | --- | --- | --- |
| `zombiesChase` | true | true | true |
| `zombieSpeedMultiplier` | 0.45 | 0.6 | 1.15 |
| `damageMultiplier` | 0.6 | 1 | 1.35 |
| `aggroDistance` | 300 | 0 | 0 |
| `rewardMultiplier` | 1 | 1.25 | 1.5 |
| `obstacleDensity` | 0.8 | 1.6 | 2.6 |
| `ammoCrateChance` | 0.5 | 0.38 | 0.28 |

Easy used to be a frozen diorama (speed multiplier 0 and an unreachable aggro distance). Since the ITD2 pass it is a slow chase instead: the gate opens at 300 studs (800 in the first cut), chase speed is 0.45x (a Walker closes at 6.3 studs/s against a 24 studs/s player), damage is 0.6x, and the spawn-section tier is shifted down by one. Hard still aggroes from the first stud and shifts tiers up by one. The difficulty id shifts the spawn-section tier by -1/0/+1 (see Spawning).

---

## Zombies

Files: `src/server/systems/ZombieAI.luau`, `ZombieFactory.luau`, `ZombieAnimator.luau`, `ZombieRigs.luau`, `ZombieHitboxes.luau`, configs `ZombiesConfig`, `ZombieSkins`, `GameConstants`; client `src/client/systems/ZombieAudio.luau`, `ZombieVfx.luau`

### Archetypes

`ZombiesConfig` is an **array**, not a map: iteration order is the weight-roll order.

| | Walker | Runner |
| --- | --- | --- |
| Spawn weight | 4 | 1 |
| Health | 100 | 60 |
| `walkSpeed` (calm) | 5 | 8 |
| `alertSpeedMultiplier` | 2.8 | 2.75 |
| Chase speed (product) | 14 | 22 |
| Touch damage | 15 | 10 |
| Damage cooldown | 1.0s | 0.8s |
| `reactionDelay` | 0.75s | 0.35s |
| `awareRadius` / `alertRadius` / `attackRadius` | 110 / 70 / 4.5 | 130 / 95 / 4.5 |
| `turnToFacePlayerChance` | 0.85 | 1.0 |
| `collisionDeathDistance` / `collisionGlanceDistance` | 1.7 / 3.8 | 1.5 / 3.2 |
| `glancePower` | 1.0 | 1.4 |

Second pass, 2026-09-07, from the 144 `ZombieDefinition` and 7 `ZombieMovementDefinition` assets in `level_zombies.bundle` (read with UnityPy): `awareRadius` 140, `alertRadius` 120, `attackRadius` 60 (35/30/15 m), `turnToFacePlayerChance` 0.8 walker / 1.0 runner, `collisionDeathDistance` 2, `collisionGlanceDistance` 4 (0.5 / 1 m), `glancePower` 2 / 3 against `ZombieBehaviourConfig.GLANCE_POWER_REFERENCE` 3. Speeds are `speedMin`..`speedMax` = 0.8..8 studs/s for walkers (`ZMD_Walker` 0.2..2 m/s) and 16..20 for runners (`ZMD_Hunter` 4..5 m/s), shaped by the shared speed curve `(0,0) (0.05,0) (0.05,0.6) (1,1)` over `distance / alertRadius` and ramped in over `ALERT_ACCELERATION_DURATION` 1 s when a zombie turns alert. Chasing zombies re-aim every `facingUpdateFreq` 0.5 s at `player + velocity x 0.5 s x playerLeading` (0.8 / 0.9) and turn at most `maxRotation` 60°/s, driven through `Humanoid:Move` with a rate-limited heading; `Aware` zombies turn their body toward the runner at 60°/s without moving. The old delayed-position juke and `reactionDelay` are gone: the 0.5 s sample-and-hold plus the turn limit is ITD2's juke. Medium and Hard now have `aggroDistance` 0 (Easy 300), because ITD2 zombies react from the first metre. Measured on Medium: walkers ramp 0.5 -> 4.3 studs/s in the first second, then 4.0 at 65 studs, 3.6 at 35, 3.1 at 10 as the curve eases them into bite range.

**Smoothing (2026-09-09).** The 5 Hz tick only decides mode, speed and a `desiredHeading`; `ZombieAI.smoothStep` runs every Heartbeat and turns each zombie's `heading` toward it at `turnRate` (60°/s chasing, `AWARE_TURN_RATE` while facing) before calling `Humanoid:Move`, so `AutoRotate` follows a direction that changes a little every frame instead of jumping 12° five times a second. Aware zombies rotate the root the same way, only when the look vector differs. Zombie torsos sit in the `Zombies` collision group, which does not collide with itself (`PhysicsService:CollisionGroupSetCollidable`), so clumps no longer shove each other and jitter; spawn separation keeps them apart, the player still collides. The Quaternius zombie clips fold the torso 80° at the waist, which read as retching on our rig, so `glb_to_keyframes.py --posture UpperTorso=0.4,LowerTorso=0.6,Head=0.8` scales those joints' whole rotations (axis-angle, not Euler pitch) and the shuffle, idle and scratch were re-uploaded at 20..35° of lean; the baked hunch in `ZombieFactory` is now -4..0° at the waist. Spawn spread: the lateral maximum holds at 30..32 studs instead of ramping to 16 (only a fifth of ITD2 sections ramp it, the median holds), the outside border is 10, clump separation 6.5 and the spawner places at most 3 events per tick, so the corridor fills as a spread rather than a line.

**Look.** The whole rig is built at `ZombieFactory.SCALE` = 0.86 (sizes, positions and joint pivots; the 6x5x3 `Hitbox` stays in world units), so a zombie's eyes sit at 4.4 studs, level with the runner's camera at 4.3, instead of 0.8 studs above it; at 1.0 they read as giants from first person. `ZombieFactory.build` gives each instance a random tint (`bodyColor` lerped 0.15..0.45 toward one of four dark palette colours, trousers darker, head a skin tone lerped toward the body), a random hunch (`Waist` -9..-20°, `Neck` 4..14°, shoulders 16..34° forward with ±5° asymmetry) and neon eyes held to the head by a `Weld` with an explicit `C0`. Body parts carry no `Texture` instances: the global `TFZ_Fabric` override supplies the cloth PBR tinted by `part.Color`, whereas the old opaque `Texture` hid the colour and every zombie read as light grey. `Humanoid.HipHeight` is `ZombieFactory.HIP_HEIGHT` = `ROOT_HEIGHT - SCALE`, because HipHeight is measured from the bottom of the root part and the legs end `ROOT_HEIGHT` below the root centre; with the old value of 2.35 the Humanoid held every rig a stud in the air (measured 0.97 studs average over 18 live zombies). `ZombieAI` places the root at ground + `ROOT_HEIGHT`.

### Skinned rigs (2026-09-29)

Files: `src/shared/config/ZombieSkins.luau`, `src/server/systems/ZombieRigs.luau`, `src/server/systems/ZombieHitboxes.luau`, `ZombieFactory.buildSkinned`

Zombies are now three skinned Sketchfab characters (CC BY 4.0) that come with their own authored clips. The **Look** notes above and the rig paragraph under Spawning describe the older rigs, which are only built when a skin's rig asset has not loaded. `ZombieSkins.byConfig` maps the `ZombiesConfig` archetypes onto skins:

| Archetype | Skin | Source (skeleton) | Weight | Clips (ground speed in studs/s at playback 1) |
| --- | --- | --- | --- | --- |
| Walker | Walker | "Zombie" by pxltiger (3ds Max Biped) | 65% | idle, walk a/b (0.876), run (12.0), attack, death back/forward |
| Walker | Hazmat | "Zombie Hazmat" by LxNazarov (Mixamo) | 35% | idle, walk (0.774), spotted scream, attack; `maxSpeed` 2 |
| Runner | Ghoul | "ZOMBIE. Animation test for the game" by stasbelyk13 (Blender) | 100% | idle a/b, walk a/b (5.9, 9.0), run a/b (15.2, 20.7), attack a/b, death back/forward, hit |

`ZombieSkins.get` only returns a skin whose rig asset id and idle clip are both live, and `pick(configId, rng, withDeath)` re-weights over the usable skins; corpse props ask for skins with a death clip, so they never wear the Hazmat. Each skin also names its head, chest and hips bones and the bone pairs and widths of eight limb segments, using the bone names Roblox gave on import (`Base HumanHead_09`, `mixamorig:Head_06`, `Bone.005_3`).

`ZombieRigs` loads each rig Model with `InsertService:LoadAsset` at require time into `ServerStorage.ZombieRigs`: the part holding the Bones is renamed `Rig` (the clips address it by that name), the importer's `AnimationController` and `InitialPoses` are removed, and every visual part is made non-colliding, non-queryable and massless. `ZombieFactory.build` waits up to 8 s for the template and falls back to the older rig if it never arrives.

`buildSkinned` makes a plain HumanoidRootPart at the usual `ROOT_HEIGHT`, stands the rig's root bone on the ground (shifted by the skin's `offset`) and joins the rig to the root with a Motor6D named `Root`. The Ghoul needs `offset` (0, 3.077, -0.2): every one of its 11 clips holds `Bone.009` 3.08 studs below its bind pose, which sank the body into the floor. The model carries `ZombieSkin` and, for capped skins, `MaxSpeed` attributes; `ZombieAI` clamps the chase speed to `MaxSpeed`.

**Hit boxes.** Roblox raycasts a skinned MeshPart against its bind pose (a T-pose), so bullets hit invisible boxes instead: `Head`, `Chest`, `Hips` and the eight limb segments (`LeftUpperLeg` .. `RightLowerArm`), sized from the bone positions at build time. `ZombieHitboxes.attach` joins each box to the root with a Motor6D, and every `PreSimulation` (after the Animator has posed the bones, before physics moves the assembly) writes its `Transform` so the box sits on `bone.TransformedWorldCFrame`. `Transform` does not replicate, which is fine because only the server raycasts. Zombies more than 220 studs from every player (re-checked every 0.5 s) keep their boxes where they are. The boxes are `CanQuery` only, and a part named `Head` is still what `WeaponService.handleHit` treats as a headshot.

**Blockers.** None of the hit boxes collide: a bone-driven colliding box that dips below hip height in a lunge or stumble dragged the Humanoid over. Player collision comes from two static boxes welded to the root above hip height, `LowerTorso` (from `HIP_HEIGHT + 0.2` to just above the hips) and `UpperTorso` (from there to just under the head), which keep the names the rest of the game already toggles (`ZombieRig.torso`, sleepers, death). The 6x5x3 touch `Hitbox` is unchanged, so the grab and glance bands work as before.

**Gaps.** Skinned zombies have no rise or feeding clip. Riser and feast formations therefore spawn as ordinary idle zombies (`holdLying` and `hasFeedingClip` return false), and head tracking and the procedural corpse chew do nothing because there is no `Neck` or `Waist` Motor6D.

### Spawning

Spawning is no longer tied to chunks. `ChunkSpawner` builds geometry only; `ZombieAI.spawnStep` runs on the same 0.2 s tick and is driven by **distance**: it keeps `nextSpawnAt` on the run axis and fires while `lead + ZOMBIE_SPAWN_AHEAD (200) >= nextSpawnAt`, at most `MAX_SPAWN_EVENTS_PER_STEP` = 8 events per tick. Each event advances `nextSpawnAt` by `rng(spawnDelayMin, spawnDelayMax) * BASE_RUN_SPEED` studs. Because the trigger is distance, placement is a pure function of the seed, density is per stud rather than per second, the corridor primes itself at `lead = 0`, and a player frozen by `DevConfig.FREEZE_RUN` accumulates nothing. `ZombieAI.configure` starts `nextSpawnAt` at `ZombieSpawnConfig.START_CLEARANCE` = 140 studs (about 6 s of running), because at 0 the first event landed on the start line itself and, once a frontal collision became a grab, killed the runner before the first stride. 200 studs is inside every biome's fog (105..168), so there is no pop-in.

What an event spawns comes from `src/shared/config/ZombieSpawnConfig.luau`. A location lists `spawnSections: { string }?`; `src/server/systems/RoutePlan.luau` (the route plan extracted from `ChunkSpawner`, seeded from `seed`; `ChunkSpawner` uses `seed + 1`, `ZombieAI` `seed + 2`) splits that location's stretch into equal bands, one per section, and returns the section id plus progress `t` in 0..1 for the spawn point. `ZombieSpawnConfig.resolve(id, t, tierOffset)` composes three tables that own disjoint fields: `densityTiers[1..5]` (spawn delay range, `maxAlive`), `difficultyTiers[1..5]` (lateral band, side bias, `alertChance`), `clumpPresets` (`None` / `Small` / `Large`: chance, radius, size). Every field is a `Ramp { start, finish, curve }` evaluated at `t` with `linear` / `easeIn` / `easeOut` / `hold`. The difficulty id shifts both tiers by -1/0/+1. Delays per density tier are 1.6 / 0.9 / 0.55 / 0.35 / 0.22 s, taken from medians over the 1365 reference sections; clump radius 12 studs and size 2..3 likewise (the "radius 8 m, size 7..9" example in the teardown is an outlier).

Lateral placement is **player-relative**: `x = clamp(leadX ± rng(lateralMin, lateralMax))`, so the threat corridor follows the player and the visible lane can stay 240 wide. With City opted in (`Steady_Mixed` -> `Pressure_Mixed` -> `Pressure_Clumped`) the measured lateral spread from the player fell from 87..111 studs to 28..59 and the in-fog count rose from 4..6 to 8..20. A location without `spawnSections` gets a flat fallback section derived from its old `zombiesMin`/`zombiesMax` (`delay = CHUNK_LENGTH / BASE_RUN_SPEED / mean`), which is density-neutral per stud. All five biomes are opted in: City `Steady_Mixed -> Pressure_Mixed -> Pressure_Clumped`, Forest `Calm_Open -> Steady_Walkers -> Pressure_Mixed`, Wasteland `Steady_Mixed -> Heavy_Clumped` (short and brutal), Farmstead `Steady_Walkers -> Steady_Mixed -> Pressure_Clumped`, Cornfield `Calm_Open -> Pressure_Clumped` (nothing, then everything; the 24-stud fog does the rest). The fallback remains for any future location that omits the field. Measured on Medium across City and Wasteland: 20..35 alive, 3..21 in fog, zero Heartbeat frames over 33 ms in 110 s (peak 24.6 ms).

**ITD2 numbers (2026-09-07, second pass).** The section tiers were rebuilt from the medians of the 1365 real `ZombieSpawnSection` records (`docs/research/ITD2_spawn_sections.json`), converted at 4 studs per metre: spawn delay by density tier 2.0->1.2 / 0.8->0.5 / 0.35->0.3 / 0.2 / 0.1->0.06 s, lateral distance from the runner 0..48->16 / 0..32->16 / 0..30->16 / 0..32->24 / 8..28 studs, clump chance 0.14->0.4 (Small), 0.21->0.6 (Large), 0.7 (Heavy) with radius 12->24 and size 2..6, lying chance up to 0.3, eating chance 0.02..0.03, runner share 0.05..0.15 (`runnerChance` replaces the global 4:1 weight), stand-up distance 120..160 studs (ITD 30..60 m). Every spawned zombie rolls lying (`Dormant`, stands up at `standUpDistance`) then eating (`Feeding` beside a corpse prop, wakes at `alertRadius x 0.5`) exactly as `m_lyingDownChance` / `m_eatingChance` do; the default `patternSet` is `Corridor` (single events plus ITD clumps) and the formation set below is kept as an opt-in. Zombies only spawn where a ray down lands on `Floor` or `Apron`, never on props. `GameConstants.ZOMBIE_SPAWN_BORDER` 6 mirrors `m_spawnXOutsideBorderWidth`.

**Formations (2026-09-07).** A spawn event no longer means "one zombie or a random clump". Each section names a `patternSet` in `ZombieSpawnConfig.patternSets` (Calm, Steady, Pressure, Heavy) and every event draws a pattern from it with the seeded RNG (`ZombieSpawnConfig.pickPattern`): `single`, `clump` (the old radius clump), `wall` (5..6 zombies across the corridor 8 studs apart with one 14-stud gap at a random slot, the Into the Dead gate), `diagonal` (3..5 staggered 7 studs sideways and 6 forward), `column` (3..4 in a line along the run, a flank to skirt), `loiter` (2..3 calm zombies at the edge of the playable band), `risers` (2..4 zombies lying on the ground in the `LayToIdle` first frame, mode `Dormant`, anchored and untouchable, who play the rise clip when a runner is within 60% of `awareRadius` and then join the normal state machine) and `feast` (a corpse prop plus three zombies in mode `Feeding` kneeling around it on the feeding clip, who stand and give chase when a runner is within 55% of `alertRadius`). Sleepers are skipped by the AI tick, cannot grab, collide only through the ground and are reaped by the same distance cull; corpse props live in `Workspace.ZombieProps` (a `ZombieFactory` build with the Humanoid, hitbox and eyes removed, laid supine over a stain) and are culled and cleared with the zombies. Tuning lives in `ZombieSpawnConfig.formations`. Calm sections lean on loiter and risers, Pressure and Heavy on walls and clumps, so density rises through shape as well as count.


Clumps roll `clumpChance`, place `rng(sizeMin, sizeMax)` zombies on a jittered disc of `clumpRadius`, and are capped by `maxAlive - aliveCount`. Placement retries up to `SEPARATION_RETRIES` = 4 times against `MIN_SEPARATION` = 8 studs (5 inside a clump). Each spawn raycasts for ground and sits the root at `hit.Y + ZombieFactory.HIP_HEIGHT`. `alertChance` spawns a zombie already in `Alert`. A hard `MAX_ALIVE` = 60 backstops everything.

Models come from a **pool** keyed by archetype (`MAX_POOLED` = 24 each, flushed by `ZombieAI.configure(seed)` which `MissionService.startSquad` calls next to `ChunkSpawner.configure`). `Touched` and `Died` are connected once when a model is built and resolve `zombies[model]` at fire time, so a reused model cannot double-fire. Only models retired **alive** are pooled: a dead `Humanoid` cannot be revived by raising `Health` (the same reason `DevBench.respawnTarget` rebuilds its dummies), so `Died` leads to `recycle`, which destroys. Lifetime is by distance, not chunk: any zombie behind `DistanceTracker.getMinDistance() - DESPAWN_BEHIND_DISTANCE` (the last player, so a straggler keeps theirs) is recycled each tick; `clearChunk` is gone. Feeding zombies are `locked` and skipped by the reaper and by `Touched`.

The fallback rig (`ZombieFactory.build` when no skinned rig applies, see Skinned rigs above) is a reduced R15: `HumanoidRootPart`, `LowerTorso`, `UpperTorso`, `Head`, upper arms and upper legs, joined by `Motor6D`s named exactly `Root`, `Waist`, `Neck`, `LeftShoulder`, `RightShoulder`, `LeftHip`, `RightHip`, plus two neon eyes welded to the head and an invisible 6x5x3 `Hitbox` welded to the root that carries the `Touched` connection. `Humanoid.RigType = R15`, `HipHeight = 2.35`, `BreakJointsOnDeath = false`. Anything that needs a zombie's torso goes through `src/shared/util/ZombieRig.luau` (`torso`, `waitForTorso`, `neck`), never `FindFirstChild("Body")`. See [[Decisions]] for why reduced rather than full.

### The AI tick

`ZombieAI.init` accumulates `Heartbeat` deltas and runs `aiStep` every `ZOMBIE_AI_TICK` = 0.2s. One step does:

1. `recordPositions()`: append `{ t, pos }` for every participant, trimming samples older than `HISTORY_WINDOW` = 2s.
2. Compute `speedScale = difficulty.zombieSpeedMultiplier * (1 + sum of modifier zombieSpeedBonus)`.
3. Compute `aggroActive = difficulty.zombiesChase and DistanceTracker.getMaxDistance() >= difficulty.aggroDistance`. This is a **global** flag for the whole horde, not per zombie. When it flips, `Workspace.ZombiesAggro` is updated, which is what the client audio and VFX layers react to.
4. Reap every unlocked zombie behind `getMinDistance() - DESPAWN_BEHIND_DISTANCE` into the pool.
5. Per zombie: a corpse lure within `LURE_RANGE` 80 overrides everything (`MoveTo(lure)` at alert speed). Otherwise find the nearest player and resolve a **mode**: `Idle`, `Aware` (inside `awareRadius`), `Alert` (inside `alertRadius`), `Attack` (inside `attackRadius`), with a x1.25 exit hysteresis so it does not chatter at 5 Hz. `Aware` is the ceiling while the global aggro gate is off, and for the fraction of zombies whose `turnToFacePlayerChance` roll failed at spawn (`state.facesPlayer`). Only `Alert`/`Attack` call `Humanoid:MoveTo` and get `AutoRotate`; everything else head-tracks. `WalkSpeed` is `walkSpeed * speedScale` when calm and `walkSpeed * alertSpeedMultiplier * speedScale` when chasing, so `zombieSpeedMultiplier = 0` still freezes Easy in every mode. Zombies farther than `AI_FULL_RANGE` = 180 from the nearest player are evaluated every 4th tick (`strideOffset` staggers them). A mode change is the only thing that calls `ZombieAnimator.setMode`.

The accumulator carries its remainder (`-= ZOMBIE_AI_TICK`), so the tick is an honest 5 Hz. `spawnStep` runs just before `aiStep` on the same tick.

**Swing, scream and speed cap (2026-09-29).** A chasing zombie within `ATTACK_REACH` 7 studs of its target starts `ZombieAnimator.attack` (one of the skin's attack clips, sped up so a swing never lasts more than 1.8 s) and walks at 30% of its chase speed (`ATTACK_SLOWDOWN`) until the swing ends; damage still comes only from the `Hitbox` touch. The chase speed is capped by the model's `MaxSpeed` attribute (Hazmat 2 studs/s). The first time a zombie turns `Aware` it plays the skin's `spotted` clip once (Hazmat only, at 1.4x so the 5.4 s scream does not stand for 5 s).

### Aggro, per difficulty

| Difficulty | Behaviour |
| --- | --- |
| Easy | Gate opens once the lead player passes 300 studs; chase at 0.45x speed, 0.6x damage, a frontal grab costs health instead of the run. |
| Medium | `aggroDistance = 0` since the ITD2 values pass (it was 500): the gate is open from the first stud and each zombie escalates on its own radii (Aware 140, Alert 120), so the horde wakes as a gradient rather than all at once. |
| Hard | `aggroDistance = 0` at 1.15x speed and 1.35x damage; the radii still decide who moves. |

The global flag stays as a master switch because six client systems read `Workspace.ZombiesAggro`. While a zombie is `Idle` or `Aware`, `trackPlayerWithHead` rotates the neck `Motor6D` (fallback rigs only; skinned rigs have no `Neck` joint) toward the nearest player within `HEAD_TRACK_RANGE` 70, clamped to ±60° yaw and ±0.4 rad pitch (halved before applying). This is what makes the passive horde feel alive.

### The juke

**Superseded (2026-09-07).** `reactionDelay` and the position history are gone; the ITD2 re-aim every `facingUpdateFreq` 0.5 s with the 60°/s turn limit is the juke now (see the second-pass paragraph under Archetypes). The original design, kept for reference:

The mechanic that makes lateral input matter. An aggro'd zombie does not chase the player's *current* position: it chases

```lua
getDelayedPosition(target, root.Position, config.reactionDelay)
```

which walks the 2-second sample history and returns the newest sample older than `now - reactionDelay`. A Walker (0.75s) is aiming at where you were three quarters of a second ago and can be sidestepped; a Runner (0.35s) tracks much tighter. Targets are limited to the nearest player within `GameConstants.ZOMBIE_AGGRO_RANGE` = 120.

If you change `reactionDelay`, note that values above `HISTORY_WINDOW` (2s) silently clamp to the oldest sample.

### Damage

Contact only, through the invisible `Hitbox` (the old 2x3x1 body left under 2 studs to tell a graze from a hit). `onTouched` resolves the player, applies the per-(zombie, player) `damageCooldown`, ignores `locked` feeders and rear brushes, then measures the lateral offset between the player and the zombie root along `RUN_DIRECTION:Cross(Y)` and picks one of three bands:

| Lateral offset | Result |
| --- | --- |
| `<= collisionDeathDistance` | `TakeDamage(touchDamage * difficulty.damageMultiplier)`; the existing `HealthChanged` reactions fire |
| `<= collisionGlanceDistance` | No damage. `DistanceTracker.applySlow(player, 1 - 0.45 * power, 0.35 + 0.45 * power)` and `Remotes.Event.PlayerGlanced:FireClient(player, side, power)` |
| beyond | Nothing. A true edge miss now exists |

`power = clamp(0.35 + 0.65 * centrality * glancePower, 0, 1)` where centrality is 1 at the death edge and 0 at the outer edge. Measured: a 2.7-stud graze cost 0 health and dipped `WalkSpeed` from 24 to 17.26, matching the formula. On the client `src/client/controllers/GlanceController.luau` turns the event into `RunController.applyGlance` (lateral shove and a 0.22 s input lock), `CameraEffectsController.impulse` / `fovKick`, `BodyMotionController.impulse` and `AnimationController.playOneShot("Stumble")` (silent until the clip is uploaded). A hit inside `collisionDeathDistance` is a **grab**: on Medium and Hard (`DifficultyConfig.grabLethal = true`) the server sets `DeathCause = "Grabbed"` on the player and drains the humanoid through `TakeDamage(Health)`, so a `ForceField` from a revive still protects; on Easy the grab deals `touchDamage * 3 * damageMultiplier` = 27 instead. Corpses (`humanoid.Health <= 0`) never touch. The client damage reactions in `CameraEffectsController`, `PostFx`, `PlayerSfx` and `GoreController` all skip a hit that lands at zero health, so a grab plays the death sequence alone rather than a bite flash plus a death. The two reaction paths cannot double up: a glance deals no damage, a hit sends no glance. Speed loss stays on the server because `DistanceTracker` rewrites `WalkSpeed` every Heartbeat; the shove stays on the client because the character's network ownership already lets the client move its own X.

### Corpse lure and feeding

Two entry points used by `DeathService`:

- `swarmCorpse(position, duration)` sets a global lure; every zombie within 80 studs walks to it for the duration (8s).
- `feedOnCorpse(position, duration, maxFeeders)`, called 1.1s later with `maxFeeders = 5`, sorts nearby zombies by distance, takes the closest 5, arranges them on a 3.4-stud ring facing the corpse, sets `WalkSpeed = 0`, anchors their roots, plays the feeding animation, and drives a `Heartbeat` loop that bobs and leans each one (42° ± 12° pitch, `sin(elapsed * 5 + phase)`). Roots are unanchored when the duration expires.

`clearLure()` is called on revive so the horde disperses.

### Animation

**Skinned path (2026-09-29).** `setupSkinned` loads every idle, walk, run, attack and death clip of the skin (plus `hit` and `spotted` where it has them), with a second idle at Core priority as a base layer so a fading switch never shows the bind T-pose. Walk and run clips are pooled as moves, each with its ground speed from `ZombieSkins`. `chooseMove` scores every move at the zombie's current speed: the skating left once the playback rate is clamped to 0.55..2.4, plus 0.3 x how far that rate is from 1 (both as log ratios); a new clip has to win by 0.25 so the cycle does not flap while the AI eases the speed. The winner plays at `speed / groundSpeed`, which keeps the feet planted, and `setSpeed` re-runs the choice every tick. A Walker-skin zombie at 3 studs/s shuffles on its walk and at 8 breaks into the run; the Ghoul moves through four cycles from 5.9 to 20.7 studs/s. The Ghoul's `hit` clip plays as a flinch on any damage while it moves at 4 studs/s or less. On death `playDeath` stops every track but the base, plays a death clip and freezes it 0.1 s before its end (a finished non-looped track would snap the rig back up); `ZombieAI.onDied` anchors the root upright at its current yaw and turns the torso blockers off, and the body is recycled after `ZOMBIE_CORPSE_LIFETIME` (2 s). A skin without a death clip (Hazmat) falls without one. Corpse props have no Humanoid, so `poseCorpse` adds an `AnimationController` and holds the last frame of a death clip.

**Fallback path.** `ZombieAnimator.setup(model, humanoid, rng)` loads five tracks from variant arrays (`IDLE_VARIANTS` x3, `WALK_VARIANTS`, `RUN_VARIANTS`, each entry picked with the seeded `rng` rather than the old position hash, which made a whole clump pick the same idle) plus a lunge and a feeding loop. Each zombie also draws a `phase` in 0..1 and a speed `jitter` in 0.9..1.12. Every looped track starts through `playLooped`, which plays, `AdjustSpeed`s, and after 0.1 s sets `TimePosition = phase * Length` (`Length` is 0 until the asset has loaded).

`setMode(tracks, mode, fast, walkSpeed)` cross-fades walk/run (`fast` is `config.id == "Runner"`), plays the lunge on `Attack` (the track that was loaded but never played before), and scales the moving clip by `clamp(walkSpeed / 14, 0.35, 1.6) * jitter`; the floor matters because Easy sets `WalkSpeed = 0`, which would freeze the clip.

Every `loadTrack` returns `nil` when the asset id is 0, and every consumer is nil-tolerant, so a clip that is missing or rejected leaves a still pose rather than an error. The fallback clips are the Quaternius set (walk and run references 2.5 and 4.3 studs/s on walker2); the skinned clips come from the Sketchfab packs. See [[Assets Pipeline]].

### Audio and VFX

`src/client/systems/ZombieAudio.luau` layers four things: a looping growl attached to each zombie on spawn, periodic 3D idle moans from nearby bodies, a one-off alert bark volley when `Workspace.ZombiesAggro` flips true, and a horde walla loop whose volume scales with the count of zombies inside `SfxConfig.HORDE_WALLA_RANGE`, saturating at `HORDE_WALLA_FULL_COUNT`.

`src/client/systems/ZombieVfx.luau` handles blood bursts (and occasional lingering ground stains, gated on the `bloodEnabled` setting) plus a dirt "wake up" burst on nearby zombies when aggro engages.

`src/client/systems/UiSfx.luau` also watches the horde: its `Heartbeat` loop ducks the music whenever an aggro'd zombie is within `MUSIC_DUCK_RANGE`.

With `SfxConfig.SPATIAL_AUDIO` on (2026-09-29) the growl is a `ZombieLoop` voice and the moans, barks and bites are `ZombieVocal` / `Bite` voices of the spatial audio engine, following the torso: they get the class curve (140 studs for vocals, 90 for the growl), air absorption, an occlusion ray, the doorway loss across an `AcousticSpace` boundary and the speed-of-sound delay; the walla is a 2D ambience bed. See [Spatial audio](#spatial-audio).

---

## Spatial audio

Files: `src/client/audio/` (`AudioMath`, `AudioBus`, `AudioEnvironment`, `AudioEngine`, `AudioReflections`, `AudioDebug`), config `src/shared/config/SpatialAudioConfig.luau`, tests `tests/audio/run.luau`, design and Studio test plan `docs/audio/spatial-audio.md`, weapon-side changes `docs/audio/weapons-integration.md`. Flag `SfxConfig.SPATIAL_AUDIO` (default on since branch `cloud/spatial-audio`); `SfxConfig.ACOUSTIC_SIMULATION` swaps the engine's own occlusion and reverb for Roblox's client-beta simulation.

Every non-weapon sound is played through `AudioEngine.play({ key or id, class, position or follow, volume, pitch, delay, loop })`, which returns a handle (`stop(fade)`, `setVolume`, `setPitch`, `fade`, `setPosition`, `isPlaying`). A voice is `AudioPlayer -> AudioFilter (Lowpass12dB) -> AudioEmitter` for 3D, or the bus fader for 2D, from a fixed pool (48 desktop, 24 mobile; steals by priority, then by distance and age, class limits first). Per class (`SpatialAudioConfig.classes`): bus, audible range and hold radius, curve shape (`natural` inverse with taper, `power` for loud sources, `linear` for loops), air absorption strength, occlusion strength, reflections, priority, voice limit, speed-of-sound delay, duck send, jitter, and optional close / mid / far layer bands.

What a 3D voice gets every update (near voices every frame, far every fourth; mobile every second and sixth):

| Effect | Mechanism | Numbers |
| --- | --- | --- |
| Distance | `AudioEmitter:SetDistanceAttenuation` with the class curve, 13 points | e.g. `ZombieVocal` 140 studs, hold 8; `GunshotRemote` 1400, hold 24; `Explosion` 2600, hold 60 |
| Air absorption | filter cutoff from ISO 9613-1 at 6x, 25 m knee, scaled by the class `air` | 22 kHz to 90 studs, 11.7 kHz at 107, 4.5 kHz at 180, 3.2 kHz at 250, 1.2 kHz floor |
| Occlusion | one ray listener to source (two for gunshots and explosions), material table, smoothed (open 0.12 s, close 0.25 s) | stone -30 dB / 600 Hz, metal -26 / 900, wood -18 / 1500, glass -16 / 3000, soft -10 / 2500 |
| Doorway | source and listener in different `AcousticSpace` zones | -9 dB, 2.5 kHz, 0.3 s glide |
| Delay | `AudioPlayer:Play(SoundService:GetMixerTime() + distance / 1225)` on one-shots | 36 studs 29 ms, 154 studs 125 ms, 357 studs 292 ms |
| Layers | equal-power crossfade of close / mid / far keys; a missing key falls back to the nearest one | `GunshotRemote` 0..60 / 40..350 / 250..1400 |
| Reflections | a 6-ray fan (3 mobile) from gunshots and explosions, one `Reflection` voice per hit, delayed by the extra path, filtered by the surface, taps under 40 ms dropped, at most two indoors | range 140, gain 0.55, live cap 12 (6 mobile) |
| Environment | listener zone, biome and phase pick `Hangar`, `Interior`, `Street`, `Forest` or `Open`; the bus reverb and slapback glide to the preset in 0.5 s | Street: decay 0.9 s, wet -20 dB, slap 85 ms; Interior: 1.4 s, -12 dB; Open: 0.3 s, -30 dB |
| Mix | ambience and music duck under weapons and explosions through a sidechain compressor (threshold -24 dB, ratio 4, 5 ms / 600 ms); ui joins after it; master limiter -1 dB | settings drive the master and music faders through `MusicController` |

The per-frame budget: 8 occlusion rays (4 mobile), no allocations, at most one filter and one volume write per updated voice. `AudioDebug.toggle()` (key N once the main session binds it in `SandboxInput`) lists every voice with its distance, delay, occlusion, cutoff and volume; `AudioDebug.fireTestShot()` (key M) plays a remote rifle shot with its reflection fan 30 studs ahead.

## Weapons

Files: `src/server/systems/WeaponService.luau` (server authority), `src/server/systems/WorldWeapon.luau` (third-person model), `src/server/systems/ViewmodelPacks.luau` (pack rig loader), `src/client/systems/WeaponController.luau` (input and prediction), `Viewmodel.luau`, `PackViewmodel.luau`, `ViewmodelClipPlayer.luau`, `WeaponSfx.luau`, `WeaponVfx.luau`, configs `src/shared/config/WeaponsConfig.luau`, `ViewmodelPackConfig.luau`, clip modules `src/shared/viewmodel_clips/`

### Config

| | Pistol (M9) | SMG (K10) | Shotgun (S870) | Rifle (R4) |
| --- | --- | --- | --- | --- |
| Damage | 34 | 16 | 12 x 8 pellets | 30 |
| Headshot | x2 | x1.8 | x1.5 | x2 |
| Fire rate (/s) | 5 | 11 | 1.25 | 8 |
| Auto | no | yes | no | yes |
| Mag / reserve mags | 12 / 4 | 30 / 4 | 6 / 4 | 30 / 5 |
| Spread (deg) | 1.1 | 2.6 | 5.5 | 1.5 |
| Range (studs) | 250 | 200 | 120 | 350 |
| Reload, tactical / empty | 2.1 / 2.4 s | 2.0 / 3.53 s | shell loop, see below | 2.45 / 3.4 s |
| Ammo-add, tactical / empty | 1.62 / 1.89 s | 1.02 / 2.56 s | 0.7 s into each shell | 1.85 / 2.42 s |
| Draw time | 0.65 s | 0.6 s | 0.75 s | 0.85 s |
| Casing | 9mm | 9mm | 12ga, on the pump | 7.62x39 |
| Low-ammo cue at | 3 | 8 | 2 | 8 |
| Viewmodel pack | DuqueCD7 Pistol | 1Matzh UZI | DuqueCD7 Saps-12 | DuqueCD7 AK-47 |
| Price (credits) | 0 | 900 | 1600 | 2600 |

Economy helpers on the same module: `MAX_LEVEL` 5, `upgradePrice(level) = 400 + 350 * (level - 1)`, `xpForLevel(level) = 40 * level^2`, `damageAt(config, level) = damage * (1 + 0.08 * (level - 1))`, `XP_PER_KILL` = 6.

### Reload model (2026-09-29, after MW2019)

Every reload has a total length and an **ammo-add** moment, when the magazine seats and the count changes; all times are multiplied by `SkillEffects.reloadScale`. The rules follow Call of Duty: Modern Warfare (2019):

- A **tactical** reload (rounds left) keeps the old magazine. An **empty** reload drops it (the `mag_drop` sound) and adds the chambering action: pistol slide release, AK charging-handle rack (an AK has no bolt hold-open), Uzi top-knob cock.
- Before ammo-add a trigger press does nothing and the old count stands. After ammo-add a shot cuts the rest of the reload, and the viewmodel blends out of the clip over 0.12 s.
- The pump shotgun loads shell by shell from `shellReload`: `start` 0.75 s, `perShell` 0.9 s with the shell counted `addAt` 0.7 s into its cycle, `finish` 0.7 s, plus `chamber` 0.55 s of pump when the tube started empty. A trigger press during the loop lets the shell in hand reach its add point, plays a 0.2 s fast `exit` (plus the pump if nothing is chambered) and then fires the buffered shot. Six shells from empty take 7.4 s.
- After an equip nothing fires or reloads for `drawTime`; the Equip clip plays on at natural speed and a shot cuts its tail.

`WeaponsConfig.magazineReload`, `shellAddTime`, `shellReloadTime` and `shellCancel` compute this timeline, and both `WeaponService` and `WeaponController` call them, so the server and the client prediction cannot drift apart. The seconds are matched to the pack clips, which play at natural speed or at most about 1.3 to 1.45x, and every ammo-add sits on the clip's `MagIn`, `SlideRelease`, `BoltForward` or `ShellIn` marker. `reloadTime` / `ammoAdd*` on the shotgun describe a one-shell reload for anything that reads them generically.

### Server validation chain: `WeaponService.onFire`

Every one of these must pass or the request is dropped silently. Order matters; the mag is only decremented after the last check.

1. A state exists for the player and `WeaponsConfig.get(state.weaponId)` resolves.
2. `origin` and `direction` are both `Vector3` (`typeof` check: rejects tables and userdata spoofs).
3. `direction.Magnitude` is in `(0.9, 1.1)`: a unit vector, not a scaled one that would extend range.
4. The character has a humanoid with `Health > 0`.
5. The draw is over (`now >= state.drawUntil`). If a reload is running it is first advanced to `now + SYNC_TOLERANCE` (0.1 s): a magazine reload past its ammo-add is ended, because the shot cuts its tail; any other reload refuses the shot.
6. `now - state.lastFireAt >= (1 / config.fireRate) * RATE_TOLERANCE`, with `RATE_TOLERANCE` = 0.97, i.e. 3% slack for network jitter.
7. `state.mag > 0`.
8. `characterOrigin(player)` resolves: Head, falling back to HumanoidRootPart.
9. `(origin - anchor).Magnitude <= ORIGIN_TOLERANCE` (5 studs). The client claims the muzzle position; this bounds how far from the body it can be.
10. If that distance exceeds 0.05, a raycast from `anchor` to `origin` must hit **nothing**. This is the line-of-sight check: it stops a client claiming a muzzle position on the far side of a wall. The ray excludes the character and the whole `Workspace.Zombies` folder (2026-09-29), so only world geometry can block it; before that, a zombie hit box pressed against the player during a grab or lunge swallowed point-blank shots.

Only then: `lastFireAt = now`, `mag -= 1`, attributes synced. Then for each of `config.pellets`, a spread direction (`applySpread`, uniform yaw and pitch within `spreadDeg`) is raycast to `config.range` with the character excluded. Each hit goes to `handleHit` and is appended to a hit list.

Finally the server fires `WeaponHit("Shot", origin, hits, player, weaponId)` to **all** clients. Each hit carries `{ position, normal, material }` where `material` is the literal string `"Flesh"` for zombie hits and the real `Instance.Material.Name` otherwise, so clients pick impact VFX without re-raycasting.

`handleHit` resolves the hit part up to the owning Model with a Humanoid, refuses player characters (no friendly fire), reads the shooter's weapon level from their profile, computes `damageAt(config, level)`, multiplies by `headshotMultiplier` if the part is named `Head`, applies `TakeDamage`, and on a kill awards `ProfileManager.addKill`, `MissionGoals.report(player, "Kills", 1)` and `+6` weapon XP.

### Ammo persistence across weapon swaps

Per-player state is `{ weaponId, mag, reserve, lastFireAt, reload, drawUntil }`, plus a separate `savedAmmo[player][weaponId] = { mag, reserve, lastFireAt }` map.

`onEquip` (server handler for the `WeaponEquip` remote):

1. Validates the id, and that `ownsWeapon(player, weaponId)`: profile `WeaponsOwned` lookup, falling back to Pistol-only if the profile has not loaded. The ownership check is skipped while the temporary `WeaponsConfig.ALL_WEAPONS_UNLOCKED` test flag is on.
2. No-ops if it is already the equipped weapon.
3. Snapshots the *outgoing* weapon's mag, reserve and `lastFireAt` into `savedAmmo`.
4. Builds a fresh default state for the incoming weapon, then overwrites mag/reserve/lastFireAt from `savedAmmo` if a snapshot exists. A reload in progress is dropped with the old state (before its ammo-add the old count stands; shells already loaded stay in), `drawUntil` is set to `now + drawTime`, and the `ReloadScale` attribute is published for the client's prediction.

Carrying `lastFireAt` across the swap is deliberate: it stops weapon-swapping from being a fire-rate bypass.

`refillAmmo` (called on `Hub -> Mission`) wipes the entire `savedAmmo` table for the player and restores the current weapon to a full mag plus `magSize * reserveMags`, so every run starts clean.

### Reload jobs

`onReload` refuses during the draw, while a reload runs, with a full magazine or with an empty reserve. Otherwise it creates a `ReloadJob` on the shared timeline (`style` magazine or shell, `startedAt`, `empty`, `scale`, `ammoAddAt`, `endsAt`, and for shells `planned` / `loaded` / `limit`) and sets the `Reloading` attribute. A `Heartbeat` loop runs `advanceReload` for every player: a magazine job moves `min(magSize - mag, reserve)` rounds at ammo-add; a shell job counts one shell at each add time and stops early if the tube fills or the reserve runs out; every change syncs `AmmoMag` / `AmmoReserve`, so the HUD ticks per shell. `onFire` runs the same advance just before judging a shot.

`WeaponReloadCancel` (no arguments; the client sends it when fire is pressed during a shell reload) runs `WeaponsConfig.shellCancel` to lower the shell limit and pull `endsAt` in to the fast exit, keeping fire blocked until then. For a magazine job it simply ends the reload. The old `reloadToken` is gone: an equip replaces the whole state, so a job cannot complete into the wrong gun.

### Client input and prediction

`WeaponController` binds MouseButton1 (with a `Heartbeat` auto-fire loop while held, for `config.auto` weapons), `R` to reload, `F` to inspect (packs with an `Inspect` clip, currently the SMG), `1`/`2` to equip loadout slots and `Q` to toggle between them. While the temporary `WeaponsConfig.ALL_WEAPONS_UNLOCKED` flag is on, keys `1`-`4` equip `WeaponsConfig.order` (Pistol, SMG, Shotgun, Rifle) whether owned or not and `Q` returns to the previous weapon; the flag has to be false before shipping. It maintains `predictedMag` locally so the ammo counter and dryfire respond instantly; the HUD counter turns amber at `lowAmmo` and red at 0.

The client runs its own copy of the reload timeline (2026-09-29): `tryReload` builds a `ReloadState` with the same `WeaponsConfig` helpers and the server's `ReloadScale`, and `advanceReload` moves `predictedMag` at ammo-add (or per shell) every Heartbeat. A trigger press during a shell reload calls `cancelShellReload`: it fires `WeaponReloadCancel`, tells the viewmodel to finish the shell in hand and exit, and buffers the shot (`pendingShot`) until the fast exit is over. While a local reload runs the prediction owns the count; a lower `AmmoMag` from the server is taken at once (a shot or reload it refused), and any other mismatch once `ACK_WINDOW` 0.75 s has passed since the last shot or reload end, so an update still in flight cannot undo a predicted reload. The old unscaled `localReloadUntil` lockout is gone.

Firing sends `WeaponFire(camera.CFrame.Position, camera.CFrame.LookVector)`. The camera position is the claimed origin the server validates in steps 9-10 above.

Tracer thinning: `showTracer` is true for every shot on semi-auto weapons and every third shot on autos.

### Pack viewmodels (2026-09-29)

Files: `src/shared/config/ViewmodelPackConfig.luau`, `src/server/systems/ViewmodelPacks.luau`, `src/client/systems/PackViewmodel.luau`, `src/client/systems/ViewmodelClipPlayer.luau`, clip modules `src/shared/viewmodel_clips/{Pistol,Rifle,Shotgun,SMG}Clips.luau`

All four classes are drawn from first-person packs taken whole (skinned arms, weapon and authored clips) from Sketchfab under CC BY 4.0:

| Class | Pack | Clips used |
| --- | --- | --- |
| Pistol | "FPS Character Animation Pack Pistol" by DuqueCD7 | Equip, Idle, Walk, Fire, Reload (tactical cut at 0.76; empty plays it all with a `SlideRelease` marker at 0.78) |
| Rifle | "FPS Character Animation Pack Ak-47" by DuqueCD7 | Equip, Idle, Walk, Fire, Reload (tactical to 0.55, before the hand reaches the bolt; empty to 0.88 with the rack) |
| Shotgun | "FPS Character Animation Pack Saps-12" by DuqueCD7 | Equip, Idle, Walk, the first 20% of Fire followed by the AccionFire pump, IdleToReload / Reload loop 0.1..0.88 / ReloadToIdle |
| SMG | "UZI, First Person Animations (2026 Remake)" by 1Matzh | Equip, Idle, Walk, Fire, Reload (to 0.9), ReloadEmpty (to 0.9, with the top-knob cock), Inspect |

Each pack's skinned rig is a Model asset (`viewmodel/fps/<class>/rig`). Rojo cannot write skinned MeshParts and their Bone tree, so `ViewmodelPacks.init`, the server's first boot stage after materials, loads them with `InsertService` into `ReplicatedStorage.ViewModelPacks`, anchored and non-colliding. The clips are not Animation assets: `tools/fps_pack` bakes them into ModuleScripts (see [[Assets Pipeline]]), and `ViewmodelClipPlayer` decodes the tracks and writes `Bone.Transform` every frame. It solves bones parent first from each bone's model-space change against its own rest pose, because Roblox's importer drops unweighted bones and folds their transforms into the children, so baked local transforms would not match. It supports cross-fades, looping, `from` / `to` cuts and stretching a section to a given duration.

`PackViewmodel` owns the clips on top of that: the idle or walk loop underneath, and a queue of one-shot entries (clip section, speed or duration, fade, tag, phase markers, `blendOut`). When the queue runs dry the base loop blends back in over the last entry's `blendOut`, which is how a cut reload returns to the ready pose.

- `reload(plan)` fits the tactical or empty cut to the config time minus its blend-out, or for the shotgun queues enter, one loop section per shell, leave, and the chambering pump from empty.
- `fire` snaps in over 0.03 s (0.12 s when it interrupts an equip, reload or inspect). For the shotgun it keeps only the recoil part of Fire (`fireTo` 0.2) and chains the AccionFire pump, sped up together (at most 1.5x) so the action is closed by `followReady` inside 90% of the fire interval; that is why the shotgun fires at 1.25/s rather than 1.5.
- `cancelReload` trims a shell loop just past its `ShellIn` marker, then blends back or into the pump.
- Phase markers (`MagOut`, `MagIn`, `BoltBack`, `BoltForward`, `SlideRelease`, `ShellIn`), stored as clip fractions measured from the magazine and bolt bones, fire through `Viewmodel.onPhase` however the clip is cut or stretched, tagged with the entry (`fire`, `tactical`, `empty`, `shell`, `chamber`, `equip`, `inspect`). `WeaponController` ejects the shotgun hull on `BoltBack` tagged `fire`, and `WeaponSfx` plays the foley.

The rigs are uploaded at about 2.2x life size with a common arm span (UnitScale nodes: AK 2.961, Saps-12 1.2218, Uzi 3.0, pistol native), and each clone is scaled by `RIG_SCALE` 0.4 so the arms do not reach into walls and cars beside the camera. `eye` is the view point in the rig's RootPart space; `restTilt` corrects the Uzi, whose bind A-pose came in turned -90 degrees about X. Muzzle and eject attachments are placed from the front and top of the weapon mesh and follow `weaponBone` through every clip. `Viewmodel.luau` keeps the procedural layer (recoil springs, sway, drift, hip aim) for both kinds of rig and hands `PackViewmodel.step` the camera-space placement each frame; for packs the procedural translations are scaled by `PROCEDURAL_POSITION_SCALE` 1.1 and the procedural bob is damped to 25% (`BOB_SCALE`), because the Walk clip carries its own.

### Viewmodel

Since 2026-09-29 the rig in this section is the fallback, built through `ViewmodelBuilder` only when a class's pack has not loaded; the procedural layers described here (recoil, drift, juke, hip aim) apply to both. `src/client/systems/Viewmodel.luau` builds a per-weapon part rig from primitives (receiver, slide or bolt handle, barrel, handguard or pump, sights, grip, magazine, stock) plus two procedural arms (hand, thumb, fingers, wrist, sleeve cuff, forearm, upper arm), and two attachments named `Muzzle` and `Eject`.

The procedural boxes are only the fallback. `ViewmodelBuilder.buildMeshWeapon` first looks for `ReplicatedStorage.ViewModels.<class>` (mounted by Rojo from `assets/viewmodels/<name>.model.json`) and binds its parts to bones by exact name via `MESH_BONES`: `Main → weaponRoot`, `Slide → slide`, `Pump → pump`, `Magazine`, `Barrel`, `Grip`. Pistol and Rifle now ship real mesh sets; the Rifle geometry is Cube 3D output (see [[Assets Pipeline]]): meshes were extracted as OBJ over a localhost HTTP bridge, converted to GLB, uploaded through Open Cloud as Model assets (Studio's `CreateAssetAsync` cannot upload meshes), and the resulting mesh ids plus albedo textures live in `assets/viewmodels/rifle.rig.txt`. That path is now scripted: `tools/cube3d/{Generate,Extract,Import,DumpRig}*.server.luau` on the Studio side and `scripts/mesh_pipeline.py serve|convert|finalize` plus `.glb` support in `upload_assets.py` on the repo side, documented step by step in `tools/cube3d/README.md`. Marker parts `Muzzle`, `CasingEject`, `HandRMount`, `HandLMount` are authored by hand and all four are read: the hand mounts position each hand (orientation stays in code, and a template without mounts falls back to the pistol-shaped constants; on a shotgun `HandLMount` is taken relative to `Pump` so the support hand rides the stroke). The glTF import path rotates meshes 180° about Y, so the rifle sources were uploaded in Roblox's -Z-muzzle convention directly.

**The rig is parented to `Workspace.CurrentCamera` and every part is `Anchored`, so welds do not work.** Instead, each piece stores its rest `offset` CFrame and `step` writes `piece.part.CFrame = rootCFrame * offset` every `RenderStepped`. This is recorded as a decision in [[Decisions]]: welds on anchored parts under Camera silently do nothing, which cost real debugging time.

`rootCFrame` is the camera CFrame composed with, in order: `BASE_OFFSET` `(0.9, -0.9, -1.9)`, stride bob and breathing and sway translation, recoil offset on Z, a rotation from recoil pitch/roll and sway, a sprint pose blend, and a reload tilt. Inputs come from `ExertionState` (speed, stride phase, running flag) and from camera delta between frames for the sway.

The camera is forward-locked, so its frame delta is zero and three other inputs keep the rig alive: `drift` (a slow three-axis sinusoid at `ViewmodelConfig.drift.rates` with amplitude 0.012 rad, so the gun never sits dead still), `juke` (a yaw/roll/shift impulse on every change of the lateral input axis: yaw 0.16, roll 0.22, shift 0.12) and the hip-aim rotation below. Stride bob amplitudes were raised to 0.042/0.05/0.028/0.018 and breathing to 0.024/0.014 for the same reason. Measured at steady run: the rig moves through 0.28 x 0.19 x 0.34 studs and 2° of yaw, pitch and roll relative to the camera.

### Hip aim

`src/client/systems/HipAim.luau` picks the nearest live zombie inside a cone in front of the camera (`ViewmodelConfig.hipAim`: range 70, cone 42°, line-of-sight raycast), keeps it for `hold` 0.35 s after it leaves so the gun does not flick between targets, and blends a lock value at `blendRate` 6. `HipAim.angles` turns the target into yaw and pitch relative to the camera, clamped to ±24° and ±14° and scaled by the lock (38°/22° in the first cut read as the gun snapping sideways). `Viewmodel` feeds that into the `aimRot` spring (stiffness 28, damping 10, near-critical) with coupled roll (`rollCouple` 0.15), a lateral `shift` 0.1 and a `dip` 0.03, so the weapon visibly swings toward the zombie the way Into the Dead's hip aim does. The crosshair follows: `HipAim.bindCrosshair` moves the HUD dot to the projected aim point and back to screen centre otherwise. `WeaponController.tryFire` shoots along `HipAim.fireDirection(origin)` once the lock passes `fireLock` 0.55 and falls back to `AimAssist.adjustFireDirection`; the server's cone check (`MAX_YAW_COSINE` = cos 100°) accepts anything inside the cone; the visual clamp only limits how far the gun turns, the shot still goes to the target. Measured 2026-09-06: shots left along the aimed direction, crosshair excursion up to 656 px at 2245 px width, never off screen because the 42° cone is narrower than the 54° horizontal half-FOV.

**Recoil.** `Viewmodel.onFired` impulses `recoilPos` (back 1.5 x `recoilKick`, up 0.4 x) and `recoilRot` (pitch 2.2 x `recoilSnap`, with only ±0.25/±0.35 x of random yaw and roll), and each weapon's `recoilDamping` in `WeaponsConfig` is now 1.8 x sqrt(`recoilStiffness`) (Pistol 28, SMG 29, Shotgun 22, Rifle 25), so the springs settle without ringing. The camera no longer gets a random three-axis shake per shot: `CameraEffectsController.recoil(kick)` drives a critically damped pitch spring (`ViewmodelConfig.cameraRecoil`: stiffness 70, damping 17, pitch 0.55 rad/s per unit of `cameraKick`, yaw jitter ±0.08) that lifts the view about half a degree per rifle shot and returns smoothly; the FOV kick dropped to 0.25 x kick. The old `impulse` shake stays for hits and landings only.

Three pieces get overridden offsets during animation, computed in `animatedOffsets`:

| Piece | Trigger | Motion |
| --- | --- | --- |
| `slide` / `BoltHandle` | `onFired` (non-shotgun) | `sin(t * pi) * slideTravel` over 0.16s |
| `pump` | `onFired` (shotgun), starts at `t = -0.4` for a delay | `sin(t * pi) * pumpTravel` over 0.42s |
| `magazine` | reload, 16%-68% of duration | drops 1.1 studs and returns, eased cubic |

At 74% of the reload the slide/pump racks once more. `setVisible` uses `LocalTransparencyModifier` rather than `Transparency` so it composes with first-person culling, and the whole rig hides when the humanoid dies.

`getMuzzlePosition()` is used as the tracer origin for the local player (so tracers leave the gun, not the eye) while remote players' tracers start at the replicated `origin`.

`WorldWeapon.luau` is the server-side third-person counterpart: it welds a simplified gun model to `RightHand`/`Right Arm`, rebuilt whenever the `WeaponId` attribute changes or the character's appearance loads. Those parts *are* unanchored and welded, which is why the same trick is not needed there.

### Per-class audio and the acoustic switch

`src/client/systems/WeaponSfx.luau`.

Sound selection: every sound is resolved by its `AssetIds.audio.weapons` key at play time, so a recording added to the manifest under an expected key takes over with no code change. Each weapon config lists three `closeSounds` (dry, near-field takes from The Free Firearm Sound Library); `shotSoundId` picks one that has an id, never the same one twice in a row, and falls back to the older `shotSound`. Ids of 0 no-op.

Voices (2026-09-29): each sound id gets a pool of 4 `Sound`s, growing to 8, played round-robin with ±4% pitch and ±1.5 dB of jitter. A voice that is still playing is never restarted, since that chops its tail; only past eight voices is the one furthest into its playback reused. `WeaponSfx.preload` builds the pools for every weapon id at client start.

The tail is a separate one-shot layered on top, chosen by acoustic space:

```
tail id     = interior and "tail_interior" or "tail_open"
tail volume = shotVolume * (interior and 0.34 or 0.46)
```

rate-limited by `TAIL_COOLDOWN` 0.55s so automatic fire does not stack tails.

`isInterior(position)` walks a cached list of every `BasePart` in the Workspace carrying an `AcousticSpace` attribute (currently `HangarInteriorZone` and `RangeInteriorZone`), transforms the point into each zone's object space, and box-tests against `Size / 2`. The list is iterated **backwards**, so the most recently added zone wins on overlap, and dead zones are pruned in the same pass. `Workspace.DescendantAdded` keeps the cache live.

The same interior flag also retunes a `ReverbSoundEffect` on the `Weapons` SoundGroup:

| | Interior | Open |
| --- | --- | --- |
| `DecayTime` | 1.5 | 0.4 |
| `WetLevel` | -8 | -18 |

Other layers (2026-09-29):

- **Reload and handling foley** comes from clip markers, not timers. `playPhase(phase, class, tag)` looks up the class key first (`rifle_bolt_back`, `pistol_slide_release`, `shotgun_shell_in`, ...), then the generic key (`mag_out`, `mag_in`, `bolt`) at a per-class placeholder pitch; an empty class key means silence for that phase (a pump has no magazine to pull). `Draw` and `Holster` play `weapon_draw` / `weapon_holster` on swaps. On an empty reload, `MagOut` also schedules `mag_drop` 0.5 s later.
- **Low ammo.** At or below `config.lowAmmo` rounds each shot adds `low_ammo_click`, rising to +3 dB and 6% pitch on the last round, where `last_round` joins (the pistol falls back to the bolt sound pitched up, since its slide really locks back). Shell weapons skip the last-round clack. A trigger press on an empty magazine plays one `dryfire` per press.
- **Casing landings.** `WeaponVfx.onCasingLanded` reports each casing's first two impacts with the surface material and impact speed; `playCasingLand` plays a brass (`casing_brass_*`) or hull (`casing_shotgun_*`) variation on one of 12 positional voices on Terrain attachments, within 45 studs, scaled by surface (metal rings, wood is dull, grass, sand and mud are near silent) and by speed. Until those recordings exist it falls back to Kenney `shell_01` / `shell_02`, pitched down and softer for hulls.
- `playDistantShot` for other players' fire more than 40 studs away, played as a 3D sound at the replicated origin at 80% volume with 30-400 stud rolloff; and `playGong` for range hits (the gong recording was rejected by moderation, so it is silent until replaced).

To add a new acoustic space, create a part, set `AcousticSpace = "Interior"`, and parent it into the Workspace: no code change needed.

The spatial audio engine reads the same zones (`AudioEnvironment.zoneAt`, with `HangarInteriorZone` mapped to the `Hangar` preset and any other zone to `Interior`); `docs/audio/weapons-integration.md` lists how `WeaponSfx` moves onto it, after which the `Weapons` SoundGroup and its `ReverbSoundEffect` go.

### Weapon VFX

`src/client/systems/WeaponVfx.luau`, rebuilt 2026-09-29 against the MW spec:

- **Muzzle flash.** One rig per `Muzzle` attachment, built once and re-triggered: white-hot core sprites that live about two frames (`FLASH_CORE_TIME` 0.028 s), a forward tongue and 3 to 5 flame petals drawn as `Beam`s from one of four shape variants (never the same twice running) with random roll and ±20% scale, a `PointLight` for 0.04..0.06 s, sparks on 35% of shots and a faint smoke wisp. Class scale: pistol 0.8, SMG 0.85, rifle 1, shotgun 1.5. Every emitter is `LockedToPart`, because at 24 studs/s a world-space flash is left almost a stud behind the muzzle. Every shotgun shot leaves a denser puff; `burstSmoke` exposes the same puff (not called anywhere yet) and `barrelSmoke` still rises after a burst of 3+ shots followed by 0.35 s of quiet.
- **Casings.** Pooled per caliber: `9mm` brass, `762x39` lacquered steel thrown harder and slightly forward, `12ga` red hull with a brass head, which the pump ejects on its `BoltBack` stroke instead of the shot (`ejectOnFire = false`). A casing spawns at the `Eject` attachment in camera space at 60% size (a world-size casing next to the eye would cover the screen), flies there for 0.25..0.35 s under camera-relative gravity, then hands off to world space with the runner's velocity added, falls on a parabola at half `Workspace.Gravity` and bounces up to twice off raycast hits (restitution 0.3, friction 0.45, random scatter) before settling. No physics parts, which tunnel through floors. All casings move with one `BulkMoveTo` per frame and live about 3 s, fading over the last 0.25 s.
- Neon tracer beams (`TRACER_COLOR` 255/214/140) from muzzle to impact, and material-aware impact effects that branch on the `"Flesh"` marker the server sends.

---

## Ammo crates

File: `src/server/systems/AmmoCrates.luau`

`ChunkSpawner` calls `AmmoCrates.spawnForChunk(index, pivot, 128, difficulty.ammoCrateChance)` for every chunk. The function immediately returns if `random:NextNumber() > chance`, so it is at most one crate per chunk: 50% on Easy, 38% on Medium, 28% on Hard.

The crate is three non-colliding parts (body, lid, stripe) plus the signature: a `GreenSmoke` `ParticleEmitter` on an attachment 1.2 studs up, rate 14, speed 14-20, upward acceleration `(1, 8, 0)` so the pillar drifts, sizes 4 to 16, plus a green `PointLight` with range 26. That pillar is the entire discovery mechanic: the crate itself is small and low.

Placement is random within `LANE_WIDTH/2 - 24` = ±96 on X and `±(chunkLength/2 - 20)` on Z, with random yaw. It is parented to the `Workspace.Chunks` folder rather than into the chunk model, so `AmmoCrates.clearChunk(index)` must be called explicitly on cull: `ChunkSpawner.despawnChunk` does this alongside `ZombieAI.clearChunk`.

Pickup is a polled proximity check, not a Touched event: `AmmoCrates.init` spawns a `while true` loop with `task.wait(0.2)`. Each pass early-outs if no crates exist, then for every living player checks every crate against `PICKUP_RADIUS` = 9.

The grant is:

```lua
rounds = floor(config.magSize * BASE_MAGS * SkillEffects.ammoScale(player))
```

with `BASE_MAGS` = 1.5, then `WeaponService.addReserve` clamps the result to `magSize * reserveMags`. The weapon used is whatever the player's `WeaponId` attribute currently says, so a Shotgun (mag 6) gets 9 shells while a Rifle (mag 30) gets 45: the crate is worth proportionally the same to everyone.

---

## Economy and vendors

File: `src/server/systems/ShopService.luau`, client `src/client/ui/ShopGui.luau`

The transport is two RemoteFunctions: `ShopCatalog(vendorId) -> Catalog?` and `ShopPurchase(vendorId, entryId, kind) -> { ok, message, catalog }`. Both are throttled at `REQUEST_COOLDOWN` 0.25s per player.

### Catalog kinds

A `CatalogEntry` is a uniform shape (`{ id, kind, displayName, description, price, level, maxLevel, owned, affordable, equipped, xp, xpNeeded }`) so the GUI renders every vendor with one row template.

| Kind | Built by | Meaning |
| --- | --- | --- |
| `Weapon` | `weaponEntries` | Not yet owned; price is `config.price` |
| `WeaponUpgrade` | `weaponEntries` | Owned; price is `upgradePrice(level)`, gated on XP |
| `Loadout` | `loadoutEntries` | Owned weapons only; toggles slot membership, price 0 |
| `Skill` | `skillEntries` | Price `SkillsConfig.priceFor(config, level)` |
| `Skin` | `skinEntries` | Price `config.price`, or 0 if already owned (then it just equips) |

`buildCatalog` maps vendor id to kinds: `Gunsmith` = weapons + loadout, `WeaponDealer` = weapons, `Medbay` = skills, `BubblegumMachine` / `SodaMachine` = skins. Anything else returns `nil` and the request fails with "Unknown vendor". There is also a branch for a vendor id `"Merchant"` that does not exist in `VendorsConfig`: dead code.

### Purchase validation

`onPurchase` never trusts the client's idea of what an item costs or where it is sold:

1. Type-check `vendorId` and `entryId` as strings, `kind` as string-or-nil.
2. Throttle.
3. Load the profile; fail with "Profile not loaded" if absent.
4. **Rebuild the catalog server-side** for that vendor and search it for a matching `id` (and `kind`, if supplied). A miss returns "Item not sold here". This is the check that makes vendor scoping real: you cannot buy a skill from the Gunsmith by guessing the id.
5. Dispatch on the *matched entry's* kind, not the client's.
6. Return the freshly rebuilt catalog in the response, so the GUI re-renders from server truth rather than mutating optimistically.

Credits are only ever moved by `ProfileManager.spendCredits`, which refuses negative amounts and insufficient balances and re-syncs the `Credits` player attribute on success.

### Weapon XP gate on upgrades

`purchaseWeapon` is the only place with a two-currency requirement. Unowned: pay `config.price`, get `{ level = 1, xp = 0 }`. Owned:

1. Refuse if `level >= MAX_LEVEL` (5).
2. `xpNeeded = xpForLevel(level)` = `40 * level^2`, so L1->L2 needs 40, L2->L3 160, L3->L4 360, L4->L5 640. At 6 XP per kill that is 7 / 27 / 60 / 107 kills with that specific weapon.
3. Refuse with "Needs N more kills XP" if `progress.xp < xpNeeded`.
4. Spend `upgradePrice(level)` credits: 400, 750, 1100, 1450.
5. **Subtract** `xpNeeded` from `progress.xp` and increment the level. XP is spent, not a running total.

XP is per weapon (`data.WeaponsOwned[id].xp`), awarded only in `WeaponService.handleHit` on the killing shot, so levelling a Rifle requires Rifle kills.

### Loadout slots

`LOADOUT_SLOTS` = 2, stored as `data.Loadout` (an ordered array of weapon ids). `toggleLoadout`:

- If the weapon is already in the loadout, remove it, unless it is the last one, which returns "Need at least one weapon".
- Otherwise, if the loadout is already full, `table.remove(data.Loadout, 1)` drops the oldest, then append.

On success `ShopService` calls `WeaponService.applyLoadout(player)`, which pushes `LoadoutSlot1` / `LoadoutSlot2` attributes (the client's `1`/`2`/`Q` keys read these) and re-equips slot 1 if the currently equipped weapon is no longer in the loadout.

---

## Monetization

File: `src/server/systems/MonetizationService.luau`, config `src/shared/config/ProductsConfig.luau`

### The no-P2W boundary

This is a hard product rule, and the code is structured to enforce it:

- Credits, weapons, weapon upgrades, skills and loadout slots are reachable **only** through `ShopService`, which spends credits and has no Robux path at all.
- `ProductsConfig` contains exactly one developer product, `Continue`, and two game passes (`VIP`, `Supporter`) both flagged `cosmeticOnly = true`.
- `MonetizationService` exposes no generic "grant credits" handler. Grants are registered by product id via `setGrantHandler`, and the only registration in the codebase is `DeathService` registering `"Continue"`.

If you add a product, the question to answer first is whether its grant handler can be expressed without touching `Credits`, `WeaponsOwned` or `SkillLevels`.

### The Continue product

`ProductsConfig.products.Continue` is 49 Robux, `productId = 0` (not yet created on the Roblox side). `DeathService.onChoice` branches on `ProductsConfig.isConfigured("Continue")`:

- Configured: `MonetizationService.promptPurchase(player, "Continue")` and wait for `ProcessReceipt`.
- Not configured: call `grantContinue` directly, a free revive. This keeps the death flow testable before the product exists.

Either way the revive goes through the same `grantContinue`, which enforces `REVIVES_PER_RUN` = 1.

### ProcessReceipt idempotency

`MarketplaceService.ProcessReceipt` is assigned once in `MonetizationService.init`. The handler:

1. Resolve the player; if absent return `NotProcessedYet` (Roblox will retry later).
2. Resolve their profile; if absent return `NotProcessedYet`: never grant against a missing profile.
3. `receiptKey = tostring(receiptInfo.PurchaseId)`. **If `data.PurchaseHistory[receiptKey]` is already set, return `PurchaseGranted` immediately.** This is the idempotency guard: the key lives in the persisted profile, so a retry after a server restart still short-circuits.
4. Look up the product by numeric id; unknown ids warn and return `NotProcessedYet`.
5. Look up the registered grant handler; missing handler warns and returns `NotProcessedYet`.
6. `pcall` the handler. If it errors or returns false, return `NotProcessedYet`: the player is not charged for a failed grant.
7. Only on success write `PurchaseHistory[receiptKey] = true` and return `PurchaseGranted`.

The ordering matters: the history entry is written **after** the grant, so a crash mid-grant results in a retry rather than a swallowed purchase.

### Game passes

`ownsPass(player, passId)` caches per player per pass with `PASS_CACHE_TTL` 120s, and retries `UserOwnsGamePassAsync` up to 3 times with a `0.5 * attempt` backoff. If every attempt fails it falls back to the stale cached value, and only returns false if there is nothing cached: a Roblox API outage should not silently strip someone's pass.

Both passes have `passId = 0`, so `promptPass` and `ownsPass` currently return false immediately.

The client-facing surface is a single validated remote: `PromptPurchase(kind, id)` where `kind` is `"Product"` or `"Pass"`. Both arguments are string-checked and the id is resolved against `ProductsConfig`, so the remote cannot be used to prompt arbitrary asset ids.

---

## Death sequence and results

Files: `src/server/systems/DeathService.luau`, `src/client/controllers/DeathController.luau`, `src/client/systems/DeathGore.luau`

`DeathService.init` sets `Players.RespawnTime = 600` globally. Nothing auto-respawns; every respawn in the game is an explicit `player:LoadCharacter()`.

### Server side

`MissionService.setDeathHandler(onPlayerDied)` wires the humanoid `Died` connection to `DeathService`. `onPlayerDied` ignores non-participants and re-entrant calls (`pending[player]`), then:

1. Capture `deathCFrame` from the character pivot.
2. `poseCorpse`: anchor the root and tween it over 0.45s into a lying pose at y = 1.15 preserving yaw (`CFrame.Angles(pi/2, 0, 0)`).
3. Allocate a monotonic `token` and store `pending[player]`.
4. `ZombieAI.swarmCorpse(position, SWARM_DURATION)` (8s), and after 1.1s `ZombieAI.feedOnCorpse(position, 8, 5)`.
5. Compute rewards, award them to the profile immediately, and fire `DeathBegan` to that client.
6. `task.delay(CHOICE_TIMEOUT, ...)`: 30 seconds later, if `pending[player].token` still matches, force `returnToHub`.

Rewards are computed in `computeRewards`:

```lua
distance   = floor(DistanceTracker.getDistance(player))
multiplier = RewardMultiplier.compute(difficulty.id, MissionState.getModifiers())
xp         = floor(distance / 5)
credits    = floor(distance / 10 * multiplier) + MissionGoals.bonusCredits(player)
```

Note that `computeRewards` calls `MissionGoals.report(player, "Distance", distance)` *before* reading completed goals, so the final distance always counts toward `Distance1500`.

Rewards are awarded via `ProfileManager.awardRun`, which adds credits and XP, accumulates `StatsLifetime.Distance` and increments `StatsLifetime.Runs`.

`onChoice(player, choice)` handles the `DeathChoice` remote. Anything that is not `"continue"` returns to the hub. `"continue"` checks `canRevive` (`revivesUsed < REVIVES_PER_RUN` = 1), then either prompts the product or grants directly.

`reviveAtDeath` clears the corpse lure, `LoadCharacter()`s, pivots the new character to `deathCFrame + (0, 2, 0)`, attaches a `ForceField` destroyed after `REVIVE_PROTECTION_TIME` 3s, and re-arms the death watcher.

`returnToHub` clears pending state and revive count, ends the goal run, removes the player from the mission (which may trigger world teardown), sets `FlowPhase = "Hub"` and reloads the character: `FlowService.onCharacterAdded` then teleports them into the hangar.

Hub deaths take a completely separate path: `watchHubDeaths` connects to every `CharacterAdded` and, for non-participants, respawns after `HUB_RESPAWN_DELAY` 3s.

### Client cinematic

`DeathController.onDeathBegan(rewards)` builds a timeline:

| t | Event |
| --- | --- |
| 0 | Restore character visibility (the first-person camera hides body parts), `DeathGore.render(corpsePos)`, death scream, bind the death camera at `RenderPriority.Camera + 1` |
| 1.1, 2.2, ... | Five `DeathGore.feastTick(corpsePos)` calls, 1.1s apart |
| 6.0 | Blackout fades to 0.15 alpha and "YOU ARE DEAD" fades in over 0.9s |
| 7.5 | Results panel appears; rows count up |

The camera is `Scriptable`, positioned at `corpsePos + (0, 1.1, 0)`, looking at the nearest zombie head within 26 studs (`findNearestZombieHead` scans `Workspace.Zombies`) or a fallback point above. It adds a three-axis sine shake and a roll that oscillates around -12°, and lerps toward the target with `1 - exp(-6 * dt)` for frame-rate independence.

Result rows count up in 14 steps at 0.03s each with a `UiSfx.rewardTick()` per step, then the credits row is rewritten to include the multiplier: `Credits: N  (x1.95)`.

Buttons: **Return to Hub** and **Continue**. If the Continue product is configured the button label shows the Robux price and firing it sends `"continue"` *without* closing the UI (the purchase prompt has to resolve first); otherwise it closes and sends `"continue"` for the free grant. Enter / KeypadEnter / gamepad A are bound to Return via `ContextActionService`. `CursorMode.setModalOpen("DeathResults", true)` frees the mouse while the panel is up.

`DeathGore` gates everything on the `bloodEnabled` and `dismembermentEnabled` settings, so the whole sequence degrades to a plain camera + results screen when a player turns gore off.

---


**Fall-back camera (2026-09-06, staged 09-07).** `DeathController.updateDeathCam` no longer orbits the corpse. On `DeathBegan` it records the live camera CFrame and the ground under the corpse (raycast, so raised Farmstead and Wasteland geometry works) and plays three stages: **impact** (0..0.22 s, the view jolts back and down with a 6° FOV kick), **fall onto the side** (0.22..0.95 s, ease-in to an eye 0.85 studs off the ground, yawed 60° off the run line and rolled -78°, so the world lies sideways), then **roll onto the back** (0.95..1.75 s, ease-out into the lying pose: eye 1.05 studs up, facing the run direction, pitched up `FALL_PITCH` 64° so the sky fills the top of the frame and whoever bends over the body fills the bottom), followed by a decaying impact bounce, a slow breath and a 4° roll wobble. Measured: roll 7° -> -57° -> +7°, pitch -10° -> 63° by 1.4 s. The pose is blended 22% toward the nearest zombie head and that blend is itself smoothed at 2.5/s (`HEAD_TRACK_RATE`), because an unsmoothed blend swung the view 20° every time the feeders shuffled; the ground is sampled in `onDeathBegan` before `DeathGore.render`, since the gore parts are collidable and a later raycast lands on a gib instead of the floor. Measured 2026-09-06: pitch 4° to 63° in 1.2 s, eye 1.05 studs over the floor, then 61..65° breathing. Two things had to be fixed for the camera to move at all: the engine's default `Health` script kept regenerating the corpse to 1 HP every second (each tick re-triggered the grab and `Died`), so `DeathService` now disables that script on every spawn and `StarterCharacterScripts/Health` ships an empty replacement; and `CursorMode.scanForExternalMenu` mistook the full-screen damage vignette for a foreign menu and froze the camera 0.2 s after death, so a GUI now only counts as a menu when it holds a large solid panel **and** a button or text box. `ZombieAI.feedOnCorpse` no longer teleports feeders into a ring: the corpse lure makes every zombie within 80 studs run to the body, and the five nearest candidates are **posed on arrival** (within `FEED_REACH` 4.6 studs): anchored 2.3..3.1 studs from the corpse facing it, every second one kneeling (root dropped 0.9, hips pitched back 82°), the rest standing. The eating itself is a procedural pose on the Motor6D `C0`s, allowed for zombies by asset-policy rule 1 and verified by screenshot from the corpse's eye and from the side: waist bent 54° (40° kneeling) plus a 7° chew, neck 16° down plus a 16° chew, both arms swung 46..50° forward and 14° out, with `chew = max(sin(t), 0)^3` at 5.5 rad/s so the head dips sharply and lifts slowly. The old whole-body bob was what read as "moving back and forth". Base `C0`s are restored on release and on recycle (`poseRestores`), the AI tick skips locked states, and the procedural layer yields automatically once a real feeding clip is loaded (`ZombieAnimator.hasFeedingClip`). `DeathService.poseCorpse` lays the root down at ground + 1.15 from the same raycast rather than the hard-coded y = 1.15.
## Skills

Files: `src/shared/config/SkillsConfig.luau`, `src/server/systems/SkillEffects.luau`

Four skills, `maxLevel` 3 each, priced linearly as `basePrice + priceStep * currentLevel`.

| Skill | Base / step | Value per level | Applied by |
| --- | --- | --- | --- |
| Toughness | 600 / 700 | +20 max HP | `FlowService.applyHumanoidConfig` via `bonusHealth` |
| Endurance | 800 / 900 | +2 top speed | `DistanceTracker.step` via `bonusSpeed`, raises the `MAX_RUN_SPEED` cap |
| Fast Hands | 700 / 800 | 12% faster reload | `WeaponService.onReload` via `reloadScale` |
| Scavenger | 500 / 650 | +25% crate ammo | `AmmoCrates.collect` via `ammoScale` |

`SkillEffects` is the single translation layer from stored levels to gameplay numbers, and it clamps every lookup to the config's `maxLevel` so a corrupted profile cannot exceed the intended ceiling. Two formulas are worth noting:

- `reloadScale = max(0.5, 1 - level * 12 / 100)`: L3 gives 0.64, and the floor of 0.5 exists so future tuning cannot produce an instant reload.
- `ammoScale = 1 + level * 25 / 100`: L3 gives 1.75.

Toughness preserves the current health *ratio* when max health changes, so buying it mid-session does not heal you to full.

---

## Mission goals (stub)

Files: `src/server/systems/MissionGoals.luau`, `src/shared/config/MissionGoalsConfig.luau`

Three per-run objectives, evaluated once at death.

| Goal | Metric | Target | Reward |
| --- | --- | --- | --- |
| `Distance1500` (Long Haul) | Distance | 1500 | 250 credits |
| `Kills25` (Cleanup) | Kills | 25 | 300 credits |
| `NoDamage500` (Untouched) | CleanDistance | 500 | 200 credits |

`beginRun` initialises `{ Distance = 0, Kills = 0, CleanDistance = 0 }`. `report(player, metric, value)` takes a **max** for `Distance` and `CleanDistance` and a **sum** for everything else. `completed` walks `MissionGoalsConfig.order` and returns the ids whose metric has reached target; `bonusCredits` sums their rewards, and `DeathService` adds that to the payout.

**This is a stub in one specific way:** only two call sites ever report. `WeaponService.handleHit` reports `"Kills"`, and `DeathService.computeRewards` reports `"Distance"`. Nothing anywhere reports `"CleanDistance"`, so `NoDamage500` is unreachable. Making it work needs a damage-taken hook that snapshots the current distance and reports the delta since the last hit: `DistanceTracker` already has the per-player number.

There is also no UI: goals are not shown during a run and only surface as an unlabelled credit bonus in the results panel.

---

## Settings and skins persistence

### Profiles

File: `src/server/systems/ProfileManager.luau`

ProfileStore (`ddashdev/profilestore@1.1.0`, the project's only Wally dependency) over a store named `PlayerData`, session key `Player_<UserId>`. The template is `ProfileData` at `Version = 2` with `Credits`, `XP`, `WeaponsOwned` (defaults to `Pistol` at L1), `SkillLevels`, `SkinsOwned` (`Recruit`), `EquippedSkin`, `PurchaseHistory`, `Loadout`, `Settings` and `StatsLifetime`.

On load: `AddUserId`, `Reconcile`, then `migrate(data)` which bumps old versions forward (v1 -> v2 repairs an empty `Loadout`). `OnSessionEnd` kicks the player. Sessions are ended on `PlayerRemoving` and in `BindToClose`.

**Studio caveat:** `dataStoresAvailable()` probes a throwaway DataStore, and on failure the module silently switches to `store.Mock`. Progression then appears to work but nothing persists. `ProfileManager.isUsingMock()` exposes this, and `init` warns once.

Two callbacks fan out on load: `onLoaded` subscribers (used by `SettingsPersistence`, `SkinService`, `WeaponService`) and an attribute sync writing `Credits` and `XP` onto the player for the HUD wallet.

### Settings

Files: `src/shared/config/SettingsConfig.luau`, `src/client/systems/SettingsService.luau`, `SettingsApply.luau`, `src/client/ui/SettingsGui.luau`, `src/server/systems/SettingsPersistence.luau`

The schema is the single source of truth for all four consumers: the GUI builder, the client store's defaults, the applier, and the server sanitiser. Nine keys in three categories:

| Category | Keys |
| --- | --- |
| Audio | `masterVolume` (0-1, default 0.7), `musicVolume` (0-1, default 0.5), `muted` |
| Graphics | `firstPersonBody`, `shadows`, `effectsQuality` (0.4-1 step 0.2), `fpsCounter` |
| Content | `bloodEnabled`, `dismembermentEnabled` |

Round trip:

1. Client seeds from `SettingsConfig` defaults at startup.
2. Server fires `SettingsSync` with `data.Settings` on profile load; the client hydrates.
3. Any `set(key, value)` notifies `observe` subscribers immediately and schedules a debounced save (2s) over `SettingsSave`.
4. Server-side, `SettingsPersistence` throttles at 1.5s per player and runs `sanitize`: unknown keys dropped, `toggle` must be a boolean, `slider` must be a number and is clamped to the spec's `min`/`max`. Only surviving keys are written into `data.Settings`.

`SettingsApply` is wiring-only: each key is bound to its effect (`MusicController.setMasterVolume`, `setMusicVolume`, `setMuted`, `Lighting.GlobalShadows`, `FpsCounter.setVisible`, `VfxConfig.setDensity`). `firstPersonBody` is read directly by `CameraController`, `bloodEnabled` / `dismembermentEnabled` by `GoreController`, `ZombieVfx` and `DeathGore`.

`VfxConfig` is deliberately the one config that is **not** `table.freeze`d, because `setDensity` mutates `VfxConfig.DENSITY` in place. See [[Performance]].

### Skins

Files: `src/server/systems/SkinService.luau`, `src/shared/config/SkinsConfig.luau`

Five skins, each defined purely as four `Color3` values (head, torso, arms, legs): Recruit (default-owned, free), Ranger 1200, Field Medic 1800, Heavy Trooper 2600, Ghost Operator 4200.

Application is via `HumanoidDescription`. `buildDescription` sets the four colour groups and then explicitly zeroes every clothing, face, body-part and accessory field and normalises all scales, so a player's own avatar cannot leak through. `humanoid:ApplyDescription` is wrapped in a `pcall` that warns on failure.

It re-applies on both `CharacterAdded` and `CharacterAppearanceLoaded`, because Roblox can overwrite the description when the avatar finishes loading and only one of those events is reliable depending on timing.

On profile load, `SkinService` grants every skin flagged `defaultOwned`, then validates `EquippedSkin`: if it is not a real id, or not owned, it resets to `SkinsConfig.DEFAULT_ID`. `equip` refuses unowned skins, so `ShopService.purchaseSkin` must grant before equipping (which it does: spend, set `SkinsOwned[id] = true`, then `SkinService.equip`).
