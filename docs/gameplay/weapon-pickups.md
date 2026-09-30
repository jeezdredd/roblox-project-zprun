# Weapon pickups

Item 3 of the Zombies layer (`wiki/project-zprun/Roadmap.md`): no wall-buy. Weapons lie in
the world as staged scenes the world generator places along the corridor, read through
the fog by a pooled outline, and are taken by holding a prompt. The mystery box survives
as a crashed supply drop under red smoke, opened for run credits. Reference is Call of Duty:
Zombies as a risk economy: the gun you want is a detour and a spend, never a menu.

## 1. The scenes

`src/shared/config/PickupScenesConfig.luau`, data only (no engine types, so the planner
and its tests read it under the standalone Luau CLI): colours are `{r, g, b}`, sizes
`{x, y, z}`, materials names. Every scene is built from primitives and the props already in
`WorldMeshConfig`; no asset was added and no id invented.

| Scene id | Weapon | Biomes | Built from |
| --- | --- | --- | --- |
| `DeadSoldier` | Rifle (R4 Carbine) | any | a prone body in olive (torso, helmet, limbs, pack), a blood stain, the carbine beside the hand |
| `FencePost` | Shotgun (S870) | Farmstead, Cornfield, Forest | two posts and two rails, a crate, the shotgun leaning on the post |
| `PoliceCar` | Pistol (M9) | City, Wasteland | the `car_police` mesh (primitive cruiser with a light bar when not loaded), a cone, the pistol on the hood |
| `Checkpoint` | SMG (K10) | City, Wasteland, Farmstead | the `sandbags` mesh (stacked boxes when not loaded), a barrel, a stop sign, the SMG on the bags |
| `Sawmill` | Chainsaw | Forest, Farmstead | **`enabled = false`**: a config entry only, no melee system exists; the planner never picks it |

The weapon props (`PickupScenesConfig.weaponProps`) are silhouettes per weapon id in the
gun's own frame (-z along the barrel); the pickup removes that sub-model and leaves the
scene standing.

## 2. Placement

`src/shared/world/PickupPlanner.luau`, pure. `plan(config, biome, chunkIndex, rng,
{halfLength, halfWidth})` returns at most one scene and one supply drop for the chunk,
each with `CANDIDATES` (3) spots in order:

- nothing in the first `START_CLEARANCE_CHUNKS` (2) chunks; the squad starts with its
  loadout;
- a scene with the biome's chance from `density` (City 0.45, Wasteland 0.4, Farmstead
  0.35, Forest 0.3, Cornfield 0.25), chosen by weight among the scenes allowed there, on
  the road shoulder `SHOULDER_INSET` (4..12 studs) inside the playable edge, clear of the
  chunk ends by `END_CLEARANCE` (14), facing the road with `YAW_JITTER` (20 degrees);
- a supply drop with `supplyDrop.chance` (City and Wasteland 0.12, Farmstead 0.1, Forest
  and Cornfield 0.08) in the middle half of the lane; every drop candidate keeps
  `SCENE_DROP_GAP` (24) studs along the road from every scene candidate, since the
  server may use any of them, and a candidate that finds no clear lane in six tries is
  left out (a drop with none is dropped, never forced).

The server (`src/server/systems/WeaponPickups.luau`, called by `ChunkSpawner` once the
chunk stands) seeds `Random.new(runSeed + 3 + chunkIndex * 7919)` per chunk for the
plan, and separate Randoms off the same base for the drop's weapon roll (+1) and the
mesh picks (+2), so the plan's stream never shifts with what happened to load.

What is deterministic from the run seed and the chunk index alone: whether the chunk
gets a scene and a drop, which scene, the three candidate spots of each, the drop's
weapon. What is not: which of the three candidates is used. The server takes the first
one that is free of the chunk's props, and a chunk's props depend on its build, which
for a pooled chunk is an earlier one (pooling reuses chunk models in spawn order). A
run still shows one layout to everyone, because the server builds it once and the
clients only see the result; two runs of the same seed agree on the plan and usually
on the spots, not always.

The spot check, all in chunk-local x/z: the chunk's `ChunkOccupancy` footprints,
remembered under the chunk model at its build (`ChunkOccupancy.remember`; the query
below cannot see the non-queryable dressing such as corn walls, dry grass and
undergrowth, the footprints can), the pickups already standing (their small parts are
not queryable either) by radius, the chunk's ammo crates (`AmmoCrates.positionsForChunk`),
and last `Workspace:GetPartBoundsInBox` above the floor with the chunk model and
`Workspace.Pickups` as the includes. A chunk whose three spots are all blocked gets no
scene. Scenes live in `Workspace.Pickups`, tagged `WeaponPickup`, with the attributes
`SceneId`, `Kind` (`Scene` or `Drop`), `WeaponId` and `Taken`, and go with their chunk
(`clearChunk` from `ChunkSpawner.despawnChunk`).

## 3. Taking one

The scene's invisible anchor at the weapon carries a `ProximityPrompt` (`PickupPrompt`,
`HoldDuration` 0.3, `MaxActivationDistance` 10, no line of sight). `Triggered` arrives on
the server, which checks: the run is active and the player a participant with
`FlowPhase` Mission, the character alive, the root within `PICKUP_DISTANCE` (16, more
than the prompt shows for a running player's latency), the scene not taken. Then
`WeaponService.pickUp(player, weaponId)`:

- the found weapon takes the slot of the weapon in hand in a **run loadout**, a copy of
  the profile's loadout kept in `WeaponService` for the run; the `LoadoutSlot1/2`
  attributes and the 1 and 2 keys read it, `ownsWeapon` accepts it, and the equip goes
  through the same `onEquip` a loadout equip does (draw time, ammo snapshots);
- a found gun is full: its ammo snapshot is dropped, so it equips at `magSize` and a full
  reserve; finding a weapon already carried refills that one instead;
- the profile's `Loadout` is never written. `MissionService.removeFromMission` calls
  `WeaponService.clearRunLoadout`, which drops the run loadout and re-applies the
  profile's, so the player returns to the hub with their own guns.

The client gets `WeaponPickup` (`"Weapon"`, weaponId, position) for the toast
("PICKED UP S870 SHOTGUN"), the reward tick and the pickup burst.

## 4. The supply drop

The reworked mystery box: the `supply_crate` mesh (a primitive crate when not loaded) on
its side in a scrape of earth, the parachute silk collapsed beside it, cords, a canister
on top pouring **red smoke** (`RedSmoke` emitter and a red light, the same shape as the
ammo crate's pillar so it reads at the same distance). Green smoke stays the ammo
crate's (`AmmoCrates`), so the two never read alike.

The prompt reads "Crack open · 250 CR". The server checks the run balance
(`RunEconomy.snapshot`), rolls the weapon with `PickupPlanner.rollDrop` from the weighted
table (Shotgun 4, SMG 4, Rifle 3, Pistol 1; the roll is seeded per drop, and a roll of
the weapon already in hand is rerolled once so the credits buy a gun and not a refill),
spends the
credits through `RunEconomy.spend` (kill pay first, then distance pay, and the distance
spent counts as banked so the same studs never pay for it again;
`RunEconomyMath.spend`, tested), hands the weapon over through `pickUp` and shuts the
smoke off. Too poor: `"Refused"` with "Need 250 CR" and nothing changes.

## 5. Highlights

`src/client/systems/WeaponPickupClient.luau` (started from `WeaponController.init`). Every
scene reads through the fog by a `Highlight` (outline only, `Occluded`, warm for a scene,
red for a drop). Roblox renders at most 31 Highlight instances, so the client keeps a
pool of at most `HIGHLIGHT_BUDGET` (24) and every `HIGHLIGHT_REFRESH` (0.25 s) hands them
to the nearest untaken scenes by `src/shared/util/HighlightBudget.luau` (pure): a scene
that holds one keeps it unless a scene without one is closer by
`HIGHLIGHT_SWAP_MARGIN` (6 studs), so two scenes at the same distance never trade the
outline; scenes passed, taken or culled hand theirs back to the pool. No Highlight is
ever created beyond the budget.

## 6. Tests

`luau tests/pickups/run.luau`: the config (every enabled scene names a real weapon with
a prop, the chainsaw is disabled, the drop table is whole, the budget is under 31), the
weighted pick (bands, zero and missing weights, the drop proportions over a sweep), the
scene choice per biome, the seeded placement (same seed same plan, other seed differs,
nothing in the first chunks, shoulder and lane bounds, facing, the rates against the
config, the drop's gap from the scene) and the highlight pool (budget, nearest first,
release on moving on, hysteresis, zero budget, vanished scenes, duplicates).
`tests/economy` gains the spend.

## 7. Studio check list

- **Scenes appear.** Start a run on Medium: from the third chunk on, scenes stand on the
  road shoulders about every other chunk in the city (a fallen soldier, a police car
  with a pistol on the hood, a checkpoint with an SMG); in the fields a shotgun leans on
  a fence post. None stands inside a car, a barrier or a building; none is in the lane.
- **Same seed, same scenes.** Two clients in one run see the same scenes in the same
  places; the same seed twice (DevBench) gives the same layout.
- **The outline.** Every scene ahead carries a warm outline visible through the fog
  before its shape is; a supply drop a red one. With more than 24 scenes and drops
  spawned ahead (lower the fog, raise `density` to 1 in Studio) only the nearest 24
  carry it and the far ones gain it as you approach; `Workspace.CurrentCamera` never
  holds more than 24 `PickupHighlight` instances.
- **Hold to take.** Walk to a scene: the prompt reads "R4 Carbine · Take"; hold E for
  0.3 s: the carbine leaves the scene, the toast reads "PICKED UP R4 CARBINE", the
  weapon in hand is the carbine with a full magazine and reserve, and the slot it
  replaced (the 1 or 2 key) now holds it. A second player at the same scene after that
  gets no prompt.
- **Server checks.** The prompt is the only trigger; there is no client remote to fire.
  Die beside a scene and hold the prompt during the death cinematic, or hold it as a
  player who left the squad (`SquadLeave`) while standing in the run: nothing happens;
  a scene taken by a teammate shows no prompt to the next player.
- **Back in the hub** the 1 and 2 keys hold the profile's loadout again and the Gunsmith
  shows it unchanged.
- **Supply drop.** Find the red smoke, rising straight up from the canister; with under
  250 run credits the prompt refuses ("NEED 250 CR"); with more, "+N CR THIS RUN" drops
  by 250, the toast names a weapon other than the one in hand, it is in hand, the smoke
  stops.
- **Spots.** In the Cornfield and the Forest no scene stands inside a corn wall, dry
  grass or undergrowth; a drop never stands on a scene or an ammo crate.
- **Ammo crates unchanged:** green smoke, walk-over pickup, "+N AMMO".
- **Budget.** The chunk counter line (`BudgetLine`) does not change; the scenes are not
  in the chunk model.
