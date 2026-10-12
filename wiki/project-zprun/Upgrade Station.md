# Upgrade Station

A Pack-a-Punch-style bench mid-run that upgrades the carried weapon for run credits.
Branch `cloud/upgrade-station` (2026-09-30); design, numbers and Studio checks in
`docs/gameplay/upgrade-station.md`. Item 5 of the Zombies layer in [[Roadmap]]; the credits
are [[Run Economy]]'s, the highlight pool and the prompt guard are [[Weapon Pickups]]'.

## Files

| File | Role |
| --- | --- |
| `src/shared/config/UpgradeStationConfig.luau` | Spacing (640 studs), clearance (512), the station biomes (City, Wasteland, Farmstead), the spot rules, the prompt numbers, the parts, the announcer keys. Data only |
| `src/shared/world/UpgradeStationMath.luau` | Pure: `priceFor`, `damageScale`, `quote` (buy, short, max level), `chunkHasStation`, `plan`. `luau tests/upgrade/run.luau` |
| `src/server/systems/UpgradeStations.luau` | Builds the station per chunk from its own seeded Random, the `UpgradePrompt`, the validation through `RunPromptGuard`, the spend through `RunEconomy.spend`, the level through `WeaponService.setRunLevel` |
| `src/server/systems/RunPromptGuard.luau` | The server check shared with the pickups: active run, participant, Mission phase, alive, within reach |
| `src/server/systems/SceneParts.luau` | The part builder from data, shared with the pickup scenes |
| `WeaponService.levelOf`, `setRunLevel`, `carriedWeapon` | The run's levels per weapon id over the profile's, read by `onFire`, the `WeaponLevel` attribute, dropped by `clearRunLoadout` |
| `WeaponPickupClient` | The station's outline colour through the pool, the quote in the prompt's action text, the toast, the announcer, the bursts |
| `WeaponController` | The level after the weapon name under the ammo readout |
| `assets/manifest.json` | `audio/upgrade/announcer_upgrade_01`, `_02`, `announcer_max`: `needed`, candidate sources in the note |

## Rules

- One station per 640 studs in the station biomes, deterministic from the run seed and
  the chunk index; a chunk of another biome at the mark gets nothing. It goes to the chunk
  whose span crosses a multiple of 640, none before 512.
- Station stream seeds are `seed + chunkIndex * 7907`, deliberately off the pickups' step
  of 7919, so no station Random ever equals a pickup plan's or a drop roll's for any chunk.
  Keep the steps distinct when adding another seeded per-chunk system.
- Placement: on the shoulder 6 to 11 studs inside the playable edge, 16 from the chunk
  ends, yaw jitter 12 degrees, 3 candidate spots. `RADIUS` 9 must cover every part (the
  generator reaches about 8.4 studs from the origin); `tests/upgrade` computes the extent
  from the parts, so a part added past it fails the test.
- `ChunkSpawner` calls `UpgradeStations.spawnForChunk` once the chunk stands at its pivot
  and before `WeaponPickups.spawnForChunk`, so the chunk's pickups keep clear of the
  station. The spot check is the pickups' own: the chunk's remembered footprints, the ammo
  crates by a 3-stud radius (they spawn first and are not queryable), then an overlap
  query. The station lives in `Workspace.Pickups` and reports its footprint for the chunk,
  since the lamp, mat and vise are not queryable.
- The price is the Gunsmith's ladder (400, 750, 1100, 1450); paid in run credits only,
  never the profile balance; refused at L5 and when short, with the reason.
- The level is the run's: `WeaponService` holds it beside the run loadout, the profile's
  `WeaponsOwned` is never written, the hub shows the profile level again. A weapon's run
  level is the one bought at a station this run, else the profile's, and 1 for a weapon
  the profile does not own (a found one).
- `WeaponService` republishes the `WeaponLevel` attribute after the profile loads (the
  default Pistol may already be current, so no equip runs) and after a Gunsmith upgrade.
- The announcer is a manifest slot with `status: needed`; no generated speech, no
  invented id; the code plays it only when the id is non-zero.

## Trade-offs (owner's calls made here)

- The station shares the pickups' tag, folder and highlight pool rather than its own:
  one pool keeps the Highlight count under Roblox's limit across both, and the bench lamp
  is the station's own light when the pool is spent.
- The quote is written into the prompt's action text on the client, per player, since
  a ProximityPrompt's text replicates to everyone and the price is the player's. It comes
  from `UpgradeStationMath.quote` over the replicated `WeaponLevel` and `RunCredits`
  attributes, so it is only right while the server keeps both current. It reads
  `Upgrade to L<n> · <price> CR`, `L<n> · <price> CR (short)` when credits run short, and
  `At the top` at the maximum level.
- The run level is per weapon id, not per gun: a found weapon of the same id keeps the
  level bought, which reads as "the run's carbine is L2" rather than a lost purchase.
