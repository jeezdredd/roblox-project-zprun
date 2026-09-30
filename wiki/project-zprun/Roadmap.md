# Roadmap

Ordering is approximate and gets renegotiated as the build moves. Items that cannot progress without the project owner acting outside the codebase (Creator Dashboard, asset authoring, publishing) are marked **owner-blocked**; everything else is code work.

See [[Progress]] for what each shipped layer actually contains, [[Architecture]] for how the systems fit together and [[Decisions]] for why the awkward parts are the way they are.

## Done

Shipped layers, roughly in the order they landed:

- **Prototype run**: auto-run driver (`src/client/controllers/RunController.luau`), A/D lateral input, lane clamp against `GameConstants.RUN_ORIGIN`, distance scored as `root.Position:Dot(RUN_DIRECTION)` in `src/server/systems/DistanceTracker.luau` with speed ramping from base to max.
- **Procedural biomes**: five locations in `src/shared/config/LocationsConfig.luau` (City, Forest, Wasteland, Farmstead, Cornfield) built by the 240x128 chunk factory `src/server/systems/ChunkFactory.luau` and streamed by `src/server/systems/ChunkSpawner.luau`, which plans a route, pools chunks and cross-fades colour, material and props into the next biome.
- **Zombies**: part-based rig factory, weighted spawning per chunk, difficulty-gated aggro and the juke mechanic (each zombie chases a delayed position sample, `reactionDelay` 0.35s for Runners and 0.75s for Walkers) in `src/server/systems/ZombieAI.luau`, plus a cross-fading animation layer in `src/server/systems/ZombieAnimator.luau`.
- **Hub and squad lobby**: hangar, vendor rooms, burning-city diorama and three boardable helicopters; `src/server/systems/SquadService.luau` runs one squad record per pad with Solo/FriendsOnly/Public gating, leader-only map/difficulty/modifier config, snapshot fan-out and a countdown that hands a fresh seed to `src/server/systems/MissionService.luau`.
- **Death sequence**: corpse pose, zombie lure and feeding ring, corpse-eye camera, YOU ARE DEAD, counted-up results and Return/Continue with one revive per run (`src/server/systems/DeathService.luau`, `src/client/controllers/DeathController.luau`, `src/client/systems/DeathGore.luau`).
- **Settings and skins**: schema-driven settings panel built from `src/shared/config/SettingsConfig.luau`, server-side sanitising and persistence, gore content warning, and five HumanoidDescription skins applied on spawn by `src/server/systems/SkinService.luau`.
- **Asset pipeline**: `assets/manifest.json` as the single source of truth (302 entries on 2026-09-29: 247 approved, 43 reviewing, 7 pending, 4 rejected, 1 needed), uploaded through Open Cloud by `scripts/upload_assets.py`, re-checked by `scripts/refresh_status.py`, with `scripts/sync_configs.py` regenerating `src/shared/config/AssetIds.luau` and `assets/LICENSES.md`. Every consumer treats id `0` as "not uploaded" and no-ops.
- **Audio, VFX and lighting detail pass**: foley and body-state audio, zombie voices, world ambience and reverb zones, step dust, juke bursts, breath vapour, embers and ash, event-driven post processing, and a lighting director that lerps presets per phase, night flag and biome.
- **Profiles**: ProfileStore persistence with template, version migration, Credits/XP attributes and an automatic `store.Mock` fallback when DataStores are unavailable in Studio (`src/server/systems/ProfileManager.luau`).
- **Desert base and range**: ground plane, road out to the burning city and an outdoor shooting range with gong targets behind the hangar (`src/server/systems/DesertBase.luau`).
- **Weapons**: four classes in `src/shared/config/WeaponsConfig.luau` with five upgrade levels; `src/server/systems/WeaponService.luau` validates fire intent (rate tolerance, unit direction, muzzle origin within 5 studs of head/root plus a line-of-sight raycast), does raycast damage with headshots and per-weapon ammo state that survives swaps; procedural first-person viewmodel (`src/client/systems/Viewmodel.luau`), third-person world model (`src/server/systems/WorldWeapon.luau`), per-class gunshot audio with interior/open reverb tails driven by `AcousticSpace` zone attributes.
- **Vendors and monetization**: authoritative catalogs and purchases over a RemoteFunction in `src/server/systems/ShopService.luau` (weapon unlock/upgrade, skills, skins, two loadout slots), and `src/server/systems/MonetizationService.luau` with an idempotent `ProcessReceipt` keyed on the profile's `PurchaseHistory` and a Robux Continue product.
- **ITD run layer**: ammo crates with green smoke pillars, per-run mission goals with credit bonuses, loadout slots, and the Farmstead and Cornfield biomes.
- **Anti-blur pass**: texel density normalised across surfaces, bloom limits and a sun-in-frame exception for the forest preset.
- **Skinned zombies (2026-09-29, da0ea7e)**: three CC BY 4.0 Sketchfab characters with 22 authored clips (`ZombieSkins`, `ZombieRigs`), bone-driven hit boxes and static torso blockers (`ZombieHitboxes`), walk/run choice by ground speed, attack swing, Hazmat scream, Ghoul flinch, held death poses and posed corpse props. See [[Gameplay Systems]].
- **MW2019 weapon pass (2026-09-29, da0ea7e)**: first-person packs for all four classes (`PackViewmodel`, `ViewmodelClipPlayer`), tactical and empty reloads with ammo-add, shell-by-shell shotgun with fire cancel, draw time, pooled visible casings with landing sounds, a new muzzle flash, marker-driven foley, the low-ammo layer, and 32 CC0 recordings from The Free Firearm Sound Library. See [[Gameplay Systems]] and [[Decisions]].

## Now: quality pass in stages

After the 2026-09-29 review the work runs in stages, one area at a time, each held to the standard of the best current shooters:

| Stage | Scope | Status |
| --- | --- | --- |
| 0. Test yard | A Studio yard in place of the run, with every texture, prop, weapon and animation on show and weapons to fire | Done (da0ea7e) |
| 1. Regressions | Casing size, animations that looked broken, muffled gunshots | Casings checked at real size; gunshots rebuilt (v6), waiting for a listen; first-person clips checked frame by frame; the weapon gallery's rigs hung above their posts and now stand on them; the Uzi (stock against the cheek) and pistol (too far) reframed; recoil made frame-rate independent and set near MW2019 hip fire, the shotgun's clip kick cut from 34 to about 15 degrees |
| 2. Sound in space | Distance curves per class, air absorption, speed-of-sound delay, occlusion, reflections, environment tails and reverb, a bus mix with ducking and a limiter, for every sound | Engine in (70feddb) and the weapons on it behind `SfxConfig.WEAPONS_ON_ENGINE` ([[Weapon Audio]]); waiting for the listening pass, then the legacy paths go |
| 3. Animation | Everything that moves: first-person packs, zombies, the third-person player, procedural layers; the best available sources | Third-person body layer on (the place keeps the avatar joint upgrade off for `Motor6D` joints), holds being tuned ([[Third-Person Body]]); third-person locomotion sets coded ([[Third-Person Locomotion]]), owed: the sixteen Mixamo clips through the retarget, then the yard gallery on `clipSetFor` |
| 4. Weapons and ammunition | Behaviour and feel, the remaining MW spec items (mech and punch layers, hit and kill markers, wall pull-back, the first raise) | Planned |
| 5. Environment | Props in the road chunks, textures and decals, map and lighting | Environment pass in (a371ee6): road dressing clusters, material variants per biome, mesh middle row and ruins, decal layer, night presets per biome, chunk budgets and the yard's biome strip ([[Environment]]); the screenshot plan and the missing decals are open |

Carried over from the MW2019 pass:

| Item | Detail |
| --- | --- |
| Skinned zombie gaps | No rise or feeding clips, so riser and feast formations spawn as idle zombies and corpse feeders stand still; the Hazmat has no death clip. Mixamo has Zombie Stand Up (three variants) and Zombie Biting Victim On The Ground (`docs/research/animation-sources-2026-09-30.md`) |
| Animation sources | Searched 2026-09-30 under the asset policy (`docs/research/animation-sources-2026-09-30.md`): no free CC0 / CC BY first-person pack reaches MW2019; the packs at that level are engine-bound Fab listings. Shortlist: Mixamo for every third-person clip, Cransh AK-74m and 1Matzh 9mm Pistol / Scorpion for first person, UTPS.dsk for native R15 reloads |
| In-game credits | Every Sketchfab asset is CC BY 4.0, and the footsteps, the OpenGameArt shots and the mag drop are CC BY 3.0; `assets/LICENSES.md` says the credits belong in the settings panel before release |
| Ship switches and gate | Set `WeaponsConfig.ALL_WEAPONS_UNLOCKED` back to false; run `selene src/`, `python3 tools/validate_api.py` and `rojo build` before each commit |
| Shotgun pack | Stays the Saps-12: teenjust500's 870 has the same broken shared skin and no idle or walk clips; revisit if a clean pump pack turns up |

## Next: Zombies layer

The stage the owner has specified. Reference for it is Call of Duty: Zombies as a risk economy, not as a wave-based map. Fixed work order: kill credits → perks → diegetic pickups → intermission → upgrade station.

### 1. Kill credits paid mid-run (`RunEconomy`)

A new server service holding a per-run credit balance separate from the profile balance. Kills pay into it as they happen; the results screen banks it into the profile through `ProfileManager`. Dying without a Continue does **not** burn what was earned: penalties there were judged demotivating, and that call belongs in [[Decisions]]. The kill hook already exists: `src/server/systems/WeaponService.luau` awards weapon XP and reports the `Kills` metric to `MissionGoals` from the same place.

### 2. Perks

Six starter perks (Toughness, Sprinter, Fast Hands, Field Medic, Scavenger, Steady Aim), levels 1-3. Slot 1 is free, slots 2 and 3 are bought with Credits. Perks and slots are **Credits only, never Robux**: the no-pay-to-win rule in the project rules. Build order inside the item: config module → Perk Lab station in the hangar (a sixth vendor-style room, same `VendorPrompt` pattern as `src/server/systems/VendorRooms.luau`) → HUD readout.

Open question to settle before writing the config: four of the six names overlap the persistent skills already in `src/shared/config/SkillsConfig.luau` (Toughness, Endurance, FastHands, Scavenger), which are applied through `src/server/systems/SkillEffects.luau`. Either perks subsume skills or perks are the per-run layer over them; shipping both under near-identical names would be confusing.

### 3. Diegetic weapon pickups

No wall-buy. Weapons lie in the world as staged scenes defined by a new `PickupScenesConfig` (dead soldier, shotgun on a fence post, chainsaw at a sawmill, pistol by a police car, SMG on checkpoint sandbags) picked up by holding a key for 0.3s. Each scene carries a `Highlight` outline so it reads through fog, and highlights must be **pooled: Roblox only renders 31 `Highlight` instances at once**, so scenes beyond the budget hand their outline back as the player passes.

The mystery box survives in reworked form: a crashed supply drop marked with red smoke. Green smoke stays reserved for ammo crates (`src/server/systems/AmmoCrates.luau`) so the two are never confused at distance.

### 4. Helicopter intermission

Replaces the current instant hand-off, where `MissionService.startSquad` spawns the squad straight onto `HangarConfig.RUN_START_CFRAME`. Three beats:

| Beat | Content |
| --- | --- |
| Cabin | Interactive helicopter interior: loadout and perk swap, ready check, 90s AFK timeout |
| Crash cinematic | ~12-15s; the pilot turns, the copilot shoots him. No gore in this cutscene: everyone sees it and the Gore toggle does not apply |
| Wake-up | Player comes to at the wreck with a 6s aggro grace window and a "RUN" prompt |

Repeat runs play a compressed ~5s version with skip voting. The crash is faked entirely with camera keyframes, light and sound: no real physics.

### 5. Upgrade station

A Pack-a-Punch-style station reachable mid-run that upgrades the carried weapon for run credits, with an announcer voice on use. The weapon level ladder it drives already exists (`WeaponsConfig.MAX_LEVEL = 5`, `upgradePrice`, `damageAt`), so the work is the station, the in-run spend path and the audio. Announcer lines are **owner-blocked**: the project rules require real licensed audio files through the manifest pipeline, never generated speech.

## Planned: Route forks

Branching route choice at biome boundaries: the squad votes with their feet between two entrances (Sewer, Forest, Metro with a burning train hazard, more to come), each branch trades a cost for a reward, and run modifiers stack on top. Full design and the live status board are in [[Route Forks]]. First step is a fork between two existing biomes to prove voting and route insertion before any new art. Step 1 is built and in playtest (2026-09-28).

## Later

- **Robux product and pass ids**: `src/shared/config/ProductsConfig.luau` still ships `productId = 0` and `passId = 0` for Continue, VIP and Supporter Pack. Every call site checks `ProductsConfig.isConfigured(...)` first, so the game runs with them at 0 and falls back to a free Continue. **Owner-blocked**: the items have to be created in the Creator Dashboard and the numeric ids pasted in. Test procedure is written up in `docs/monetization-test-plan.md`.
- **Animation clips** (updated 2026-09-29): player run, death and stumble are live, zombies use the 22 clips of their Sketchfab packs (the 7 Quaternius zombie clips remain for the fallback rigs), and the five viewmodel slots are obsolete because the pack clips are baked into Luau. Open: `player/strafe_left` and `player/strafe_right` and the sixteen locomotion and zombie slots of [[Third-Person Locomotion]] (Mixamo through `retarget_mixamo.py`; the rifle and pistol strafes replace the additive strafe leans once uploaded).
- **Spectating**: on death in a squad, watch surviving teammates until the run ends instead of returning to the hub immediately. Nothing in `src/` implements this yet.
- **More biomes and zombie types**: both are data-driven; a biome is an entry in `LocationsConfig` plus a `laneStyle`/prop set in `ChunkFactory`, a zombie is an entry in `ZombiesConfig`.
- **TeleportService**: only if the hub and the run ever split into separate places. Today they share one DataModel, 4300 studs apart (`HangarConfig.HUB_CENTER` vs `GameConstants.RUN_ORIGIN`), which `StreamingEnabled` handles; transport is already abstracted behind `FlowService` phases, so the split would be contained.
- **Loose ends worth closing**: the `NoDamage500` goal is unreachable because nothing reports the `CleanDistance` metric to `MissionGoals.report`; `src/server/systems/TrackBuilder.luau` pivots the start platform in absolute world space instead of relative to `RUN_ORIGIN`, leaving it 4000 studs from where squads actually spawn; two separate ScreenGuis named `DamageVignette` draw the same red overlay.

## Blocked on the owner

| Item | Why it cannot move in code | What unblocks it |
| --- | --- | --- |
| Continue product, VIP and Supporter passes | Ids must exist in the Creator Dashboard | Create the items, paste ids into `ProductsConfig` |
| Player strafe clips | No strafe loop in the CC0 library | Download Mixamo `Rifle Strafe Left/Right`, run the retarget pipeline, upload |
| Upgrade station announcer voice | Audio must be a real licensed file; generated speech is banned | Source or record licensed lines, add them to `assets/manifest.json` |
| Real receipt testing | Studio purchase testing does not exercise the live receipt pipeline | Publish the place and re-run the cases in `docs/monetization-test-plan.md` with a non-owner account |
| Maturity questionnaire | Stylised blood and dismemberment need the experience rated before wider release | Complete the questionnaire at publish time |
