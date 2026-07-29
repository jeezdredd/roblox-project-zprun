# Dev bench

An iteration harness for weapon work. Everything in it is gated on `RunService:IsStudio()`, so none of it can reach a published server regardless of what is committed.

Switches live in [`src/shared/config/DevConfig.luau`](../src/shared/config/DevConfig.luau).

## What it removes

Before, testing one viewmodel change cost a scripted walk to the helicopter, a proximity-prompt hold, a squad launch and two waits — around twenty seconds, and it failed silently whenever anything in the hub flow changed. Now pressing Play drops you into a live solo run in well under a second, with the content warning skipped.

`QUICK_RUN.relaunchAfterDeath` also re-launches a run after you die, so a death-and-retry loop needs no input at all.

## Commands

Two command channels, and they are not interchangeable — a `BindableEvent` does not cross the client/server boundary, so each one only responds in the VM that created it.

**`ReplicatedStorage.DevBench` — fire from the *server* command bar.**

| Command | Effect |
| --- | --- |
| `launch` | Start a solo run now |
| `targets` | Build the dummy range at your current position |
| `cleartargets` | Remove it |
| `ammo` | Refill magazine and reserve |
| `weapon`, `"Rifle"` | Equip a weapon, granting ownership first if the profile lacks it |
| `state` | Print phase, weapon and mission state |

**`ReplicatedStorage.DebugWeapon` — fire from the *client* command bar.**

| Command | Effect |
| --- | --- |
| `fire` / `reload` / `inspect` | Drive the weapon without synthetic input, which does not reach the running client |
| `empty` | Set the predicted magazine to zero, to reach the empty-reload path |
| `freeze` / `unfreeze` | Stop and restart the forward run |
| `clearmodals` | Clear every modal flag in `CursorMode` |
| `state` | Print the client-side gate values |

## The target range

`targets` builds a fan of dummies at 10, 25, 50 and 100 studs. Each is a `Model` with a `Humanoid`, which is exactly what `WeaponService.findZombieModel` accepts, so hit registration, hit zones and gore all behave as they do on a zombie. They respawn on a timer.

Pair it with `freeze`: this is an endless runner, so without stopping forward motion the range is behind you within a second.

## Measuring, not eyeballing

Two rules learned the hard way on this rig.

**Measure absolutely, not relatively.** Slide travel measured against the receiver reads identically whether the rig is in front of the camera or lying at the world origin — the relative frame cancels exactly the failure you are trying to detect. Check each part's distance from the camera and its share of the screen instead.

**Take a screenshot in every phase you changed.** The viewmodel hung in mid-air in the hub for a long time purely because every screenshot had been taken during a run.
