# Map Segments

A run is a chain of long maps instead of short biome swaps. The squad leader picks the
start map in the helicopter lobby. Each map is a long stretch built from its own
sub-locations, and the next map is prepared while the squad runs the current one. Every
map ends in a fork between two of its neighbours, both prepared. The boundary blends
over five chunks, lighting and ambience included, so the run never cuts from City
straight into Desert. Branch `cloud/map-segments` (2026-10-04). Related: [[Route Forks]],
[[Environment]], [[Gameplay Systems]], [[Performance]].

Before: `LocationsConfig` biomes lasted 4 to 8 chunks of 128 studs, which is 20 to 40 s
at 24 studs/s and 8 to 17 s at 60, and blended over `TRANSITION_CHUNKS = 2`.

## Status board

| Map | Status | Sub-locations | Neighbours (enabled in bold) | Lighting | Ambience bed |
| --- | --- | --- | --- | --- | --- |
| City | enabled | City | **Wasteland**, **Forest**, Suburbs, Highway | City | `audio/ambience/city_bed` needed |
| Wasteland | enabled | Wasteland | **City**, **Forest**, **Farmland**, Highway, Desert | Wasteland | `audio/ambience/wasteland_bed` needed |
| Forest | enabled | Forest | **City**, **Wasteland**, **Farmland**, Mountains, Swamp | Forest | `audio/ambience/forest_bed` needed |
| Farmland | enabled | Farmstead, Cornfield | **Forest**, **Wasteland**, Suburbs | Farmstead | `audio/ambience/farmland_bed` needed |
| Suburbs | disabled, no content | none | City, Farmland, Highway | City | slot not yet added |
| Highway | disabled, no content | none | City, Wasteland, Suburbs, Desert | Wasteland | slot not yet added |
| Desert | disabled, no content | none | Wasteland, Highway, Mountains | Wasteland | slot not yet added |
| Mountains | disabled, no content | none | Forest, Desert, Swamp | Forest | slot not yet added |
| Swamp | disabled, no content | none | Forest, Mountains | Forest | slot not yet added |

To enable a map:
- give it `locationIds` (new `LocationsConfig` entries with their chunk content);
- add its ambience slot to the manifest;
- set `enabled = true`.

`MapMath.check` (tests/world) then requires two enabled neighbours and two-way links.
The lobby offers Random and the enabled maps; Random draws an enabled map from the run's
seed.

| Item | Status |
| --- | --- |
| Maps with sub-locations, durations, neighbours, lighting, ambience | done, pure tests |
| Lengths from duration and expected speed, with the floor | done, pure tests |
| Map-end fork between two neighbours | done, needs a Studio run |
| Pool warm-up and transition pre-build (server), asset preload (clients) | done, `preloadSeconds` needs measuring |
| 5-chunk transition: ground patches, mixed edges, staggered flanks, dressing density | done, check in the yard strip |
| Lighting interpolated over the zone, ambience crossfade | done (beds silent until uploaded) |
| Vote line closer (638 instead of 1024 studs) | done, `ForkResolvedLead` and `ForkPlacedAfter` to measure |
| Step 2: physical fork (the field splits at the divider) | not started, separate PR |

## Files

| File | Role |
| --- | --- |
| `src/shared/config/MapsConfig.luau` | The maps (sub-locations, `durationSeconds` 120 to 180 by default, neighbours, lighting preset, ambience slot, `preloadSeconds`, `preloadGroups`, optional speed profile), `MAP_TRANSITION_CHUNKS = 5`, `FLOOR_FACTOR = 1.5`, warm-up numbers. Data only |
| `src/shared/world/MapMath.luau` | Pure: speed and distance over the ramp, the floor, map length in chunks, fork options, next sub-location, start map, transition and zone alpha, crossfade, vote lead, pools to free, the table check. `luau tests/world/run.luau` |
| `src/server/systems/RoutePlan.luau` | Plans a whole map when it begins (length, sub-locations, the end fork with each option's first sub-location); holds at the boundary while the vote is open |
| `src/server/systems/ChunkSpawner.luau` | The map transition (the new map's first chunks blend from the old map's last sub-location, pre-built ones taken first), sub-location transitions inside a map; Workspace attributes `Map`, `MapBlendFrom`, `MapBlendTo`, `MapBlendStart`, `MapBlendEnd`, `MapBlendAlpha` |
| `src/server/systems/ChunkPools.luau` | Built chunks in ServerStorage: pools per location, pre-built transition chunks |
| `src/server/systems/MapPreload.luau` | When a map becomes current, warms both options under a per-frame budget, frees maps two steps behind and the option not taken; `MapPreload` attribute for the clients; `MapWarmSeconds` |
| `src/server/systems/ForkService.luau` | Divider, signs, vote at `VOTE_LEAD`; option names from `MapsConfig`; `ForkResolvedLead`, `ForkResolvedAt` |
| `src/server/systems/ChunkFactory.luau`, `WorldFlanks.luau`, `world/WorldDressing.luau`, `shared/world/DressingPlanner.luau` | The blend by alpha (below) |
| `src/client/systems/LightingDirector.luau` | Map presets; inside the zone the two maps' presets blended by the player's own distance |
| `src/client/systems/MapAmbience.luau` | Map ambience beds, equal-power crossfade over the zone |
| `src/client/systems/MapPreloader.luau` | `ContentProvider:PreloadAsync` of both options' meshes, textures, prop surfaces and material variants |
| `src/server/systems/SandboxMapStrip.luau` | Yard strip: every allowed transition as a row |
| `SquadService`, `SquadConfigGui`, `MissionService` | The lobby's map choice is the start map; Random replaces Mixed |

## Rules

### Length

`MapMath.lengthChunks` gives the distance the drawn duration covers at the speed
expected there. It integrates the speed ramp on the run's clock, as `DistanceTracker`
does, from the map's expected start time. That distance is never under the floor, the
larger of:
- `SPAWN_AHEAD_DISTANCE + MAX_RUN_SPEED * preloadSeconds(slower next option) * 1.5`
  (the owner's "speed x build time" rule);
- the fork's own span, `FIRST_DIVIDER_AT + DIVIDER_LENGTH + VOTE_LEAD` (1322 studs).

At today's constant 24 studs/s a map runs 23 to 34 chunks (2880 to 4320 studs). A map
with a ramp to 60 gets proportionally longer for the same minutes.

### Forks

Every map end is a fork between two different enabled neighbours (`MapMath.forkOptions`),
drawn when the map begins so both can be prepared. Each option's first sub-location is
drawn at the same time. A map never forks into a map that is not its neighbour. City and
Desert are not neighbours.

### Preload

When the lead runner enters a map, `MapPreload` does the following, at least one chunk a
frame within `WARM_BUDGET_MS` (4 ms):
- builds both options' five transition chunks (the vote waits on these, so they go
  first);
- warms each option's sub-location pools to 3 chunks;
- names the options in `MapPreload` for the clients' `PreloadAsync`.

When the vote closes, the option not taken loses its queued work, its transition chunks
and its pools. Pools of maps two steps behind are freed, and everything goes when the
run ends.

### Transition

The new map's first five chunks blend from the old map's last sub-location, at alpha
1/6, 2/6, ... 5/6:
- floor and apron colours lerp;
- the base material switches at 0.5, with irregular patches of the other location's
  ground (most at mid-blend). A patch is a cluster of two to four overlapping turned
  slabs and discs; along the chunk they thicken toward the end where the other
  ground's share grows and may hang over it, so the switch line itself is broken up
  (`ChunkFactory.addGroundPatches`, at most 6 clusters per surface);
- each corridor-edge element is the new style with probability alpha;
- each flank switches on its own (left at 0.4, right at 0.6);
- both locations dress the chunk at their shares of the density.

Inside a map, sub-locations still blend over `TRANSITION_CHUNKS` (2).

### Lighting and ambience

The server publishes the zone (`MapBlendFrom`, `MapBlendTo`, `MapBlendStart`,
`MapBlendEnd`) once the next map is chosen. Each client blends the two presets by its own
distance through the zone (smoothstep), so the light changes across the five chunks
rather than at the boundary. Night uses each preset's night variant. Ambience beds
crossfade at equal power over the same zone.

### Vote lead

The vote can close once the held boundary is out of sight. With both options pre-built,
the binding limit is no longer the spawn distance but keeping the held end of the
corridor hidden: the widest run fog (Wasteland, 420) plus a chunk plus 1.5 s at the top
speed while the chosen chunks are placed and stream, giving **638 studs** (was 1024).

| | Old (1024) | New (638) |
| --- | --- | --- |
| at 24 studs/s | 42.7 s | 26.6 s |
| at 60 studs/s | 17.1 s | 10.6 s |

## Studio checks (owner)

1. Lobby: the map row reads Random, City, Wasteland, Forest, Farmland. A run started on
   each begins on that map; Random lands on an enabled one.
2. A full map: the Output prints `[MapPreload] options warm in ... s`. Note the seconds
   per option pair and set each map's `preloadSeconds` from them (the floor uses them).
3. At the fork: the sign names two neighbours. After the vote, read the Workspace
   attributes:
   - `ForkResolvedLead` (about 638);
   - `ForkPlacedAfter`: seconds until the boundary chunk was placed. It should be a frame
     or two, since the chunks were pre-built; anything near `SETTLE_SECONDS` (1.5) means
     raising it.

   From the lead runner, the corridor's end must never be visible.
4. The transition: run through it at normal speed and at `DevFreezeRun`.
   - The ground mixes with no seam line.
   - Edge props and flanks change gradually.
   - The light shifts across the five chunks with no jump at the boundary.
   - With beds uploaded, the ambience crossfades.
5. Yard strip: set `MapStripPair` to `all` (or `City>Forest`), and `MapStripShot` to a
   pair for its camera. Check each row: plain, five blends, plain.
6. Over two maps, ServerStorage `ChunkPool` grows by about `3 x sub-locations` per
   option, then shrinks when the option not taken is dropped and when maps fall two steps
   behind.

## Step 2 (next PR): physical fork

The field splits at the divider into two half-corridors, each blending toward its
option. The choice is made late by where the runners are, and the losing half is closed
with a funnel and despawned.
