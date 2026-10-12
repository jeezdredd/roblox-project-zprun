# AV polish tasks

Owner: producer. Written 2026-10-12. Inputs: production/project-stage-report.md, production/claude-desktop-tasks.md (T1-T22), the producer draft and the reviewer's critique of 2026-10-12 (verdict REVISE, 31 required changes), and spot checks in the repo the same day.

Status: PROVISIONAL. The five domain audits returned empty. The reviewer found failed premises in the camera, VFX and zombie animation areas (bob already exists, no ragdoll anywhere), so those briefs open with "Verify first". Owner decision pending: rerun the camera, VFX and zombie-animation audits before M2 sprint planning.

Target: animation, audio and visuals at the level of Call of Duty: Modern Warfare (2019) presentation, with TTK Testing by Sable Digital as the Roblox weapon-feel benchmark. The milestone plan and exit criteria are in wiki/project-zprun/Roadmap.md; sprint 1 is production/sprints/sprint-01.md.

## Shared AV rules block (paste with every A-task, after the shared rules block from production/claude-desktop-tasks.md)

```
Asset rules: any technique is allowed (Studio MCP generate_mesh / generate_material / generate_texture, Blender MCP, licensed packs, generated audio) if the result passes a look or listen in a Studio playtest. Every asset: manifest entry with source and licence, plus "generator" and "terms" for generated assets -> scripts/upload_assets.py -> scripts/sync_configs.py -> assets/LICENSES.md. Ids only from real uploads. Nothing extracted from another game. Reference frames from MW2019 or TTK never enter the repo: cite a public video and a timestamp instead.
Line numbers: line references in older briefs predate commit 3e0ab9c (comment strip). Locate code by symbol name, never by line number.
Studio lane: only the task holding the Studio lane drives Studio MCP and rojo serve. Code lanes finish with all checks green and hand over a short verification note for the Studio lane.
Asset lane: author assets in parallel, but only one task at a time runs the ingest step (assets/manifest.json, src/shared/config/AssetIds.luau, assets/LICENSES.md, assets/NEEDED.md). Queue for it.
Viewmodel work: only in the main checkout or in a worktree made by scripts/worktree_setup.sh (A2).
Owner verdicts: every look or listen pass is recorded in its row of docs/av/vertical-slice-bar.md with the date, pass or fail, and the capture filename (or "live listen").
Captures: written under docs/av/captures/, which is gitignored. Never commit captures.
Low tier: every new VFX, light or audio voice declares its Low tier value in config next to its High value, even before A39 tunes them.
```

## Measurement methods (use these wherever an accept line names them)

| Measure | Method |
| --- | --- |
| InstanceCount flat | Stats.InstanceCount sampled once per second for 30 s of sustained fire after a 10 s warm-up; max and min within 2 percent of the mean |
| Server step cost | `debug.profilebegin` label read in MicroProfiler, or an `os.clock` accumulator averaged over 600 frames; T14 picks one and every later task reuses it |
| Loudness | integrated loudness with ffmpeg loudnorm (print_format json) run from tools/audio_build; families or buses compared in LU |
| Frame-rate independence | the same motion run at 30 and 144 fps in a Luau test; amplitude within 10 percent |
| UI text size | smallest run HUD or menu text at least 24 px at 1080p in the Studio console emulator |
| Owner look or listen | verdict row in the bar document, as in the rules block |

## Single-writer map

One task at a time per row. Everything else runs in parallel.

| Shared code | Writers, in order |
| --- | --- |
| WeaponService | T1, T3a, T13 |
| DistanceTracker, RunEconomy | T2, T11, T3b |
| DeathService | T2, T4 |
| AmmoCrates | T2, T3a |
| ZombieAI | T9, T16, T20, then the split modules per A20 and A21 |
| ZombieAnimator | T16, A20, A34 |
| ZombieVfx | T17a, T15, A21, A26 |
| ZombieAudio | T17a, A23 |
| WeaponVfx | T17a, T17b (split), T15, A24, A25 |
| WeaponSfx, OwnGunshot class | T17a, A7b, A9, A33 audio sessions |
| SfxConfig, SpatialAudioConfig, AudioBus | A7a, A8, A9, A23, A39 |
| CameraEffectsController, CameraConfig | A14, A33 feel sessions |
| Viewmodel, ViewmodelConfig, ViewmodelPackConfig, ViewmodelClipPlayer | A15, A16, A17, A18, A19, A32, A33 |
| LightingConfig, LightingDirector | T15, A27, A38 lighting sessions |
| ChunkFactory, DressingConfig | T15, A28, A29, A38 material sessions |
| PostFx | T15, A30, A31 |
| SettingsConfig, SettingsGui | A14, T15, T7a, T7b |
| docs/av/vertical-slice-bar.md | A4a, A4b, A4c (verdict rows are appended by any task) |
| assets/manifest.json and the generated files | the asset lane, one ingest at a time |

## Amendments to T briefs (apply when pasting the T brief)

- T2: owner step. The "non-Studio server" check needs a published private test. Studio-lane agents verify the clamp in Studio; the owner runs the live check.
- T3 splits in two. T3a: PerkEffects (new), PerkService, SkillEffects, PerksConfig, WeaponService, AmmoCrates, health and reload caps; accept is every perk except Sprinter measurable, reload multiplier >= 0.6, max health <= 180. T3b: the Sprinter speed path in DistanceTracker after T11, plus the caps table in wiki Run Economy.md. If T3a registers a client module in src/client/init.client.luau, it waits for T5.
- T1, T4: the live receipt and the non-Studio checks are owner steps.
- T7 splits in two. T7a gamepad and console menus (M3), including gamepad reachability of the existing credits panel in SettingsGui. T7b touch controls (M4).
- T9: read "running straight with no input" as "auto-running straight with no steering input". The game auto-runs, so this is D1's running player.
- T12 splits in three: T12a squad scaling, T12b spectate, T12c squad goal.
- T14: owner step for the MicroProfiler capture. T14 also fixes the server step cost method above.
- T15 moves to the first M2 sprint. It writes the light budget rule: at most 12 live PointLights on High with 6 chunks ahead, of which 2 are reserved for transient lights (muzzle flash, explosions) owned by A24.
- T17 splits in two. T17a: pools and client scans as briefed. T17b: split WeaponVfx (1133 lines) into muzzle, impact, casing and tracer modules behind the same facade, before A24.
- T20 moves to M2, right after T16 and before A20.
- T21: also strip the "never synthesized" and "generated speech is banned" wording from wiki Roadmap.md if the roadmap rewrite has not already done so.

## M1 Secure foundation

### A1. Align asset guidance with policy 2026-09-07 and record generator provenance
```
Context: docs/asset-policy.md (2026-09-07) allows generated audio, motion, models and textures. scripts/sync_needed.py still writes "Never synthesized" (hit and kill marker hints), "Never generated speech" (announcer hints) and "no synthesis" in the NEEDED.md header. The manifest has no field for the generator service or its terms.
Do: rewrite those hints and the header to match the policy, adding a generated option where it fits (announcer lines from a voice service with commercial terms, marker ticks). Add optional manifest fields "generator" and "terms" (service name and terms version or date); make scripts/sync_configs.py print them in assets/LICENSES.md. Studio MCP generate_* output is recorded as generator "Roblox AI (Studio MCP <tool>)" and terms "Roblox Terms of Use, <date read>"; do not claim ownership wording beyond what A3 confirms. Update wiki Assets Pipeline.md. Do not edit wiki Roadmap.md.
Accept: python3 scripts/sync_needed.py regenerates NEEDED.md with none of the old wording; a fixture manifest row with generator and terms renders in LICENSES.md (test in tests/credits/run.py or a new tests/ suite); every tests/*/run.luau and tests/*/run.py passes.
Est: 1 / 1.5 / 2.5 days.
```

### A2. Worktree setup that carries the gitignored Fab content
```
Context: .gitignore lists assets/fab/ and src/shared/fab/ with a trailing slash, which matches directories only. A git worktree lacks the Fab packs, and PackViewmodel loads viewmodel_clips then fab, so viewmodel work tested in a worktree falls back to the wrong rig. A symlink is a file to git, so a symlinked assets/fab would show as untracked and could be staged.
Do: add slash-less ignore patterns assets/fab and src/shared/fab next to the existing ones, and the same for any other gitignored local input the build reads. Add scripts/worktree_setup.sh <path> <branch> that creates the worktree and symlinks those inputs from the main checkout. Document it in wiki Development Policy.md.
Accept: a worktree made with the script passes rojo build; in Studio the rifle draws the Fab pack; git status --porcelain in the fresh worktree prints nothing.
Est: 0.5 / 0.5 / 1 day.
```

### A3. Generation capability probe and upload quota check
```
Context: the AV plan leans on Studio MCP generate_mesh, generate_material and generate_texture, and on about 40 audio uploads in M2. Neither has been checked in this Studio build or account.
Do (Studio lane, owner present for the account check):
- List the Studio MCP tools actually exposed. For each generate_* tool, make one throwaway asset and record whether the output gets an uploadable or persistent asset id, its resolution and format, and whether it carries alpha.
- Read the current Roblox terms for AI-generated content and record the exact wording that applies to ownership and commercial use; A1 cites it.
- Owner reads the account's audio upload allowance in the Creator Dashboard (30-day quota, ID verification state).
- If the quota is below the M2 need, write the fallback: pack variants into one file and play them as AudioPlayer playback regions.
Write the findings to docs/av/generation-capabilities.md. No production assets.
Accept: the document answers each question with a date; the M2 asset plan is marked feasible, or adjusted.
Est: 0.5 / 0.5 / 1 day.
```

### A4. Vertical slice quality bar (three sessions: A4a, A4b, A4c)
```
Context: M2 needs a checklist the owner can score in one playtest. Wiki Research AAA on Roblox.md holds a frame-by-frame TTK breakdown. Open owner calls that change the rows: D-AV2 (slice rifle pack), ADS (in or out).
Do: write docs/av/vertical-slice-bar.md, at most 30 rows in total, each tagged P0 or P1, each with a pass rule, the camera spot or listening spot, the reference (public video plus timestamp), the A-task that delivers it, and an empty verdict column.
- A4a: weapon feel and camera rows (draw, first raise, idle, sway, move tilt, fire, recoil and recovery, reloads tactical and empty, sprint in and out, wall pullback, bob, breath, shake, FOV kick, weapon surface quality).
- A4b: audio rows (close, mech, punch, tail, mid, far, impacts, casings, dry fire, low ammo, markers, zombie voices, pursuit audio, ambience, mix loudness).
- A4c: world, effects and HUD rows (City night lighting, fog, one warm accent, foreground detail, decals, muzzle, impacts, blood, zombie skin and wounds, hit reactions, deaths, grade, hit direction, HUD) and the capture list of fixed shots that A5 will script.
Sign-off waits for D-AV2. If the owner adds ADS, A4a is reopened.
Accept: the owner signs off the document; every row names its A-task; at most 30 rows.
Est: 0.5 / 0.5 / 1 day per session.
```

### A5. Capture harness
```
Context: before and after comparisons (A6, A27, T15 "High unchanged", A38) need repeatable shots.
Do: add a Studio-only capture mode (DevConfig switch, server gated by RunService:IsStudio()) that loads a named shot from a config module: camera CFrame, frozen ClockTime, fixed run seed and biome, scripted zombie poses and positions, weapon state. Drive it from Studio MCP and save screenshots under docs/av/captures/<set>/<shot>.png. Add docs/av/captures/ to .gitignore. Seed the shot list from A4c.
Accept: the same shot captured twice gives matching frames at a glance; switching the mode off leaves the run unchanged; no capture file is tracked by git.
Est: 1 / 1.5 / 2.5 days.
```

## M2 Vertical slice: City night, Rifle, skinned zombies

Order: T9, T15, T16, T17a and T17b come first in M2. A6 runs after T9 and A5.

### A6. Slice baseline capture
```
Depends on: A5, A4 signed off, T9 merged.
Do: in the Studio lane, take every A4c capture-list shot of the current build into docs/av/captures/baseline-2026-10/. Audio rows are not captured: the owner listens live and the verdict is written into the row, or the owner records at the OS level.
Accept: every capture-list shot has a baseline file; every bar row is marked pass, fail or unknown.
```

### A7. Weapon audio listening pass and legacy removal (two sessions)
```
Context: the spatial engine plays weapons behind SfxConfig.WEAPONS_ON_ENGINE (default true). The listening pass is docs/audio/spatial-audio.md section 6 plus the checks in wiki Weapon Audio.md. The v6 gunshots are still waiting for a listen. The legacy Sound-pool branches live in WeaponSfx and SandboxWeaponGallery.
A7a (Studio lane, owner present): listen at the range, an interior room and the sound lane; tune shotVolume, the sub, duck depth and the tails in config only.
A7b (after owner approval): delete the legacy branches, the switch and dead helpers; keep the tests/audio math tests.
Accept: approval recorded in wiki Weapon Audio.md and the bar; grep finds no WEAPONS_ON_ENGINE; luau tests/audio/run.luau passes; gunshots audible from all three spots.
```

### A8. Audio mix master
```
Context: AudioBus already builds an AudioLimiter from SpatialAudioConfig.LIMITER. There is no loudness target per bus and no combat state, so every new asset drifts.
Depends on: A7a.
Do: set an integrated loudness target per bus (weapons, impacts, zombies, ambience, UI, music) and record the measured value of the current assets with the loudness method; confirm the limiter and compressor settings; add a combat mix state (ambience and music down, weapons and zombies up, with attack and release) driven by recent fire and pursuit count. Config in SpatialAudioConfig or SfxConfig.
Accept: a table of target and measured loudness per bus in wiki Weapon Audio.md; the combat state is audible in an owner A/B listen; no clipping at the limiter in 60 s of sustained fire with 30 zombies.
```

### A9. Mech, punch, dry-fire and magazine handling layers (Rifle)
```
Verify first: no mech or punch layer exists in WeaponSfx or the OwnGunshot class; which dry-fire and magazine sounds exist; the low-ammo layer already ships (wiki Roadmap Done list).
Depends on: A7b.
Do: add a mechanical action layer (bolt and receiver) and a low transient punch layer for the Rifle, a dry-fire click on an empty trigger pull, and magazine out, in and tap foley on the reload markers; keys in WeaponsConfig or SfxConfig, played through the engine class with its jitter. Source from FFSL recordings or generate. Other classes follow in A33.
Accept: owner A/B listen with the layers on and off; the per-volley cap and duck behaviour unchanged (tests/audio); each layer within 3 LU of its target in the A8 table.
```

### A10. Bullet impact and ricochet audio (asset lane)
```
Context: audio/weapons/impact_{concrete,dirt,flesh,metal,wood}_{01,02} and ricochet_01 are needed; Kenney stand-ins play today. WeaponSfx.playImpacts routes by material family.
Do: source at least 3 variants per family (asset policy audio gate): freesound CC0, Sonniss GameAudioGDC, or generated with terms recorded per A1. If A3 found a tight quota, pack the variants per family into one file with playback regions. Normalise within the class; manifest, upload, sync_configs, sync_needed. Extend the variant table if a third variant needs a key.
Accept: integrated loudness of every family within 3 LU of the others; owner listen in the yard on concrete, dirt, metal, wood and zombies; LICENSES.md lists every file; the slots are gone from NEEDED.md.
```

### A11. Distant gunshot layers (asset lane)
```
Context: audio/weapons/mid_* and far_* (8 slots) feed WeaponSfx.playDistantShot (mid 40..350, far 250..1400 studs). The NEEDED.md hints name FFSL Prepared rows cut with tools/audio_build/build_shots_v6.py.
Do: cut all 8 takes with build_shots_v6.py from FFSL, or generate them; manifest, upload, sync. Add a Studio-only test script that fires a dummy remote shooter at 30, 200 and 600 studs from the player, since MCP playtests are solo.
Accept: with the dummy shooter, the rifle reads as near, mid and far at the three distances in an owner listen; the switch points match the config ranges.
```

### A12. Hit marker, kill marker and range gong sounds (asset lane)
```
Context: audio/ui/hit_marker and kill_marker are needed (HitMarkers stays silent until filled, wiki Hit Markers.md); audio/range/gong was rejected by moderation.
Do: source or generate a short tick, a kill confirm and a steel gong; manifest, upload, sync. Config only beyond that.
Accept: markers audible on confirmed hits only; the gong plays at the desert range; moderation approved after refresh_status.py.
```

### A13. City ambience and sirens (asset lane)
```
Context: audio/ambience/city_bed and audio/city/siren_ambulance are needed; the police siren was rejected. MapAmbience crossfades beds at map boundaries.
Do: source or generate the City bed (burning city at a distance: far sirens, wind, fire crackle, no music, no voices) and two siren variants; manifest, upload, sync.
Accept: the bed plays in the City and crossfades at the boundary; within 3 LU of the ambience bus target; owner listen.
```

### A14. Living camera
```
Context: CameraEffectsController (191 lines) already has a bob (bobWeight, BOB_VERTICAL_AMPLITUDE, BOB_HORIZONTAL_AMPLITUDE), shake, recoil, impulse and fovKick. BreathingController, ExertionState and FootPlanting exist.
Verify first: whether the bob phase is tied to footfalls or to time, what breath motion the camera or Viewmodel carries today, and how recoil recovers.
Do: tie the bob phase to FootPlanting events, add an exertion-scaled breath drift, a sprint bob profile, and a recoil kick with a separate recovery spring, all frame-rate independent. Add a camera motion intensity setting in SettingsConfig (comfort). Pure math in a util with a Luau test.
Accept: the bar's camera rows pass in owner review; frame-rate independence test passes; the comfort setting at 0 removes bob and breath.
```

### A15. Procedural weapon motion layer
```
Context: TTK Testing's feel rests on viewmodel motion between clips: look sway, move tilt, jump and land, sprint in and out, and a fire-to-sprint delay. The bar has these rows; clip work (A17) does not cover them.
Verify first: which of these Viewmodel and ViewmodelConfig already apply (viewmodel drift exists since 2026-09-06), and how Stances and Wall Pullback layer on top.
Do: in Viewmodel and ViewmodelConfig, add or tune look sway with lag and overshoot, move tilt on lateral input, jump and land offsets, sprint in and out blends, and a fire-to-sprint delay; springs frame-rate independent; one config table per class, Rifle tuned. Stances and Wall Pullback keep priority.
Accept: the bar's sway and sprint rows pass in owner review; frame-rate independence test passes.
```

### A16. One arm set (Rifle)
```
Context: black camo sleeves and gloves on the AK, pistol and shotgun packs, a bare forearm with a watch on the SMG. D-AV1 picks the set, after D-AV2.
Do: after D-AV1, re-skin or swap the arm meshes so the rifle pack uses the chosen set (tools/arms_rig pipeline, SurfaceAppearance colour, normal and roughness), through the asset lane. Other classes in A33.
Accept: rifle arms match the chosen set in the yard and on the run; no wrist seam at the cuff during either reload (frame-step capture).
```

### A17. Rifle clip polish and seam check
```
Depends on: A16.
Context: the asset policy gate requires FadeTime >= 0.15, seamless loops, Transform written after the Animator pass and marker-driven audio. Open owner call: rifle empty reload 3.4 s, or reloadTimeEmpty 3.13 and ammoAddEmpty 2.40.
Do: run the gate on every rifle clip (idle, walk, sprint, fire, both reloads, equip) in the yard; fix fades, seams and marker timing in ViewmodelPackConfig and ViewmodelClipPlayer. Apply the owner's empty reload call.
Accept: frame-step captures show no bone pops; reload foley lands on its markers; the empty reload decision is in wiki Decisions.md.
```

### A18. First raise
```
Depends on: A17.
Verify first: whether the rifle pack has a first-draw or inspect clip that can serve.
Do: on the first equip per life, play the first raise from the pack's clip, or a Luau-authored pose sequence through AnimationSequencer; later equips use the normal draw. Fire is blocked until the fire-ready pose. Data in ViewmodelPackConfig.
Accept: visible on the first rifle equip after spawn and after Continue, never on swaps; owner look pass.
```

### A19. Rifle surface pass
```
Context: the TTK benchmark names weapon textures. A16 covers arms only.
Do: give the slice rifle a SurfaceAppearance set (colour, normal, roughness, metalness) with edge wear and a light grime pass, made in Blender or a licensed texture set; ingest through the asset lane. No change to the mesh or rig.
Accept: owner look pass in the yard at the bar's weapon spot under day and City night lighting; textures within the memory note in wiki Performance.md.
```

### A20. Zombie directional flinch
```
Depends on: T20 (ZombieAI split), T16.
Verify first: which hit reactions exist per skin in ZombieAnimator and ZombieHitboxes (the Ghoul has a flinch).
Do: add a directional additive flinch for body and head hits on every skinned zombie, capped per frame, chosen from 2 or more variants. Server rules unchanged.
Accept: owner look pass at 10 and 40 studs; the server step cost for zombies stays under 0.3 ms with 60 alive (T14 method).
```

### A21. Zombie death with impulse
```
Depends on: A20, T17a pools, T18 (remote hardening merged).
Context: no ragdoll exists. The server owns and recycles zombie rigs, so a death effect cannot live on the server model.
Do: on death the server fires one server-to-client event with the zombie id, hit position and an impulse vector. The client spawns a pooled local corpse clone at the rig's pose, applies the impulse (short client physics or a directional death clip), and lets it outlive the server recycle, then fades it. Variant choice plus a randomised start offset, unit-tested.
Accept: owner look pass; no synchronised deaths (test); InstanceCount flat; the server step cost target still holds.
```

### A22. Zombie skin and wound materials
```
Verify first: the current SurfaceAppearance set on each skinned zombie.
Do: bring each slice zombie skin to a full PBR set; add a wound decal or texture swap on hit regions, and a clear headshot read (decal plus blood burst sized differently from body hits). Gore toggle governs all of it.
Accept: owner look pass at 10 and 40 studs; gore off removes every wound; ingest through the asset lane.
```

### A23. Pursuit audio behind the player
```
Depends on: T9, T17a.
Do: guarantee pursuit footsteps and breath growls for the nearest N chasing zombies behind the player, with distance-driven intensity and a rear-hemisphere mix bias, within the voice caps in SfxConfig.
Accept: in a Medium run, auto-running straight with no steering input, the owner can tell by ear that a Runner closes from 40 to 10 studs; voice caps respected.
```

### A24. Muzzle flash and muzzle light (Rifle)
```
Depends on: T17b, T15 (light budget), A3.
Do: author flipbook sheets for the rifle muzzle flash front and side views, rendered in Blender to a grid sheet (2x2, 4x4 or 8x8, at most 1024 px, alpha) or taken from a licensed pack; Studio generate_texture only if A3 showed it produces alpha sprite sheets. Add a short muzzle PointLight from the 2 reserved transient lights. Wire through VfxConfig; keep the pools.
Accept: the bar's muzzle row passes in owner review; live PointLights never exceed the T15 budget; InstanceCount flat.
```

### A25. Impact puffs and sparks
```
Depends on: A24 (same module family).
Do: flipbook impact puffs per material family and sparks for metal, same sourcing rule as A24, through VfxConfig and the existing pools.
Accept: the bar's impact rows pass; emitter budget respected; InstanceCount flat.
```

### A26. Blood mist
```
Depends on: A21 (ZombieVfx).
Do: blood mist flipbook for body and head hits, sized per hit type, gore toggle respected.
Accept: the bar's blood row passes; gore off shows none; InstanceCount flat.
```

### A27. City night lighting
```
Depends on: T15, T14 baseline. Open owner call: whether ClockTime keeps sweeping inside map boundary blends.
Do: retune the City night preset (Atmosphere, ColorCorrection, Bloom, sun and moon, one warm accent per chunk) against the A5 shots. Config plus LightingDirector only; no new PointLights.
Accept: before and after captures for the City rows; owner look pass; FogBudget test passes.
```

### A28. City decals and materials
```
Context: decals still to upload and the biome strip's 25 shots are open (wiki Environment.md).
Do: fill the City decal and material gaps (Megascans pipeline, generate_material if A3 confirms it, ambientCG pattern); ingest through the asset lane; respect DressingConfig budgets.
Accept: the City biome strip shots captured; ChunkBudgetCounter within budget; every new asset in the manifest.
```

### A29. City hero props (cap 3)
```
Do: generate or model up to 3 City foreground hero props (generate_mesh or Blender, GLB to Open Cloud per tools/cube3d/README.md), placed through DressingConfig.
Accept: owner look pass in the City shots; budgets hold; manifest rows carry generator and terms.
```

### A30. Night run colour grade
```
Depends on: T15.
Do: per-phase colour grade for the City night run in PostFx, config driven.
Accept: owner look pass against the A5 shots; Low tier keeps or drops it per T15.
```

### A31. Hit direction indicator
```
Depends on: A30 (PostFx).
Do: a damage direction indicator around the crosshair from the server's damage event, config driven; gore toggle still governs blood overlays.
Accept: owner look pass; the direction is correct for hits from four sides in a Studio test.
```

## M3 Scale presentation

### A32. Known viewmodel clip defects
```
Context (wiki Progress.md): SMG ReloadEmpty magazine and rounds jump at 0.207..0.216; SMG Equip right hand and gun step at frames 18-19; shotgun shell bone slides at the loop seams.
Do: fix the keyframes or mask the joints in the clip data; verify frame by frame in the yard.
Accept: frame-step captures show no jump, step or slide.
```

### A33. Class parity (nine sessions: Pistol, SMG, Shotgun, each in three groups)
```
Context: M2 brought the Rifle to the bar.
Run per class, one group per session:
- Look: arm set (A16 method) and surface pass (A19 method).
- Feel: clip gate (A17 method), first raise (A18 method), weapon motion tuning (A15 config table).
- Sound and effects: mech, punch, dry-fire and magazine layers (A9 method), muzzle flash (A24 method).
Accept: the bar's weapon rows pass for the class in owner review; class tests pass.
```

### A34. Zombie rise, feed and Hazmat death clips
```
Owner step: download Mixamo "Zombie Stand Up" (3 variants) and "Zombie Biting Victim On The Ground".
Do: retarget with tools/animation_pipeline/retarget_mixamo.py, ingest, sync; ZombieAnimator plays them when non-zero. For the Hazmat death, retarget a Mixamo death or author one.
Accept: riser and feast formations animate in a run; corpse feeders chew; the Hazmat dies on a clip.
```

### A35. Third-person locomotion clips
```
Owner step: the Mixamo downloads in docs/animation/third-person-locomotion.md.
Do: retarget, ingest, sync; the yard gallery adopts clipSetFor.
Accept: in the yard gallery and in a dummy-teammate test, the class sets play with no fallback.
```

### A36. HUD and marker pass
```
Depends on: T7a.
Verify first: the current HUD element list and font sizes.
Do: restyle the run HUD to a minimal MW2019-level layout (ammo, credits, goals, squad) with UiTheme type tokens.
Accept: owner look pass at 16:9 and 4:3; smallest text meets the UI text size method.
```

### A37. Upgrade announcer lines (asset lane)
```
Context: audio/upgrade/announcer_upgrade_01, _02 and announcer_max are needed; the policy now allows a generated voice with commercial terms.
Do: source or generate the three lines; ingest; within 3 LU of the UI bus target.
Accept: lines play at the upgrade station; owner listen.
```

## M4 Every biome, every platform

### A38. Biome presentation pass (twelve sessions: Forest, Wasteland, Farmstead, Cornfield, each in three groups)
```
Run per biome, one group per session: lighting (A27 method), decals and materials (A28 method), ambience bed (A13 method; forest, wasteland and farmland beds are needed slots).
Accept: the bar's world rows pass for the biome; the bed crossfades at the boundary.
```

### A39. Low tier audiovisual budget
```
Depends on: T15 and the M2 to M4 AV content.
Do: on Low, reduce AudioEngine voice pools and reflection rays, flipbook resolution and emitter rates, decal counts; keep pursuit audio and markers intact.
Accept: Low tier frame time beats the T14 baseline in the phone emulator; the pursuit cue is still audible.
```

## M5 Public test readiness

### A40. Placeholder release gate
```
Context: asset policy rule 5 says refresh_status.py should fail a release while placeholders remain; NEEDED.md "Used by" is prose, so there is no slot-to-system data.
Do: add a "system" field to manifest rows (populated for needed and placeholder rows first); add --release to scripts/refresh_status.py that exits non-zero on any placeholder row and on any needed row whose system ships; add it to CI as a manual job.
Accept: a fixture with one placeholder fails; the current manifest prints the exact list.
```

## Backlog (not scheduled)

- Run music intensity layer and stingers (stem sync on AudioPlayer, generated music licence).
- Low-health desaturation with heartbeat duck.
- City hero props beyond 3.
- ADS epic, only if the owner adds ADS.
- Teammate revive, only if game design adds it.

## Draft to final ID map

| Draft | Final | Change |
| --- | --- | --- |
| A1, A2 | A1, A2 | A2 gains the ignore fix |
| A3 | A4a-c | split in three, capped at 30 rows |
| A4 | A6 | needs A5 harness and T9; audio rows live |
| A5 | A7a, A7b | |
| A6, A7, A8, A20 | A10, A11, A12, A13 | asset lane; A11 uses a dummy shooter |
| A9 | A9 | gains dry-fire and magazine foley; after A7b |
| A10 | A14 | premise fixed: bob exists |
| A13, A12, A11 | A16, A17, A18 | reordered: arms, clip gate, first raise |
| A14 | A20, A21 | split; client-local corpse clone |
| A15 | A23 | accept reworded |
| A16 | A24, A25, A26 | split; flipbook sourcing changed |
| A17 | A27 | after T15 |
| A18 | A28, A29 | split; props capped at 3 |
| A19 | A30, A31 | heartbeat to backlog |
| A21 | A36 | moved to M3 after T7a |
| A22-A25 | A32-A35 | A33 split into nine sessions |
| A26 | backlog | |
| A27, A28 | A38, A39 | A38 split into twelve sessions |
| A29 | dropped | the credits panel already exists |
| A30 | A40 | gains the "system" field |
| new | A3, A5, A8, A15, A19, A22, A37 | probe, harness, mix master, weapon motion, rifle surfaces, zombie materials, announcer |

## Rejected review notes

1. Teammate revive in the T12 split: rejected. The T12 brief scopes squad scaling, spectate and a squad goal; revive is a design addition, and Continue is the only revive today. T12 splits into scaling, spectate and squad goal. Revive sits in the backlog for game design.
2. "A15 no input contradicts D1": the conclusion is rejected, the wording fix is kept. The game auto-runs, so a player giving no steering input is a running player, which is exactly D1's case. The accept now says "auto-running straight with no steering input" so nobody reads it as standing still.
3. "Fold A28 into T15 or run it right after": the placement is rejected. Tuning Low tier budgets for VFX and audio that M2 is about to replace would be done twice. T15 keeps its own Low tier rates for today's effects; every new AV task declares its Low value in config (rules block); A39 tunes the whole set in M4.
4. "A21 and A29 depend on T7 gamepad": half accepted. The HUD pass (now A36) waits for T7a. The credits panel (draft A29) is already built (wiki Credits.md, src/shared/config/CreditsConfig.luau, tests/credits), so the task is dropped and its gamepad reachability joins T7a's accept list.
5. The rationale for A21 ("replication overwrites client Motor6D changes") is not adopted: Motor6D.Transform does not replicate, as the stage report already notes. The spec it led to (a pooled client-local corpse clone driven by a server-to-client death event) is adopted for another reason: the server recycles pooled rigs, so a death effect has to outlive the server model.
