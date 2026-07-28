# Decisions

The decision log for Task Force Z. Every entry records what was decided, why, and what it costs or enables downstream. Entries marked **Provisional** are still expected to change; everything else is treated as settled and should not be re-litigated without a new entry here.

Related: [[Architecture]], [[Performance]], [[Progress]], [[Roadmap]].

## Standing decisions

### One place, transport abstracted

**Decision.** The whole flow — boot, hangar hub, helicopter lobby, run, death, reward — lives in a single Roblox place. Moving between the hub and the run is a CFrame teleport, not a `TeleportService` call.

**Reason.** `TeleportService` does not work in a Studio playtest, so a multi-place layout would make the core loop untestable in the only environment available day to day.

**Consequence.** Hub and run geometry coexist in one DataModel and have to be kept physically apart (see the run-origin entry below). If real place-to-place teleports are ever needed, the phase machine in `src/server/systems/FlowService.luau` is the single seam that has to change — no gameplay system reads the transport directly.

### Humanoid movement with client ownership, distance measured on the server

**Decision.** The run is driven by `Humanoid:Move()` called every RenderStepped from `src/client/controllers/RunController.luau`. The character stays under the client's network ownership and replicates natively. The server independently measures progress in `src/server/systems/DistanceTracker.luau` as `root.Position:Dot(RUN_DIRECTION)`.

**Reason.** Client-owned humanoid movement is the only way to get responsive input at run speed on Roblox. Server-side simulation of the runner would add a round trip to every lateral dodge, which is the entire skill expression of the game.

**Consequence.** Movement is exploitable in principle, but the payout is not: distance is read from the replicated root position on the server, and rewards, kills and credits are all computed server-side. Anything that pays out has to be derived from server-observed state, never reported by the client.

### Soft lane clamp instead of a wrap teleport

**Decision.** When the runner reaches the lane edge, `RunController.clampToField` slides the root back to the boundary. It does not wrap the player to the opposite side, and it does not rely on `Touched` events against the barrier parts.

**Reason.** A wrap teleport reads as a bug at speed, and `Touched` is unreliable at run velocity — a fast lateral move can tunnel through a thin barrier without ever firing. Position clamping is frame-accurate and cannot be missed.

**Consequence.** The physical side barriers built by `ChunkFactory` are now a backstop rather than the mechanism. The threshold constant is still called `GameConstants.WALL_WRAP_MARGIN`, a leftover name from the wrap era that no longer describes what it does.

### Server-owned zombies chasing a lagged player position

**Decision.** Every zombie root is pinned with `SetNetworkOwner(nil)` in `src/server/systems/ZombieAI.luau`, and each one paths toward a sample of the player's position taken `config.reactionDelay` seconds ago rather than the current position.

**Reason.** Server ownership keeps the horde authoritative and consistent for all three squad members. The delayed sample turns zigzag juking into the intended counterplay: the horde commits to where you were, so changing direction makes it overshoot.

**Consequence.** The delay is the primary difficulty dial per archetype — Walker 0.75s, Runner 0.35s in `src/shared/config/ZombiesConfig.luau` — so Runners track much more tightly. Server-owned physics for a large horde is also the main CPU cost of a run; the AI runs on a 0.2s tick rather than per-frame to pay for it.

### Aggro gated per difficulty by run distance

**Decision.** Zombies only begin chasing once `DistanceTracker.getMaxDistance()` passes `difficulty.aggroDistance`, and the flag is mirrored to the `Workspace.ZombiesAggro` attribute for client audio and VFX to react to.

**Reason.** A single global aggro rule cannot serve both a first-time player and a Hard run. Gating on distance travelled gives every difficulty a different length of grace period at the start of the run instead of a different proximity radius.

**Consequence.** The three tiers in `src/shared/config/DifficultyConfig.luau` are deliberately far apart: Hard aggros at 0 studs, Medium at 500, Easy sets `zombiesChase = false` and `aggroDistance = math.huge` so zombies never move at all. **Provisional** — Easy also sets `zombieSpeedMultiplier = 0`, which makes it a pure obstacle course rather than an easy horde; that is a tuning placeholder, not a final design.

### Custom zombie rigs must set `RequiresNeck = false`

**Decision.** `src/server/systems/ZombieFactory.luau` sets `humanoid.RequiresNeck = false` on every built rig.

**Reason.** A Humanoid without a neck Motor6D named exactly as Roblox expects is killed instantly by the engine. The part-based zombie rig does not match the standard skeleton.

**Consequence.** Any future custom Humanoid rig in this project has to carry the same flag. This is a hard engine constraint, not a preference.

### Gore is rendered by the client, the server only reports the event

**Decision.** The server broadcasts the fact of a death (`DeathBegan`) and hit events; each client decides what to draw based on its own `bloodEnabled` / `dismembermentEnabled` settings in `src/client/systems/DeathGore.luau` and `src/client/systems/ZombieVfx.luau`.

**Reason.** If the server spawned gibs and blood parts, one player's content toggle could not hide them — they would already exist in the shared world.

**Consequence.** Gore is presentation-only and never affects gameplay state. The cost is that gore is not authoritative: two players watching the same death can legitimately see different things.

### Forced first person during the run

**Decision.** Runs are locked to first person. `src/client/controllers/CameraController.luau` hides the local character every frame with `LocalTransparencyModifier`, and visibility is restored for the death cinematic.

**Reason.** A design call — third person flattens the threat of something chasing you from behind, which is the whole premise.

**Consequence.** Everything about weapon presentation had to be built for first person, which is where the viewmodel work comes from. The `firstPersonBody` setting lets a player keep their visible body, but the head and accessories are always hidden regardless, because they clip the camera.

### Managed death instead of engine ragdoll

**Decision.** `BreakJointsOnDeath = false` is set in `FlowService`, the server anchors and poses the corpse, and `Players.RespawnTime` is set to 600 so nothing auto-respawns — every respawn is an explicit `player:LoadCharacter()`.

**Reason.** The death sequence is a cinematic: the corpse has to stay intact and readable while zombies swarm and feed on it, and the player has to be able to sit in the results screen without the engine yanking them back.

**Consequence.** Respawn is now entirely the responsibility of `src/server/systems/DeathService.luau`, including hub deaths, which need a separate watcher with a delay. Forgetting to call `LoadCharacter` on any path leaves the player permanently dead.

## Persistence and economy

### ProfileStore with a Studio mock fallback

**Decision.** Player data is persisted with ProfileStore (the only Wally dependency). On startup `src/server/systems/ProfileManager.luau` probes a DataStore; if the probe fails in Studio it silently switches to `store.Mock`.

**Reason.** Studio without API access cannot reach DataStores, and hard-failing there would make the entire economy untestable locally. Session locking and the template/migration model were the reasons for choosing ProfileStore over raw `DataStoreService`.

**Consequence.** Progression appears to work in Studio but nothing persists. This is deliberately observable via `ProfileManager.isUsingMock()` and must be checked before trusting any local test of the economy. Profile shape is versioned; `migrate()` runs on load and the template is the single source of truth for new fields.

### The server is authoritative for ammo, damage and credits

**Decision.** A hard rule, also recorded in `CLAUDE.md`. The client predicts and displays; it never decides. `src/server/systems/WeaponService.luau` owns mag and reserve counts, runs the damage raycast, and validates every fire request: fire rate within a 3% tolerance, direction magnitude in the 0.9–1.1 band, the claimed muzzle origin within 5 studs of the character's head or root, and an unobstructed raycast between the character and that origin.

**Reason.** Everything in the game converts into credits, and credits buy permanent progression. Any client-trusted number is a direct exploit into the economy.

**Consequence.** Client-side prediction has to be reconciled against server attributes (`AmmoMag`, `AmmoReserve`, `Reloading`), which is why `src/client/systems/WeaponController.luau` maintains a predicted magazine and a local reload lockout separate from the authoritative state. Every new remote is expected to validate its arguments the same way.

### Per-weapon ammo persists across swaps

**Decision.** `WeaponService.applyLoadout`/equip saves a `{mag, reserve, lastFireAt}` snapshot per weapon id and restores it when that weapon is equipped again, rather than resetting to a full magazine.

**Reason.** Without this, swapping to the second loadout slot and back is a free instant reload, which deletes the reload mechanic and makes ammo crates pointless.

**Consequence.** `lastFireAt` travels with the snapshot too, so swapping cannot be used to bypass the fire-rate check either. Ammo is genuinely a resource across the whole run, and the two loadout slots are a real tactical choice rather than a magazine doubler.

### Weapon upgrades are gated on kill XP as well as credits

**Decision.** Upgrading a weapon in `src/server/systems/ShopService.luau` requires both enough credits and enough per-weapon XP: `progress.xp >= WeaponsConfig.xpForLevel(progress.level)`, where XP is earned by getting kills with that specific weapon and the curve is `40 * L^2`. The XP is spent on upgrade, not just checked.

**Reason.** A credits-only upgrade path means a long safe run buys a maxed weapon you have never fired. Requiring kills with the weapon itself ties power to using it.

**Consequence.** Weapons level independently, so there is a real cost to switching mains. The catalog surfaces both gates — `affordable` is false when either credits or XP are short — so the shop UI can explain which one is missing.

### No pay-to-win, as a hard rule

**Decision.** Credits, weapons, weapon upgrades, skills and loadout slots are never purchasable with Robux. Only cosmetics and the post-death Continue are sold. The pass entries in `src/shared/config/ProductsConfig.luau` carry an explicit `cosmeticOnly = true` field.

**Reason.** A co-op run where one squad member bought their damage is not a co-op run. Keeping the line bright also keeps the shop logic simple — there is exactly one server-side currency path and Robux is not connected to it.

**Consequence.** Monetization pressure has to come from cosmetic depth and from the Continue, which caps the whole Robux surface. Any future product proposal that grants gameplay power is rejected by this entry rather than evaluated.

### ProcessReceipt idempotency keyed on the profile

**Decision.** `src/server/systems/MonetizationService.luau` records `receiptInfo.PurchaseId` into the player's `ProfileData.PurchaseHistory` and returns `PurchaseGranted` immediately if the key is already present. If the profile is not loaded, or the product id is unknown, or the grant handler fails, it returns `NotProcessedYet`.

**Reason.** Roblox retries `ProcessReceipt` until it is told the purchase was granted. Storing the receipt id anywhere other than the same saved profile the grant is written to would allow the grant and the record to diverge on a crash.

**Consequence.** Double-granting requires the profile save itself to fail, and a failed grant is retried by the platform rather than silently swallowed. `PurchaseHistory` grows without bound over a player's lifetime; that is accepted for now.

**Provisional.** Every id in `ProductsConfig` is still `0`. `ProductsConfig.isConfigured` guards the prompt, and `DeathService` falls back to granting the revive for free when the Continue product is unconfigured — so the paid path is written but has never been exercised against a real product. See `docs/monetization-test-plan.md`.

## Presentation

### The viewmodel is posed by direct CFrame writes, not welds

**Decision.** `src/client/systems/Viewmodel.luau` builds an anchored part rig parented under the Camera and writes `piece.part.CFrame = rootCFrame * offset` for every piece on RenderStepped. There are no Motor6Ds and no weld-driven animation.

**Reason.** This was a real bug, not a style preference: `Weld.C0` does not move anchored parts. Parts parented to the Camera have to be anchored to avoid falling, so the natural weld-rig approach silently produced a rigid, unanimated gun.

**Consequence.** Recoil, sway, stride bob, breathing, the sprint pose, equip-in and the multi-stage reload are all authored as CFrame offsets composed per frame, which is more code but gives exact control over timing. It also means the viewmodel cannot reuse Roblox animation assets — every motion is procedural. The third-person weapon model other players see is a separate welded rig on the character and does not share this code path.

### Weapon audio is per class with zone-driven reverb tails

**Decision.** Each weapon class has its own shot layers, cut from CC0 recording packs, with a short close layer plus a tail whose character is chosen by the acoustic zone the shooter is standing in. Zones are plain parts carrying an `AcousticSpace` attribute (`"Interior"` inside the hangar and under the shooting-range canopy); `src/client/systems/WeaponSfx.luau` reads the attribute rather than doing any acoustic analysis.

**Reason.** Weapon feel is the stated benchmark for this project, and the single biggest cheap win is making the same gun sound different indoors and outdoors. An attribute on a part is something a world builder can place with no audio code changes.

**Consequence.** Any new interior needs to remember to tag its zone, or shots inside it will use the open tail. The upside is that the reverb decision is data, not geometry analysis, and costs nothing at runtime.

### Fog is art direction, not just a draw-distance trick

**Decision.** Each biome preset in `src/shared/config/LightingConfig.luau` carries its own fog colour and start/end distances, and `src/client/systems/LightingDirector.luau` continuously lerps between them as the route crosses biomes. Values are chosen for silhouette and mood — Cornfield closes to 24–190 studs, City opens to 90–520.

**Reason.** Taken from the Into the Dead reference: fog defines the corridor the player reads and makes zombies resolve out of nothing at a controlled distance. Treating it purely as a culling knob produces flat grey distance in every biome.

**Consequence.** Fog cannot be tuned for performance alone — shortening it changes how a biome reads. Draw distance is handled separately by streaming and chunk culling in `src/server/systems/ChunkSpawner.luau`, so the two concerns stay independent. Biome transitions have to cross-fade lighting as well as materials, which is why the director lerps continuously instead of switching presets.

### Texel density and bounded bloom

**Decision.** Surface textures set `StudsPerTileU/V` explicitly per surface role instead of stretching one tile across a whole part, and the bloom pass in `src/client/systems/PostFx.luau` is clamped — intensity 0.34 with threshold 1.25 by default, raised to 0.62 / 1.0 only in the specific case of the sun being in frame in the forest biome.

**Reason.** Large parts with a single stretched texture read as blur at run speed, which was the actual visual complaint. Unbounded bloom then amplified that blur into a wash over bright surfaces.

**Consequence.** Every new textured surface has to pick a tile size deliberately; the helpers in `src/shared/util/TextureUtil.luau` and `src/shared/util/MaterialUtil.luau` take it as a parameter so it cannot be forgotten silently. Bloom is now an effect with a ceiling rather than a global brightness dial, and additional intensity is only added transiently by the damage pulse and death fade.

## World layout

### The run world was moved to `GameConstants.RUN_ORIGIN`

**Decision.** The running track is built around `RUN_ORIGIN = (-4000, 0, 0)`, 4300 studs from the hub at `HangarConfig.HUB_CENTER = (300, 0, 0)`.

**Reason.** The hub grew a desert ground plane, a road and a burning-city diorama, all of which extend far enough to physically intersect the streamed run chunks when both were built near the origin. Overlap meant hub props appearing in the middle of a run and streaming fighting over the same region.

**Consequence.** The two regions are now disjoint enough that `StreamingEnabled` can cull one entirely while the player is in the other, which is the main reason the split is worth its cost. The cost is that every run-world builder has to respect `RUN_ORIGIN`, and there is a known inconsistency: lateral clamping and chunk pivots are expressed relative to `RUN_ORIGIN`, but distance is still measured in absolute world Z via `root.Position:Dot(RUN_DIRECTION)`, which only works because `RUN_ORIGIN.Z` is 0. `src/server/systems/TrackBuilder.luau` still pivots the start platform in absolute space and has not been migrated.

## Content and process

### Stylized gore, declared and toggleable

**Decision.** The game keeps its gore — blood pools, gibs, zombies visibly feeding on the corpse — in a stylized, non-photoreal register. It is declared through the Roblox maturity questionnaire, a one-shot content warning is shown at client start by `src/client/ui/GoreWarningGui.luau` with Backspace to disable, and two independent settings (`bloodEnabled`, `dismembermentEnabled`) remain available in the Content category thereafter.

**Reason.** The death sequence is the emotional payload of a run, and sanitizing it removes the stakes. Roblox permits this content when it is declared, so the correct path is declaration plus player control rather than self-censorship.

**Consequence.** The audience is narrowed by the maturity rating. Both settings must be respected by every effect that draws blood or body parts, which is why the checks live in `DeathGore`, `GoreController` and `ZombieVfx` rather than in a single choke point — each system reads the setting itself.

**Provisional.** The rating outcome has not been validated against a live published experience yet.

### Assets go through the manifest pipeline, never generated

**Decision.** `assets/manifest.json` is the single source of truth. Real licensed files are dropped into `assets/audio/**` or `assets/textures/**`, `scripts/upload_assets.py` uploads anything without an id through Roblox Open Cloud and writes back the id and moderation state, and `scripts/sync_configs.py` regenerates `src/shared/config/AssetIds.luau` and `assets/LICENSES.md`. Audio must be genuine CC0 or licensed recordings.

**Reason.** Licensing has to be provable per asset, and moderation state has to be visible without opening the Roblox site. Generated audio was ruled out as a quality floor.

**Consequence.** `AssetIds.luau` is generated and must never be hand-edited. Missing or rejected ids are emitted as literal `0`, so every consumer guards on `id > 0` and silently no-ops — which is why the game runs correctly today with all twelve player animation slots still at `0`. The binaries themselves are git-ignored; only the manifest, licence file and generated ids are tracked.

### Remote names in one frozen table, remotes created lazily

**Decision.** `src/shared/net/Remotes.luau` holds every event and function name in a frozen table and creates the instance on demand — find-or-create on the server, `WaitForChild` on the client.

**Reason.** Remote names as string literals scattered across systems is the classic source of silent client/server mismatches. A single frozen table makes the whole surface greppable and typo-proof.

**Consequence.** Nothing has to care about instance creation order. The one wrinkle is that `Remotes.init()` — which pre-creates all seventeen — is called from exactly one place, `SquadService.init`, so remote pre-creation is coupled to a system that has nothing to do with it.

### Settings are persisted and sanitized server-side

**Decision.** Settings are stored in the profile and pushed to the client on load by `src/server/systems/SettingsPersistence.luau`, which validates every incoming key against the `SettingsConfig` schema (type check, slider clamp) and throttles saves to one per 1.5s per player.

**Reason.** This supersedes the original decision to keep settings client-only with no remotes. Once profiles existed, settings not surviving a rejoin became the more obvious problem, and any client-written value reaching a saved profile has to be schema-checked.

**Consequence.** `SettingsConfig` is now load-bearing in three places — the GUI builder, the client store defaults and the server sanitizer — so adding a key means adding it once and getting all three. The client store in `src/client/systems/SettingsService.luau` still owns the live values and the `observe` API; persistence sits underneath it rather than replacing it.

### Boot stages are isolated, commits are authored by the user

**Decision.** `src/server/init.server.luau` wraps every `init()` in a `runStage(name, fn)` pcall so a failing system warns instead of killing boot. `selene src/`, `python3 tools/validate_api.py` and `rojo build` all run before a commit, and commits carry no Claude co-author trailer or mention.

**Reason.** A single bad `Instance.new` used to take the whole server down — the crash that motivated `tools/validate_api.py`, which statically checks every constructed class and assigned property against the downloaded API dump. Isolating stages turns a hard crash into a missing subsystem.

**Consequence.** A broken system is easy to miss because the game still boots, so the server output has to be read after any world-builder change. The validation tool only catches static property and class errors, not logic ones.
