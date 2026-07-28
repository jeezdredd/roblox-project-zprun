# Roadmap

Ordering is approximate and gets renegotiated as the build moves. Items that cannot progress without the project owner acting outside the codebase (Creator Dashboard, asset authoring, publishing) are marked **owner-blocked**; everything else is code work.

See [[Progress]] for what each shipped layer actually contains, [[Architecture]] for how the systems fit together and [[Decisions]] for why the awkward parts are the way they are.

## Done

Shipped layers, roughly in the order they landed:

- **Prototype run** — auto-run driver (`src/client/controllers/RunController.luau`), A/D lateral input, lane clamp against `GameConstants.RUN_ORIGIN`, distance scored as `root.Position:Dot(RUN_DIRECTION)` in `src/server/systems/DistanceTracker.luau` with speed ramping from base to max.
- **Procedural biomes** — five locations in `src/shared/config/LocationsConfig.luau` (City, Forest, Wasteland, Farmstead, Cornfield) built by the 240x128 chunk factory `src/server/systems/ChunkFactory.luau` and streamed by `src/server/systems/ChunkSpawner.luau`, which plans a route, pools chunks and cross-fades colour, material and props into the next biome.
- **Zombies** — part-based rig factory, weighted spawning per chunk, difficulty-gated aggro and the juke mechanic (each zombie chases a delayed position sample, `reactionDelay` 0.35s for Runners and 0.75s for Walkers) in `src/server/systems/ZombieAI.luau`, plus a cross-fading animation layer in `src/server/systems/ZombieAnimator.luau`.
- **Hub and squad lobby** — hangar, vendor rooms, burning-city diorama and three boardable helicopters; `src/server/systems/SquadService.luau` runs one squad record per pad with Solo/FriendsOnly/Public gating, leader-only map/difficulty/modifier config, snapshot fan-out and a countdown that hands a fresh seed to `src/server/systems/MissionService.luau`.
- **Death sequence** — corpse pose, zombie lure and feeding ring, corpse-eye camera, YOU ARE DEAD, counted-up results and Return/Continue with one revive per run (`src/server/systems/DeathService.luau`, `src/client/controllers/DeathController.luau`, `src/client/systems/DeathGore.luau`).
- **Settings and skins** — schema-driven settings panel built from `src/shared/config/SettingsConfig.luau`, server-side sanitising and persistence, gore content warning, and five HumanoidDescription skins applied on spawn by `src/server/systems/SkinService.luau`.
- **Asset pipeline** — `assets/manifest.json` as the single source of truth (110 entries: 83 approved, 13 reviewing, 12 pending, 2 rejected), uploaded through Open Cloud by `scripts/upload_assets.py`, with `scripts/sync_configs.py` regenerating `src/shared/config/AssetIds.luau` and `assets/LICENSES.md`. Every consumer treats id `0` as "not uploaded" and no-ops.
- **Audio, VFX and lighting detail pass** — foley and body-state audio, zombie voices, world ambience and reverb zones, step dust, juke bursts, breath vapour, embers and ash, event-driven post processing, and a lighting director that lerps presets per phase, night flag and biome.
- **Profiles** — ProfileStore persistence with template, version migration, Credits/XP attributes and an automatic `store.Mock` fallback when DataStores are unavailable in Studio (`src/server/systems/ProfileManager.luau`).
- **Desert base and range** — ground plane, road out to the burning city and an outdoor shooting range with gong targets behind the hangar (`src/server/systems/DesertBase.luau`).
- **Weapons** — four classes in `src/shared/config/WeaponsConfig.luau` with five upgrade levels; `src/server/systems/WeaponService.luau` validates fire intent (rate tolerance, unit direction, muzzle origin within 5 studs of head/root plus a line-of-sight raycast), does raycast damage with headshots and per-weapon ammo state that survives swaps; procedural first-person viewmodel (`src/client/systems/Viewmodel.luau`), third-person world model (`src/server/systems/WorldWeapon.luau`), per-class gunshot audio with interior/open reverb tails driven by `AcousticSpace` zone attributes.
- **Vendors and monetization** — authoritative catalogs and purchases over a RemoteFunction in `src/server/systems/ShopService.luau` (weapon unlock/upgrade, skills, skins, two loadout slots), and `src/server/systems/MonetizationService.luau` with an idempotent `ProcessReceipt` keyed on the profile's `PurchaseHistory` and a Robux Continue product.
- **ITD run layer** — ammo crates with green smoke pillars, per-run mission goals with credit bonuses, loadout slots, and the Farmstead and Cornfield biomes.
- **Anti-blur pass** — texel density normalised across surfaces, bloom limits and a sun-in-frame exception for the forest preset.

## Next: Zombies layer

The stage the owner has specified. Reference for it is Call of Duty: Zombies as a risk economy, not as a wave-based map. Fixed work order: kill credits → perks → diegetic pickups → intermission → upgrade station.

### 1. Kill credits paid mid-run (`RunEconomy`)

A new server service holding a per-run credit balance separate from the profile balance. Kills pay into it as they happen; the results screen banks it into the profile through `ProfileManager`. Dying without a Continue does **not** burn what was earned — penalties there were judged demotivating, and that call belongs in [[Decisions]]. The kill hook already exists: `src/server/systems/WeaponService.luau` awards weapon XP and reports the `Kills` metric to `MissionGoals` from the same place.

### 2. Perks

Six starter perks (Toughness, Sprinter, Fast Hands, Field Medic, Scavenger, Steady Aim), levels 1-3. Slot 1 is free, slots 2 and 3 are bought with Credits. Perks and slots are **Credits only, never Robux** — the no-pay-to-win rule in `CLAUDE.md`. Build order inside the item: config module → Perk Lab station in the hangar (a sixth vendor-style room, same `VendorPrompt` pattern as `src/server/systems/VendorRooms.luau`) → HUD readout.

Open question to settle before writing the config: four of the six names overlap the persistent skills already in `src/shared/config/SkillsConfig.luau` (Toughness, Endurance, FastHands, Scavenger), which are applied through `src/server/systems/SkillEffects.luau`. Either perks subsume skills or perks are the per-run layer over them; shipping both under near-identical names would be confusing.

### 3. Diegetic weapon pickups

No wall-buy. Weapons lie in the world as staged scenes defined by a new `PickupScenesConfig` — dead soldier, shotgun on a fence post, chainsaw at a sawmill, pistol by a police car, SMG on checkpoint sandbags — picked up by holding a key for 0.3s. Each scene carries a `Highlight` outline so it reads through fog, and highlights must be **pooled: Roblox only renders 31 `Highlight` instances at once**, so scenes beyond the budget hand their outline back as the player passes.

The mystery box survives in reworked form: a crashed supply drop marked with red smoke. Green smoke stays reserved for ammo crates (`src/server/systems/AmmoCrates.luau`) so the two are never confused at distance.

### 4. Helicopter intermission

Replaces the current instant hand-off, where `MissionService.startSquad` spawns the squad straight onto `HangarConfig.RUN_START_CFRAME`. Three beats:

| Beat | Content |
| --- | --- |
| Cabin | Interactive helicopter interior: loadout and perk swap, ready check, 90s AFK timeout |
| Crash cinematic | ~12-15s; the pilot turns, the copilot shoots him. No gore in this cutscene — everyone sees it and the Gore toggle does not apply |
| Wake-up | Player comes to at the wreck with a 6s aggro grace window and a "RUN" prompt |

Repeat runs play a compressed ~5s version with skip voting. The crash is faked entirely with camera keyframes, light and sound — no real physics.

### 5. Upgrade station

A Pack-a-Punch-style station reachable mid-run that upgrades the carried weapon for run credits, with an announcer voice on use. The weapon level ladder it drives already exists (`WeaponsConfig.MAX_LEVEL = 5`, `upgradePrice`, `damageAt`), so the work is the station, the in-run spend path and the audio. Announcer lines are **owner-blocked**: `CLAUDE.md` requires real licensed audio files through the manifest pipeline, never generated speech.

## Later

- **Robux product and pass ids** — `src/shared/config/ProductsConfig.luau` still ships `productId = 0` and `passId = 0` for Continue, VIP and Supporter Pack. Every call site checks `ProductsConfig.isConfigured(...)` first, so the game runs with them at 0 and falls back to a free Continue. **Owner-blocked**: the items have to be created in the Creator Dashboard and the numeric ids pasted in. Test procedure is written up in `docs/monetization-test-plan.md`.
- **Animation clips** — all 12 animation entries in `assets/manifest.json` (5 player, 7 zombie) are still at asset id `0`, so `src/client/controllers/AnimationController.luau` and `src/server/systems/ZombieAnimator.luau` degrade silently and the game currently runs on procedural motion only. There are no weapon animation clips at all — the viewmodel is posed by direct CFrame writes each frame. **Owner-blocked**: animations must be authored and published from Studio.
- **Spectating** — on death in a squad, watch surviving teammates until the run ends instead of returning to the hub immediately. Nothing in `src/` implements this yet.
- **More biomes and zombie types** — both are data-driven; a biome is an entry in `LocationsConfig` plus a `laneStyle`/prop set in `ChunkFactory`, a zombie is an entry in `ZombiesConfig`.
- **TeleportService** — only if the hub and the run ever split into separate places. Today they share one DataModel, 4300 studs apart (`HangarConfig.HUB_CENTER` vs `GameConstants.RUN_ORIGIN`), which `StreamingEnabled` handles; transport is already abstracted behind `FlowService` phases, so the split would be contained.
- **Loose ends worth closing** — the `NoDamage500` goal is unreachable because nothing reports the `CleanDistance` metric to `MissionGoals.report`; `src/server/systems/TrackBuilder.luau` pivots the start platform in absolute world space instead of relative to `RUN_ORIGIN`, leaving it 4000 studs from where squads actually spawn; two separate ScreenGuis named `DamageVignette` draw the same red overlay.

## Blocked on the owner

| Item | Why it cannot move in code | What unblocks it |
| --- | --- | --- |
| Continue product, VIP and Supporter passes | Ids must exist in the Creator Dashboard | Create the items, paste ids into `ProductsConfig` |
| Player and zombie animation clips | Animations are authored and published from Studio, not uploadable through the asset script | Author the 12 clips, run the manifest pipeline |
| Upgrade station announcer voice | Audio must be a real licensed file; generated speech is banned by `CLAUDE.md` | Source or record licensed lines, add them to `assets/manifest.json` |
| Real receipt testing | Studio purchase testing does not exercise the live receipt pipeline | Publish the place and re-run the cases in `docs/monetization-test-plan.md` with a non-owner account |
| Maturity questionnaire | Stylised blood and dismemberment need the experience rated before wider release | Complete the questionnaire at publish time |
