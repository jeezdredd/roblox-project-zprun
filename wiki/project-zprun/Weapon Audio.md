# Weapon Audio

The weapon sounds on the spatial audio engine: the shooter's gun, teammates' shots,
casings, the range gong and bullet impacts through the engine's classes, with the legacy
`Sound`-pool path kept behind a switch. Branch `cloud/weapons-audio` (2026-09-30); the
change list and its status are `docs/audio/weapons-integration.md`, the engine itself
`docs/audio/spatial-audio.md`. See [[Architecture]] for the audio module tree and
[[Assets Pipeline]] for the key lookup rule the weapon sounds follow.

## The switch

`SfxConfig.WEAPONS_ON_ENGINE` (default true, only read while `SfxConfig.SPATIAL_AUDIO`
is on). On, every `WeaponSfx` function plays through `AudioEngine`; off, it takes the path
it had before: per-id `Sound` pools on the `Weapons` SoundGroup with its room reverb,
acoustic zones scanned from Workspace, casing voices on Terrain attachments, anchor parts
for 3D one-shots. Both paths share the key resolution, the variation picking, the
surface table and the phase markers, so a comparison in Studio only changes the
transport.

## Files

| File | Role |
| --- | --- |
| `src/client/audio/WeaponAudioMath.luau` | Pure: tail choice by environment and class, the reflection rate limit, the distance layer keys of a remote shot, the impact family of a material, the per-volley cap. `luau tests/audio/run.luau` |
| `src/client/systems/WeaponSfx.luau` | Both paths; the engine path per class below, plus the new `playImpacts` |
| `src/client/systems/WeaponController.luau` | Passes the muzzle position into `playShot`; calls `playImpacts` with the volley's hits |
| `src/client/systems/SandboxWeaponGallery.luau` | The sound lane (key B) through `GunshotRemote`, `ZombieVocal` and `Explosion` |
| `src/shared/config/WeaponsConfig.luau` | `midSound` / `farSound` per weapon |
| `src/shared/config/SfxConfig.luau` | The switch |
| `assets/manifest.json`, `assets/NEEDED.md`, `scripts/sync_needed.py` | The `mid_*`, `far_*`, `impact_*` and `ricochet_01` slots, status `needed`, with candidate sources |

## Engine path per sound

| Sound | Class | Notes |
| --- | --- | --- |
| Close take, sub, phase foley, low-ammo click, last-round clack, dryfire, mag drop | `OwnGunshot` | 2D on the weapons bus; the class adds the pitch and gain jitter and feeds the duck sidechain |
| Tail | `OwnGunshot` | `Interior` and `Hangar` (from `AudioEnvironment.environmentAt` at the listener) take `tail_interior` at 0.34 of the shot volume; `Street`, `Forest` and `Open` take `tail_open_<class>` at full share, or `tail_open` at 0.46 when the class has none; 0.55 s cooldown as before |
| Reflection fan | `Reflection` via `AudioReflections.fire` | from the muzzle, 0.6 of the shot volume, the profile's rays; one fan per 90 ms, so 600 rpm fires every shot and 1200 rpm every second one; the class caps live slaps at 12 (6 on mobile) |
| Teammate's shot | `GunshotRemote` | close, mid, far layers from `closeSounds` / `midSound` / `farSound`; a missing layer falls back to the nearest one that exists, so the close take plays at every distance today, low-passed and delayed by the class; the fan fires from the muzzle on its own 90 ms gate; no 40-stud threshold and no anchor part |
| Casing landing | `Casing` | surface volume and pitch, speed factor and brass / hull pick unchanged; the class culls past 45 studs |
| Range gong | `Impact` | range 300, hold 20, pitch jitter 0.04; still silent while the gong recording is rejected |
| Bullet impact | `Impact` | family by material: concrete (default), metal, wood, dirt, flesh; `impact_<family>_01..02` when uploaded, else the Kenney impacts already in the manifest at 0.6 volume; the first two hits of a volley; one hard hit in six adds `ricochet_01` (silent until uploaded) |

Preload on the engine path is `WeaponSfx.preload` doing a `PreloadAsync` over the weapon
ids (the engine's own preload still skips the `weapons` category).

## Not done

- The FFSL mid takes: the library could not be fetched from the build environment, so
  no take was cut. The slots are in the manifest as `needed`; cutting them is
  `tools/audio_build/build_shots_v6.py` on the "mid distance, front of shooter" rows
  (AK-47 `C_31P` and the matching PPQ, Nova and M45 files), then the upload pipeline.
- Step 6 of the order of work in the integration doc (dropping the legacy branches, the
  `weapons` preload skip and the `Weapons` SoundGroup) waits for the Studio comparison.

## Studio checks owed

Range fire per class with the switch on and off; the K overlay's voice counts during
full auto (`OwnGunshot` at most 8, `Reflection` at most 12); the B sound lane from the
listening pad; casings on each surface strip; a teammate's shot heard from the lane pad
at 100 and 300 studs.
