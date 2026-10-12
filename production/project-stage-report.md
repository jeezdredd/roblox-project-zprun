# Project Stage Analysis

**Date**: 2026-10-12
**Stage**: Production
**Stage Confidence**: PASS. Configured `project.stage: Production` matches the observed tree: 237 Luau files, about 53,600 lines, 159 commits, 18 test suites.

Tier: `modes.rigor: minimal`. Absent GDDs, art bible, ADRs, epics and sprint plans are not gaps at this tier. The design record lives in `wiki/project-zprun/` (28 notes) instead of `design/`.

## Completeness Overview

| Area | State |
| --- | --- |
| Design | Wiki carries systems, decisions, roadmap. Roadmap "Next" is stale: intermission, weapon pickups, upgrade station and Perk Lab are already built. |
| Code | Production scale. Server 59 files, client 82, shared 92. Six modules over 850 lines. `selene` and `validate_api.py` clean. |
| Architecture | Wiki `Architecture.md` and `Decisions.md`. No ADR files, not required at this tier. |
| Production | No sprint tracking, not required at this tier. Work is driven by chat sessions. |
| Tests | 15 Luau suites and 3 Python suites, all passing on 2026-10-12. No runner script and no CI, so nothing keeps them passing. |

## Review summary

Four specialist passes ran on 2026-10-12: game design and balance, code architecture, security, performance. Load-bearing claims were rechecked by hand before landing here.

### Blocks a public test

1. **Distance pay trusts the client.** `DistanceTracker.luau:164` credits `root.Position` with no speed or teleport check, and the player owns their character physics. A teleport banks unlimited credits and tops the leaderboard.
2. **Every weapon is free.** `WeaponsConfig.ALL_WEAPONS_UNLOCKED = true` is not Studio-gated, and the server skips the ownership check at `WeaponService.luau:194`.
3. **Perks do nothing.** Players can buy six perks and three slots for about 23,750 credits. No gameplay system reads `PerkService.equipped`.
4. **No touch or gamepad gameplay input.** Steering and fire are keyboard and mouse only. Owner decided on 2026-10-12 that PC is the priority, console plays at PC parity, and phone and tablet are supported with degraded visuals allowed.
5. **Paid Continue can be lost.** If the 30 s death choice times out while the Robux prompt is open, the receipt never resolves. Continue is also free in live while its product id is 0.

### Design

- On Medium, zombies cannot catch a steady runner. The 0.6 speed multiplier caps runners at 12 studs/s against the player's 24. That is weaker than the ITD2 baseline the values came from. Threat is lateral interception only.
- Pay and spawns scale per stud, so speed skills raise income about 50 percent and are the dominant purchase.
- Co-op is three solo runs sharing one horde. Density has no squad term, and there is no revive or spectate.
- No onboarding. First input prompt never appears, and the first zombie arrives about 19 s after the run starts.
- Shotgun max damage 96 is below Walker health 100.
- Return hooks are per-run goals and credits only. There is no daily cadence and no leaderboard beyond distance.

### Code

- Client boot has no failure isolation. One throwing `init()` in `init.client.luau` kills every later controller. The server already wraps stages.
- Two viewmodel paths: `PackViewmodel` and legacy `ViewmodelBuilder`. Fab packs are gitignored, so the legacy path is the clean-clone fallback.
- God modules: `ZombieAI` 1292 lines, `WeaponVfx` 1278, `ChunkFactory` 1269, `AudioEngine` 1039.
- 3,540 comment lines exist against the "no comments in code" rule.

### Performance (static read, nothing measured yet)

- About 6 PointLights per 128-stud chunk from street lamps, plus barrels and police bars, under Future lighting with no mobile tier.
- Server zombie steering calls `Humanoid:Move` every frame per zombie, outside the 0.2 s AI tick.
- `ZombieAnimator` rebuilds up to 11 tracks per spawn. Impact effects and blood stains create instances per hit and per death.
- `ZombieAudio` calls `GetChildren` on all zombies every frame.
- The reviewer also flagged `Motor6D.Transform` writes in `ZombieHitboxes` as network load. Roblox does not replicate `Transform`, so treat that as server CPU only until measured.

## Recommended next steps

Ordered task briefs, written to be pasted into a separate Claude session, are in `production/claude-desktop-tasks.md`.
