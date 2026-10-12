# Weapon Pickups

Diegetic weapon pickups along the corridor and the crashed supply drop. Branch
`cloud/weapon-pickups` (2026-09-30); design, numbers and Studio checks in
`docs/gameplay/weapon-pickups.md`. Item 3 of the Zombies layer in [[Roadmap]]; the
credits it spends are [[Run Economy]]'s, the world it stands in is [[Environment]]'s.

## Files

| File | Role |
| --- | --- |
| `src/shared/config/PickupScenesConfig.luau` | The scenes (dead soldier, fence post, police car, checkpoint; the chainsaw disabled), the weapon props, per-biome density, the supply drop table, the prompt and highlight numbers. Data only |
| `src/shared/world/PickupPlanner.luau` | Pure: the weighted pick, the scene choice per biome, the plan per chunk with candidate spots. `luau tests/pickups/run.luau` |
| `src/shared/util/HighlightBudget.luau` | Pure: which scenes hold a Highlight this pass, nearest first with hysteresis |
| `src/server/systems/WeaponPickups.luau` | Builds the scenes per chunk from a Random seeded with the run seed and the chunk index, checks the spot against the chunk's props, the `PickupPrompt`, the server validation, the supply drop roll and spend |
| `src/client/systems/WeaponPickupClient.luau` | The Highlight pool (at most 24), the toasts |
| `WeaponService.pickUp`, `clearRunLoadout` | The run loadout a found weapon writes into, equipped through the loadout's own `onEquip`; gone with the run |
| `RunEconomy.spend`, `RunEconomyMath.spend` | Run credits for the drop: kill pay first, the distance spent counted as banked |
| `ChunkSpawner`, `ChunkFactory`, `ChunkOccupancy`, `AmmoCrates` | `configure(seed + 3)`, `spawnForChunk`, `clearChunk`, `init` hooks; the footprints remembered per chunk model; the crate positions per chunk |
| `WorldMeshConfig` | `supply_crate` entry and group (the id was already in the manifest) |

## Rules

- The plan (scene, drop, their candidate spots, the drop's weapon) is deterministic
  from the run seed and the chunk index, each from its own Random; the candidate used
  depends on the chunk's props, which pooling makes spawn-order dependent. One run shows
  one layout to everyone. Nothing in the first two chunks. Chunk seeds are spaced by
  `CHUNK_SEED_STEP` 7919 so neighbouring chunks never share a stream, with fixed offsets
  for the drop roll and the mesh picks, so the plan's stream never shifts with what
  happened to load.
- A chunk gets at most one scene and one supply drop. Scenes stand on the road shoulder
  4 to 12 studs inside the playable edge, at least 14 studs from the chunk ends, with up
  to 20 degrees of yaw jitter; the planner offers 3 candidate spots and the server takes
  the first free of the chunk's props. The drop lands mid-lane, within half the playable
  half width either side, and at least `SCENE_DROP_GAP` (24 studs) along the road from
  every scene candidate, not just the first, since the server may use any of them; if no
  try lands clear the drop is skipped.
- Scene weights: a zero or missing weight never wins, and the weighted pick returns nil
  when nothing can.
- Hold 0.3 s. The prompt shows at 10 studs but the server accepts a trigger from 16, to
  absorb a running player's latency; [[Upgrade Station]] uses the same 10/16 split with a
  0.6 s hold. The server check behind every mid-run ProximityPrompt (pickups and the
  station) is `RunPromptGuard.canUse`: active run, participant, `FlowPhase` Mission,
  alive, root within reach of the prompt's anchor. The pickup also checks that the scene
  is untaken.
- The found weapon replaces the slot in hand for the run only; the profile's loadout is
  never written. Picking up a weapon already carried refills that one instead of taking a
  slot, and a found gun always arrives full: the ammo it had the last time it was carried
  is forgotten. If the run ends with a found weapon in hand, the profile's primary is
  drawn.
- Highlights: never more than 24 instances (Roblox renders 31); the nearest scenes hold
  them, a held one keeps its slot inside a 6-stud margin.
- Red smoke is the supply drop's, green stays the ammo crate's.
- The chainsaw is a config entry with `enabled = false` until a melee system exists.

## Trade-offs (owner's calls made here)

- The scenes are placed after the chunk is built, in their own folder, rather than
  inside `ChunkFactory`: chunks are pooled and a taken scene must not come back with a
  pooled chunk. The chunk's `ChunkOccupancy` footprints are remembered under its model
  (`ChunkOccupancy.remember`) so the spot check sees the non-queryable dressing too;
  the standing pickups and the ammo crates are checked by radius, the queryable rest by
  an overlap query. Crate and station parts are not queryable, so `AmmoCrates.positionsForChunk`
  and `UpgradeStations.footprintsForChunk` exist for that radius check (crates count with
  a 3-stud radius). `WeaponPickups.init` returns the shared `Pickups` folder so the pickup
  and station spot checks both see both kinds.
- The drop's weapon is rolled from a seeded Random per drop, so the roll cannot be
  fished by re-triggering; the weapon in hand is rerolled once, and the credits are spent
  only after the roll gave a real weapon.

## Implementation notes

### Spot check

- The overlap query sweeps a box from 1 to 6 studs above the floor, so stains and
  markings below it never block a spot.
- `ChunkOccupancy.remember` keeps the claims in a table weak-keyed by chunk model: a
  destroyed chunk drops its list, a pooled one keeps it since its props stay put.
  `isFreeFor` returns true when nothing was remembered for that model (a chunk built
  before remembering existed).

### Scene configs

- Scene parts are authored in the scene's own frame (x right, y up, -z toward the road),
  weapon props in the gun's frame (-z along the barrel, y up). Rotations are in degrees; a
  cylinder's axis runs along x.
- Colours and sizes are plain number tables so the pure `PickupPlanner` and
  `UpgradeStationMath` (`src/shared/world`) and their tests read the configs under the
  standalone Luau CLI.
- A mesh part is sized by `length` (footprint along z, through `placeByLength`) or
  `height`; with neither it keeps its natural size (the station's oil barrels).
- The upgrade station's parts use the same PartSpec shape and are built by the same
  `SceneParts` code.
