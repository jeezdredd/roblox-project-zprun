# Run Economy

Kill credits paid mid-run into a per-run balance that is banked at the end, and the
perks layer with its Perk Lab room. Branch `cloud/run-economy` (2026-09-30); the design,
numbers and Studio checks are `docs/economy/run-economy-and-perks.md`. Items 1 and 2
(config half) of the Zombies layer in [[Roadmap]]; see [[Gameplay Systems]] for the
vendors and skills it sits beside.

## Files

| File | Role |
| --- | --- |
| `src/shared/config/RunEconomyConfig.luau` | Kill pay per zombie id (Walker 25, Runner 40, default 25), headshot +10, streak +5 per position after the first inside 4 s (cap +25), 10 studs per credit |
| `src/shared/util/RunEconomyMath.luau` | Pure: streak, kill pay, distance pay, distance owed after a bank, unpaid goal bonus, total, bank. `luau tests/economy/run.luau` |
| `src/server/systems/RunEconomy.luau` | The balance per participant (and the distance pay already banked) and the `RunCredits` attribute; `onKill`, `setDistance`, `snapshot`, `bank`, `endRun` |
| `src/shared/config/PerksConfig.luau` | Six perks, levels 1..3 with prices and effect values, slot prices (2: 1500, 3: 3500), `validateEquipped` |
| `src/server/systems/PerkService.luau` | Levels, slots and the equipped set in the profile (version 4); the Perk Lab catalog and purchases; attributes `PerkSlots`, `PerksEquipped` |
| `WeaponService`, `DistanceTracker`, `DeathService`, `MissionGoals`, `MissionService`, `ShopService`, `ProfileManager` | The hooks: kill pay, distance pay, banking on death and on leaving (`ProfileManager.onReleasing`, before the session ends), goal bonuses paid once (`claimBonus`), the vendor id `PerkLab`, the profile fields |
| `VendorsConfig`, `VendorRooms` | The sixth room at hub offset (-152, 0, 128) |
| `src/client/ui/ShopGui.luau`, `RunHud.luau`, `src/client/controllers/DeathController.luau` | The three perk row kinds, the perk badges, the credits split on the results screen |

## Rules

- Every pay is multiplied by the difficulty reward multiplier when earned and floored.
- The balance is one number (kill pay plus distance pay), shown as "+N CR THIS RUN".
- Distance pay is capped by the server's run clock (decision D5, sprint 1 T11): the distance credits never exceed elapsed seconds x `DISTANCE_PAY_SPEED` (24, the base run speed) / `STUDS_PER_CREDIT` x `DISTANCE_PAY_SLACK` (1.1) x the reward multiplier (`RunEconomyMath.distancePayCap`). A 36 studs/s run earns at most 1.1x the distance credits of a 24 studs/s run per minute; the distance past the cap still counts for leaderstats and goals, and kill, headshot, streak and goal pay stay uncapped. The distance itself is the server-validated one (`RunDistanceGuard`, T2).
- Banking: the results screen banks and zeroes the balance (a Continue earns afresh, and
  neither the distance already paid nor a goal bonus already paid is paid twice);
  leaving a run alive banks the rest through `addCredits` without counting a run, from
  the profile's releasing hook so it lands before the session ends. Dying never burns
  what was earned.
- The equipped set cannot change during a run: the equip toggle is refused outside
  `LoadoutWindow` (the hub and the cabin's ready check).
- Perks are the per-run layer over the persistent skills: levels and slots are bought once
  with Credits and kept; the equipped set is chosen before a run and cleared when it
  ends. Slot 1 is free. Never Robux.
- The four perks that stack on a skill read differently: Thick Skin (Toughness),
  Adrenaline (Endurance), Speedloader (Fast Hands), Pack Rat (Scavenger).
- Perks are read by `PerkEffects` (server, sprint 1 T3a/T3b), which mirrors `SkillEffects` and folds each skill and perk pair through `src/shared/util/PerkMath.luau`:

| Perk (effect) | Read by | Combined with | Cap |
| --- | --- | --- | --- |
| Thick Skin (`bonusHealth`) | `FlowService` max health | Toughness skill | max health 180 |
| Adrenaline (`sprintSpeed`) | `DistanceTracker` run speed | Endurance skill | `MAX_RUN_SPEED` 60; distance pay capped per minute (T11) |
| Speedloader (`reloadScale`) | `WeaponService` reload time, `ReloadScale` attribute | Fast Hands skill | multiplier never below 0.6 |
| Field Medic (`healPerKill`) | `WeaponService` on a confirmed kill | none | up to max health, never revives |
| Pack Rat (`ammoScale`) | `AmmoCrates` crate rounds | Scavenger skill | none (1.75 x 1.5 at most) |
| Steady Aim (`spreadScale`) | `WeaponService` server spread, `SpreadScale` attribute for the client prediction | none | never below 0.4, never widens |

Equipped perks still clear at run end (`PerkService.onRunEnd`).

## Trade-offs (owner's calls made here)

- Perk levels are persistent purchases, the equip choice is per run: the money loop
  (kill pay -> Perk Lab) needs something to keep, and the per-run choice is what makes a
  perk a perk rather than a fifth skill.
- The pistol-sized streak (4 s window, +25 cap) rewards pace without letting a horde wall
  print credits.
- The Perk Lab sits on the west wall at z 128 rather than mirroring the Bubblegum Stand
  at z -132, which would block the gate on the south wall.

## Implementation notes

### Perk catalogs (`PerkService`, `ShopService`)

- Perk Lab rows come in order: one PerkSlot row first, then per perk a Perk row (the
  level purchase) and, once it has a level, a PerkEquip toggle row at price 0.
- The Cabin catalog (the helicopter's loadout panel, served only while the player is in
  the cabin) lists the weapon Loadout toggle rows, then the PerkEquip rows, all at price
  0: nothing to buy there.
- Every catalog read and every equip toggle first sanitizes the profile: if the equipped
  set fails `validateEquipped` (a duplicate, an unknown perk, a perk at level 0, or more
  perks than slots), the whole set is cleared. This covers corrupted and older profiles.
