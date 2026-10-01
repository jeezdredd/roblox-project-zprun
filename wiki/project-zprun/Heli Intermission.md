# Heli Intermission

The helicopter between the launch countdown and the run: a cabin with a ready check, a
timed crash beat, the wake-up at the wreck with a grace window. Branch
`cloud/heli-intermission` (2026-10-01); flow, numbers and Studio checks in
`docs/gameplay/heli-intermission.md`. Item 4 of the Zombies layer in [[Roadmap]]; the
swaps reuse [[Run Economy]]'s perks and the Gunsmith's loadout. The crash cinematic's
camera, light and sound are the main session's ([[Development Policy]]).

## Files

| File | Role |
| --- | --- |
| `src/shared/config/IntermissionConfig.luau` | Ready timeout 90 s, crash 13 s (12..15) or 5 s on a repeat, grace 6 s, the wreck offset, the cabin origin, seats, eye, parts, crew |
| `src/shared/util/IntermissionMath.luau` | Pure: ready check, skip vote, crash length, grace. `luau tests/intermission/run.luau` |
| `src/server/systems/IntermissionService.luau` | The cabin, the seats, the two beats, the remotes, the hand-over to `MissionService.startSquad`, `GraceUntil` |
| `src/server/systems/LoadoutWindow.luau` | Swaps allowed in the hub and the cabin's ready check only |
| `src/client/ui/CabinGui.luau` | READY, LOADOUT, LEAVE, SKIP, the timer, "RUN" |
| `src/client/systems/IntermissionCamera.luau` | Seated view with a right-mouse look (yaw +-100, pitch -50..40, eased) in the ready check; fixed view and black fade in the crash beat; `playCrash` is the cinematic's seam |
| `AnimationController`, `AnimationsConfig.SIT_CLIP` | The seated pose while `SeatPart` is set, the gait layer paused; slot `animation/player/sit_idle` `needed` |
| `CursorMode.setCameraOwner` | The cabin view keeps the camera while the panel frees the cursor |
| `DevBench`, `DevConfig.QUICK_LAUNCH` | Play launches through the intermission (`intermission = true`) or straight in |
| `SquadService`, `MissionService`, `FlowService`, `ZombieAI`, `ShopService`, `PerkService`, `SceneParts` | The hooks: the launch, the wreck spawn, the `Cabin` phase, the grace, the `Cabin` catalog, the window, transparency |

## Rules

- One intermission at a time, as one run at a time; a launch is refused while one is
  busy, and a launch the intermission refuses leaves the hangar squad as it was.
- The run starts when everyone still in the cabin is ready, or at 90 s for whoever is there.
- Swaps only in the hub and the cabin's ready check, read from server-set attributes.
- A repeat run (every member has a run in the profile) gets the 5 s crash with a
  unanimous skip vote; otherwise 13 s, no skip.
- Zombies ignore a player until `GraceUntil` (server time).

## Trade-offs (owner's calls made here)

- "Repeat" is read from the profile's lifetime run count, not from this server session:
  a returning player is not shown the full crash again after a rejoin.
- The cabin is a third `FlowPhase` value rather than an attribute beside "Hub": every
  reader that tests `== "Mission"` treats it as not a run, and FlowService's humanoid
  rules and character reset handling get a phase to key on.
- The skip vote cannot be taken back, and leaving is only allowed during the ready check:
  the crash beat is short and everyone sees the same thing.
