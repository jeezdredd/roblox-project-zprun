# Task briefs for Claude Desktop

Source: four-pass review on 2026-10-12, summary in `production/project-stage-report.md`.
Each task is self-contained. Paste one task per session, together with the shared rules block.

## Shared rules block (paste with every task)

```
Project: Task Force Z, Roblox, Luau --!strict, Rojo. Read CLAUDE.md and production/project-stage-report.md first.
Rules: no comments in new or edited code; no imports inside functions; never use the em dash character; server is authoritative for ammo, damage, credits, purchases; every remote validates its arguments; new assets only through assets/manifest.json -> scripts/upload_assets.py -> scripts/sync_configs.py plus assets/LICENSES.md; never invent asset ids.
Before finishing: selene src/, python3 tools/validate_api.py, python3 tools/strip_comments.py --check, rojo build -o build.rbxl, and every tests/*/run.luau with `luau` plus tests/*/run.py with python3 must pass. Update the matching wiki/project-zprun note.
Commits: only when I ask, authored by me, no co-author trailer, no mention of Claude.
If Studio MCP is connected, verify in a playtest and report what you saw.
```

## Decisions

| # | Question | Answer |
| --- | --- | --- |
| D1 | Zombie chase | Decided 2026-10-12: zombies chase all the time but cannot catch a player who keeps running; they catch you only when you stop, stumble or get blocked by a barrier. |
| D2 | Platforms | Decided 2026-10-12: PC is the priority. Console is supported at PC parity through gamepad. Phone and tablet are supported with touch controls, and may run at degraded visual quality on weaker devices. |
| D3 | Perks | Decided 2026-10-12: wire perks into gameplay. |
| D4 | Existing comment lines | Decided 2026-10-12: remove all 3,540, moving useful explanations into the wiki. Done in the main session, see T19. |
| D5 | Distance pay | Decided 2026-10-12: zombies keep spawning per stud; distance credits per minute are capped at the base-speed rate times 1.1. Kill and goal credits are not capped. |

## P0: before any public playtest

### T1. Gate the free-weapons test flag
```
WeaponsConfig.ALL_WEAPONS_UNLOCKED is true at src/shared/config/WeaponsConfig.luau:86 and is not Studio-gated. The server skips the ownership check at src/server/systems/WeaponService.luau:194, so any player can equip any weapon by firing WeaponEquip. The client also reads it at src/client/systems/WeaponController.luau:422-439.
Do: default the flag to false; on server and client treat it as active only when RunService:IsStudio() is true.
Accept: in a non-Studio server an equip for an unowned weapon is ignored; Studio testing with number keys still works when the flag is turned on locally.
```

### T2. Server-validated run distance
```
src/server/systems/DistanceTracker.luau:164-170 credits root.Position:Dot(RUN_DIRECTION) with no check. The player owns their character physics (MissionService.luau:57), so a teleport or speed hack feeds RunEconomy distance pay, leaderstats Distance, MissionGoals Distance and CleanDistance, and is banked into saved Credits.
Do: per Heartbeat accept at most GameConstants.MAX_RUN_SPEED * dt * 1.25 of forward delta; cap the run total at elapsed * MAX_RUN_SPEED * 1.1; server teleports (wreck, revive, relocate, anti-stuck nudge) reset the baseline without crediting; record implausible jumps as server-side strikes and snap the player back after repeated strikes. Expose the last validated position for other systems.
Then: switch the proximity checks in RunPromptGuard.luau:26, AmmoCrates.luau:150, WeaponPickups.luau:174 and UpgradeStations.luau:104 to the validated position.
Accept: moving the HumanoidRootPart +5000 studs from the command bar during a run adds no credits and leaves the leaderstat unchanged; a normal run at max Endurance earns the same as before; add a Luau test under tests/ for the clamp math.
```

### T3. Make perks do something (D3: wire them)
```
Perks can be bought and equipped through PerkService (src/server/systems/PerkService.luau), costing about 23,750 credits for everything, but no gameplay system calls PerkService.equipped. Skills already work through src/server/systems/SkillEffects.luau.
Do: add a PerkEffects path mirroring SkillEffects so each perk in src/shared/config/PerksConfig.luau (Toughness, Sprinter, FastHands, FieldMedic, Scavenger, SteadyAim) is read by one named system. Where a perk duplicates a skill stat (health, reload, ammo crates, speed), cap the combined result and document the cap in wiki/project-zprun/Run Economy.md.
Accept: each perk has a measurable effect in a playtest; equipped perks clear at run end as today; combined skill and perk reload multiplier never drops below 0.6; combined max health never exceeds 180.
```

### T4. Continue purchase reliability
```
src/server/systems/MonetizationService.luau:116-119 calls DeathService.grantContinue, which returns false when no death is pending. If the 30 s death choice times out while the Robux prompt is open, ProcessReceipt returns NotProcessedYet forever and the player is charged with nothing delivered. Also the Continue productId is 0 in ProductsConfig, so DeathService.luau:187-191 grants it free in live servers.
Do: pause the death choice timeout while a purchase prompt is open; if the death is gone when the receipt arrives, store a Continue credit on the profile and resolve the receipt as granted. Allow the free path only under RunService:IsStudio().
Accept: every receipt resolves; the timeout case is added to docs/monetization-test-plan.md; a live server with productId 0 never grants a free Continue.
```

### T5. Client boot failure isolation
```
src/client/init.client.luau:60-112 calls about 45 X.init() lines directly. One throwing init kills every later controller. The server wraps each stage in runStage with pcall at src/server/init.server.luau:38-42.
Do: wrap each client init the same way, logging the module name and error once.
Accept: a deliberate error thrown in one client init leaves weapons, HUD, death flow and the remaining controllers working.
```

### T6. Test runner and CI
```
18 test suites exist (tests/*/run.luau for the luau CLI, tests/*/run.py) and all pass today, but nothing runs them automatically. There is no .github/ directory.
Do: add scripts/run_tests.sh that runs every tests/*/run.luau with luau and every tests/*/run.py with python3 and exits non-zero on any failure. Add .github/workflows/ci.yml running selene src/, python3 tools/validate_api.py, python3 tools/strip_comments.py --check, rojo build and scripts/run_tests.sh, with tool versions pinned through rokit.toml. The Fab content under src/shared/fab is gitignored, so CI must build without it.
Accept: CI is green on main; breaking one test makes CI red.
```

## P1: game feel and retention

### T7. Gamepad and touch gameplay controls (D2)
```
Decision: PC keyboard and mouse is the priority and must not change. Console must play like PC through a gamepad. Phone and tablet must be fully playable with touch, and may look worse on weak devices (see T15).
Today gameplay input is A/D, arrows, MouseButton1 fire and R reload (src/client/controllers/InputController.luau, src/client/systems/WeaponController.luau:767). Gamepad is bound for menus only, touch for nothing. HipAim already picks targets, so no precise aiming input is needed.
Do:
- Route every gameplay action (steer, fire, reload, weapon slots, interact prompts) through one action layer, so keyboard, gamepad and touch feed the same code path. ContextActionService is the natural fit if it matches the existing input code.
- Gamepad: left stick steer, right trigger fire, X reload, bumpers previous and next weapon, A for interact prompts. Right stick mirrors whatever the mouse does today within the locked camera limits. Show gamepad glyphs in prompts when the last input was a gamepad.
- Console: every menu, the shop, the Perk Lab, the upgrade station, the death and Continue screen and squad launch must be usable with a gamepad only, with a visible selection highlight. Text must stay readable on a TV, so check the smallest UI text size.
- Touch: drag on the left half of the screen to steer, plus fire, reload and weapon swap buttons on the right. Buttons respect the safe area and do not overlap the HUD at 16:9, 19.5:9 and 4:3 for tablets. Hide touch controls when a keyboard or gamepad is in use.
- Keep A/D, mouse and R behaviour on PC exactly as it is.
Accept:
- A full run, from hub through death or extraction, is playable with only a gamepad and with only touch in the Studio device emulator.
- Every menu is reachable and usable with a gamepad only.
- PC controls are unchanged.
- Touch buttons stay clear of the HUD on phone and tablet emulator profiles.
```

### T8. First 60 seconds onboarding
```
A first run is boot, hub, board, 4 s countdown, a 13 s unskippable crash cinematic, then a 6 s grace. No input is ever taught, and the first zombie arrives about 19 s after the run starts. ProfileManager already stores Runs.
Do: on first run skip or shorten the crash cinematic; show short in-run prompts for steer, fire and reload inside the start clearance; place one guaranteed single walker so the first kill happens by about 25 s. Log the steps with AnalyticsService:LogOnboardingFunnelStepEvent.
Accept: a new profile reaches its first kill within 25 s of the run starting; returning players see no prompts.
```

### T9. Relentless chase that cannot catch a running player (D1)
```
Decision: zombies chase all the time but cannot catch a player who keeps running at normal speed. They catch the player only when the player stops, stumbles (glance or collision slowdown) or is blocked by a barrier.
Current code works against this in three places:
1. Chase gives up: ZombieAI.luau:668-681 drops from Alert to Aware once the player is beyond alertRadius * HYSTERESIS (120 * 1.25 = 150 studs).
2. Zombies slow down near the player: speedFromCurve (ZombieAI.luau:475-481) scales speed by distance / alertRadius with a dead zone, so a zombie 30 studs behind runs at about two thirds of its max and one within 6 studs stops.
3. Max speeds are far below the player: Medium zombieSpeedMultiplier 0.6 (DifficultyConfig.luau:30) caps Runners at 12 and Walkers at 4.8 studs/s against player speed 24 (GameConstants.BASE_RUN_SPEED).
Do:
- Once a zombie reaches Alert it keeps chasing until DistanceTracker despawns it behind the last player (DESPAWN_BEHIND_DISTANCE 160). No hysteresis exit.
- Split chase into two cases. A zombie ahead of the player keeps the current ITD-style curve, so lateral juking still works. A zombie behind or beside the player (dot of its offset with RUN_DIRECTION below zero) runs at a flat pursuit speed with no slow-down near the player.
- Express pursuit speed as a fraction of BASE_RUN_SPEED per zombie class in ZombiesConfig, scaled per difficulty in DifficultyConfig. Starting points: Runner 0.9 (21.6 studs/s), Walker 0.55 (13.2). Difficulty fractions: Easy x0.85, Medium x1.0, Hard x1.05, and the result must never reach 1.0 of BASE_RUN_SPEED.
- A stopped or blocked player must actually be reached: within ATTACK_REACH the zombie swings and the existing grab or damage path applies.
- Behind the player the threat is heard, not seen: make sure chasing zombies keep their footstep and growl audio (ZombieAudio) so the player knows the pack is there.
- Fix the wiki claim that the FastZombies bonus is added when ZombieAI.luau:589 multiplies it, and keep FastZombies below player speed too.
Accept, on Medium, in Studio playtests:
- A player running straight with no input is never reached from behind.
- A player who stops is reached by the pack within about 3 seconds.
- A glance or barrier hit with a Runner 10 studs behind lets it close to striking range.
- Chasing zombies do not vanish while still within 160 studs behind the last player.
- Lateral juking of zombies ahead still works as before.
```

### T10. Run telemetry
```
Every economy and balance number is an estimate. Roblox AnalyticsService supports LogCustomEvent, LogEconomyEvent, LogProgressionEvent and LogFunnelStepEvent.
Do: at run end log duration, distance, kills by zombie class, headshots, credits by source, ammo picked up and spent, difficulty, modifiers, squad size and death cause. Log credit sinks with LogEconomyEvent in ShopService, PerkService and UpgradeStations. Server-side only.
Accept: events appear in the Creator Dashboard after a published test; no event fires more than once per run per player.
```

### T11. Cap distance pay per minute (D5)
```
Distance pay is 1 credit per 10 studs (RunEconomyConfig STUDS_PER_CREDIT) and spawns are per stud, so Endurance plus Adrenaline (24 to 36 studs/s) earn about 50 percent more per minute. This makes speed the dominant purchase.
Decision: keep spawns per stud; cap distance credits per minute at the BASE_RUN_SPEED rate times 1.1. Kill, headshot, streak and goal credits stay uncapped.
Do: in RunEconomy, track distance credits against elapsed run time so the running total never exceeds elapsed_seconds * BASE_RUN_SPEED / STUDS_PER_CREDIT * 1.1 times the difficulty multiplier; distance beyond the cap still counts for leaderstats and goals. Pair with T2 so the elapsed clock is server-side. Update wiki Run Economy.md.
Accept: a 36 studs/s run earns at most 1.1x the per-minute credits of a 24 studs/s run; covered by a test in tests/economy.
```

### T12. Co-op scaling, spectate and revive
```
Spawn density has no squad term (ZombieSpawnConfig densityTiers maxAlive, ZombieAI MAX_ALIVE 60). Three players share one horde, there is no spectate on death and no teammate revive.
Do: scale maxAlive and spawn delay by squad size (1.0, 1.6, 2.1 as a starting point); add spectate of a living teammate after death; add a squad goal in MissionGoals paid to all members.
Accept: zombies per player per minute stay within 20 percent across 1, 2 and 3 players; a dead player can cycle spectate targets; the squad goal pays every member once.
```

### T13. Shotgun and weapon sanity pass
```
Shotgun is 8 pellets x 12 damage = 96, below Walker health 100, so a full point-blank blast does not kill a Walker (src/shared/config/WeaponsConfig.luau around lines 181-189).
Do: set pellet damage so a full point-blank blast kills a Walker and four pellets do not; re-check time-to-kill for all four weapons against Walker 100 and Runner 60 and record the table in wiki/project-zprun/Gameplay Systems.md.
Accept: TTK table in the wiki; a Luau test asserts the shotgun one-shot rule.
```

## P2: performance (measure first)

### T14. Baseline profile
```
Nothing has been measured; wiki/project-zprun/Performance.md has no MicroProfiler capture and two of its claims are wrong (ZombieAI steering runs every frame, ZombieAudio allocates every frame).
Do: in Studio record a City night run on Hard with 60 zombies alive. Capture MicroProfiler, Script Performance for ZombieAI, ZombieAudio, WeaponVfx, ZombieHitboxes and AudioEngine, Server Stats heartbeat time, outgoing network KB/s per player, Stats.InstanceCount over 5 minutes of sustained fire, and the live PointLight count.
Accept: numbers recorded in Performance.md and the two wrong claims corrected. No code changes in this task.
```

### T15. Run-chunk lights and device quality tiers (D2)
```
Decision: PC looks are the priority. Phone, tablet and weak PCs may degrade visually to hold frame rate.
Street lamps add about 6 PointLights per 128-stud chunk (ChunkFactory.luau:673, spacing at 1148-1154), plus barrels (:717) and police bars (:775). Lighting.Technology is Future (default.project.json:62) and cannot be switched per device at runtime. EnvironmentQuality.luau:41-61 only strips tagged detail and near-band shadows on touch devices.
Do:
- Define two client tiers in one place: High for PC and console at normal graphics quality; Low for touch devices and for any device whose graphics quality level is low.
- Lights: keep every lamp mesh, but give only every second or third lamp a PointLight on High, and only lamps near the player on Low.
- Low tier: turn off Bloom, DepthOfField and SunRays, lighten Atmosphere, drop CastShadow on small props, strip tagged decor, and lower particle rates in WeaponVfx, WorldVfx and ZombieVfx.
- High tier must look the same as today.
Accept:
- At most 12 live PointLights with 6 chunks ahead on High, fewer on Low.
- High tier side-by-side capture unchanged versus before.
- Low tier frame time improved versus the T14 baseline in the Studio phone emulator and at low graphics quality on PC.
```

### T16. Zombie server cost
```
ZombieAI.smoothStep (ZombieAI.luau:564-581) calls Humanoid:Move for every moving zombie every frame. It exists to stop zombie jitter, so keep the smoothing. ZombieAnimator.luau:104-107 creates Animation objects and calls LoadAnimation for up to 11 clips on every spawn, and stopAll (:549-560) destroys them on recycle.
Do: in smoothStep skip Move when the heading change since the last call is under about 1 degree; cache Animation objects once per clip; keep tracks on pooled models and stop rather than destroy them on recycle; call ZombieHitboxes.detach on recycle.
Accept: smoothStep under 0.3 ms average with 60 alive per T14 method; zero LoadAnimation calls per spawn after warm-up; no visible jitter or heading pop.
```

### T17. Effect pooling and client scans
```
WeaponVfx.luau:1215-1232 and :1274 create an Attachment, ParticleEmitter and Part per impact; ZombieAI.luau:341-350 and ZombieVfx.luau:22-91 create parts per death. ZombieAudio.luau:45-85 calls GetChildren on Workspace.Zombies every frame. WeaponSfx.luau:52-61 listens to DescendantAdded on all of Workspace.
Do: pool impact anchors and blood stains like the existing casing pool; cache zombie torsos on ChildAdded and throttle walla counting to 5 Hz; replace the Workspace DescendantAdded hook with a CollectionService tag set by the builders that create AcousticSpace volumes.
Accept: Stats.InstanceCount flat over 30 s of sustained fire after warm-up; zero GetChildren calls per frame in ZombieAudio.
```

## P3: code health

### T18. Remote hardening
```
Do: reject NaN and infinite numbers in SettingsPersistence.luau:33-35 and ProfileManager.spendCredits (:238); repair non-finite or negative Credits and XP on profile load; add per-player throttles to ShopCatalog (ShopService.luau:347), PromptPurchase (MonetizationService.luau:125), SquadLaunch and SquadLeave (SquadService.luau:315-320); refuse profile purchases outside the Hub phase unless the design allows them; validate the value in Sandbox setMode even though it is Studio-only.
Accept: a Luau test covers the finite-number checks; valid behaviour unchanged.
```

### T19. Comment policy cleanup (DONE 2026-10-12)
```
Done in the main session: 3,591 comments removed from 176 files, all checks green. Every removed comment is kept in docs/archive/code-comments-2026-10-12.md. tools/strip_comments.py --check keeps new comments out.
```

### T20. Split ZombieAI
```
src/server/systems/ZombieAI.luau is 1292 lines. Split into ZombieSpawner (spawn stepping), ZombiePool (pools, recycle), ZombieSteering (tick and smoothStep), ZombieFeeder (lure and feeding poses, around lines 890-930). ZombieAI stays the facade with the same public API and remains the single Heartbeat owner. Move the module-level Heartbeat in ZombieHitboxes.luau:54 into an init called from ZombieAI.init. Do this after T16.
Accept: no module over 500 lines; a 2-minute playtest shows the same behaviour; selene clean.
```

### T21. Wiki truth pass
```
Roadmap "Next" lists intermission, weapon pickups, upgrade station and Perk Lab, which are already built. Route forks steps 4-8 depend on grenades, which do not exist. The Sawmill chainsaw scene is disabled but still listed.
Do: update Roadmap.md, Progress.md, Gameplay Systems.md and Route Forks.md to match the code; mark route forks steps 4-8 frozen; remove the Sawmill entry from PickupScenesConfig and the wiki.
Accept: every feature named in Roadmap "Next" is genuinely unbuilt.
```

### T22. Dev key handling
```
scripts/upload_assets.py:101 and scripts/refresh_status.py:44 pass the Open Cloud key on the curl command line, where other local processes can read it.
Do: pass the header through a temporary file with mode 600 or through stdin with curl -H @-.
Accept: the key never appears in argv; uploads still work.
```

### T23. Weapon roster architecture (D10)
```
Decision D10: the arsenal will grow to many weapons per class (rifles, pistols, SMGs, machine guns, launchers, grenades). Today WeaponsConfig gives each weapon an id and a class, but ViewmodelPackConfig, PackViewmodel, Viewmodel and SandboxWeaponGallery look packs up by class, ViewmodelConfig.ARM_GRIP and AnimationsConfig.locomotionSets are keyed by class, and about 17 files use the literal "Rifle". Two rifles cannot coexist.
Do: give every weapon in WeaponsConfig a pack key and make ViewmodelPackConfig keyed by pack, with class kept for shared behaviour (stance, locomotion set, arm grip default, audio class). Route every pack lookup through the weapon id. Add a data-only weapon template so a new weapon is one config entry plus assets. Keep ownership, upgrades, pickups, shop and loadout slots working per weapon id, with a profile migration if saved data keys change. Make the test yard gallery list weapons, not classes, and include Fab packs when present.
Accept: two weapons of the same class can be owned, equipped and switched in one run, each with its own viewmodel and clips; existing saves load unchanged; a Luau test covers the pack lookup and the migration; selene, validate_api, comment check, rojo build and all tests pass.
```

### T24. AK as a second rifle (D10)
```
Depends on T23. The committed AK pack (asset "rifle", clips viewmodel_clips/RifleClips, CC BY 4.0, rig id in AssetIds.viewmodel.fps.rifle) shipped as the Rifle until commit bd4325b moved the class to the Fab M4. Its old config block is in that commit's parent.
Do: add the AK as its own weapon (id, display name, stats distinct from the M4, price, upgrade path) with its pack entry restored from the old block, minus comments. Apply the art director's notes from production/av-polish-tasks.md: darker or black-polymer furniture, reload actionHold low enough that the muzzle stays below the horizon. Leave the extra reload states and visible rounds to A42 and A43.
Accept: the AK can be bought, equipped and fired next to the M4 in a run; first-person captures match the comparison set; credits in LICENSES.md stay correct; all checks pass.
```

### T25. Import the FPS Essentials Kit weapons (D10)
```
Depends on T23. The owner bought FPS Essentials Kit 0.9b on the Unity Asset Store (asset policy rule 3, revised 2026-10-12). Already unpacked on 2026-10-12 without Unity into the gitignored assets/unity/fps-essentials-kit/ (data only; code, shaders and third-party additions dropped; file list in _extract_manifest.json). It holds first-person rigs and FBX clips for G36C (Draw, Fire, FireAim, Reload, CompleteReload, Hide, Melee, Vault), RSASS (Draw, Fire, Reload, ReloadEmpty, Hide, Melee, Vault), MP7 (Draw, Fire, FireAim, Reload, CompleteReload, Hide, Melee, Vault), M590 (Draw, Fire, FireAim, ReloadStart, ShellInLoop, ReloadEnd, Hide, Melee, Vault) and ACR (Draw, Down, Fire_HIP, Fire_ADS, Reload Full, Reload_Empty, Melee, Vault); an M67 grenade and a scope as OBJ meshes; a Soldier model; 63 WAV sounds (per weapon, generic, bullet impacts, footsteps, player) and PBR textures.
Do: per weapon, convert the rig and clips to glTF with Blender MCP, run tools/fps_pack (report, bake, emit_luau) into the gitignored src/shared/unity/<Weapon>Clips.luau, extend PackViewmodel's clip search to the unity folder, upload rigs and sounds through the manifest with the product page as source and "Unity Asset Store EULA" as licence, and add each as its own weapon entry on top of T23. Map the reload clips onto the D8 ammo states, the sounds onto WeaponSfx layers, and reskin the arms to camo sleeves (D7) where they differ.
Accept: each of the five weapons can be bought, equipped, fired and reloaded in a run with its own clips and sounds; nothing from the pack is tracked by git; all checks pass.
```

## Suggested order

T1, T2, T5, T6 first: small, mechanical, and they close the exploit and stability holes. Then T3, T9, T4, T8, T10. T7 comes after those, because PC is the priority, but before any public launch. T11 and T19 wait for D5 and D4. Run T14 before any of T15 to T17.
