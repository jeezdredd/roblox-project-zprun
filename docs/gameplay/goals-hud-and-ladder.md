# Goals HUD and the visible weapon ladder

Two small surfaces over systems that already existed: the mission goals, tracked and paid
since the ITD run layer but never shown, now sit on the run HUD with live progress; and
the Gunsmith's weapon rows show the level ladder they sell (the damage now, the next
level's price and gain). No asset was added.

## 1. Goals on the run HUD

### What existed

`MissionGoals` (server) keeps `{ Distance, Kills, CleanDistance }` per participant,
`completed` walks `MissionGoalsConfig.order` and `DeathService` pays the bonus of every
completed goal once per run. Only two call sites reported: kills from
`WeaponService.handleHit`, and the distance once, at death, from
`DeathService.computeRewards`. Nothing reported `CleanDistance`, so `NoDamage500`
(Untouched) was unreachable, and nothing showed a goal during the run.

### What changes

| Piece | Role |
| --- | --- |
| `src/shared/util/GoalsHudMath.luau` | Pure: `encode` (progress to one string, config order, floored), `decode`, `rows` (name, "320 / 1500", done). `luau tests/goals/run.luau` |
| `MissionGoals` | Publishes the encoded progress as the `GoalsProgress` player attribute: on `beginRun`, then at most every 0.25 s while a report changed something, nil on `endRun` |
| `DistanceTracker.step` | Reports `Distance` live (the best distance, the same number the leaderstat shows) and `CleanDistance`: a drop in the humanoid's health since the last frame marks a hit at the current best distance, the clean distance is the best minus that mark |
| `RunHud` | A "GOALS" block top left (x 16, y 116, under the FPS counter), one line per goal in config order: "LONG HAUL  320 / 1500", done rows in the accent colour with "DONE"; hidden with the rest of the run HUD in the hub |

The attribute string is `Distance1500=320;Kills25=4;NoDamage500=120` (goal ids, the
metric's progress floored), so it changes once per whole unit at most and the HUD decodes
it without a remote. `DeathService`'s report at death stays, harmless (a max).

`CleanDistance` closes the loose end the Roadmap names: the hit hook is the health drop
`DistanceTracker` already sees every frame, no new connection per character. A Continue
counts as a hit (the death was one), so the clean distance starts again from the revive.

## 2. The ladder in the Gunsmith

`src/shared/util/WeaponLadderText.luau` (pure, tested against `WeaponsConfig.upgradePrice`
and `damageAt` level by level) writes the weapon row's description:

| Row | Text |
| --- | --- |
| not owned (the dealer) | `Rifle · 30 dmg · 600 rpm · mag 30 · L1 of 5` |
| owned, below max | `Rifle · 32.4 dmg · next L3: 750 CR, +2.4 dmg` (the name label carries "L2/5", `ShopGui` still appends "XP 12/160") |
| at max | `Rifle · 39.6 dmg · top of the ladder` |

Numbers are whole when whole, else one decimal. `ShopService.weaponEntries` calls it for
both the dealer and the Gunsmith; the row layout, the action button and the purchase
flow are unchanged. The level, the price on the button and the XP gate were already
there; what was missing was the damage the level buys and the next step's price on the
row itself.

## 3. Studio check list

- **Goals block.** Start a run: top left under the FPS counter reads "GOALS" with three
  lines at 0: "LONG HAUL  0 / 1500", "CLEANUP  0 / 25", "UNTOUCHED  0 / 500". It does
  not overlap the FPS counter or anything else at top left; in the hub it is gone with
  the run HUD.
- **Live progress.** The Long Haul line follows the metre counter (whole studs, a few
  times a second, never behind by more than a quarter second); each kill adds one to
  Cleanup at once.
- **Untouched.** Run without a hit: the line climbs with the distance. Take a hit: it
  drops to 0 and climbs again from there. Reach 500 clean studs: the line reads "500 /
  500  DONE" in the accent colour; at death the results credits include its 200.
- **Done rows** stay done for the rest of the run, and a Continue keeps Long Haul and
  Cleanup where they were (the distance and the kills stand), while Untouched restarts.
- **Gunsmith rows.** With a L2 rifle: the name reads "R4 CARBINE   L2/5" and the row
  "Rifle · 32.4 dmg · next L3: 750 CR, +2.4 dmg · XP n/160"; the button still reads the
  price and refuses without the XP. At L5: "top of the ladder", no button price. The
  text fits the row without truncation at the panel's default width.
- **Dealer rows** for an unowned weapon read the class, damage, rpm, magazine and "L1 of 5".
