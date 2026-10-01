# Hit Markers

Hit and kill markers around the crosshair, Modern Warfare 2019 hip fire style, on the
server's confirmation only. Branch `cloud/hit-markers` (2026-10-01); details and the
Studio checks in `docs/gameplay/hit-markers.md`. Stage 4 of the quality pass in
[[Roadmap]]; the confirmation rule is recorded against [[Development Policy]] section 1.

## Files

| File | Role |
| --- | --- |
| `src/shared/config/HitMarkerConfig.luau` | Durations (0.12 s, kill 0.25 s), damage scaling, pop and fade, tick geometry, colours, sound keys, the setting key |
| `src/shared/util/HitMarkerMath.luau` | Pure: variant, duration, scale, restart with priority, the marker's frame, the per-pellet sum. `luau tests/hitmarkers/run.luau` |
| `src/server/systems/WeaponService.luau` | `handleHit` returns the outcome (damage dealt, head, kill); `onFire` sends the shot's sum as the sixth value of the `WeaponHit` "Shot" reply |
| `src/client/ui/HitMarkers.luau` | The four ticks on the crosshair, driven by that confirmation for the local shooter only |
| `SettingsConfig` | "Hit markers" (`hitMarkers`), Interface section, default on |
| `assets/manifest.json` | `audio/ui/hit_marker`, `audio/ui/kill_marker`: `needed`, id 0, silent |

## Rules

- Server confirmation only, never the prediction; the damage rules are unchanged.
- One marker at a time; a kill marker is not cut short by a hit.
- Hit 0.12 s scaled 0.9..1.25 by damage, headshot amber, kill red 1.35 for 0.25 s.
- Silent until real sound files fill the two slots.
