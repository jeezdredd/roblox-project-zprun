# Route Forks

Branching route choice during a run. Near the end of a biome the corridor splits into two entrances and the squad picks where to run next. Each branch changes the rules of the next stretch, so every choice trades a cost for a reward.

Status: **step 1 in playtest** (fork between existing biomes); since `cloud/map-segments` (2026-10-04) every fork sits at a map's end and offers two neighbouring maps, see [[Map Segments]]. Last updated 2026-10-04.

Related: [[Gameplay Systems]], [[Roadmap]], [[Decisions]], [[Architecture]].

## Status board

| # | Item | Status | Notes |
| --- | --- | --- | --- |
| 1 | Fork between two existing biomes | playtest | Built 2026-09-28 (da0ea7e). Vote verified in Studio both ways (left runner picked the left option, right runner the right). Sign and HUD screenshot-checked. See "Step 1 implementation" |
| 2 | Branch rule fields in `LocationConfig` | not started | See "Branch rules" below |
| 3 | Flashlight driven by "night OR branch requires it" | not started | Today `FlashlightController` reads only `NightMission` |
| 4 | Sewer branch | not started | Needs a narrow `laneStyle` and tunnel props |
| 5 | Metro branch with burning train hazard | not started | Needs track geometry and the train system |
| 6 | Grenades and explosives | not started | Do not exist in `src/` yet; the sewer ban is meaningless until they do |
| 7 | Explosives ban per branch | not started | Depends on 6 |
| 8 | Fork HUD (timer, branch icons, rules) | not started | |

Status values: `not started`, `in progress`, `playtest`, `done`, `blocked (reason)`.

## Step 1 implementation (2026-09-28)

Files: `src/shared/config/ForkConfig.luau`, `src/server/systems/RoutePlan.luau`, `src/server/systems/ChunkSpawner.luau`, `src/server/systems/ForkService.luau`, `src/client/ui/ForkHud.luau`; wired in `src/server/init.server.luau`, `src/server/systems/MissionService.luau` (`ForkService.configure(seed)`) and `src/client/init.client.luau`.

- **Planning** (superseded by [[Map Segments]]). Forks used to be placed mid-route by spacing rules (`FIRST_DIVIDER_AT`, `MIN_SPACING`). Now `RoutePlan` plans a whole map at a time and puts its fork at the map's end; `FIRST_DIVIDER_AT` (300) survives as part of every map's minimum length. Until resolved the fork is a placeholder entry and nothing past it is planned.
- **Options.** Two enabled neighbours of the current map (`MapsConfig.maps[id].neighbours`), never a map that is not a neighbour, never the same map.
- **Streaming hold.** `ChunkSpawner` stops at `RoutePlan.holdIndex()`, now the boundary itself: the map transition is the new map's first five chunks, and both options' versions of them are built while the squad runs the map (`MapPreload`), so the chosen one is placed the moment the vote closes.
- **Vote.** The vote line is `ForkConfig.VOTE_LEAD` before the boundary: since map segments the widest run fog plus a chunk plus 1.5 s at the top speed, 420 + 128 + 90 = 638 studs (was `SPAWN_AHEAD_DISTANCE + TRANSITION_CHUNKS * CHUNK_LENGTH` = 1024). The divider is `DIVIDER_LENGTH` (384) of jersey barriers on the centre line ending at the vote line, with a sign gantry at its start. When the lead runner crosses the line, each living participant counts for the side of the centre line they are on (left = `options[1]`, -X; right = `options[2]`, +X). Tie or nobody alive: random.
- **Client.** `ForkService` publishes `Workspace` attributes `ForkLeft`, `ForkRight`, `ForkVoteDistance`, then `ForkResult`. `ForkHud` shows CHOOSE YOUR ROUTE with both options, highlights the side the local runner is on, distance and seconds to the line, then the result for 3 s.

**Known limits of step 1**

- The new map starts 638 studs (about 11-27 s) after the vote (was 1024, 17-43 s). Going further means hiding the far end (a tunnel mouth, a bend) or the physical fork of [[Map Segments]] step 2.
- Chunk obstacles are not kept clear of the divider, so an obstacle can sit against the barriers or in front of the sign.
- The HUD countdown divides by current forward speed, so it jumps when the runner slows.

## Where it hooks into the code

The route is already a pre-planned queue of locations: `ChunkSpawner` builds `routePool` from `LocationsConfig.order`, streams chunks per entry, cross-fades into the next biome and sets `Workspace` attribute `Biome` at each boundary. A fork is a point in that queue where the next entry is decided by the squad instead of being taken from the pool. Chunk streaming, pooling and zombie spawning stay unchanged.

Note: there are no discrete lanes in the run. `GameConstants.LANE_WIDTH = 240` is one wide field with free lateral movement inside the playable band. Anything described below as "tracks" or "lanes" is geometry inside that band, not a lane system.

## Fork mechanic

- About 10 seconds before the end of the current biome the corridor splits into two entrances with a sign over each: branch name, icon, 2-3 rule lines.
- **Choice is physical, not a menu.** Each entrance has a trigger volume. When the timer ends, the entrance holding more living players wins. Tie or nobody inside: random. Players decide with their feet while running, so there is no UI pause.
- Server-authoritative: the server counts players in the volumes, picks the branch, inserts it at the head of the route queue and broadcasts the result. Clients only show the timer and the pick.
- Players who ran into the losing entrance are funnelled back into the winning one by geometry (the entrances merge a few chunks later), never teleported.
- Solo: the same, one vote.

Design rule: **every branch must have both a cost and a reward.** If one branch is strictly better, everyone picks it and the fork is dead content.

## Branches

| Branch | Cost | Reward |
| --- | --- | --- |
| **Sewer** | dark, flashlight forced on, narrow corridor, explosives banned | more ammo and loot, fewer zombies at once |
| **Forest** | trees cut visibility, dense obstacles force frequent strafing | no restrictions |
| **Metro** | burning train hazard on the tracks, narrow platforms | short and straight stretch, train kills zombies too |
| **Highway jam** (idea) | open but heavy hordes, car wrecks as obstacles | bonus credits per kill |
| **Burning block** (idea) | fire damage near the edges, smoke | rare weapon pickup |

### Metro: burning train

- The metro stretch has 2-3 track strips separated by platforms or pillars.
- **Telegraph, 2-3 s before impact:** headlight glow from the tunnel on one specific track, rising rumble, sparks on the rail, light camera shake. No hazard kills without a readable warning.
- Track is random, but never all tracks at once; there is always a safe strip.
- Hit: kill or heavy damage (tune in playtest).
- **Zombies die too.** This is the core of the branch: luring a crowd onto the rails and letting the train through turns the hazard into a tool and pays kills.
- After the pass the rail burns for a couple of seconds, so the strip stays dangerous briefly.
- Train frequency rises towards the end of the metro stretch.
- With the Night modifier the train headlights become the main light source and are visible from far away.

## Branches and modifiers

Run modifiers (`ModifiersConfig`: `FastZombies`, `Night`) stay in force for the whole run. A branch sets rules for its **stretch**; a modifier sets rules for the **run**. They stack.

| | Night | Fast Zombies |
| --- | --- | --- |
| **Sewer** | already dark, Night adds little | narrow corridor plus fast zombies is very hard |
| **Metro** | train headlights are the main light | less time to dodge zombies between trains |
| **Forest** | trees plus darkness, minimal visibility | strafing plus speed |

- Reward multipliers multiply: `modifier.rewardMultiplier * branch.rewardMultiplier`.
- Where a modifier changes nothing (Night in the sewer) its share of the bonus should be cut for that stretch, otherwise it is a free bonus. Open question.

## Branch rules (planned `LocationConfig` fields)

| Field | Type | Meaning |
| --- | --- | --- |
| `forceFlashlight` | boolean | flashlight on regardless of Night |
| `allowExplosives` | boolean | grenades and explosives usable |
| `hazard` | string? | e.g. `"train"`; drives a hazard system for the stretch |
| `lootMultiplier` | number | scales ammo crates and pickups |
| `rewardMultiplier` | number | stacks with the modifier multiplier |
| `corridorWidth` | number | narrower playable band for sewer and metro |

## Open questions

- Fork frequency: every biome boundary, or every second one?
- Is the fork shown in advance (sign visible from far) or does it appear late for pressure?
- How the losing-entrance funnel looks without feeling like a wall.
- Night-in-sewer multiplier cut: yes or no.
- Train hit: instant kill or heavy damage.
- Can the gap between vote and new biome (1024 studs today) be hidden or shortened? Needs a visual trick at the fork, see "Known limits of step 1".
- Should two-location maps fork at all ("stay" vs "switch"), or only Mixed?
