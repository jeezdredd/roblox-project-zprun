# Spatial audio: natural sound propagation

Branch `cloud/spatial-audio`, written 2026-09-29 for the stage 2 audio task
(`docs/tasks/cloud-spatial-audio.md`). This document is the design, the research it rests
on, the Studio test plan and the migration plan. The weapon-side changes that the main
session owns are in [weapons-integration.md](weapons-integration.md).

The owner's complaint: every sound is muffled, "as if indoors", with no natural propagation.
The cause is structural. Every consumer today builds its own `Sound` with one of two
rolloff shapes, no filtering by distance, no delay, no occlusion, and one global
`AmbientReverb` preset (`Hangar` in the hub, `NoReverb` in the run). The fix is one client
audio engine that every non-weapon consumer plays through, built on the Roblox audio API
(`AudioPlayer`, `AudioEmitter`, `AudioListener`, `Wire` and the effect classes), behind
`SfxConfig.SPATIAL_AUDIO` with the legacy path intact.

## 1. Research summary

### 1.1 The Roblox audio API in 2026

Sources: the class reference pages under
`https://create.roblox.com/docs/reference/engine/classes/<Class>` and
`.../enums/<Enum>`, read from their source in the `Roblox/creator-docs` repository
(`content/en-us/reference/engine/classes/*.yaml`, branch `main`, fetched 2026-09-29),
the audio guides `https://create.roblox.com/docs/audio/objects` and
`https://create.roblox.com/docs/audio/effects`, the tutorial
`https://create.roblox.com/docs/tutorials/use-case-tutorials/audio/add-3D-audio`, and the
DevForum announcements listed at the end of this section. `create.roblox.com`,
`devforum.roblox.com` and `robloxapi.github.io` are blocked by this container's egress
policy, so the docs were read through the GitHub mirror and the forum through search
excerpts; every forum-only fact is marked as such.

**Graph model.** Audio does not flow through the instance tree. An `AudioPlayer` loads an
asset (`Asset`, `Looping`, `Volume` 0..10, `PlaybackSpeed` 0..20, `TimePosition`,
`PlaybackRegion`, `LoopRegion`, `Play(atTime?)`, `Stop(atTime?)`, `Ended`, `Looped`) and
exposes one `Output` pin. A `Wire` (`SourceInstance`, `SourceName` = `"Output"`,
`TargetInstance`, `TargetName` = `"Input"`, read-only `Connected`) carries the stream to
the next node. Many wires may feed one input pin (the fader-as-bus pattern in the
effects guide: "wire multiple audio players through an audio effect"), and a node with no
wire to an `AudioDeviceOutput` is silent. Wires can be parented anywhere; the guides and
the tutorial parent them under the source or target for tidiness only.

**Spatialisation.** An `AudioEmitter` is the 3D source. `PositionType` is `Parent`
(default) or `Instance` with `PositionInstance` (an instance with a position; nil or
positionless makes the emitter inaudible). `DistanceAttenuationMode` defaults to `Custom`
and then uses the curve given to `SetDistanceAttenuation({[distance] = volume, ...})`:
up to 400 points, linear interpolation, flat beyond the end points, empty table means the
built-in inverse curve. The presets `Inverse`, `InverseTapered`, `Linear`,
`LinearSquared` use `DistanceAttenuationBounds` (`NumberRange`, default 4..10000).
`SetAngleAttenuation` gives directivity (0..180 degrees to volume). An `AudioListener`
hears emitters and outputs the mixed, panned result on its `Output` pin;
`GetAudibilityFor` returns the combined 0..1 attenuation. **`AudioInteractionGroup`** on
emitter and listener restricts hearing to matching groups: this is how one listener per
bus is built, and it also keeps our emitters away from any listener the engine creates on
its own.

**Listener placement.** `SoundService.DefaultListenerLocation` (`ListenerLocation`:
`Default`, `None`, `Character`, `Camera`) is `PluginSecurity` read and write, so scripts
cannot set it; `Default` behaviour depends on `VoiceChatService.EnableDefaultVoice` and
`UseAudioApi`. The engine therefore creates its own listeners (parented to
`Workspace.CurrentCamera`, `PositionType = Parent`) with our interaction groups, and its
own `AudioDeviceOutput`. `SoundService.ListenerType` / `SetListener` affect legacy `Sound`
instances only.

**Timing.** `SoundService:GetMixerTime()` is a sample-accurate, monotonic audio clock, and
`AudioPlayer:Play(atTime)` / `Stop(atTime)` schedule against it (the docs say the methods
"expect times derived from `GetMixerTime()`"); `Cancel(actionId)` withdraws a scheduled
action. This is the speed-of-sound delay mechanism: no `task.delay`, no frame jitter.

**Effects** (each has `Input` and `Output` pins, `Bypass`):

| Class | Parameters (documented ranges) | Used for |
| --- | --- | --- |
| `AudioFader` | `Volume` 0..3 | every bus, the master |
| `AudioFilter` | `FilterType` (`Peak`, `LowShelf`, `HighShelf`, `Lowpass6dB`/`12dB`/`24dB`/`48dB`, `Highpass12dB`/`24dB`/`48dB`, `Bandpass`, `Notch`), `Frequency` 20..22000, `Q` 0.1..10, `Gain` -30..30, `GetGainAt` | per-voice air absorption and occlusion low-pass |
| `AudioEqualizer` | `LowGain`, `MidGain`, `HighGain` -80..10 dB, `MidRange` 200..20000 | concussion effect on the sfx bus |
| `AudioReverb` | `DecayTime` 0.1..20 s, `DecayRatio` 0.1..1, `Density`, `Diffusion` 0.1..1, `DryLevel`, `WetLevel` -80..20 dB, `EarlyDelayTime` 0..0.3 s, `LateDelayTime` 0..0.1 s, `HighCutFrequency`, `LowShelfFrequency`, `LowShelfGain`, `ReferenceFrequency` | environment tails per bus |
| `AudioEcho` | `DelayTime` 0.001..5 s, `Feedback` 0..1, `DryLevel`, `WetLevel` -80..10 dB, `RampTime` | street-canyon slapback on the weapons and sfx buses |
| `AudioCompressor` | `Threshold` -60..0 dB, `Ratio` 1..50, `Attack` 0.0001..0.5 s, `Release` 0.01..5 s, `MakeupGain`; extra `Sidechain` input pin: "the threshold analyses those streams instead of Input, enabling volume ducking of one stream based on another" | ducking ambience and music under gunfire |
| `AudioLimiter` | `MaxLevel` -12..0 dB, `Release` 0.001..1 s | master limiter |
| `AudioAnalyzer` | `PeakLevel`, `RmsLevel`, `GetSpectrum` (client only) | debug overlay meters |

**Built-in acoustic simulation.** `SoundService.AcousticSimulationEnabled`,
`AudioEmitter` / `AudioListener` `AcousticSimulationEnabled` plus per-object
`OcclusionEnabled`, `ReverbEnabled`, `DiffractionEnabled` (`SimulationMode`: `Default`,
`Enabled`, `Disabled`), `BasePart.AudioCanCollide` ("similar to `CastShadow` for
lighting") and `PhysicalProperties.AcousticAbsorption` (0..1, higher absorbs more reverb;
`Density` controls how much an occluding part muffles) exist in the API. The feature
shipped as a Studio beta (DevForum "[Studio Beta] Acoustic Simulation", thread 3634265)
and then as a **client beta** usable in published experiences (DevForum "[Client Beta]
Acoustic Simulation: Emit audio with presence!", thread 4307121, January 2026 per search
excerpts; the exact day could not be read because the forum is blocked here). The public
roadmap (`https://create.roblox.com/roadmap`) lists "Acoustic Simulation for Sounds" for
late 2026. `SimulationFidelity` is already deprecated. The task rule is to prefer an
engine feature only when it is out of beta, so the engine implements its own occlusion
and environment path, and exposes `SfxConfig.ACOUSTIC_SIMULATION` (default `false`) to
switch the built-in simulation on instead: with it on the engine skips its own rays and
bus reverb and sets the flags above. That switch is a Studio listen for the owner (test
plan item 8).

**Limits and cost (forum excerpts, unverified here).** One DevForum thread reports a cap
of 300 `AudioEmitter`s and another a large frame cost past roughly 1000 `AudioPlayer`s
(threads 2848873 and 3928632). The pool sizes in section 5 stay an order of magnitude
under both.

**Announcements read through search excerpts:** "New Audio API [Beta]: Elevate Sound and
Voice in Your Experiences" (thread 2848873), "New Audio API Features: Directional Audio,
AudioLimiter and More" (thread 3282100, December 2024: `AngleAttenuation`, `AudioLimiter`,
`GetWaveformAsync`, `AudioEcho.RampTime`, `DefaultListenerLocation`), "Adding the Audio
API Roll Off Curve Editor" (thread 2973392), "[Studio Beta] Acoustic Simulation"
(3634265), "[Client Beta] Acoustic Simulation" (4307121).

### 1.2 API verification

The official dump host `raw.githubusercontent.com` is denied by this container's egress
policy for `curl` (the `WebFetch` tool reaches it but truncates the 10 MB file), so
`tools/validate_api.py` cannot download its cache here. Every class, property, method and
enum in the engine was verified against two independent derivatives of the dump instead:

1. The `Roblox/creator-docs` reference YAML (auto-generated from the dump, carries tags
   such as `Deprecated`, `NotScriptable`, security levels), branch `main`, read
   2026-09-29.
2. `@rbxts/types` 1.0.955 (roblox-ts typings generated from the API dump, published
   2026-09-25), downloaded from the npm registry, which this container can reach.

`tools/validate_api.py` was run against a dump-shaped JSON built from (2), which checks the
same two things it checks with the real dump: every `Instance.new("Class")` names a real
class and every property assigned on it exists. The owner should run
`python3 tools/validate_api.py` locally with the real dump before merging; nothing in the
engine uses a member that is absent from either source. Members used, all present in both:

| Class | Members used |
| --- | --- |
| `AudioDeviceOutput` | `Player` (left nil = every player), `Input` pin |
| `AudioListener` | `AudioInteractionGroup`, `PositionType`, `AcousticSimulationEnabled`, `OcclusionEnabled`, `ReverbEnabled`, `DiffractionEnabled`, `Output` pin |
| `AudioEmitter` | `AudioInteractionGroup`, `PositionType`, `PositionInstance`, `DistanceAttenuationMode`, `SetDistanceAttenuation`, `AcousticSimulationEnabled`, `OcclusionEnabled`, `ReverbEnabled`, `DiffractionEnabled` |
| `AudioPlayer` | `Asset`, `AutoLoad`, `Looping`, `Volume`, `PlaybackSpeed`, `TimePosition`, `TimeLength`, `IsPlaying`, `IsReady`, `Play(atTime)`, `Stop(atTime)`, `Ended` |
| `AudioFader` | `Volume` |
| `AudioFilter` | `FilterType`, `Frequency`, `Q` |
| `AudioEqualizer` | `LowGain`, `MidGain`, `HighGain` |
| `AudioReverb` | `DecayTime`, `DecayRatio`, `Density`, `Diffusion`, `DryLevel`, `WetLevel`, `EarlyDelayTime`, `LateDelayTime`, `HighCutFrequency` |
| `AudioEcho` | `DelayTime`, `Feedback`, `DryLevel`, `WetLevel`, `RampTime` |
| `AudioCompressor` | `Threshold`, `Ratio`, `Attack`, `Release`, `MakeupGain`, `Sidechain` pin |
| `AudioLimiter` | `MaxLevel`, `Release` |
| `AudioAnalyzer` | `RmsLevel`, `PeakLevel` |
| `Wire` | `SourceInstance`, `SourceName`, `TargetInstance`, `TargetName` |
| `SoundService` | `GetMixerTime`, `AcousticSimulationEnabled`, `AmbientReverb` (legacy path) |
| `Attachment` | `WorldPosition` (emitter position hosts) |
| Enums | `EmitterPositionType.Instance`, `ListenerPositionType.Parent`, `DistanceAttenuationMode.Custom`, `AudioFilterType.Lowpass12dB`, `SimulationMode.Enabled/Disabled`, `ReverbType` (legacy) |

Not used on purpose: `SoundService.DefaultListenerLocation` (plugin security),
`VolumetricAudio` (not scriptable), `AudioEmitter.SimulationFidelity` (deprecated),
`AudioPlayer.AssetId` (deprecated, `Asset` instead).

### 1.3 How the reference shooters do it

Reached through search excerpts only (the publishers' sites are blocked here); the
quotes are as the excerpts rendered them.

- **Modern Warfare 2019 / Warzone.** Every weapon was recorded from many perspectives
  ("about 90 different microphones", twenty for the player perspective; Activision
  Initial Intel, `https://blog.activision.com/call-of-duty/2019-07/Modern-Warfare-Initial-Intel-Creating-an-Orchestra-of-Incredible-Audio-Effects-Weapon-Sounds-in-Call-of-Duty-Modern-Warfare`).
  Per-shot layers are the bang, mechanical foley, low "thump", environmental tails and
  reflections and calibre-specific casings, chosen from "environment, surroundings,
  ammunition count, rounds fired" (`https://www.asoundeffect.com/call-of-duty-modern-warfare-sound/`).
  The reflections system: "With every gunshot or explosion, ray-casts are drawn to find
  collisions with geometry where positional sound reflections are played in 3D space.
  These, too, playback with delays according to the speed of sound"; big spaces give "a
  big, deep, booming echo", confined ones are "more muffled, far less reverberating"
  (same two sources). Occlusion and portaling came from Microsoft's Project Triton
  (`https://www.windowscentral.com/gaming/call-of-duty/infinity-ward-using-microsoft-audio-tech-for-modern-warfare-4`).
  Warzone adds "EQs ... used for low-pass and high-pass filtering over distance" and
  reflection assets chosen by "location, orientation, and the distance of the
  reflections" (`https://www.asoundeffect.com/call-of-duty-warzone-sound/`).
- **Battlefield (DICE).** HDR audio scales all sources against a loudness window at the
  listener and culls by loudness ("not compression", logical values only;
  `https://www.ea.com/frostbite/news/how-hdr-audio-makes-battlefield-bad-company-go-boom`).
  Battlefield 1 "records the same event from several distances and crossfades between
  them, rather than using filters to model distance"
  (`https://www.asoundeffect.com/battlefield-1-sound/`); weapons combine "different
  reflections based on environment type or different tails depending on distance"
  (`https://www.asoundeffect.com/game-audio-future-ben-minto/`).
- **Hunt: Showdown (Crytek).** Every sound comes from a real source and attenuates by its
  power ("attenuation templates ... a loud sound is audible over a longer distance";
  `https://www.huntshowdown.com/news/hunt-audio-readability-realism-and-consistency`).
  Occlusion: "all sounds shoot a ray to the player which checks whether there is an
  obstacle and its surface type, with denser surface types creating more muffling"
  (`https://80.lv/articles/crytek-on-the-sound-design-of-hunt-showdown`). Update 2.0:
  "All far-reaching environmental sounds, gunfire, and explosions are now delayed by a
  defined speed of sound over distance (c = 343m/s)" and an echo system reflects shots
  off large structures with the same delay applied to the reflection path
  (`https://huntshowdown.wiki.gg/wiki/Update/2.0`). Update 2.4 filtering bands:
  "almost no filtering between 0-30m, some light filtering ... between 30-70m, and
  stronger filtering ... beyond 70m"
  (`https://www.huntshowdown.com/news/dev-insight-audio-design-recap-what-s-new-in-update-24`).
- **PUBG / Arma.** PUBG delays at 340 m/s ("a pistol shot 340 m away ... hear the
  gunshot after 1 second"; `https://www.pcgamer.com/how-gunshot-sounds-work-in-playerunknowns-battlegrounds/`);
  Arma 3 has a per-SoundSet speed-of-sound flag
  (`https://community.bistudio.com/wiki/Arma_3:_Sound:_cfgSoundSets`).
- **Mixing practice.** Per-class attenuation is standard: Wwise examples hold weapons flat
  to 10 units then log falloff to 140, footsteps to 130
  (`https://gameaudioresource.com/2019/08/18/chapter-11-a-weapon-rifle-shotgun/`); Unreal
  names Linear, Logarithmic, Inverse, LogReverse and "Natural Sound" curves and describes
  air absorption as "a low pass filter whose cutoff point varies relative to the
  listener's distance" (`https://dev.epicgames.com/documentation/en-us/unreal-engine/sound-attenuation-in-unreal-engine`).
  Ducking: 3-6 dB depth with a release around 500-700 ms is the common starting point,
  UI ducks others and is never ducked
  (`https://www.gamedeveloper.com/audio/game-audio-theory-ducking`,
  `https://sfxengine.com/blog/best-practices-for-game-ui-sounds`). Master limiter at
  about -1 dB with a short release, an average around -23 LUFS
  (`https://www.audiokinetic.com/en/blog/mastering-a-game-with-wwise-part1/`,
  `https://designingsound.org/2013/02/20/different-loudness-ranges-for-console-and-mobile-games/`).
  Voice limits per bus with priorities, killing finite inaudible voices
  (`https://www.audiokinetic.com/en/blog/how-to-get-a-hold-on-your-voices-optimizing-for-cpu-part-1/`).
- **Roblox FPS games.** No developer of Phantom Forces, Frontlines, RIVALS or TTK Testing
  has published their gunfire technique. Community threads use separate near and far
  assets, low-pass by distance and an echo layer
  (`https://devforum.roblox.com/t/distant-gunshot-sound-effects/1358291`).

### 1.4 Physics

Sources reached directly: the ISO 9613-1 equations as transcribed in
`python-acoustics` (`https://raw.githubusercontent.com/python-acoustics/python-acoustics/master/acoustics/standards/iso_9613_1_1993.py`),
the Roblox `RollOffMode` reference, the Unreal `SoundAttenuation.h` and
`DistanceModelAttenuation` sources on GitHub, Steam Audio's `phonon.h` material table and
Unity docs, Godot's `AudioStreamPlayer3D` docs, Resonance Audio's
`distance_attenuation.cc`. The rest (marked "excerpt") came through search excerpts
because the acoustics sites are blocked from this container.

**Air absorption (ISO 9613-1).** Computed from the standard's equations at 20 C, and
cross-checked against ISO 9613-2 Table 2 (20 C / 70 %: 0.3, 1.1, 2.8, 5.0, 9.0, 22.9,
76.6 dB/km for 125 Hz..8 kHz; quoted in `https://github.com/Sirokujira/OpenAcoustics`
and the WA EPA noise appendix, excerpt):

| Condition | 125 Hz | 250 | 500 | 1 k | 2 k | 4 k | 8 k | unit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 20 C, 50 % RH | 0.44 | 1.31 | 2.73 | 4.66 | 9.89 | 29.7 | 105.3 | dB/km |
| 20 C, 70 % RH | 0.33 | 1.12 | 2.79 | 4.98 | 9.04 | 23.1 | 77.6 | dB/km |
| 20 C, 50 % RH | 0.044 | 0.131 | 0.273 | 0.466 | 0.989 | 2.97 | 10.5 | dB per 100 m (357 studs) |

Real air removes only about 7 dB at 8 kHz and 2 dB at 4 kHz over 70 m (250 studs), so a
physically exact filter is inaudible inside a Roblox map. Games exaggerate on purpose:
Hunt's 0 / 30 / 70 m bands (1.3); Wwise ("these curves are often not physically
accurate", `https://blog.audiokinetic.com/a-wwise-approach-to-spatial-audio-part-1/`,
excerpt); Unreal's air absorption is a plain low-pass interpolated between two distances
(`https://dev.epicgames.com/documentation/en-us/unreal-engine/sound-attenuation-in-unreal-engine`);
Godot ships a 5 kHz, -24 dB distance low-pass by default
(`https://raw.githubusercontent.com/godotengine/godot-docs/master/classes/class_audiostreamplayer3d.rst`).
**Engine constant:** the 8 kHz band at 6x ISO, that is 0.63 dB per 10 m, drives a
single 12 dB/octave low-pass whose cutoff is where the exaggerated attenuation reaches
-6 dB; the curve gives 22 kHz under 20 studs, about 8 kHz at 110 studs (30 m), 4 kHz at
250 studs (70 m) and a floor of 1.2 kHz past 700 studs, which reproduces Hunt's schedule.
The class `air` strength scales the exponent.

**Distance law.** Spherical spreading is -6 dB per doubling, a line source -3 dB
(`https://www.sfu.ca/sonic-studio-webdav/handbook/Sound_Propagation.html`, excerpt).
Every engine departs from it with a minimum distance inside which the level is clamped
to full (FMOD `mindistance`, Unreal `MinRadius`, Roblox `RollOffMinDistance`), and most
add a curve family: FMOD Inverse / Linear / LinearSquare / InverseTapered
(`https://github.com/JoshParnell/libphx/blob/master/ext/include/fmod/fmod_common.h`),
Roblox `Sound` `Inverse = RollOffMinDistance / distance`, `LinearSquare`, `InverseTapered
= min(Inverse, LinearSquare)` (`RollOffMode` reference), Unreal Linear / Logarithmic /
LogReverse / Inverse / NaturalSound with `Inverse = (MaxRadius / MinRadius) * (0.02 /
(Distance / MaxRadius))`, Unity Logarithmic that "does not actually reach zero",
Resonance Audio `1 / (d + 1)` normalised to zero at the maximum. **Engine constant:**
`AudioMath.attenuationCurve(shape, range, hold)` samples 12 points of
`min(hold / d, taper)` where `taper` is the linear-square fall to zero at `range`
(`natural`), the same with a `d^0.7` power law so loud sources stay audible over most
of their range (`power`), or a plain linear fall for loops (`linear`); it feeds
`SetDistanceAttenuation`, so the emitter does the interpolation.

**Street-canyon reflections.** With source and listener at distance D from a facade,
separated by L along it, the extra path is `sqrt(L^2 + 4 D^2) - L`:

| Facade distance D | L = 0 m | L = 10 m | L = 20 m | L = 50 m |
| --- | --- | --- | --- | --- |
| 5 m (18 studs) | 29 ms | 12 ms | 7 ms | 3 ms |
| 10 m (36 studs) | 58 ms | 36 ms | 24 ms | 11 ms |
| 20 m (71 studs) | 117 ms | 91 ms | 72 ms | 41 ms |
| 40 m (143 studs) | 233 ms | 206 ms | 182 ms | 129 ms |

A handgun blast lasts about 1 ms; urban reflections stretch it to "seconds"
(`https://acoustics.org/pressroom/httpdocs/162nd/Beck_4aSCa3.html`, excerpt). Slapback
is a single repeat at 40..150 ms (`https://www.sweetwater.com/insync/slapback-delay/`,
excerpt); flutter between parallel facades d apart repeats every `2 d / c` (10 m
streets: 58 ms). The precedence effect fuses a reflection with the direct sound for lags
up to about 35..40 ms and it reads as an echo past about 50 ms
(`https://en.wikipedia.org/wiki/Precedence_effect`, excerpt). **Engine constants:**
reflection delay `(|s-h| + |h-l| - |s-l|) / 1225` s; taps under 12 ms dropped and taps
under 40 ms folded into the bus early reflections (`EarlyDelayTime`); the City slapback
`AudioEcho` at 85 ms (a 15 m canyon) with feedback 0.18, wet -16 dB.

**Speed of sound.** 343 m/s at 20 C, 1225 studs/s here: 36 studs is 29 ms, 154 studs
(43 m) is 125 ms, 357 studs (100 m) is 292 ms. Hunt delays "all far-reaching
environmental sounds, gunfire, and explosions" at 343 m/s; PUBG at 340 m/s; Arma per
sound set (1.3). ITU-R BT.1359 puts audio-late detectability at 125 ms
(`https://en.wikipedia.org/wiki/Lip_sync_error`, excerpt); no source gives a
flash-to-bang threshold, so the echo threshold (35..40 ms) is the closest number.
**Engine constant:** delay is applied to every 3D one-shot as `distance / 1225`; under
40 ms it is imperceptible lag, beyond 125 ms (154 studs) it is the readable cue. The
config exposes `DELAY_MIN_DISTANCE = 0` so the owner can raise it if near shots feel
late against the muzzle flash.

**Occlusion and obstruction.** Wwise: obstruction attenuates the direct path only (a
pillar in the same room), occlusion also the reflected sound (a partition)
(`https://www.audiokinetic.com/en/library/edge/?source=Help&id=obstruction_and_occlusion`,
excerpt). Transmission loss by partition (STC, excerpts from
`https://doordesignlab.com/blog/stc-rating-for-doors/`,
`https://www.acousticalsurfaces.com/blog/acoustics-education/sound-transmission-class-stc-rating/`,
`https://www.stcratings.com/masonry.html`): hollow door 20..25 dB, solid door 30..35,
single glass 26..28, stud wall with drywall 33..39, 8 in block 45..55, brick about 50.
Steam Audio's default material transmission (amplitude, low / mid / high;
`https://github.com/ValveSoftware/steam-audio/blob/master/core/src/core/phonon.h`):
brick 0.015 flat (-36 dB), concrete 0.015 / 0.002 / 0.001, glass 0.060 / 0.044 / 0.011,
wood 0.070 / 0.014 / 0.005: glass leaks highs relative to wood. Unreal traces one ray and
interpolates over 0.1 s; Steam Audio traces several rays around the source so edges do
not flicker. **Engine constants (material table in `SpatialAudioConfig.materials`):**

| Material family (`Enum.Material` names) | Loss | Low-pass |
| --- | --- | --- |
| Concrete, Brick, Cobblestone, Pavement, Asphalt, Rock, Basalt, Granite, Slate, Limestone, Sandstone, Marble | -30 dB | 600 Hz |
| Metal, CorrodedMetal, DiamondPlate, Foil | -26 dB | 900 Hz |
| Wood, WoodPlanks, Cardboard, Plaster, Plastic, SmoothPlastic | -18 dB | 1500 Hz |
| Glass, Ice | -16 dB | 3000 Hz |
| Fabric, Carpet, Leaf, LeafyGrass, Grass, Sand, Snow, Mud, Ground, Salt | -10 dB | 2500 Hz |
| Water | -22 dB | 800 Hz |

The losses are lower than the STC figures on purpose: a fully realistic -45 dB reads as
silence in a game, and the goal is "muffled and quieter, and opens up again". The
second ray (gunshots and explosions) halves the loss when only one of the two rays is
blocked, which is the obstruction case.

**Reverb by environment.** Free field has no reflections; street canyons measure 2..7 s
T30 depending on width (`https://discovery.ucl.ac.uk/10058525/`, excerpt) but that is
unreadable under gunfire; forest IRs are dominated by scatter among trunks, up to 1.5 s
above 1 kHz at 40 m (`https://asa.scitation.org/doi/10.1121/1.1629304`, excerpt); a
229,000 cubic foot hangar measured 5 s before treatment
(`https://acousticalsolutions.com/application/tweed-new-haven-airport`, excerpt); gyms
and halls 1.2..2 s. The presets in 3.5 follow these, shortened for readability.

## 2. Sound consumer map (today, before this branch)

`Sound` everywhere, two rolloff shapes, one global reverb. Groups are the legacy
`SoundGroup` tree `TFZ_Master` > `TFZ_Music`, `TFZ_Sfx` > `Weapons` from
`MusicController`. "3D" means a `Sound` parented to a part with `RollOffMode.InverseTapered`
and the min/max listed.

| Consumer | Sound | Space | Rolloff min/max | Group | Notes |
| --- | --- | --- | --- | --- | --- |
| `MusicController` | `MenuMusic`, `MissionMusic` loops | 2D | - | Music | phase-switched, `TweenService` fade, duck scale from `UiSfx` |
| `MusicController` | `CitySiren` (`siren_facility`) loop | 2D | - | Master | hub only, bypasses the sfx group |
| `SfxPlayer.play2D` | pool of 10 `Sound`s in `SoundService` | 2D | - | Sfx | round robin, pitch jitter |
| `SfxPlayer.play3D` | new `Sound` per call on a part | 3D | per call | Sfx | destroyed on `Ended` or after 8 s |
| `ZombieAudio` | `Growl` loop per zombie torso | 3D | 10 / 120 | Sfx | pitch 0.55..0.85, staggered start |
| `ZombieAudio` | idle moans | 3D | 10 / 90 | Sfx | one random body every 5..13 s, max 6 candidates |
| `ZombieAudio` | alert barks | 3D | 10 / 120 | Sfx | up to 5 bodies within 120 studs when aggro flips |
| `ZombieAudio` | bite | 3D or 2D | 6 / 70 | Sfx | nearest body within 14 studs else 2D at 80 % |
| `ZombieAudio` | `HordeWalla` loop | 2D | - | Sfx | volume by count within 160 studs, full at 12 |
| `WorldSfx` | `HangarRoomtone` loop | 2D | - | Sfx | hub only |
| `WorldSfx` | `FireCrackle` loops on `FireAnchor` parts | 3D | 40 / 320 | Sfx | first 10 anchors of the diorama |
| `WorldSfx` | `distant_boom` | 3D | 200 / 2200 | Sfx | every 20..60 s in the hub or the City biome |
| `WorldSfx` | radio | 3D | 12 / 90 | Sfx | hangar `Cabin` part, hub only |
| `WorldSfx` | `SoundService.AmbientReverb` | global | - | - | `Hangar` in hub, `NoReverb` in mission |
| `PlayerSfx` | `Heartbeat`, `WindInEars` loops | 2D | - | Sfx | volume by health and speed |
| `PlayerSfx` | gear rattle, land soft/hard, cloth whoosh | 2D | - | Sfx | via `play2D` |
| `PlayerSfx` | `EqualizerSoundEffect` "Concussion" | bus | - | Sfx | `HighGain` -22 dB for 1.5 s after damage |
| `CityAmbience` | 3 siren patrols on orbiting parts | 3D | 45 / 800 | Sfx | burst 9..16 s, gap 10..26 s |
| `CityAmbience` | `RotorLoop` on `PatrolChopper` | 3D | 60 / 1100 | Sfx | hub only |
| `FootstepController` | local pool of 6 on the root part | 3D | 6 / 70 | Sfx | cut at 0.32 s |
| `FootstepController` | teammate pool of 3 on their root | 3D | 6 / 90 | Sfx | stride phase from velocity |
| `BreathingController` | calm / heavy / gasp loops | 2D | - | Sfx | `RenderStepped` weights |
| `DeathController` | `DeathScream` | 2D | - | Master | bypasses the sfx group |
| `UiSfx` | hover, click, countdown, reward tick | 2D | - | Sfx | via `play2D`; also drives the chase duck |
| `DefaultSoundMuter` | Roblox character sounds | - | - | - | muted |
| `WeaponSfx` (main session) | shot takes, tails, foley, low-ammo | 2D | - | Weapons | pools of 4..8 per id, `ReverbSoundEffect` retuned by `AcousticSpace` |
| `WeaponSfx` (main session) | casing landings | 3D | 2 / 45 | Weapons | 12 attachments in Terrain |
| `WeaponSfx` (main session) | `playDistantShot` | 3D | 30 / 400 | Sfx | anchor part per shot, > 40 studs only |
| `WeaponSfx` (main session) | `playGong` | 3D | 20 / 300 | Sfx | range hits |
| `SandboxWeaponGallery` (main session) | gallery markers, sound lane | 3D | 4 / 60, 10 / 1000 | Sfx | test yard |

Zones: parts with `AcousticSpace = "Interior"` from `HangarBuilder` (hangar),
`DesertBase` (range canopy) and `Sandbox` (the test room); biome from
`Workspace.Biome` (`City`, `Forest`, `Wasteland`, `Farmstead`, `Cornfield`, set by
`ChunkSpawner`); hub or mission from `Players.LocalPlayer.FlowPhase`.

## 3. The engine

Client modules under `src/client/audio/`, config in
`src/shared/config/SpatialAudioConfig.luau` (data only, one table per class, environment
and material, plus the platform budgets), tests under `tests/audio/`.

| Module | Owns |
| --- | --- |
| `AudioMath.luau` | Pure math, no Roblox services: attenuation curves, air-absorption cutoff, distance delay, layer crossfade weights, occlusion smoothing, reflection delay and gain, dB helpers. Tested with the `luau` CLI. |
| `AudioBus.luau` | Builds the bus graph once, applies settings volumes and mute, environment reverb and slapback per bus, the duck sidechain, the master limiter. |
| `AudioEnvironment.luau` | `AcousticSpace` zone cache, biome and phase, the environment id and material profile for a position, occlusion raycasts with the per-frame budget. |
| `AudioEngine.luau` | The voice pool and the one play API, the per-frame propagation update, priorities and voice limits, distance layers, the `enabled()` flag. |
| `AudioReflections.luau` | Ray fan for gunshots and explosions, spawns delayed filtered reflection voices from the hit points. |
| `AudioDebug.luau` | The overlay: active voices with class, distance, delay, occlusion, cutoff and bus meters. |

### 3.1 Bus graph

Built once by `AudioBus.init()` under a `Folder` named `TFZ_Audio` in `SoundService`.
Every emitter and every bus listener carries `AudioInteractionGroup = "TFZ_<bus>"`, so
3D voices are mixed per bus and any engine-created default listener (empty group) never
hears them.

```
3D voice: AudioPlayer -> Wire -> AudioFilter(Lowpass12dB) -> Wire -> AudioEmitter[group TFZ_<bus>]
2D voice: AudioPlayer -> Wire -> AudioFilter(Lowpass12dB) -> Wire -> <bus fader>.Input

weapons  : AudioListener[TFZ_weapons]  -> Fader -> Reverb(env) -> Echo(slapback) -> Master
sfx      : AudioListener[TFZ_sfx]      -> Fader -> Reverb(env) -> Echo(slapback) -> Equalizer(concussion) -> Master
voices   : AudioListener[TFZ_voices]   -> Fader -> Reverb(env) -> Master
ambience : AudioListener[TFZ_ambience] -> Fader -> Compressor(duck, Sidechain <- weapons + explosion send) -> Master
music    : (2D only)                   -> Fader -> Compressor(duck, Sidechain <- same) -> Master
ui       : (2D only)                   -> Fader -> Master
Master   : Fader(masterVolume, mute) -> Limiter(MaxLevel -1 dB, Release 0.08 s) -> AudioDeviceOutput
```

The duck sidechain is a `Wire` from the weapons fader `Output` and from an explosion send
fader into the `Sidechain` pin of the two compressors (threshold -24 dB, ratio 4, attack
5 ms, release 600 ms: about -6 dB under sustained fire, per the ducking practice in 1.3).
The UI bus joins after the compressors, so it is never ducked, and before the limiter, so
it can never clip. The settings sliders drive `master`, `music` and the sfx-family
faders through the same `MusicController.setMasterVolume` / `setMusicVolume` / `setMuted`
API as today; the chase duck (`UiSfx`) keeps calling `MusicController.setDuck`, which
now scales the music fader.

The legacy `SoundGroup` tree stays, because `WeaponSfx` still plays `Sound`s through it;
`MusicController` keeps both trees at the same volumes so the mix stays consistent while
the two coexist.

### 3.2 Voice pool and play API

A voice is `{ player, filter, emitter, wireToFilter, wireOut, attachment, state }`. The
pool is built at init (48 desktop, 24 mobile) and never allocates per frame or per play:
`play` picks a free voice or steals by priority, sets `Asset`, `Volume`, `PlaybackSpeed`,
retargets `wireOut` to the emitter (3D) or the bus fader (2D), sets the emitter's
`PositionInstance` to the followed part or to the voice's own `Attachment` (moved to the
requested position), applies the class curve with `SetDistanceAttenuation`, and calls
`Play(mixerTime + delay)`.

```lua
local handle = AudioEngine.play({
    key = "zombie.idle_01",        -- AssetIds.audio path, or `id = 123456` directly
    class = "ZombieVocal",         -- SpatialAudioConfig.classes entry
    position = Vector3.new(...),   -- or follow = basePartOrAttachment
    volume = 0.4,                  -- multiplied by the class gain and the jitter
    pitch = 1,                     -- centre; the class adds its jitter
    delay = 0,                     -- extra seconds on top of the distance delay
    loop = false,
})
handle:stop(fadeSeconds?)   handle:setVolume(v)   handle:fade(to, seconds)
handle:isPlaying()          handle:setPosition(v)
```

A handle is a small reusable table tied to the voice generation, so a stale handle after
a steal is a no-op. `AudioEngine.enabled()` is `SfxConfig.SPATIAL_AUDIO`; when it is
false every wrapper in `SfxPlayer` takes the old `Sound` path unchanged.

### 3.3 Propagation per voice

Every `Heartbeat`, near voices (under 60 studs) update every frame and far voices every
fourth frame (mobile: every second and every sixth):

1. **Distance and curve.** The emitter's curve does the volume; the class table gives the
   audible range and the curve shape (`AudioMath.attenuationCurve`, section 4).
2. **Air absorption.** The filter cutoff is `AudioMath.absorptionCutoff(distance,
   strength)`: 22 kHz at the source falling to the class floor, exaggerated against
   ISO 9613-1 for readability (section 1.4).
3. **Occlusion.** `AudioEnvironment.occlusion(listener, source)` casts one ray (two for
   gunshots and explosions, the second offset 3 studs to soften edges) within the
   per-frame budget (8 desktop, 4 mobile), ignoring characters, zombies, the
   viewmodel, non-`CanQuery` parts and parts tagged `AudioTransparent`. A hit returns
   the material's transmission loss and low-pass from the material table; the value
   is smoothed with separate attack (open up in 0.12 s) and release (close in 0.25 s)
   constants so a passing door frame never clicks. Occlusion multiplies the voice volume
   and lowers the cutoff (min with absorption).
4. **Environment.** The source's zone versus the listener's zone: a source inside an
   interior heard from outside (or the reverse) gets the doorway loss (-9 dB, 2.5 kHz),
   fading over 0.3 s as either crosses the boundary. The listener's environment drives
   the bus reverb and slapback (section 3.5).
5. **Delay.** One-shots start at `mixerTime + distance / 1225 + extra`. Loops start at
   once (a growl that began 200 studs away is not a transient).
6. **Layers.** A class with `layers = { close, mid, far }` plays the layers whose
   crossfade weight is above 0.02 at trigger time (one-shots) or every update (loops),
   from `AudioMath.layerWeights`. A missing key falls back to the nearest existing one.
7. **Culling.** A voice beyond its class range plus 10 % is stopped (one-shot) or muted
   and skipped (loop) until it comes back.

### 3.4 Reflections

For classes with `reflections = true` (other players' gunshots, explosions, and the
weapon-side own-shot environment layer the main session will add): at trigger time
`AudioReflections.fire(position, class, key)` casts a fan of rays from the source
(6 desktop, 3 mobile: every 60 or 120 degrees around the horizontal plus one at 30
degrees up, range 140 studs, the same filter as occlusion). Each hit within range makes a
reflection voice at the hit point, delayed by `(|source-hit| + |hit-listener| -
|source-listener|) / 1225`, at a gain of `reflectionGain * material.reflect /
(1 + pathLength / 60)`, low-passed by the material and by the path length, pitched down
by 4 % so it never doubles the direct sound. Hits closer than 8 studs to one another
merge, delays under 12 ms (fused with the direct sound by the precedence effect) are
dropped, and at most 12 (mobile 6) reflection voices play at once, oldest stolen first.
Open field: no hits, no reflections. Street canyon: two slaps 40-120 ms apart from the
facades. Interior: many short reflections that the bus reverb already covers, so
interiors cap at two.

### 3.5 Environments

`AudioEnvironment.at(position)` returns one of `Interior`, `Hangar`, `Street`, `Forest`,
`Open`:

| Environment | From | Reverb (decay s / wet dB / high cut Hz / early delay ms) | Slapback |
| --- | --- | --- | --- |
| `Hangar` | hub phase, inside the hangar zone | 2.6 / -10 / 5000 / 30 | none (reverb carries it) |
| `Interior` | any other `AcousticSpace = "Interior"` zone | 1.4 / -12 / 4000 / 12 | none |
| `Street` | mission, biome `City` | 0.9 / -20 / 6000 / 40 | 85 ms, feedback 0.18, wet -16 dB |
| `Forest` | mission, biome `Forest` or `Cornfield` | 0.6 / -22 / 3500 / 25 | none |
| `Open` | mission, `Wasteland` and `Farmstead`, hub outdoors | 0.3 / -30 / 3000 / 10 | none |

The values are applied to the bus `AudioReverb` / `AudioEcho` with a 0.5 s glide when the
listener changes environment. Per-source tails beyond that come from recordings (the
weapon tails already exist as `tail_open` / `tail_interior`; see the weapons doc for the
missing `tail_street` and `tail_forest`).

### 3.6 Mobile and budgets

`AudioEngine` picks the profile from `UserInputService.TouchEnabled and not
KeyboardEnabled`:

| Budget | Desktop | Mobile |
| --- | --- | --- |
| Voice pool | 48 | 24 |
| Occlusion rays per frame | 8 | 4 |
| Reflection rays per shot | 6 | 3 |
| Reflection voices alive | 12 | 6 |
| Near voice update | every frame | every 2nd frame |
| Far voice update (> 60 studs) | every 4th frame | every 6th frame |
| Per-class voice limits | as in the class table | halved, minimum 2 |

Estimated cost: 48 voices x 2 wires x 3 nodes is 240 instances at init, one
`SetDistanceAttenuation` table write per play, one filter frequency and one volume write
per updated voice, and at most 8 raycasts per frame. The per-frame Luau work is the
distance loop over the pool, well under 0.1 ms.

## 4. Per-class parameters

Ranges are in studs (1 stud = 0.28 m). "Curve" names an `AudioMath` shape: `natural`
(inverse with a hold radius, tapering to zero at range), `power` (loud sources: slower
fall, audible near the full range), `linear` (loops that should stay present, then fade).
"Air" is the absorption strength (1 = the exaggerated ISO curve of section 1.4, 0 = none).
"Occl" scales the material loss. Priority is 0..100, higher survives a steal.

| Class | Bus | Range | Curve | Air | Occl | Reflections | Priority | Voice limit (desktop) | Delay | Layers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `OwnGunshot` (main session) | weapons | 2D close layers; environment layer 3D at the muzzle | - | 0 | 0 | yes (env layer) | 100 | 8 | no | close 2D; env 3D |
| `GunshotRemote` | weapons | 1400 | power | 1.0 | 1.0 | yes | 90 | 8 | yes | close 0..60, mid 40..350, far 250..1400 |
| `Explosion` | sfx | 2600 | power | 1.0 | 0.7 | yes | 100 | 4 | yes | close 0..120, far 90..2600 |
| `ZombieVocal` | voices | 140 | natural | 0.6 | 1.0 | no | 60 | 8 | yes | - |
| `ZombieLoop` (growl) | voices | 90 | natural | 0.6 | 1.0 | no | 40 | 10 | no | - |
| `ZombieFootstep` | sfx | 50 | natural | 0.4 | 1.0 | no | 25 | 8 | no | - |
| `PlayerFootstep` (local) | sfx | 70 | natural | 0.2 | 0 | no | 35 | 6 | no | - |
| `TeammateFootstep` | sfx | 90 | natural | 0.4 | 1.0 | no | 30 | 6 | no | - |
| `Impact` (bullet, ricochet) | sfx | 120 | natural | 0.8 | 1.0 | no | 50 | 8 | yes | - |
| `Casing` (main session) | sfx | 45 | natural | 0.3 | 0.5 | no | 20 | 12 | no | - |
| `Bite` | voices | 70 | natural | 0.3 | 0.5 | no | 80 | 2 | no | - |
| `AmbienceSource` (fire, siren, radio, rotor) | ambience | 320..1100 per source | linear | 0.7 | 0.6 | no | 30 | 10 | no | - |
| `AmbienceBed` (roomtone, walla, wind, heartbeat, breath) | ambience | 2D | - | 0 | 0 | no | 30 | 8 | no | - |
| `Reflection` | bus of the parent class | 300 | natural | 1.0 | 0.5 | no | 45 | 12 | path delay | - |
| `Music` | music | 2D | - | 0 | 0 | no | 100 | 2 | no | - |
| `UI` | ui | 2D | - | 0 | 0 | no | 100 | 4 | no | - |
| `Scream` (death) | voices | 2D | - | 0 | 0 | no | 100 | 1 | no | - |

The main-session classes (`OwnGunshot`, `Casing`) are defined in the config so the
weapon code can adopt them without a config change.

## 5. Feature flag and migration

- `SfxConfig.SPATIAL_AUDIO = true` on this branch. `AudioEngine.init()` builds the graph
  only when it is on; every consumer asks `AudioEngine.enabled()` and otherwise runs the
  code it has today. `SfxPlayer.play2D` and `play3D` keep their signatures and forward to
  the engine (class `Generic2D` / `Generic3D`, range from the old max rolloff), so call
  sites this branch does not touch (`WeaponSfx.playDistantShot`, `playGong`,
  `SandboxWeaponGallery`) already propagate.
- `SfxConfig.ACOUSTIC_SIMULATION = false`: the built-in beta simulation instead of the
  engine's rays and bus reverb (section 1.1).
- Order of work on this branch: design doc; `AudioMath` and its tests; config; bus,
  environment, engine, reflections, debug; then the consumers one by one (`ZombieAudio`,
  `WorldSfx`, `PlayerSfx`, `CityAmbience`, `FootstepController`, `BreathingController`,
  `DeathController`, `UiSfx`, `MusicController`), each with the legacy branch kept.
- The main session merges the branch, runs the Studio test plan (section 6), and moves
  `WeaponSfx` per [weapons-integration.md](weapons-integration.md). Once the weapons are
  on the engine the `Weapons` `SoundGroup`, its `ReverbSoundEffect` and
  `SoundService.AmbientReverb` can go, and `SfxConfig.SPATIAL_AUDIO` can be removed with
  the legacy branches.

## 6. Studio test plan

Run in the Studio test yard (`DevConfig.SANDBOX.enabled = true`, Play spawns in it).
The main session adds one key for the overlay: in `SandboxInput`,
`elseif input.KeyCode == Enum.KeyCode.N then AudioDebug.toggle()`. The overlay lists
every live voice with class, bus, distance, delay, occlusion, cutoff and volume, plus
the bus meters and the listener environment. Every item names what to hear, the knob if
it is wrong, and what the overlay should show.

1. **Sound lane, distance (key B on the listening pad).** Speakers at 25, 50, 100, 200
   and 400 studs each play a rifle shot, a bark and a boom. Hear: the shot arrives
   later at each speaker (0.02, 0.04, 0.08, 0.16, 0.33 s), gets duller with distance
   (bark still bright at 50, dull at 200, a thump at 400) and drops smoothly with no
   step between speakers. Knobs: `classes.<class>.range` and `.curve` for the level,
   `classes.<class>.air` and `ABSORPTION.exaggeration` for the dullness,
   `SPEED_OF_SOUND_STUDS` for the delay. Overlay: one voice per speaker with the listed
   delay and a cutoff falling from 22 k to under 3 k.
2. **Sound lane, occlusion.** The sixth speaker sits 50 studs away behind a concrete
   wall. Hear: quieter and muffled compared with the open 50 stud speaker; step
   sideways until the wall clears the line and the sound opens up over a quarter second
   with no click. Knobs: `materials.Concrete.loss` and `.cutoff`, `OCCLUSION.attack` and
   `.release`. Overlay: occlusion 1.0 behind the wall, 0.0 beside it, moving smoothly.
3. **Sound lane, reflections.** Stand on the pad; the yard's low walls and the material
   walls are within reflection range. Hear: after each shot one or two short slaps from
   the direction of the nearest walls, later than the shot; walk into the open middle
   of the yard and they disappear. Knobs: `REFLECTIONS.range`, `.rays`, `.gain`,
   `materials.<m>.reflect`. Overlay: `Reflection` voices with their delay in ms, none in
   the open.
4. **Interior room.** Walk into the concrete room; the seventh speaker inside plays last.
   Hear: the tail lengthens (1.4 s decay) when you step through the doorway and the
   yard sounds outside go dull; from outside, the speaker inside is muffled and opens
   up as you cross the door line. Knobs: `environments.Interior.*`,
   `ENVIRONMENT.doorwayLoss` and `.doorwayCutoff`. Overlay: environment `Interior`, the
   inside voice with the doorway flag when you are outside.
5. **Material walls (west).** Shoot each wall from behind the row so the impact is on
   the far side, then from the front. Hear: impacts through concrete are the dullest,
   through wood mid, through glass bright but quiet. Knobs: `materials.*`. Overlay:
   impact voices with the material name.
6. **Zombie wave (key G).** Six zombies chase from 60 studs. Hear: growls and barks
   come from their bodies, close ones bright and loud, the far ones behind you dull;
   with the wave at the door of the room from inside, the pack is muffled until they
   enter; no growl cuts off mid-word when the pool is full (the oldest far voice goes
   first). Knobs: `classes.ZombieVocal` / `ZombieLoop` limits and priorities,
   `POOL_SIZE`. Overlay: voice count under the pool size, steals listed.
7. **Footsteps on the surface strips (east).** Walk each strip. Hear: your own steps
   stay dry and close (no delay, no filter); a teammate's steps (second client, or the
   gallery walkers) get quieter and duller with distance and are occluded by the room
   walls. Knobs: `classes.PlayerFootstep`, `TeammateFootstep`, `ZombieFootstep`.
8. **Built-in simulation A/B.** Set `SfxConfig.ACOUSTIC_SIMULATION = true`, repeat
   items 2 to 4. Hear: Roblox's own occlusion and reverb instead of ours; note which
   reads better and whether the beta costs frames on the FPS counter. Overlay: the
   occlusion column reads `engine`.
9. **Mix.** Fire a magazine next to the fire anchors of the diorama (hub) or with the
   siren patrols playing. Hear: ambience and music dip about 6 dB under fire and come
   back over half a second; UI clicks in the settings menu are never dipped; nothing
   clips when a wave, a shot and an explosion coincide. Knobs: `DUCK.*`, `LIMITER.*`.
   Overlay: the ambience and music meters dip while the weapons meter is hot.
10. **Settings.** Move the master, music and mute controls. Hear: both the engine mix
    and the legacy weapon sounds follow them together.
11. **Mobile profile.** In Studio's device emulator (a phone preset) repeat items 1, 3
    and 6. Hear: the same picture with fewer reflection slaps; no stutter on the wave.
    Overlay: profile `mobile`, pool 24, rays 4.
12. **Legacy path.** Set `SfxConfig.SPATIAL_AUDIO = false`. Hear: the sounds from
    before this branch, unchanged, so the flag is a safe rollback.

## 7. Checks

Run before every commit on this branch:

```
selene src/                    # std: selene generate-roblox-std (roblox.yml is git-ignored)
python3 tools/validate_api.py
rojo build -o build.rbxlx      # needs ServerPackages (wally install) to exist
luau tests/audio/run.luau      # pure-math tests, standalone Luau CLI
```

`tests/audio/run.luau` requires `AudioMath` by relative path and prints one line per test
group; it exits non-zero on the first failing assertion.

## 8. Open questions for the owner

Listed with the reasonable call made on this branch (also in [[Decisions]] in the vault):

1. **Built-in acoustic simulation or our rays.** Chosen: our rays, because the engine
   feature is a client beta. Flip `SfxConfig.ACOUSTIC_SIMULATION` to compare in the yard.
2. **Reflection assets.** Chosen: reuse the shot asset, filtered and pitched, until
   dedicated slap recordings exist (candidates in the weapons doc).
3. **Duck depth.** Chosen: about -6 dB under fire with a 600 ms release; the compressor
   values are in `SpatialAudioConfig.duck` for a quick retune.
4. **Air absorption exaggeration.** Chosen: 6x the ISO 8 kHz figure (section 1.4),
   which lands on Hunt's 30 / 70 m bands; `ABSORPTION.exaggeration` retunes it.
5. **Mobile pool.** Chosen: 24 voices; if the yard's zombie wave steals audibly, raise it
   before lowering the ray budget.
