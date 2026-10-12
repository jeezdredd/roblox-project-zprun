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
| `src/client/systems/CrashCinematic.luau` | Client only: the cabin ambience in the ready check, the 13 s crash timeline, the faked flight and spin |
| `src/client/systems/CabinCrew.luau` | Client only: soldier pilot and copilot clones in place of the server's block figures, posed by the cinematic |
| `AnimationController`, `AnimationsConfig.SIT_CLIP` | The seated pose while `SeatPart` is set, the gait layer fading out and picking up again on unseat. The only sit pose in the game (AnimationController removes the default Animate script, whose walk and run played under ours at full weight); it has a real uploaded id, so any Seat plays it |
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
- Zombies ignore a player until `GraceUntil` (server time); a missing or non-number
  `GraceUntil` never protects.
- Members stay seated: after a character reset, and whenever `Humanoid.SeatPart` goes nil
  (a jump), IntermissionService seats them again on a deferred call.
- During the crash beat nobody can leave or change their ready state; the only input
  accepted is the skip vote, and only on a repeat run. Ready and skip toggles are rate
  limited to one per 0.25 s per player.
- The cabin's LEAVE reuses the hangar's `SquadLeave` remote: IntermissionService acts on
  it only during the ready check, and SquadService ignores a player no longer in a
  hangar squad.
- `IntermissionMath` keys members by UserId and takes server seconds. The ready check
  returns Waiting, AllReady, TimedOut or Empty; a member who leaves takes their ready
  flag and skip vote with them. A skip passes only when every remaining member voted and
  someone is still there. An empty squad gets the full crash length, clamped to the
  config range.
- The wreck is `HangarConfig.RUN_START_CFRAME * WRECK_OFFSET` (offset in the run start's
  frame, -z the run direction), so it stays on the start platform. At the wake, a member
  the run did not take (dead, or a run already going) goes back to the hub.
- Moving a character to the wreck takes network ownership away first. On 2026-10-12
  relaunched runs had the server place the character at the wreck and, 0.3 s later, the
  client's own simulation (just handed the character back as it left the seat) return it
  to the cabin 8000 studs away, so the run had nobody on the road. MissionService now
  sets the root's owner to the server, pivots, holds 0.5 s, hands ownership back, then
  re-checks at 1, 2 and 3 s and teleports again if the character is more than 200 studs
  off. `SetNetworkOwner` is refused for an anchored assembly (a corpse pose), so it runs
  in pcall. `startSquad`'s `spawnCFrame` is the wreck after the intermission and the run
  start when omitted.
- CabinGui uses DisplayOrder 60, above the black fade at 50. During the crash beat the
  screen belongs to the cinematic: the panel shows only while a skip vote is open.

## Trade-offs (owner's calls made here)

- "Repeat" is read from the profile's lifetime run count, not from this server session:
  a returning player is not shown the full crash again after a rejoin.
- The cabin is a third `FlowPhase` value rather than an attribute beside "Hub": every
  reader that tests `== "Mission"` treats it as not a run, and FlowService's humanoid
  rules and character reset handling get a phase to key on.
- The skip vote cannot be taken back, and leaving is only allowed during the ready check:
  the crash beat is short and everyone sees the same thing.
- No gore in the crash: everyone sees it and the Gore toggle does not apply, so the shot
  is only a flash, a jolt and a slump, with no blood or wound.

## Implementation notes

### Cabin

- `IntermissionConfig` is data only with no engine types (positions `{x, y, z}`, colours
  `{r, g, b}`, the server builds the CFrames) so `IntermissionMath` and its tests read it
  under the standalone Luau CLI.
- The cabin is primitives through `SceneParts` in the PartSpec shape, no asset, placed at
  (4000, 600, 4000) away from every chunk, hub and diorama.
- Cabin frame: origin on the floor's centre, x across with the open door at +x, y up, -z
  toward the cockpit. The three troop seats line the left wall; `SEAT_YAW` -90 looks
  along +x at the door.
- Pilot and Copilot are each their own Model with parts laid out from a figure point on
  the seat, but the Model's pivot is not set to that point, so poses anchor on the torso.
- The hub's dusk lighting leaves the olive cabin near black, so `CABIN_FILL_LIGHTS` adds a
  dim warm dome light over the seats and the green of the cockpit instruments, with
  `Shadows = false` so the seats and crates do not black out the floor.

### Wiring

- The server publishes the player attributes `IntermissionStage`, `CabinSeat` (the seat
  index; the client finds `SeatView<n>` in `Workspace.IntermissionCabin`) and
  `GraceUntil`, plus a snapshot on the `IntermissionState` remote (nil closes it).
- The stage attribute and the snapshot travel separately, so when Crash starts the camera
  waits up to 0.5 s for the snapshot's `endsAt`, else assumes now + `CRASH_LENGTH`.

### Camera

- IntermissionCamera binds at `RenderPriority.Camera + 5`, after the camera controllers,
  and lets go the moment FlowPhase leaves Cabin (Scriptable back to Custom).
  CrashCinematic binds at Camera + 6, the last camera write each frame; the ready-check
  ground flight binds two below it.
- Look convention: yaw and pitch are degrees from the seat's view; mouse right turns
  right (negative yaw about +y), mouse down looks down. The ease is exponential and
  frame-rate independent, snapping within 0.01 degrees. The view stays put on releasing
  the right button and returns to the door whenever the beat changes.
- After the crash: black at once (0.05 s), held 0.4 s over the teleport to the wreck,
  then a 0.8 s fade out.

### Crash cinematic

- `setCabinAmbience` starts the rotor drone, the cockpit crew and the sliding town in the
  ready check; `play()` takes the same rotor sound over so it runs into the crash without
  a seam. `play()` returns false when `Workspace.IntermissionCabin` or this seat's
  `SeatView` is missing, and the caller keeps its plain black fade.
- Timeline (13 s): 0 to 1.5 s the view turns from the door to the cockpit; 1.4 to 2.2 s
  the pilot turns his head; 1.8 to 3.2 s the copilot turns and raises a pistol to the
  pilot's head; 3.6 s the shot (muzzle flash, gunshot, camera jolt, the pilot's head
  snaps aside and he slumps on the console); 4.0 s alarm, red strobe, spin and drop
  begin; 5.2 to 6.5 s the view swings back to the door; 9.5 s full spin; 11.6 s impact
  (white flash, hardest shake, debris); 11.85 s black with ear ringing until the wake.
- The server owns the length (13 s, 5 s on a repeat, early on a unanimous skip); each
  client keys to `endsAt` through `Workspace:GetServerTimeNow()`, so every seat sees the
  same moment. A shorter beat plays the end of the same timeline (offset = 13 minus the
  time left), so impact lands about 1.4 s before the end; the spin missed before a late
  start is integrated up front.
- The flight and spin are faked: the cabin never moves (the seated characters are welded
  to server-built parts). A local ground (`Outside`: a 3200-stud desert plane, a road and
  70 town blocks that wrap round far out in the haze) slides back along +z under the
  door in the ready check, then turns about the cabin and rises from 420 to 7 studs below
  it in the beat. Full spin is 0.85 turns per second, ramping in from 4.0 to 9.5 s, with
  a 13 degree bank; forward flight fades as the spin takes over.
- `stop()` restores the Pilot and Copilot parts, the light strip colour, the cabin light
  brightness, the console glow and the field of view, and removes the cinematic pistol.
  Looped sounds stop at once; one-shots (the ear ringing) live 12 s more to carry over
  the wake.
- Studio review from the client command bar:
  `workspace.CurrentCamera:SetAttribute("CinematicTimeScale", 0.2)` plays it slowly,
  `workspace.CurrentCamera:SetAttribute("CinematicAt", 3.6)` pins one moment.

### Cabin crew

- The server builds Pilot and Copilot as block figures in `Workspace.IntermissionCabin`.
  While the local player is in the cabin, CabinCrew hides them through
  `LocalTransparencyModifier` and seats two clones of `StarterPlayer.StarterCharacter`
  with the seated clip, tinted olive as flight suits when the clone is the soldier body.
  If the cabin or the template is missing, `CabinCrew.ensure` returns nil and the block
  figures stay (the cinematic then poses those).
- The crew is dropped when the cinematic ends or the character is removed outside the
  Cabin phase; a respawn still in the cabin keeps it.
- CrashCinematic drives `CabinCrew.pose` with 0..1 weights: look, raise and pilotLook
  from the timeline, slump and knock for the shot's aftermath, recoil for the pistol
  kick. Heads turn with IKControl LookAt.
- The copilot's arm is a Transform IKControl whose end effector is the pistol's muzzle
  attachment on the hand, so the barrel points at the pilot's head (muzzle 0.9 studs from
  it) whatever the grip offset; with the soldier crew the muzzle flash comes from that
  pistol. The pilot's knock and slump are written onto the Neck and Waist Motor6D
  Transform after the animator and the IK, every PostSimulation.
