# Environment

The run's world at shooter quality: road dressing from the PBR props, material variants
per biome, building meshes in the City middle row and the Wasteland ruins, a decal layer,
day and night presets per biome, and per-chunk budgets with a Studio counter. Branch
`feature/environment-pass` (2026-09-30); the design, the engine and reference research and
the screenshot plan are in `docs/world/environment.md`, the assets it still wants in
`docs/world/assets-needed.md`. See [[Gameplay Systems]] for run generation, [[Performance]]
for the budgets it extends and [[Assets Pipeline]] for the variants and props it uses.
[[Megascans]] imports Fab surfaces that replace these sets on the owner's machine.

## Files

| File | Role |
| --- | --- |
| `src/shared/config/DressingConfig.luau` | Data: zones, cluster recipes, per-biome densities and zone overrides, ground heights, material assignment per surface, budgets, triangle counts per mesh, tags |
| `src/shared/config/DecalsConfig.luau` | Data: the marks per biome (key into `AssetIds.texture.decal`, zone, size, count, layer) and the id lookup that treats a missing key as 0 |
| `src/shared/config/VisibilityConfig.luau` | How far each lighting preset lets you see, the exempt presets, the streaming radius mirror |
| `src/shared/world/DressingPlanner.luau` | Pure: turns the rules, an rng, an occupancy object and the loaded prop sizes into placements (zone, ground height, yaw, collide, shadow, tier, cluster). `luau tests/world/run.luau` |
| `src/shared/world/ChunkBudget.luau` | Pure: triangle estimate from counts, comparison against a budget, the printed line |
| `src/shared/world/FogBudget.luau` | Pure: visibility against the spawn distance and the streaming radius |
| `src/server/world/WorldDressing.luau` | Placements into instances: `WorldMeshes.placeNatural`, a primitive stand-in per group, burn patches, tags, per-biome `SurfaceAppearance.Color` tints |
| `src/server/world/WorldDecals.luau` | Ground cards, wall cards and the floor `Texture` from `DecalsConfig` |
| `src/server/world/ChunkBudgetCounter.luau` | Studio only: counts a built chunk, prints the line, stores it as the model attribute `BudgetLine`; `checkFog` warns about presets that would show a chunk spawning |
| `src/server/systems/ChunkFactory.luau` | Variants on the floor and aprons, the edge row recording each element's footprint and leaving gaps, mesh lane obstacles (`barrier`, `car_burned`, `rubble`, the new hedgehog and sandbag block), the dressing and decal calls, the counter |
| `src/server/systems/WorldFlanks.luau` | Building meshes in the City middle row, building meshes as sunk and tilted Wasteland ruins, mesh trees capped at x = 70 in the Forest, variants on sidewalks, kerbs, facades, ruins, berms, barn roofs and the forest floor |
| `src/shared/util/MaterialUtil.luau` | The eight 2026-09-29 variants registered so `apply` can use them |
| `src/shared/config/LightingConfig.luau` | Bloom, sun rays and shadow softness per preset; `CityNight`, `ForestNight`, `WastelandNight`, `FarmsteadNight`, `CornfieldNight`; `nightFor(biome)` |
| `src/client/systems/LightingDirector.luau` | Lerps the new fields, picks the biome's night preset, honours `DevLightingPreset` in Studio, exposes `getCurrent()` |
| `src/client/systems/PostFx.luau` | Bloom from the active preset instead of the Forest special case |
| `src/client/systems/EnvironmentQuality.luau` | The mobile tier: removes `TFZ_Detail`, stops `TFZ_ShadowNear` casting, on streamed chunks too; Studio scene triangle and draw-call line per biome change |
| `src/server/systems/SandboxBiomeStrip.luau` | The yard station: five chunks side by side and the 25 fixed screenshot cameras |
| `default.project.json` | `MaterialPattern = Organic` on the four ground variants, `Lighting.LightingStyle = Realistic` |

The three config modules hold no engine types, so `DressingPlanner`, `ChunkBudget`,
`FogBudget` and their tests load them under the standalone Luau CLI. New fields must stay
plain numbers, strings and tables.

## How a chunk is dressed

`ChunkFactory.build` runs as before up to the lane obstacles, then `WorldDressing.dress`
plans clusters into whatever ground `ChunkOccupancy` still has, and `WorldDecals.dress`
lays the marks. Zones are measured outwards from the road centre and apply to both sides:

| Zone | x | Collides | Shadows | Mobile tier |
| --- | --- | --- | --- | --- |
| shoulder | 26..29.2 | no | no | removed |
| sidewalk | 30.6..34.4 | no | no | removed |
| edge | 35.5..43.5 | yes | yes, 3 studs and taller | stops casting |
| apron | 44.5..59.5 | yes | yes, 3 studs and taller | stops casting |

Farmstead squeezes edge and apron to 35.5..41.5 (between the rail fence and the crop
rows); Cornfield to 30.6..35 (the corn mesh rows start at 37). Ground height is a function
of the biome and x (City sidewalk 0.9, forest floor part 0.7, everything else 0.5), so
nothing floats and no raycast is needed.

A cluster is one recipe (checkpoint, abandoned, burned, hedgehogs, truck, dump, roadside,
rubble) placed around an anchor: the first member always lands or the cluster is dropped
whole, later members take the zone their recipe names, scattered members try three spots,
line members (barriers, hedgehogs) follow each other along the road. Cluster centres keep
30 studs apart on one side, 18 across, 14 from the chunk ends, and two consecutive gaps on
a side differ by at least 4. Per chunk: City 4 clusters (10..18 props, sides alternate),
Wasteland 3 (8..14), Farmstead 2 (4..9), Cornfield 1 (2..4, one side), Forest 1 (2..4, one
side). The corridor edge row now records each element's footprint and leaves 6..18 studs
after it, which is where the clusters stand. On a pure cornfield edge the row does nothing,
because the `WorldFlanks` crop rows already reach the corridor edge; in City the street wall
belongs to `WorldFlanks` and the row only places kerb-side clutter in front of it.

Props in `ChunkFactory`: mesh trees carry an invisible trunk collider, so the trunk blocks
the runner and the canopy does not. Corn stands block sight, not movement; only the
part-built fallback corn wall gets stalk lines on its runner-facing side, mesh corn rows get
none. Car meshes face either way along z, so half are flipped 180 degrees and car rows do
not visibly repeat. The hedgehog and sandbag wall is one of the lane obstacle variants of
City and Wasteland: without the hedgehog mesh it falls back to the jersey divider, and if
only the sandbags are missing a third hedgehog takes the middle slot.

Tags: `TFZ_Prop` on every placed prop, `TFZ_Detail` on shoulder and sidewalk clutter,
the third and later members of a cluster and decal cards beyond the second, and
`TFZ_ShadowNear` on the casters. The anchor of a cluster is never detail, so every cluster
survives the mobile tier.

## Materials

| Surface | City | Forest | Wasteland | Farmstead | Cornfield |
| --- | --- | --- | --- | --- | --- |
| Floor | `TFZ_AsphaltCracked` 14 | `TFZ_Grass` 6 | `TFZ_RoadWorn` 60 (floor is asphalt now) | `TFZ_DirtDry` 14 | `TFZ_DirtDry` 14 |
| Apron | `TFZ_ConcreteDirty` 10 | `TFZ_Grass` 6 | `TFZ_DirtDry` 14 | `TFZ_Grass` 6 | `TFZ_Grass` 6 |
| Walls and parts | sidewalk, kerb, dividers `TFZ_ConcreteDirty`; 35 % of brick facades `TFZ_PlasterPeeling`; lamp posts and fence poles `TFZ_PaintPeelingMetal` | forest floor part `TFZ_DirtDry` | ruins `TFZ_ConcreteDirty`, berms `TFZ_Sand`, burn patches `TFZ_GroundBurned` | barn roofs `TFZ_MetalRusty` | |

Texel density: a 2K map at 14 studs per tile is 522 px/m, inside the 500 px/m target for
ground at the feet. `TFZ_RoadWorn` at 60 studs per tile is far below it and is used only
on the Wasteland floor, where one tile spans the road and its faded lines replace the
marking parts. The number to change if it blurs is `DressingConfig.materials.Wasteland.floor`.

- A City brick facade that gets `TFZ_PlasterPeeling` has its part colour set to a neutral
  204,194,180: the variant's colour map already carries the colour and a tint would double it.
- A burn patch is destroyed rather than placed when `MaterialUtil.apply` fails for
  `TFZ_GroundBurned`. The burn map is the point of the patch; a flat tint would read as a stain.
- A floor that falls back to a flat `Texture` tile gets the part colour lerped 35 % toward
  white as its `Color3`. Without it the texture's own grey wins and every biome floor reads
  the same.

## Decals

Marks are `Decal`s on thin invisible cards (a decal spans a whole face, so the floor
cannot carry one), lifted 0.02 plus 0.01 per layer above the ground, and one tiled
`Texture` on the floor for tyre wear. Keys in the project today: `asphalt_patch_a/b` (City
lane), `graffiti_a/b/c` and `leak_streaks` (cards on Jersey dividers, ruin fronts and
shopfronts). Keys listed but not yet uploaded (`road_crack_a`, `oil_stain_a`, `scorch_a`,
`blood_trail_a`, `blood_pool_a`, `tyre_marks_a`, `lane_arrow_worn`, `crosswalk_worn`,
`manhole_a`) place nothing until `AssetIds.texture.decal` has them. The tinted `Stain`
parts and the `Marking` parts stay meanwhile.

`DecalsConfig` zones: `lane` is the playable band within `LANE_HALF` (24 studs) of the road
centre, minus half the card width, and `END_CLEARANCE` (8 studs) off the chunk ends; it does
not avoid the centre line. `shoulder` is the strip just inside the corridor edge, `edge` the
corridor edge row, `wall` a card standing `WALL_GAP` in front of a named road-facing wall
part (each thin along its local x), and `floor` the tiled `Texture` on the floor's top face
rather than a card. Overlapping marks render by layer: cracks and patches 1, stains and
graffiti 2, blood 3.

`WorldDecals` collects the wall parts that may take a card in `GetDescendants` order with no
explicit sort. The seeded rng draws stay in step only because a chunk is always built in the
same order, which is what gives the same chunk the same marks.

## Lighting

Every preset carries `bloomIntensity`, `bloomThreshold`, `sunRays` and `shadowSoftness`;
`PostFx` reads bloom from `LightingDirector.getCurrent()`, so the old Forest special case
(0.62 / 1.0, above the wiki's bloom rule) is gone. The bloom rule: every preset keeps
`bloomIntensity` at most 0.4 and `bloomThreshold` at least 1.2. A night mission uses
`LightingConfig.nightFor(biome)`: `CityNight` (sodium lamps on blue-black), `ForestNight`
(mist), `WastelandNight` (moonlit, the furthest sight), `FarmsteadNight`, `CornfieldNight`
(the shortest sight); `Night` remains the fallback. In Studio the `Workspace` attribute
`DevLightingPreset` forces a preset. A preset forced in Studio, from the command bar or the
biome strip, wins over the map-boundary zone blend; setting it back to nil releases it.

Fog against streaming: `VisibilityConfig` states each preset's visibility, meant as the
distance at which its fog swallows a 10-stud object (City 340,
Forest 300, Wasteland 420, Farmstead 360, Cornfield 220, nights 180..380), and
`FogBudget` requires `visibility + CHUNK_LENGTH <= SPAWN_AHEAD_DISTANCE` (768) and
`SPAWN_AHEAD_DISTANCE + CHUNK_LENGTH + 64 <= StreamingTargetRadius` (1024). The tests run
it over every preset; `ChunkBudgetCounter.checkFog` warns in Studio. The visibility
numbers are design targets until the strip's shot C confirms them.
`VisibilityConfig.STREAMING_TARGET_RADIUS` mirrors `Workspace.StreamingTargetRadius` in
`default.project.json` because Luau cannot read that property, so change the two together.

## Budgets

| Measure | Desktop | Mobile |
| --- | --- | --- |
| Parts | 320 | 240 |
| Triangles (manifest counts, props without one assume 1.5k) | 320k | 180k |
| Instances | 520 | 360 |
| Decal cards and floor textures | 12 | 6 |
| Lights | 8 | 4 |
| Shadow casters | 80 | 30 |

`ChunkBudgetCounter.report` prints one line per built chunk in Studio, for example
`[Chunk City] parts 247/320 (m 240) tris 118k/320k (m 180k) inst 331/520 (m 360) decals 8
lights 6 shadows 44 | over mobile: parts`, and stores it on the model. The server builds
one world to the desktop budget; the mobile budget is met on a touch-only client by
`EnvironmentQuality` removing the detail tier. The Forest lever taken: mesh trees stop at
x = 70 in the near band and the primitive tree carries on behind them.

Triangle counts come from the `triangles` field of `assets/manifest.json`, copied into
`DressingConfig.triangles`. Props uploaded as Models carry no count there and take
`TRIANGLES_DEFAULT` (1500) until one is read in Studio; primitives count at the engine's own
mesh triangle counts (`DressingConfig.primitiveTriangles`). When a prop mesh is not loaded,
the planner sizes the primitive stand-in from `DressingConfig.fallbackSizes` (x, z, height in
studs, default 2, 2, 2); real sizes come from `WorldMeshes.naturalSize`.

## Test yard

`SandboxBiomeStrip.init()` (hook after `Sandbox` in `init.server.luau`) builds one chunk
per biome at `SandboxOrigin + (0, 0, -560)`, chunk centres at x = -520, -260, 0, 260,
520, seed 1234 and obstacle count 3, each with a label carrying its counter line. Set the
`Workspace` attribute `BiomeStripShot` to `City/A` .. `Cornfield/E` for the fixed cameras
(A runner, B kerb, C wide, D night, E feet); an empty string gives the camera back.

## Trade-offs (owner's calls made here)

- Wasteland floor is asphalt (`TFZ_RoadWorn`) instead of ground; the road-style lane now
  reads as a dead highway.
- One server build for every client; desktop versus mobile is the client's tier, not two
  builds.
- Forest mesh trees stop at x = 70 to bring the chunk toward the mobile triangle budget.
- Decal ids stay `rbxassetid://` strings on `Decal.Texture`, as the yard already does,
  though the docs now name `Decal.ColorMapContent`.
- `default.project.json` adds `LightingStyle = Realistic` beside `Technology = Future`.
- Light ranges stay at the wiki's 60 although the engine now allows 120.
- Preset visibility lives in `VisibilityConfig`, not in the preset table, so the pure fog
  check can load it without `Color3`.

Large static scenes split into streamed cells are a separate path: [[Prebuilt Maps]].
