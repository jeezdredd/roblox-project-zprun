# Run economy and perks

Item 1 and the config half of item 2 of the Zombies layer (`wiki/project-zprun/Roadmap.md`):
kill credits paid the moment a zombie dies, into a per-run balance that the results screen
banks, and the perks that ride along on a run, bought and equipped at a sixth hangar room.
The reference is Call of Duty: Zombies as a risk economy: every kill pays, the money is
spent on the next run's edge, and dying costs you the run, not the money.

## 1. Run economy

### What exists today

`DistanceTracker.step` writes the player attribute `RunCredits` as `distance / 10 x
multiplier` and the HUD shows it as "+N CR THIS RUN"; `DeathService.computeRewards`
recomputes the same number on death, adds the mission goal bonus and pays it through
`ProfileManager.awardRun`. Kills award weapon XP and the `Kills` metric in
`WeaponService.handleHit` and nothing else. A player who leaves a run alive banks nothing.

### What changes

| Piece | Role |
| --- | --- |
| `src/shared/config/RunEconomyConfig.luau` | Kill pay per zombie id, the headshot bonus, the streak window, step and cap, the distance rate |
| `src/shared/util/RunEconomyMath.luau` | Pure: streak position, streak bonus, kill pay, distance pay, total, bank. `luau tests/economy/run.luau` |
| `src/server/systems/RunEconomy.luau` | The per-run balance per participant (`kills` and `distance` halves), the `RunCredits` attribute, `onKill`, `setDistance`, `snapshot`, `bank`, `endRun` |
| `WeaponService.handleHit` | On the killing shot: `RunEconomy.onKill(player, ZombieId attribute, headshot)` next to the XP and the goal report |
| `DistanceTracker.step` | `RunEconomy.setDistance(player, traveled)` instead of writing the attribute itself |
| `MissionService` | `beginRun` starts the balance; `removeFromMission` banks what is still unbanked through `ProfileManager.addCredits` and clears the run's perks |
| `DeathService.computeRewards` | Snapshots and banks the balance, adds the goal bonus, passes the kill and distance halves and the kill count to the results screen |
| `DeathController` | The credits line shows the split when the run had kills |

### The pay table

Every pay is multiplied by the difficulty reward multiplier (`RewardMultiplier`, difficulty
x modifiers) at the moment it is earned and floored, so the balance is always whole
credits and a harder run pays more per kill, not only per metre.

| Pay | Value | Note |
| --- | --- | --- |
| Walker kill | 25 | `RunEconomyConfig.killPay.Walker` |
| Runner kill | 40 | faster, more dangerous, worth more |
| Unknown zombie id | 25 | `KILL_PAY_DEFAULT`, so a new type pays before its row exists |
| Headshot | +10 flat | the killing shot hit `Head` |
| Streak | +5 per streak position after the first, cap +25 | a kill within 4 s of the last extends the streak; the sixth kill in a row and every one after adds the cap |
| Distance | 1 credit per 10 studs | the rate the run always paid, folded into the same balance |

At Medium (multiplier 1.6) a Walker headshot in a streak of three pays floor((25 + 10
+ 10) x 1.6) = 72. A run of 2000 studs with 40 mixed kills and a few streaks lands around
600 to 900 credits on Medium, against the 320 the distance alone paid before, which is
what the Perk Lab prices below are set against.

### Banking

- `RunEconomy.bank` takes the balance out and leaves the run at zero. `DeathService` calls
  it on the results screen, so a Continue starts earning afresh and the second death banks
  only the new earnings; the first share is already in the profile.
- `MissionService.removeFromMission` banks whatever is still unbanked (a player who leaves
  the run alive, the squad's run tearing down) through `ProfileManager.addCredits`, without
  counting a run.
- Dying without a Continue banks everything earned. Nothing burns.
- The HUD's "+N CR THIS RUN" is the one balance; the wallet in the corner stays the
  profile balance and is hidden during a run as before.

## 2. Perks

### The open question, settled

`SkillsConfig` holds four persistent skills (Toughness, Endurance, FastHands, Scavenger)
applied through `SkillEffects`; four of the six perks the Roadmap names sit on the same
stats. The proposal: **perks are the per-run layer over the persistent skills**. A skill
level is bought once and is always on; a perk's levels are bought once too, but a perk
only acts on a run it was equipped for, and the equipped set is cleared when the run
ends, so the choice is made before every run at the Perk Lab. The overlapping four carry
display names that do not read like the skills:

| Perk id | Display name | Skill it stacks on | Effect key |
| --- | --- | --- | --- |
| Toughness | Thick Skin | Toughness | `bonusHealth` 15 / 30 / 45 HP |
| Sprinter | Adrenaline | Endurance | `sprintSpeed` +2 / +4 / +6 |
| FastHands | Speedloader | Fast Hands | `reloadScale` 0.9 / 0.82 / 0.75 |
| FieldMedic | Field Medic | none | `healPerKill` 2 / 4 / 6 HP |
| Scavenger | Pack Rat | Scavenger | `ammoScale` 1.15 / 1.3 / 1.5 |
| SteadyAim | Steady Aim | none | `spreadScale` 0.85 / 0.7 / 0.55 |

The effect keys are named for the system that will read them (health, movement,
weapons, ammo, medic); nothing reads them in this change.

### Slots and prices (Credits only, never Robux)

| Item | Price |
| --- | --- |
| Slot 1 | free |
| Slot 2 | 1500 |
| Slot 3 | 3500 |
| Perk level 1 / 2 / 3 | 400..500 / 850..1100 / 1500..2000 per perk (`PerksConfig.perks[id].levelPrices`) |

### Server state (`PerkService`)

Profile version 4 adds `PerkLevels` (id -> level), `PerkSlots` (1..3, default 1) and
`PerksEquipped` (ids in slot order). The Perk Lab catalog (`ShopService` vendor id
`PerkLab`) lists the slot row (kind `PerkSlot`), a level row per perk (kind `Perk`) and,
for every perk with a level, an equip row (kind `PerkEquip`, price 0). Purchases go
through `ShopService.onPurchase`, which rebuilds the catalog server-side and dispatches
on the matched entry's kind, so the client cannot buy a slot from the Gunsmith or equip a
perk it has not unlocked. Every credit moves through `ProfileManager.spendCredits`. The
equipped set is validated by `PerksConfig.validateEquipped` (no duplicates, no unknown
id, no level 0, no more than the slots owned) on load, on every toggle and on read, and
cleared by `MissionService.removeFromMission`. The player attributes `PerkSlots` and
`PerksEquipped` (comma-separated ids) carry the state to the HUD.

## 3. Perk Lab

A sixth vendor-style room in `VendorsConfig` (`PerkLab`, "Perks for the next run") built
by `VendorRooms` with the same shell, counter, `VendorPrompt` and `VendorId` as the
others, on the west wall beside the Canteen at hub offset (-152, 0, 128), clear of the
gate on the south wall. Its props: six lab benches with lit flasks (one colour per perk),
a whiteboard, a rack of sealed cases, two monitors. The panel is `ShopGui` itself:
`actionTextFor` gains the three kinds (BUY SLOT, UNLOCK / UPGRADE, EQUIP FOR RUN /
EQUIPPED), the rows, theme and purchase flow are unchanged.

HUD: `RunHud` keeps the run balance readout and adds a row of two-letter text badges
(`PerksConfig.perks[id].badge`) under the wallet corner for the perks riding along. No
asset is added.

## 4. Studio check list

- **Kill pay per type.** In a run, kill a Walker and a Runner: "+N CR THIS RUN" rises by
  25 x multiplier and 40 x multiplier at the moment each dies (Medium: 40 and 64). A
  headshot kill adds 10 x multiplier more. Three kills inside four seconds pay 0, +5,
  +10 extra (x multiplier); a pause over four seconds resets the streak.
- **Distance still pays.** Run without shooting: the readout rises one credit per ten
  studs x multiplier, as before.
- **Results screen.** Die: the credits row shows the total with the kills, kill pay,
  distance pay and multiplier; the wallet in the hub has grown by that amount plus the
  goal bonus. Take a Continue: the readout starts from 0, die again, only the new share is
  added. Leave a run alive (squad leave): the wallet grows by the unbanked balance and
  the run count does not.
- **Perk Lab.** The sixth room stands beside the Canteen; walk in, hold the prompt: the
  panel lists "Perk slots 1 of 3", the six perks with UNLOCK prices, no equip rows yet.
- **Buying slot 2.** With 1500 credits, BUY SLOT 2: the wallet drops by 1500, the row
  reads "2 of 3 owned", the `PerkSlots` attribute is 2. Without the credits the button is
  red and the purchase refuses.
- **Equipping.** UNLOCK a perk (its equip row appears), EQUIP FOR RUN: the row reads
  EQUIPPED and the badge appears in the run HUD once the run starts. A third equip with two
  slots refuses with "All 2 slots are taken". After the run ends the badges are gone and
  the equip rows read EQUIP again; the levels and slots stay.
- **Persistence.** Rejoin: levels and slots are kept; an equipped set made before the
  rejoin is kept too (it is only cleared by a run's end).
- **Nothing reads the effects yet:** max health, speed, reload, ammo and spread are
  unchanged by an equipped perk.
