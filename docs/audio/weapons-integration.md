# Weapons on the spatial audio engine

Companion to [spatial-audio.md](spatial-audio.md). The engine landed without touching
`WeaponSfx.luau`, `WeaponVfx.luau`, `WeaponController.luau`, `WeaponsConfig.luau`,
`assets/manifest.json` or `AssetIds.luau`; this document is the exact change list for
them. Everything below assumes `SfxConfig.SPATIAL_AUDIO` is on.

## Status (branch `cloud/weapons-audio`, 2026-09-30)

Done, behind `SfxConfig.WEAPONS_ON_ENGINE` (default on, only read while
`SPATIAL_AUDIO` is on; off keeps every legacy path below intact so the two can be
compared in Studio):

| Section | State |
| --- | --- |
| 3 casings, 4 gong | `playCasingLand` on `Casing`, `playGong` on `Impact`; the legacy attachment voices and anchor parts stay on the off path |
| 1 own gun | close take, sub, foley, low-ammo layer and tail through `OwnGunshot` (jitter comes from the class); tail by `AudioEnvironment.environmentAt(AudioEngine.listenerPosition())` through `WeaponAudioMath.tailFor`; reflection fan from the muzzle (`WeaponController` passes `Viewmodel.getMuzzlePosition()`) gated to one per 90 ms by `WeaponAudioMath.gate`; the pools, the `Weapons` group reverb and the zone scan are legacy-only |
| 2 teammates | `playDistantShot` on `GunshotRemote` with `layerIds` from `WeaponAudioMath.layerIds`; `WeaponsConfig` carries `midSound` / `farSound` (`mid_<class>`, `far_<class>`), manifest slots exist with `assetId` 0 so the close take plays at every distance; the fan fires from the muzzle on the same gate |
| 5 impacts | `WeaponSfx.playImpacts(hits)` from `WeaponController.onWeaponHit`: family by material (`WeaponAudioMath.impactFamily`), `impact_<family>_01..02` when uploaded, else the Kenney impacts already in the manifest (`land_hard`, `bolt`, `land_soft`, `bite_*`) at 0.6 of the volume; two hits per volley; one hard hit in six adds `ricochet_01` |
| 6 sound lane | `SandboxWeaponGallery.playSoundLane` plays through `GunshotRemote` (with the fan), `ZombieVocal` and `Explosion` on the engine path, the wrapper on the off path; K and L were already bound |
| 7 mid takes | not done: the FFSL repository could not be fetched from the build environment (github.com answers 403 through its proxy, raw files time out), so no take was cut; the `mid_*` / `far_*` / `impact_*` / `ricochet_01` slots are in `assets/manifest.json` as `needed` with their candidate sources and in `assets/NEEDED.md` |

Pure rules in `src/client/audio/WeaponAudioMath.luau`, tested by `tests/audio/run.luau`
(tail choice, the rate limit, the layer keys, the impact families). Step 6 of the order
of work (removing the legacy branches, the `weapons` skip in `AudioEngine.preload` and
the `Weapons` SoundGroup) waits for the Studio comparison.
The engine API is `AudioEngine.play(spec): Handle` (`src/client/audio/AudioEngine.luau`,
spec fields in section 3.2 of the design doc) and `AudioReflections.fire(position, id,
bus, volume, pitch, rays)`.

## 1. The shooter's own gun (`WeaponSfx.playShot`)

Today every layer is a 2D `Sound` in a per-id pool on the `Weapons` SoundGroup, and a
`ReverbSoundEffect` on that group is retuned by `isInterior`. On the engine:

| Layer | Today | On the engine |
| --- | --- | --- |
| Close take (`closeSounds`, `shotSound` fallback) | `playOneShot(id, shotVolume, shotPitch)` | `AudioEngine.play({ id = id, class = "OwnGunshot", volume = config.shotVolume, pitch = config.shotPitch })`. 2D on the weapons bus; the class adds the ±4 % pitch and ±1.5 dB gain jitter, so drop `jitteredGain` and `PITCH_JITTER`. `duck = true` on the class means the take feeds the sidechain that dips ambience and music. |
| Sub layer (`gunshot_sub_*`) | `playOneShot(sub, SUB_VOLUME[class], 1)` | same call, class `OwnGunshot`, volume `SUB_VOLUME[config.class]` |
| Low-ammo click, last-round clack, dryfire, phase foley (`playPhase`), mag drop | `playOneShot` | same call, class `OwnGunshot`, no other change: the marker timing stays in `PackViewmodel` |
| Tail (`tail_open` / `tail_interior`, then `tail_open_<class>`) | `updateTail()` picks by `isInterior(root)` and retunes the reverb | pick by `AudioEnvironment.environmentAt(AudioEngine.listenerPosition())`: `Interior` and `Hangar` play `tail_interior`, `Street`, `Forest` and `Open` play `tail_open` (or the per-class `tail_open_<class>`), still 2D on the weapons bus at the same 0.34 / 0.46 of `shotVolume`. The weapons bus already carries the environment reverb and the street slapback, so delete the `ReverbSoundEffect`, `ensureGroup`, `scanZones`, `isInterior` and `updateTail`. Keep `TAIL_COOLDOWN`. |
| Environment layer (new: the MW2019 reflections) | none | after the close take: `AudioReflections.fire(muzzle, id, "weapons", config.shotVolume * 0.6, config.shotPitch, AudioEngine.reflectionRays())` where `muzzle` is the world position of the muzzle attachment (`WeaponVfx` has it for the flash). Rate-limit to one fan per 90 ms so automatic fire spawns a slap every second shot; the `Reflection` class caps live slaps at 12 (6 on mobile). In an open field this plays nothing; in the City it plays the facade slaps; in the room it plays at most two. |

Pools: the engine's voice pool replaces `pools` / `poolCursor` / `acquireVoice`; a
playing voice is never restarted (the engine picks a free voice or steals the least
valuable one, class limit 8 for `OwnGunshot`). `WeaponSfx.preload` can stay as a
`ContentProvider:PreloadAsync` over the ids, or go once `AudioEngine.preload` stops
skipping the `weapons` category (one line in `AudioEngine.luau`: remove
`category == "weapons"` from the skip test; it is skipped today only because
`WeaponSfx` preloads its own pools).

## 2. Other players' shots (`WeaponSfx.playDistantShot`)

Today: below 40 studs nothing, above it an anchor `Part` per shot and `SfxPlayer.play3D`
at 30 / 400 with 80 % volume. On the engine, no threshold, no anchor, one call:

```lua
function WeaponSfx.playDistantShot(position: Vector3, weaponId: string)
	local config = WeaponsConfig.get(weaponId)
	if not config then
		return
	end
	local id = shotSoundId(config)
	AudioEngine.play({
		layerIds = { close = id, mid = weaponSoundId(config.midSound), far = weaponSoundId(config.farSound) },
		class = "GunshotRemote",
		position = position,
		volume = config.shotVolume,
		pitch = config.shotPitch,
	})
	AudioReflections.fire(position, id, "weapons", config.shotVolume * 0.6, config.shotPitch, AudioEngine.reflectionRays())
end
```

`GunshotRemote` gives the class curve (`power`, 1400 studs, hold 24), full air absorption,
two occlusion rays, the speed-of-sound delay from the muzzle to the listener, and the
distance layers `close` 0..60, `mid` 40..350, `far` 250..1400 studs with equal-power
crossfades. A layer whose key is missing or 0 falls back to the nearest one that exists,
so until the mid and far recordings land the close take plays at every distance,
low-passed and delayed. `WeaponsConfig` gains two keys per weapon,
`midSound` and `farSound` (`"mid_rifle"`, `"far_rifle"`, ...), empty until the
recordings exist. Teammates' shots then read as MW's third-person perspectives:
close and dry beside you, a mid crack down the street, a far thump with the delay.

The call site in `WeaponController` (the replicated fire event) does not change.

## 3. Casings (`WeaponSfx.playCasingLand`)

Today twelve `Sound`s on Terrain attachments, 2 / 45 rolloff, culled past 45 studs of the
camera. On the engine the surface table, the speed factor and the brass / hull pick stay;
the voice becomes:

```lua
AudioEngine.play({ id = soundId, class = "Casing", position = position, volume = volume, pitch = pitch })
```

The `Casing` class carries the 45 stud range (the engine culls beyond it), a 2 stud
hold, light air, half-strength occlusion and a limit of 12 voices, so `casingVoices`,
`ensureCasingVoices` and the camera distance test go.

## 4. Range gong (`WeaponSfx.playGong`)

```lua
AudioEngine.play({ id = AssetIds.audio.range.gong, class = "Impact", position = position, volume = 0.9, range = 300, hold = 20, pitchJitter = 0.04 })
```

No anchor part. The gong recording is still rejected by moderation, so this stays
silent until a replacement is uploaded.

## 5. Bullet impacts and ricochets

`WeaponVfx` draws impacts but nothing plays for them yet. When recordings exist
(section 7), play them from the hit position with the material:

```lua
AudioEngine.play({ id = impactIdFor(material), class = "Impact", position = hitPosition, volume = 0.7 })
```

`Impact` is 120 studs, strong air absorption, one occlusion ray and the distance delay,
so a hit on a far wall arrives after the shot the way a real crack does.

## 6. Test yard hooks (`SandboxInput`, `SandboxWeaponGallery`)

`SandboxInput` binds K to `AudioDebug.toggle()` and L to `AudioDebug.fireTestShot()`
(N stays the game's mute key).

`SandboxWeaponGallery.playSoundLane` can stay on `SfxPlayer.play3D` (it now routes
through the engine's `Generic3D` class: distance curve, air, occlusion, delay). To hear
the lane through the real classes, replace the three `play3D` calls with:

```lua
AudioEngine.play({ id = weapons.close_rifle, class = "GunshotRemote", position = box.Position, volume = 1 })
AudioReflections.fire(box.Position, weapons.close_rifle, "weapons", 0.6, 1, AudioEngine.reflectionRays())
AudioEngine.play({ id = zombie.alert_bark, class = "ZombieVocal", follow = box, volume = 1 })
AudioEngine.play({ id = world.distant_boom, class = "Explosion", position = box.Position, volume = 1 })
```

The gallery's marker sounds (`play3D(station.anchor, id, volume, 4, 60, 0)`) are fine
through the wrapper.

## 7. Recordings the weapon classes still need

No asset id is invented here; every slot is a manifest entry the owner uploads through
`assets/manifest.json` -> `scripts/upload_assets.py` -> `scripts/sync_configs.py`, and
the engine falls back gracefully while a key is missing. Provenance: the Free Firearm
Sound Library (Ben Jaszczak, GitHub mirror `https://github.com/buddingmonkey/FreeFirearmsSFXLibrary`,
CC0-1.0) is what the close takes came from; its `Prepared Master Sheet.csv` (read from
the repository on 2026-09-29) lists, for every weapon, a "near distance, front of
shooter, left, right, stereo" file (our close takes) and a "mid distance, front of
shooter, forward, back, stereo" file, for example AK-47 `C_28P.wav` (near) and
`C_31P.wav`, `C_34P.wav`, `C_36P.wav` (mid, single, short and long bursts); the Walther
PPQ, Benelli Nova and Carl Gustav M45 have the same six-row pattern. There is no far
(100 m plus) perspective in that library, and `freesound.org` and `bigsoundbank.com` could
not be reached when this was written, so the far candidates below are to verify.

| Key (`AssetIds.audio.weapons`) | Used by | Candidate source | Licence | Notes |
| --- | --- | --- | --- | --- |
| `mid_rifle`, `mid_pistol`, `mid_shotgun`, `mid_smg` | `GunshotRemote` mid band (40..350 studs) | FFSL Prepared, the "mid distance" file of each weapon (AK-47 `C_31P`, and the matching PPQ, Nova, M45 rows) | CC0-1.0 | cut one shot each with `tools/audio_build/build_shots_v6.py` (blast without the range reflection, the reflection into `tail_open_<class>`) |
| `far_rifle`, `far_pistol`, `far_shotgun`, `far_smg` | `GunshotRemote` far band (250..1400 studs) | freesound CC0 search "distant gunshot" / "gunfire far field"; BigSoundBank (Joseph Sardin, public-domain release already used for the casings) "gunshot far" entries | CC0 / public domain | until one exists the engine plays the close take low-passed to 1.2..3 kHz, which is close to what a far recording is; a derived far layer (the mid take low-passed at 1.5 kHz plus `tail_open`) is allowed by the asset policy if it passes a listen |
| `tail_street`, `tail_forest` | `WeaponSfx` tail by environment | freesound CC0 "gunshot echo urban" / "gunshot forest echo"; or derive from the FFSL mid files' own reflections | CC0 | without them `tail_open` plays and the bus slapback (City) and forest reverb carry the difference |
| `explosion_close_01`, `explosion_close_02` | `Explosion` close band (0..120 studs) | OpenGameArt CC0 explosion packs (the `distant_boom` came from `https://opengameart.org/content/big-low-frequency-explosion-boom`); freesound CC0 "explosion close" | CC0 | `distant_boom` stays the far band |
| `impact_concrete_01..03`, `impact_metal_01..03`, `impact_wood_01..03`, `impact_dirt_01..03`, `ricochet_01..03` | `Impact` (section 5) | Kenney Impact Sounds (CC0, already in the manifest) as placeholders; freesound CC0 "bullet impact concrete" etc. | CC0 | mark the Kenney ones `"status": "placeholder"` and list them in `assets/NEEDED.md` |
| `slap_hard_01`, `slap_soft_01` | `Reflection` (optional) | derive from the close takes: 60 ms of the blast low-passed at 3 kHz (hard) and 1.5 kHz (soft) | inherits | the engine reflects the shot recording itself, filtered by the surface, so these are a polish item, not a blocker |

CC BY sources are acceptable too (`assets/LICENSES.md` says the credits go in the
settings panel before release); the Vincent Sevedge OpenGameArt shots already carry
that obligation.

## 8. Order of work

1. Run the Studio test plan (design doc, section 6; K overlay, L test shot).
2. `playCasingLand` and `playGong` (sections 3 and 4): smallest change, proves the
   engine on weapon sounds.
3. `playShot` (section 1): close take, sub, foley and tail through `OwnGunshot`; delete
   the group, reverb, pools and zone scan; add the reflection fan.
4. `playDistantShot` (section 2) with `midSound` / `farSound` in `WeaponsConfig`.
5. Upload the mid takes (section 7) and listen to a teammate's shot at 100 and 300
   studs on the sound lane pad.
6. Remove the `weapons` skip from `AudioEngine.preload` and the legacy branches once
   the owner signs off; then `SfxConfig.SPATIAL_AUDIO` and the `Weapons` SoundGroup can go.
