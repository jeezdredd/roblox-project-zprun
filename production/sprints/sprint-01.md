## Sprint 1 -- 2026-10-13 to 2026-10-23 (9 working days)

Milestone: M1 Secure foundation (sprints 1 and 2). Plan: wiki/project-zprun/Roadmap.md. T briefs: production/claude-desktop-tasks.md (with the amendments in production/av-polish-tasks.md). A briefs: production/av-polish-tasks.md.

### Goals
- Close the exploit and stability holes: T1, T2, T4, T5, T22.
- Keep main green from now on: T6.
- Wire perks and cap distance pay: T3a, T3b, T11.
- Unblock M2: A1 asset guidance, A2 worktree setup, A3 generation probe and quota, A4 quality bar draft, T14 baseline.
- Wiki truth: T21.

### Tasks
Estimates are optimistic / expected / pessimistic agent-days. No velocity history exists, so they are uncalibrated.

| ID | Task | Owner | Estimate | Dependencies | Files touched | Lane | Group | Status |
|----|------|-------|----------|-------------|---------------|------|-------|--------|
| T1 | Gate free-weapons flag (CRITICAL PATH) | security-engineer | 0.5 / 0.5 / 1 | none | WeaponsConfig, WeaponService, WeaponController | A | G1 | done |
| T5 | Client boot isolation | lead-programmer | 0.5 / 0.5 / 1 | none | src/client/init.client.luau | B | G1 | done |
| T6 | Test runner and CI | devops-engineer | 0.5 / 1 / 2 | none | scripts/run_tests.sh (new), .github/workflows/ci.yml (new), rokit.toml | C | G1 | done |
| T22 | Dev key handling | security-engineer | 0.5 / 0.5 / 1 | none | scripts/upload_assets.py, scripts/refresh_status.py | D | G1 | done |
| A1 | Asset guidance and generator provenance | tools-programmer | 1 / 1.5 / 2.5 | none | scripts/sync_needed.py, scripts/sync_configs.py, assets/NEEDED.md, assets/LICENSES.md, a tests fixture, wiki Assets Pipeline.md | E (asset lane) | G1 | todo |
| A2 | Worktree Fab setup and ignore fix | tools-programmer | 0.5 / 0.5 / 1 | none | .gitignore, scripts/worktree_setup.sh (new), wiki Development Policy.md | F | G1 | todo |
| T21 | Wiki truth pass | producer | 0.5 / 1 / 1.5 | none | wiki Progress.md, Gameplay Systems.md, Route Forks.md, src/shared/config/PickupScenesConfig.luau (Roadmap.md only if the roadmap rewrite is not applied) | G | G1 | todo |
| A4a | Quality bar: weapon and camera rows | creative-director | 0.5 / 0.5 / 1 | none | docs/av/vertical-slice-bar.md (new) | H | G1 | todo |
| A3 | Generation probe and upload quota | technical-artist | 0.5 / 0.5 / 1 | Studio lane free; owner for the quota | docs/av/generation-capabilities.md (new) | S (Studio) | G1 | todo |
| A4b | Quality bar: audio rows | sound-designer | 0.5 / 0.5 / 1 | A4a | docs/av/vertical-slice-bar.md | H | G2 | todo |
| T2 | Server-validated distance (CRITICAL PATH) | network-programmer | 1.5 / 2 / 3 | T1 merged | DistanceTracker, RunPromptGuard, AmmoCrates, WeaponPickups, UpgradeStations, DeathService (baseline resets), GameConstants, tests/distance (new) | A | G2 | done (owner live check pending) |
| T14 | Baseline profile | performance-analyst | 0.5 / 1 / 1.5 | A3 done in the Studio lane; owner for MicroProfiler | wiki Performance.md only | S (Studio) | G2 | todo |
| A4c | Quality bar: world, effects, HUD rows and capture list | art-director | 0.5 / 0.5 / 1 | A4b | docs/av/vertical-slice-bar.md | H | G3 | todo |
| T3a | Perks: server multipliers (CRITICAL PATH) | gameplay-programmer | 1.5 / 2 / 3 | T2 merged; T5 if it registers a client module | PerkEffects (new), PerkService, SkillEffects, PerksConfig, WeaponService, AmmoCrates | A | G3 | done |
| T4 | Continue reliability | gameplay-programmer | 1 / 1.5 / 2 | T2 merged (DeathService) | MonetizationService, DeathService, ProductsConfig, ProfileManager, DeathController, docs/monetization-test-plan.md | A2 | G3 | todo |
| T11 | Cap distance pay per minute | economy-designer | 0.5 / 1 / 1.5 | T2 merged (DistanceTracker, server clock) | RunEconomy, RunEconomyConfig, DistanceTracker if needed, tests/economy, wiki Run Economy.md | A3 | G3 | done |
| T3b | Perks: Sprinter speed path and caps table (CRITICAL PATH) | gameplay-programmer | 0.5 / 0.5 / 1 | T3a and T11 merged | DistanceTracker, PerkEffects, wiki Run Economy.md | A | G4 | done |

Planned: 15.5 expected agent-days across 9 code lanes plus the Studio lane. Each lane plans at most 7 of its 9 days; the other 20 percent is held for Studio verification fixes and review rework.

### Parallel groups
- G1, day 1: T1, T5, T6, T22, A1, A2, T21, A4a, plus A3 in the Studio lane. No two of them share a file.
- G2, after T1 merges and A4a lands: T2, A4b, plus T14 in the Studio lane.
- G3, after T2 merges and A4b lands: T3a, T4 and T11 in parallel (no shared file), A4c.
- G4, after T3a and T11 merge: T3b.

### Must be sequential
- Lane A: T1 -> T2 -> T3a -> T3b. WeaponService (T1, T3a), DistanceTracker (T2, T11, T3b), AmmoCrates (T2, T3a), DeathService (T2, T4).
- Lane H: A4a -> A4b -> A4c, one document. Owner sign-off waits for D-AV2 (slice rifle pack) and the ADS call.
- Lane E (asset lane): A1 is the only task this sprint that touches the generated asset files.
- Lane S (Studio, one session): A3, then T14, then verification of T5, T1, A2, T2, T4, T11, T3a and T3b in merge order. Code lanes never drive Studio themselves.

### Critical path
T1 (0.5) -> T2 (2) -> T3a (2) -> T3b (0.5) = 5 days of 9, plus about 1 day of Studio verification. A T2 slip of more than 2 days pushes T3b into sprint 2.

### Owner steps this sprint
| Step | Needed by | When |
|------|-----------|------|
| Read the audio upload quota in the Creator Dashboard | A3 | day 1-2 |
| Decide the audit rerun (targeted camera, VFX and zombie-animation audits recommended) | M2 planning | day 3 |
| D-AV2: pick the slice rifle pack on look (RifleClips or Fab M4Clips) | A4 sign-off, then D-AV1 | day 5 |
| ADS: in or out | A4a weapon rows | day 5 |
| MicroProfiler capture with the Studio lane | T14 | day 3-5 |
| Non-Studio server check for T1 and T2 (published private test) | T1, T2 accept | after T2 merges |
| Review the quality bar | A4 sign-off | day 8 |
| Approve the wiki Roadmap.md rewrite drafted by the roadmap pass | T21 scope | day 1 |

### Risks
| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Lane A slips (T2 server validation is the least known task) | Med | High | T3a, T4 and T11 fan out after T2; decide at T2 merge whether T3b moves to sprint 2 |
| Studio lane congestion (A3, T14 and 8 verifications) | High | Med | Batch verifications on days 4 and 8; the owner keeps Studio MCP enabled |
| CI cannot build without Fab content | Med | Med | T6 accept includes a clean-clone build; Fab references must fall back |
| Owner time for decisions and reviews | High | Med | All owner steps listed above with dates; A4 review is one slot on day 8 |
| A3 finds generate_* missing or the audio quota low | Med | Med | A3 writes the fallback (Blender, licensed packs, packed audio variants) before M2 planning |
| No velocity history | Certain | Med | Record actuals per task; re-estimate M1 and M2 at the sprint 1 retro |

### Notes
- No viewmodel work is planned this sprint, so the A2 worktree setup is not on the critical path; viewmodel tasks in M2 wait for it.
- Agents never commit; the owner commits, authored by the owner only.
- Sprint 2 candidates (finish M1, start M2): T18 remote hardening, A5 capture harness, A4 rework after sign-off, any slip from lane A, then T9 and T16 as the first M2 work.
- Scope against the draft plan: sprint 1 gains T11, A3 and the T3 split, and loses no item; the critical path drops from 6.5 to 5 days because T3a, T4 and T11 run in parallel after T2.
