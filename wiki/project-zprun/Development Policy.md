# Development Policy

How work on Task Force Z is done, revised on 2026-10-01 after a week in which a lot
landed fast and the owner's recordings kept showing problems the checks had missed.

Related: [[Decisions]], [[Progress]], [[Roadmap]].

## 1. Server owns the outcome, the client owns the feel

The server stays authoritative for everything that changes game state: damage, kills,
ammo counts, reloads, credits, purchases, perks, pickups. It validates every remote.

Everything the shooter sees and hears about their own action is drawn by the client at
once, with no round trip: muzzle flash, recoil, casings, tracers, impact puffs, impact
sounds, hit markers. The server's reply only reconciles numbers (ammo, kills) and draws
other players' shots. The old rule drew the shooter's tracers and impacts from the
server's `Shot`, a round trip late and from wherever the viewmodel had moved to; since
2026-10-01 `WeaponController.predictShot` draws them from a client ray with the same
spread rule. The damage path is unchanged.

## 2. Motion is checked as motion

A still frame cannot show a pop, a flicker or a one-frame glitch. Every change to
animation, the camera, the viewmodel or VFX is checked as a sequence:

- in Studio: the clip at a slowed `ViewmodelTimeScale` sampled every few frames, or the
  character driven by `Humanoid:Move` and sampled over a gait cycle, joint values read
  back where a pose is in doubt;
- from the owner's recordings: frames at the recording's own rate around every shot,
  reload, weapon switch, camera switch and death, never only one frame every few
  seconds.

A change is reported as done only after that check, and the report says what was
checked and what was not.

## 3. Who works on what

| Area | Owner |
| --- | --- |
| Camera, first-person viewmodel, third-person body, animation, weapon VFX, the soldier body, the helicopter intermission's camera | main session |
| Server systems, economy, perks, pickups, stations, UI, configs, docs for those | cloud agent |

Every task given to the cloud agent names the files it must not touch. The agent opens a
PR; the main session reviews it (correctness, server trust, placement, repo rules) and
sends the fixes; the agent fixes, merges into `main` itself and pushes. The owner pulls.

## 4. Repo rules (unchanged)

- Commits are authored by the owner; no trailers; no mention of the tools used.
- No em or en dashes in any file.
- Fab content (Fab Standard License): never committed; repo is public. Processed maps
  and generated lists live in the gitignored `assets/fab/` and `src/shared/fab/`; only
  manifest rows (ids, licence, a note) are committed (`docs/environment/megascans.md`).
- Asset ids only from the manifest pipeline (manifest, `upload_assets.py`,
  `refresh_status.py`, `sync_configs.py`); never invented. No synthesized audio.
- Before every commit: `selene src/`, `python3 tools/validate_api.py`,
  `rojo build`, the `luau tests/*` suites, `python3 tests/credits/run.py` (every CC BY
  asset credited in the game exactly once), both sync scripts' `--check`.
- The owner's commit command is one chain joined with `&&` and ends with
  `git pull --no-rebase --no-edit && git push`, so a failed check stops the commit and
  a merge never opens an editor.
