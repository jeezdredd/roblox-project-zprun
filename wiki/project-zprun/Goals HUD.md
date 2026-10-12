# Goals HUD

The mission goals shown on the run HUD with live progress, and the weapon ladder made
visible on the Gunsmith's rows. Branch `cloud/goals-hud` (2026-09-30); details and the
Studio checks in `docs/gameplay/goals-hud-and-ladder.md`. Closes the `NoDamage500` loose
end in [[Roadmap]]; the goals themselves are in [[Gameplay Systems]] (mission goals), the
ladder they show is the Gunsmith's and the [[Upgrade Station]]'s.

## Files

| File | Role |
| --- | --- |
| `src/shared/util/GoalsHudMath.luau` | Pure: the progress string (`encode`, `decode`) and the HUD rows. `luau tests/goals/run.luau` |
| `src/shared/util/WeaponLadderText.luau` | Pure: the Gunsmith row text (damage now, the next level's gain, top of the ladder; no price, the button has it) |
| `src/server/systems/MissionGoals.luau` | The `GoalsProgress` attribute (distances in steps of 5 studs), published at most every 0.25 s while reports change it, cleared on a death and on any exit from the run |
| `src/server/systems/DistanceTracker.luau` | Reports `Distance` live and `CleanDistance` (the best clean stretch so far: studs since the last health drop, kept as a max) |
| `src/server/systems/ShopService.luau` | `weaponEntries` descriptions from `WeaponLadderText` |
| `src/client/ui/RunHud.luau` | The "GOALS" block, top left, hidden in the hub |

## Rules

- One attribute carries every goal's progress, floored, in config order; no remote.
- `GoalsProgress` is `Id=value` pairs joined by `;`, e.g. `Distance1500=320;Kills25=4`.
  The decoder skips malformed pairs, and a goal missing from the string reads 0.
- Each value is floored to its metric's step (5 studs for `Distance` and `CleanDistance`,
  1 otherwise). The cap at the target is applied when the HUD builds its rows, not in
  the string. Goal targets must be whole multiples of the step, or a goal can show short
  of completion.
- The Gunsmith row label holds about 42 RobotoMono characters before it truncates, and
  `ShopGui` appends " · XP n/need" to an owned row below max, so `WeaponLadderText` stays
  short. The name label already carries the weapon name and "L2/5", so an owned row shows
  only the numbers, e.g. "32.4 dmg · L3: +2.4 dmg". Level 0 means not owned (the
  dealer's row).
- A hit is a drop in the humanoid's health between two frames of `DistanceTracker.step`;
  a Continue counts as one.
- The row text never changes the price or the gate: the button, the XP requirement and
  the purchase path are the Gunsmith's as before.

## Trade-offs (owner's calls made here)

- The hit hook lives in `DistanceTracker.step` (a health compare per frame) rather than
  a `HealthChanged` connection per character, so nothing touches the spawn flow.
- The progress string is published from a heartbeat flush rather than on every report,
  since the distance reports every frame.
