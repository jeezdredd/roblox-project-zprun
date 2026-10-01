# Helicopter intermission

Item 4 of the Zombies layer (`wiki/project-zprun/Roadmap.md`). Replaces the instant
hand-off where the launch countdown called `MissionService.startSquad` and the squad
appeared at `HangarConfig.RUN_START_CFRAME`. This change is the server flow and the
cabin. The crash cinematic itself (camera keyframes, light, sound) is the main
session's and comes after; here the crash beat is a timed wait under a black fade.

## 1. The flow

```
SquadService countdown (4 s)
  -> IntermissionService.begin(members, config, seed)
     Cabin  ready check: all ready, or 90 s, then for whoever is here
     Crash  12..15 s (13 by default); 5 s and skippable on a repeat run
  -> MissionService.startSquad(present, config, seed, wreck CFrame)
     Wake   GraceUntil = now + 6 s on each player; "RUN" on the client
```

| Piece | Role |
| --- | --- |
| `src/shared/config/IntermissionConfig.luau` | Data only: the ready timeout, the crash lengths, the grace seconds, the wreck offset, the cabin origin, the seats and the seated eye, the cabin parts and the two crew figures |
| `src/shared/util/IntermissionMath.luau` | Pure: the ready check state machine, the skip vote, the crash length rule, the grace window, seconds left. `luau tests/intermission/run.luau` |
| `src/server/systems/IntermissionService.luau` | Builds the cabin, seats the squad, runs the two beats on a heartbeat, validates the ready and skip remotes, hands over to `MissionService.startSquad`, sets `GraceUntil` |
| `src/server/systems/LoadoutWindow.luau` | When the loadout and the perks may change: the hub, and the cabin's ready check; never the crash beat, never a run |
| `SquadService` | `doLaunch` calls `IntermissionService.begin`; a launch is refused while an intermission is busy (one run at a time), and a countdown that ends while another squad holds it leaves the squad as it was |
| `MissionService.startSquad` | Takes an optional spawn CFrame (the wreck); `removeFromMission` clears `GraceUntil` |
| `FlowService`, `Flow` | A third phase, `"Cabin"`: walk speed 0, no jump; a character reset in the cabin stays in the cabin |
| `ZombieAI` | `findNearestPlayer` skips and `onTouched` ignores a player in their grace window |
| `src/client/ui/CabinGui.luau` | The panel: the squad and their marks, the timer, READY, LOADOUT, LEAVE; SKIP on a repeat crash; the "RUN" prompt |
| `src/client/systems/IntermissionCamera.luau` | Placeholder: the fixed seated view, the black fade for the crash beat |

## 2. The cabin

`Workspace.IntermissionCabin`, built once at server start at `CABIN_ORIGIN` (4000, 600,
4000), far from the hub (300, 0, 0) and from the run (x -4000, toward -z). Primitives
through `SceneParts` (which gained a `transparency` field for the windscreen and the
cargo net); no asset, no id.

- A troop cabin 9 x 7 x 16 studs: diamond-plate floor, olive walls and roof, an open
  door in the right wall (+x) with a sill and a grab rail, a cargo net and two crates
  aft, a red light strip with a `PointLight`, an extinguisher.
- Three `Seat` parts on the left wall facing the door (`SEAT_YAW` -90), one per squad
  member (`SQUAD_CAPACITY` 3), webbing behind each, and a `SeatView` part per seat at
  the seated eye (`EYE_OFFSET`, pitched down 8 degrees) for the camera.
- The cockpit through the bulkhead opening: floor, walls, roof, a console with a lit
  strip, a windscreen, two seats, and the two crew figures as their own Models,
  `Pilot` and `Copilot`, so the cinematic can move them.

## 3. Cabin beat

- `begin` takes the members still in the game and alive (up to the seats), gives each a
  seat (`CabinSeat` attribute), `IntermissionStage` "Cabin", `FlowPhase` "Cabin", and
  seats them (`PivotTo` above the seat, `Seat:Sit`). A member who jumps out is seated
  again the next frame; one who resets their character is seated again on spawn.
- The ready check (`IntermissionMath`): `IntermissionReady(boolean)` toggles the
  sender's mark (members only, during the ready check, a 0.25 s rate limit). The
  beat ends when every member still here is ready, or at `READY_TIMEOUT` (90 s) for
  whoever is here, ready or not. A member who leaves the game or presses LEAVE
  (`SquadLeave`, during the ready check only, back to the hub) is removed with their
  mark; an empty cabin ends the intermission.
- Swaps: LOADOUT opens the shop panel on the `"Cabin"` catalog (`ShopService.CABIN_VENDOR`):
  the loadout rows and the perk equip rows, nothing to buy. The catalog exists only
  for a player in the cabin's ready check, and every loadout toggle and perk equip, from
  any panel, goes through `LoadoutWindow.isOpen` (hub, or cabin during the ready check,
  never a run participant), read from the attributes the server sets. This replaces
  PerkService's "refuse while a participant" with "allow only in the hub and the
  cabin": the crash beat is now closed too.

## 4. Crash beat

- The length: `CRASH_LENGTH` (13 s, clamped to 12..15) the first time; when every member
  has at least one run in the profile (`StatsLifetime.Runs`), `CRASH_LENGTH_REPEAT`
  (5 s) and skippable. The server does nothing but wait; the beat ends at its time or
  when every member still here has voted `IntermissionSkip` (repeat only).
- `IntermissionStage` is "Crash": no swaps, no leaving, the panel shows the timer and
  SKIP with the votes.
- `IntermissionCamera.playCrash(endsAt)` is the seam for the cinematic: today a black
  fade over the seated view.

## 5. Wake

- `finish` releases everyone (seat, attributes), sends the panel away and calls
  `MissionService.startSquad(present, config, seed, wreckCFrame)`: the squad stands up
  at `RUN_START_CFRAME * CFrame.new(WRECK_OFFSET)` (4 studs forward, on the start
  platform), spaced as before. Each participant gets `GraceUntil` (server time, now +
  6 s); anyone the run did not take (dead, or a run already going) is sent home.
- Zombies neither pick a player in grace as a target nor hurt them on touch
  (`IntermissionMath.inGrace`, the same rule the client reads).
- The client holds the black for 0.4 s over the teleport, fades it out over 0.8 s, and
  shows a large red "RUN" with the grace seconds left until `GraceUntil` passes.

DevBench's `launch` still calls `MissionService.startSquad` directly and skips the
intermission (a test shortcut).

## 6. Tests

`luau tests/intermission/run.luau`: the ready check (all ready, unready again, a
stranger, a solo squad), the timeout (before, at, after, all ready wins), a member
leaving (the last unready one, a ready one taking their mark, everyone gone), the skip
vote (counts, strangers, the holdout leaving, an empty squad), the crash length (first
time, veterans, empty, the clamp), the grace window (inside, the edge, wrong types), and
the cabin layout (a seat per member, unique part names, the crew, off the map).

## 7. Studio check list

- **Launch.** A squad of one: the countdown ends and the player sits in the cabin, the
  view fixed from the seat at the open door with the red light; the panel reads READY
  CHECK, the member with "...", AUTO 90s counting down. No walking, jumping out puts
  them back in the seat; a character reset puts them back in the seat.
- **Ready.** READY marks the member; with one member the crash beat starts at once.
  With two, one ready waits; the second ready starts it. NOT READY takes the mark back.
- **Timeout.** Nobody presses READY: at 0 the crash beat starts for everyone.
- **Leave.** LEAVE in the ready check: back in the hub, walking, the panel gone; the rest
  carry on. Leaving the game in the cabin: the rest carry on; the last one leaving ends
  it and frees the helicopter for another squad's launch.
- **Swaps.** LOADOUT opens "LOADOUT AND PERKS" with the loadout rows and the equip rows
  of perks with a level, no prices; toggling works and the 1 and 2 keys follow. In the
  crash beat the panel closes and a toggle sent by hand is refused.
- **Crash beat.** The screen fades to black, BRACE FOR IMPACT with the seconds; 13 s on a
  profile with no runs, no SKIP. On a profile with runs: 5 s and SKIP; with two members,
  one vote shows 1/2 and waits, two votes end it at once.
- **Wake.** The black holds a moment, the run opens at the wreck point a few studs ahead
  of the old start, "RUN" in red with 6..1 s; zombies near the wreck do not turn toward
  the player or hurt them until it passes, then behave as before.
- **Another squad** pressing launch while a squad is in the cabin: nothing launches, its
  helicopter stays as it was.
- **Hub after a run:** perks and loadout change again at the Perk Lab and the Gunsmith.

Not verified without Studio: the cabin's look and the seated view (the eye offset, the
door framing), `Seat:Sit` on the soldier character, the black fade against
CursorMode's held camera, and the zombies' first frames after the grace ends.
