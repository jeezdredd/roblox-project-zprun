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
- Banking: the results screen banks and zeroes the balance (a Continue earns afresh, and
  neither the distance already paid nor a goal bonus already paid is paid twice);
  leaving a run alive banks the rest through `addCredits` without counting a run, from
  the profile's releasing hook so it lands before the session ends. Dying never burns
  what was earned.
- The equipped set cannot change during a run.
- Perks are the per-run layer over the persistent skills: levels and slots are bought once
  with Credits and kept; the equipped set is chosen before a run and cleared when it
  ends. Slot 1 is free. Never Robux.
- The four perks that stack on a skill read differently: Thick Skin (Toughness),
  Adrenaline (Endurance), Speedloader (Fast Hands), Pack Rat (Scavenger).
- No perk effect is read by gameplay yet; the effect keys name the system that will.

## Trade-offs (owner's calls made here)

- Perk levels are persistent purchases, the equip choice is per run: the money loop
  (kill pay -> Perk Lab) needs something to keep, and the per-run choice is what makes a
  perk a perk rather than a fifth skill.
- The pistol-sized streak (4 s window, +25 cap) rewards pace without letting a horde wall
  print credits.
- The Perk Lab sits on the west wall at z 128 rather than mirroring the Bubblegum Stand
  at z -132, which would block the gate on the south wall.
