# Roadmap

Rewritten 2026-10-12 after the four-pass project review and the AV polish plan. The work now runs in five milestones, each with exit criteria a playtest can check. Items that cannot move without the project owner acting outside the codebase (Creator Dashboard, Mixamo downloads, publishing, look and listen sign-off) are marked **owner step**.

The task briefs live outside the wiki: the review's T1-T22 in `production/claude-desktop-tasks.md`, the AV tasks A1-A40 in `production/av-polish-tasks.md`, the current sprint in `production/sprints/`. See [[Progress]] for what each shipped layer contains, [[Architecture]] for how the systems fit together and [[Decisions]] for why the awkward parts are the way they are.

The target for presentation is Call of Duty: Modern Warfare (2019) for weapon audio, foley and the living camera, TTK Testing by Sable Digital for weapon feel on Roblox, and Into the Dead for the run and the biomes. The frame-by-frame TTK breakdown is in [[Research AAA on Roblox]].

## Done

Shipped layers, roughly in the order they landed:

- **Run core**: auto-run driver, lateral input, lane clamp, server distance and speed ramp in `DistanceTracker`; five procedural biomes from the chunk factory, then long maps chained with forks ([[Map Segments]], [[Prebuilt Maps]], [[Megascans]], [[Environment]]).
- **Zombies**: weighted spawning, the juke mechanic and the three-radius state machine in `ZombieAI`; three CC BY 4.0 skinned zombies with 22 clips, bone-driven hit boxes and held death poses ([[Gameplay Systems]]).
- **Hub, squad and flow**: hangar, vendor rooms, three boardable helicopters, squad lobby and launch; the helicopter intermission with cabin, crash beat and wake-up ([[Heli Intermission]]).
- **Death sequence**: corpse pose, feeding ring, corpse-eye camera, results and one Continue per run.
- **Weapons**: four classes with five upgrade levels, server-validated fire and ammo, Fab and committed first-person packs with tactical and empty reloads, casings, marker-driven foley, the low-ammo layer, stances, wall pullback, hit and kill markers, damage numbers ([[Stances]], [[Wall Pullback]], [[Hit Markers]], [[Weapon Audio]]).
- **Sound in space**: the spatial audio engine with distance curves, occlusion, reflections, a bus mix and a limiter; weapons play on it behind a switch until the listening pass ([[Weapon Audio]]).
- **Zombies layer**: kill credits banked at run end and the Perk Lab ([[Run Economy]]), diegetic weapon pickups and the supply drop ([[Weapon Pickups]]), the upgrade station ([[Upgrade Station]]), mission goals on the HUD ([[Goals HUD]]), route forks step 1 ([[Route Forks]]).
- **Bodies**: the Swat Guy soldier body, the third-person body layer and the coded locomotion sets ([[Soldier Body]], [[Third-Person Body]], [[Third-Person Locomotion]]).
- **Asset pipeline and credits**: `assets/manifest.json` as the single source of truth through Open Cloud, generated `AssetIds` and `LICENSES.md`, and the in-game credits panel ([[Assets Pipeline]], [[Credits]]).
- **Code health**: every comment removed from `src/` with `tools/strip_comments.py --check` keeping them out (2026-10-12).

## Decisions in force

| # | Decision |
| --- | --- |
| D1 | Zombies chase all the time but cannot catch a player who keeps running; they catch you when you stop, stumble or hit a barrier |
| D2 | PC first; console at PC parity through gamepad; phone and tablet supported, with degraded visuals allowed |
| D3 | Perks are wired into gameplay |
| D4 | No comments in code (done) |
| D5 | Distance credits per minute are capped at the base-speed rate times 1.1; kill and goal credits are not |
| D6 | Aiming is hip fire with an aim focus: holding aim pulls the weapon slightly toward centre, narrows FOV a little and calms sway, so the player reads as aiming; no full sight alignment |
| D7 | Arms are camo sleeves and gloves on every class |
| D8 | Reloads differ by ammo state: empty, partly spent and almost full each get their own animation and timing |
| D9 | State is visible everywhere: the magazine check and inspect show the real round count, and animations, textures, sounds and behaviour reflect what is happening to the weapon, the player and the zombies |
| D10 | The arsenal grows large: rifles, pistols, SMGs, machine guns, launchers, grenades. Every weapon is its own entry with its own pack; the committed AK ships as a second rifle beside the Fab M4 |

### The detail rule (D9)

The owner's bar for AAA is that nothing is generic. Every task checks itself against these questions before it closes:
- Does the presentation change with state? Ammo left, magazine empty or not, health, speed, surface underfoot, distance, wet or dry, damaged or clean.
- Can the player read that state without the HUD? Rounds visible in the magazine check, a lighter rattle near the end of a magazine, a heavier breath at low health, a limp on a crippled zombie.
- Are there variants instead of one clip or one sound? Reloads per ammo state, impacts per surface, deaths per hit direction, footsteps per surface.

Open for the owner:

| Call | Options | Blocks |
| --- | --- | --- |
| Slice anchor rifle | Both the AK and the M4 ship (D10). The art director recommends the AK as the vertical slice anchor: camo sleeves already match D7, it lives in the public repo so CI builds it, and the M4 needs new arms and a value lift. Captures in production/captures/rifle-compare.jpg | Quality bar sign-off |
| Boundary clock | Each map has its own time of day, and the lighting blend at a map boundary moves the clock, so the sun or moon visibly races across the sky for a few seconds. Keep that sweep, hide the clock change behind the fork (fog or tunnel), or give every map the same time | Lighting passes |

## Milestones

Sprints are two weeks. There is no velocity history yet, so the targets are re-baselined after sprint 1.

| # | Theme | Target |
| --- | --- | --- |
| M1 | Secure foundation | end of sprint 2 |
| M2 | Vertical slice: City night, Rifle, skinned zombies at the bar | sprints 3-6 |
| M3 | Scale presentation to every weapon and zombie, gamepad | sprints 7-8 |
| M4 | Every biome, touch and the Low tier | sprints 9-10 |
| M5 | Public test readiness | sprints 11-12 |

### M1 Secure foundation

Contains T1, T2, T3 (split into server multipliers and the speed path), T4, T5, T6, T11, T14, T18, T21, T22, and A1-A5 (asset guidance, worktree setup, generation probe, quality bar, capture harness).

Exit criteria:
- CI is green on main, and a deliberately broken test turns it red.
- In a non-Studio server an equip for an unowned weapon is ignored (**owner step** for the live check).
- Moving the HumanoidRootPart 5000 studs during a run changes neither credits nor the leaderstat, and a test covers the clamp.
- Every perk has a measurable effect; the combined reload multiplier stays at or above 0.6 and max health at or below 180.
- A 36 studs/s run earns at most 1.1 times the distance credits of a 24 studs/s run (test in `tests/economy`).
- Every Continue receipt resolves, the timeout case included; product id 0 grants nothing outside Studio.
- A thrown error in one client init leaves the HUD, weapons and death flow working.
- Non-finite numbers are rejected on every remote that takes one (test).
- [[Performance]] holds the baseline numbers and names the measurement method later tasks reuse.
- The Open Cloud key never appears in a process argument list.
- A worktree made by `scripts/worktree_setup.sh` builds, draws the Fab rifle in Studio and shows a clean `git status`.
- The asset guidance matches the 2026-09-07 policy, and generated assets carry `generator` and `terms` in the manifest and in `LICENSES.md`.
- The Studio MCP generation tools and the audio upload quota are checked and written down.
- The quality bar (`docs/av/vertical-slice-bar.md`, at most 30 rows tagged P0 or P1) is signed off by the owner, and the capture harness reproduces its shots.

### M2 Vertical slice

Scope: the City map at night, the Rifle only, the skinned zombies, played solo. Everything the player sees and hears in that slice reaches the bar before any of it is copied to other content. It opens with T9 (relentless chase), T15 (light budget and quality tiers), T16, T17 (pooling, then the WeaponVfx split) and T20 (ZombieAI split), because the AV tasks build on them. Then A6-A31: the baseline capture, the weapon audio listening pass and the legacy removal, the mix master, the mech and punch layers, impacts, distant shots, markers, City ambience, the living camera, the weapon motion layer, arms, clip polish, the first raise, rifle surfaces, zombie flinch, death and wound materials, pursuit audio, muzzle, impact and blood effects, City lighting, decals, up to three hero props, the colour grade and the hit direction indicator.

Exit criteria:
- Every P0 row of the bar passes in an owner review of a 5-minute Medium run, with the verdict, date and capture recorded in the row; P1 rows are tracked.
- No manifest slot used by the slice is `needed` or `placeholder`.
- `SfxConfig.WEAPONS_ON_ENGINE` and the legacy weapon audio path are gone.
- Every bus sits within 3 LU of its loudness target.
- T9 holds on Medium: an auto-running player with no steering input is never reached from behind; a player who stops is reached within about 3 s.
- With 60 zombies alive the zombie server step stays under 0.3 ms by the [[Performance]] method, and `InstanceCount` stays within 2 percent over 30 s of fire after warm-up.
- At most 12 live PointLights with 6 chunks ahead on High, with 2 reserved for muzzle flashes.
- PC High shows no frame time regression against the M1 baseline.
- A dummy remote shooter reads as near, mid and far at 30, 200 and 600 studs.
- All tests, selene, `validate_api.py`, `strip_comments.py --check` and `rojo build` are green.

### M3 Scale presentation

Contains T7a (gamepad and console menus), T10 (telemetry), T13 (shotgun and TTK), and A32-A37: clip defects, class parity for Pistol, SMG and Shotgun, zombie rise, feed and Hazmat death clips, third-person locomotion clips, the HUD pass and the upgrade announcer.

Exit criteria:
- Pistol, SMG and Shotgun each pass the bar's weapon rows.
- The SMG reload and equip defects and the shotgun shell slide are gone in frame-step captures.
- Risers rise, feeders chew, the Hazmat dies on a clip (**owner step**: the Mixamo downloads).
- Teammates use the class locomotion sets with no fallback (**owner step**: the Mixamo downloads).
- A full run and every menu, the credits panel included, work with a gamepad only; PC controls are unchanged.
- The smallest HUD text is at least 24 px at 1080p in the console emulator.
- A Luau test covers the shotgun one-shot rule, and [[Gameplay Systems]] has the TTK table.
- Telemetry events appear in the Creator Dashboard after a published test (**owner step**).

### M4 Every biome, every platform

Contains T7b (touch), A38 (Forest, Wasteland, Farmstead and Cornfield, each through lighting, materials and the ambience bed) and A39 (Low tier audiovisual budget).

Exit criteria:
- Each of the four biomes passes the bar's world rows, and its bed crossfades at the boundary.
- A full run is playable with touch only, and touch buttons stay clear of the HUD at 16:9, 19.5:9 and 4:3.
- Low tier frame time beats the M1 baseline in the phone emulator, and the pursuit cue is still audible.

### M5 Public test readiness

Contains T8 (first 60 seconds), T12 (squad scaling, spectate, squad goal), A40 (placeholder release gate), and the owner items below.

Exit criteria:
- A new profile gets its first kill within 25 s.
- Zombies per player per minute stay within 20 percent across 1, 2 and 3 players; a dead player can cycle spectate targets; the squad goal pays every member once.
- `refresh_status.py --release` fails on any placeholder and on any needed slot whose system ships, and passes on the release build.
- One owner-run 2-player session confirms distant shots, pursuit audio and teammate locomotion.
- Product ids are set, the maturity questionnaire is done and the live receipt test from `docs/monetization-test-plan.md` passes (**owner step**).

## Critical path

T1, T2, then T3 inside M1. The quality bar and the capture harness gate every M2 review. In M2 the chain is T17 then the WeaponVfx split, then T15's light budget, then the muzzle and impact effects; T16 then the ZombieAI split, then zombie flinch and death; the weapon audio listening pass, then the legacy removal, then the mech and punch layers. The owner's look and listen reviews are on the critical path for every M2 exit row, so they are batched twice per sprint.

## How parallel work stays safe

- **One Studio lane.** Studio MCP drives one Studio session, so only one task at a time plays, captures or verifies. Code lanes merge first and hand over a verification note.
- **One asset lane.** Assets are authored in parallel, but only one task at a time writes the manifest, `AssetIds.luau`, `LICENSES.md` and `NEEDED.md`.
- **One writer per shared module.** The order per module (WeaponService, DistanceTracker, ZombieAI, ZombieVfx, WeaponVfx, WeaponSfx, the viewmodel modules, lighting, PostFx, settings and the rest) is in the single-writer map of `production/av-polish-tasks.md`.
- **Worktrees carry the Fab content.** The Fab packs are gitignored, so a plain worktree falls back to the legacy viewmodel; viewmodel work runs only in the main checkout or a worktree from `scripts/worktree_setup.sh` ([[Development Policy]]).
- **Line numbers are stale.** The comment strip moved every line, so briefs locate code by symbol name.

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The AV briefs rest on unaudited premises (two already failed: the camera bob exists, no ragdoll exists) | High | Med | "Verify first" lines; targeted audit rerun before M2 planning |
| Owner time for look and listen reviews holds up M2 | High | High | The bar turns reviews into a checklist; two review slots per sprint |
| The single Studio session serialises verification | High | Med | Code in parallel, one verification queue in merge order |
| The audio upload quota is too small for about 40 M2 uploads | Med | High | Checked in M1; fallback packs variants into one file with playback regions |
| Studio MCP generators cannot make what a brief assumes (alpha sprite sheets, uploadable ids) | Med | Med | Checked in M1; Blender renders and licensed packs as the fallback |
| Moderation delays leave slots silent | Med | Med | Upload early in the sprint; id 0 degrades to silence |
| Mixamo downloads need the owner's account | High | Med | Exact clip lists in the briefs; agents do the retarget and wiring |
| Generated asset terms change | Low | High | Service and terms date recorded per manifest row |
| Merge conflicts in the god modules | Med | Med | Single-writer map; the ZombieAI and WeaponVfx splits land early in M2 |

## Later

- **Route forks steps 4-8**: frozen until grenades exist ([[Route Forks]]).
- **Run music intensity layer**, the low-health heartbeat, more hero props and teammate revive: backlog until the owner or game design asks for them.
- **More biomes and zombie types**: both are data, an entry in `LocationsConfig` or `ZombiesConfig`.
- **TeleportService**: only if the hub and the run ever split into separate places; the transport is already behind `FlowService` phases.

## Blocked on the owner

| Item | What unblocks it |
| --- | --- |
| Continue product, VIP and Supporter passes | Create the items in the Creator Dashboard and paste the ids into `ProductsConfig` |
| Real receipt testing | Publish and run `docs/monetization-test-plan.md` with a non-owner account |
| Maturity questionnaire | Complete it at publish time |
| Mixamo clips (player strafes, third-person sets, zombie rise and feed) | Download the clips listed in the A34 and A35 briefs |
| Audio upload quota | Read it in the Creator Dashboard for the M1 probe |
| Look and listen sign-off | Score the bar rows in the batched reviews |
