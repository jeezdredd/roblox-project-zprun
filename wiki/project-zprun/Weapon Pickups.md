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
| `ChunkSpawner` | `configure(seed + 3)`, `spawnForChunk`, `clearChunk`, `init` hooks |
| `WorldMeshConfig` | `supply_crate` entry and group (the id was already in the manifest) |

## Rules

- Placement is deterministic from the run seed and the chunk index; every player sees
  the same scenes. Nothing in the first two chunks.
- Hold 0.3 s; the server validates phase, participant, distance (16 studs) and that the
  scene is untaken. The found weapon replaces the slot in hand for the run only; the
  profile's loadout is never written.
- Highlights: never more than 24 instances (Roblox renders 31); the nearest scenes hold
  them, a held one keeps its slot inside a 6-stud margin.
- Red smoke is the supply drop's, green stays the ammo crate's.
- The chainsaw is a config entry with `enabled = false` until a melee system exists.

## Trade-offs (owner's calls made here)

- The scenes are placed after the chunk is built, in their own folder, and checked
  against the chunk's props with an overlap query, rather than inside `ChunkFactory`:
  chunks are pooled and a taken scene must not come back with a pooled chunk.
- The drop's weapon is rolled from a seeded Random per drop, so the roll cannot be
  fished by re-triggering, and it is spent only after the roll gave a real weapon.
