# Hit and kill markers

Stage 4 of the quality pass (`wiki/project-zprun/Roadmap.md`, Weapons and ammunition:
"hit and kill markers"). Reference: Modern Warfare 2019's hip fire, where four short
diagonal ticks flash around the crosshair when a shot lands and a heavier red set
marks a kill.

## 1. What shows

| Variant | When | Look | Time |
| --- | --- | --- | --- |
| Hit | the server confirms the local shooter's shot hurt a zombie | four short white ticks on the diagonals around the crosshair | 0.12 s |
| Headshot | as Hit, with a pellet or bullet in the head | the same ticks, amber | 0.12 s |
| Kill | the server confirms the shot killed a zombie | the ticks red and larger (scale 1.35) | 0.25 s |

A hit's ticks scale slightly with the damage the shot dealt: 1 at 30 (a rifle body
shot), a quarter of the relative difference, kept within 0.9..1.25, so a full shotgun
blast reads a little bigger and a pistol graze a little smaller. Each marker pops in at
1.15 times its size, settles over its first 30 percent, holds and fades out over the
last 45 percent.

One marker at a time: the next confirmation restarts it (no stacked copies), except
that a hit or a headshot does not cut short a kill marker still showing, nor a body
hit a headshot one. All numbers live in `src/shared/config/HitMarkerConfig.luau`.

## 2. Confirmation, not prediction

The marker shows on the server's confirmation of the hit, never on the client's
prediction of the shot, so it never shows for a hit the server did not count (a shot
the server rejected, a zombie already dead, a forcefield). This is the owner's call for
markers; the shot's flash, tracers and impact puffs stay predicted
(`WeaponController.predictShot`, Development Policy section 1).

- `WeaponService.handleHit` returns what one ray did to a zombie: the damage dealt
  (the health drop, so never more than the zombie had), a head hit, a kill; nil when it
  hurt none. The damage rules are unchanged; the outcome is read after them.
- `WeaponService.onFire` sums a shot's pellets (`HitMarkerMath.combine`: damage summed,
  any head, any kill) and adds the result as the sixth value of the `WeaponHit` "Shot"
  reply it already fires to every client. Nil when the shot hurt no zombie. Nothing of
  it comes from the client.
- `src/client/ui/HitMarkers.luau` listens to the same reply beside `WeaponController`,
  takes it only when the shooter is the local player, and draws the marker centred on
  the weapon HUD's crosshair (which moves with hip aim), else the screen's centre.
  `WeaponController` is unchanged.

Test dummies in the yard (any non-player model with a Humanoid) count as zombies here,
as they already do for damage.

## 3. Sound

No approved sound in the manifest fits: `audio/ui/countdown_tick` is the squad launch
cue and `audio/ui/reward_tick` the pickup cue, and sharing either would blur the cues.
Two slots are `needed` with id 0 (`audio/ui/hit_marker`, `audio/ui/kill_marker`), with
candidate sources in the manifest notes and rows in `assets/NEEDED.md`. The client plays
them 2D in the UI class only when the id is non-zero; until then the markers are silent.
No synthesized audio.

## 4. Setting

"Hit markers" in a new Interface section of the settings panel (`SettingsConfig`,
key `hitMarkers`, toggle, default on). Off: nothing draws and nothing plays. The panel
is built from the schema, so the row appears with no panel code.

## 5. Tests

`luau tests/hitmarkers/run.luau`: the variant per confirmation, the timing (0.12 and
0.25 s, the pop, the fade only going down), the damage scaling (reference, up, down,
both clamps, every weapon's body shot within range), restarting without stacking (a
kill over a hit, a hit not cutting a kill, a headshot over a hit), and the per-pellet sum.

## 6. Studio check list

- **Hit.** In the yard or a run, shoot a Walker in the body with the rifle: four white
  ticks flash around the crosshair for about a tenth of a second; a miss shows nothing.
- **Headshot.** The same in amber.
- **Kill.** The killing shot shows the red, larger ticks for a quarter second; a hit
  landing on another zombie during it does not cut it short.
- **Rapid fire.** Hold the SMG on a zombie: one marker restarting with each confirmed
  hit, never several overlapping.
- **Shotgun.** One marker per shot, slightly bigger at close range (more pellets in).
- **Lag.** With incoming replication lag (Studio network settings), the marker comes a
  round trip after the shot, the tracer at once: the marker never shows for a shot the
  server did not count.
- **Hip aim.** With the crosshair moved by the hip aim lock, the ticks centre on it.
- **Setting.** Settings, Interface, Hit markers off: no markers; on again: back.
- **Other players' shots** never show a marker on this screen.
- **Silent** until the two sound slots are filled; nothing errors.

Not verified without Studio: the ticks' look at 1080p and on a phone, the motion of the
pop and fade (to be checked as motion, frames around each shot), and the new settings
section's fit in the panel.
