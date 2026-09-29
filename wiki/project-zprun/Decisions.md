# Decisions

The decision log for Task Force Z. Every entry records what was decided, why, and what it costs or enables downstream. Entries marked **Provisional** are still expected to change; everything else is treated as settled and should not be re-litigated without a new entry here.

Related: [[Architecture]], [[Performance]], [[Progress]], [[Roadmap]].

## Standing decisions

### One place, transport abstracted

**Decision.** The whole flow (boot, hangar hub, helicopter lobby, run, death, reward) lives in a single Roblox place. Moving between the hub and the run is a CFrame teleport, not a `TeleportService` call.

**Reason.** `TeleportService` does not work in a Studio playtest, so a multi-place layout would make the core loop untestable in the only environment available day to day.

**Consequence.** Hub and run geometry coexist in one DataModel and have to be kept physically apart (see the run-origin entry below). If real place-to-place teleports are ever needed, the phase machine in `src/server/systems/FlowService.luau` is the single seam that has to change: no gameplay system reads the transport directly.

### Humanoid movement with client ownership, distance measured on the server

**Decision.** The run is driven by `Humanoid:Move()` called every RenderStepped from `src/client/controllers/RunController.luau`. The character stays under the client's network ownership and replicates natively. The server independently measures progress in `src/server/systems/DistanceTracker.luau` as `root.Position:Dot(RUN_DIRECTION)`.

**Reason.** Client-owned humanoid movement is the only way to get responsive input at run speed on Roblox. Server-side simulation of the runner would add a round trip to every lateral dodge, which is the entire skill expression of the game.

**Consequence.** Movement is exploitable in principle, but the payout is not: distance is read from the replicated root position on the server, and rewards, kills and credits are all computed server-side. Anything that pays out has to be derived from server-observed state, never reported by the client.

### Soft lane clamp instead of a wrap teleport

**Decision.** When the runner reaches the lane edge, `RunController.clampToField` slides the root back to the boundary. It does not wrap the player to the opposite side, and it does not rely on `Touched` events against the barrier parts.

**Reason.** A wrap teleport reads as a bug at speed, and `Touched` is unreliable at run velocity: a fast lateral move can tunnel through a thin barrier without ever firing. Position clamping is frame-accurate and cannot be missed.

**Consequence.** The physical side barriers built by `ChunkFactory` are now a backstop rather than the mechanism. The threshold constant is still called `GameConstants.WALL_WRAP_MARGIN`, a leftover name from the wrap era that no longer describes what it does.

### Server-owned zombies chasing a lagged player position

**Decision.** Every zombie root is pinned with `SetNetworkOwner(nil)` in `src/server/systems/ZombieAI.luau`, and each one paths toward a sample of the player's position taken `config.reactionDelay` seconds ago rather than the current position.

**Reason.** Server ownership keeps the horde authoritative and consistent for all three squad members. The delayed sample turns zigzag juking into the intended counterplay: the horde commits to where you were, so changing direction makes it overshoot.

**Consequence.** The delay is the primary difficulty dial per archetype (Walker 0.75s, Runner 0.35s in `src/shared/config/ZombiesConfig.luau`) so Runners track much more tightly. Server-owned physics for a large horde is also the main CPU cost of a run; the AI runs on a 0.2s tick rather than per-frame to pay for it.

**Superseded (2026-09-07)** for the chase target: `reactionDelay` and the position history were removed in the ITD2 pass (see "Zombie behaviour and spawn tiers use ITD2's measured values"). Server ownership stands.

### Aggro gated per difficulty by run distance

**Decision.** Zombies only begin chasing once `DistanceTracker.getMaxDistance()` passes `difficulty.aggroDistance`, and the flag is mirrored to the `Workspace.ZombiesAggro` attribute for client audio and VFX to react to.

**Reason.** A single global aggro rule cannot serve both a first-time player and a Hard run. Gating on distance travelled gives every difficulty a different length of grace period at the start of the run instead of a different proximity radius.

**Consequence.** The three tiers in `src/shared/config/DifficultyConfig.luau` are deliberately far apart: Hard aggros at 0 studs, Medium at 500, Easy sets `zombiesChase = false` and `aggroDistance = math.huge` so zombies never move at all. **Provisional**: Easy also sets `zombieSpeedMultiplier = 0`, which makes it a pure obstacle course rather than an easy horde; that is a tuning placeholder, not a final design.

**Superseded.** Easy became a slow chase ("Easy is a slow chase, not a diorama") and the ITD2 values pass set `aggroDistance` to 300 / 0 / 0 for Easy / Medium / Hard; the per-zombie radii now do the gating.

### Custom zombie rigs must set `RequiresNeck = false`

**Decision.** `src/server/systems/ZombieFactory.luau` sets `humanoid.RequiresNeck = false` on every built rig.

**Reason.** A Humanoid without a neck Motor6D named exactly as Roblox expects is killed instantly by the engine. The part-based zombie rig does not match the standard skeleton.

**Consequence.** Any future custom Humanoid rig in this project has to carry the same flag. This is a hard engine constraint, not a preference.

### Gore is rendered by the client, the server only reports the event

**Decision.** The server broadcasts the fact of a death (`DeathBegan`) and hit events; each client decides what to draw based on its own `bloodEnabled` / `dismembermentEnabled` settings in `src/client/systems/DeathGore.luau` and `src/client/systems/ZombieVfx.luau`.

**Reason.** If the server spawned gibs and blood parts, one player's content toggle could not hide them: they would already exist in the shared world.

**Consequence.** Gore is presentation-only and never affects gameplay state. The cost is that gore is not authoritative: two players watching the same death can legitimately see different things.

### Forced first person during the run

**Decision.** Runs are locked to first person. `src/client/controllers/CameraController.luau` hides the local character every frame with `LocalTransparencyModifier`, and visibility is restored for the death cinematic.

**Reason.** A design call: third person flattens the threat of something chasing you from behind, which is the whole premise.

**Consequence.** Everything about weapon presentation had to be built for first person, which is where the viewmodel work comes from. The `firstPersonBody` setting lets a player keep their visible body, but the head and accessories are always hidden regardless, because they clip the camera.

### Managed death instead of engine ragdoll

**Decision.** `BreakJointsOnDeath = false` is set in `FlowService`, the server anchors and poses the corpse, and `Players.RespawnTime` is set to 600 so nothing auto-respawns: every respawn is an explicit `player:LoadCharacter()`.

**Reason.** The death sequence is a cinematic: the corpse has to stay intact and readable while zombies swarm and feed on it, and the player has to be able to sit in the results screen without the engine yanking them back.

**Consequence.** Respawn is now entirely the responsibility of `src/server/systems/DeathService.luau`, including hub deaths, which need a separate watcher with a delay. Forgetting to call `LoadCharacter` on any path leaves the player permanently dead.

## Persistence and economy

### ProfileStore with a Studio mock fallback

**Decision.** Player data is persisted with ProfileStore (the only Wally dependency). On startup `src/server/systems/ProfileManager.luau` probes a DataStore; if the probe fails in Studio it silently switches to `store.Mock`.

**Reason.** Studio without API access cannot reach DataStores, and hard-failing there would make the entire economy untestable locally. Session locking and the template/migration model were the reasons for choosing ProfileStore over raw `DataStoreService`.

**Consequence.** Progression appears to work in Studio but nothing persists. This is deliberately observable via `ProfileManager.isUsingMock()` and must be checked before trusting any local test of the economy. Profile shape is versioned; `migrate()` runs on load and the template is the single source of truth for new fields.

### The server is authoritative for ammo, damage and credits

**Decision.** A hard rule, also recorded in `CLAUDE.md`. The client predicts and displays; it never decides. `src/server/systems/WeaponService.luau` owns mag and reserve counts, runs the damage raycast, and validates every fire request: fire rate within a 3% tolerance, direction magnitude in the 0.9 to 1.1 band, the claimed muzzle origin within 5 studs of the character's head or root, and an unobstructed raycast between the character and that origin.

**Reason.** Everything in the game converts into credits, and credits buy permanent progression. Any client-trusted number is a direct exploit into the economy.

**Consequence.** Client-side prediction has to be reconciled against server attributes (`AmmoMag`, `AmmoReserve`, `Reloading`), which is why `src/client/systems/WeaponController.luau` maintains a predicted magazine and a local reload lockout separate from the authoritative state. Every new remote is expected to validate its arguments the same way.

### Per-weapon ammo persists across swaps

**Decision.** `WeaponService.applyLoadout`/equip saves a `{mag, reserve, lastFireAt}` snapshot per weapon id and restores it when that weapon is equipped again, rather than resetting to a full magazine.

**Reason.** Without this, swapping to the second loadout slot and back is a free instant reload, which deletes the reload mechanic and makes ammo crates pointless.

**Consequence.** `lastFireAt` travels with the snapshot too, so swapping cannot be used to bypass the fire-rate check either. Ammo is genuinely a resource across the whole run, and the two loadout slots are a real tactical choice rather than a magazine doubler.

### Weapon upgrades are gated on kill XP as well as credits

**Decision.** Upgrading a weapon in `src/server/systems/ShopService.luau` requires both enough credits and enough per-weapon XP: `progress.xp >= WeaponsConfig.xpForLevel(progress.level)`, where XP is earned by getting kills with that specific weapon and the curve is `40 * L^2`. The XP is spent on upgrade, not just checked.

**Reason.** A credits-only upgrade path means a long safe run buys a maxed weapon you have never fired. Requiring kills with the weapon itself ties power to using it.

**Consequence.** Weapons level independently, so there is a real cost to switching mains. The catalog surfaces both gates (`affordable` is false when either credits or XP are short) so the shop UI can explain which one is missing.

### No pay-to-win, as a hard rule

**Decision.** Credits, weapons, weapon upgrades, skills and loadout slots are never purchasable with Robux. Only cosmetics and the post-death Continue are sold. The pass entries in `src/shared/config/ProductsConfig.luau` carry an explicit `cosmeticOnly = true` field.

**Reason.** A co-op run where one squad member bought their damage is not a co-op run. Keeping the line bright also keeps the shop logic simple: there is exactly one server-side currency path and Robux is not connected to it.

**Consequence.** Monetization pressure has to come from cosmetic depth and from the Continue, which caps the whole Robux surface. Any future product proposal that grants gameplay power is rejected by this entry rather than evaluated.

### ProcessReceipt idempotency keyed on the profile

**Decision.** `src/server/systems/MonetizationService.luau` records `receiptInfo.PurchaseId` into the player's `ProfileData.PurchaseHistory` and returns `PurchaseGranted` immediately if the key is already present. If the profile is not loaded, or the product id is unknown, or the grant handler fails, it returns `NotProcessedYet`.

**Reason.** Roblox retries `ProcessReceipt` until it is told the purchase was granted. Storing the receipt id anywhere other than the same saved profile the grant is written to would allow the grant and the record to diverge on a crash.

**Consequence.** Double-granting requires the profile save itself to fail, and a failed grant is retried by the platform rather than silently swallowed. `PurchaseHistory` grows without bound over a player's lifetime; that is accepted for now.

**Provisional.** Every id in `ProductsConfig` is still `0`. `ProductsConfig.isConfigured` guards the prompt, and `DeathService` falls back to granting the revive for free when the Continue product is unconfigured, so the paid path is written but has never been exercised against a real product. See `docs/monetization-test-plan.md`.

## Presentation

### The viewmodel is a jointed rig with a single anchored root

**Decision.** `src/client/systems/ViewmodelBuilder.luau` builds a model under the Camera in which only the `Root` part is anchored. Every other piece is unanchored and massless and hangs off the root through a joint chain: `Motor6D` for the animatable bones, `Weld` for static decoration. `pose()` writes `Root.CFrame` for the procedural layer and `Motor6D.Transform` for each bone, and lets the engine resolve the chain.

**Reason.** The rig was originally all-anchored and posed by writing every part's world `CFrame` each frame, because an early attempt at weld-driven animation did nothing at all. The observation behind that was correct (a joint cannot move an anchored part) but the conclusion drawn from it was too broad. The fix is not to abandon joints; it is to anchor only the root, which is what the reference first-person rigs do. Anchoring everything closed off the entire animation path.

**Consequence.** The rig now carries an `AnimationController` and an `Animator`, and each `Motor6D` is named after its bone, so a published Roblox animation targeting the same joint names drives this rig with no further work. Authored poses from `PoseLibrary` and a future external clip both write the same channel (`Transform`) so neither can corrupt the rest transform in `C0`. Static pieces are welded rather than jointed specifically so the Animation Editor lists only the eleven bones worth keyframing instead of every part.

**Verification.** The conversion was checked against the numbers measured before it, which are unchanged: fire slide travel 0.212 studs, reload slide 0.216, magazine drop 0.368, idle 0.000. Motor `Transform` and the resolved part transform agree to two decimals on every frame, and welded pieces sit at 0.0000 offset from their bone.

### Poses are authored in design units; SCALE is applied by the rig, never by hand

**Decision.** Every pose in `src/shared/config/PoseLibrary.luau` is written against the unscaled rig, in the same units as the rest offsets in `src/client/systems/ViewmodelBuilder.luau`. The builder multiplies the translation part of each authored offset by `ViewmodelConfig.SCALE` before composing it, in the `scaled()` helper. A pose author never writes a scale factor.

**Reason.** The first pose set shipped without this and every authored translation was 39 % oversized, because `SCALE` is 0.72 and the poses were being composed raw against an already-scaled rig. Nothing errored: the gun simply moved too far, which reads as "the animation is bad" rather than as a bug with a cause. Rotations are deliberately left unscaled; only translations carry units.

**Consequence.** Poses stay readable as physical distances and survive a change to `SCALE` without a rewrite. It also fixes the class of error to one place: if the viewmodel is ever rebuilt at a different size, `scaled()` is the only thing that has to be correct.

### Sequence blend-in is per sequence, and recoil has none

**Decision.** `AnimationTimings.BLEND_TIME` (0.12 s) is the default cross-fade when one sequence replaces another, but a sequence can override it with its own `blendTime`. `Fire` sets `blendTime = 0`.

**Reason.** A blend longer than the sequence it is blending into silently attenuates that sequence. The `Fire` pose held for 0.05 s against a 0.12 s blend never got past roughly 45 % of its authored value, measured as 0.025 studs of slide travel where the pose asks for 0.187. Recoil has to snap and then decay; the blend was turning the snap into a nudge.

**Consequence.** Any new short sequence must declare its own `blendTime`, and the check is arithmetic: if total duration is under `BLEND_TIME`, the default is wrong. Verification is numeric: measure the driven bone's travel relative to the receiver, not the camera, so the procedural sway layer is excluded.

### Weapon audio is per class with zone-driven reverb tails

**Decision.** Each weapon class has its own shot layers, cut from CC0 recording packs, with a short close layer plus a tail whose character is chosen by the acoustic zone the shooter is standing in. Zones are plain parts carrying an `AcousticSpace` attribute (`"Interior"` inside the hangar and under the shooting-range canopy); `src/client/systems/WeaponSfx.luau` reads the attribute rather than doing any acoustic analysis.

**Reason.** Weapon feel is the stated benchmark for this project, and the single biggest cheap win is making the same gun sound different indoors and outdoors. An attribute on a part is something a world builder can place with no audio code changes.

**Consequence.** Any new interior needs to remember to tag its zone, or shots inside it will use the open tail. The upside is that the reverb decision is data, not geometry analysis, and costs nothing at runtime.

### Fog is art direction, not just a draw-distance trick

**Decision.** Each biome preset in `src/shared/config/LightingConfig.luau` carries its own fog colour and start/end distances, and `src/client/systems/LightingDirector.luau` continuously lerps between them as the route crosses biomes. Values are chosen for silhouette and mood: Cornfield closes to 24 to 190 studs, City opens to 90 to 520.

**Reason.** Taken from the Into the Dead reference: fog defines the corridor the player reads and makes zombies resolve out of nothing at a controlled distance. Treating it purely as a culling knob produces flat grey distance in every biome.

**Consequence.** Fog cannot be tuned for performance alone: shortening it changes how a biome reads. Draw distance is handled separately by streaming and chunk culling in `src/server/systems/ChunkSpawner.luau`, so the two concerns stay independent. Biome transitions have to cross-fade lighting as well as materials, which is why the director lerps continuously instead of switching presets.

### Texel density and bounded bloom

**Decision.** Surface textures set `StudsPerTileU/V` explicitly per surface role instead of stretching one tile across a whole part, and the bloom pass in `src/client/systems/PostFx.luau` is clamped: intensity 0.34 with threshold 1.25 by default, raised to 0.62 / 1.0 only in the specific case of the sun being in frame in the forest biome.

**Reason.** Large parts with a single stretched texture read as blur at run speed, which was the actual visual complaint. Unbounded bloom then amplified that blur into a wash over bright surfaces.

**Consequence.** Every new textured surface has to pick a tile size deliberately; the helpers in `src/shared/util/TextureUtil.luau` and `src/shared/util/MaterialUtil.luau` take it as a parameter so it cannot be forgotten silently. Bloom is now an effect with a ceiling rather than a global brightness dial, and additional intensity is only added transiently by the damage pulse and death fade.

## World layout

### The run world was moved to `GameConstants.RUN_ORIGIN`

**Decision.** The running track is built around `RUN_ORIGIN = (-4000, 0, 0)`, 4300 studs from the hub at `HangarConfig.HUB_CENTER = (300, 0, 0)`.

**Reason.** The hub grew a desert ground plane, a road and a burning-city diorama, all of which extend far enough to physically intersect the streamed run chunks when both were built near the origin. Overlap meant hub props appearing in the middle of a run and streaming fighting over the same region.

**Consequence.** The two regions are now disjoint enough that `StreamingEnabled` can cull one entirely while the player is in the other, which is the main reason the split is worth its cost. The cost is that every run-world builder has to respect `RUN_ORIGIN`, and there is a known inconsistency: lateral clamping and chunk pivots are expressed relative to `RUN_ORIGIN`, but distance is still measured in absolute world Z via `root.Position:Dot(RUN_DIRECTION)`, which only works because `RUN_ORIGIN.Z` is 0. `src/server/systems/TrackBuilder.luau` still pivots the start platform in absolute space and has not been migrated.

## Content and process

### Stylized gore, declared and toggleable

**Decision.** The game keeps its gore (blood pools, gibs, zombies visibly feeding on the corpse) in a stylized, non-photoreal register. It is declared through the Roblox maturity questionnaire, a one-shot content warning is shown at client start by `src/client/ui/GoreWarningGui.luau` with Backspace to disable, and two independent settings (`bloodEnabled`, `dismembermentEnabled`) remain available in the Content category thereafter.

**Reason.** The death sequence is the emotional payload of a run, and sanitizing it removes the stakes. Roblox permits this content when it is declared, so the correct path is declaration plus player control rather than self-censorship.

**Consequence.** The audience is narrowed by the maturity rating. Both settings must be respected by every effect that draws blood or body parts, which is why the checks live in `DeathGore`, `GoreController` and `ZombieVfx` rather than in a single choke point: each system reads the setting itself.

**Provisional.** The rating outcome has not been validated against a live published experience yet.

### Assets go through the manifest pipeline, never generated

**Decision.** `assets/manifest.json` is the single source of truth. Real licensed files are dropped into `assets/audio/**` or `assets/textures/**`, `scripts/upload_assets.py` uploads anything without an id through Roblox Open Cloud and writes back the id and moderation state, and `scripts/sync_configs.py` regenerates `src/shared/config/AssetIds.luau` and `assets/LICENSES.md`. Audio must be genuine CC0 or licensed recordings.

**Reason.** Licensing has to be provable per asset, and moderation state has to be visible without opening the Roblox site. Generated audio was ruled out as a quality floor.

**Consequence.** `AssetIds.luau` is generated and must never be hand-edited. Missing or rejected ids are emitted as literal `0`, so every consumer guards on `id > 0` and silently no-ops, which is why the game runs correctly today with all twelve player animation slots still at `0`. The binaries themselves are git-ignored; only the manifest, licence file and generated ids are tracked.

### Remote names in one frozen table, remotes created lazily

**Decision.** `src/shared/net/Remotes.luau` holds every event and function name in a frozen table and creates the instance on demand: find-or-create on the server, `WaitForChild` on the client.

**Reason.** Remote names as string literals scattered across systems is the classic source of silent client/server mismatches. A single frozen table makes the whole surface greppable and typo-proof.

**Consequence.** Nothing has to care about instance creation order. The one wrinkle is that `Remotes.init()`, which pre-creates all twenty remotes (eighteen events, two functions), is called from exactly one place, `SquadService.init`, so remote pre-creation is coupled to a system that has nothing to do with it.

### Settings are persisted and sanitized server-side

**Decision.** Settings are stored in the profile and pushed to the client on load by `src/server/systems/SettingsPersistence.luau`, which validates every incoming key against the `SettingsConfig` schema (type check, slider clamp) and throttles saves to one per 1.5s per player.

**Reason.** This supersedes the original decision to keep settings client-only with no remotes. Once profiles existed, settings not surviving a rejoin became the more obvious problem, and any client-written value reaching a saved profile has to be schema-checked.

**Consequence.** `SettingsConfig` is now load-bearing in three places (the GUI builder, the client store defaults and the server sanitizer) so adding a key means adding it once and getting all three. The client store in `src/client/systems/SettingsService.luau` still owns the live values and the `observe` API; persistence sits underneath it rather than replacing it.

### Boot stages are isolated, commits are authored by the user

**Decision.** `src/server/init.server.luau` wraps every `init()` in a `runStage(name, fn)` pcall so a failing system warns instead of killing boot. `selene src/`, `python3 tools/validate_api.py` and `rojo build` all run before a commit, and commits carry no Claude co-author trailer or mention.

**Reason.** A single bad `Instance.new` used to take the whole server down: the crash that motivated `tools/validate_api.py`, which statically checks every constructed class and assigned property against the downloaded API dump. Isolating stages turns a hard crash into a missing subsystem.

**Consequence.** A broken system is easy to miss because the game still boots, so the server output has to be read after any world-builder change. The validation tool only catches static property and class errors, not logic ones.

### Zombies on a reduced R15 rig

**Decision.** `src/server/systems/ZombieFactory.luau` builds zombies as an 11-part model using the exact R15 joint names (`Root`, `Waist`, `Neck`, `LeftShoulder`, `RightShoulder`, `LeftHip`, `RightHip`) with `Humanoid.RigType = R15` and `HipHeight = 2.35`, but without elbows, wrists, knees or ankles. Part lookups moved behind `src/shared/util/ZombieRig.luau` (`torso`, `waitForTorso`, `neck`) so `ZombieAudio`, `ZombieVfx`, `UiSfx` and `ZombieAI` no longer hardcode a part named `Body`.

**Reason.** The old rig was a 2x3x1 slab with a head and a single `Neck` Motor6D. `assets/NEEDED.md` already specced all seven zombie clips as Mixamo R15 retargets, and `docs/asset-policy.md` rule 3 demands R15, but an R15 clip drives `Waist`, `LeftHip` and `RightShoulder`, none of which existed. `LoadAnimation` and `Play` would both have succeeded while nothing moved, so the retarget would have been paid for and thrown away. A full R15 was rejected because it roughly triples part and joint count per zombie, and the spawn-section work deliberately raises density several-fold.

**Consequence.** Unmodified R15 clips play as-is; Roblox drops tracks for the missing joints. Limbs swing as rigid segments with no knee or elbow break, which reads acceptably at silhouette distance and not at all in a close-up. Anything that wants a zombie's torso must go through `ZombieRig`, not `FindFirstChild("Body")`. All seven zombie animation ids are still `0`, so nothing animates yet: the rig is ready, the clips are not.

**Superseded (2026-09-29).** This rig, and the walker2 mesh rig after it, are now fallbacks; see "Zombies are skinned Sketchfab rigs" below.

### Easy is a slow chase, not a diorama

**Decision.** `DifficultyConfig.Easy` is `zombiesChase = true`, `zombieSpeedMultiplier = 0.45`, `damageMultiplier = 0.6`, `aggroDistance = 800` (lowered to 300 in the ITD2 values pass). Before the ITD2 pass it was `zombiesChase = false`, speed `0`, aggro `math.huge`.

**Reason.** With speed `0` the horde was scenery that still bit on touch, and `damageMultiplier` had no lever to pull because nothing ever reached the player. The three-radius state machine only calls `Humanoid:MoveTo` in `Alert`/`Attack`, and those are gated by `zombiesChase`, so a speed multiplier alone changes nothing; the gate has to open for Easy to differ from Medium by degree rather than by kind. 0.45x makes a Walker close at 6.3 studs/s against a 24 studs/s runner, which is a threat you can always outrun but cannot ignore. The section tier shift of -1 already thins the spawns.

**Consequence.** Easy players now meet moving zombies after 800 studs. Anyone relying on Easy as a no-pressure tour needs a new mode; nothing in the code provides one. Reverting is four numbers in `DifficultyConfig`.

### Fog is Atmosphere, never classic fog

**Decision.** `LightingConfig` presets carry `atmosphereDensity` and `atmosphereOffset` (0.8..0.95 and 0.42..0.8 in the run biomes) and `LightingDirector` writes both every Heartbeat. The `fogStart` / `fogEnd` fields stay in the presets but do nothing while an `Atmosphere` exists.

**Reason.** Roblox ignores `Lighting.Fog*` whenever an `Atmosphere` instance is present, so the old presets (density 0.28..0.5, offset 0) produced no fog at all and the run read as a clear evening. Classic fog without an Atmosphere was tried on a pillar stand: it darkens geometry but leaves the sky bright, so silhouettes stand against a clear backdrop instead of dissolving into haze. Only Density plus Offset gives the Into the Dead wall where pillars vanish between 120 and 160 studs and the sky remains.

**Consequence.** Fog is tuned by two numbers per biome and cannot be tuned by distance in studs; `ZOMBIE_SPAWN_AHEAD` 200 was checked to stay behind the wall. Anyone who deletes the Atmosphere to "fix" lighting silently switches the game to the ignored classic values.

### Hip aim owns the fire direction on the client

**Decision.** `src/client/systems/HipAim.luau` selects the nearest zombie in a 42° cone up to 70 studs, swings the viewmodel toward it (clamped ±38°/±22°, tightened to ±24°/±14° in the second visual round) and moves the crosshair with it. `WeaponController.tryFire` fires along `HipAim.fireDirection` once the lock passes 0.55 and falls back to `AimAssist` otherwise.

**Reason.** The camera is forward-locked, so the player cannot aim by turning. Into the Dead resolves this by pointing the gun at the nearest threat from the hip; once the gun visibly points at a zombie, the only honest reading is that the shot goes where the gun points. Firing along the camera while the gun aims elsewhere would look broken.

**Consequence.** No server change: the existing 100° validation cone already accepts the ±38° clamp. A zombie in the cone but behind cover fails the line-of-sight raycast and the aim returns to centre, so cover cannot be shot through. The 42° cone is narrower than the 54° horizontal half-FOV at the 74° vertical FOV, so the crosshair never leaves the screen; widening the cone past the half-FOV would need a screen clamp.

### A frontal collision is a grab, not a bite

**Decision.** `ZombieAI.onTouched` treats a hit inside `collisionDeathDistance` as a grab: lethal on Medium and Hard (`DifficultyConfig.grabLethal`), triple touch damage on Easy. Hits in the glance band and bites from behind keep the old health damage.

**Reason.** The ITD2 teardown and the implementation plan both describe the centre band as death and the outer band as a slide. The first implementation dealt 15 damage there instead, so running head-on into a clump produced several bites inside one second, the bite flash and the death cinematic at the same time, and no readable difference between "I clipped it" and "I ran into it". Health still matters for the rear bites of a chasing Runner and for Easy.

**Consequence.** Medium and Hard players die on the first frontal collision, which is the reference's rule and the reason the glance band exists. `DeathCause` is only set on grabs today; other causes can be added without touching the client.


## 2026-09-07: Asset policy judges results, not methods

The original policy banned code-authored animation and any synthesised audio because
nothing could be checked while it was being made. With the Studio screenshot loop,
Blender/RBXMonkey and usable AI generation in place, the ban was producing stiff
stock-Roblox motion and empty audio slots. The policy now allows any technique for any
rig (clips, mocap, AI motion, Luau poses, procedural layers, generated audio) gated by a
playtest, and widens sources to CC-BY, licensed packs and AI output with commercial
rights. Provenance stays strict: manifest entry and licence for everything, ids only
from real uploads, and nothing extracted from other games. See `docs/asset-policy.md`.

### Animation clips are retargeted from CC0 libraries by script

**Decision.** Zombie and player body clips come from the Quaternius Universal Animation Library (CC0) through `tools/animation_pipeline/glb_to_keyframes.py`, which writes `KeyframeSequence` files directly; Mixamo and the Blender add-on path in the same folder remain available but are no longer the blocker.

**Reason.** The Mixamo route needs an Adobe login, manual FBX exports and the Roblox Blender add-on, so every slot sat at `assetId = 0` for weeks. The revised asset policy allows any technique with recorded provenance; a CC0 library with a GLB per tier can be fetched and converted headlessly, and the output is the same XML the player run clip was uploaded as. Retargeting by relative world rotation sidesteps bone-roll conventions entirely, which is what made the old FBX bone-rename approach fragile.

**Consequence.** Clip quality is bounded by what the free tiers contain: the runner uses a human jog, feeding uses a kneeling repair loop, and no strafe loops exist. The reduced zombie rig drops elbow, wrist, knee and ankle tracks, so limbs stay straight. The baked hunch in `ZombieFactory` was cut to a third so the clip's own posture leads.

**Update (2026-09-29).** These clips now drive only the fallback zombie rigs and the player. Zombies use the clips that ship with their Sketchfab packs, baked by `tools/zombie_pack` (see below).

### Spawn events are formations, not dice rolls

**Decision.** `ZombieAI.spawnEvent` picks a named pattern (wall, diagonal, column, clump, single, loiter, risers, feast) from the section's `patternSet` and lays zombies out geometrically; sleepers (`Dormant`, `Feeding`) wake by distance.

**Reason.** Uniform random lateral placement produced noise the player could not read: no gates, no flanks, nothing to weave. Into the Dead's corridor is legible because its groups have shape and its dormant zombies react to you. A wall with one gap is a decision; a scatter is not.

**Consequence.** The seeded RNG stream changes, so an old seed gives a different world. Walls can only be as wide as the playable band, so the gap is always inside ±45. Dormant and feeding zombies need the rise and feeding clips; without them the pattern degrades to ordinary idle zombies.

### Zombie behaviour and spawn tiers use ITD2's measured values

**Decision.** `ZombiesConfig`, `ZombieBehaviourConfig`, `ZombieSpawnConfig` and `DifficultyConfig.aggroDistance` carry the numbers read out of Into the Dead 2's shipped data (section medians per tier, zombie and movement definitions from the zombie bundle), converted at 4 studs per metre. The corridor is ±30 studs with natural boundaries.

**Reason.** The first ITD2 pass copied the structure but kept invented radii, speeds and a 240-stud lane bounded by an invisible wall, which read as an empty plain with lamps. The reference's feel comes from a 7.5 m corridor, zombies that spawn within 8 m of your line and react from 30 m, walkers that never outrun you and hunters that do, and boundaries you can see.

**Consequence.** Medium is harder in the first 500 studs than before because zombies chase immediately. A runner who never steers dies between 120 and 260 studs; steering is the game. Spawn seeds changed again. `reactionDelay` and the position history are gone; any future juke tuning goes through `facingUpdateFreq` and `maxRotation`.

## 2026-09-28: Route forks

### Route choice is a physical vote at biome boundaries

**Decision.** Near the end of a biome the corridor splits into two entrances; the entrance holding more living players when the timer ends decides the next stretch, and `ChunkSpawner` inserts that location at the head of the route queue. Branches (Sewer, Forest, Metro) carry their own rules through new `LocationConfig` fields, and run modifiers keep applying on top with multiplied rewards.

**Reason.** Runs were a fixed shuffled sequence of biomes with no player agency. A physical vote keeps the run moving (no menu pause) and works the same for solo and a squad of three.

**Consequence.** Every branch must have both a cost and a reward or it becomes dead content. The sewer explosives ban depends on grenades existing, which they do not yet. **Provisional**: frequency, telegraph distance and the funnel back from the losing entrance are unsettled. See [[Route Forks]].

## 2026-09-29: Skinned zombies and MW2019 weapons

### Call of Duty: Modern Warfare (2019) is the weapon-feel reference

**Decision.** Weapon handling follows MW2019, from a written spec built on datamined MW2 (2022) state timers at 1 stud = 28 cm: every reload has a total length and an ammo-add moment; tactical and empty reloads differ (empty drops the magazine and adds the chambering action: AK rack, pistol slide release, Uzi cock); only the tail after ammo-add can be cut by firing; the pump loads shell by shell and a trigger press finishes the shell in hand, then fires after a fast exit; every weapon has a draw time; casings are visible pooled objects with surface landing sounds, and the pump ejects on the pump stroke; the shot is layered (close take, environment tail, low-ammo spring, last-round clack), sounds come from round-robin voices that are never restarted, and reload foley fires from animation markers.

**Reason.** MW2019 was already the presentation reference in [[Overview]], but the reload was a single timer, rounds appeared at its end, sounds played on timers that drifted off the hands, and casings were loose physics parts. MW's rules make ammo a readable decision (cancel early and keep the old count, or wait for the seat) and are documented well enough to copy with numbers.

**Consequence.** The timeline lives in `WeaponsConfig` helpers that `WeaponService` and `WeaponController` both call, so a timing change is one edit and the prediction cannot drift. Times are tied to the pack clips' markers (see "Clips play at natural speed"). Spec items not built yet: mech, punch and sub shot layers, reflection raycasts with slap delays, sidechain ducking and a master limiter, teammate distance layers, movement foley, hit and kill markers, wall pull-back and the first raise; they are listed in [[Roadmap]].

### Zombies are skinned Sketchfab rigs, not procedural or generated ones

**Decision.** Zombies wear three CC BY 4.0 skinned characters with their own authored clips (`ZombieSkins`, `ZombieRigs`, `ZombieFactory.buildSkinned`): Walker and Hazmat for the Walker archetype (65 / 35), Ghoul for the Runner. The reduced primitive rig and the Cube 3D walker2 rig stay only as fallbacks for when a rig asset has not loaded.

**Reason.** The procedural rig read as sticks, and the walker2 rebuild depended on generic CC0 human clips re-posed onto a mesh modelled with hanging arms (every clip swung the arms across the chest until the rest pose was rewritten). A pack whose clips were authored for its own skeleton plays correctly as soon as each clip is baked against the imported bones; the only per-pack fix was the Ghoul's constant root offset.

**Consequence.** Clips are per skin, so a new zombie type is a download, a bake and a `ZombieSkins` entry. Features that assumed the R15 joints do nothing on skinned rigs until a pack supplies them: rise and feeding clips, head tracking, the procedural corpse chew. Every pack is CC BY 4.0, so the authors have to be credited in game before release.

### Bullets hit bone-driven boxes; players are blocked by static boxes

**Decision.** Skinned zombies carry invisible, queryable, non-colliding boxes (`Head`, `Chest`, `Hips`, eight limb segments) that `ZombieHitboxes` moves onto their bones every `PreSimulation` through Motor6D `Transform`, plus two static colliding boxes (`UpperTorso`, `LowerTorso`) welded to the root above hip height. The touch `Hitbox` is unchanged.

**Reason.** Roblox raycasts a skinned MeshPart against its bind pose, so shooting the mesh would hit an invisible T-pose. Driving boxes through `Transform`, which does not replicate, keeps the work on the server where the raycasts happen and keeps headshots exact. The first version let the bone-driven boxes collide, and a box that dipped below hip height in a lunge or stumble dragged the Humanoid over, so collision moved to static blockers.

**Consequence.** Box sizes come from the bind pose and per-skin limb widths, so a new skin needs its limb bone pairs in `ZombieSkins`. Past 220 studs from every player the boxes stop following, which is safe because nobody shoots that far through the fog. `Head` stays the headshot contract with `WeaponService`, and the blockers keep the `UpperTorso` / `LowerTorso` names, so `ZombieRig`, sleepers and death handling work unchanged. Because a hit box can press against the player, the shot's head-to-camera line-of-sight ray now ignores `Workspace.Zombies`.

### Clips play at natural speed

**Decision.** Playback speed comes from the clip, not from a number the clip is stretched to fit. Zombie walk and run clips play at `speed / groundSpeed`, using the ground speed measured when the clip was baked, and `ZombieAnimator` picks among a skin's cycles the one that needs the least clamping (rate 0.55..2.4); a skin with only a shuffle gets a speed cap instead (Hazmat `maxSpeed` 2). Weapon reload times in `WeaponsConfig` are chosen to match the pack clips at natural speed or at most about 1.3 to 1.45x, with ammo-add on the clip's own `MagIn`, `SlideRelease`, `BoltForward` or `ShellIn` marker.

**Reason.** A fixed reference speed skated the feet (walker2 played its walk at half and its run at a third of the body speed), and squeezing a reload clip into an invented time makes the hands rush or drift away from the ammo counter. The clip's own motion is the ground truth.

**Consequence.** Tuning runs the other way round: to make a zombie faster, give it a faster cycle or accept the clamp; to shorten a reload, choose a different cut point on the clip and move ammo-add with it. The shotgun's fire rate dropped from 1.5 to 1.25 so the pump closes at 1.25x inside one interval. The AK and pistol tactical cut points (0.55 and 0.76) are estimates still to be checked frame by frame.

### First-person clips are baked into Luau, not uploaded

**Decision.** The first-person pack clips are baked by `tools/fps_pack` into ModuleScripts under `src/shared/viewmodel_clips/` and played by `ViewmodelClipPlayer`, which writes `Bone.Transform` every frame. The pack rigs themselves are Model assets loaded with `InsertService`.

**Reason.** It skips an Animation upload and moderation round per clip (the zombie route needs one per slot), and cuts, stretching and cross-fades are plain code. Roblox's importer drops unweighted bones and folds their transforms into the children, so baked local transforms would not match the imported rig; storing each bone's model-space change against its own rest pose does.

**Consequence.** About 2.3 MB of clip data ships in `ReplicatedStorage.Shared`. The five `animation/weapon/*` manifest slots are unused. A pack with a broken shared skin (the Uzi) needs a solved skin fix before either its rig or its clips are usable, and the same fix file has to be used for both.
