# Environment pass — the run's world at shooter quality

Design for stage 5 of the run: dressing the road corridor with the PBR props and material
variants already in the project, rebuilding the primitive middle-row buildings and ruins
from the generated meshes, a decal layer, per-biome day and night lighting, and per-chunk
budgets with a Studio counter. Companion list of assets this pass wants but does not have:
[assets-needed.md](assets-needed.md).

Everything here is written against the code on `main` as of 2026-09-30. Chunk coordinates
are chunk-local: x across the road (0 is the centre line, the run direction is -z), z along
it (-64 is the far end of a 128-stud chunk, +64 the near end).

## 1. What the run builds today

`ChunkFactory.build` makes a 240 x 128 model per chunk: a 1-stud floor, two invisible
barriers at x = +-31, two 110-stud aprons, then the corridor edge rows, the flanks
(`WorldFlanks.build`), and the lane obstacles. `ChunkOccupancy` holds circle footprints
for the chunk being built so lane props and flank props never overlap. `ChunkSpawner`
pools finished chunk models per biome (transition chunks excepted), so anything parented
under the chunk model is pooled with it.

The bands, as the code lays them out (x is the distance from the centre line):

| Band | x range | What lives there |
| --- | --- | --- |
| Lane | 0..26 | 3 lane obstacles (`buildObstacle`, `findSpot(8)`), 2..5 tinted `Stain` parts, 16 `Marking` parts (City), field fill (trees, undergrowth, dry grass, corn walls) in field biomes |
| Shoulder | 26..30 | Nothing today; the playable band runs to 30 |
| Edge row | 33..42 | `buildCorridorEdge`: car rows, fence runs, police cars, rubble, Jersey rows (City); trees and boulders (Forest); rail fences (Farmstead); ruins, rubble, crashes, boulders (Wasteland); nothing (Cornfield). Reserved as one 8-stud strip afterwards |
| Near band | 42..~100 | `WorldFlanks`: City sidewalk 30..35, buildings at 56; Forest tree grid 37..94; Wasteland ruin shells at 44..54, dead trees, boulders, wrecks; Farmstead barn 54..84 and crop rows 42..124; Cornfield mesh rows at 37 and 43, tall crop rows 48..104 |
| Middle band | ~90..~140 | City facade primitives at 90 (heights 50..110, no detail); Forest canopy balls from 98; Wasteland berms 74..124; Farmstead windbreak trees at 134 |
| Far band | 140..228 | City skyline blocks; Forest canopy mass; Wasteland mesas and dead towers at 144; Farmstead and Cornfield hills at 154 |

Per biome:

| Biome | Floor / apron today | Lane | Edge row | Near | Middle / far | Lighting |
| --- | --- | --- | --- | --- | --- | --- |
| City | Asphalt `TFZ_Asphalt` (12) / Concrete texture tile 7 | kerb-side debris every 28..52 studs per side (car, rubble, divider, crash), lamps every 34..44 at x = 32.5, 1..2 burning barrels, 35 % traffic jam, 3 obstacles | car rows, chain-link fences, police car, rubble, Jersey rows | sidewalk, kerb, 85 % mesh buildings 26..60 tall else facade primitives | facade primitives without detail; skyline blocks; 30 % smoke column | `City` day, shared `Night` |
| Forest | Grass / Grass (both texture tiles) | trees (`tree_any`), 14 undergrowth clumps, logs and boulders | a tree every 8..12 studs, 25 % boulder | dark floor part, jittered tree grid to x = 94 (shadows inside 59), bushes | canopy balls and trunks from 98 | `Forest`, shared `Night` |
| Wasteland | Ground / Ground textures | rubble, boulders, crashes | primitive ruin 40 %, rubble 25 %, crash 17 %, boulder 18 % | primitive ruin shells, dead trees, boulder meshes, `car_wreck` | sand berms; mesas and dead towers | `Wasteland`, shared `Night` |
| Farmstead | Ground / Grass textures | dry grass clumps, 3 trees, cars, logs, boulders, crashes; telegraph poles at x = 127 | rail fences 24..48 long, 50 % tree | barn, low crop rows with a gap, hay bales | windbreak trees; hills | `Farmstead`, shared `Night` |
| Cornfield | Ground / Grass textures | 4 corn walls, logs, boulders; telegraph poles | none | two corn mesh rows, tall crop rows, corn mass at 124 | hills | `Cornfield`, shared `Night` |

Gaps this pass closes:

- The 16 PBR props (`WorldMeshConfig.groups` `barrier`, `sandbags`, `hedgehog`, `oil_barrel`, `tyre`, `trash`, `rubble`, `car_burned`, `car_abandoned`, `truck_crashed`, `cone`, `road_sign`) are loaded by `WorldMeshes` but placed nowhere in the run.
- The 8 material variants added on 2026-09-29 (`TFZ_AsphaltCracked`, `TFZ_RoadWorn`, `TFZ_ConcreteDirty`, `TFZ_GroundBurned`, `TFZ_DirtDry`, `TFZ_PlasterPeeling`, `TFZ_MetalRusty`, `TFZ_PaintPeelingMetal`) exist under `MaterialService` in `default.project.json` but are not in `MaterialUtil.sets`, so `MaterialUtil.apply` cannot use them. Aprons and every wall still use flat `Texture` tiles.
- Middle-row city buildings, wasteland ruins and the whole far band are primitives.
- "Decals" are tinted `SmoothPlastic` parts; the six decal textures in `AssetIds.texture.decal` are only shown on the test yard wall.
- One `Night` preset serves all five biomes; day presets do not state how far they let you see, so nothing ties fog to the 768-stud spawn edge.
- No budget is checked per chunk. The wiki's last measurement (`Performance.md`) is City 221 parts, Forest 237, Wasteland 114, Farmstead 166, Cornfield 129, and about 450k triangles for a Forest chunk before mesh LOD.

## 2. Engine research (Roblox creator docs, read 2026-09-30)

Read from the `Roblox/creator-docs` repository (`content/en-us/reference/engine/classes/*.yaml`,
`enums/*.yaml` and the guides). Docs URL = `https://create.roblox.com/docs/<path>`. Every
member this pass scripts was also checked against the API dump used by
`tools/validate_api.py`.

| Topic | What the docs say | What this pass does |
| --- | --- | --- |
| Mesh LOD | `MeshPart.RenderFidelity` `Automatic` picks the mesh LOD by distance: highest under 250 studs, medium 250..500, lowest past 500. `Performance` lets the engine discard appearance. ([MeshPart](https://create.roblox.com/docs/reference/engine/classes/MeshPart), [RenderFidelity](https://create.roblox.com/docs/reference/engine/enums/RenderFidelity)) | Keep `Automatic` (set in `WorldMeshes` via `CreateMeshPartAsync`). Middle-band buildings sit at 90..140 studs, so they render at full LOD; the pass keeps them at the 2.4k..2.9k triangles the manifest records |
| Collision | `Enum.CollisionFidelity`: `Default`, `Hull`, `Box`, `PreciseConvexDecomposition`, `Tunable`. `Box` has the lowest memory overhead; `Default` and precise "consume significantly more memory". ([CollisionFidelity](https://create.roblox.com/docs/reference/engine/enums/CollisionFidelity), [improve](https://create.roblox.com/docs/performance-optimization/improve)) | Props keep the fidelity `WorldMeshConfig` already declares (Box for props, Hull for boulders). Clutter inside the playable band never collides; blockers in the edge strip do |
| Draw calls | Identical `MeshContent` + `SurfaceAppearance` instances are merged into one draw call; overlapping transparent surfaces cost overdraw; textures beyond 512 px cost 4x memory per doubling. ([improve](https://create.roblox.com/docs/performance-optimization/improve)) | Props are clones of one template each, so a cluster of five tyres is one draw call. Decal cards are few (budgeted) and never stacked on the same spot |
| Material variants | `MaterialVariant.BaseMaterial`, `ColorMap`, `NormalMap`, `MetalnessMap`, `RoughnessMap` are plugin-only; `StudsPerTile` and `MaterialPattern` (`Regular`, `Organic`) are the runtime-visible knobs. A part uses a variant through `BasePart.MaterialVariant` (name must match a child of `MaterialService` with the same `BaseMaterial`); `MaterialService:SetBaseMaterialOverride` swaps a whole base material. ([MaterialVariant](https://create.roblox.com/docs/reference/engine/classes/MaterialVariant), [materials](https://create.roblox.com/docs/parts/materials)) | Variants stay declared in `default.project.json`; `MaterialUtil` only records which exist. This pass sets `MaterialPattern = Organic` on the ground variants (Rojo 7.7 accepts the property) and assigns variants per biome and band |
| Decals | `Decal.Face`, `Transparency`, `Color3`, `ZIndex` ("lower values render first"); `Texture.StudsPerTileU/V`, `OffsetStudsU/V`. `Decal.Texture` is marked as superseded by `Decal.ColorMapContent` (a `Content`). ([Decal](https://create.roblox.com/docs/reference/engine/classes/Decal), [Texture](https://create.roblox.com/docs/reference/engine/classes/Texture), [textures-decals](https://create.roblox.com/docs/parts/textures-decals)) | A decal spans a whole face, so marks go on thin invisible cards; wide wear goes on the floor's top face as a tiled `Texture`. Ids are read as `rbxassetid://` strings through `Decal.Texture`, as the yard already does; a key that is 0 or missing places nothing |
| SurfaceAppearance | MeshPart only; maps are plugin-only, `Color` is a runtime tint ("tinting does not affect performance"); `AlphaMode` `Overlay`, `Transparency`, `TintMask`, `Opaque`. ([surface-appearance](https://create.roblox.com/docs/art/modeling/surface-appearance), [SurfaceAppearance](https://create.roblox.com/docs/reference/engine/classes/SurfaceAppearance)) | Props keep their `PropSurfaces` templates; burned cars and rubble get a darker `Color` tint per biome instead of new maps |
| Lighting | `Lighting.Technology` is superseded by `Lighting.LightingStyle` (`Realistic`, `Soft`) and `PrioritizeLightingQuality`. `ShadowSoftness` (default 0.2), `GlobalShadows`, `EnvironmentDiffuseScale`, `EnvironmentSpecularScale`, `Ambient`, `OutdoorAmbient`, `Brightness`, `ClockTime`, `ExposureCompensation`. The engine "automatically degrades shadow quality at graphics levels below 4, eventually disabling shadows"; disable `CastShadow` on small parts. Light `Range` is now clamped at 120 studs (was 60). ([Lighting](https://create.roblox.com/docs/reference/engine/classes/Lighting), [lighting](https://create.roblox.com/docs/environment/lighting), [LightingStyle](https://create.roblox.com/docs/reference/engine/enums/LightingStyle)) | `default.project.json` keeps `Technology = Future` (still honoured) and adds `LightingStyle = Realistic` so the intent survives the deprecation. Shadows: only the edge strip and near band cast; clutter never does. Lamp ranges stay at 60, the wiki's budget |
| Atmosphere | `Density` hides objects and terrain (not the skybox); `Offset` controls light transmission and, set high, "may reveal level-of-detail popping"; `Color`, `Decay`, `Glare` need `Haze` > 0. Classic `FogStart/FogEnd` are hidden while an `Atmosphere` exists. Ranges are not documented. ([Atmosphere](https://create.roblox.com/docs/reference/engine/classes/Atmosphere), [atmosphere](https://create.roblox.com/docs/environment/atmosphere)) | Fog stays Atmosphere-only (wiki decision). Each preset declares a `visibility` distance the owner confirms in Studio; the pure check ties it to the spawn edge (section 5.6) |
| Post effects | `BloomEffect.Intensity/Size/Threshold`, `ColorCorrectionEffect.Brightness/Contrast/Saturation/TintColor`, `SunRaysEffect.Intensity/Spread`, `DepthOfFieldEffect`; effects "work differently or not at all" at low quality levels. ([post-processing-effects](https://create.roblox.com/docs/environment/post-processing-effects)) | Bloom, sun rays and grading move into the preset table so night presets can set their own; the wiki's bloom rule (Intensity <= 0.4, Threshold >= 1.2) holds for every preset |
| Streaming | `StreamingTargetRadius` (1024 here) is the largest stream-in distance; `StreamingMinRadius` default 64; `Model.ModelStreamingMode` `Default/Atomic/Persistent/PersistentPerPlayer/Nonatomic`; `StreamOutBehavior`; `Player:RequestStreamAroundAsync`. The streaming guides do not offer fog as a pop-in cure. ([streaming](https://create.roblox.com/docs/workspace/streaming), [Workspace](https://create.roblox.com/docs/reference/engine/classes/Workspace)) | Chunk models stay `Default` streaming mode (they are pooled whole). The pass checks `visibility + CHUNK_LENGTH <= SPAWN_AHEAD_DISTANCE` and `SPAWN_AHEAD_DISTANCE + CHUNK_LENGTH + 64 <= StreamingTargetRadius`, so a chunk is both replicated and fogged before it can be seen |
| Counters | `Stats.SceneTriangleCount`, `SceneDrawcallCount`, `ShadowsTriangleCount`, `InstanceCount`, `GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.GraphicsMeshParts)`; Render Stats (Shift+F2 on the client); `RunService:IsStudio()` is true in every Studio playtest. No per-frame triangle budget is stated; the only hard limit is 20k triangles per mesh. ([Stats](https://create.roblox.com/docs/reference/engine/classes/Stats), [identify](https://create.roblox.com/docs/performance-optimization/identify), [specifications](https://create.roblox.com/docs/art/modeling/specifications)) | Server: a Studio-only per-chunk estimate (parts, triangles from the manifest counts, instances, decals, lights, shadow casters) against the desktop and mobile budgets. Client: a Studio-only line with the real `SceneTriangleCount` and `SceneDrawcallCount` when the biome changes |
| Placement queries | `WorldRoot:Raycast`, `GetPartBoundsInBox`, `OverlapParams`, `RaycastParams.FilterType` `Include/Exclude`; `CanQuery = false` removes a part from queries. ([WorldRoot](https://create.roblox.com/docs/reference/engine/classes/WorldRoot)) | Not needed: chunks are flat and built synchronously, so ground height is a function of the band (section 5.2) and overlap is `ChunkOccupancy`, no raycasts |

Verified against the dump and typings (all scriptable): `BasePart.MaterialVariant`,
`BasePart.CastShadow`, `MeshPart.RenderFidelity`, `MaterialVariant.StudsPerTile`,
`MaterialVariant.MaterialPattern`, `Decal.Texture/Face/Transparency/Color3/ZIndex`,
`Texture.StudsPerTileU/V/OffsetStudsU/V`, `Atmosphere.Density/Offset/Haze/Glare/Color/Decay`,
`Lighting.Ambient/OutdoorAmbient/Brightness/ClockTime/ExposureCompensation/ShadowSoftness`,
`BloomEffect.*`, `ColorCorrectionEffect.*`, `SunRaysEffect.*`, `Stats.SceneTriangleCount/
SceneDrawcallCount/InstanceCount`, `RunService:IsStudio`, `UserInputService.TouchEnabled/
KeyboardEnabled/MouseEnabled`, `Instance:AddTag/HasTag`, `CollectionService:GetTagged/
GetInstanceAddedSignal`. Not scriptable and therefore left to `default.project.json`:
`Lighting.Technology`, `Lighting.LightingStyle`, `Workspace.StreamingTargetRadius`,
`MaterialVariant.*Map`, `SurfaceAppearance.*Map`. Not used because the docs do not carry them:
`CollisionFidelity.DynamicPreciseConvexDecomposition`, `SurfaceAppearance.TexturePack`.

## 3. Reference research

Read as search-result excerpts (the sandbox blocks most art sites), so each line carries the
page it came from. Rules marked *synthesis* are our reading of several sources, not a quoted
fact.

- Into the Dead 1/2 dress the corridor with "fences to vault, trees to dodge, and
  zombie-hiding corn crops", "eerie silhouettes, fog, and the iconic glowing eyes"; the
  Switch port's complaint was that zombies "just sort of pop-in rather than fade into view"
  because the view distance was short and the fog did not cover it. Fog is the spawn
  boundary and it has to hide the edge, not just decorate it.
  ([Fextralife review](https://fextralife.com/run-for-your-life-into-the-dead-review-2/),
  [Nintendo Life review](https://www.nintendolife.com/reviews/nintendo-switch/into_the_dead_2),
  [MyGamer review](https://www.mygamer.com/into-the-dead-2-switch-review/))
- PikPok kept upgrading the road after launch: 1.47 "new visual effects, prop models, and
  updated lighting", 1.50 a remastered chapter with "updated weather effects"; the night mode
  is "midnight, raining and you only have a flashlight that has a limited range".
  ([PikPok 1.47](https://pikpok.com/news/into-the-dead-2-1-47-0-update/),
  [PikPok 1.50](https://pikpok.com/news/into-the-dead-2-update-1-50/))
- Modern Warfare (2019) scanned "everything from old tires to demolished cars"; its art
  director wants the player to "get really close to walls" and see tiling detail; every
  light is volumetric and air density is set per area. Verdansk's road storytelling is
  burnt-out vehicles, "concrete defenses and immobile truck", checkpoints under overhead
  signs, sandbags, barricades; the map is remembered for drab, desaturated colour.
  ([Washington Post](https://www.washingtonpost.com/graphics/2019/video-games/call-of-duty-modern-warfare-behind-the-scenes/),
  [Activision blog](https://blog.activision.com/call-of-duty/2019-06/Initial-Intel-Call-of-Duty-Modern-Warfares-game-engine-is-put-through-its-paces),
  [Verdansk infrastructure](https://callofduty.fandom.com/wiki/Verdansk_(map)/Infrastructure_of_Verdansk_(Warzone_2.0)),
  [PC Gamer](https://www.pcgamer.com/what-happened-to-all-the-color-in-call-of-duty-warzones-pacific-map/))
- Call of Duty Zombies streets are "lit only by spotlights, street lamps, and long-abandoned
  vehicles": one warm light type per accent; the boarded window with six visible boards is
  the series' most readable prop.
  ([Season Four Reloaded](https://www.callofduty.com/blog/2021/07/season-four-reloaded-announcement-black-ops-cold-war-warzone),
  [Barriers](https://nazizombies.fandom.com/wiki/Barriers))
- Set dressing composes "in clusters of related details, where proximity, similarity, and
  implied connectedness helps us see objects as groups"; Naughty Dog's Anthony Vaccaro:
  "clumping assets and creating negative space enhances your details... always vary the size
  and distance of your detail clumping". Shape budget about 70 % big, 25 % medium, 5 % small;
  odd counts.
  ([Level Design Book](https://book.leveldesignbook.com/process/env-art),
  [80.lv Vaccaro](https://80.lv/articles/environment-art-tips-from-anthony-vaccaro),
  [Doretz](https://www.exp-points.com/chris-doretz-principles-of-concept-design))
- Wayfinding: "players look in the direction they are moving" and "focus on contrast";
  "warm colors and bright lights pull players in"; the art pass "should preserve gameplay
  clarity and should not bury routes under detail". Valve on Left 4 Dead: lightening the fog
  "gained a greater sense of scale... readability of characters greatly improved"; "a few
  critical lights" draw players "like a moth to a bug zapper".
  ([Level Design Book wayfinding](https://book.leveldesignbook.com/process/blockout/wayfinding),
  [300mind](https://300mind.studio/blog/game-level-design-guide/),
  [L4D commentary](https://left4dead.fandom.com/wiki/Developer_Commentary_(Left_4_Dead)),
  [L4D design theory](https://developer.valvesoftware.com/wiki/Left_4_Dead_Design_Theory))
- Decals are "mostly based on natural phenomena such as the cracks, water stains and puddles
  on the floor"; tiling textures "have to be inconspicuous". Texel density around 512 px/m for
  background props and 1024 px/m for hero or first-person surfaces.
  ([80.lv SanXia street](https://80.lv/articles/005cg-001agt-sanxia-street-1940-modular-approach-trim-sheets-decals),
  [Polycount texel density](https://polycount.com/discussion/192294/texel-density-and-units-in-depth))
- Distance fog "masks terrain LOD transitions, pop-in and the far clip plane"; Roblox
  Atmosphere fog starts at the camera, so density and offset must be tuned together.
  ([Distance fog](https://en.wikipedia.org/wiki/Distance_fog),
  [DevForum atmosphere thread](https://devforum.roblox.com/t/atmospheric-fog-needs-something-like-the-old-fogstart/701963))

Rules adopted:

1. Three depth bands: the lane and the first 10 studs of apron get full detail and decals;
   the near band gets props; past 110 studs only silhouettes. *synthesis*
2. Lanes clean, edges busy: nothing but flat decals and non-colliding clutter inside x = 30;
   clusters on the edge strip and apron. *synthesis*
3. A point of interest is 2..5 related props, odd counts preferred, one big + one medium +
   small scatter, centres at least 30 studs apart and never the same gap twice in a row.
4. Two points of interest per side per 128-stud chunk in the City, fewer elsewhere; at
   24..60 studs/s that is one every 1..3 s. *synthesis*
5. One warm light accent per chunk (lamp, fire barrel, headlights) on a cool base.
6. Fog is coloured, never black; each preset states its visibility and it is shorter than
   the spawn edge.
7. Cracks, oil, scorch and blood are decals; tiling surfaces stay featureless.
8. Texel density at the feet at least 500 px/m (2K map at 14 studs/tile = 522 px/m); walls
   beyond the edge strip at least 250 px/m.
9. Day and night are separate presets per biome, not a slider.
10. Every prop in the lane band is telegraphed as a silhouette in the fog first.

## 4. Zones (chunk-local)

| Zone | x (either side) | Ground top y | Collides | Casts shadow | Who may sit here |
| --- | --- | --- | --- | --- | --- |
| lane | 0..26 | 0.5 (floor) | obstacles only | obstacles only | lane obstacles (existing system), decal cards, floor texture |
| shoulder | 26..30 | 0.5 | never | never | cones, tyres, trash bags, blood pools |
| sidewalk (City) | 30..35 | 0.9 | never | never | trash bags, tyres, cones, oil barrels |
| edge | 35..44 | 0.5 (0.9 on the City sidewalk band's inner stud) | yes | yes | barriers, sandbags, hedgehogs, cars, trucks, rubble, signs, barrels |
| apron | 44..60 | 0.5 (Forest 0.7 on the ForestFloor part) | yes | yes for anything taller than 3 studs | trucks, cars, rubble, ground patches |
| near | 60..110 | as the flank builds it | flank rules | near band only | flank builders (`WorldFlanks`) |
| middle | 90..140 | flank | never | never | mesh buildings, ruin shells |
| far | 140..228 | flank | never | never | silhouettes |

Ground height is a pure function `DressingPlanner.groundHeight(biome, x)`; every placement
uses it plus the mesh's own sink so nothing floats and nothing is buried. Chunks are flat, so
no raycast is needed. Lane obstacles keep their `findSpot(8)` placement, and the planner runs
after them and after the edge row, so it can only take free ground.

## 5. Design

### 5.1 Road dressing

Data: `src/shared/config/DressingConfig.luau` (rules per biome). Logic:
`src/shared/world/DressingPlanner.luau`, pure Luau (no services, no `Vector3`), tested by
`tests/world/run.luau`. It takes the biome rules, an `Rng` (anything with `NextNumber` and
`NextInteger`, so `Random` fits), an occupancy object (anything with `claim`, so
`ChunkOccupancy` fits) and a size table (prop name to footprint in studs, filled from
`WorldMeshes.naturalSize` at runtime, from nominal sizes in tests). It returns a list of
placements: `{ group, name?, x, z, yaw, y, collide, shadow, tier, cluster }`. The server
module `src/server/world/WorldDressing.luau` turns placements into instances with
`WorldMeshes.placeNatural` and a primitive fallback per group when the mesh is not loaded.

Cluster recipes (a recipe places 2..5 props around an anchor; counts are ranges):

| Recipe | Members | Zone | Biomes |
| --- | --- | --- | --- |
| checkpoint | 2..3 `barrier` in a line, 1 `sandbags`, 1..2 `cone`, 0..1 `road_sign` | edge | City, Wasteland |
| abandoned | 1 `car_abandoned`, 0..2 `tyre`, 1..3 `trash`, 0..1 `cone` | edge (car), shoulder (clutter) | City, Farmstead |
| burned | 1 `car_burned`, 1..2 `oil_barrel`, 0..1 `rubble`, scorch patch | edge, apron | City, Wasteland |
| hedgehogs | 2..3 `hedgehog`, 0..1 `barrier`, 0..1 `sandbags` | edge | City, Wasteland |
| truck | 1 `truck_crashed` (diagonal), 1..3 `cone`, 0..2 `tyre` | apron (truck), shoulder (clutter) | City, Wasteland, Farmstead |
| dump | 2..3 `tyre`, 1..2 `trash`, 0..1 `oil_barrel` | sidewalk / shoulder | City, Farmstead, Forest |
| roadside | 1 `road_sign`, 0..1 `tyre`, 0..1 `cone` | edge | Farmstead, Cornfield, Forest |
| rubble | 1..2 `rubble`, 0..2 `oil_barrel`, 0..1 `hedgehog` | edge, apron | Wasteland |

Density per chunk (clusters, then props):

| Biome | Clusters | Props | Sides | Notes |
| --- | --- | --- | --- | --- |
| City | 4 (2 per side) | 10..18 | alternate | the existing edge row keeps its cars and fences but leaves gaps (below) |
| Wasteland | 3 | 8..14 | alternate | scorch patches under every burned car |
| Farmstead | 2 | 4..9 | alternate | covered car by the barn side, sign on the other |
| Cornfield | 1 | 2..4 | one | the corn rows start at the edge, so only a sign, tyre or cone |
| Forest | 1 | 2..4 | one | a dump or a roadside sign, nothing that reads as a road checkpoint |

Spacing: cluster centres at least 30 studs apart along z on the same side, at least 18
across sides, never inside 14 studs of a chunk end (the neighbour chunk owns that ground).
The planner varies the gap by drawing it from the range each time, and rejects a gap equal
to the previous one (rule 3). Zones are chosen by member: the recipe says which zone each
member wants; members that fail `claim` are dropped, and a cluster that loses its first
member is dropped whole, so a half cluster never ships.

Edge row co-existence: `buildCorridorEdge` today builds elements back to back and the
whole 8-stud strip is then reserved. It changes to record each element's real z extent as a
box and to leave a gap of 6..18 studs after each element, so about a third of the strip is
free for clusters. Nothing else about the row changes.

Collision and shadows follow the zone table. Props also get tags: `TFZ_Prop` (every placed
prop), `TFZ_Detail` (shoulder and sidewalk clutter, the third and later members of a cluster,
decal cards) which the mobile tier removes, and `TFZ_ShadowNear` (edge and apron props that
cast) which the mobile tier switches to no shadow.

Lane obstacles gain mesh variants with the same footprints: City `buildDivider` places a
`barrier` mesh when loaded, `buildCrash` a `car_burned`, Wasteland rubble the `rubble` prop,
and a new `buildBlock` kind puts `hedgehog` + `sandbags` across a lane in City and
Wasteland. Every one keeps its primitive fallback.

### 5.2 Material variants

`MaterialUtil.sets` gains the eight variants (colour, normal, roughness ids from
`TexturesConfig`, `studsPerTile` as declared in `default.project.json`). Assignment:

| Surface | City | Forest | Wasteland | Farmstead | Cornfield |
| --- | --- | --- | --- | --- | --- |
| Floor | `TFZ_AsphaltCracked` (14) | `TFZ_Grass` (6) | `TFZ_RoadWorn` (60), floor material Asphalt | `TFZ_DirtDry` (14) | `TFZ_DirtDry` (14) |
| Apron | `TFZ_ConcreteDirty` (10) | `TFZ_Grass` (6) | `TFZ_DirtDry` (14) | `TFZ_Grass` (6) | `TFZ_Grass` (6) |
| Sidewalk, kerb | `TFZ_ConcreteDirty` | | | | |
| Facade blocks | 35 % of brick styles `TFZ_PlasterPeeling` (12); others keep their base material | | ruin shells `TFZ_ConcreteDirty` | barn walls `TFZ_Wood` (override) | |
| Jersey dividers | `TFZ_ConcreteDirty` | | `TFZ_ConcreteDirty` | | |
| Lamp posts, fence poles, wire hardware | `TFZ_PaintPeelingMetal` (6) | | `TFZ_MetalRusty` (6) | `TFZ_MetalRusty` on barn roof sheets | |
| Ground patches | `TFZ_GroundBurned` (16) under burned cars | `TFZ_DirtDry` on the forest floor part | `TFZ_GroundBurned` under burned cars and scorch points | | |

Texel density: an ambientCG 2K map at 14 studs per tile is 2048 / (14 x 0.28 m) = 522 px/m,
inside rule 8 for the ground at the feet; 10 studs is 731 px/m; 6 studs is 1219 px/m. The
one exception is `TFZ_RoadWorn` at 60 studs per tile (one tile spans the playable width so
its painted lines land once): a 2K map is 122 px/m, a 4K map 244 px/m. It is used only on
the Wasteland floor, where the grading is desaturated and hazy and where its faded lines
replace the 16 `Marking` parts. If it blurs at the feet in the Studio check, the fallback is
one line in `DressingConfig.materials.Wasteland.floor` (`TFZ_AsphaltCracked`) and
`roadMarkings = true` in `LocationsConfig`.

`MaterialPattern = Organic` is set on `TFZ_DirtDry`, `TFZ_GroundBurned`, `TFZ_AsphaltCracked`
and `TFZ_ConcreteDirty` in `default.project.json` so the ground repeats less; `TFZ_RoadWorn`
stays `Regular` because its lines must line up.

### 5.3 Mesh buildings and ruins

City middle band (`WorldFlanks.cityFlank`, slots 22..40 wide at x = 90): each slot tries a
`building` mesh first, fitted to the slot width and clamped to 50..110 tall (the meshes are
2.4k..2.9k triangles, so a chunk's 8..12 middle slots add at most 35k triangles); the
primitive `facadeBuilding(detail = false)` stays as the fallback and for one slot in four,
so the skyline keeps its variety. Middle-band meshes never cast shadows and never collide.
Far band stays primitive silhouettes.

Wasteland ruins (`ruinShell`): when a `building_concrete` or `building_brick` mesh is loaded
the shell becomes that mesh sunk 35..55 % into the ground, tilted 3..8 degrees away from the
road, with a `rubble` prop at its street foot and the existing `RuinFront` wall segments
cut to two; otherwise the primitive shell as today. The buried mesh reads as a gutted block
at 40..80 studs without new assets.

### 5.4 Decal layer

`src/shared/config/DecalsConfig.luau` lists marks; `src/server/world/WorldDecals.luau`
places them. Each entry: `key` (into `AssetIds.texture.decal`), biomes, zone, size range,
count range per chunk, transparency range, `ZIndex` layer, tier. The id lookup is
`(AssetIds.texture.decal :: any)[key] or 0`; 0 places nothing, so a missing key is silent.

| Key | Status | Biomes | Zone | Size (studs) | Per chunk | Layer |
| --- | --- | --- | --- | --- | --- | --- |
| `asphalt_patch_a`, `asphalt_patch_b` | in project | City | lane | 8..14 | 2..4 | 1 (cracks) |
| `graffiti_a/b/c` | in project | City, Wasteland | wall card on Jersey rows, ruin fronts, facade bases | 5..8 | 1..3 | 2 |
| `leak_streaks` | in project | City | wall card at facade bases | 4 x 9 | 0..2 | 2 |
| `road_crack_a` | needed | City, Wasteland | lane | 6..12 | 1..3 | 1 |
| `oil_stain_a` | needed | City, Wasteland | edge, under cars | 5..8 | 1..2 | 2 |
| `scorch_a` | needed | City, Wasteland | under burned cars | 10..16 | per burned car | 2 |
| `blood_trail_a` | needed | all | lane and shoulder | 4 x 10 | 0..2 | 3 |
| `blood_pool_a` | needed | all | shoulder, edge near barricades | 3..5 | 0..2 | 3 |
| `tyre_marks_a` | needed | City, Wasteland | floor `Texture`, 60 x 64 tile | 1 | floor |
| `lane_arrow_worn`, `crosswalk_worn`, `manhole_a` | needed | City | lane | 6 / 40 x 8 / 4 | 0..1 | 1 |

Until the needed keys arrive, the tinted `Stain` parts stay (they are the blood layer today)
and the `Marking` parts stay in the City. A decal card is a `Part` (w x 0.05 x d),
`Transparency = 1`, no collide, no query, no touch, no shadow, with one `Decal` on its top
face; cards sit at ground + 0.02 + layer x 0.01 so layers never fight. Wall cards stand 0.06
studs in front of the wall face. Cards are `TFZ_Detail` (tier) except the first two per
chunk, so the mobile tier keeps a little.

### 5.5 Lighting presets

`LightingConfig.LightingPreset` gains `visibility` (studs, the distance at which the
preset's fog swallows a 10-stud object, confirmed in Studio), `bloomIntensity`,
`bloomThreshold`, `sunRays`, `shadowSoftness`. `PostFx` reads bloom from the active preset
(today it hard-codes 0.34/1.25 with a Forest exception); `LightingDirector` lerps the new
fields with the old ones. `LightingDirector` picks `<Biome>Night` when `NightMission` is
set and the preset exists, else `Night`; in Studio a `DevLightingPreset` string attribute on
`Workspace` forces a preset for screenshots.

Day presets keep their current colours and get:

| Preset | visibility | bloom I / T | sunRays | shadowSoftness |
| --- | --- | --- | --- | --- |
| City | 340 | 0.34 / 1.25 | 0.08 | 0.35 |
| Forest | 300 | 0.4 / 1.2 (was 0.62 / 1.0, above the wiki rule) | 0.12 | 0.5 |
| Wasteland | 420 | 0.3 / 1.3 | 0.1 | 0.25 |
| Farmstead | 360 | 0.36 / 1.25 | 0.14 | 0.4 |
| Cornfield | 220 | 0.3 / 1.3 | 0.06 | 0.5 |
| Hub | 600 | 0.34 / 1.25 | 0.08 | 0.35 |
| Sandbox | 1400 | 0.2 / 1.4 | 0.04 | 0.35 |

Night presets, one per biome (`Night` stays as the fallback and for the hub):

| Preset | clock | brightness | ambient / outdoor | atmosphere density / offset / haze / glare | colour / decay | grading sat / contrast / tint | visibility | bloom |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CityNight | 0.4 | 0.25 | (6,6,12) / (12,12,20) | 0.92 / 0.7 / 1.4 / 0 | (34,36,58) / (12,12,26) | -0.25 / 0.14 / (208,218,255) | 300 | 0.4 / 1.2 (sodium lamps glow) |
| ForestNight | 23.6 | 0.2 | (4,8,8) / (8,14,14) | 0.95 / 0.8 / 2.0 / 0 | (26,40,44) / (8,16,18) | -0.35 / 0.16 / (196,224,236) | 220 | 0.3 / 1.3 |
| WastelandNight | 1.2 | 0.35 | (10,10,14) / (16,16,22) | 0.86 / 0.6 / 0.8 / 0.1 | (44,46,60) / (16,16,28) | -0.3 / 0.12 / (214,220,255) | 380 | 0.3 / 1.3 |
| FarmsteadNight | 0.8 | 0.22 | (6,6,10) / (12,11,18) | 0.9 / 0.72 / 1.6 / 0 | (30,30,48) / (12,10,22) | -0.28 / 0.14 / (210,214,250) | 300 | 0.36 / 1.25 |
| CornfieldNight | 0.2 | 0.18 | (8,9,10) / (14,15,16) | 0.97 / 0.85 / 2.6 / 0 | (36,38,42) / (14,14,16) | -0.4 / 0.1 / (220,228,232) | 180 | 0.3 / 1.3 |

The warm accent at night is the existing lamp (City), burning barrel (City, Wasteland) and
lit windows (City middle band); Farmstead gets one barn lamp (`PointLight`, range 40) per
chunk that has a barn, Forest and Cornfield none (the flashlight is the player's).

### 5.6 Fog against streaming

Pure check `src/shared/world/FogBudget.luau`, run by the tests over every preset:

- `visibility + CHUNK_LENGTH <= SPAWN_AHEAD_DISTANCE` (768): the newest chunk is spawned
  a full chunk beyond what the fog lets you see, so a chunk never appears inside sight.
- `SPAWN_AHEAD_DISTANCE + CHUNK_LENGTH + 64 <= StreamingTargetRadius` (1024): the server
  builds nothing the client cannot already have.
- `DESPAWN_BEHIND_DISTANCE >= 2 x visibility / 3` is not required (the camera looks
  forward) and is only reported.

Sandbox and Hub presets are exempt from the first rule (no run there). The Studio
confirmation is shot C of the screenshot plan: from the strip's wide camera the far end of
the five chunks must be lost in fog.

### 5.7 Budgets and the counter

Per chunk, all biomes:

| Measure | Desktop | Mobile | How it is estimated |
| --- | --- | --- | --- |
| Parts (`BasePart` including `MeshPart`) | 320 | 240 | count |
| Triangles | 320k | 180k | `MeshPart`: the manifest count per mesh name (props without a count assume 1.5k); primitive `Part` 12, `WedgePart` 8, cylinder and ball 96 |
| Instances (all descendants) | 520 | 360 | count |
| Decal cards + floor textures | 12 | 6 | count |
| Lights | 8 | 4 | count |
| Shadow casters | 80 | 30 | parts with `CastShadow` |

Estimation and comparison are pure (`src/shared/world/ChunkBudget.luau`), tested. The
server module `src/server/world/ChunkBudgetCounter.luau` walks a built chunk model and, in
Studio only, prints one line per build:

```
[Chunk City] parts 247/320 (m 240) tris 118k/320k (m 180k) inst 331/520 (m 360) decals 8 lights 6 shadows 44 | over mobile: parts
```

The client module `src/client/systems/EnvironmentQuality.luau` decides the tier: mobile when
`UserInputService.TouchEnabled` and neither keyboard nor mouse is enabled, else desktop. On
mobile it destroys `TFZ_Detail` instances locally and sets `CastShadow = false` on
`TFZ_ShadowNear`, listening to `CollectionService:GetInstanceAddedSignal` so streamed-in
chunks are handled too. In Studio it also prints `Stats.SceneTriangleCount` and
`SceneDrawcallCount` when `Workspace.Biome` changes, so the estimate can be compared with a
real number.

Forest is the one biome over the mobile triangle budget today (about 450k). Lever taken:
the near-band tree grid keeps mesh trees inside x = 70 and uses the primitive tree past it
(the canopy balls already hide the difference), which halves mesh trees per chunk to about
60 (240k triangles); the rest is the mobile tier's job. This is recorded as a trade-off.

### 5.8 Modules and data flow

```
ChunkFactory.build
  floor, aprons          -> MaterialUtil.apply(DressingConfig.materials[biome].floor/apron)
  markings, stains       -> unchanged
  ChunkOccupancy.reset
  buildCorridorEdge      -> reserves per element, leaves gaps
  WorldFlanks.build      -> mesh middle band, mesh ruins, materials on walls and poles
  lane obstacles         -> mesh variants with primitive fallback
  DressingPlanner.plan   -> WorldDressing.place (props, patches, tags)
  DecalsConfig           -> WorldDecals.place (cards, floor texture)
  ChunkBudgetCounter.report (Studio only)
```

New files: `src/shared/config/DressingConfig.luau`, `src/shared/config/DecalsConfig.luau`,
`src/shared/world/DressingPlanner.luau`, `src/shared/world/ChunkBudget.luau`,
`src/shared/world/FogBudget.luau`, `src/server/world/WorldDressing.luau`,
`src/server/world/WorldDecals.luau`, `src/server/world/ChunkBudgetCounter.luau`,
`src/client/systems/EnvironmentQuality.luau`, `src/server/systems/SandboxBiomeStrip.luau`,
`tests/world/run.luau`. Edited: `ChunkFactory`, `WorldFlanks`, `MaterialUtil`,
`LightingConfig`, `LightingDirector`, `PostFx`, `LocationsConfig` (Wasteland floor),
`default.project.json` (variant patterns, `LightingStyle`).

Tests (`luau tests/world/run.luau`): planner keeps every placement inside its zone and off
the lanes, respects occupancy and spacing, drops half clusters, never repeats a gap, is
deterministic per seed; ground height per zone; budget estimate arithmetic and the over
list; fog budget over every preset and the constants; decal id lookup treats missing keys
as 0; material assignment names only registered sets.

## 6. Screenshot test plan

`SandboxBiomeStrip` (server, enabled with the yard) builds one pure chunk per biome side by
side at `SandboxOrigin + (0, 0, -560)`, south of the yard floor (the yard ends at z = -400),
chunk centres at x = -520, -260, 0, 260, 520 in `LocationsConfig.order`, all facing -z like
the run, seed 1234 and obstacle count 3 (the wiki's measurement setup). Each chunk gets a
floating label with its biome and the counter line.

The shot list is a table in the module; the owner sets the `Workspace` attribute
`BiomeStripShot` to `"<Biome>/<Shot>"` (for example `City/A`, `Forest/D`) and the server
writes `DevCameraCFrame` (which `CameraController` already honours in Studio) and
`DevLightingPreset`; an empty string gives the camera back. Shots relative to the chunk
centre C (floor top at y = 0.5):

| Shot | Camera | Looks at | Preset | Checks |
| --- | --- | --- | --- | --- |
| A runner | C + (0, 5, 60) | C + (0, 3, -60) | biome day | lanes clear; three lanes readable; clusters read as one thing each; nothing floats at the edge strip |
| B kerb | C + (-22, 3.5, 30) | C + (40, 4, -20) | biome day | edge row and cluster do not intersect; shadows only on edge and apron props; decals not fighting the floor |
| C wide | C + (0, 42, 120) | C + (0, 8, -40) | biome day | middle band meshes fit their slots; far band is silhouette; the far end of the strip is in fog |
| D night | as A | as A | biome night | one warm accent visible; fog colour not black; no over-bloom (lamp halos stay round) |
| E feet | C + (8, 2.2, 10) | C + (8, 0.5, -6) | biome day | texel density at the feet (no blur), variant seams, floor texture tiling |

Five biomes x five shots = 25 fixed positions, all stored in the module. A per-biome note
lists what must be true; the PR carries the same list for the owner.

## 7. Trade-offs recorded

- Wasteland floor becomes asphalt (`TFZ_RoadWorn`) instead of ground: the road-style lane
  now looks like a road; `RoadWorn` is below the texel target and is used nowhere else.
- Server builds one world for every client; desktop and mobile budgets are met by the
  client stripping tagged detail, not by two builds.
- Mesh trees stop at x = 70 in the Forest near band to bring the chunk toward the mobile
  triangle budget.
- Decal ids stay `rbxassetid://` strings on `Decal.Texture` (same as the yard), although
  the docs now point at `Decal.ColorMapContent`.
- `default.project.json` adds `LightingStyle = Realistic` next to `Technology = Future`;
  both are Studio-only properties, so nothing in Luau depends on either.
- Light ranges stay at the wiki's 60 even though the engine now allows 120.
