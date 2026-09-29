# Cloud task: stage 2, natural sound propagation (spatial audio)

You are a Claude Code cloud session working directly on this repository. A second session
(the "main session") works at the same time on the owner's Mac with Roblox Studio attached
and handles everything that needs Studio. You cannot run Roblox, so your job is the part
that can be built and checked without it: research, design, the audio engine code, its
integration into the non-weapon sound consumers, tests of the pure logic, and a precise
Studio test plan. The main session merges and verifies your branch in Studio.

## Goal

Every sound in the game has to propagate through space the way it does in the best modern
shooters (reference: Call of Duty: Modern Warfare 2019 and later, Battlefield, Hunt:
Showdown; on Roblox, the best FPS games). The owner's complaint today: sounds are muffled,
"as if indoors", with no natural propagation. That applies to everything: gunshots,
zombie groans and screams, footsteps, impacts, explosions, fire, sirens.

What "natural" means here, at minimum:

- distance attenuation curves per sound class (not one rolloff for everything);
- air absorption: high frequencies fall away with distance;
- speed of sound: a distant shot or explosion arrives late (343 m/s; the project uses
  1 stud = 0.28 m, see `METRE` in `src/shared/config/WorldMeshConfig.luau`, so about
  1225 studs/s);
- occlusion and obstruction: a sound behind a wall or a building is muffled and quieter,
  smoothly, and opens up again when the path clears;
- environment: open field, street canyon (slapback from facades), forest, interior. Tails
  and reflections depend on where the source and the listener are. Interiors are marked
  today by parts with the attribute `AcousticSpace = "Interior"` (DesertBase,
  HangarBuilder, Sandbox); biomes come from `src/shared/config/LocationsConfig.luau`;
- reflections for loud events (gunshots, explosions): echoes that come from the actual
  surfaces around, with their delay, direction and filtering (the MW2019 approach: rays
  find surfaces, reflection sounds play from those points);
- a mix that holds up: bus hierarchy, a master limiter, ducking (own gunfire and nearby
  explosions push ambience down, UI is never ducked), voice limits and priorities.

## Ownership (avoid merge conflicts)

The main session is editing these right now. Do not modify them; if they need changes,
describe the exact change in your docs instead:

- `src/client/systems/WeaponSfx.luau`, `WeaponVfx.luau`, `WeaponController.luau`,
  `PackViewmodel.luau`, `Viewmodel.luau`, `ViewmodelClipPlayer.luau`,
  `SandboxInput.luau`, `SandboxWeaponGallery.luau`
- `src/server/systems/Sandbox.luau`, `SandboxGallery.luau`
- `assets/manifest.json`, `src/shared/config/AssetIds.luau`, `assets/LICENSES.md`,
  `assets/NEEDED.md`
- `src/shared/config/WeaponsConfig.luau`, `ViewmodelPackConfig.luau`

Everything else is yours to change when the task needs it (new modules, `SfxPlayer`,
`ZombieAudio`, `WorldSfx`, `PlayerSfx`, `CityAmbience`, `UiSfx`, `MusicController`,
`FootstepController`, `BreathingController`, `DeathController`, `SfxConfig`,
`SettingsApply`, `init.client.luau`, the wiki).

## Step 0: read first

`CLAUDE.md`, `AGENTS.md`, `docs/asset-policy.md`, `wiki/project-zprun/Architecture.md`,
`Gameplay Systems.md`, `Decisions.md`, `Roadmap.md`, `Progress.md`, then every sound
consumer listed above plus `src/shared/config/SfxConfig.luau`, `DevConfig.luau` and
`GameConstants.luau`. Map every place a sound is created or played (class, 2D or 3D,
rolloff, SoundGroup) into a table; it goes into the design doc.

## Step 1: research

Use WebSearch and WebFetch. Sources to cover, at least:

1. The Roblox Audio API as it is today (2026): `AudioPlayer`, `AudioEmitter`,
   `AudioListener`, `Wire`, `AudioDeviceOutput`, `AudioFader`, `AudioFilter`,
   `AudioEqualizer`, `AudioReverb`, `AudioEcho`, `AudioCompressor` (sidechain),
   `AudioLimiter`, `AudioAnalyzer`, `AudioInteractionGroup`, distance and angle
   attenuation (`SetDistanceAttenuation` and friends), `SoundService` settings such as
   `DefaultListenerLocation`, and any built-in acoustic simulation (geometry-based
   occlusion or reverb) Roblox has shipped or put in beta. Pages:
   create.roblox.com/docs (engine reference and the audio guides) and the Roblox DevForum
   announcements. Prefer an engine feature over a hand-rolled one when it exists and is
   out of beta.
2. Verify every class, property, method and enum you use against the official API dump
   (the same one `tools/validate_api.py` downloads:
   `https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json`).
   Nothing goes into the code that you could not confirm there.
3. How AAA shooters build gunshot and environment audio: MW2019 and later (layered
   perspectives close / mid / far crossfaded by distance, the reflections system,
   occlusion, HDR mixing and ducking), plus Battlefield and Hunt: Showdown. GDC talks,
   interviews, articles.
4. Physics you implement: atmospheric absorption per frequency band (ISO 9613-1 figures,
   and how games exaggerate it for readability), inverse-distance law and where games
   depart from it, street-canyon slapback timings.

Write every fact you rely on with its source URL into the design doc.

## Step 2: design doc (push it first)

`docs/audio/spatial-audio.md`: research summary, the sound-consumer map from step 0, the
bus graph, the per-class parameter table (audible range, attenuation curve, air
absorption, occlusion strength, reflections on or off, priority, voice limit, bus), CPU
and voice budgets for desktop and mobile, the feature flag, and the migration plan. Commit
and push it before you write engine code, so the owner can read the direction early.

Starting classes (refine them with the research): own gunshot (2D close layers, the
environment part in 3D), other players' gunshots (3D, distance layers, audible very far),
explosion, zombie vocal, zombie and player footsteps, bullet impact and ricochet, casing,
positional ambience (fire, siren, radio), ambience beds, music, UI.

## Step 3: engine

New client modules (for example under `src/client/audio/`; names are yours, document
them):

- bus graph built once: master with limiter into the device output; sub buses (weapons,
  sfx, voices, ambience, music, ui) with faders the settings sliders drive (the master,
  music and sfx volumes that `MusicController` and `SettingsApply` handle today);
  sidechain ducking;
- an emitter pool and one play API: asset id or `AssetIds` key, a position or an
  Attachment/BasePart to follow, the sound class, volume and pitch variation, optional
  start delay; it returns a handle (stop, fade, set volume). No per-frame allocations;
- per-voice propagation: the class attenuation curve, air-absorption low-pass by
  distance, distance delay, occlusion with smoothing (rays from listener to source,
  spread over frames with a per-frame ray budget, cheaper updates for far voices),
  environment from `AcousticSpace` zones and the biome;
- reflections for gunshots and explosions: a few rays find nearby surfaces within a
  range; each hit plays a delayed, filtered reflection from that point; open fields get
  none, streets get slapback;
- distance layers: a class may list close / mid / far keys and the engine crossfades
  them by distance; a missing key falls back to the nearest one that exists;
- keep all pure math (curves, absorption, delay, crossfades, occlusion smoothing) in a
  module without Roblox services, and test it with the standalone `luau` CLI under
  `tests/audio/` (document the command in the design doc).

Everything sits behind a flag (`SfxConfig.SPATIAL_AUDIO`, default `true` on your branch)
with the legacy path intact until the owner signs off in Studio.

## Step 4: integration

Move the non-weapon consumers onto the engine: `ZombieAudio`, `WorldSfx`, `PlayerSfx`,
`CityAmbience`, `FootstepController`, `BreathingController`, `DeathController`, `UiSfx`
(2D on the ui bus), `MusicController`. Keep `SfxPlayer`'s public functions as thin
wrappers so any call site you did not touch keeps working.

Weapons stay with the main session. Write `docs/audio/weapons-integration.md` with the
exact changes for `WeaponSfx` (own shot: which layers stay 2D, which go through the
environment and reflections; other players' shots through distance layers and delay;
tails by environment) and which recordings the weapon classes still need (for example
mid and far perspectives), with candidate sources and licences.

## Step 5: checks you can run

Before every commit: `selene src/` (generate the std with `selene generate-roblox-std`
if it is missing), `python3 tools/validate_api.py`, `rojo build -o build.rbxlx` (tools in
`rokit.toml`), and the `luau` tests. Fix what you introduce. If a tool cannot be installed
in your environment, say so in the PR instead of skipping silently.

## Step 6: Studio test plan

In the design doc, a checklist the owner and the main session run in the Studio test
yard (Play starts in it; `DevConfig.SANDBOX.enabled`): the sound lane (key B plays
speakers at 25, 50, 100, 200 and 400 studs, plus one behind a wall), the interior room,
the material walls, zombie waves (key G), footsteps on the surface strips. For each:
what should be heard, which parameter to turn if it is not, and a debug view if you add
one (for example an overlay listing active voices with distance, delay, occlusion and
filter cutoff). If you need a key or a hook in the test yard, write a separate debug
module and put the one-line hook the main session should add into the PR description.

## Step 7: vault and PR

Update `wiki/project-zprun` (English): the audio part of Architecture, Gameplay Systems,
Decisions (why the Audio API, why these curves), Progress (branch status). Then open a
pull request to `main` from branch `cloud/spatial-audio`: what is done, what needs a
listen in Studio, open questions. Push often; never push to `main`.

## Rules

- `CLAUDE.md` and `AGENTS.md` apply. Commits and the PR carry no co-author trailer and no
  mention of Claude or AI.
- No synthesized or generated audio. Audio files are git-ignored; they are uploaded only
  by the owner through `assets/manifest.json` -> `scripts/upload_assets.py`. Never invent
  or copy an asset id; if the design needs recordings, list them in the docs with
  candidate CC0 / CC BY sources.
- Never invent API names; confirm them in the API dump and the docs.
- Luau `--!strict`, the codebase's style and comment density, no dead code.
- Mobile budget: cap active emitters and rays per frame, stagger updates, cull what is
  out of range.
- When a decision is the owner's (a trade-off with no clear answer), make the reasonable
  call, write it in Decisions, and list it in the PR.

## Done means

The design doc and the research are pushed; the engine and the integration build with
the checks green; the pure-math tests pass; the weapons integration doc and the Studio
test plan are complete; the vault is updated; the PR is open with a clear list of what
the owner has to listen to.
