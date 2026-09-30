# Upgrade station

Item 5 of the Zombies layer (`wiki/project-zprun/Roadmap.md`): a Pack-a-Punch-style
station reachable mid-run that upgrades the carried weapon for run credits, with an
announcer voice on use. The level ladder it drives already exists (`WeaponsConfig.MAX_LEVEL`
= 5, `upgradePrice`, `damageAt`); the work is the station, the in-run spend path and the
audio slot. Reference is Call of Duty: Zombies as a risk economy: the station is a detour
and a spend, and what it buys is gone with the run.

## 1. Placement

`src/shared/config/UpgradeStationConfig.luau` (data only) and
`src/shared/world/UpgradeStationMath.luau` (pure, `luau tests/upgrade/run.luau`).

- One station per `SPACING_STUDS` (640) of road: the chunk whose span crosses a multiple
  of it gets one (chunks 4, 9, 14, ... at the default 128-stud chunks and 64-stud start
  platform), none before `START_CLEARANCE_STUDS` (512), and only in the station
  `biomes` (City, Wasteland, Farmstead): a Forest or Cornfield chunk that crosses the
  mark gets nothing and the next mark is 640 studs on. `chunkHasStation(config, biome,
  chunkStart, length)` is the whole rule.
- The spot: `plan` gives `CANDIDATES` (3) spots on the road shoulder `SHOULDER_INSET`
  (6..11 studs) inside the playable edge, clear of the chunk ends by `END_CLEARANCE`
  (16), facing the road with `YAW_JITTER` (12 degrees).
- `src/server/systems/UpgradeStations.luau` is called by `ChunkSpawner` once the chunk
  stands, before the chunk's pickups, with its own `Random.new(runSeed + 4 + chunkIndex
  * 7919)` (mesh picks on a second Random off the same base), so which chunks get a
  station and their candidate spots depend on the run seed and the chunk index alone.
  It takes the first candidate free of the chunk's remembered footprints
  (`ChunkOccupancy.isFreeFor`) and of anything queryable of the chunk or of
  `Workspace.Pickups` in a box above the floor; the pickups placed after it see it in
  that folder and keep clear. The station lives in `Workspace.Pickups` too, tagged
  `WeaponPickup` with `Kind` `Station`, and goes with its chunk.

## 2. The station

Built by `SceneParts` (the part builder shared with the pickup scenes) from
`UpgradeStationConfig.parts`: a steel bench on two legs with a vise, a tool board
behind it, a generator with an exhaust and an amber warning light, a lamp stand whose
shade carries a `SpotLight` down on the bench, two `oil_barrel` meshes (cylinders when
not loaded), a mat. No asset was added. The prompt anchor sits on the bench.

The outline comes through the pickups' pooled `Highlight` (`WeaponPickupClient`,
`HighlightBudget`, at most 24 live) in the station's own colour
(`HIGHLIGHT_OUTLINE`, a cold blue against the scenes' warm and the drop's red); the bench
lamp is the station's own light for when the pool is spent by scenes nearer.

## 3. Using it

- `UpgradePrompt` on the anchor: `HoldDuration` 0.6, `MaxActivationDistance` 10, no
  line of sight. The client writes this player's quote into the prompt's action text
  when it shows and whenever `WeaponLevel`, `RunCredits` or `WeaponId` change:
  "Upgrade to L3 · 750 CR", "L3 · 750 CR (short)" or "At the top".
- `Triggered` on the server goes through `RunPromptGuard.canUse` (the check shared with
  the pickups: run active, participant, `FlowPhase` Mission, alive, root within
  `USE_DISTANCE` 16). Then the carried weapon (`WeaponService.carriedWeapon`), its level
  for this run (`WeaponService.levelOf`: the level bought this run, else the profile's,
  else 1 for a found weapon), the quote (`UpgradeStationMath.quote` against
  `RunEconomy.snapshot`), the spend (`RunEconomy.spend`, run credits only, the profile
  balance is never touched), `WeaponService.setRunLevel`.
- Price from the ladder: `upgradePrice(level)` = 400, 750, 1100, 1450 for L1 to L5, the
  same the Gunsmith charges; at `MAX_LEVEL` the station refuses with "Already at the
  top, L5", short of credits with "Need N CR". The quote and both refusals are tested.
- The level lives in `WeaponService`'s run state beside the run loadout the pickups
  write into, per weapon id, read by `onFire` for damage (`damageAt`), and published as
  the `WeaponLevel` attribute. `clearRunLoadout` (from `MissionService.removeFromMission`)
  drops it with the run; the profile's `WeaponsOwned` is never written. A weapon found
  after the upgrade with the same id keeps the level (it is the run's level for that
  weapon, not the gun's).

## 4. Visible result

- HUD: the weapon name under the ammo readout reads "R4 CARBINE  L3" in the accent
  colour once the level is over 1 (`WeaponController.refreshHud`, on `WeaponLevel`).
- The toast "R4 CARBINE UPGRADED TO L3", the reward tick and two pickup bursts at the
  bench (`WeaponVfx.pickupBurst`, an existing module); a refusal toasts in red.
- Announcer: `AssetIds.audio.upgrade.announcer_upgrade_01` / `_02` (one at random on an
  upgrade) and `announcer_max` (on the max-level refusal), played 2D through the audio
  engine (`SfxPlayer` when it is off) only when the id is non-zero. The three slots are
  `needed` in `assets/manifest.json` with candidate sources in the note (Kenney Voiceover
  Pack, CC0; freesound CC0; a line recorded by the owner) and rows in `assets/NEEDED.md`.
  No generated speech, no invented id: the station is silent until real files land.

## 5. Tests

`luau tests/upgrade/run.luau`: the price per level against `WeaponsConfig.upgradePrice`,
the damage scale against `damageAt`, the quote (buy, exactly enough, short, max level,
above max, level zero, fractional), the station chunks (one per spacing, the clearance,
the biomes, a mark on a chunk edge), the seeded placement (same seed same spots, another
seed differs, no spots without a station, shoulder and end bounds, facing).

## 6. Studio check list

- **Stations appear** on Medium in the city: the first at chunk 4 (about 640 studs in),
  then every 640 studs while the route is City, Wasteland or Farmstead; none in the
  Forest or the Cornfield; on the shoulder, never inside a car, a wall, a corn wall or
  another scene; the bench lamp lights the bench at night, the warning light glows amber.
- **Same seed, same stations** for two clients and for the same seed twice.
- **The outline** is cold blue through the fog; with more than 24 scenes and stations
  ahead the nearest 24 carry it.
- **The quote.** Walk up with a L1 weapon and 0 run credits: "Upgrade station · L2 · 400
  CR (short)"; earn 400: the text changes to "Upgrade to L2 · 400 CR" without moving.
- **Hold to upgrade** (0.6 s): "+N CR THIS RUN" drops by 400, the toast reads "R4
  CARBINE UPGRADED TO L2", the name under the ammo readout reads "R4 CARBINE  L2" in the
  accent colour, two bursts at the bench; a Walker now takes floor(damage x 1.08) per
  hit. Hold again: 750, then 1100, 1450; at L5 the prompt reads "At the top" and a hold
  toasts "ALREADY AT THE TOP, L5".
- **Run only.** Die and return to the hub: the Gunsmith shows the weapon at its profile
  level, the HUD name has no level suffix; a new run starts at the profile level.
- **Other weapon.** Swap to the sidearm at the station: the quote is the sidearm's.
- **Found weapon.** Pick up a found carbine after upgrading the carbine: it keeps L2.
- **Announcer silent** (ids 0) until the slots are filled; nothing errors.
