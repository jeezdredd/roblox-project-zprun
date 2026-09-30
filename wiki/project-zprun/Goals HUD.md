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
| `src/shared/util/WeaponLadderText.luau` | Pure: the Gunsmith row text (damage now, next level's price and gain, top of the ladder) |
| `src/server/systems/MissionGoals.luau` | The `GoalsProgress` attribute, published at most every 0.25 s while reports change it |
| `src/server/systems/DistanceTracker.luau` | Reports `Distance` live and `CleanDistance` (studs since the last health drop) |
| `src/server/systems/ShopService.luau` | `weaponEntries` descriptions from `WeaponLadderText` |
| `src/client/ui/RunHud.luau` | The "GOALS" block, top left, hidden in the hub |

## Rules

- One attribute carries every goal's progress, floored, in config order; no remote.
- A hit is a drop in the humanoid's health between two frames of `DistanceTracker.step`;
  a Continue counts as one.
- The row text never changes the price or the gate: the button, the XP requirement and
  the purchase path are the Gunsmith's as before.

## Trade-offs (owner's calls made here)

- The hit hook lives in `DistanceTracker.step` (a health compare per frame) rather than
  a `HealthChanged` connection per character, so nothing touches the spawn flow.
- The progress string is published from a heartbeat flush rather than on every report,
  since the distance reports every frame.
