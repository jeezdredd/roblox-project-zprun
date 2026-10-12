# Code comments archive

Every comment removed from `src/` on 2026-10-12, when the no-comments rule was applied to existing code. Line numbers refer to the file before removal (commit d0fd34c). Move anything still useful into the matching wiki note.

## src/client/audio/AudioBus.luau

```
    3  -- The bus graph of the spatial audio engine, built once under SoundService.TFZ_Audio:
    4  --
    5  --   3D voices are heard by one AudioListener per bus (interaction group TFZ_<bus>) and
    6  --   2D voices wire straight into the bus fader. Each bus is a fader followed by its
    7  --   effects, everything sums into the master fader, then the limiter, then the device.
    8  --
    9  --   weapons  : listener -> fader -> reverb(env) -> echo(slapback) -> master
   10  --   sfx      : listener -> fader -> reverb(env) -> echo(slapback) -> equalizer -> master
   11  --   voices   : listener -> fader -> reverb(env) -> master
   12  --   ambience : listener -> fader -> duck group -> compressor -> master
   13  --   music    :             fader -> duck group -> compressor -> master
   14  --   ui       :             fader -> master
   15  --   duck send fader -> compressor.Sidechain   (voices of classes with duck = true)
   16  --
   17  -- Every wire here is many-to-one (several sources into one Input pin), which the
   18  -- effects guide documents; no source pin feeds two wires. The settings sliders drive
   19  -- the master and music faders through MusicController; the environment reverb and
   20  -- slapback glide towards the preset of the listener's environment.
   41  -- buses whose reverb and echo follow the environment
   45  -- the wet level that stands in for "off" (AudioEcho and AudioReverb have no gain floor of -inf)
  216  -- ambience and music sum here, then duck together under the sidechain
  255  -- The instance a 2D voice wires into.
  261  -- The interaction group a 3D voice's emitter joins to be heard on the bus.
  290  -- The chase duck from UiSfx: 0 no reduction, 1 full (floored at a tenth like the
  291  -- legacy path).
  297  -- The concussion equaliser on the sfx bus.
  320  -- Glides the reverb and slapback of every environment bus towards the target preset.
```

## src/client/audio/AudioDebug.luau

```
    3  -- Debug overlay for the spatial audio engine: profile, listener environment, ray use,
    4  -- pool occupancy, per-bus activity and one row per live voice with its class, bus,
    5  -- distance, start delay, occlusion, filter cutoff and volume. Toggled from the Studio
    6  -- test yard (SandboxInput binds a key to AudioDebug.toggle()).
   21  -- the test shot lands this far ahead of the camera
  141  -- A remote rifle shot 30 studs ahead of the camera with its reflection fan, so the
  142  -- reflections and the distance delay can be heard in the yard before WeaponSfx moves
  143  -- onto the engine (test plan item 3).
```

## src/client/audio/AudioEngine.luau

```
    3  -- The spatial audio engine: a fixed pool of voices (AudioPlayer -> AudioFilter ->
    4  -- AudioEmitter on the voice's own Attachment in Terrain, or a bus fader), one play API
    5  -- for every consumer, and the per-frame
    6  -- propagation update that gives each voice its distance curve, air absorption,
    7  -- occlusion, doorway loss, speed-of-sound delay and distance layers. Nothing is
    8  -- allocated per frame; a play picks a free voice or steals the least valuable one.
    9  -- Design and numbers: docs/audio/spatial-audio.md.
   29  -- an AssetIds.audio path ("zombie.idle_01") or a raw asset id; layers instead for
   30  -- close / mid / far perspectives (keys or ids per layer name)
   36  -- a fixed point, or an instance with a position to follow (BasePart, Attachment)
   41  -- seconds on top of the distance delay
   45  -- per-call overrides of the class
   50  -- an extra low-pass cap, for reflections coloured by their surface
   76  -- occlusion and doorway attenuation from the last propagation
   96  -- A 3D loop outlives its voices: out of range, or robbed by a louder sound, it keeps
   97  -- this record and takes a voice again once it is back in range and one is free or worth
   98  -- stealing. A horde's growls and a street of fires stay right however many there are;
   99  -- only the nearest hold real voices.
  102  -- a later start: no start delay, a short fade in
  113  -- the same table as the handle's refs: the voice the loop holds right now, if any
  131  -- one-shots that stopped playing are checked for release this often
  133  -- layer weights below this are not worth a voice
  135  -- a voice culled for range is stopped past this share of its range
  137  -- loops without a voice look for one this often, fading in over LOOP_FADE_IN
  140  -- a returning loop only steals a voice it clearly outranks, so two loops at the class
  141  -- limit do not trade one voice back and forth
  246  -- The emitter sits on the voice's attachment and the attachment is moved onto the
  247  -- source every frame: AudioEmitter.PositionType / PositionInstance are in the API but
  248  -- not enabled yet (Studio, 2026-09-29), and an emitter whose parent has no position
  249  -- (the AudioPlayer) is inaudible. Parenting it into a followed model would destroy it
  250  -- with the model.
  332  -- A class's layer bands in close -> far order, built once per class.
  362  -- A free voice, or the least valuable active one when the new sound outranks it, or
  363  -- nil when the new sound is the one to drop. Class limits are enforced first, so a
  364  -- horde of moans steals from itself before it steals a footstep.
  438  -- The propagation update of one 3D voice: distance, culling, absorption, occlusion,
  439  -- doorway loss, distance layers, then the filter and the volume.
  450  -- a one-shot is over; a loop's record takes a voice again when it comes back
  516  -- defined after startVoice
  560  -- the emitter's attachment tracks a moving source every frame; propagation
  561  -- (filters, occlusion, volume) runs on the slower cadence below
  635  -- first propagation before the sound starts, with its own rays and a long step so
  636  -- the smoothing lands at once: a voice born behind a wall is muffled from its
  637  -- first sample
  663  -- Gives a loop record a voice when its source is in range; `resume` starts it at a
  664  -- random point of the loop with a short fade, so returning growls never start in step.
  717  -- Every voice of a handle, when it is still the generation the handle was given.
  832  -- Rays a reflection fan casts on this platform.
  849  -- Plays a sound and returns a handle; a silent request (id 0, out of range, or no voice
  850  -- worth stealing) returns an empty handle whose methods do nothing.
  917  -- distance layers: one voice per band that has weight, each falling back to the
  918  -- nearest key the sound actually has
  968  -- Rows for the debug overlay (allocates; only called while the overlay is open).
```

## src/client/audio/AudioEnvironment.luau

```
    3  -- Where a sound is: the AcousticSpace zones, the biome and the flow phase resolve into
    4  -- an environment id (Hangar, Interior, Street, Forest, Open); the material table gives
    5  -- the loss and cutoff of whatever blocks a path; and the occlusion raycasts run inside
    6  -- a per-frame budget so a full zombie wave never spends more than a handful of rays.
   21  -- parts that sound passes through freely (tag them in the world builders)
   23  -- a ray stops this short of the source so the source's own part never occludes it
   79  -- The most recently added zone containing the point, pruning zones that left the
   80  -- world on the way.
  140  -- A raycast outside the per-frame budget (reflection fans pay their own cap).
  145  -- Blocked fraction (0 open .. 1 blocked) of the listener-to-source path plus the material
  146  -- of the first blocking part, or nil when this frame's ray budget is spent. `rays` is 1
  147  -- or 2; the second ray runs parallel, offset sideways, so an edge reads as half blocked.
```

## src/client/audio/AudioMath.luau

```
    3  -- Pure propagation math for the spatial audio engine: attenuation curves, air absorption,
    4  -- speed-of-sound delay, distance-layer crossfades, occlusion smoothing and reflection
    5  -- timing. Numbers in, numbers out; no Roblox services or datatypes, so
    6  -- `luau tests/audio/run.luau` exercises it outside Studio. Distances are studs
    7  -- (1 stud = 0.28 m), times are seconds, frequencies are hertz.
   13  -- 343 m/s at 20 C, in studs per second.
   19  -- ISO 9613-1 attenuation of the 8 kHz band at 20 C, 50 % RH, in dB per 100 m
   21  -- games exaggerate air absorption for readability; 1 is physical
   23  -- absorption grows with frequency roughly as f^slope between 1 and 8 kHz
   25  -- metres of free filtering before the low-pass starts (Hunt: none below 30 m)
   27  -- the cutoff is the frequency attenuated by this many dB
   50  -- Volume (0..1) of a class curve at `distance`. Every shape holds full volume inside
   51  -- `hold` and reaches zero at `range`:
   52  --   natural: the inverse law (hold / d) tapered by a linear-square fall so the end is
   53  --            silent rather than an abrupt cut (Roblox's InverseTapered idea);
   54  --   power:   the inverse law bent flatter, (hold / d) ^ 0.7, for loud sources that stay
   55  --            audible over most of their range, with the same taper;
   56  --   linear:  a straight fall from hold to range, for loops that should stay present.
   73  -- The curve as the distance -> volume table `AudioEmitter:SetDistanceAttenuation` takes:
   74  -- the emitter interpolates linearly between the points, so they are spaced where the
   75  -- inverse part bends most. The table is sorted-key friendly (numeric keys).
   85  -- denser near the hold radius, where 1/d changes fastest
   95  -- Low-pass cutoff standing in for air absorption at `distance`. The 8 kHz band loses
   96  -- `dbPer100mAt8k * exaggeration * strength` dB per 100 m past the knee; absorption at
   97  -- other frequencies scales as (f / 8 kHz) ^ slope, so the frequency that has lost
   98  -- `thresholdDb` is the cutoff. Strength 0 (or no distance past the knee) is the
   99  -- ceiling, so a 2D or near voice is untouched.
  111  -- Seconds a sound emitted `distance` studs away takes to arrive. Below `minDistance`
  112  -- no delay is applied (the owner's knob if near shots read as lag).
  120  -- Crossfade weight of band `index` among distance layers ordered close -> far. Each band
  121  -- is full inside its own range and ramps across the overlap with its neighbours, with an
  122  -- equal-power shape so the sum stays level in the crossfade; 0 outside the band. A
  123  -- playing layer asks for its own weight every update, so this builds no table.
  141  -- Every band's weight at `distance`, for picking the layers to start.
  150  -- The layer to play for `wanted` when a class lists layers but the sound only has some
  151  -- of the keys: the nearest one that exists in `order` (close, mid, far), searching
  152  -- outwards from the wanted index. Nil when nothing exists.
  170  -- Exponential approach with a time constant: after `timeConstant` seconds the gap has
  171  -- closed by 63 %, after three it is gone for listening purposes.
  179  -- Occlusion (0 open .. 1 blocked) smoothed with separate speeds: a path that clears
  180  -- opens quickly (attack) and a path that closes does so a little slower (release), so a
  181  -- door frame passing the line of sight never clicks.
  187  -- Gain multiplier for an occluded voice: the material loss scaled by the class's
  188  -- occlusion strength and by how much of the path is blocked.
  193  -- Cutoff of an occluded voice: from the ceiling towards the material cutoff as the path
  194  -- blocks, in the log domain so the sweep sounds even.
  205  -- Extra travel of a reflection over the direct path, as a delay.
  211  -- Gain of a reflection: the class's reflection gain, the surface's reflectivity, and a
  212  -- soft inverse fall over the full path so a slap off a far facade is quiet but present.
  217  -- Steal score for a voice: higher priority survives, and among equals the one furthest
  218  -- out of its range and longest playing goes first. Lower score is stolen first.
  224  -- Symmetric jitter: random01 in 0..1 maps to 1 - amount .. 1 + amount.
```

## src/client/audio/AudioReflections.luau

```
    3  -- Reflections for loud events (the MW2019 approach): a fan of rays from the source
    4  -- finds nearby surfaces, and each hit plays the sound again from that point, later by
    5  -- the extra path over the direct one, quieter by the path and the surface, and
    6  -- low-passed by the material. An open field has no hits and no reflections; a street
    7  -- gets slapback from its facades; an interior keeps at most two because the bus reverb
    8  -- already carries the rest.
   30  -- every third ray looks a little up, for balconies, canopies and ceilings
   38  -- `id` is the recording to reflect (usually the shot itself), `bus` the bus of the
   39  -- event's class, `volume` the event's volume before the class gain. `rays` overrides
   40  -- the profile count.
   85  -- the engine adds the hit-to-listener leg itself (Reflection has delay = true),
   86  -- so only the source-to-hit leg goes in here
```

## src/client/audio/WeaponAudioMath.luau

```
    3  -- Pure rules for the weapon sounds on the engine (WeaponSfx): which tail a shot takes
    4  -- in an environment, the reflection fan's rate limit, the distance layer keys of a
    5  -- remote shot, the impact family of a material. No services and no requires, so
    6  -- tests/audio/run.luau runs it under the standalone Luau CLI.
   12  -- share of the shot volume each tail plays at
   17  -- environments whose reverb carries the room, so the shot takes the interior tail
   20  -- The tail of a shot: the interior recording inside a room or the hangar, the class's
   21  -- own outdoor reflection elsewhere, the generic outdoor tail (quieter) when the class
   22  -- has none. Returns the id (0 for none) and the volume as a share of the shot volume.
   34  -- Rate limit for the reflection fan: `lastAt` is when the last fan fired, `now` the
   35  -- clock, `interval` the minimum gap. Returns whether this one may fire and the new
   36  -- `lastAt` to store.
   44  -- Distance layers of a remote shot: the close take always, mid and far only when they
   45  -- have an id. The engine's layer fallback plays the nearest layer that exists.
   85  -- Which impact recording set a hit on `materialName` plays; stone and everything
   86  -- unlisted is concrete.
   91  -- The keys an impact tries, in order: the family's own recordings, then the generic
   92  -- placeholder key for the family.
  101  -- How many of one volley's hits get a sound: the first few, so a shotgun's pellets
  102  -- read as one impact, not eight.
```

## src/client/body/AimReplicator.luau

```
    3  -- Puts the local player's aim on the wire for the other clients' third-person bodies:
    4  -- the camera's pitch and its yaw relative to the character's facing, whole degrees, and
    5  -- the manual lean (Stances) in tenths, at most twenty times a second and only when
    6  -- something moved, with a keepalive every second.
    7  -- Lossy by design: a dropped packet is replaced by the next one 50 ms later.
   30  -- The local aim as the other clients should see it: (pitch, yaw offset) in degrees, or
   31  -- nil without a live character.
```

## src/client/body/BodyController.luau

```
    3  -- Runs a BodyRig on every other player's character, and on the local one while the
    4  -- third-person view is on (Studio only). Feeds each rig from what already replicates:
    5  -- the WorldWeapon model and the WeaponId attribute for the gun and the draw, the
    6  -- Reloading / AmmoMag / AmmoReserve / ReloadScale attributes for reloads, the
    7  -- WeaponHit "Shot" remote for the kick, the BodyAim packets for the aim, and the root
    8  -- velocity for the sprint. Updates are scheduled by distance (ThirdPersonConfig.lod)
    9  -- in PreSimulation, after the animator, with a cap per frame.
  122  -- the sockets are children of the grip and arrive with the model
  139  -- The character is bound once its arms and torso exist; a character that never gets
  140  -- them (an R6 avatar) is left to the animator.
  199  -- The local character joins the set only while the third-person view is on, and its
  200  -- aim comes straight from the camera.
  263  -- For the yard label under a real player: seconds since their last aim packet, or nil
  264  -- for a player without a rig.
```

## src/client/body/BodyRig.luau

```
    3  -- One third-person body: the aim on the waist and neck, the weapon frame with its
    4  -- recoil, sprint, draw and reload gestures, and the two hand IK chains that follow it.
    5  -- The weapon leads and the hands follow: nothing here poses an arm joint directly.
    6  -- Written in PreSimulation on top of whatever the Animator left in the joints (see
    7  -- docs/animation/third-person-body.md section 3.1). The chest, the head and the gun are
    8  -- aimed from the root's upright frame, worked out down the joint chain for this frame's
    9  -- pose, so the run clip's forward lean does not tip the gun at the ground. Fed by
   10  -- BodyController for real players and by SandboxBodyGallery for the yard mannequins.
   23  -- how close a read-back Transform must be to the last write to count as untouched
   26  -- a joint the layer multiplies: what it wrote last and the animator pose under it, so a
   27  -- frame where the animator did not rewrite the joint (no track playing, or throttled)
   28  -- starts from the same base instead of stacking the twist
   35  -- an arm's three joints, read each update for the reach (an avatar rescale moves them)
   74  -- the manual lean (Stances), -1 left to 1 right: shown and wanted
  139  -- The shoulder joint in torso space and how far the hand's centre gets from it with the
  140  -- arm straight.
  147  -- The smallest slide along `back` (a unit vector) that brings `point` within `reach` of
  148  -- `origin`, at most `limit`: 0 when the point is already in reach, or when sliding back
  149  -- does not bring it closer.
  184  -- Binds an R15 character, or returns nil when it is not one or its arms are missing.
  261  -- Reads the weapon's class and sockets; nil clears the weapon (the hands go back to
  262  -- the animator).
  303  -- The manual lean, -1 (left) to 1 (right): the upper torso rolls toward it at the waist.
  326  -- A shot: the kick and snap springs, and the pump stroke on a gun that does not eject
  327  -- on fire.
  341  -- A reload on the weapon's own timeline: `shells` for the pump shotgun (how many go
  342  -- in), `empty` adds the chambering action, `scale` is the player's ReloadScale.
  358  -- The reload ended or was cancelled: the support hand returns to the gun.
  368  -- The draw after an equip.
  377  -- The support hand's frame in grip space for a gesture pose; the belt is in torso
  378  -- space, so it is returned with `inTorso` true.
  419  -- The animator's pose under the layer this frame (see the Joint type): a Transform that
  420  -- still reads back as the last write was not touched by the animator, so the base under
  421  -- that write is used again instead of stacking on it.
  424  -- Transform does not read back bit-exact (Studio, 2026-09-30), so an exact compare
  425  -- took every frame for an animator write and stacked the twist
  436  -- The rotation a joint's Transform has to add on top of `joint` (the joint frame under
  437  -- the animator's pose, in world space) so Part1 ends on the world rotation `wanted`.
  442  -- Part1's rotation relative to Part0 when the joint's Transform is identity.
  460  -- The draw's blend from the lowered pose (1 at the start of the draw, 0 once up) and
  461  -- its IK weight.
  473  -- One update, `deltaTime` seconds since the last one for this rig.
  494  -- the hands' IK weight first: the chest straightens only as far as they hold the gun
  503  -- this frame's pose in world space, from the root up the joint chain; `upright` is
  504  -- the root's rotation, what the torso and the head face with the clip's lean taken out
  520  -- the aim's waist share (plus the recoil's) over the upright chest, keeping only
  521  -- part of the clip's lean while a gun is held
  535  -- the head ends on the whole aim with a little of the clip's motion left in
  556  -- the weapon frame: the hold, lowered for the draw and the sprint, placed from the
  557  -- point between the shoulders along the aim over the upright chest, then kicked by the
  558  -- recoil; kept in torso space, where the two hand targets live
  585  -- Both hands inside the arms' reach, whatever the avatar's proportions: a grip past
  586  -- the right arm's reach brings the whole gun back along its axis, and a support socket
  587  -- past the left arm's slides back along the gun (no closer than a hand's width to the
  588  -- right hand), so the left hand lands on the receiver instead of stopping short of the
  589  -- handguard in the air.
  614  -- Whether the rig can still be used (the character is in the world).
  631  -- For the yard label: the live gesture and IK state.
  638  -- The animator reused its last pose this frame, so a multiplied twist would stack.
```

## src/client/controllers/AnimationController.luau

```
    3  -- The local character's locomotion clips. With a weapon held the gait comes from the
    4  -- weapon class's clip set (AnimationsConfig.locomotionSets, LocomotionMath): idle,
    5  -- walk, run, sprint and the strafes, blended by weight and played at the ground speed.
    6  -- A gait whose clip has not been uploaded falls back inside the set and then to the
    7  -- generic Run, so the character never stops animating. The tracks replicate through the
    8  -- Animator, so teammates see the same gait; the body layer (src/client/body) writes its
    9  -- aim and hand IK after the Animator on top of whatever plays here.
   31  -- the seated pose, kept apart from the gait tracks the update loop blends
   80  -- The engine gives every character its default Animate script, whose run and walk
   81  -- tracks played under ours at full weight (two gaits blended: the stumbling run seen on
   82  -- 2026-09-30). The locomotion here replaces it, so it goes, with its tracks.
  125  -- 0 until the clip is uploaded: then seating only pauses the gait layer
  137  -- The clip set of the weapon the local player holds.
  153  -- In a seat (the helicopter cabin): the sit pose plays and the gait layer is paused,
  154  -- its tracks faded out; on unseat the pose stops and the gaits pick up again.
  181  -- sideways share of the ground velocity in the character's frame
  198  -- the set's measured clip speeds, or the legacy Run's when the set has no clip
  214  -- the legacy strafes are additive leans and keep their own rate
  233  -- Plays the set's one-shot for `kind` ("reload", "hit") for the weapon held, when its
  234  -- clip exists.
  243  -- Whether the local character is seated (the sit pose, the gait layer paused).
  252  -- The gait playing right now, for overlays and the yard.
  257  -- The asset ids of a weapon class's locomotion set, keyed by gait and one-shot name
  258  -- (idle, walk, run, sprint, strafe_left, strafe_right, reload, hit); a slot whose clip
  259  -- is not uploaded yet carries 0. For the yard mannequins and any other rig that wants to
  260  -- run the same gaits as a player of that class.
```

## src/client/controllers/BreathingController.luau

```
    3  -- Breathing layers (calm, heavy, gasp) weighted by exertion. With the spatial audio
    4  -- engine on each layer is a 2D PlayerFoley loop that starts when its weight rises and
    5  -- stops when it falls away, so idle layers cost no voice; with it off the Sounds from
    6  -- before stay.
```

## src/client/controllers/CameraController.luau

```
   34  -- Even with "Show Own Body" on, the torso and arms sit inside the camera and fill
   35  -- the frame with giant untextured slabs, and the arms duplicate the viewmodel's.
   36  -- Only the legs read correctly when looking down, so everything above the waist
   37  -- is hidden regardless of the setting.
   60  -- the third-person weapon model is welded to the hand and would double the viewmodel
  114  -- Studio QA: a fixed shot for screenshots, set from the command bar as the workspace
  115  -- attribute DevCameraCFrame (nil gives the camera back)
  121  -- a fixed shot of the third-person body (V in the test yard) has to show it
  141  -- Reviewing animation on the third-person body: give the camera back to Roblox's
  142  -- orbit controller, keep the character visible and open up the zoom clamp that
  143  -- CursorMode uses to hold first person. Checked before FREEZE_RUN because both are
  144  -- inspection modes and this one wants the stock camera either way.
  145  -- (the test yard toggles the same view at run time with V, SandboxInput)
  155  -- maximum first: Roblox clamps a new minimum to the current maximum (0.5 while
  156  -- first person is held), which left the camera inside the head
  164  -- With the run frozen for inspection, the fixed runner camera would leave you staring
  165  -- down the corridor with no way to look at anything, since it has no mouse look at
  166  -- all. Hand the camera back to Roblox's own first-person controller and keep only the
  167  -- body hiding. The viewmodel tracks whatever drives camera.CFrame, so it follows.
  172  -- Not while a menu is open: this runs every frame, so forcing the lock here
  173  -- overrode CursorMode releasing the cursor and left menus unclickable.
```

## src/client/controllers/FootPlanting.luau

```
   13  -- Planting is for standing on uneven ground. Above this ground speed it fades out: the
   14  -- running clips place the feet themselves, and chasing the moving feet with IK threw
   15  -- the hips about (2026-09-30: the soldier ran with the pelvis rolled 60 degrees).
   56  -- the chain starts at the thigh: hip, knee and ankle bend, the pelvis stays with the clip
  108  -- the foot part's centre sits half its height above the sole (0.55 on the block
  109  -- body, 0.28 on the soldier)
```

## src/client/controllers/FootstepController.luau

```
    3  -- Footsteps for the local character (on ExertionState's stride) and for teammates (a
    4  -- stride phase advanced from their velocity), chosen by the material under foot. With
    5  -- the spatial audio engine on each step is a PlayerFootstep or TeammateFootstep voice
    6  -- following the root part, cut at MAX_SLICE with a short fade; with it off the pooled
    7  -- Sounds from before stay.
   95  -- A step through the engine: a short voice on the root part, cut at MAX_SLICE.
```

## src/client/controllers/RunController.luau

```
   44  -- Past the band by more than this the character is not on the run at all: still in the
   45  -- cabin or the hub while the server's teleport to the wreck is on its way. Clamped there,
   46  -- it was thrown to the band's edge at the cabin's height and z, overwrote the teleport
   47  -- (the client owns its character) and fell out of the map (2026-10-12, relaunches).
   64  -- Frozen: leave the default controls enabled instead of taking them over, so you can
   65  -- actually walk around and look at things rather than being rooted in place. `force`
   66  -- is how the unfreeze debug command overrides the switch without editing config.
```

## src/client/systems/AnimationSequencer.luau

```
    8  -- Plays authored pose sequences and hands the resulting bone offsets back to the
    9  -- viewmodel. It never touches the procedural layer: sway, bob and recoil are applied
   10  -- by Viewmodel on top of whatever this returns.
   99  -- Any sequence can be cut off mid-frame; the current pose becomes the blend origin
  100  -- so the switch never snaps.
  101  -- `targetDuration` stretches or squeezes the whole sequence to that many seconds (the
  102  -- reload plays over the weapon's reloadTime); omitted, the authored timings stand.
  103  -- `blendTime` overrides the sequence's own blend-in: Fire has none so the kick lands on
  104  -- the frame, but a shot that cuts a reload tail needs one or the arms jump.
  175  -- Restart from the top. Pointing the index back at the last step
  176  -- left its clock already spent, so alpha hit 1 again on the very
  177  -- next frame, this branch re-fired every frame and the pose froze
  178  -- on the final step instead of cycling.
```

## src/client/systems/CabinCrew.luau

```
    3  -- The helicopter's two crew as soldiers (docs/gameplay/heli-intermission.md), client
    4  -- only. The server builds the Pilot and Copilot as block figures in
    5  -- Workspace.IntermissionCabin; while this player is in the cabin they are hidden locally
    6  -- and two soldier bodies (clones of StarterPlayer.StarterCharacter, the same Mixamo
    7  -- soldier every player wears) sit in the cockpit seats with the seated clip. The crash
    8  -- beat (CrashCinematic) drives them through pose():
    9  --
   10  --   the pilot turns his head to the copilot (an IKControl LookAt)
   11  --   the copilot turns his head to the pilot and brings a pistol up to the pilot's head
   12  --   (an IKControl Transform whose end effector is the pistol's muzzle, so the barrel
   13  --   points at the head whatever the hand's grip offset)
   14  --   the shot: the pilot's head snaps aside and he slumps onto the console (the neck
   15  --   and waist joints rotated after the animator, every PostSimulation)
   16  --
   17  -- No blood or wound: everyone sees the beat and the Gore toggle does not apply.
   33  -- each soldier's root over its cockpit seat, in the cabin's frame (floor top, -z forward)
   36  -- flight suits: a dull olive over the soldier's uniform texture
   39  -- how close to the pilot's head the copilot holds the muzzle
   60  -- the pilot's slump after the shot (0..1) and the head's knock aside (0..1)
  129  -- a posed prop on an anchored root: no falling or getting-up states
  169  -- The neck and waist after the animator and the IK, every frame: the shot's knock and
  170  -- the slump onto the console.
  183  -- Builds the crew in the cabin (once); nil when the cabin or the soldier is missing,
  184  -- and the block figures stay.
  208  -- the copilot's sidearm, holstered (hidden) until the beat brings it up; its muzzle
  209  -- is carried as an attachment on the hand so the arm's IK can aim the barrel itself
  266  -- The beat's crew poses. `look`, `raise` and `pilotLook` are 0..1 weights from the
  267  -- cinematic's timeline, `slump` and `knock` the shot's aftermath, `recoil` the pistol's
  268  -- kick (0..1).
  278  -- the muzzle a hand's width from the pilot's temple, the barrel on his head
  300  -- The muzzle the flash and the shot come from, or nil.
  305  -- Removes the soldiers and shows the block figures again.
  329  -- the local player only ever sees one cabin; a respawn or a leave drops the crew
```

## src/client/systems/CameraNearFade.luau

```
    3  -- Hides whatever the camera is inside. The death camera lies at the corpse's eye with
    4  -- the zombies feeding on it, the third-person orbit swings through the soldier's own
    5  -- arms and helmet, and a revived body stands where the camera comes back: on the
    6  -- owner's recording (2026-09-30) the screen filled with the inside of a sleeve, a
    7  -- zombie's arm and the helmet shell. Every frame after the camera has moved, the parts
    8  -- whose box reaches within the margin of the camera get LocalTransparencyModifier 1 and
    9  -- get their value back once the camera leaves them. The viewmodel lives under the
   10  -- camera and is never touched.
   11  --
   12  -- Candidates are the local character, the zombies near the camera (their skinned
   13  -- visual parts are CanQuery false, so a spatial query cannot see them) and whatever a
   14  -- bounds query finds.
   23  -- after the camera and its effects (Camera, Camera + 1) and the death camera (Camera + 1)
   25  -- studs from the camera to a part's box; the near plane is 0.1, so anything this close
   26  -- fills the view
   28  -- a skinned zombie's part box is its bind pose, and the clips move the mesh outside it
   30  -- zombies whose pivot is farther than this are skipped
   33  -- parts faded now, with the modifier they had before
  102  -- someone else may have set it meanwhile (the first-person hide): leave theirs
```

## src/client/systems/CityAmbience.luau

```
    3  -- The burning city outside the hangar: siren patrols orbiting on invisible parts in
    4  -- bursts, and the rotor loop of every patrol chopper. With the spatial audio engine on
    5  -- each one is an AmbienceSource voice following its part (long linear curve, air
    6  -- absorption, occluded by the hangar); with it off the Sounds from before stay.
```

## src/client/systems/CrashCinematic.luau

```
    3  -- The helicopter crash beat (docs/gameplay/heli-intermission.md, roadmap: "the pilot
    4  -- turns, the copilot shoots him"), client only, played over the cabin the server built
    5  -- (Workspace.IntermissionCabin: the SeatView parts, the Pilot and Copilot figures, the
    6  -- LightStrip, the ConsoleGlow). No gore: everyone sees it and the Gore toggle does not
    7  -- apply, so the shot is a flash, a jolt and a slump.
    8  --
    9  -- One 13 s timeline (seconds):
   10  --   0.0-1.5   the seated view turns from the door to the cockpit
   11  --   1.4-2.2   the pilot turns his head to the copilot
   12  --   1.8-3.2   the copilot turns, raises a pistol to the pilot's head
   13  --   3.6       the shot: muzzle flash, gunshot, camera jolt; the pilot's head snaps aside
   14  --             and he slumps onto the console
   15  --   4.0       the alarm and the red strobe; the helicopter starts to spin and drop
   16  --   5.2-6.5   the view swings back to the door: the ground turns and rises outside
   17  --   11.6      impact: white flash, the hardest shake, impact and debris
   18  --   11.85     black; ringing in the ears until the wake-up at the wreck
   19  -- A shorter beat (the repeat run's skippable version) plays the end of the same
   20  -- timeline, so the impact always lands on the beat's last second.
   21  --
   22  -- The flight and the spin are faked: the cabin stays where the server built it and a
   23  -- local ground (`Outside`: desert, a road, blocks of a town) slides under it during the
   24  -- ready check, then turns and rises under it in the beat, which is the same picture
   25  -- through the door without moving server parts the seated characters are welded to.
   26  -- Everything the beat changes in the cabin is put back by stop().
   41  -- server time the beat ends (the wake-up)
   43  -- this player's seat (CabinSeat)
   45  -- turns the screen black over `seconds` (the intermission camera's fade)
   50  -- after the intermission camera (Camera + 5), so this is the last write
   72  -- the turn of the helicopter at full spin (radians per second) and the bank it pulls
   75  -- the ground under the cabin when the spin starts, and at the impact
  119  -- the cabin floor's centre, x across to the door, -z to the cockpit
  125  -- the rotor drone of the ready check, handed to the beat when it starts
  129  -- the ground outside, shared by the ready check's flight and the beat
  135  -- the cabin floor's frame the ground hangs under
  137  -- studs flown so far (the town slides back along +z)
  154  -- eased 0..1 between two timeline marks
  205  -- The ground the helicopter falls toward: a desert plane and blocks of a town, built
  206  -- locally around the cabin's floor and moved every frame.
  249  -- Puts the ground under the cabin: `flown` slides the town back (each block wraps
  250  -- round far out in the haze), `spin` turns it about the cabin, `altitude` below it.
  306  -- spin rate ramps in from T_SPIN to T_SPIN_FULL
  321  -- the soldier crew (CabinCrew) when it could be built; the block figures otherwise
  336  -- the pilot: head turns to the copilot, then the shot knocks it aside and he slumps
  360  -- the copilot: head to the pilot, right arm up with the pistol at the pilot's head
  448  -- forward flight fades out as the spin takes over
  470  -- the bank of the turn, and the shake: rotor buzz always, the spin's buffeting, the
  471  -- shot's jolt and the impact
  499  -- debug knob for reviewing the beat slowly from the command bar (client):
  500  -- workspace.CurrentCamera:SetAttribute("CinematicTimeScale", 0.2)
  503  -- or pinned to one moment: workspace.CurrentCamera:SetAttribute("CinematicAt", 3.6)
  523  -- Starts the beat; returns false when the cabin or the seat view is missing (the
  524  -- caller keeps its plain black fade then).
  598  -- a figure's pivot is its seat origin only if the server built it that way; use the
  599  -- torso's position as the anchor so the poses stay on the figure either way
  633  -- with the soldier crew the flash comes from the copilot's own pistol
  655  -- the spin already run before a late start (the short beat)
  669  -- The rotor drone while the squad sits in the cabin (the ready check); the beat takes
  670  -- it over, so the sound runs on without a seam into the crash.
  683  -- the two soldiers in the cockpit
  685  -- the town sliding by under the open door
  712  -- Ends the beat and puts the cabin back as the server built it.
  738  -- the ringing carries over the wake-up; everything else stops now
```

## src/client/systems/CursorMode.luau

```
   18  -- systems that drive the camera themselves while a menu is open (the helicopter
   19  -- cabin's view, IntermissionCamera): the held camera is theirs, only the cursor is ours
   92  -- A system that drives the camera itself (`owned` true) while a menu frees the
   93  -- cursor: the menu no longer holds the camera still or hands it back to Custom.
  109  -- A menu only frees the cursor if it remembers to announce itself, and anything built
  110  -- outside this codebase never will - which leaves the player staring at a menu they
  111  -- cannot click. So rather than trusting every panel to call setModalOpen, watch for one
  112  -- that looks modal: an enabled ScreenGui holding a solid frame over a good part of the
  113  -- screen. Panels that do announce themselves are unaffected; the id is separate.
  117  -- GuiObject.Visible reports only its own flag, and a hidden parent still leaves children
  118  -- flagged visible with a real AbsoluteSize. Checking the chain is what separates an open
  119  -- menu from a closed one whose panels were never individually hidden.
```

## src/client/systems/DroppedMagazines.luau

```
    3  -- Spent magazines dropped by a speed reload (PackViewmodel, ViewmodelPackConfig.magDrop).
    4  -- The viewmodel magazine is copied at world size where the eye sees it (the rig is a
    5  -- scaled-down copy around the eye, so scaling the position from the eye keeps the
    6  -- image), then falls with the runner's velocity, bounces once or twice on whatever is
    7  -- below and lies flat until it expires. Anchored and moved by hand like the casings: no
    8  -- physics owner, nothing for the character to trip over.
   16  -- `bones`: world CFrames of the joints a mesh skinned to several bones is drawn with
   17  -- (ViewmodelPackConfig.MagDrop `skin`); `body`: the magazine's box in mesh space when
   18  -- the mesh bounds are larger than the magazine
   39  -- about real gravity at 28 cm per stud; the drop has to be seen, not snapped to the floor
  101  -- lies the magazine flat on `normal`, keeping its heading
  162  -- `pieces` are the viewmodel meshes with the CFrame they are drawn at now, `eye` the
  163  -- camera position the rig is scaled around, `scale` the rig-to-world factor,
  164  -- `velocity` what the magazine leaves the hands with (the runner's own speed).
  172  -- one model per magazine: a skinned copy finds its bones by name within its model,
  173  -- so the bones of two dropped magazines must not share one
  211  -- the magazine turns about its own centre and lies on its own faces
  222  -- the thinnest local axis of the body is the one it lies on
```

## src/client/systems/EnvironmentQuality.luau

```
    3  -- The client side of the per-chunk budgets. The server builds one world to the desktop
    4  -- budget and tags what the mobile tier can lose (DressingConfig.TAGS): on a touch-only
    5  -- device the tagged clutter and decal cards are removed locally and the near-band
    6  -- shadow casters stop casting, on streamed-in chunks too. In Studio it also prints the
    7  -- real scene triangle and draw-call counts when the biome changes, so the server's
    8  -- per-chunk estimate can be compared with a measurement.
   22  -- the scene needs a moment to stream the new biome in before its count means anything
```

## src/client/systems/IntermissionCamera.luau

```
    3  -- The camera during the helicopter intermission (docs/gameplay/heli-intermission.md),
    4  -- for now only the placeholders the server flow needs:
    5  --
    6  --   Cabin  the seated view from this player's seat (the SeatView part the server
    7  --          builds per seat in Workspace.IntermissionCabin), looking at the open door;
    8  --          holding the right mouse button looks around (yaw +-100, pitch -50..40 from
    9  --          the seat's view, eased), the cursor staying free for the panel.
   10  --   Crash  the crash cinematic (CrashCinematic) over the same seat for the beat's
   11  --          length, ending in black; a plain black fade when the cabin is missing.
   12  --          The rotor drone of the ready check runs on into it.
   13  --   After  the black holds a moment over the teleport to the wreck, then fades out and
   14  --          the camera goes back to the run's controller.
   15  --
   16  -- Bound after the camera controllers (RenderPriority.Camera + 5) so it is the last
   17  -- write while it holds; it lets go the moment FlowPhase leaves "Cabin".
   46  -- the crash beat's end (server time) from the cabin snapshot; the stage attribute and
   47  -- the snapshot travel separately, so the beat waits a moment for it
   50  -- the look around the cabin, degrees from the seat's view: where the mouse put it and
   51  -- where the camera is on its way there
  114  -- the crash beat: exactly the seat's view (the cinematic will own it)
  130  -- the cabin panel frees the cursor; the camera stays ours meanwhile
  150  -- The crash beat: the cinematic over this player's seat, ending on the black this
  151  -- module holds over the teleport; a plain black fade when it cannot play.
  190  -- the view goes back to the door the moment the beat changes
  208  -- hold the black over the teleport to the wreck (black at once when a skip vote
  209  -- cut the beat short), then open on the run
  236  -- right mouse held: the mouse looks around; released, the view stays where it is
```

## src/client/systems/LightingDirector.luau

```
   19  -- the map at the lead runner and the boundary zone being crossed (ChunkSpawner): over
   20  -- the zone the preset is the two maps' presets blended by where this player is, so the
   21  -- light changes across the transition chunks instead of at the boundary
   24  -- Studio QA: a preset id forced from the command bar or the biome strip (nil releases it)
  124  -- Over a map boundary zone: the two maps' presets blended by this player's place in
  125  -- the zone; nil outside one (or with a preset forced in Studio).
  208  -- leaving a zone hands the target back to the map's own preset
  219  -- The preset on screen right now (mid-lerp values included), for PostFx.
```

## src/client/systems/MapAmbience.luau

```
    3  -- Each map's ambience bed during a run (wiki: Map Segments), crossfaded over a map
    4  -- boundary: inside the transition zone (MapBlend* Workspace attributes from
    5  -- ChunkSpawner) the old map's bed and the new one's play at equal-power gains for this
    6  -- player's place in the zone; elsewhere the map at the lead runner plays alone. A bed
    7  -- whose id is 0 (AssetIds.audio.ambience, still needed) is silence, so this runs before
    8  -- any bed is uploaded. Through the audio engine's AmbienceBed class when it is on, a
    9  -- plain looped Sound in the Sfx group otherwise.
   32  -- the bed's level at full gain, and how fast a gain follows its target (per second)
   99  -- The wanted gain per map for this frame.
```

## src/client/systems/MapPreloader.luau

```
    3  -- Client half of the map preload (wiki: Map Segments): while the squad runs a map the
    4  -- server names both fork options in the MapPreload Workspace attribute (MapPreload);
    5  -- this asks ContentProvider for their meshes, textures, prop surfaces and material
    6  -- variants, so whichever option the vote picks draws at full resolution the moment it
    7  -- streams in. The boot screen preloads everything once (Boot.client); this keeps the
    8  -- next map's assets warm after a long run has pushed them out. Each asset is asked for
    9  -- once per session.
   45  -- Everything one map draws with that is worth asking for ahead.
```

## src/client/systems/MusicController.luau

```
    3  -- Music, the hub siren bed and the volume controls. Owns the legacy SoundGroup tree,
    4  -- which WeaponSfx and the legacy paths still play through, and mirrors every volume,
    5  -- mute and duck change onto the spatial audio engine's buses so the two mixes move
    6  -- together. With the engine on, the tracks themselves are 2D voices on the music bus
    7  -- (cross-faded by the engine's fades) and the siren is an ambience bed.
   91  -- the menu track stands in, a little faster
```

## src/client/systems/PackViewmodel.luau

```
    3  -- First-person rig built from a weapon pack (ReplicatedStorage.ViewModelPacks, loaded by
    4  -- the server's ViewmodelPacks) and driven by its baked clips through ViewmodelClipPlayer.
    5  -- Viewmodel.luau owns the procedural layer (sway, recoil, bob) and hands this module the
    6  -- camera-space placement each frame; this module owns the clips: equip, the idle or walk
    7  -- loop underneath, fire, reload sequences and their sound phases.
    8  --
    9  -- One-shots run as a queue of entries (a clip section with its own speed, fade and
   10  -- phase tag). When the queue runs dry the idle/walk loop is blended back in over the
   11  -- last entry's `blendOut`, which is how a cut reload returns to the ready pose.
   24  -- One clip section in the one-shot queue. `duration` fits the from..to section to that
   25  -- many seconds and wins over `speed`. `tag` travels with every phase the entry emits
   26  -- ("fire", "tactical", "empty", "shell", "chamber", "equip", "inspect") so listeners can
   27  -- tell a pump after a shot (ejects a hull) from the chambering pump after a reload.
   38  -- ViewmodelClipPlayer weight: share of the clip's move that is applied
   44  -- the magazine (or tube) was empty: empty clip cut, chambering pump for shells
   46  -- shell reloads: how many shells go in
   48  -- SkillEffects.reloadScale as replicated by the server (1 = config timings)
   53  -- seconds to blend back to the ready pose (or into the chambering pump)
   55  -- seconds of chambering pump after the exit, when nothing is chambered
   57  -- a shell is in the hand and still goes in before the exit
   68  -- each part's CFrame relative to the root; the parts follow the root every frame
   76  -- the class's `hold` offset, applied between the camera and the eye point, the one
   77  -- used while a reload, draw or inspect plays, and the blend between them (1 = action)
   81  -- the wall pull-back on top of the hold (WallPullback): identity in the open
   83  -- the stance, magazine check and lean counter-pose on top of that (Stances):
   84  -- identity at mid with no lean
   86  -- looping clip underneath (idle or walk), nil while a one-shot plays
   89  -- the one-shot playing now, nil while the base loop plays
   91  -- clip time phases were last checked at
   93  -- fade for the next return to the base loop
   95  -- the magazine is empty (WeaponController's prediction): the bolt or slide holds back
   98  -- the held bones and their Transforms while locked back (ViewmodelPackConfig.lockBack)
  100  -- the speed reload has dropped its magazine (reset when the empty reload ends)
  102  -- magazine meshes hidden by the speed reload, with the transparency they had
  104  -- part -> index into parts/offsets
  109  -- a shot out of a reload, equip or inspect pose: MW blends the cut over 0.1-0.15 s,
  110  -- a hard cut would pop the arms across the screen
  112  -- a shot out of idle or another shot: the kick has to land on the frame
  115  -- fire + follow (pump) must close within this share of the fire interval
  118  -- how far past the ShellIn marker a cancelled shell is allowed to run
  121  -- time constant of the blend between `hold` and `actionHold`
  147  -- the committed packs live in Shared.viewmodel_clips; Fab packs in Shared.fab, which
  148  -- exists only on the owner's machine (the Fab licence keeps them out of the repo)
  180  -- Front and top of the weapon mesh at rest, expressed in the weapon bone's frame so it
  181  -- follows the bone through every clip. The packs' weapons point down -Z in rig space.
  202  -- a turned rest pose: measure the mesh box along the upright rig axes and put the
  203  -- anchors back into rest space with the upright orientation turned by `tilt`
  234  -- Replaces whatever plays with `entries` back to back. Entries whose clip is missing
  235  -- from the pack are skipped.
  251  -- Back to the idle/walk loop over `fade` seconds from wherever the arms are now.
  275  -- The parts are anchored, so moving the root leaves them where the template had them.
  276  -- The skinned meshes still draw on the bones, but the engine picks each mesh's level
  277  -- of detail (and its bounds) from the part: left near the world origin, thousands of
  278  -- studs from the camera, the arms rendered from the lowest detail level and parts of
  279  -- the left arm flickered into the view for single frames (the owner's recording,
  280  -- 2026-10-01). The parts are carried with the root every frame instead.
  322  -- the rig starts on the draw
  358  -- the draw always plays at natural speed; WeaponsConfig.drawTime decides when a shot
  359  -- may cut its tail
  364  -- The magazine ran dry (or was filled): with a `lockBack` the bolt or slide holds back
  365  -- from the last shot until the empty reload's release.
  370  -- Rig parts whose name matches `pattern`; with a `bone`, only the one nearest it at rest
  371  -- (two magazines can carry rounds of the same name).
  405  -- The bolt or slide held back on an empty magazine, except while the empty reload runs
  406  -- (its own clip starts locked back and releases it). Written after the clips each frame,
  407  -- relative to the gun, so it rides along with every clip and the procedural layer.
  416  -- Studio knob for checking it from the command bar
  426  -- The speed reload: hides the magazine meshes over their windows and, when the clip
  427  -- passes the drop point, throws a world-size copy of the magazine out of the well.
  458  -- a mesh skinned to several bones takes them along, posed as drawn now
  475  -- tucked joints move their vertices inside the magazine and ride with it
  476  -- (RootPart space at rest: offset * mesh point)
  507  -- The wall pull-back's pose for the next steps, in the hold space (WallPullback eases
  508  -- it; identity puts the gun back in the ready pose).
  513  -- The stance pose for the next steps, in the hold space after the wall pose (Stances
  514  -- eases it; identity is the class's own hold).
  529  -- One-shot clip; the idle or walk loop resumes underneath when it ends.
  542  -- Clips back to back, stretched together to `duration` when given.
  574  -- `interval` is the weapon's fire interval. A class with a follow clip (the pump) keeps
  575  -- only the recoil part of Fire and speeds both up together, no faster than 1.5x, so
  576  -- the action is closed before the next shot is allowed.
  632  -- Magazine reloads play one clip section fitted to the config time (tactical cut or
  633  -- empty), shell reloads build enter + N shells + leave (+ pump from empty).
  686  -- Fire (or a swap) interrupting a reload. For shells the one in the hand still reaches
  687  -- its ShellIn marker, then the arms blend back over `exit` (or into the chambering
  688  -- pump); anything else blends back right away.
  733  -- Emits the markers the stepped clip crossed. `clip` is the clip that was playing
  734  -- before the step, so a marker right at the end still fires on the step that finishes
  735  -- the clip, and a cut clip never reaches the markers past its end.
  767  -- Makes sure something plays: the next queued entry, else the idle/walk loop.
  792  -- `placement` is the camera CFrame with the procedural offsets applied; the rig's eye
  793  -- point is put on it.
  796  -- debug knob for checking clips frame by frame from the command bar:
  797  -- workspace.CurrentCamera:SetAttribute("ViewmodelTimeScale", 0.1)
  804  -- A clip that ends mid-frame hands the rest of the frame to the next one, so a chain
  805  -- of short sections (shell after shell) stays on the WeaponsConfig timeline instead
  806  -- of losing a frame at every seam.
  830  -- framing knob for tuning a class's `hold` from the command bar:
  831  -- workspace.CurrentCamera:SetAttribute("ViewmodelHold", Vector3.new(0.05, -0.1, 0.05))
```

## src/client/systems/PlayerSfx.luau

```
    3  -- The player's own body: heartbeat and wind loops driven by health and speed, gear
    4  -- rattle on every step, landings, the cloth whoosh on a hard lateral flip, and the
    5  -- concussion filter after damage. Everything here sits on the listener, so with the
    6  -- spatial audio engine on it plays as 2D PlayerFoley voices on the sfx bus and the
    7  -- concussion drives the sfx bus equaliser; with it off the Sounds and the
    8  -- EqualizerSoundEffect from before stay.
```

## src/client/systems/PostFx.luau

```
   83  -- the biome and night presets carry their own bloom (LightingConfig)
```

## src/client/systems/SandboxBodyGallery.luau

```
    3  -- Studio test yard, client side: the third-person body gallery. A row of mannequins per
    4  -- weapon class (clones of the local character with the class's WorldWeapon built on),
    5  -- one column per station: idle, walk, run, strafe, sprint, aim sweep, fire burst,
    6  -- tactical reload, empty reload, shells and equip. Each station drives its BodyRig with
    7  -- scripted inputs on a loop, so the hold, the aim spread, the recoil and every gesture
    8  -- can be judged by eye at the class's real WeaponsConfig timings. Placed relative to the
    9  -- SandboxOrigin attribute in the free strip east of the zombie gallery.
   27  -- run clip speed (0 for none) and the reported body speed
   30  -- seconds of one loop; the driver runs on `phase` inside it
   47  -- updates since the label was last written
   51  -- clear ground south of the props at real size (the first spot, z -170, stood among them)
  103  -- A copy of the local character stood on `cframe`: root anchored, scripts and the
  104  -- server's gun removed, name hidden, the class's gun built on. The copy also drops the
  105  -- local character's IKControls (FootPlanting's foot chains, and the body layer's own
  106  -- when V was on): with their targets left on the real character, and no animator track
  107  -- rewriting the joints each frame, they bent the mannequins over at the hips.
  139  -- a posed prop: no falling-down or getting-up states on an anchored root
  207  -- Seconds of one loop of a gesture station at this class's timings, plus a rest.
  225  -- The scripted input of one station for this update.
  291  -- start the round at a different station each frame: with every station in full
  292  -- cadence the per-frame cap would otherwise starve the same last rows every frame
  306  -- per station, not per frame: with the round robin a station and a frame
  307  -- multiple rarely met, and the labels froze for seconds
  333  -- the mannequins face +z, so the walkway along the south side sees them head on
```

## src/client/systems/SandboxInput.luau

```
    3  -- Keys for the Studio test yard (server Sandbox, DevConfig.SANDBOX):
    4  --   G sends a chasing wave, H resets the yard, J calms everyone, T teleports back to the
    5  --   start (server commands);
    6  --   V third person on/off (the stock orbit camera, viewmodel hidden, body visible);
    7  --   Z slow motion: 1, 1/4, 1/10 for the viewmodel, casings, both clip galleries and the
    8  --     treadmills (camera ViewmodelTimeScale, workspace DevTimeScale, server gallery);
    9  --   B plays the sound lane;
   10  --   K shows the audio engine overlay (every live voice with its distance, delay,
   11  --     occlusion and filter), L fires a remote rifle shot 30 studs ahead with reflections.
   12  -- Studio's own free camera (Shift+P) works too.
   13  -- The dev button at the top centre swaps the test yard and the normal run while
   14  -- playing (server Sandbox, DevMode); M does the same, and holding Left Alt frees the
   15  -- cursor to click it. The yard keys (G H J T Z B) only act in the yard. Does nothing
   16  -- outside Studio.
   39  -- keys that only mean something in the yard
   92  -- CameraController reads this (Studio only) like DevConfig.THIRD_PERSON_VIEW
  110  -- the dev button: shows where you are and goes to the other mode
  118  -- top centre: the goals panel owns the top left corner
```

## src/client/systems/SandboxWeaponGallery.luau

```
    3  -- Studio test yard (Sandbox), client side:
    4  --   * the first-person weapon gallery: every pack clip on its own copy of the pack rig,
    5  --     standing in the world at the uploaded size (about twice life size) and seen from
    6  --     the side, looping with a short pause; the in-game uses of a clip (tactical and
    7  --     empty reload cuts, the shotgun's shell loop and chambering pump, fire into pump)
    8  --     get their own stations. Clip markers flash on the label and play their sound at
    9  --     the rig, so sound sync can be judged by eye and ear.
   10  --   * the zombie gallery's treadmills (SandboxGallery on the server): strips scrolled at
   11  --     each walk/run clip's measured ground speed.
   12  --   * the sound lane: speakers played in turn (B) with a gunshot, a zombie call and an
   13  --     explosion.
   14  -- Everything honours the workspace attribute DevTimeScale (set by SandboxInput, Z).
   48  -- rigs at 1.6x their uploaded size (about 3.5x life): hands, bolts and magazines read
   49  -- from the walkway. Each rig's eye point (where the game puts the camera) stands at
   50  -- EYE_HEIGHT above the station, so every exhibit is framed the way the game frames it
   51  -- and its weapon sits at about the walkway's eye height.
   54  -- studs from the post top to the station label, clear of the arms above the weapon
   62  -- display order; clips not listed follow alphabetically
   86  -- `height` is studs above the post's centre; the label floats over the rig
  117  -- Every clip in the pack plus the in-game cuts of this class.
  167  -- World centre of the weapon body as the player posed it last. The weapon bone's own
  168  -- origin can sit far from the gun (the rifle's Grip_01 is below and behind it), so the
  169  -- weapon mesh's rest centre is carried along with the bone.
  195  -- move the whole model so the root lands on the station, then drive it by the root
  209  -- The bind pose is no guide to where the clips hold the weapon (the pistol pack's
  210  -- bind pose has it several studs below the idle hold, which left every pistol rig
  211  -- hanging far above its post), so the rig is lifted by its eye point and the post
  212  -- stands under the weapon body as the idle clip's first frame holds it.
  283  -- the rig looks down its -Z: turn it to look down world -X, so the +Z walkway
  284  -- sees its right side (ejection port, bolt, mag well)
  366  -- the stripes run toward the model's back (-X) and wrap within the strip
  380  -- The sound lane: each speaker in turn plays a gunshot, a zombie call and an explosion.
  382  -- the lane is a distance test, so it only makes sense from its pad: pressed anywhere else
  383  -- (the spawn is 300 studs away, where every speaker is about -30 dB or quieter) B moves
  384  -- you there
  395  -- the speakers stand toward -Z of the pad
  420  -- the rifle shot is two files (the dry close part and its outdoor reflection,
  421  -- WeaponSfx.tailFor) that together make the recording
  427  -- through the engine's real classes when the weapons are on it (the remote
  428  -- gunshot with its reflection fan, the zombie vocal, the explosion), else the
  429  -- plain 3D wrapper
  471  -- wait for the yard, so the gallery is built once the player is there
```

## src/client/systems/SfxPlayer.luau

```
    3  -- Shared one-shot playback. With the spatial audio engine on, both calls are thin
    4  -- wrappers over AudioEngine.play (classes Generic2D and Generic3D, the old rolloff
    5  -- distances mapped onto range and hold), so call sites that were never moved onto the
    6  -- engine still propagate. With it off, the pooled 2D Sounds and the per-call 3D Sound
    7  -- from before the engine are unchanged.
```

## src/client/systems/Stances.luau

```
    3  -- Weapon stances, manual lean and the magazine check on the first-person rig
    4  -- (wiki: Stances; numbers in StanceConfig, rules in StanceMath).
    5  --
    6  -- - Stances: the stance key cycles mid, high ready and low ready. The pose goes into the
    7  --   pack viewmodel's hold space through PackViewmodel.setStancePose, eased like the
    8  --   wall pull-back. A shot from high or low ready asks requestFire first: the gun comes
    9  --   up over the class's raise time and the shot leaves when it is up; it stays up for
   10  --   StanceConfig.RETURN_AFTER after the last shot, then eases back to the chosen stance.
   11  --   A reload, the draw or an inspect eases the pose out without changing the stance.
   12  -- - Lean: Q and E (hold, or toggle) roll the camera and move it sideways, stopping short
   13  --   of a wall at the side; the viewmodel takes part of the roll back and the
   14  --   third-person upper body leans (BodyRig, with the value on the BodyAim packet). The
   15  --   lean is put on the camera after the camera's own steps and taken off again before
   16  --   them, so the runner camera's lerp never sees it. Visual only: nothing reaches the
   17  --   server's rules.
   18  -- - Magazine check: WeaponController turns a held R into startCheck/releaseCheck; the
   19  --   weapon tips toward the camera and the count shows while it is in.
   20  --
   21  -- Only the pack viewmodel shows the poses. Without one (the legacy rig, the hub, death)
   22  -- the viewmodel stops asking and every shot is allowed at once.
   40  -- the viewmodel stopped asking for a pose this long ago: no pack rig on screen
   42  -- folders the side cast never stops on (as WallPullback)
   61  -- lean
   66  -- set by the Studio DebugWeapon hook (WeaponController): a lean held without keys
   71  -- prompts on screen that use the right-lean key (E is ProximityPrompt's default)
   85  -- the runner camera, or in a frozen Studio run (the test yard) Roblox's own
   86  -- first-person camera that CameraController hands over, so the lean can be tried
   87  -- there too (not in the third-person review view)
  129  -- Distance to a wall on the lean's side, nil when clear.
  138  -- Camera.Value - 1: take last frame's lean off, but only if nothing else moved the
  139  -- camera since (a cut, the death camera), so the camera's own steps start clean.
  150  -- Camera.Value + 2: after CameraController and CameraEffectsController.
  156  -- outside a live run (death camera, cabin, a menu) the lean is gone at once, so no
  157  -- other camera ever gets it on top
  181  -- One frame of the stance state and the pose for the pack viewmodel's stance channel:
  182  -- the stance or check pose with the lean's counter-pose on top. `suppressed` while a
  183  -- reload, the draw or an inspect plays.
  187  -- the rig was away (death, the hub, a weapon change): start from mid again
  199  -- A shot asks to leave. True at once without a pack rig on screen; otherwise true when
  200  -- the gun is up, and false while it comes up (the shot waits for isUp).
  212  -- Whether a shot is waiting on a raise right now.
  237  -- Whether the pack viewmodel is on screen asking for poses (the check and the stances
  238  -- only exist there).
  251  -- The eased lean, -1 (left) to 1 (right), for the body and the BodyAim packet.
  256  -- The weights and the lean, for overlays and Studio checks.
  269  -- Studio checks: hold a lean (-1..1) without keys, nil hands it back to the keys.
```

## src/client/systems/UiSfx.luau

```
    3  -- Interface sounds and the chase duck. With the spatial audio engine on the clicks are
    4  -- UI-class voices on the ui bus, which joins the mix after the duck compressor so a
    5  -- menu never dips under gunfire; the chase duck still goes through
    6  -- MusicController.setDuck, which scales the music fader.
```

## src/client/systems/Viewmodel.luau

```
   27  -- a weapon pack rig (skinned arms + weapon with baked clips) replaces `rig` for every
   28  -- class ViewmodelPackConfig lists once the server has loaded its model
   31  -- what the caller last asked for (the test yard's third-person view hides the rig); a
   32  -- rig built later keeps it, and a dead character hides the rig regardless
   35  -- listeners get (phase, weapon class, tag); the tag says what the clip was doing
   36  -- ("fire", "tactical", "empty", "shell", "chamber", "equip") so a pump after a shot can
   37  -- be told from the chambering pump after a reload
   41  -- what the legacy sequencer is playing, for the tag of the phases it emits
   43  -- when the current rig started its draw; WeaponController holds fire for drawTime
   46  -- The viewmodel only belongs to the run. Outside the Mission phase the camera is not
   47  -- ours, so a rig parented to it hangs in mid-air in front of the hub camera.
   61  -- the recoil springs integrate in small steps so a shot kicks the same at any frame rate
   79  -- When a published clip drives the Animator it owns Motor6D.Transform. The procedural
   80  -- layer writes the same channel every RenderStepped, so both writing in one frame means
   81  -- the later write wins and the clip silently does nothing. This flag hands the joints
   82  -- over; the root keeps carrying sway, bob and recoil either way.
  166  -- the draw clock starts now: the old rig can stay on screen while the new one
  167  -- loads, and it must not count as the new weapon being ready
  213  -- Seconds since the current rig started its draw (huge when there is no rig, so a
  214  -- missing viewmodel never holds fire).
  222  -- Call this with true for as long as an AnimationTrack is driving rig.animator, and
  223  -- false the moment it stops. While it is true the procedural bone offsets stand down
  224  -- and the clip owns every joint.
  277  -- a shot that cuts a reload or the draw blends out of that pose instead of snapping
  285  -- WeaponController's predicted magazine ran dry or was filled (the bolt or slide of a
  286  -- pack rig holds back while it is empty)
  294  -- The authored sequence drives the pose and the audio phases; the springs only add
  295  -- the mechanical travel on top, so nothing here runs on a wall-clock timer any more.
  296  -- The plan's times come from WeaponsConfig, the same timeline the server counts ammo on.
  304  -- legacy fallback for a pump without its pack: one pass over the whole reload
  316  -- Fire interrupting a reload (see PackViewmodel.cancelReload). The legacy rig simply
  317  -- blends back to rest.
  517  -- near a wall the gun draws in (WallPullback casts along the aim, eases the pose)
  519  -- the stance, the magazine check and the lean's counter-pose (Stances); a reload, the
  520  -- draw or an inspect eases them out so the clip plays from the class's own hold
  566  -- tiltRoll packs two different units into one spring: X is a lateral shift in studs,
  567  -- Z is a roll in radians. Adding the whole vector here fed the roll back in as a
  568  -- depth translation, so strafing shoved the weapon towards and away from the camera.
  569  -- Only X belongs in the position sum; Z is applied in the rotation sum below.
  608  -- Sprint is the only looping sequence, and it yields to anything the player
  609  -- actively triggered: firing, reloading or inspecting.
```

## src/client/systems/ViewmodelBuilder.luau

```
   14  -- Rojo-mounted MeshParts render at the mesh's native size (see MeshTemplates), so the
   15  -- weapon and arm meshes are loaded through MeshTemplates as soon as this module loads.
   24  -- Yields until the weapon and arm meshes have loaded, so the first equip does not build
   25  -- from wrongly sized templates. Only call it where yielding is allowed.
   41  -- authored offsets for this bone are in the parent's axes (weapon space), not in the
   42  -- bone's own rest frame; pose() converts them. Set on the mesh hand pivots, whose rest
   43  -- frames are turned far from the weapon's axes.
   65  -- authored pose offsets from AnimationSequencer, keyed by bone name; they
   66  -- multiply the bone's rest transform and stack with the mechanical overrides
   68  -- An Animator drives Motor6D.Transform, and so do we. Writing both in the same frame
   69  -- means the later write wins and the clip appears to do nothing. When a clip owns the
   70  -- bones, we keep the root - which carries sway, bob and recoil - and leave the joints
   71  -- to it.
  100  -- One helper for both build paths. The fill is what makes the weapon readable against a
  101  -- bright desert sky, but under the Night modifier it lights the player permanently and
  102  -- the flashlight beam stops registering, so it tracks the mission attribute live rather
  103  -- than being decided once at equip time.
  160  -- Only the root is anchored. A joint cannot move an anchored part, so every
  161  -- other piece hangs off the root through the joint chain.
  177  -- Animatable joints are Motor6D and carry the bone name, so a published
  178  -- Roblox animation targeting the same names drives this rig unchanged.
  200  -- Adopts a part that already exists, rather than creating one. This is the only way to
  201  -- get mesh geometry into the rig: MeshPart.MeshId cannot be written by a script, so the
  202  -- meshes arrive as instances mounted by Rojo and we join them here.
  237  -- Mesh geometry for a class, if Rojo has mounted any. `Main` is the hub the rest hangs
  238  -- off, and the three moving pieces take the same bone names the procedural rig used, so
  239  -- PoseLibrary and the spring layer carry over untouched.
  263  -- The mounted template ships its own joints so it reads correctly in Studio. We
  264  -- rebuild them here against this rig's root, and leaving the originals in place
  265  -- would put two Motor6Ds on the same part - which over-constrains the rig and stops
  266  -- an Animator driving it at all.
  298  -- The procedural path runs every size and rest offset through ViewmodelConfig.SCALE,
  299  -- and so do the arms below. Adopting the mesh at its authored size left a full-size
  300  -- weapon in hands shrunk to 0.72, and made the authored pose translations - which
  301  -- ViewmodelBuilder.pose also scales - land short.
  305  -- weaponRoot first, so every other piece can hang off it
  317  -- A template without a Barrel bone and without a Muzzle marker used to leave these
  318  -- nil and then index them, taking the client down at equip time. weaponRoot is always
  319  -- present by this point, so it is the floor.
  337  -- A dedicated Muzzle marker already sits at the barrel tip, so it needs no offset.
  338  -- Falling back to the barrel itself means the attachment would otherwise sit at the
  339  -- part's centre and spawn the flash halfway down the weapon.
  353  -- An Animator matches a clip's poses to parts by name, so two parts sharing a name
  354  -- across the left and right arm stops the whole clip driving anything. Every part here
  355  -- carries its side.
  374  -- Only the forearm stub is ever inside a first-person frame; an upper arm would
  375  -- chain behind the camera and render as nothing.
  380  -- a short stub: measured in Studio, a 0.95-long forearm sat 1.1 studs from the
  381  -- camera and covered 60% of screen height on its own
  385  -- Mesh arms cut from a Mixamo soldier (tools/arms_rig). Same bone names as the box arms
  386  -- (handR, handRWrist, handRForearm and the L set), so PoseLibrary and the spring layer
  387  -- drive them unchanged. The bones sit on invisible pivots: the hand bone on the grip
  388  -- axis, the wrist bone on the wrist, and the meshes hang off them by their centres.
  389  -- Returns false when the meshes are not uploaded yet, and the caller falls back to boxes.
  390  -- Roblox's glTF importer turns uploaded meshes 180 degrees about Y (see ZombieFactory),
  391  -- so each arm mesh is turned back about its own centre.
  473  -- Prefer real mesh geometry when Rojo has mounted some for this class; the procedural
  474  -- box weapon below stays as the fallback for classes that have no mesh yet.
  642  -- The root carries the whole procedural layer; every other piece follows through its
  643  -- joint. Bone offsets go into Motor6D.Transform, which is the same channel an Animator
  644  -- writes, so authored poses and a published clip cannot fight over the rest transform.
  671  -- PoseLibrary is authored in design units against the unscaled rig, so its
  672  -- translations have to follow ViewmodelConfig.SCALE like every rest offset.
  676  -- Motor6D.Transform acts in the bone's rest frame; turn a weapon-space offset
  677  -- into that frame so it moves and turns the hand along the weapon's axes,
  678  -- still pivoting about the hand
```

## src/client/systems/ViewmodelClipPlayer.luau

```
    3  -- Plays clips baked by tools/fps_pack (gltf_anim.py + emit_luau.py) on an imported
    4  -- skinned viewmodel by writing Bone.Transform every frame, so pack animations run
    5  -- without uploading Animation assets.
    6  --
    7  -- A track holds, per key, the bone's model-space change from its rest pose (Roblox axes,
    8  -- RootPart space): x, y, z in 1/2000 stud and a quaternion in 1/32767, base64 packed.
    9  -- Roblox's importer drops bones without skin weights and folds their transforms into
   10  -- the children, so baked local transforms would not match; a model-space change applied
   11  -- to each bone's own rest world does:
   12  --     targetWorld = delta(t) * restWorld
   13  --     Transform   = boneCFrame^-1 * parentWorld^-1 * targetWorld
   14  -- Bones are solved parent first. `extras` are nodes without skin (the pack's camera
   15  -- bone) whose rest world was baked alongside; `extraWorld` samples them.
   28  -- stretch or squeeze the played section (from..to) to last this many seconds
   29  -- (reload timing from config); overrides `speed`
   31  -- start fraction of the clip (a shell loop skips the clip's idle lead-in)
   33  -- end fraction of a one-shot: the clip reports finished there and the caller blends
   34  -- to the next clip (a tactical reload stops before the bolt pull)
   36  -- share of the clip's move away from the pose it started in (1 = as authored): a
   37  -- lighter version of an authored motion, such as a kick that is too big
   83  -- frame indices and raw 7-number rows; free of Roblox types so it can be tested
   84  -- outside the engine
  117  -- clip time at which a one-shot finishes (the `to` fraction)
  121  -- real seconds of the last step that were left over after a one-shot finished,
  122  -- so the next clip can start in the same frame instead of losing them
  134  -- `root` is the importer's RootPart holding the Bone tree. Call before any Transform is
  135  -- written so the rest worlds are read from the bind pose. `scale` multiplies the baked
  136  -- translations, for a rig scaled with Model:ScaleTo.
  178  -- Rest world (RootPart space) of the first bone with this name.
  188  -- World (RootPart space) the bone was given on the last step, or its rest world.
  257  -- Moves the end of the playing one-shot, never behind the current time. Used to let a
  258  -- shell reach its insert marker and stop there when fire cancels the loop.
  267  -- Drops the current clip; the pose holds until the next play() crossfades out of it.
  302  -- Where a pack trades two identical meshes between bones in one frame (the G17's
  303  -- magazines swap roles at frame 54 of both reloads), interpolating across the trade flies
  304  -- both through the view for that frame. The tracks of `clipName` matching `pattern` hold
  305  -- their pose of the frame before and snap on `frame` instead.
  350  -- A bone's own Transform (relative to its parent bone) at one clip time: the bolt or
  351  -- slide locked back on an empty magazine is held at this, so it stays on the gun while
  352  -- the gun moves through whatever else plays.
  378  -- The current model-space change of a track (blended through the crossfade, and held at
  379  -- the clip's weight from the pose it started in).
  391  -- Rest-relative world (RootPart space) of a baked extra node, e.g. the camera bone.
  404  -- Advances the clip and writes every bone. Returns true on the step a one-shot clip ends.
```

## src/client/systems/WallPullback.luau

```
    3  -- The first-person weapon pulling back near walls (docs/gameplay/wall-pullback.md),
    4  -- after Modern Warfare 2019. Each frame the viewmodel asks for the pose: a thin
    5  -- spherecast from the camera along the aim, as long as the held weapon's reach
    6  -- (WallPullbackConfig.reach by class); the nearer the hit, the further the pack
    7  -- viewmodel retracts toward the chest and tilts up and aside, eased in and out by
    8  -- WallPullbackMath so it never pops. Fully pulled back (the muzzle would be inside the
    9  -- wall) the gun does not fire until the hit is clear again; partly pulled back it
   10  -- fires. The cast ignores the local character, zombies and their props, pickups,
   11  -- casings and the viewmodel itself; parts with CanQuery off are never hit, and parts
   12  -- with CanCollide off are skipped too (RESPECT_CAN_COLLIDE). The server's rules are
   13  -- unchanged: this only keeps the client from sending a shot from inside a wall.
   24  -- folders the cast never stops on (ZombieAI, ZombieAI's corpses and props,
   25  -- WeaponPickups and the upgrade stations, WeaponVfx's casings and debris)
   27  -- a fire block older than this is stale (the viewmodel stopped asking: hub, death)
   71  -- One frame: casts, eases the blend and returns the pose for the pack viewmodel's hold
   72  -- channel (identity when nothing is near). `class` is the held weapon's class.
   87  -- Fully pulled back: the shot would leave from inside the wall.
   92  -- The eased blend (0 ready, 1 fully pulled back) and the last hit distance, for
   93  -- overlays and Studio checks.
```

## src/client/systems/WeaponController.luau

```
   31  -- Client-side reload, run on the same WeaponsConfig timeline as the server so the
   32  -- predicted count changes when the hands seat the magazine (or each shell), not a
   33  -- round trip later. The server runs its own copy of this and stays authoritative.
   41  -- magazine
   45  -- shell: shells planned, counted so far, and the most that will go in (fewer once
   46  -- fire has cancelled the loop)
   53  -- A higher AmmoMag than predicted within this long of a shot or a reload end is an
   54  -- older update still in flight, not news. Past it the server's number wins.
   63  -- a shot pressed during a shell reload fires once the fast exit is over
   65  -- a shot pressed in high or low ready fires once the gun is up (Stances)
   67  -- R: pressed when, and whether the hold has turned into a magazine check
   72  -- the mouse wheel's quick swap ignores ticks closer together than this
   78  -- client-side spread for the shooter's own predicted tracers and impacts
   83  -- Tracers, impact puffs and impact sounds for one shot. The shooter draws these the
   84  -- frame the shot leaves (predictShot); everyone else draws them from the server's Shot.
  112  -- The shooter's own shot, drawn at once from a client ray with the same spread rule
  113  -- as WeaponService. Damage stays the server's (it rays the same origin and direction
  114  -- and validates them); waiting for its Shot reply put every tracer and impact one round
  115  -- trip behind the muzzle flash, and the tracer then started from wherever the viewmodel
  116  -- had moved to.
  151  -- the Studio "empty" debug command fakes an empty mag; keep reconcile off it for a bit
  183  -- SkillEffects.reloadScale, replicated by the server so the client timeline matches.
  212  -- Counts what the reload has seated by `now` and ends it when its time is up.
  240  -- Fire pressed during a shell reload: the shell in the hand still goes in, then a fast
  241  -- exit (plus the pump if nothing is chambered) and the buffered shot. Returns
  242  -- "cancelled", "late" when the loop is already over (ReloadToIdle playing), or "empty"
  243  -- when stopping now would leave nothing to fire.
  271  -- `pressed` is a fresh trigger press (not the auto-fire repeat): it can cancel a shell
  272  -- reload and it arms the one dry click per press.
  278  -- fully pulled back against a wall: the muzzle is inside it, nothing leaves until
  279  -- it clears (partly pulled back, the gun fires)
  300  -- before ammo-add nothing fires and the old count stands
  303  -- another weapon's reload, or the magazine is seated: the shot cuts the rest
  307  -- from high or low ready (or a magazine check) the gun comes up first; the press
  308  -- fires once it is up
  342  -- the pump ejects its hull on the pump stroke instead (see the phase listener)
  358  -- the action is still cycling (the pump after a shot): let it close first
  421  -- Number keys: loadout slots 1 and 2 normally. With the temporary
  422  -- WeaponsConfig.ALL_WEAPONS_UNLOCKED test flag, key N takes WeaponsConfig.order[N]
  423  -- whether it is owned or not (keys past the list do nothing).
  435  -- The mouse wheel (Q leans now, Stances): back to the previous weapon when testing with
  436  -- every weapon unlocked, otherwise the loadout slot toggle.
  497  -- the magazine check's count (hold R), only while the weapon is tipped in
  514  -- The check's count from the client's own count, shown only while the weapon is tipped
  515  -- toward the camera; optionally the corner counter is hidden outside a check.
  532  -- Hold R: once held past MAG_CHECK.holdTime with the pack viewmodel up and no reload
  533  -- running, the press is a magazine check instead of a reload.
  545  -- The server only lowers AmmoMag on a shot, so a lower value than predicted is news
  546  -- (a shot it rejected, a reload it refused). A higher one right after a shot is usually
  547  -- an older update still in flight; reconcileAmmo takes it once things are quiet. While
  548  -- a local reload runs the prediction owns the count.
  634  -- a swap cancels the reload (the server keeps whatever it had counted) and any
  635  -- buffered shot; reset before setWeapon, which can yield while the rig loads
  663  -- the shooter already drew this shot when it left (predictShot)
  673  -- Studio-only hook so animation work can be driven and screenshotted without
  674  -- synthetic mouse input, which does not reach the client under a locked cursor.
  704  -- the reload animation alone, with no reload behind it: slowed down with the
  705  -- camera's ViewmodelTimeScale it is not cut short when the server's reload ends
  720  -- Stops the forward run so a static target range stays in front of you.
  721  -- Without this the runner leaves the dummies behind within a second.
  739  -- Clip markers: reload foley, and the pump's hull. BoltBack tagged "fire" is the pump
  740  -- stroke after a shot; the chambering pump after a reload ("chamber") ejects nothing.
  756  -- the pickups' outlines and toasts start with the weapons
  772  -- a short press reloads on release; a hold is the magazine check
```

## src/client/systems/WeaponPickupClient.luau

```
    3  -- The client half of the weapon pickups (docs/gameplay/weapon-pickups.md) and the
    4  -- upgrade station (docs/gameplay/upgrade-station.md): the Highlight outlines that let
    5  -- a scene or a station read through the fog, pooled below Roblox's limit of 31
    6  -- rendered Highlights and handed to the nearest by the pure HighlightBudget; the toast
    7  -- when the server hands over a weapon, upgrades one or refuses; the announcer line and
    8  -- the burst on an upgrade; and the station prompt's quote, written into the prompt's
    9  -- action text locally for this player's weapon. The prompts are the server's.
   85  -- One from the pool, made only while the pool is under the budget.
  196  -- An announcer line, 2D, when its id is non-zero (the slots are `needed` in the
  197  -- manifest until real licensed files exist; nothing plays until then).
  211  -- The station prompt's action text is this player's quote: the level bought and its
  212  -- price, or why not, from the attributes the server keeps (WeaponLevel, RunCredits).
  298  -- For the debug overlay and tests in Studio: highlights live right now.
```

## src/client/systems/WeaponSfx.luau

```
   19  -- Every sound is resolved by its AssetIds.audio.weapons KEY at play time, so a real
   20  -- recording dropped into assets/manifest.json (for example `rifle_bolt_back`) takes
   21  -- over from the generic placeholder without a code change. A key that is missing or 0
   22  -- falls back to the generic key, and to silence when that is missing too.
   23  --
   24  -- Two paths (docs/audio/weapons-integration.md). With SfxConfig.WEAPONS_ON_ENGINE the
   25  -- shooter's layers play on the engine's OwnGunshot class, the tail is picked by the
   26  -- listener's acoustic environment, a reflection fan runs from the muzzle, teammates'
   27  -- shots are GunshotRemote with distance layers, casings and the gong and bullet
   28  -- impacts take their own classes. Off, every function takes the Sound-pool path it had
   29  -- before, so the two can be compared in Studio.
   39  ---------------------------------------------------------------------------------------
   40  -- Legacy path: a Weapons SoundGroup with a room reverb, per-id Sound pools, acoustic
   41  -- zones scanned from Workspace.
   91  -- a room, so indoors only (updateTail): outdoors the recordings carry their own space
  106  -- Voices: each sound id gets a small pool played round-robin. A voice that is still
  107  -- playing is never restarted (that chops its tail, the classic Roblox gun-audio
  108  -- artefact); the pool grows instead, and only past MAX_VOICES does the voice furthest
  109  -- into its playback get reused, the least audible cut available.
  112  -- per-voice variation so repeats never sound identical
  184  -- The shooter's own layers: 2D on the weapons bus through OwnGunshot (the class adds
  185  -- the pitch and gain jitter and feeds the duck sidechain), or the legacy pool.
  201  -- First key with a real id, or 0.
  215  -- the engine's own preload skips the weapons category, so it is done here
  254  -- Picks one of `keys` that has an id, never the same one twice in a row per `slot`.
  286  -- `tail_open_<class>` is the rest of the same outdoor recording as the close shot: the
  287  -- range's reflection and its decay, padded so both start at the blast. Played together at
  288  -- the same volume and pitch they rebuild the original shot. Indoors the close shot keeps
  289  -- its blast and takes the room tail instead. The generic `tail_open` (another recording)
  290  -- stands in, quieter, for a class without its own tail.
  296  -- the legacy path only knows interior or not
  311  -- The environment layer (the MW2019 reflections): a fan of rays from the muzzle, each
  312  -- hit playing the shot again from that surface. One fan per REFLECTION_INTERVAL, so
  313  -- automatic fire spawns a slap every second shot or so; the Reflection class caps the
  314  -- live slaps.
  324  -- Low-ammo cue: a metallic spring layer on each shot once the mag is down to
  325  -- config.lowAmmo, rising to +3 dB on the last round, where the slide/bolt lock clack
  326  -- joins it. Both keys stay silent until their recordings exist (the lock falls back to
  327  -- the generic bolt only on the pistol, whose slide really locks back).
  329  -- kept light: the recordings carry their own low end
  347  -- `remaining` is the magazine count after this shot, for the low-ammo layer; `muzzle`
  348  -- is the world position of the muzzle, the origin of the reflection fan. The spent
  349  -- casing's sound is no longer on a timer here: it plays when the visible casing lands
  350  -- (WeaponVfx.onCasingLanded -> WeaponSfx.playCasingLand).
  366  -- a little weight under the blast (spec: mech + punch + sub + tail)
  389  -- Phase markers from the viewmodel clips (PackViewmodel, AnimationSequencer), so the
  390  -- sound lands on the animation beat rather than on a timer that drifts when the clip is
  391  -- cut. Resolution per phase: the class key (`rifle_bolt_back`), then the generic keys.
  392  -- A class key of "" means that class makes no sound on that phase (a pump has no
  393  -- magazine to pull out).
  403  -- a shell pushed into the tube: the magazine seat, shorter and higher
  439  -- Placeholder pitch per class while the generic samples stand in: a pump reads heavier,
  440  -- a pistol lighter.
  448  -- the dropped magazine hits the ground about this long after it leaves the gun
  457  -- The sound a clip marker plays for a weapon class: id (0 = silent), volume, pitch.
  458  -- Also used by the Studio test yard to play markers at a gallery rig.
  485  -- empty reloads drop the spent magazine instead of pouching it
  493  -- Casing landings. On the engine: the Casing class (45 studs, culled by the engine,
  494  -- half-strength occlusion, 12 voices). Legacy: positional voices on attachments in
  495  -- Terrain (no Part per sound), pooled like the 2D voices; with every voice busy a
  496  -- landing is dropped, never cut.
  501  -- impact speed into the surface (studs/s) that plays at full volume: a casing dropped
  502  -- from the hip under world gravity lands at about 35-45, its bounce well under that
  528  -- volume and pitch by what the casing hit: brass rings on metal and stone, goes dull on
  529  -- wood and all but disappears in grass, sand or mud
  577  -- Registered with WeaponVfx.onCasingLanded; `caliber` is the WeaponsConfig casing.
  598  -- the brass tinkle stands in for a plastic hull: lower and softer reads as a thunk
  639  -- A ghost part for the legacy 3D one-shots, gone after `lifetime` seconds.
  655  -- A teammate's shot. On the engine: GunshotRemote with the close, mid and far layers
  656  -- (a layer without a recording falls back to the nearest one that exists, so the close
  657  -- take plays at every distance until the mid and far takes land), the class's air
  658  -- absorption, occlusion and speed-of-sound delay, and the reflection fan from the
  659  -- muzzle. Legacy: nothing inside 40 studs, then a 3D take and its tail on an anchor.
  689  -- the close part alone is a dry 0.13 s crack; the reflection is what carries at range
  706  -- Bullet impacts on the Impact class (120 studs, strong air absorption, one occlusion
  707  -- ray, the distance delay, so a hit on a far wall arrives after the shot). The family's
  708  -- own recordings (`impact_<family>_01..`) when they exist, else a Kenney impact already
  709  -- in the manifest stands in. A volley plays its first IMPACTS_PER_VOLLEY hits, so a
  710  -- shotgun's pellets read as one impact. Engine path only: the legacy path never had
  711  -- impact sounds.
  721  -- Kenney Impact Sounds (CC0) that are already in the manifest, per family.
  762  -- the stand-ins are foley recordings, closer to the mic than a bullet strike
```

## src/client/systems/WeaponVfx.luau

```
   23  -- The engine's own smoke sprite (the one the legacy Smoke object draws), shipped with
   24  -- every client; it is not an uploaded asset. The default ParticleEmitter sprite is a
   25  -- four-point sparkle, which reads as glitter rather than smoke once it is gray and
   26  -- large. Set this to nil to fall back to that default.
   29  -- One render-step callback drives both the casings and the flash timers. It runs just
   30  -- after the camera scripts (Camera = 200) so a view-space casing is placed from this
   31  -- frame's camera and never trails it by a frame; Heartbeat or a late priority jitters.
   34  -- a hitch must not teleport a casing through half the map in one step
   83  --------------------------------------------------------------------------------------
   84  -- Muzzle flash
   85  --
   86  -- MW reads as a white-hot core that is gone in one or two frames, a few flame petals
   87  -- thrown sideways, a forward tongue and a short light pop, never the same shape twice.
   88  -- Everything is built once per muzzle attachment and reused, so a 600 rpm weapon does
   89  -- not create and destroy a dozen instances a second. Every emitter is LockedToPart:
   90  -- the player runs at about 24 studs/s, and a world-space flash or wisp gets left almost
   91  -- a stud behind the muzzle in the two frames it lives, smearing back towards the eye.
   92  --------------------------------------------------------------------------------------
   98  -- forward lean of the petals, radians; 0 is a flat star across the muzzle
  105  -- Four shapes picked at random (never the same one twice in a row) on top of the
  106  -- random roll and scale, so sustained fire never repeats a frame.
  121  -- +-20% per shot
  123  -- Petals and tongue stay up at least one rendered frame and are cut after this, which
  124  -- is two frames at 60 fps. The core particle's own lifetime matches it.
  129  -- the first-person muzzle sits half a stud from the sleeves: at the world brightness the
  130  -- light washed the arms and the ground in front orange for three frames on every shot
  131  -- (the owner's recording, 2026-10-01)
  134  -- The first-person packs are drawn at about 1.17 studs per metre (an AK is 1.03 studs)
  135  -- while the world is 3.57 (1 stud = 0.28 m), so a flash sized for the world gun is three
  136  -- times too big on the viewmodel: a flame half the rifle long and a white blot over the
  137  -- crosshair on every shot (the owner's recording, 2026-09-30). Every size, speed and
  138  -- range on a rig under the camera is scaled by this.
  155  -- beams[1] is the forward tongue, the rest are petals; tips[i] is beams[i]'s far end
  164  -- 1 in the world; VIEWMODEL_FLASH_SCALE on a first-person rig
  168  -- optional values so pruning can assign nil under strict mode
  181  -- Rate is zeroed before parenting: a fresh emitter defaults to 20/s and would
  182  -- spray for a frame otherwise.
  196  -- pulls the sprite towards the camera so the barrel end does not cut it in half
  212  -- both rig builders keep the muzzle attachment's -Z along the barrel
  218  -- per-shot wisp: faint and short, it only has to hint that the gun is hot
  246  -- a denser puff: every shotgun shot, and burstSmoke
  274  -- the lazy post-burst wisp that rises off the barrel (barrelSmoke)
  307  -- Untextured beams from the muzzle to a tip attachment, facing the camera and
  308  -- tapering to nothing, make the flame spikes. The tips live on the muzzle's part so
  309  -- they ride along with the viewmodel for the two frames a flash lasts.
  369  -- Shrinks a rig built for the world down to the viewmodel's scale.
  380  -- Rigs die with their viewmodel on every weapon swap; drop the stale entries so the
  381  -- table does not hold destroyed instances for the rest of the session.
  393  -- someone may have cleared the attachment's children; rebuild if so
  424  -- The flash is laid out in camera axes, not the attachment's: the pack rigs'
  425  -- attachment frames follow a bone whose roll is arbitrary, and the star has to face
  426  -- the viewer whatever that bone does.
  477  -- Size is rewritten per shot for the +-20% scale; the envelope adds a little more
  478  -- spread between the two sprites, and Rotation 0-360 rolls each one.
  511  -- Spec: a puff after every shotgun shot; everything else leaves a faint wisp.
  525  -- A short, dense puff out of the muzzle. For the end of a sustained burst, or any
  526  -- moment a single heavy shot should leave smoke hanging.
  538  -- at least one rendered frame, however high the frame rate or however late
  539  -- in the frame the shot landed
  561  --------------------------------------------------------------------------------------
  562  -- Casings
  563  --
  564  -- Spec: parabola plus raycast bounce, never physics parts (small fast parts tunnel
  565  -- through floors). A casing lives in two phases:
  566  --   view:  simulated in CAMERA space from the eject port, so it arcs out of the frame
  567  --          while the player runs forward at 24 studs/s instead of vanishing behind;
  568  --   world: handed off with the carrier's velocity added, then a ballistic arc with a
  569  --          raycast per frame, up to two bounces, and it lies still on the surface.
  570  -- Parts are pooled per caliber and moved with one BulkMoveTo per frame; only casings
  571  -- that are live get iterated.
  572  --------------------------------------------------------------------------------------
  579  -- a second part for a different-looking base (the 12ga brass head); 0 = none
  584  -- camera-space eject velocity, studs/s: +X right, +Y up, +Z back toward the camera
  588  -- tumble about one axis, revolutions per second
  593  -- lacquered steel, the usual finish on surplus 7.62x39; swap in BRASS_COLOR for brass
  597  -- Sizes are world sizes, a bit over life size so a casing on the ground still reads.
  598  -- Casing sizes are real dimensions in metres times these. The world is about 3.6 studs
  599  -- per metre (1 stud = 0.28 m); the pack viewmodels are drawn far smaller (an AK is
  600  -- ~1.03 studs long, about 1.17 studs per metre, measured 2026-09-29), so a world-size
  601  -- casing next to the eject port looked bigger than the gun. Both get a mild boost so a
  602  -- 19 mm case still reads.
  621  -- AK: thrown harder and a touch forward rather than back at the shooter
  636  -- a pumped hull is heavier and flipped out by hand, so it goes slower and lazier
  654  -- per caliber
  655  -- across calibers; the oldest is recycled past this
  659  -- A casing handed from the view to the world triples in size (view scale to world
  660  -- scale) on the spot, about 0.7 studs from the eye: a dark rod flicked across the
  661  -- screen on every shot (the owner's recording, 2026-10-01). World casings closer to
  662  -- the camera than this stay hidden; they show once they have fallen behind or landed.
  665  -- world-down, re-expressed in camera space each frame
  667  -- Workspace.Gravity is ~5.6x real at 28 cm per stud; half of it lands the casing
  668  -- about 0.55-0.65 s after the shot, where the spec puts the drop sound
  671  -- fraction of the along-surface speed kept per bounce, so a casing thrown forward at
  672  -- run speed skids a couple of studs and falls behind rather than racing the player
  674  -- studs/s of random sideways kick per bounce
  676  -- a rebound slower than this settles on the spot instead of micro-hopping
  678  -- hits slower than this into the surface are not reported (inaudible anyway)
  680  -- spin kept per bounce
  681  -- rev/s about the long axis
  683  -- The eject port sits about 0.6 studs from the eye, inside a viewmodel drawn at well
  684  -- under world scale, so a world-size casing there would cover a good part of the
  685  -- screen. It is drawn at this fraction while in view and snaps to world size at the
  686  -- handoff, by which point it has always left the frame to the right. 1 disables it.
  688  -- used when the rig's Eject attachment is somewhere nonsensical (missing mesh anchor)
  703  -- head centre offset along -X (the base end), at scale 1
  708  -- index in activeCasings, 0 when idle
  718  -- rotation only; camera-relative in the view phase, world afterwards
  720  -- body-local unit axis
  722  -- radians per second
  736  -- reused every frame so the step allocates nothing
  742  -- invisible trigger and acoustic volumes are non-collidable; casings fall through them
  764  -- a cylinder Part's axis is X, so Size.X is the length
  816  -- swap-remove; the step walks the list backwards so the moved one is already done
  851  -- the folder was destroyed under us; forget whatever was flying
  865  -- the head's end cap sits a hair past the hull's so the two discs do not z-fight
  915  -- the camera holds the viewmodel; the folder holds every other effect part
  927  -- deferred so a listener that errors or yields cannot stall the render step
  953  -- Lying on something that moves (a zombie, a loose prop) would leave it floating
  954  -- once that thing walks off, so it just goes.
  961  -- keep the heading it tumbled into, laid flat: long axis in the surface plane
  975  -- the speed INTO the surface: what makes the ting loud, whatever the skid speed
  982  -- report the plop, then it sinks
  998  -- a bounce knocks the tumble off its clean axis
 1030  -- Handoff: same world point, and the velocity it really has there, which is
 1031  -- the carrier's (the running player) plus the eject throw.
 1061  -- a casing that just settled is placed here once and then left alone
 1081  -- Spawns one casing at the eject port. `carrierVelocity` is the velocity of whatever
 1082  -- carries the gun (normally the HumanoidRootPart's), added at the world handoff so a
 1083  -- casing leaves with the runner's momentum instead of stopping dead in the air.
 1084  -- Unknown calibers fall back to 9mm. Pump shotguns should call this on the pump.
 1117  -- Long axis (X) along the barrel, nose forward. The tumble is mostly about the
 1118  -- body's Y, which starts as camera up, so it cartwheels flat like a real ejection.
 1119  -- Negative spin swings the nose out to the right first, pivoting on the extractor.
 1127  -- placed now as well as in the step, so it can never render one frame at wherever
 1128  -- this pool slot last lay
 1141  -- Fires on each of a casing's first two impacts with the surface's material and the
 1142  -- speed into the surface in studs/s (typically 25-35 for the drop, 6-10 for the
 1143  -- bounce). Meant for the drop sound: brass ting, dull wood, silent grass, hull thunk.
 1144  -- Returns a function that removes the listener.
 1155  -- Older entry point: a 9mm casing with no carrier velocity.
 1176  -- the viewmodel's QA knob slows casings too, so a throw can be screenshotted
 1184  --------------------------------------------------------------------------------------
 1185  -- Tracers, smoke, pickups, impacts
 1186  --------------------------------------------------------------------------------------
 1201  -- The lazy wisp rising off a hot barrel after a burst. It uses the muzzle's pooled
 1202  -- emitter and is locked to the gun: world-space smoke streaks past the camera at run
 1203  -- speed instead of hanging off the barrel.
```

## src/client/systems/WorldSfx.luau

```
    3  -- World sources: the hangar roomtone bed, fire crackle loops on the diorama's
    4  -- FireAnchor parts, the distant boom every so often, the radio in the hangar cabin.
    5  -- With the spatial audio engine on the fires and the radio are AmbienceSource voices
    6  -- following their parts, the boom is an Explosion (delayed by distance, with
    7  -- reflections off the surroundings) and the roomtone a 2D bed; the legacy Sounds and
    8  -- the global AmbientReverb switch stay for the flag off (AmbientReverb only ever
    9  -- touched Sounds, so it is harmless to the engine's buses either way).
```

## src/client/systems/ZombieAudio.luau

```
    3  -- Zombie voices: a looping growl on every body, periodic idle moans from nearby
    4  -- bodies, an alert bark volley when the horde aggros, bites, and the horde walla bed.
    5  -- With the spatial audio engine on every voice is a ZombieLoop, ZombieVocal or Bite
    6  -- class voice following the body, so it propagates (distance curve, air, occlusion,
    7  -- delay); the walla is a 2D ambience bed. The Sound path from before stays for the
    8  -- flag off.
  119  -- the voice follows the body and releases itself when the model leaves the world
```

## src/client/ui/CabinGui.luau

```
    3  -- The helicopter intermission's panel (docs/gameplay/heli-intermission.md):
    4  --
    5  --   Cabin  the ready check: the squad with a mark per member, the AFK timer, READY
    6  --          (a toggle), LOADOUT (the shop panel on the "Cabin" catalog: loadout slots
    7  --          and perk equips, nothing to buy) and LEAVE (back to the hub).
    8  --   Crash  the timer and, on a repeat run, SKIP with the votes so far.
    9  --   Wake   a large "RUN" while GraceUntil is ahead, with the seconds left.
   10  --
   11  -- Everything shown comes from the server's IntermissionState snapshot; the buttons
   12  -- only send requests (IntermissionReady, IntermissionSkip, SquadLeave) the server
   13  -- validates.
  102  -- above the intermission's black fade (50)
  206  -- the crash beat is the cinematic's screen: the panel only stays for a skip vote
```

## src/client/ui/DamageNumbers.luau

```
    3  -- Damage numbers (docs/gameplay/hit-markers.md): the damage the server confirmed for the
    4  -- local shooter's shot rises from the hit point and fades over DamageNumberConfig.DURATION.
    5  -- Fed by HitMarkers from the same WeaponHit "Shot" reply as the markers (its hits and
    6  -- sixth value), placed at the first flesh hit: one number per shot, a shotgun's pellets
    7  -- summed. A fixed pool of BillboardGuis on invisible, non-queryable anchors in
    8  -- Workspace.DamageNumbers, the oldest reused when all are showing. Headshots take the
    9  -- theme accent, kills the largest size; the "Damage numbers" setting turns them off.
```

## src/client/ui/ForkHud.luau

```
    3  -- Route fork prompt: shows the two choices while the local runner approaches the vote
    4  -- line, highlights the side they are on, then announces the result. Reads only the
    5  -- Workspace attributes ForkService writes. See wiki/project-zprun/Route Forks.md.
```

## src/client/ui/HitMarkers.luau

```
    3  -- Hit and kill markers (docs/gameplay/hit-markers.md), after Modern Warfare 2019's hip
    4  -- fire: four short diagonal ticks around the crosshair when the server confirms the
    5  -- local shooter's shot hurt a zombie, tinted for a headshot, larger and red for a kill.
    6  -- Driven only by the server's confirmation in the WeaponHit "Shot" reply (its sixth
    7  -- value), never by the client's prediction, so a marker never shows for a hit the
    8  -- server did not count. One marker at a time, restarted by the next confirmation
    9  -- (HitMarkerMath); the "Hit markers" setting turns them off.
   28  -- the four ticks: their direction from the centre and their rotation
   74  -- The crosshair the weapon HUD draws (it moves with hip aim); the screen's centre when
   75  -- it is not there.
  119  -- The server's confirmation for one of the local player's shots.
  167  -- the same reply WeaponController draws other players' shots from; only the local
  168  -- shooter's own shots carry a confirmation for this player
```

## src/client/ui/HudGui.luau

```
   66  -- N, not M: the weapon modification menu owns M, and two actions on one key made
   67  -- the gunsmith unusable.
```

## src/client/ui/RunHud.luau

```
   73  -- the run balance: kill pay and distance pay folded into one number (RunEconomy)
   81  -- the perks riding along, as text badges under the wallet corner
  127  -- the run's goals with their progress, top left, one line each; the server packs
  128  -- them into the GoalsProgress attribute (docs/gameplay/goals-hud-and-ladder.md)
  132  -- under the FPS counter (12, 88), clear of the wallet row above it
```

## src/client/ui/SettingsGui.luau

```
  157  -- The read-only credits list (CreditsConfig, generated from the manifest): each group
  158  -- of CC BY works, one line per work, then the acknowledgements; scrolls on its own.
  241  -- the setting rows scroll between the title and the close button, so a longer
  242  -- schema (the credits list) never pushes the button off the panel
```

## src/client/ui/ShopGui.luau

```
  309  -- `titleOverride` replaces the vendor's display name (the cabin's loadout panel has no room).
```

## src/client/ui/SquadConfigGui.luau

```
  168  -- the start map: Random, then the maps with content (disabled ones are not offered)
```

## src/replicatedfirst/Boot.client.luau

```
  113  -- Everything visual the first run needs: the mesh templates and their textures in
  114  -- ReplicatedStorage, and every texture and mesh id in AssetIds (world props, PBR sets).
  115  -- Without this the textures arrive while the player is already running and visibly
  116  -- sharpen from a blurry first mip.
  120  -- Returns what to hand PreloadAsync and how many assets that should come to. The asset
  121  -- folders go in as instances: SurfaceAppearance maps cannot be read from a game script
  122  -- (reading ColorMap needs the Plugin capability), but PreloadAsync fetches everything an
  123  -- instance references, so the folders load in full without reading them.
  177  -- Starts the preload in the background; the returned table fills in as assets arrive.
  181  -- whatever goes wrong, the boot must not wait on a preload that died
  197  -- Share of the bar each phase fills: uplink, assets (driven by the real preload count),
  198  -- priming, deploying. The asset phase is the only one that waits on anything, and it
  199  -- shows its count so a slow first load reads as progress rather than a hang.
```

## src/replicatedfirst/BootConfig.luau

```
   13  -- textures and meshes fetched during the boot screen, so the first run does not start
   14  -- with low-resolution textures sharpening as the player moves; the boot never waits
   15  -- longer than this for them
   17  -- seconds into the asset phase before the skip key is shown
```

## src/server/systems/AmmoCrates.luau

```
  103  -- The crates standing in a chunk (their parts are not queryable), for WeaponPickups.
```

## src/server/systems/BodyAimRelay.luau

```
    3  -- Relays each player's third-person aim (pitch, yaw offset) and manual lean to every
    4  -- client: validates the numbers, clamps them, drops packets that arrive faster than the
    5  -- client is meant to send, and forwards them on the same unreliable remote with the
    6  -- sender attached. The lean is cosmetic (Stances): clamped to -1..1, 0 when absent.
    7  -- No state beyond the last accepted time per player; the aim is never authoritative
    8  -- for anything (shots carry their own direction through WeaponService).
```

## src/server/systems/ChunkFactory.luau

```
   65  -- tint with the part colour, otherwise the texture's own grey wins and every
   66  -- biome floor reads the same
   71  -- A mesh tree with an invisible trunk collider, so only the trunk blocks the runner.
  180  -- the meshes face either way along z; flip half of them so rows do not repeat
  250  -- the barrier's long side runs along the road, segments end to end
  272  -- Hedgehogs and a sandbag wall across a lane: the checkpoint blocker of the City and
  273  -- the Wasteland. Falls back to the divider when the props are not loaded.
  286  -- the wall's long side runs across the road
  382  -- A tussock of dry grass: a low mound with thin blades leaning outwards.
  463  -- A stand of corn: a few rows across the corridor with a pale tassel line on top and
  464  -- stalk lines on the face towards the runner. Blocks sight, not movement.
  503  -- the face the runner sees: stalk lines so the block reads as corn, not hedge
  861  -- Free run of the edge strip after each element, so the dressing clusters have room.
  865  -- `otherKind` and `alpha` mix two styles along the edge in a transition: each element
  866  -- is the other style with probability alpha.
  869  -- the flank crop rows start right at the corridor edge
  878  -- the z the element takes, its full extent plus its own gap
  881  -- the crop rows of a cornfield flank reach the edge on their own
  884  -- the street wall lives in WorldFlanks; this row is the kerb-side clutter in
  885  -- front of it
  937  -- the element's footprint is recorded so lane debris, flank props and the
  938  -- dressing clusters keep out of it; the gap after it is theirs
  944  -- In a transition, irregular patches of the other location's ground on a floor or an
  945  -- apron: as many as its share of the blend asks for (none at either end, most at the
  946  -- middle), so the ground reads as a mix instead of a seam. One patch is a cluster of
  947  -- overlapping turned slabs and discs, so its outline reads as worn ground rather than
  948  -- a laid tile. Along the chunk they thicken toward `towardZ` (the end where the other
  949  -- ground's share grows: ahead before the base ground switches, behind after it) and
  950  -- may hang over that end a little, so the switch itself is broken up too.
  969  -- density rising linearly toward `towardZ`, like the blend share itself
  978  -- stacked a hair apart so overlapping pieces do not fight over the same plane
  986  -- a cylinder's axis is its X: turned up, its +X end is the top face
 1020  -- the biome's material variants (docs/world/environment.md, section 5.2); the flat
 1021  -- texture tiles stay as the fallback when a variant has not shipped
 1026  -- the location the base ground is not, and its share of the blend
 1029  -- the run goes toward -Z: ahead is where the next location's share grows
 1110  -- in a transition the edge mixes both styles, element by element, by the blend
 1207  -- between the last crop row and the windbreak trees of the farm flank
 1251  -- the props and marks go last, into whatever ground the obstacles and flanks left
 1252  -- in a transition both locations dress the chunk, each at its share of the density
 1261  -- the footprints stay with the model (pooled chunks keep their props), for what is
 1262  -- placed after the build: WeaponPickups tests its spots against them
```

## src/server/systems/ChunkOccupancy.luau

```
    3  -- Footprints already taken in the chunk being built, so props do not spawn inside
    4  -- each other. Chunk building is synchronous, so one module-level list is enough:
    5  -- ChunkFactory.build resets it, then every placement either claims a circle or skips.
    6  -- Coordinates are chunk-local x/z; radii are the prop's ground footprint, not its
    7  -- canopy (a tree's crown may overlap a car, its trunk may not).
   12  -- the claims of every built chunk, keyed by the chunk model (weak: a destroyed chunk
   13  -- takes its list with it; a pooled one keeps it, its props stay where they were), so
   14  -- things placed after the build (WeaponPickups) can avoid what the query cannot see
   36  -- Takes the circle when it is free. Returns whether it was taken.
   45  -- Records a footprint without checking (for things placed by construction, such as
   46  -- a lamp row or a building slot, that later random props must avoid).
   51  -- Reserves a rectangle as a row of circles along its long axis.
   71  -- Keeps a copy of the current claims under `key` (the chunk model) for isFreeFor.
   84  -- Whether the circle is free of the claims remembered under `key` (true when nothing
   85  -- was remembered: a chunk built before this existed).
   94  -- Tries a few random spots from `sample` and claims the first free one.
```

## src/server/systems/ChunkPools.luau

```
    3  -- Built chunks waiting to be placed (wiki: Map Segments), kept in ServerStorage so they
    4  -- never replicate until the spawner moves them into Workspace:
    5  --   pools: plain chunks per location (no blend), reused as the run passes them;
    6  --   transitions: the blended first chunks of a map, built ahead for each fork option
    7  --   under the key "<from>|<to>|<k>".
    8  -- ChunkSpawner takes from both; MapPreload fills them over several frames and frees
    9  -- what the run has left behind.
   55  -- Destroys a location's pooled chunks (the run has left every map that uses it).
   88  -- Drops every pre-built transition chunk into `toLocation` from `fromLocation` (the
   89  -- option the vote did not choose, or all of them with nil).
  107  -- Pooled chunk counts per location and the transition count, for the Studio line.
```

## src/server/systems/ChunkSpawner.luau

```
   30  -- Workspace attributes for the clients (wiki: Map Segments): the map at the lead
   31  -- runner, and the map boundary being crossed (the zone's ends in run distance; each
   32  -- client works out its own alpha from where it is, LightingDirector and MapAmbience)
   39  -- set by ForkService when a vote closes; the spawner reports how long the boundary
   40  -- chunk took to be placed after it (Studio measurement of the vote lead)
   58  -- What a chunk is built from: the location, and the blend into another one.
   63  -- a map's first chunks blend from the previous map's last sub-location
   73  -- inside a map, the last TRANSITION_CHUNKS of a sub-location blend into the next one
   96  -- MapPreload built the chosen option's transition chunks while the map ran
  114  -- the station first, so the chunk's pickups keep clear of it
  156  -- the map at the lead, and the boundary zone ahead or under it once its map is known
  212  -- A run from the lobby's map choice (an id or "Random"); the seed draws the route.
  245  -- Studio only: presets whose fog would let a chunk be seen spawning
```

## src/server/systems/DeathService.luau

```
   40  -- The results: the run balance (kill pay and distance pay, already multiplied as it was
   41  -- earned) is banked here and the goal bonus added; a Continue starts a fresh balance,
   42  -- so what was earned before the death is never lost, and neither the distance already
   43  -- paid nor a goal bonus already paid is paid a second time.
```

## src/server/systems/DevBench.luau

```
   18  -- Iteration harness. Everything here is gated on RunService:IsStudio(), so none of it
   19  -- can reach a published server. Its whole purpose is to make one weapon change cost a
   20  -- single Play click instead of a scripted walk to the helicopter and a squad launch.
   50  -- through the cabin like a squad launch (DevConfig.QUICK_LAUNCH), or straight in;
   51  -- always straight in for the test yard, the cabin has nothing to test there
   70  -- only from the hub: a character reset in the cabin is not a new launch
   95  -- A dummy is any Model with a Humanoid that is not a player, which is exactly what
   96  -- WeaponService.findZombieModel already accepts, so hit registration and gore both
   97  -- work without the bench knowing anything about them.
  207  -- Server-side command surface. The Studio command bar runs in a separate Lua VM from
  208  -- the game scripts, so module state is not shared and calling DevBench directly from
  209  -- there does nothing useful; a BindableEvent is the one channel that does reach us.
  237  -- WeaponService refuses to equip a weapon the profile does not own, so the
  238  -- bench grants it first rather than putting a bypass into the live path.
```

## src/server/systems/DistanceTracker.luau

```
   27  -- the health seen last frame and the distance at the last drop of it, for the
   28  -- CleanDistance goal metric (the best clean stretch so far: the current stretch is
   29  -- the studs since the last hit, MissionGoals keeps the longest)
   58  -- Studio only: DevConfig.FREEZE_RUN, or the DevFreezeRun workspace attribute set from the
   59  -- server command bar while testing (the client's freeze debug command cannot reach here).
  168  -- the distance pay goes into the run balance next to the kill pay
  175  -- a drop in health is a hit: the current clean stretch starts again from here;
  176  -- the goal keeps the best stretch so far (MissionGoals takes the max)
```

## src/server/systems/FlowService.luau

```
   36  -- seated in the helicopter: no walking off, no jumping out of the seat
   75  -- a character reset in the cabin stays in the cabin: IntermissionService seats it
   76  -- again on its own CharacterAdded
```

## src/server/systems/ForkService.luau

```
    3  -- Route forks: every map ends in a fork between two of its neighbours (wiki: Map
    4  -- Segments). Builds the centre divider and signs before the map boundary, closes the
    5  -- vote when the lead runner crosses the vote line (ForkConfig.VOTE_LEAD before the
    6  -- boundary), and hands the choice to RoutePlan and MapPreload. The vote is physical:
    7  -- each living runner counts for the side of the divider they are on. In Studio the
    8  -- lead at the vote and the time until the boundary chunk is placed are kept as
    9  -- Workspace attributes (ForkResolvedLead, ForkPlacedAfter) for measuring the lead.
   10  -- See wiki/project-zprun/Route Forks.md.
   49  -- lateral > 0 is the runner's right (+X when running towards -Z)
   80  -- Keep scaled text off the board edges; without it the descenders were clipped.
  101  -- Jersey barriers down the centre line, with small gaps so it reads as a road
  102  -- divider and a runner who strays onto it is nudged rather than walled.
  111  -- Sign gantry at the divider start, facing the runners.
  120  -- Runners face RUN_DIRECTION, which is the part's look vector, so they see the Back face.
```

## src/server/systems/IntermissionService.luau

```
    3  -- The helicopter intermission (docs/gameplay/heli-intermission.md), between the squad's
    4  -- launch countdown (SquadService) and the run (MissionService.startSquad):
    5  --
    6  --   Cabin  the squad sits in a helicopter cabin far off the map. Ready check: the run
    7  --          goes when everyone still here is ready, or after READY_TIMEOUT for whoever
    8  --          is here. Loadout and perk swaps are open (LoadoutWindow, the "Cabin" panel
    9  --          of ShopService); a member may leave back to the hub.
   10  --   Crash  the crash cinematic. The server only waits CRASH_LENGTH (the short,
   11  --          skippable version when every member has run before); the camera, light and
   12  --          sound are the client's. Nothing can be changed and nobody can leave.
   13  --   Wake   MissionService.startSquad spawns whoever is still here at the wreck and
   14  --          each gets GraceUntil (server time): ZombieAI neither chases nor hurts them
   15  --          until it passes, and the client shows "RUN".
   16  --
   17  -- One intermission at a time (one run at a time); SquadService refuses a launch while
   18  -- one is busy. The rules are IntermissionMath (pure, tests/intermission).
   75  -- The wreck: an offset from the run's start, in its frame.
  107  -- the seated eye for IntermissionCamera, looking along the seat at the open door
  130  -- the hub's dusk lighting leaves the olive cabin near black: a dim warm dome light
  131  -- over the troop seats and the green of the instruments in the cockpit
  143  -- no shadows: the seats and crates would black out the floor under them
  243  -- Keeps a member in their seat: after a character reset, and when the seat lets go
  244  -- (a jump), seated again on the next frame.
  269  -- Takes a player out of the intermission's state (attributes, seat, watches).
  290  -- A member out of the intermission: they left the game, or chose to leave the cabin
  291  -- (sent back to the hub). The rest carry on; an empty cabin ends it.
  331  -- The wake-up: whoever is still here spawns at the wreck with the grace window.
  354  -- the run did not take them (dead, or a run already going): back home
  397  -- Called by SquadService at the end of the launch countdown in place of
  398  -- MissionService.startSquad. False when another intermission is going or nobody
  399  -- could board.
  475  -- The squad leave button: out of the cabin back to the hub, during the ready check only.
  487  -- the same remote the hangar's squad panel uses; SquadService ignores a player who
  488  -- is no longer in a hangar squad
```

## src/server/systems/LoadoutWindow.luau

```
    3  -- When a player may change what they take into a run (the loadout slots and the
    4  -- equipped perks): in the hub, and in the helicopter cabin during the ready check
    5  -- (docs/gameplay/heli-intermission.md). Never during the crash beat and never as a
    6  -- run participant. Reads the attributes the server itself sets (FlowPhase from
    7  -- FlowService, IntermissionStage from IntermissionService), so a client cannot open it.
   13  -- In the cabin, during the ready check.
```

## src/server/systems/MapPreload.luau

```
    3  -- Prepares the next map while the squad runs the current one (wiki: Map Segments).
    4  -- When a map becomes current (the lead runner enters it), for both fork options at its
    5  -- end:
    6  --   - warms each sub-location's chunk pool to MapsConfig.POOL_WARM_CHUNKS;
    7  --   - builds the map transition's blended chunks (the old map's last sub-location into
    8  --     the option's first one, MAP_TRANSITION_CHUNKS of them), so the vote's choice is
    9  --     placed the moment it closes;
   10  --   - tells the clients to preload the options' meshes and textures (the MapPreload
   11  --     Workspace attribute, MapPreloader on the client);
   12  -- and frees the pools of maps two steps behind. The work runs in a queue under a
   13  -- per-frame budget (MapsConfig.WARM_BUDGET_MS, at least one chunk a frame), into
   14  -- ServerStorage (ChunkPools), so nothing replicates until it is placed. In Studio the
   15  -- time to warm both options is printed and kept as MapWarmSeconds (the measurement
   16  -- behind MapsConfig.preloadSeconds).
   37  -- transition jobs: the blend's target, its index and the option it serves
   51  -- the slowest single build of the current warm-up, ms: at least one chunk is built per
   52  -- frame, so this, not WARM_BUDGET_MS, is the real worst frame
  102  -- the transition chunks first (the vote waits on them), then the pools
  147  -- the run is over: nothing stays warm in ServerStorage between runs
  167  -- The vote chose `choice`: the other option's queued work and pre-built transition
  168  -- chunks go (unless both options start in the same sub-location).
  175  -- locations still needed: the chosen map's and the current map's
  201  -- the option not taken: its warmed pools go now (it never joins the history)
```

## src/server/systems/MissionGoals.luau

```
   16  -- the goals whose bonus a results screen has already paid this run
   19  -- The run HUD reads the progress from one attribute (docs/gameplay/goals-hud-and-ladder.md);
   20  -- reports come every frame for the distance, so the string is written at most every
   21  -- PUBLISH_INTERVAL and only when a whole unit changed.
   24  -- the distances are shown in steps of 5 studs, the counts whole
   94  -- Pays the bonus of every completed goal not paid yet this run and marks them paid, so
   95  -- the death after a Continue pays only the goals completed since.
```

## src/server/systems/MissionService.luau

```
   43  -- The client owns its character, and a teleport could come back: measured 2026-10-12 on
   44  -- relaunched runs, the server put the character at the wreck and 0.3 s later the
   45  -- client's own simulation, freshly given the character back as it left the cabin seat,
   46  -- returned it to the cabin, 8000 studs off (the run then ended a minute later with
   47  -- nobody on the road). The server holds the character while the new CFrame reaches the
   48  -- client, then hands it back; the checks repeat the teleport if it still came back.
   49  -- A runner covers a few dozen studs in the checked seconds, far inside the tolerance.
   55  -- refused for an anchored assembly (a corpse pose), which stays where it is anyway
  139  -- `spawnCFrame` is where the squad stands up (the wreck after the helicopter
  140  -- intermission); the run's start when omitted.
  196  -- whatever the run still holds is banked (a death has banked its share already);
  197  -- the perks chosen for this run are spent with it
  204  -- the goals go with the run on a quit too (DeathService ends them on a death)
  220  -- the profile's session ends synchronously on PlayerRemoving and on BindToClose, so
  221  -- the run is settled (banked, perks cleared) before it, while the data is still there
```

## src/server/systems/PerkService.luau

```
    3  -- Perks on the server (docs/economy/run-economy-and-perks.md): the levels a player has
    4  -- bought, the slots they own and the perks they equipped for the next run, all in the
    5  -- profile; the Perk Lab catalog and purchases go through ShopService's remotes with
    6  -- the vendor id "PerkLab". Slot 1 is free, slots 2 and 3 and every level cost Credits
    7  -- through ProfileManager.spendCredits, never Robux. The equipped set is validated
    8  -- against the slots and levels owned and cleared when the run ends; nothing reads the
    9  -- effects yet.
   43  -- Drops anything the profile no longer supports (a corrupted or older profile).
   55  -- The equip toggle row of a perk with a level (kind PerkEquip, price 0).
   74  -- The Perk Lab catalog: the slots first, then every perk twice, its level purchase
   75  -- (kind Perk) and its equip toggle (kind PerkEquip).
  126  -- Only the equip rows, for the cabin's loadout panel (no purchases there).
  171  -- Equips or unequips a perk for the next run, within the slots owned.
  177  -- only in the hub and in the cabin's ready check (LoadoutWindow)
  201  -- The perks riding along on this run, in slot order (validated).
  211  -- The run is over: the choice is lost with it, the levels and slots stay.
```

## src/server/systems/PrebuiltMaps.luau

```
    3  -- Places the prebuilt maps (docs/environment/prebuilt-maps.md): every enabled entry in
    4  -- PrebuiltMapsConfig.maps reads its generated layout module (src/server/prebuilt/<map>.luau,
    5  -- server only,
    6  -- from tools/city_import/split_scene.py), loads each cell's Model asset
    7  -- (AssetIds.model.maps.<map>.<cell>) through InsertService and puts its meshes where the
    8  -- layout says, under Workspace.PrebuiltMaps/<map>/<cell>. One Model per cell, streamed
    9  -- atomically, so a cell arrives or leaves as a whole. Collision follows the layout's hint
   10  -- (none, box, hull). In Studio each cell prints a budget line like the chunk reports and
   11  -- keeps it as the BudgetLine attribute. A missing layout, id or mesh is a warning, never
   12  -- an error: the rest of the map still builds.
   69  -- The collision the hint asks for. A Box or Hull fidelity can only come from a fresh
   70  -- mesh build (CollisionFidelity is not writable at run time), so the part takes the
   71  -- geometry of a MeshPart built with it; the part keeps its size and SurfaceAppearance.
  106  -- One cell; runs inside a worker's pcall, so an error here only loses this cell.
  173  -- a fixed pool of workers takes the cells in order; each cell runs in pcall, so a
  174  -- failure never holds a slot or stops the others
```

## src/server/systems/ProfileManager.luau

```
   25  -- perks (PerkService): levels bought, slots owned (1 is free), the perks equipped
   26  -- for the next run in slot order
   50  -- Slot 1 primary, slot 2 sidearm; the 1 and 2 keys read these directly.
   70  -- run synchronously before a profile's session ends (the player leaving, the server
   71  -- closing), while the data can still be written: the run is settled here
   98  -- Everyone starts with a primary as well as a sidearm, so existing profiles get
   99  -- the rifle and a second slot rather than being stuck on the pistol alone.
  109  -- the perk layer: one free slot, nothing bought, nothing equipped
  157  -- Registers a callback that runs before EndSession() for a player leaving and for every
  158  -- profile on BindToClose, synchronously and in order, so credits banked in it land in the
  159  -- profile. A callback that errors is reported and never keeps the session from ending.
```

## src/server/systems/RoutePlan.luau

```
    3  -- The run's route as a chain of maps (wiki: Map Segments). Each map is planned whole
    4  -- when it begins: its length in chunks from a drawn duration and the speed expected
    5  -- there (MapMath.lengthChunks, never under the floor), filled with its sub-locations
    6  -- in turn. Its end is a fork between two enabled neighbours, chosen when the map
    7  -- begins so both can be prepared while the squad runs it (MapPreload); the fork
    8  -- carries each option's first sub-location so their transition chunks can be built
    9  -- ahead. Nothing is planned past an open fork: the spawner holds at the boundary.
   22  -- map ids; options[1] is the left side of the divider, options[2] the right
   24  -- each option's first sub-location, drawn when the fork is planned
   35  -- the first entry of a map after a boundary: its first MAP_TRANSITION_CHUNKS blend
   36  -- from prevLocationId
   39  -- set on the placeholder entry that stands for the next map until the vote closes;
   40  -- its locationId and mapId are the first option's until then
   48  -- seconds into the run the map is expected to start and its drawn duration
  101  -- Plans a whole map from `startIndex`: length, sub-locations, and the fork at its end
  102  -- (a placeholder entry, provisional on the first option).
  125  -- the whole transition stays inside the first sub-location
  129  -- never leave a sliver shorter than a location's minimum at the map's end
  159  -- no two enabled neighbours (a config error MapMath.check reports): extendPlan runs
  160  -- the same map again rather than stop
  172  -- nothing is planned past a fork until the vote closes (resolveFork)
  175  -- the same map again (it has no fork): no map transition, the sub-location blend
  176  -- inside the map covers the seam
  182  -- Plans the route far enough ahead that forks are known before their divider has to
  183  -- be built.
  188  -- The first fork not yet decided, with its boundary distance.
  199  -- The chunk index the spawner must not reach while a fork is open: the boundary
  200  -- itself. Everything before it belongs to the current map.
  206  -- The vote closed: the placeholder becomes the chosen map, planned whole from the
  207  -- boundary with its pre-drawn first sub-location.
  237  -- The map run that contains a chunk index (the last planned one past the plan).
  248  -- The map run before `run`, if any.
  254  -- The fork placeholder at the end of `run`, while the vote is open.
  265  -- Maps run so far, in order, as ids (MapPreload frees pools two steps behind).
  295  -- The boundary distance of a map run and the end of its transition zone.
  316  -- A run from the lobby's map choice (Random or an id); the seed draws everything.
```

## src/server/systems/RunEconomy.luau

```
    3  -- The per-run credit balance of each participant, separate from the profile balance
    4  -- (docs/economy/run-economy-and-perks.md). Kills pay into it the moment they happen
    5  -- (WeaponService), the distance pay DistanceTracker always made is folded into the
    6  -- same balance, and the one number is replicated as the RunCredits player attribute.
    7  -- The balance is banked into the profile by whoever ends the run (DeathService on the
    8  -- results screen, MissionService when a participant leaves alive): nothing earned is
    9  -- ever lost, whether the run ends in a death, a Continue or a walk back to the hub.
   25  -- distance pay already banked this run: a Continue keeps the distance, so the pay
   26  -- for it is owed only once
   53  -- A kill by `player`: pays the zombie's base, the headshot and the streak bonus, all
   54  -- scaled by the difficulty multiplier, into the run balance at once.
   68  -- The distance pay for the furthest point reached, less what a bank earlier in the run
   69  -- already paid for it (the distance survives a Continue, its pay does not repeat).
  100  -- Spends run credits (a supply drop): false, and nothing changes, when the balance
  101  -- does not cover it. The distance half spent counts as banked distance pay.
  117  -- Takes the balance out of the run: returns what the caller pays into the profile and
  118  -- leaves the run at zero, so a Continue earns afresh and a second bank pays nothing.
  131  -- The run is over: what is still unbanked is returned for the caller to pay, and the
  132  -- state and the attribute go.
```

## src/server/systems/RunPromptGuard.luau

```
    3  -- The server's own check behind every mid-run ProximityPrompt (weapon pickups, the
    4  -- upgrade station): the trigger came from a living participant of the active run, in
    5  -- the Mission phase, whose root stands within reach of the prompt's anchor. The prompt
    6  -- itself only shows within its MaxActivationDistance; the reach is a little more, for
    7  -- the latency of a running player.
```

## src/server/systems/Sandbox.luau

```
    3  -- Studio test yard (DevConfig.SANDBOX). Instead of the run, the player walks a flat
    4  -- yard well away from the road with the weapons live, laid out as stations:
    5  --   * spawn: key board; idle zombies of every skin at 25 and 60 studs (respawning a few
    6  --     seconds after each death); G sends a chasing wave
    7  --   * west: target dummies at 10/25/50/100 studs and a row of material walls to shoot
    8  --     (impacts, casings, ricochet sounds); the first-person weapon gallery beyond it
    9  --     (client, SandboxWeaponGallery): every pack clip on its own rig, seen from the side
   10  --   * east: surface strips for footstep and casing sounds; the zombie clip gallery
   11  --     (SandboxGallery): every skin x every clip, walkers on scrolling treadmills
   12  --   * the sound lane (far east): speakers at 25/50/100/200/400 studs and one behind a
   13  --     wall, played in turn by the client (B)
   14  --   * north: every world prop at its real size next to a 1.8 m mannequin, then a wall of
   15  --     every surface MaterialVariant and decal
   16  --   * a closed room for the interior acoustics
   17  -- Keys (client SandboxInput): G wave, H reset, J calm, T back to start, V third person,
   18  -- Z slow motion (1, 1/4, 1/10), B sound lane.
   19  --
   20  -- It rides on the normal mission: DevBench's QUICK_RUN starts a solo run, this module
   21  -- moves the character into the yard, and two workspace attributes switch the run's
   22  -- systems over: SandboxActive (ZombieAI stops its own spawning; the stuck check is off
   23  -- through DevFreezeRun) and SandboxAggro (ZombieAI's chase switch in the yard).
   24  --
   25  -- The yard and the normal run swap while playing (Studio only): the workspace attribute
   26  -- DevMode holds "Yard" or "Run" (DevConfig.SANDBOX.enabled picks the first one) and
   27  -- DevFreezeRun follows it. The client's dev button (SandboxInput) sends "mode"; a run in
   28  -- progress is stopped, and DevBench's quick run launches the next one in the new mode.
   53  -- the yard floor: x from -360 to +360, z from +60 to -400 around the origin
   64  -- the player spawns here facing -Z (the run direction), with everything laid out ahead
  105  -- One strip per footstep/casing material, walked or shot over to hear each surface.
  116  -- Walls to shoot at, one per impact material.
  128  -- 28 x 28 x 12 concrete room with a doorway facing the spawn
  138  -- front wall in two halves around a 6-stud doorway
  143  -- WeaponSfx reads this attribute for the interior gun tail
  156  -- a speaker inside for the sound lane (B plays it last)
  163  -- A 1.8 m figure (6.4 studs at 1 stud = 0.28 m) for judging prop scale.
  177  -- Every world mesh at its in-game size, largest last, each with a mannequin beside it.
  194  -- props modelled in metres go in at their real size; the older meshes have no
  195  -- real size, so they use the sizes the chunk builders give them
  222  -- Every surface MaterialVariant as a standing tile and a floor patch, then the decals.
  236  -- white parts: a MaterialVariant's colour map is tinted by the part colour
  244  -- decals on concrete panels
  257  -- the front face points -Z: turn the panel so its decal faces the yard (+Z)
  264  -- A standing board with the yard's keys, readable from the spawn.
  306  -- Walls to shoot beside the target range.
  319  -- The sound lane: speakers at fixed distances from a listening pad, and a second lane
  320  -- with a thick wall in front of its speaker, for distance and occlusion.
  336  -- B brings the player here first (SandboxWeaponGallery.playSoundLane)
  342  -- behind a wall: same 50 studs, a concrete wall 10 studs in front of the speaker
  357  -- low walls so zombies and casings stay in
  362  -- surface strips beside the spawn
  374  -- the client builds the weapon gallery here (SandboxWeaponGallery)
  381  -- one of each skin at 25 and 60 studs, facing the spawn
  471  -- after MissionService has placed the character at the run start
  499  -- a run in progress restarts in the new mode: stop sends the player to the hub and
  500  -- DevBench's quick run launches again from there (straight in for the yard, through
  501  -- the cabin for the run when DevConfig.QUICK_LAUNCH asks for it). In the cabin the
  502  -- launch already under way simply lands in the new mode.
  515  -- the client builds its galleries around this point
```

## src/server/systems/SandboxBiomeStrip.luau

```
    3  -- Test yard station for the environment pass: one pure chunk per biome, side by side
    4  -- south of the yard floor, built with the wiki's measurement seed so the counter lines
    5  -- are comparable. Fixed screenshot cameras per biome (docs/world/environment.md,
    6  -- section 6) are selected from Studio by setting the Workspace attribute
    7  -- BiomeStripShot to "<Biome>/<Shot>" (for example "City/A"); the station then writes
    8  -- DevCameraCFrame, which CameraController honours, and DevLightingPreset, which
    9  -- LightingDirector honours. An empty string gives both back.
   26  -- relative to the chunk centre (floor top at y = 0.5)
   33  -- south of the yard floor, which ends at z = -400 from the origin
   36  -- the wiki's measurement setup (Performance.md): seed 1234, obstacle count 3
  109  -- Camera and preset for a shot of a biome, or nil for an unknown pair.
  143  -- built the first time the yard opens (Play may start in the run, DevMode)
```

## src/server/systems/SandboxGallery.luau

```
    3  -- Studio test yard (Sandbox): the zombie clip gallery. Every skin gets a row with one
    4  -- standing model per clip, each looping its clip in place so it can be judged from the
    5  -- side. Walk and run clips have their root travel removed (tools/zombie_pack), so each
    6  -- walker stands on a strip whose texture the client scrolls at the clip's measured
    7  -- ground speed (SandboxInput): feet that stay planted on the moving ground mean the
    8  -- speed data, and so the in-game playback rate, is right. One-shots (attack, hit,
    9  -- scream, deaths) hold their last frame for a moment and start again. Bullets pass
   10  -- through the gallery (no queryable parts), so the range next to it is safe to use.
   31  -- clip slots in display order (AssetIds.animation.zombie_sf.<rig>.<slot>, and the "_ue"
   32  -- slots from AssetIds.animation.zombie_fab.<rig>, the retargeted Fab UEFN pack)
   65  -- which ZombiesConfig entry builds each skin (the config only sets health and speeds)
   72  -- a one-shot's last frame is held this long before it starts again
   74  -- one frame short of the end: a non-looped track that reaches its end stops, and the
   75  -- rig would snap to its bind pose before the next play
  102  -- Ground strip under a walking model; the client scrolls its texture along +X's
  103  -- opposite (the model faces +X, so the ground moves toward its back).
  120  -- stripes make the motion easy to read at any distance
  180  -- short range: from in front of one row the labels of the rows behind stay hidden
  184  -- Holds each one-shot on its last frame for HOLD seconds, then restarts it.
```

## src/server/systems/SandboxMapStrip.luau

```
    3  -- Test yard station for map segments (wiki: Map Segments): every map transition the
    4  -- fork graph allows, one row each, laid out as a run would build it: a plain chunk of
    5  -- the old map's sub-location, the MAP_TRANSITION_CHUNKS blended chunks, a plain chunk of
    6  -- the new map's. Built on demand (it is large): set the Workspace attribute
    7  -- MapStripPair to "City>Forest" for one row or "all" for every pair; MapStripShot set to
    8  -- a pair puts the Studio camera at the row's start looking down it (DevCameraCFrame) in
    9  -- the old map's lighting (DevLightingPreset). An empty string gives both back.
   27  -- south of the biome strip (SandboxBiomeStrip sits at z = -560 from the yard origin)
   29  -- one row's width: lane, barriers and both aprons, with a gap
   40  -- Every ordered transition the fork graph allows between enabled maps.
  141  -- Camera and preset for a row's shot, or nil for an unknown pair.
  156  -- Studio only; the yard is a run-time switch (DevMode), so the strip is wired whether
  157  -- or not Play starts in it, and builds a pair only when asked
```

## src/server/systems/SceneParts.luau

```
    3  -- Parts from data: the PartSpec shape of PickupScenesConfig and UpgradeStationConfig
    4  -- (primitives with sizes, offsets and colours as plain numbers, or a WorldMeshConfig
    5  -- group with primitive fallbacks) turned into anchored parts in a scene's frame. Shared
    6  -- by WeaponPickups and UpgradeStations.
```

## src/server/systems/ShopService.luau

```
   19  -- the cabin's loadout panel (docs/gameplay/heli-intermission.md); not a vendor room
   71  -- the ladder made visible: the damage now, the next level's price and gain
  191  -- the helicopter cabin during the ready check: swaps only, nothing to buy
```

## src/server/systems/SkinService.luau

```
   62  -- the soldier body is meshes, not catalog parts: ApplyDescription would swap it back
   63  -- to blocks, so the skin tints the uniform instead
```

## src/server/systems/SoldierCharacter.luau

```
    3  -- Makes the soldier the character every player spawns as. Once the soldier meshes have
    4  -- loaded, a fresh R15 model is converted by SoldierBody and parented to StarterPlayer as
    5  -- StarterCharacter; players who spawned on the block body before that (the first seconds
    6  -- after the server starts) are respawned unless they are in a run. While the mesh ids
    7  -- are not filled in (SoldierRigConfig.ready is false) nothing happens and everyone keeps
    8  -- the block body.
   23  -- A character that spawned on the block body while the soldier was still loading (its
   24  -- CharacterAdded can land after the build's own sweep) is respawned once the
   25  -- StarterCharacter exists; a run is never interrupted for it.
   49  -- the engine adds the default Animate to every character; a second copy would fight it
```

## src/server/systems/SquadService.luau

```
  193  -- another squad's intermission or run took the helicopter first: the squad stays
  194  -- as it was and the leader can launch again later
  203  -- the helicopter cabin first; IntermissionService starts the run after the ready
  204  -- check and the crash (docs/gameplay/heli-intermission.md). Only once it took the
  205  -- squad is the hangar squad cleared; a refusal (no cabin, nobody alive to board)
  206  -- leaves the squad as it was, like the busy case above
```

## src/server/systems/SurfaceTemplates.luau

```
    3  -- SurfaceAppearance templates for meshes loaded from Model assets
    4  -- (ReplicatedStorage.ViewmodelSurfaces and .ZombieSurfaces, generated by
    5  -- scripts/sync_configs.py from the texture/viewmodel/ and texture/zombie/ manifest rows).
    6  -- A mesh the importer left without a SurfaceAppearance gets the template named for the
    7  -- material in its name; with `replace` the template also takes the place of the
    8  -- importer's own, which Roblox builds from a metallicRoughness texture without the
    9  -- material's metallicFactor (a skin over a white B channel at factor 0 comes in as metal).
   15  -- `surfaces` maps a material name found in the mesh's name to a template name; the
   16  -- longest match wins ("Hand_Mesh_Glove_D_0" is Glove_D). True when a template went on.
   40  -- Every MeshPart under `root`; returns how many took a template.
```

## src/server/systems/UpgradeStations.luau

```
    3  -- The upgrade station (docs/gameplay/upgrade-station.md): a field armourer's bench
    4  -- placed along the run by the world generator (ChunkSpawner), one per
    5  -- UpgradeStationConfig.SPACING_STUDS of road in the station biomes, its spot from a
    6  -- Random seeded with the run seed and the chunk index. Holding its prompt upgrades the
    7  -- carried weapon one level of the WeaponsConfig ladder for run credits through
    8  -- RunEconomy; the level lives in WeaponService's run state and the profile is never
    9  -- written. The station is tagged like a pickup scene so the client's pooled Highlight
   10  -- outlines it; its bench lamp is its own light for when the pool is spent.
   36  -- the station's own chunk step, off the pickups' 7919, so no station stream ever
   37  -- equals a pickup plan's or a drop roll's for any chunk
   40  -- an ammo crate's footprint, for the spot check
   46  -- the scene origin on the floor, the footprint's centre
  157  -- The same spot check the pickups make: the chunk's remembered footprints, the chunk's
  158  -- ammo crates (spawned first, not queryable) by radius, then the overlap query. The
  159  -- station is placed before the pickups of its chunk; they avoid it through
  160  -- footprintsForChunk and Workspace.Pickups.
  184  -- Called by ChunkSpawner once the chunk stands at its pivot, before the pickups.
  212  -- The stations standing in a chunk (the lamp, the mat and the vise are not queryable),
  213  -- for the pickups' spot check.
  233  -- Shares the pickups' folder so a pickup spot check sees the station.
```

## src/server/systems/VendorRooms.luau

```
  491  -- A flask on a stand: the lab's own prop, a glass cylinder with a lit fill.
  509  -- The Perk Lab: steel benches with lit flasks along the back, a whiteboard of the six
  510  -- perks on one side, a rack of sealed cases on the other. Same shell and prompt as
  511  -- every other room; the catalog is PerkService's.
  524  -- six benches along the back: flasks on the first four, the two monitors on the
  525  -- last two (a flask and a monitor never share a bench)
```

## src/server/systems/ViewmodelPacks.luau

```
    3  -- Loads the first-person pack rigs (skinned arms + weapon, uploaded as Model assets by
    4  -- scripts/upload_assets.py) into ReplicatedStorage.ViewModelPacks, one Model per class,
    5  -- for the client's PackViewmodel to clone. Skinned MeshParts and their Bone tree cannot
    6  -- be written by Rojo, so they come in through InsertService at server start.
   18  -- The importer leaves RenderFidelity on Automatic, which drops a mesh to a coarser level of
   19  -- detail by distance; the arms fill the screen, so every mesh is reapplied at full detail.
   20  -- The skin weights travel with the mesh data, the part keeps its size, textures and bones.
```

## src/server/systems/WeaponPickups.luau

```
    3  -- Diegetic weapon pickups (docs/gameplay/weapon-pickups.md): the staged scenes of
    4  -- PickupScenesConfig built along the corridor per chunk by the world generator
    5  -- (ChunkSpawner), placed by the pure PickupPlanner from a Random seeded with the run
    6  -- seed and the chunk index, so a run puts the same scenes in the same places for every
    7  -- player. Each scene carries a ProximityPrompt held 0.3 s; the server validates the
    8  -- run phase, the distance and that the scene is still there, then hands the weapon to
    9  -- WeaponService.pickUp. The crashed supply drop is the reworked mystery box: red smoke,
   10  -- opened for run credits through RunEconomy, the weapon rolled from the weighted table.
   11  -- Highlights are the client's (WeaponPickupClient), pooled below Roblox's limit.
   40  -- the box the occupancy check sweeps above the floor (stains and markings sit below it)
   43  -- per-chunk seed spacing, so neighbouring chunks never share a stream; the plan, the
   44  -- drop roll and the mesh picks each get their own Random off it, so the plan's stream
   45  -- never shifts with what happened to load
   49  -- an ammo crate's footprint, for the spot check
   67  -- The gun itself, as a sub-model the pickup removes when taken.
  143  -- The crashed drop: the crate on its side in a scrape of earth, the parachute silk
  144  -- collapsed beside it, the red smoke canister on top.
  169  -- The server's own check of who is asking and from where.
  214  -- the roll is seeded per drop; the weapon already in hand is rerolled once, so the
  215  -- credits buy a gun and not a refill
  272  -- the canister lies on its side; the smoke rises from its position, unrolled
  279  -- Whether the spot is free: of the chunk's footprints remembered at its build (the
  280  -- query below cannot see non-queryable dressing such as corn walls, dry grass and
  281  -- undergrowth), of any queryable part of the chunk or of another pickup inside a box
  282  -- of the footprint above the floor, of the pickups and upgrade stations already
  283  -- standing (their small parts are not queryable either) and of the chunk's ammo crates.
  302  -- the station's lamp, mat and vise are not queryable either
  322  -- Called by ChunkSpawner once the chunk stands at its pivot.
  359  -- Returns the folder, shared with the upgrade stations so both spot checks see both.
```

## src/server/systems/WeaponService.luau

```
   18  -- A reload in progress, on the WeaponsConfig timeline the client predicts with. It is
   19  -- advanced every Heartbeat and again right before a shot is judged, so a shot that
   20  -- arrives just after the ammo-add sees the rounds.
   27  -- magazine: the mag seats here; after it a shot may cut the tail
   30  -- shell: planned, counted so far, most that will go in (lowered by a cancel)
   43  -- no shots before this (the draw after an equip)
   47  -- The client starts its reload one trip earlier than the server and its shots arrive
   48  -- one trip later, so both sides line up on the same timeline; this only absorbs jitter.
   60  -- the loadout for the current run once a pickup replaced a slot: the profile's loadout
   61  -- with the found weapons in, gone when the run ends (WeaponPickups, MissionService)
   63  -- the levels bought at an upgrade station this run, per weapon id: read over the
   64  -- profile's level for damage, gone with the run (UpgradeStations, MissionService)
   69  -- The weapon's level for this run: the level bought at a station this run, else the
   70  -- profile's (1 for a weapon the profile does not own, such as a found one).
  108  -- Applies whatever the reload has reached by `now`: the magazine's ammo-add, each shell
  109  -- at its add point, and the end. Attributes are synced on every count change so the
  110  -- HUD ticks per shell.
  111  -- A full magazine and reserve, as a hub refill and a found gun give.
  159  -- The loadout the 1 and 2 keys read: the run's once a pickup changed it, else the
  160  -- profile's.
  193  -- ALL_WEAPONS_UNLOCKED is the temporary test flag: any weapon, owned or not
  211  -- a reload in progress is dropped with the old state: before its ammo-add the old
  212  -- count stands, shells already in stay in
  223  -- the client runs its reload prediction with this, so it has to be there before the
  224  -- first reload request
  264  -- Applies one ray's hit. Returns what it did to a zombie (the damage dealt, a head hit,
  265  -- a kill) for the shooter's hit marker, or nil when it hurt none; the damage rules are
  266  -- unchanged, the outcome is read from them after the fact.
  292  -- the level bought at a station this run counts over the profile's
  305  -- the kill pays into the run balance at once (RunEconomy)
  347  -- the magazine is seated: firing cuts the rest of the reload
  372  -- only world geometry may block the head-to-camera gap: a zombie hit box pressed
  373  -- against the player (a grab, a lunge) must not swallow a point-blank shot
  414  -- what each pellet did to a zombie, summed into the shooter's hit confirmation
  436  -- the sixth value is the server's own confirmation of this shot (damage dealt, a
  437  -- head hit, a kill) for the shooter's hit marker, nil when it hurt no zombie; the
  438  -- client never sends any of it
  490  -- Fire pressed during a reload. Shells: the one in the hand is still counted, the loop
  491  -- stops, and the job lives on through the fast exit (plus the pump from empty), which
  492  -- is what keeps fire blocked for that window. Magazines: before ammo-add the old count
  493  -- stands, after it the tail is cut; either way the reload ends now.
  542  -- A weapon found in the world (WeaponPickups): it takes the slot of the weapon in hand
  543  -- for the rest of the run and is equipped the way a loadout equip is, full. Finding a
  544  -- weapon already carried refills that one instead. False for an unknown id.
  557  -- a found gun is full: the ammo it had the last time it was carried is forgotten
  571  -- Republishes the level attribute for the weapon in hand: after the profile loads (the
  572  -- default Pistol may already be current, so no equip runs) and after a Gunsmith upgrade.
  589  -- A level bought at an upgrade station (UpgradeStations has taken the credits): it
  590  -- holds for the rest of the run, over the profile's level, and is never written back.
  604  -- The run is over: the found weapons and the bought levels go with it and the
  605  -- profile's loadout is back in the slots; a hand still holding a found weapon draws
  606  -- the profile's primary.
```

## src/server/systems/WorldFlanks.luau

```
    3  -- Fills the space beside the run corridor, per biome.
    4  --
    5  -- The corridor is only +-PLAYABLE_HALF_WIDTH wide, but the floor and aprons run out to
    6  -- about +-230 studs and all of it is in view. Before this layer everything past the
    7  -- corridor edge was bare floor with a few isolated props, so every biome read as a
    8  -- strip of clutter on an empty slab floating in fog. The flanks are built in depth
    9  -- bands: a detailed near band that frames the corridor, a cheaper middle band, and a
   10  -- silhouette band at the back that reads through fog and closes the horizon.
   11  --
   12  -- Everything here is decoration: no collision, no queries, no touch events, and
   13  -- shadows only on the near band. Runners are clamped to the corridor, so none of it
   14  -- is reachable. Coordinates are chunk-local (the chunk pivot is its centre).
   26  -- material variants per biome (docs/world/environment.md, section 5.2)
   79  -- Walks z across the chunk in steps, calling place(zStart, span) for each slot.
   88  -- gaps may be negative (overlapping masses), but z must always advance
   93  ---------------------------------------------------------------------------------------
   94  -- City
  108  -- A city block facade seen from the corridor: body, a floor ledge per storey, a dark
  109  -- window strip per storey with the odd lit one, a shopfront band and a cornice. The
  110  -- facade faces the corridor (towards x = 0), which is the -sign direction.
  119  -- peeling plaster over brick; the map carries the colour, so the tint goes neutral
  130  -- middle band: a few lit windows so the depth reads at night, nothing else
  139  -- shopfront: darker base band with glazing
  147  -- storeys
  156  -- piers break the strip into windows
  163  -- rooftop clutter
  174  -- A generated building mesh filling one street-wall slot. The mesh's street face is
  175  -- +Z; turning it by -sign * 90 degrees points that face at the corridor. Its width
  176  -- (native x) is fitted to the slot, which sets the height within the band's clamp.
  190  -- sidewalk and kerb along the corridor edge
  199  -- near block: continuous street wall behind the corridor-edge row
  207  -- middle block: taller, no shadows; building meshes on most slots, facades on the
  208  -- rest so the skyline keeps its variety
  217  -- skyline silhouettes at the back
  226  ---------------------------------------------------------------------------------------
  227  -- Forest
  246  -- two stacked, narrowing ellipsoids read as a spruce silhouette
  260  -- dark forest floor so the gaps between trunks are not bright grass
  266  -- near band: individual trees, jittered grid, shadows on; mesh trees stop at the
  267  -- triangle budget's line and the primitive tree carries on behind them
  280  -- undergrowth along the corridor edge
  291  -- back: a continuous canopy wall with a few trunks under it
  304  ---------------------------------------------------------------------------------------
  305  -- Wasteland
  319  -- A gutted building seen from the road. With a building mesh loaded it is that mesh
  320  -- sunk into the ground and leaning away from the road, two wall stubs and rubble at its
  321  -- street foot; otherwise an L of broken walls with a jagged top. Returns the depth the
  322  -- ruin takes outwards from x.
  335  -- the tilt is about the road axis, so the top leans outwards
  372  -- near: ruins, wrecks and dead trees
  408  -- rubble berms: long low slopes that break up the flat ground
  419  -- back: mesas and a broken skyline
  433  ---------------------------------------------------------------------------------------
  434  -- Farmland and corn
  436  -- `gap` is {xMin, xMax, zMin, zMax} (x measured outwards from the corridor): rows
  437  -- crossing it are split so nothing grows through a building.
  492  -- keep the whole barn inside this chunk
  508  -- windbreak tree line between the field and the hills
  520  -- One row of corn meshes along z at distance x, rotated so the row runs with the road.
  544  -- the corn mass continues as one block to hide the row ends
  549  ---------------------------------------------------------------------------------------
  559  -- Both flanks of a chunk. In a transition (`otherKind`, `alpha`) each side switches to
  560  -- the other style on its own: the left at alpha 0.4, the right at 0.6, so the change is
  561  -- staggered across the boundary instead of both walls swapping in one chunk.
```

## src/server/systems/WorldMeshes.luau

```
    3  -- Mesh templates for world dressing. At server start every entry in WorldMeshConfig
    4  -- is turned into a MeshPart template with AssetService:CreateMeshPartAsync (MeshId is
    5  -- not writable from scripts, so templates are the only way to spawn meshes at run
    6  -- time). Builders call place() and get nil back while a mesh is missing or still
    7  -- loading; they then fall back to their primitive shapes, so a failed load never
    8  -- leaves a hole in the world.
   21  -- per-axis multipliers applied after the height scale (x and z are the footprint)
   23  -- studs to sink the mesh into the ground so it never floats on its lowest vertex
   28  -- studs per mesh unit at the entry's real size (WorldMeshConfig studsPerUnit)
   64  -- Loads every template, all requests in parallel. Blocks until every request has
   65  -- finished, so call it from a spawned thread at server start (init does), or
   66  -- directly in an Edit preview.
   97  -- Waits for loadAll to finish, at most `timeout` seconds. The first run after a
   98  -- server start calls this so its opening chunks are not built from primitives.
  110  -- One loaded member of a group, or nil when none of them loaded.
  128  -- Places a mesh standing on `base` (its position is the ground point under the
  129  -- mesh centre, its rotation is the mesh yaw), scaled uniformly so it is `height`
  130  -- studs tall. Returns nil when the template is not available.
  156  -- Places a mesh scaled so its footprint length (z) is `length` studs, keeping its
  157  -- proportions. Used for vehicles, whose size is set by the lane layout.
  166  -- Places a mesh at its real size (mesh units times the entry's studsPerUnit), for the
  167  -- props modelled in metres. `scale` multiplies that (default 1).
  176  -- Real size in studs of a loaded mesh (see placeNatural).
  182  -- Picks from a group and places in one call.
```

## src/server/systems/ZombieAI.luau

```
   51  -- skinned rigs: top speed the skin's clips can show, the swing holding it, and
   52  -- whether it has screamed at a player yet
   66  -- a zombie this close to a player swings at them (the damage itself is the Hitbox touch)
   68  -- speed kept while a swing plays, as a share of the chase speed
  155  -- A player waking at the wreck (GraceUntil, server time, set by IntermissionService)
  156  -- is neither chased nor hurt until the window closes.
  223  -- skinned rigs fall through their death clip, so the body stays upright and still
  275  -- a forced skin skips the pool, whose models carry whatever skin they were built with
  321  -- skinned: only the rig's meshes stay, the hit boxes go
  336  -- the death clip lays the body down from standing
  591  -- Studio test yard: aggro is a switch (Sandbox), not a distance run
 1187  -- the Studio test yard places its own zombies
 1230  -- Studio test yard only: one zombie of a given config and skin at a position.
```

## src/server/systems/ZombieAnimator.luau

```
   19  -- a looped idle at Core priority that never stops: whenever the other tracks are
   20  -- fading (every idle/walk/run switch) the rig falls back to this instead of its rest
   21  -- pose, which is a T-pose
   25  -- skinned rigs (ZombieSkins): every walk and run clip with its ground speed, the one
   26  -- playing, and the one-shots
   41  -- The Dormant rise and the Feeding pose take the Mixamo clips once they are uploaded
   42  -- (docs/animation/third-person-locomotion.md) and the Quaternius clips until then.
   59  -- Ground speed each clip covers at playback speed 1 on the walker2 rig (FULL_SCALE 0.92),
   60  -- measured 2026-09-28 from the planted foot's travel over 60 samples of the cycle: walk
   61  -- 2.56 studs/s on the leading foot (the shuffle drags the other), run about 4.3. The old
   62  -- references (6 and 12) played the walk at half speed and the run at a third of what the
   63  -- body covered, so the feet skated. Very fast zombies still outrun the clip at the cap;
   64  -- past about 2.2x the cycle reads as frantic rather than fast.
   73  -- Skinned rigs pick, from all their walk and run clips, the one whose ground speed is
   74  -- closest (as a ratio) to the zombie's speed and play it at speed / groundSpeed, so the
   75  -- feet stay planted. A new clip has to win by MOVE_SWITCH_MARGIN (log ratio) so the
   76  -- cycle does not flap between two clips while the AI eases the speed.
   81  -- a swing never holds the zombie longer than this (Hazmat's is a 3.5 s clip)
   84  -- the Hazmat scream when it first notices a player, sped up so it does not stand for 5 s
   86  -- a flinch stops the legs, so only zombies standing or shuffling get one
   89  -- a death clip is frozen this long before its end (a non-looped track that reaches its
   90  -- end stops and the rig would stand back up)
  127  -- Length is 0 until the clip has loaded.
  190  -- Each zombie keeps one of its skin's walks and one of its runs, picked at random, so a
  191  -- crowd of one skin does not move in step: with every clip loaded the speed fit always
  192  -- chose the same one (walk_a and walk_b share a ground speed, walk_b never played).
  268  -- How wrong a clip looks at `speed`: mostly the skating left once its playback rate is
  269  -- clamped, a little for how far from its natural rate it plays.
  409  -- Swing at a player in reach. Returns how long the swing lasts (0 when none started).
  433  -- Flinch from a bullet; `speed` is how fast the zombie is moving.
  442  -- Scream on first noticing a player. Returns how long it lasts (0 when there is none).
  453  -- Play one of the skin's death clips and hold its last frame. Returns false when the rig
  454  -- has none (the body then falls as before).
  473  -- Lay a corpse down in the last frame of one of its skin's death clips. The corpse has no
  474  -- Humanoid, so an AnimationController drives it; call once the model is in the world.
  547  -- Recycling: stop everything and free the tracks, since the next spawn from the pool
  548  -- loads a fresh set on the same Animator.
```

## src/server/systems/ZombieFactory.luau

```
   16  -- Two rigs. The full R15 walker (15 textured MeshParts cut from a generated character,
   17  -- see tools/zombie_rig) is used when every template in ReplicatedStorage.ZombieMeshes.Walker2
   18  -- carries a real mesh id; otherwise the old reduced 7-part rig is built. The choice is
   19  -- made once at require time, because ROOT_HEIGHT and HIP_HEIGHT depend on it.
   39  -- Roblox's glTF importer turns every uploaded mesh 180 degrees about Y (x and z negated,
   40  -- measured on the walker2 and arm meshes 2026-09-28), so the zombie faced backwards with
   41  -- its eyes on the back of its head. Each mesh part is turned back about its own centre,
   42  -- and the joints are written so their frames stay axis-aligned in character space.
   47  -- Rojo-mounted MeshParts render at the mesh's native size; load every zombie mesh
   48  -- through MeshTemplates now so spawned zombies get correctly scaled parts.
   53  -- The first zombies of a run can spawn before the loads finish, and a part cloned then
   54  -- keeps the wrong size for its whole life. The first build waits for them instead.
   71  -- The zombie clips (tools/animation_pipeline, Quaternius sources) are authored against a
   72  -- T-pose: their shoulder rotations take a horizontal arm down to the sides. walker2's arms
   73  -- are modelled hanging, so those same rotations swung each arm up and across the chest.
   74  -- The arm chain is therefore rest-posed horizontally here, rotated about the shoulder so
   75  -- that shoulder-to-wrist points straight out (-X left, +X right); with no clip playing the
   76  -- zombie stands in a T-pose, with a clip it reads as authored.
  109  -- a point of the arm chain moved into the T-pose (character space, scale 1)
  119  -- rest CFrame (scaled) of a mesh part: glTF flip, plus the T-pose turn for arm parts
  223  -- limbs are what a bullet should hit (Head carries the headshot bonus); only the
  224  -- torso collides, and only against the player (zombies share a no-collide group)
  239  -- joint frames are axis-aligned at the (T-posed) pivot, whatever the parts' rotation
  246  -- a faint glow in the eye sockets keeps the ITD read of eyes in the fog
  260  -- the head part is turned by GLTF_FLIP, so the offset is given in character space
  300  -- Skinned zombie from a Sketchfab rig (ZombieSkins / ZombieRigs). The visual rig hangs
  301  -- off the HumanoidRootPart by a Motor6D named Root and is animated through its Bones.
  302  -- Bullets hit invisible boxes that ZombieHitboxes keeps on the bones (Head, Chest, Hips,
  303  -- limbs); none of them collide, since a bone-driven box that dips below the hip height
  304  -- (a lunge, a stumble) drags the Humanoid over. Blocking the player is left to two static
  305  -- boxes welded to the root above the hip height (UpperTorso, LowerTorso), which the rest of
  306  -- the game already toggles by name. The root keeps the full rig's size and height so
  307  -- ROOT_HEIGHT and HIP_HEIGHT stay valid for every zombie.
  331  -- the root bone stands on the ground in every pack
  407  -- heights as the clips hold the body (the offset only undoes the clips' own shift)
  458  -- `corpse`: the model will be laid down as a corpse, so only skins with a death clip
  460  -- `skinName` forces one skin (the Studio test yard shows each skin side by side)
```

## src/server/systems/ZombieHitboxes.luau

```
    3  -- Hit parts of skinned zombies. A skinned MeshPart is raycast against in its bind pose
    4  -- (a T-pose), so the parts WeaponService and ZombieAI look for (Head, UpperTorso,
    5  -- LowerTorso, limbs) are invisible boxes jointed to the HumanoidRootPart with a Motor6D,
    6  -- and every PreSimulation (after the Animator has posed the bones, before physics moves
    7  -- the assembly) each joint's Transform is set so the box sits on its bone as the clip has
    8  -- posed it. Motor6D.Transform does not replicate, which is what we want: only the
    9  -- server raycasts against these.
   20  -- Zombies further than this from every player keep their boxes where they are: nobody
   21  -- shoots that far through the fog, and reading bone transforms costs.
   27  -- `boxes`: hit part -> (driving bone, box world CFrame at rest). Call while the rig is
   28  -- still in its bind pose (no clip applied), right after building.
   48  -- Stop following (corpses: the model is anchored and posed once).
```

## src/server/systems/ZombieRigs.luau

```
    3  -- Loads the skinned zombie rigs (ZombieSkins) from their Model assets into
    4  -- ServerStorage.ZombieRigs at require time, one template per skin, prepared for
    5  -- ZombieFactory: the part that holds the Bones is renamed "Rig" (the clips address it by
    6  -- that name), the importer's AnimationController and InitialPoses go, every visual part
    7  -- is made non-colliding, non-queryable and massless, and the skin's `surfaces` replace
    8  -- the SurfaceAppearances the importer built wrong (SurfaceTemplates).
   42  -- flatten: every part straight under the model
   93  -- The template for a skin, waiting up to `timeout` seconds while it loads.
```

## src/server/world/ChunkBudgetCounter.luau

```
    3  -- Studio-only cost line per built chunk (parts, estimated triangles, instances, decals,
    4  -- lights, shadow casters against the desktop and mobile budgets), plus the fog check
    5  -- that ties every preset's visibility to the spawn distance. Outside Studio nothing
    6  -- here runs.
   56  -- Prints the chunk's line and stores it on the model; returns it, or nil outside Studio.
   68  -- Warns once about any preset whose fog would show a chunk being spawned.
```

## src/server/world/WorldDecals.luau

```
    3  -- The decal layer of a chunk: marks from DecalsConfig placed as thin cards on the
    4  -- ground, cards in front of road-facing walls, and a tiled Texture on the floor. Ids
    5  -- come from AssetIds.texture.decal; a key that is missing or 0 places nothing.
   58  -- Chunk-local x for a ground zone, either side of the road.
  101  -- A card in front of a thin, axis-aligned wall part, on the face that looks at the road.
  137  -- Wall parts of the chunk that may take a card, in a fixed order so the rng stays in step.
  148  -- Places the biome's marks in the chunk; returns the number placed.
```

## src/server/world/WorldDressing.luau

```
    3  -- Turns DressingPlanner placements into instances in a chunk: the PBR props through
    4  -- WorldMeshes, a primitive stand-in per group when a mesh is not loaded, the burn
    5  -- patches, and the tags the mobile tier and the counter read. Chunk-local coordinates,
    6  -- parented under the chunk model so the props pool with it.
   39  -- SurfaceAppearance tints per biome: the same maps read burnt and dusty in the ruins.
   77  -- A box of the fallback size standing on the ground in the prop's own frame.
  150  -- Sizes of every loaded prop the recipes can ask for, keyed by mesh name.
  186  -- the burn map is the point of the patch; a flat tint would only read as a stain
  219  -- Dresses the chunk for `biome`; returns the number of props placed.
  220  -- `density` (0..1, default 1) scales the clusters and the prop cap: a map transition
  221  -- dresses a chunk with both locations at their shares of the blend.
```

## src/shared/config/AnimationTimings.luau

```
    3  -- Sequence timings live apart from the poses because they get retuned far more often.
    4  -- A step holds until `duration` elapses, easing from the previous step's pose.
    5  -- `phase` names fire a PhaseReached signal the moment the step starts, which is what
    6  -- drives reload audio - a marker in the sequence, never a wall-clock timer.
   13  -- pose used by classes whose library has no `pose` (the rifle has the full magazine
   14  -- change; the other classes reuse their four reload poses)
   28  -- Default blend-in for a sequence that replaces another. A sequence shorter than this
   29  -- must set its own `blendTime`, otherwise the blend is still ramping in while the pose
   30  -- is already easing out and the authored offsets only ever render at a fraction.
   34  -- Draw: up from below, then the class's rack (rifle bolt catch, pistol slide,
   35  -- shotgun pump), with the bolt phases driving the rack audio.
   49  -- Recoil snaps and decays: no blend-in at all, otherwise the kick reads as a nudge.
   61  -- Magazine still has rounds: no chambering pass. Played stretched to the weapon's
   62  -- reloadTime (Viewmodel.playReload), so these durations only set the proportions.
   80  -- magazine ran dry: adds the bolt release at the end
```

## src/shared/config/AnimationsConfig.luau

```
   62  -- Weapon locomotion sets (docs/animation/third-person-locomotion.md): the gaits a
   63  -- character plays while holding a rifle-class or a pistol-class weapon, replacing the
   64  -- generic Run when their clips exist. Gaits are Core like Run so they cross-fade by
   65  -- weight; the reload and the hit are Action one-shots. AnimationController picks the
   66  -- set by the player's weapon class and falls back to Run while a slot is 0.
   77  -- Seated (the helicopter cabin's seats, any Seat): a looped pose played while
   78  -- Humanoid.SeatPart is set, the gait layer paused meanwhile. The default Animate
   79  -- script that used to sit the character is removed (AnimationController), so this is
   80  -- the only sit pose; id 0 until the owner uploads one (animation/player/sit_idle).
  107  -- Clip ids per set, gait first, then the one-shots the set carries.
  125  -- no pistol sprint clip is planned: the run clip speeds up instead
  130  -- ground speed at which the legacy Run clip plays at its recorded rate
  132  -- Ground speed (studs/s) each Mixamo gait clip covers at its recorded rate on the
  133  -- soldier body: the planted foot's speed in the clip (X Bot, In Place), scaled by the
  134  -- soldier's leg length (hips 93.9 cm against the X Bot's 104) at 0.03 studs per cm.
  135  -- Measured 2026-09-30. The game's run speed (24) is a hard run for these clips, so the
  136  -- rifle plays its sprint there and the pistol speeds its run up.
  141  -- a moving character below this speed walks
  143  -- a sideways share of the ground velocity at or beyond this strafes: the run at 24 with
  144  -- a full A/D swerve (about 16 sideways) is 0.55 and keeps the run
  146  -- the gait turns from run to sprint above this speed (with SPRINT_HYSTERESIS either way);
  147  -- the body layer's lowered-gun sprint pose keeps its own ThirdPersonConfig.SPRINT
  204  -- the pistol run covers 13.4 studs/s, so the game's 24 needs 1.8
```

## src/shared/config/ArmRigConfig.luau

```
    3  -- GENERATED by scripts/build_arms.py from assets/viewmodels/arms/rig.json.
    4  -- Do not edit by hand: re-run tools/arms_rig/build.py and this script instead.
    5  --
    6  -- Hand frame: fingers toward -Z, back of the hand +Y, origin on the grip axis.
    7  -- `handCentre` is where the Hand MeshPart centre sits in that frame. `wrist` is the
    8  -- forearm frame (origin at the wrist, forearm running toward +Z) in the hand frame,
    9  -- and `forearmCentre` the Forearm MeshPart centre in the forearm frame.
   10  -- Studs before ViewmodelConfig.SCALE.
   22  -- false until every arm MeshId has been read back into the manifest
```

## src/shared/config/AssetIds.luau

```
    3  -- Generated by scripts/sync_configs.py from assets/manifest.json. Do not edit by hand.
```

## src/shared/config/CreditsConfig.luau

```
    3  -- Generated by scripts/sync_configs.py from assets/manifest.json. Do not edit by hand.
    4  -- The in-game credits (docs/gameplay/credits.md): every CC BY asset, approved or
    5  -- reviewing, grouped by kind, one line per credited work with the manifest keys it
    6  -- covers; then the acknowledgements no licence requires.
  389  -- shown above the list: the licences ask that changes be indicated
```

## src/shared/config/DamageNumberConfig.luau

```
    3  -- Damage numbers (DamageNumbers.luau): pool size, times in seconds (the fade starts at
    4  -- FADE_FROM of the duration), rise and sideways jitter in studs, the BillboardGui size and
    5  -- text sizes in pixels, hidden beyond MAX_DISTANCE studs.
```

## src/shared/config/DecalsConfig.luau

```
    3  -- Ground and wall marks per biome. `key` names an entry of AssetIds.texture.decal; a key
    4  -- that is missing or 0 places nothing, so the list can name marks the project does not
    5  -- have yet (docs/world/assets-needed.md). Data only, no engine types.
    6  --
    7  -- Zones: "lane" is the playable band minus a margin, "shoulder" the strip just inside the
    8  -- corridor edge, "edge" the corridor edge row, "wall" a card on a road-facing wall part.
    9  -- "floor" is a tiled Texture on the floor's top face rather than a card.
   15  -- card size in studs: { min, max } for a square card, or { width, depth } when fixed
   20  -- render order between overlapping marks: cracks 1, stains 2, blood 3
   22  -- tile size for floor textures
   28  -- A card sits this far above the ground, plus LAYER_STEP per layer, so layers never fight.
   31  -- Wall cards stand this far in front of the wall face.
   33  -- Cards beyond this many per chunk are detail the mobile tier removes.
   35  -- Lane cards keep off the road centre line by this much, and off the chunk ends.
   57  -- Wall parts, by name, that may carry a wall card. All are thin along their local x and
   58  -- face the road.
   71  -- The asset id behind a key from a lookup table; anything missing or non-positive is 0.
```

## src/shared/config/DevConfig.luau

```
    3  -- Development switches. Every one of these is gated on RunService:IsStudio() at the
    4  -- point of use, so a published server can never come up in a debug state no matter
    5  -- what is committed here.
    9  -- Skips hub, helicopter and squad lobby: spawning drops you straight into a solo run.
   10  -- This is what makes a weapon iteration cost one Play click instead of twenty seconds
   11  -- of scripted boarding.
   18  -- the start map, as the lobby's map row would pick it: a MapsConfig id or "Random";
   19  -- nil takes MapsConfig.DEFAULT_ID
   23  -- How the quick launch starts the run: through the helicopter intermission (cabin,
   24  -- ready check, crash beat, wake at the wreck) like a squad launch, or straight into
   25  -- the run as before when false.
   30  -- The content warning is a one-time player-facing gate; re-reading it every Play is
   31  -- pure friction and it also blocks input until dismissed.
   34  -- Hold the run still. The forward sprint is what you want when tuning feel, and what
   35  -- gets in the way when tuning how something looks: the corridor drags you off the thing
   36  -- you are inspecting within a second. With this on you spawn into the run with the
   37  -- weapon live, but stand still and steer with the normal WASD controls, so you can walk
   38  -- around a prop and look at it. The freeze/unfreeze debug commands still override it at
   39  -- runtime.
   42  -- Watch the third-person body instead of playing through the viewmodel: hands the
   43  -- camera to Roblox's stock orbit controller, keeps the character visible and frees
   44  -- the zoom clamp, so animation clips can be reviewed on the real character during a
   45  -- run. Wins over FREEZE_RUN's camera handling; movement freezing still applies.
   48  -- A row of stationary dummies at fixed distances, for time-to-kill and spread checks
   49  -- that a moving zombie cannot give you. Distances are in studs from the player spawn.
   53  -- Lateral fan, so the row does not occlude itself. Kept small: at 12 studs the
   54  -- nearest dummy sat off the left edge of the screen.
   60  -- Test yard instead of the run: you spawn on foot (the run frozen, stock first-person
   61  -- camera, weapons live, keys 1-4 swap guns) in a flat yard away from the road with a
   62  -- row of each zombie skin standing idle and respawning, target dummies, surface strips
   63  -- for footstep and casing sounds, an interior room for the indoor acoustics, and a row
   64  -- of props. Sandbox keys: G sends a chasing wave, H resets the yard, J calms everyone,
   65  -- T teleports back to the start, V third person, Z slow motion, B plays the sound lane.
   66  -- The yard also has both clip galleries (every zombie and weapon clip, seen from the
   67  -- side), material walls, a texture wall and a sound lane (see Sandbox.luau).
   68  -- `enabled` is the mode Play starts in; while playing, the dev button at the top centre
   69  -- (or key M) swaps between the yard and the normal run (Sandbox.luau, DevMode).
```

## src/shared/config/DressingConfig.luau

```
    3  -- Road dressing rules: which prop clusters each biome gets, where they may stand, which
    4  -- material variant every surface takes, and the per-chunk budgets. Data only, with no
    5  -- engine types, so DressingPlanner and ChunkBudget and their tests load it under the
    6  -- standalone Luau CLI. Groups are WorldMeshConfig group names; zones and bands are the
    7  -- ones in docs/world/environment.md. Distances are studs, chunk-local; x is measured
    8  -- outwards from the road centre and applies to both sides.
   16  -- "line": the members follow each other along the road; default: around the anchor
   18  -- how far from the cluster anchor a scattered member may land along the road
   20  -- yaw range in radians; default anywhere
   22  -- material variant painted on the ground under the prop (burn marks)
   35  -- clutter the mobile tier removes
   41  -- "alternate": clusters take turns between the two sides; "one": a single side
   44  -- cap on props per chunk
   46  -- zone overrides where a biome's flank already fills the default band
   55  -- variant for a share of the near-band facade blocks, and that share
   82  -- Nothing taller than this casts a shadow, whatever its zone says.
   85  -- Clearance added around every footprint when it is claimed.
   88  -- Cluster centres: at least this far apart along the road on one side, and across sides.
   91  -- Two consecutive gaps on one side must differ by at least this much.
   93  -- Clusters keep this far from the chunk ends, whose ground the neighbour chunk dresses.
   96  -- Members beyond this many in a cluster are detail.
  106  -- Footprints (x, z, height in studs) used when a prop mesh is not loaded and the
  107  -- primitive stands in for it. Real sizes come from WorldMeshes.naturalSize.
  202  -- between the rail fence at 34.5 and the crop rows from 42
  210  -- the corn mesh rows start at 37, so the edge is the last free strip before them
  221  -- Ground top per biome as a function of the distance from the centre line: the City
  222  -- sidewalk is a 0.4 slab on the floor, the forest floor part is 0.2 on top of it.
  263  -- Ground patch under burned props: a flat part painted with the variant.
  271  -- Triangles per mesh, from the `triangles` field of assets/manifest.json. Props uploaded
  272  -- as Models carry no count there and take TRIANGLES_DEFAULT until one is read in Studio.
  294  -- Triangles per primitive shape, the engine's own meshes.
  302  -- Mesh trees stay inside this distance in the Forest near band; the rest are primitive.
  305  -- Share of City middle-band slots that take a building mesh; the rest stay facades.
```

## src/shared/config/ForkConfig.luau

```
    7  -- Route forks: every map ends in a fork between two of its neighbours, and the squad
    8  -- votes with their feet (wiki: Route Forks, Map Segments).
    9  --
   10  -- Streaming sets the geometry. Before map segments the last TRANSITION_CHUNKS of a
   11  -- biome blended into the next, so the vote had to close a full spawn distance before
   12  -- that blend: SPAWN_AHEAD_DISTANCE + 2 chunks = 1024 studs before the boundary. Now the
   13  -- map transition starts at the boundary (the new map's first chunks blend from the old
   14  -- one) and both options' first chunks are built while the squad runs the map, so
   15  -- the spawner only holds at the boundary and places the chosen option's chunks the
   16  -- moment the vote closes. The vote can then close as late as keeps the held boundary
   17  -- out of sight while those chunks are placed and reach the clients: the widest fog
   18  -- plus a chunk plus SETTLE_SECONDS at the top speed.
   24  -- seconds for the held chunks to be placed and stream to the clients, measured in
   25  -- Studio (wiki: Map Segments) with margin
   28  -- How far before the map boundary the vote closes: 420 + 128 + 60 * 1.5 = 638 studs
   29  -- with today's presets (was 1024).
   37  -- Length of the centre divider that splits the corridor into the two choices, ending
   38  -- at the vote line. At BASE_RUN_SPEED 24 this is 16 s, at MAX_RUN_SPEED 60 about 6 s.
   41  -- No divider starts before this distance into a map: the squad settles into each map
   42  -- before the next choice (part of every map's minimum length, MapMath.floorLength).
   45  -- Signs and HUD: options[1] is the left side of the divider, options[2] the right,
   46  -- as seen by a runner facing RUN_DIRECTION.
```

## src/shared/config/HitMarkerConfig.luau

```
    3  -- Hit and kill markers (docs/gameplay/hit-markers.md), after Modern Warfare 2019's hip
    4  -- fire: four short diagonal ticks around the crosshair on the server's confirmation of
    5  -- damage to a zombie by the local shooter, a tint for a headshot, larger red ticks for a
    6  -- kill. Data only, no engine types: the pure HitMarkerMath and its tests read it under
    7  -- the standalone Luau CLI. Colours are {r, g, b}; sizes are pixels at scale 1.
   11  -- How long each variant shows, seconds.
   15  -- A hit's ticks grow a little with the damage the shot dealt: scale 1 at
   16  -- DAMAGE_REFERENCE (a rifle body shot), DAMAGE_SCALE of the relative difference, kept
   17  -- within SCALE_MIN..SCALE_MAX so a shotgun's full pellet sum or a pistol graze stay
   18  -- readable. A kill is always KILL_SCALE.
   25  -- Each marker pops in this much larger and settles to its scale over the first share
   26  -- of its time, holds full, then fades out over the last share.
   31  -- The ticks: distance of each tick's centre from the crosshair along the diagonal,
   32  -- length and thickness.
   43  -- AssetIds.audio.ui keys; 0 (the slots are `needed`) plays nothing.
   48  -- The settings key (SettingsConfig) that turns the markers off.
```

## src/shared/config/IntermissionConfig.luau

```
    3  -- The helicopter intermission (docs/gameplay/heli-intermission.md): between the
    4  -- squad's launch countdown and the run, the squad sits in a helicopter cabin off the
    5  -- map for a ready check, then waits out the crash cinematic, then wakes at the wreck
    6  -- with a grace window. Data only, no engine types: the pure IntermissionMath and its
    7  -- tests read this table under the standalone Luau CLI. Positions are {x, y, z},
    8  -- colours {r, g, b}; the server builds CFrames from them. The cabin is primitives
    9  -- through SceneParts (PartSpec shape), no asset.
   33  -- The ready check: everyone ready, or this many seconds and the run starts for
   34  -- whoever is there.
   37  -- The crash cinematic: the server only waits this long. The first time a squad sees
   38  -- it (any member with no run in the profile) it is the full length and cannot be
   39  -- skipped; a squad of members who have all run before gets the short version, ended
   40  -- early when every member votes to skip.
   46  -- The wake-up: zombies ignore a player whose GraceUntil (server time) is ahead, for
   47  -- this many seconds after the spawn at the wreck; the client shows "RUN" meanwhile.
   50  -- Where the squad wakes: an offset from HangarConfig.RUN_START_CFRAME, in its frame
   51  -- (-z is the run direction), so the wreck stays on the start platform.
   54  -- The cabin, far off the map and high (no chunk, hub or diorama is near it).
   56  -- red cabin light
   58  -- fill lights in the cabin's frame (from the floor's top): warm over the seats, green
   59  -- from the instrument console
   65  -- Remote rate limit per player for the ready and skip toggles.
   68  -- The troop seats along the left wall, facing the open door on the right wall (+x).
   69  -- One per squad member (HangarConfig.SQUAD_CAPACITY is 3).
   75  -- the seat faces this yaw in degrees (-90 looks along +x, at the door)
   77  -- the seated eye, from the seat's centre in the seat's frame, and how far down the
   78  -- view tilts (degrees)
   82  -- Look around during the ready check while the right mouse button is held (the cursor
   83  -- stays free for the panel): degrees from the SeatView frame, yaw either side and
   84  -- pitch down/up, degrees per pixel of mouse travel, and how fast the view eases to
   85  -- where the mouse put it (per second, exponential). The crash beat keeps the fixed view.
   99  -- The cabin in its own frame: origin on the cabin floor's centre, x across (the door
  100  -- at +x), y up, -z toward the cockpit.
  123  -- the cockpit beyond the bulkhead opening
  136  -- The two crew figures, each built into its own Model (Pilot, Copilot) so the crash
  137  -- cinematic can move them; parts in the figure's frame, the figure's origin on its seat.
```

## src/shared/config/LightingConfig.luau

```
    3  -- Lighting presets per place and biome, day and night. LightingDirector lerps between
    4  -- them; PostFx reads the bloom fields. How far each preset lets you see is in
    5  -- VisibilityConfig, checked by FogBudget against the chunk spawn distance.
   25  -- bloom stays inside the wiki rule: intensity at most 0.4, threshold at least 1.2
   38  -- Studio test yard (DevConfig.SANDBOX): clear afternoon light and far fog, so rigs,
   39  -- casings and props can be judged without the mission grading hiding them
  201  -- night fallback for biomes without their own, and the hub at night
  225  -- sodium lamps and burning barrels on a blue-black street
  249  -- mist between the trunks, no lamps, the flashlight does the work
  273  -- clear desert night, moonlit, the furthest sight of the night set
  297  -- one barn lamp per barn, the rest is dark field
  321  -- thick ground mist, the shortest sight in the game
  351  -- The night preset for a biome, or the shared Night when it has none.
```

## src/shared/config/LocationsConfig.luau

```
   73  -- a dead highway: worn asphalt with faded lines (TFZ_RoadWorn) between dirt aprons
```

## src/shared/config/MapsConfig.luau

```
    3  -- Maps (wiki: Map Segments). A run is a chain of maps, each a long stretch built from
    4  -- its own sub-locations (LocationsConfig ids, mixed inside the map for variety). The
    5  -- squad leader picks the start map in the helicopter lobby; every map ends in a fork
    6  -- between two of its neighbours, both prepared while the squad runs the map, and the
    7  -- map boundary blends over MAP_TRANSITION_CHUNKS, lighting and ambience included.
    8  -- Data only, no engine types: MapMath and its tests (tests/world) read it under the
    9  -- standalone Luau CLI.
   14  -- studs per second at the map's start, the peak and the seconds of the ramp between
   15  -- (DistanceTracker's locationTargetSpeed); nil peak is a constant speed
   24  -- listed in the lobby and reachable at forks; content still missing otherwise
   26  -- sub-locations (LocationsConfig ids), drawn in turn, never the same one twice running
   28  -- how long the squad should run it, seconds, drawn per run
   30  -- maps a fork at this map's end may offer; only enabled ones are used
   32  -- LightingConfig preset (its night variant at night)
   34  -- AssetIds.audio.ambience key of the map's ambience bed (silent while its id is 0)
   36  -- seconds the server needs to warm this map's chunk pools (the floor of the map
   37  -- before it); an estimate, measured in Studio (wiki: Map Segments)
   39  -- WorldMeshConfig groups the clients preload while the map is a fork option
   41  -- the run speed expected here; nil uses GameConstants.BASE_RUN_SPEED throughout
   47  -- the lobby's "pick one for me": any enabled map, drawn from the run's seed
   51  -- lobby order; disabled maps are left out of the lobby
   56  -- chunks over which one map blends into the next: the first chunks of the new map,
   57  -- each a step further from the old one (floor, apron, edge props, flanks, dressing)
   60  -- a map is never shorter than SPAWN_AHEAD_DISTANCE + MAX_RUN_SPEED * preloadSeconds of
   61  -- the slower next option * FLOOR_FACTOR (the owner's "speed x build time" rule)
   64  -- chunk pools warmed per sub-location of each fork option, and the frame budget
  118  -- no content yet: kept here so the neighbour graph is planned, never offered
  185  -- A map that can be run: listed and enabled.
  191  -- What the lobby may send: an enabled map or Random.
  196  -- Enabled map ids in lobby order.
```

## src/shared/config/MegascansMaterials.luau

```
    3  -- Generated by scripts/sync_configs.py from assets/manifest.json. Do not edit by hand.
    4  -- Asset ids and settings only: the Fab files themselves are never committed
    5  -- (assets/fab/ is gitignored, the repository is public). MaterialUtil appends these
    6  -- sets to its own. Only sets whose maps all have asset ids are listed; their
    7  -- MaterialVariants are the TFZ_MS_* entries in default.project.json.
    8  -- See docs/environment/megascans.md.
```

## src/shared/config/PerksConfig.luau

```
    3  -- Perks: the per-run layer over the persistent skills (docs/economy/run-economy-and-perks.md).
    4  -- A perk's levels are bought with Credits at the Perk Lab and kept; which perks ride
    5  -- along is chosen before a run and cleared when the run ends. Slot 1 is free, slots 2
    6  -- and 3 are bought with Credits. Credits only, never Robux. Effects are numbers only:
    7  -- nothing reads them yet.
    8  --
    9  -- Four ids overlap the skills (Toughness, Sprinter over Endurance, FastHands, Scavenger);
   10  -- their display names are different so the two layers never read as the same item.
   15  -- a two-letter tag for the HUD badge
   19  -- credits for level 1, 2 and 3
   21  -- the effect key and its value per level; keys are named for the system that will
   22  -- read them (health, movement, weapons, ammo, medic)
   31  -- slot 1 is free; the price of slots 2 and 3
  113  -- Price of the next level, or nil at max.
  121  -- The effect value at a level (0 or below gives nil: the perk does nothing).
  129  -- Price of the next slot after `owned`, or nil when all are owned.
  137  -- Whether `equipped` (perk ids in slot order) fits the slots owned and the levels
  138  -- unlocked: no duplicates, no unknown perk, no perk at level 0, no more than `slots`.
```

## src/shared/config/PickupScenesConfig.luau

```
    3  -- Diegetic weapon pickups (docs/gameplay/weapon-pickups.md): weapons lie in the world
    4  -- as staged scenes placed along the corridor by the world generator, deterministic
    5  -- from the run seed, taken by holding the prompt. Data only, no engine types: the pure
    6  -- planner (src/shared/world/PickupPlanner.luau) and its tests read this table under the
    7  -- standalone Luau CLI, so colours are {r, g, b} and sizes {x, y, z}; the server builder
    8  -- (WeaponPickups) turns them into parts. Scenes are built from primitives and the props
    9  -- already in WorldMeshConfig (police car, sandbags, supply crate): no new asset, no id.
   13  -- One part of a scene, in the scene's own frame (x right, y up, -z toward the road).
   15  -- "box", "cylinder" (axis along x, as Roblox cylinders are), "ball", or "mesh" (a
   16  -- WorldMeshConfig group placed through WorldMeshes with `fallback` when not loaded)
   21  -- degrees
   29  -- mesh: the footprint length along z (placeByLength) or the height
   38  -- the WeaponsConfig id handed over; a disabled scene may name a weapon that does not
   39  -- exist yet (the chainsaw)
   42  -- the prompt's object text
   44  -- biomes (LocationsConfig ids) the scene may appear in; nil means any
   46  -- pick weight among the scenes allowed in a biome
   48  -- ground footprint radius, for the occupancy check against the chunk's props
   50  -- where the weapon prop sits in the scene frame; the prompt and the highlight
   51  -- anchor there
   61  -- The prompt: hold this long, from this far. The server accepts a trigger from a
   62  -- little further than the prompt shows, for the latency of a running player.
   67  -- Highlights: Roblox renders 31 at once, the pool never holds more than this many; the
   68  -- nearest scenes get them and a held one keeps its slot until a new scene is closer by
   69  -- the margin (studs), so two scenes at the same distance never trade the outline.
   76  -- Placement: no scene in the first chunks (the squad starts with its loadout), clear
   77  -- of the chunk ends, on the road shoulder this far inside the playable edge, facing
   78  -- the road with a little yaw jitter. The planner offers this many candidate spots per
   79  -- scene and the server takes the first one free of the chunk's props.
   85  -- the supply drop lands in the middle of the lane, this fraction of the playable half
   86  -- width either side, and never within this many studs along the road of a scene
   90  -- Chance of one scene per chunk, per biome (LocationsConfig ids).
   99  -- The crashed supply drop (the reworked mystery box): red smoke, opened for run
  100  -- credits, the weapon rolled from the weighted table server-side. Green smoke stays
  101  -- the ammo crate's (AmmoCrates).
  129  -- The weapon props by weapon id, in the gun's frame (-z along the barrel, y up).
  163  -- A soldier who did not make it, his carbine beside him. Any biome.
  190  -- A pump shotgun left leaning on a fence post at the field's edge.
  199  -- the fence is centred on the scene origin: posts at x -2.75 and 2.75, the crate
  200  -- past the near post, everything inside this radius
  213  -- A sidearm on the hood of an abandoned police car.
  245  -- An SMG on the sandbags of an abandoned checkpoint.
  276  -- The chainsaw at the sawmill: a config entry only, until a melee system exists.
  298  -- Whether a scene may appear in `biome`.
```

## src/shared/config/PoseLibrary.luau

```
    3  -- Authored viewmodel poses. Each pose is a table of bone name -> CFrame offset that
    4  -- multiplies the bone's rest transform, so an empty table is the neutral pose.
    5  --
    6  -- Bone names come from ViewmodelBuilder: weaponRoot, slide, pump, magazine,
    7  -- handR / handRWrist / handRForearm, handL / handLWrist / handLForearm.
    8  --
    9  -- Every pose here was checked in Studio with screen_capture before being committed;
   10  -- see docs/asset-policy.md.
   26  -- Left hand over the pistol slide, palm down (see pistol rackGrab).
   28  -- Left hand hooking the rifle charging handle (see rifle rackGrab).
   41  -- Kept deliberately small: see the note on ViewmodelConfig.sprint. The player
   42  -- sprints for the entire run, so anything that takes the barrel off the crosshair
   43  -- here is permanent rather than transient.
   55  -- Draw: the pistol comes up canted to the left and the left hand comes over the top,
   56  -- takes the rear of the slide overhand, racks it back and lets it go. Hand offsets are
   57  -- in weapon space, unscaled units of pistol.rig.txt; the hand frame was built with
   58  -- fingers across the slide toward +X and the palm down.
  128  -- Longarms share the pistol layout but need a wider support-hand travel and a bolt
  129  -- instead of a slide; the shotgun overrides the reload with a pump stroke.
  130  -- Left hand on the magazine, in weapon space: turned so the hand's grip axis runs up the
  131  -- magazine (Rx 90), then swung about that axis so the forearm leaves the frame down and
  132  -- back instead of lying across it.
  151  -- Draw: the rifle is pushed out canted to the left, the left hand comes over the top
  152  -- of the upper receiver, hooks the charging handle, pulls it back and lets it go.
  153  -- Hand frame built with the fingers up and across the receiver toward +X.
  169  -- Magazine change with the mesh arms, checked frame by frame in Studio. Hand offsets
  170  -- are in weapon space (ViewmodelBuilder converts them for the mesh hand pivots), in
  171  -- the same unscaled units as assets/viewmodels/rifle.rig.txt: the left hand's rest
  172  -- pivot sits on the handguard axis at (0, 0.15, -0.47), the magazine centre at
  173  -- (0, -0.49, 0.02). The weapon comes up towards the centre and rolls to show the well, the left hand comes off
  174  -- the handguard, takes the magazine, strips it, drops out of frame to the vest,
  175  -- brings a fresh one back, seats it with a push and returns.
  210  -- the heel of the hand pushes the magazine home: the weapon jumps a little
  216  -- empty magazine: the left hand slaps the bolt release on the left of the receiver,
  217  -- just above the magazine well
  261  -- Draw: rack the pump (the box support hand rides on the pump)
  278  -- shotguns cycle by pump rather than a magazine swap
  324  -- The SMG still uses box arms, whose hand offsets are not in weapon space, so it takes
  325  -- the rifle poses without the mesh-hand draw (the Equip sequence falls back to idle).
```

## src/shared/config/PrebuiltMapsConfig.luau

```
    3  -- Prebuilt maps: large static scenes split into cells by tools/city_import/split_scene.py,
    4  -- uploaded as Model assets through the manifest and placed by PrebuiltMaps under
    5  -- Workspace.PrebuiltMaps/<map> (docs/environment/prebuilt-maps.md). Data only, no engine
    6  -- types, so PrebuiltMapMath and its tests can load it.
    9  -- the layout module src/server/prebuilt/<map>.luau and the manifest's model/maps/<map>/
   12  -- where the scene's origin goes, in studs, and a turn about Y in degrees
   29  -- No map is listed until one has been split and uploaded. Example:
   30  --   { map = "city", enabled = true, origin = { 0, 0, -4000 }, yaw = 0 },
   33  -- workers loading cells (InsertService:LoadAsset plus the collision refits), each taking
   34  -- the next cell when it is done
   37  -- split_scene.py writes the geometry turned 180 degrees about Y because the Roblox glTF
   38  -- importer turns meshes that way; if a Studio check shows the cells' meshes facing
   39  -- backwards, the importer changed and this is set to 180
   42  -- parts smaller than this (largest side, studs) cast no shadow
   45  -- per cell, desktop and mobile, as in the chunk reports (DressingConfig.budgets)
   51  -- the whole map, for the summary line
```

## src/shared/config/RunEconomyConfig.luau

```
    3  -- The kill economy of a run (docs/economy/run-economy-and-perks.md): what a kill pays
    4  -- into the run balance, the headshot and streak bonuses, and the distance rate the
    5  -- balance also carries. Numbers only, no engine types, so RunEconomyMath and its tests
    6  -- load it under the standalone Luau CLI. Every pay is multiplied by the difficulty
    7  -- reward multiplier (RewardMultiplier) at the moment it is earned.
   11  -- credits per kill by zombie id (ZombiesConfig); an unknown id takes KILL_PAY_DEFAULT
   18  -- flat credits added to a kill whose killing shot hit the head
   21  -- a kill within STREAK_WINDOW seconds of the last one extends the streak; every kill in
   22  -- a streak adds STREAK_STEP per streak position beyond the first, capped at STREAK_CAP
   27  -- one credit per this many studs of distance, the rate DistanceTracker always paid
```

## src/shared/config/SettingsConfig.luau

```
    3  -- "credits" is read-only: the panel shows CreditsConfig there, nothing is stored
```

## src/shared/config/SfxConfig.luau

```
    7  -- Webbing and sling rattle on every footstep: the recorded rattles (freesound CC0, see
    8  -- LICENSES) when they are live, else the older Kenney impacts.
   96  -- Spatial audio engine (src/client/audio, docs/audio/spatial-audio.md). Off means every
   97  -- consumer takes the Sound-based path it had before the engine existed.
   99  -- Roblox's built-in acoustic simulation (client beta) instead of the engine's own
  100  -- occlusion rays and bus reverb; only read while SPATIAL_AUDIO is on.
  102  -- Weapon sounds through the engine (docs/audio/weapons-integration.md): the shooter's
  103  -- gun on the OwnGunshot class with the reflection fan, teammates' shots on
  104  -- GunshotRemote, casings, the range gong and bullet impacts on their classes. Off keeps
  105  -- WeaponSfx on its Sound pools and Weapons SoundGroup, for comparison in Studio. Only
  106  -- read while SPATIAL_AUDIO is on.
```

## src/shared/config/SoldierRigConfig.luau

```
    3  -- GENERATED by scripts/build_soldier_rig.py from assets/character/soldier/source/rig.json.
    4  -- Do not edit by hand: re-run tools/character_rig/soldier.py and the script instead.
    5  --
    6  -- Character space: feet at y = 0, facing -Z. `centre` is where each MeshPart sits in
    7  -- the rest pose (arms hanging straight down, like Roblox's own R15), `pivot` is the
    8  -- joint position; every joint frame is axis-aligned so stock R15 clips play
    9  -- unchanged. `grips` is each fist's centre relative to its hand part, where a weapon
   10  -- grip sits. `ready` is false until every part has a mesh id.
```

## src/shared/config/SpatialAudioConfig.luau

```
    3  -- Data for the spatial audio engine (src/client/audio): one entry per sound class,
    4  -- per acoustic environment and per material family, plus the platform budgets. The
    5  -- reasoning and the sources behind every number are in docs/audio/spatial-audio.md.
    6  -- Distances are studs (1 stud = 0.28 m), gains are dB unless named "gain", times are
    7  -- seconds, frequencies are hertz.
   14  -- weapons | sfx | voices | ambience | music | ui
   16  -- audible range; 0 means a 2D sound with no propagation
   18  -- full-volume radius, the "size" of the source
   21  -- air absorption strength, 1 is the exaggerated ISO curve, 0 none
   23  -- scales the material loss when the path is blocked, 0 ignores occlusion
   26  -- 0..100, higher survives a voice steal
   29  -- speed-of-sound start delay for one-shots
   31  -- feeds the sidechain that ducks ambience and music
   35  -- distance layers a sound may supply (close, mid, far) and where each one plays
   48  -- slapback echo; 0 delay disables it
   55  -- transmission loss through the part, negative dB
   57  -- low-pass cutoff of what gets through
   59  -- 0..1 share of energy a reflection off it keeps
   70  -- class voice limits are multiplied by this (minimum 2)
   81  -- one-shots nearer than this start at once (raise it if near shots read as lag)
   95  -- seconds for a cleared path to open and a blocked one to close
   98  -- sideways offset of the second ray on gunshots and explosions
  100  -- the loss of a partially blocked path (one of two rays) as a share of full
  105  -- a source inside an interior heard from outside, or the reverse
  109  -- reverb and echo parameter glide when the listener changes environment
  117  -- taps closer than this fuse with the direct sound (precedence effect)
  164  -- the shooter's own gun: close layers 2D, the environment layer through reflections
  165  -- (played by WeaponSfx once it moves onto the engine, docs/audio/weapons-integration.md)
  177  -- fire, sirens, radio, rotor: range comes from the call
  179  -- roomtone, walla, wind, heartbeat, breath
  181  -- gear rattle, landings, cloth: on the listener, no propagation
  187  -- SfxPlayer.play2D / play3D wrappers for call sites not moved yet
  204  -- environments whose reverb already carries the early reflections
```

## src/shared/config/StanceConfig.luau

```
    3  -- Weapon stances, manual lean and the magazine check for the first-person rig
    4  -- (wiki: Stances), in the tactical-shooter style: a key cycles the carry between mid
    5  -- (the normal hip pose), high ready (muzzle up) and low ready (muzzle down); a shot from
    6  -- high or low ready first brings the gun up, over a time per class; Q and E lean the
    7  -- camera with a counter-pose on the viewmodel and a lean of the third-person upper body;
    8  -- holding R checks the magazine instead of reloading. All visual: the server's rules are
    9  -- unchanged. Data only, no engine types: the pure StanceMath and its tests read it under
   10  -- the standalone Luau CLI.
   11  --
   12  -- Poses are in the pack viewmodel's hold space (the channel WallPullback uses): x right,
   13  -- y up, +z toward the chest, in the pack rigs' small units (ViewmodelPackConfig.RIG_SCALE);
   14  -- angles in degrees, with the signs of CFrame.Angles: pitch > 0 lifts the muzzle,
   15  -- yaw > 0 turns it left, roll > 0 cants the top to the left.
   19  -- Keys (Enum.KeyCode item names). Q was the loadout quick swap; it moved to the mouse
   20  -- wheel. E is also the ProximityPrompt key: while a prompt is on screen E does not lean.
   28  -- The stance key steps through this order (from mid: high ready, then low ready).
   31  -- The poses, full strength. Mid is the class's own hold, so it is all zero.
   38  -- Easing between stances, per second (exponential, frame-rate independent, as
   39  -- WallPullback): into a stance a little slower than out of it.
   43  -- A shot from high or low ready raises the gun first, over this many seconds from the
   44  -- full stance (less when the stance is only partly in); the shot leaves when it is up.
   53  -- After the last shot the gun stays up this long, then eases back to the chosen stance.
   56  -- A stance weight at or under this counts as up (the gun may fire).
   59  -- Manual lean. "hold": lean while the key is down; "toggle": a press leans, the same key
   60  -- again comes back, the other key leans the other way.
   63  -- the camera: sideways offset (studs), a small drop, and the roll toward the lean
   67  -- easing rates, per second
   70  -- the viewmodel rolls with the camera; this share of the roll is taken back so the
   71  -- gun cants less than the view, and it shifts a little toward the lean
   74  -- the camera stops short of a wall at the side: a sphere of this radius is cast from
   75  -- the eye along the lean, and the offset keeps this margin from what it hits
   78  -- the third-person upper body: degrees of waist roll at a full lean
   82  -- Hold R. Released before holdTime: a reload (on release). Held past it: the magazine
   83  -- check, for at least minShow seconds; the count shows once the tilt is nearly in.
   89  -- the count appears at this share of the pose, disappears under it
   91  -- a shot during the check brings the gun back first, over this many seconds
   93  -- "exact": "27 / 30"; "estimate": Full, Almost full, About half, Almost empty, Empty
   95  -- hide the bottom-right ammo counter outside a check (magazine-check-only ammo)
   97  -- the weapon tipped toward the camera: magazine side turned to the eye
```

## src/shared/config/ThirdPersonConfig.luau

```
    3  -- Data for the third-person body layer (src/client/body, docs/animation/third-person-body.md):
    4  -- where each weapon class sits in the hands, where the support hand goes for every
    5  -- gesture, how the aim spreads over the joints, the recoil scale, the sprint pose, the
    6  -- wire rate and the LOD bands. Frames are in the weapon's grip space unless named
    7  -- otherwise: x right, y up, -z forward along the barrel, 1 stud = 0.28 m.
   10  -- the grip part's CFrame in UpperTorso space with the aim level
   12  -- support (left) hand position in grip space for the two-handed hold, and its roll
   15  -- where the support hand goes for the magazine, the chambering action and the pump
   16  -- (grip space); a class without a socket leaves it nil
   21  -- "bolt": the support hand racks at the charge socket; "slide": the weapon itself is
   22  -- pulled back (a pistol slide release, thumb work)
   24  -- studs the charge or pump stroke travels back along +z
   27  -- offset multiplied onto the hold in a sprint and at the start of the draw
   30  -- recoil scale on WeaponsConfig recoilKick (studs) and recoilSnap (degrees)
   33  -- seconds of the chambering action inside an empty reload, and of the pump stroke
   48  -- Needs Motor6D joints: the layer writes Motor6D.Transform, and the avatar joint upgrade
   49  -- builds AnimationConstraint joints instead, so the place keeps
   50  -- StarterPlayer.AvatarJointUpgrade = Disabled (default.project.json; Rojo cannot set it
   51  -- on a live sync, so it is also set by hand in Studio). BodyController, the aim relay and
   52  -- the yard station all stay idle while this is false.
   55  -- The chest turns by these shares of the aim; the head and the gun end on the whole aim,
   56  -- measured from the root's upright frame (BodyMath.spreadAim)
   62  -- share of the locomotion clip's chest lean taken out while a gun is held (the run
   63  -- clip leans the chest about 37 degrees forward), and of the head's lean always
   66  -- time constants of the approach: remote characters smooth the 20 Hz packets, the
   67  -- local character in the yard follows its own camera
   70  -- the arms pitch about this point of the UpperTorso (between the shoulders)
   80  -- the relay drops packets closer together than this from one player
   85  -- WeaponsConfig.recoilSnap is a unitless kick; this many degrees per unit
   87  -- share of the snap that pitches the waist
  103  -- IK weight while the draw starts (the gun is still coming up)
  105  -- share of the straight arm's length a hand target is kept within (the elbow keeps a
  106  -- little bend), how far the gun may come back along its axis for the right hand, and
  107  -- the gap the support hand keeps ahead of the right one when it slides back
  114  -- the support hand's belt position in UpperTorso space (magazines and shells come
  115  -- from here)
  117  -- seconds after a shot before the pump stroke starts
  119  -- return to the grip after a cancelled reload
  132  -- Tuned in the yard's body gallery against the default R15 body (arms about 1.8 studs
  133  -- from the shoulder joint, chest 2 wide). The WorldWeapon geometry (WorldWeaponModel
  134  -- LENGTHS): grip 0.7 tall at the origin with the right hand 0.3 behind it, receiver 0.56
  135  -- above it running along z (1.6 long on the rifle and the shotgun, 1.2 on the SMG, 0.9
  136  -- on the pistol), barrel beyond, magazine under the receiver's middle, handguard just
  137  -- past the receiver, stock from 0.24 behind the grip. The holds keep the gun in front of
  138  -- the chest's middle, where the left arm can still reach along it; a support socket past
  139  -- the reach slides back along the gun (BodyRig), so a longer-armed avatar reaches further.
```

## src/shared/config/UpgradeStationConfig.luau

```
    3  -- The upgrade station (docs/gameplay/upgrade-station.md): a field armourer's bench
    4  -- placed mid-run by the world generator, where the carried weapon is upgraded one
    5  -- level for run credits. The ladder it drives is WeaponsConfig's (MAX_LEVEL,
    6  -- upgradePrice, damageAt); the level bought here lasts the run and never touches the
    7  -- profile. Data only, no engine types: the pure UpgradeStationMath and its tests read
    8  -- this table under the standalone Luau CLI. Parts follow PickupScenesConfig's PartSpec
    9  -- shape and are built by the same code; the meshes are WorldMeshConfig groups already
   10  -- in the manifest (oil_barrel), no asset added.
   33  -- Where along the run: one station per SPACING_STUDS of road (the chunk whose span
   34  -- crosses a multiple of it gets one), none before START_CLEARANCE_STUDS, and only in
   35  -- these biomes (a chunk of another biome that crosses the mark gets nothing: the next
   36  -- mark is 640 studs on).
   41  -- The spot: on the road shoulder this far inside the playable edge, clear of the chunk
   42  -- ends, facing the road with a little yaw jitter; CANDIDATES spots in order, the
   43  -- server takes the first one free of the chunk's props.
   48  -- covers every part in `parts` (the generator reaches about 8.4 studs from the
   49  -- origin); tests/upgrade computes the extent from the parts
   52  -- The prompt: hold this long from this far; the server accepts a trigger from a little
   53  -- further than the prompt shows, for the latency of a running player.
   59  -- The outline (through the pickup highlight pool) and the bench lamp.
   64  -- Announcer lines (AssetIds.audio.upgrade.*): played 2D on the client when the id is
   65  -- non-zero; the slots are `needed` in the manifest until real licensed files exist.
   76  -- The station in its own frame (x right, y up, -z toward the road): a generator with
   77  -- its exhaust and warning light, the bench with a vise and a tool board behind it, a
   78  -- lamp stand, two barrels.
  124  -- The prompt anchor and the weapon rest on the bench.
```

## src/shared/config/VendorsConfig.luau

```
   69  -- perks and perk slots, Credits only (PerkService); beside the Canteen on the west
   70  -- wall, clear of the gate on the south wall
```

## src/shared/config/ViewmodelConfig.luau

```
   10  -- Whole-rig scale. Measured in Studio: at 1.0 the weapon filled 48% of screen
   11  -- height, roughly double a normal first-person framing.
   14  -- Tuned against measured screen coverage rather than by eye. At (0.42, -0.36, -2) the
   15  -- mesh weapon sat with its slide at 43% of screen height, straddling the crosshair, and
   16  -- the grip and magazine each covered a third of the frame. Lower and further out puts
   17  -- the weapon in the bottom right where it belongs and leaves the sight line clear.
   18  -- 2026-09-28: at (0.38, -0.80, -2.5) the rifle ran straight down the view axis and was
   19  -- seen end-on, so only the stock and the hands were visible. Closer, further right and
   20  -- turned a few degrees towards the centre shows the side of the weapon, the way a
   21  -- first-person weapon normally reads.
   24  -- Per-class replacement for BASE_OFFSET. The pistol is a fifth of the rifle's length, so
   25  -- at the rifle's distance it read as a toy held at arm's length between two huge
   26  -- forearms; closer and nearer the centre it fills the frame the way a sidearm does.
   35  -- Mesh arms (ArmRigConfig, cut from a Mixamo soldier). ARM_GRIP places the hand frame
   36  -- (fingers -Z, back of the hand +Y, origin on the grip axis) relative to the weapon's
   37  -- HandRMount / HandLMount marker, per class; classes not listed use Rifle. ARM_WRIST_BEND
   38  -- turns the forearm about the wrist. Both are tuned against Studio screenshots.
   39  -- Right hand: palm against the pistol grip, index along the trigger, back of the hand to
   40  -- the right, grip raked 18 degrees. Left hand: palm up under the handguard, fingers
   41  -- round its right side, origin raised onto the handguard axis. From that base each hand
   42  -- rolls about its grip axis and turns in the palm plane, and the wrist bends, so the
   43  -- forearm runs back and down out of frame instead of lying across the screen. The angles
   44  -- were solved for forearm directions of (0.35, -0.5, 0.8) right and (-0.55, -0.45, 0.7)
   45  -- left in camera space, with the wrist kept under 30 degrees.
   57  -- Two-handed pistol grip: the right hand as on the rifle, the left wrapped round the
   58  -- front of the grip over the right fingers, palm facing right, index under the guard.
   59  -- Solved for forearms of (0.25, -0.45, 0.85) right and (-0.35, -0.45, 0.82) left.
   72  -- The wrist bend is baked into the arm meshes now (tools/arms_rig/build.py WRIST_BEND:
   73  -- 28 degrees right, -26 left), so the hand and forearm meet without a crack at rest.
   74  -- Anything set here turns the forearm on top of that.
   80  -- A constant light welded to the weapon means the player is never actually in the dark.
   81  -- Under the Night modifier that cancels the flashlight outright: the beam lands on
   82  -- geometry that is already lit, so it reads as having no effect. The fill stays for
   83  -- daylight framing and switches off whenever Workspace.NightMission is set.
   92  -- recoilRot holds the angular kick in radians. The raw spring peak per shot, from
   93  -- WeaponsConfig's snap and spring, is rifle 1.26 degrees, SMG 0.59, pistol 0.98 and
   94  -- shotgun 2.56 (the recoil springs integrate in 1/240 s steps, so this holds at any frame
   95  -- rate). The AK and Uzi Fire clips barely move the gun, the pistol clip kicks it 8
   96  -- degrees and the shotgun clip 34 (played at 45 %). The per-class scale sets the
   97  -- viewmodel's pitch per shot near MW2019's hip fire: rifle 3 degrees, SMG 1.8 (at 11
   98  -- rounds a second the kicks stack), pistol 1.5 over its clip, shotgun 2.5 over its clip.
   99  -- Yaw and roll jitter scale with it.
  113  -- The kick back per shot, over WeaponsConfig.recoilKick (which the third-person body reads
  114  -- too): rifle 2.7 to 3.6 cm, SMG 1.4 to 1.8, pistol 2.2 to 1.8, shotgun 6.2 as it is.
  144  -- 2026-09-29: in a recorded run the weapon swung up to 24 degrees every time the hip aim
  145  -- picked a new zombie, which read as the viewmodel jerking about. The weapon now only
  146  -- leans towards the target (10/6 degrees), holds a target longer before letting go, and
  147  -- the aim spring below is softer.
  210  -- This is an endless runner: the player sprints for the whole run and has to shoot
  211  -- while sprinting. A conventional sprint pose lowers and yaws the weapon out of the
  212  -- fight, which measured 47 degrees off the crosshair and made hitting a zombie
  213  -- impossible. Sprint here may express weight and movement, but the barrel has to stay
  214  -- on target, so the yaw term in particular is kept near zero.
```

## src/shared/config/ViewmodelPackConfig.luau

```
    3  -- First-person weapon packs: skinned arms + weapon imported from Sketchfab glb files
    4  -- (tools/fps_pack) with their clips baked into src/shared/viewmodel_clips. A class listed
    5  -- here is drawn from its pack instead of ViewmodelBuilder's procedural rig.
    6  --
    7  -- Rig units: every rig is uploaded at the same size (arm span about 3.76 studs, the
    8  -- pistol pack's native scale), so eye offsets and procedural sway share one scale.
    9  -- `eye` is the view point in the rig's RootPart space at rest, looking down -Z.
   10  -- `phases` are sound cues as fractions of a clip, measured from the magazine and bolt
   11  -- bones' motion relative to the weapon body (tools/fps_pack, 2026-09-29). They fire
   12  -- from PackViewmodel however the clip is cut or stretched, and WeaponsConfig's
   13  -- ammo-add times are placed on them (MagIn, SlideRelease, BoltForward, ShellIn).
   14  --
   15  -- Cut points and phases re-measured 2026-09-29, offline: the baked tracks decoded as
   16  -- ViewmodelClipPlayer does (targetWorld = delta * restWorld on the Studio rest positions
   17  -- in tools/fps_pack/roblox_rest) and sampled at 240 Hz; the weapon bone's rotation
   18  -- against Idle frame 0, and the support hand, magazine and bolt bones relative to the
   19  -- weapon body. MagOut = magazine 0.05 stud out of the well, MagIn / ShellIn = seated
   20  -- within 0.01, BoltBack = bolt at its rear stop, BoltForward = bolt home (studs of the
   21  -- uploaded rig, before RIG_SCALE). A tactical cut ends after MagIn where the clip is
   22  -- nearest the ready pose before any bolt motion; an empty cut ends once the action is
   23  -- closed and the gun is back within a few degrees of idle.
   27  -- A section of one clip. `from`/`to` are fractions of the clip; the section is played
   28  -- at whatever speed fits the time WeaponsConfig gives it, then the idle/walk loop is
   29  -- blended back in over `blendOut` seconds (that blend is part of the reload time).
   30  -- `phases` are extra markers for this use of the clip only (the pistol's empty reload
   31  -- adds SlideRelease, the tactical one never reaches it).
   40  -- Pump shotgun reload: enter, one `loop` section per shell (its ShellIn marker is the
   41  -- add point), leave, and the `chamber` pump when the reload started from empty.
   49  -- A speed reload from empty drops the spent magazine instead of pouching it the way the
   50  -- tactical reload does. When `clip` plays as the empty reload and passes `at` (clip
   51  -- fraction), the meshes in `pieces` (name pattern and the bone that carries them; of
   52  -- several meshes with a matching name, the one nearest that bone at rest) leave
   53  -- the rig as a world-size copy that falls and lies on the ground (DroppedMagazines);
   54  -- `hidden` keeps magazine meshes out of sight over clip fractions where the hand would
   55  -- otherwise carry the dropped one. `worldScale` turns the rig size into world size.
   56  -- `skin` lists the joints of a mesh skinned to more than one bone (the Uzi's magazine and
   57  -- its rounds are one mesh): the copy takes those bones along as the viewmodel poses
   58  -- them, or it is drawn in its bind pose with the rounds lying apart from the magazine.
   59  -- `body` is the magazine's box in the mesh's own space (centre and size, MeshSize
   60  -- units) for a mesh whose bounds are larger than the magazine: the copy falls, spins
   61  -- and lies on that box instead of the mesh bounds. Only the first piece's is used.
   62  -- `tuck` moves the vertices of `skin` joints from their centre (`from`, mesh space) to
   63  -- a point inside the magazine (`to`), out of sight: an empty magazine shows no rounds.
   80  -- After the last round the bolt or slide stays locked back until an empty reload
   81  -- releases it: the joints that clip's first frame holds there (the slide or bolt, the
   82  -- parts that ride on it, the raised slide stop or bolt catch), and the clip.
   85  -- A frame where the pack trades identical meshes between bones: the matching tracks of
   86  -- the clip hold and snap there instead of interpolating (ViewmodelClipPlayer.cut).
   93  -- Where the rig sits relative to the pack camera, in camera space (studs of the scaled
   94  -- rig; +X right, +Y up, -Z away). The packs frame their guns for their own camera,
   95  -- which puts some of them in the middle of the view or against the face; this moves
   96  -- the whole rig, every clip alike. Tuned in Studio with the camera attribute
   97  -- ViewmodelHold (PackViewmodel.step).
   99  -- Turn of the rig about the eye, degrees (pitch, yaw, roll), applied with `hold`: a
  100  -- pack whose idle carries the gun slanted across the body can be turned so the barrel
  101  -- runs more along the view. Tuned with the camera attribute ViewmodelHoldAngles.
  103  -- The same offset while a reload, a draw or an inspect plays (nil keeps `hold`): a
  104  -- hold that brings an idle gun closer can push those clips, which already bring the
  105  -- gun in, into the camera. The rig blends between the two over about 0.1 s.
  107  -- Rotation of the rig's rest (bind) pose relative to the upright clip pose, when
  108  -- Roblox built the bones turned (the Uzi's bind A-pose comes in turned -90 degrees
  109  -- about X). Only the weapon anchors read it; the clips always pose the rig upright.
  111  -- Roblox import units per pack unit when the rig did not come in at the clips' scale
  112  -- (the Fab M4 imports in centimetres: 0.03); 1 when omitted
  120  -- share of the Fire clip's move that is applied (1 = as authored)
  122  -- fraction of `fire` played before `fireFollow` takes over (the shotgun keeps only
  123  -- the recoil of its Fire clip and hands over to the pump)
  126  -- fraction of `fireFollow` at which the action is closed again; fire and follow are
  127  -- sped up together so this lands inside one fire interval
  129  -- clip lists for classes without `tactical`/`empty` cuts, stretched to the reload time
  140  -- material name in a mesh's name -> SurfaceAppearance template in
  141  -- ReplicatedStorage.ViewmodelSurfaces, for meshes the importer left without one
  143  -- the templates also replace the importer's own SurfaceAppearance on matching meshes:
  144  -- Roblox's importer reads a metallicRoughness texture without the material's
  145  -- metallicFactor, so a skin or glove with factor 0 over a white B channel comes in
  146  -- fully metallic
  152  -- The rigs are uploaded at about 2.2x life size. At that size the arms reach 2-3 studs
  153  -- into the world and clip into walls and cars next to the camera, so the clone is scaled
  154  -- down (Model:ScaleTo scales the bones too) and the clip translations and eye with it;
  155  -- the image is the same, the world footprint shrinks.
  158  -- The procedural channels (sway, recoil, impact) are in studs tuned for the old
  159  -- 0.72-scale rig; their translations are multiplied by this for the pack rigs.
  162  -- the pack clips carry their own walk bob, so the procedural bob is damped hard
  166  -- Fab "G17 - FPS Weapon Animations Pack" (BarcodeGames, Fab Standard License; rig and
  167  -- clips are Fab content in assets/fab/ and src/shared/fab/G17Clips.luau, never
  168  -- committed). Replaced the pistol pack (2026-10-01). Imported in centimetres like the
  169  -- M4. The pack's Idle is one pose; Idle and Walk loop it. Both pack reloads fetch the
  170  -- spare first, strip the old magazine into the same hand and pouch it (a tactical
  171  -- reload with retention); from frame 54 the two magazine bones trade tracks
  172  -- (identical meshes, invisible), so the seated one is Mag1 again when the clip ends.
  173  -- The empty reload is turned into a speed reload (2026-10-01, the owner: tactical
  174  -- and empty must differ in handling, not only in length): the spent magazine falls
  175  -- free as it leaves the well (0.65 s) and the old-magazine track is hidden, and the
  176  -- slide stays locked back after the last round until the slide release.
  177  -- Reload 2.80 s: MagOut 0.60, MagIn 0.76, ready by 0.92. ReloadEmpty 3.03 s: MagOut
  178  -- 0.45, MagIn 0.58, slide release 0.63, ready by 0.78 (first estimates from the bone
  179  -- motion, to be tuned by ear).
  185  -- the pack's camera holds the pistol in the middle of the view; moved right, down
  186  -- and forward into a ready hold, and about half as far while a reload or the draw
  187  -- plays, so the magazine work stays in frame
  215  -- Mag1 is the dropped one until the trade at frame 54 (0.594), then Mag2 carries
  216  -- the old magazine's pouching track
  223  -- the pack's "FireSelector" is the Glock 18 selector on the slide's back plate: it
  224  -- rides with the slide (0.138 forward of the bind in every other clip, like the
  225  -- slide), and the slide stop ("SlideRelease") stands raised in ReloadEmpty's first
  226  -- frame; holding the slide alone left the selector forward of it
  228  -- both reloads trade the magazines' roles at frame 54 (Mag1 and Mag2 swap places in
  229  -- one frame); interpolated, the two crossed the view for a frame
  234  -- the importer gave this rig no SurfaceAppearance at all (its materials carry only
  235  -- a base colour); the arms share the M4 pack's textures
  243  -- Fab "M4 - FPS Weapon Animations Pack FREE" (BarcodeGames, Fab Standard License; the
  244  -- rig and the clips are Fab content: assets/fab/ and src/shared/fab/M4Clips.luau, never
  245  -- committed). Replaced the AK pack (2026-10-01). Roblox imports the rig in centimetres,
  246  -- the clips are baked at 3 studs per metre, so the rig is scaled by 0.03 first. The pack
  247  -- has no idle or walk: both are the Draw clip's last pose (build in tools/fps_pack), the
  248  -- procedural layer carries breathing and bob. Reload 3.63 s: MagOut 0.29, MagIn 0.64,
  249  -- back at ready by 0.78. ReloadEmpty 3.80 s: MagOut 0.31, MagIn 0.57, bolt catch
  250  -- released 0.70, ready by 0.84. In both pack reloads the hand carries the old
  251  -- magazine to the pouch and comes back with "it" (Mag2 never moves): right for the
  252  -- tactical reload with retention. The empty one becomes a speed reload: the magazine
  253  -- falls free when it leaves the well (0.85 s, fraction 0.225) and Mag1 stays hidden
  254  -- until the hand turns back from the pouch with the fresh one (1.35 s); the bolt
  255  -- stays locked back after the last round until the bolt catch (2026-10-01).
  261  -- the pack frames the rifle big in the middle of the view; moved right, down and
  262  -- forward into a hip carry, about half as far while a reload or the draw plays
  286  -- both magazines carry a round mesh of the same name: the one nearest the bone
  297  -- the bolt catch stands engaged (7 degrees) in ReloadEmpty's first frame
  299  -- the imported arms read metalness 255 (metallicFactor 0 dropped); the same maps
  300  -- with the factor applied, shared with the G17
  307  -- Fire (1.625 s) is recoil plus a slow settle: peak 0.12-0.14 (36 degrees) and the
  308  -- clip's own bolt flick is home by 0.16, so only the first 20% is kept (31 degrees
  309  -- off idle, recovering) and the AccionFire pump follows. AccionFire (1.25 s) starts
  310  -- and ends at idle: pump at the rear 0.10 (BoltBack, where the hull is ejected), home
  311  -- 0.48 (BoltForward and followReady). Reload (1.667 s, one shell, gun rolled 100
  312  -- degrees) seats the shell at 0.70. The loop section 0.24-0.89 starts and ends where
  313  -- the support hand crosses its own path (0.15 stud apart, 0.71 for the old
  314  -- 0.1-0.88), so each shell reads as one dip of the hand; one cycle fits
  315  -- WeaponsConfig perShell at 1.2x. The chamber pump ends at 0.51, just after home.
  326  -- the clip kicks the gun 34 degrees (22 by 0.08, 34 at 0.17): at the hip that reads
  327  -- as a cartoon, so it plays at 45 %, about 15 degrees, like MW's pump guns
  343  -- the imported sleeves read metalness 255 (metallicFactor 0 dropped)
  347  -- Uzi pack (1Matzh). Reload 2.033 s: MagOut 0.12, MagIn 0.51, gun back by 0.71 with
  348  -- a small overshoot, settled by 0.80 (0.2 degrees at the 0.9 cut). ReloadEmpty 3.7 s:
  349  -- MagOut 0.07, MagIn 0.35, then the open-bolt top-knob cock: pull from 0.58, knob at
  350  -- the rear 0.62 (BoltBack), home 0.70 (BoltForward), gun back by 0.88 (1 degree at
  351  -- the 0.9 cut). Both cuts play at natural speed. Fire moves no weapon part (open
  352  -- bolt), the procedural recoil carries the shot. Eye: the pack camera is at
  353  -- (0, 4.42, -0.07), moved back like the other packs'. ReloadEmpty's frame 11 lifted
  354  -- the left arm for that one frame: smoothed in SMGClips with
  355  -- tools/fps_pack/smooth_keys.py --set (2026-10-10).
  360  -- the pack's camera sits on the sights with the extended stock against the cheek;
  361  -- lowered and moved right into a hip hold, the stock leaves the view at the
  362  -- bottom right
  375  -- the speed reload: the magazine falls free as it clears the grip (frame 10) and
  376  -- stays hidden until the hand comes back with the fresh one at frame 25. The clip
  377  -- itself carries the same magazine off and teleports it into the hand at frame 24,
  378  -- with its rounds flying in from off screen a frame later.
  387  -- the mesh's bounds reach from the magazine to the rounds' bind spot
  388  -- 2.2 studs away; the magazine's own vertices (measured with
  389  -- EditableMesh, 2026-10-10)
  391  -- ReloadEmpty parks the rounds 4 studs off the magazine (it is empty);
  392  -- the dropped copy keeps them inside it, at the floorplate end (+Z,
  393  -- the feed lips are at -Z): the side holes in the middle showed them
  406  -- the importer dropped the watch material's baseColorFactor (0.24): the template
  407  -- carries it. The full part name, "Watch" alone also matches Mesh_Watch_Emission_0
```

## src/shared/config/ViewmodelRigConfig.luau

```
    3  -- Numeric specification of the first-person rig, transcribed from the free
    4  -- "Gun Viewmodel Kit" by HowToRoblox (asset 11994419773) and its Glock viewmodel.
    5  -- It lives here as data rather than as a binary model so the rig stays in git as
    6  -- text, diffable and reviewable, and so Rojo owns it like every other config.
    7  --
    8  -- Axis conventions, measured rather than assumed:
    9  --   arms  - built around HumanoidRootPart; every limb sits at 90 deg about X
   10  --   gun   - +Z is the muzzle direction, +X is up, +Y is the width axis
   11  --
   12  -- TWO HARD LIMITS, both measured in Studio rather than assumed:
   13  --
   14  -- 1. `MeshPart.MeshId` cannot be written by a script in any context available to us -
   15  --    it reports "lacking capability NotAccessible" in both a running game and the edit
   16  --    session. So this table cannot be turned into a rig by a runtime builder. The rig
   17  --    has to arrive as instances: either cloned from an inserted model, or shipped as an
   18  --    .rbxmx that Rojo mounts, which is the route we take.
   19  --
   20  -- 2. The kit's published animation ids DO NOT LOAD for us. Every one returns
   21  --    "Animation failed to load" and a track length of 0, because a Roblox Animation
   22  --    asset is only usable by the account or group that uploaded it. The ids below are
   23  --    kept purely as a record of what the kit's own clips were; they are not playable
   24  --    here and must be replaced by clips authored and published under this account.
   60  -- where the right hand grips the weapon, in the weapon's own frame
   84  -- Joint names are load-bearing: the published clips address these exact tracks.
  130  -- Offsets are relative to the weapon's Main part, which is the hub every other piece
  131  -- hangs off. `movable = true` earns a Motor6D so a clip can drive it; everything else
  132  -- is welded, which also keeps the Animation Editor's track list down to what matters.
  166  -- Reference only: these are the kit's own clip ids and they do not load for us
  167  -- (see limit 2 above). Replace with ids published from this account.
```

## src/shared/config/VisibilityConfig.luau

```
    3  -- How far each lighting preset lets you see, in studs: the distance at which its fog
    4  -- swallows a 10-stud object, judged in Studio (docs/world/environment.md, screenshot
    5  -- plan shot C). FogBudget checks these against the chunk spawn distance so a chunk is
    6  -- never spawned inside sight. Kept apart from LightingConfig, which needs Color3, so the
    7  -- check runs under the standalone Luau CLI.
   27  -- No run is spawned under these presets, so the spawn-edge rule does not apply.
   33  -- Mirrors Workspace.StreamingTargetRadius in default.project.json, which Luau cannot read.
   36  -- Slack between the spawn edge plus one chunk and the streaming radius.
```

## src/shared/config/WallPullbackConfig.luau

```
    3  -- The first-person weapon pulling back near walls (docs/gameplay/wall-pullback.md),
    4  -- after Modern Warfare 2019: a short cast from the camera along the aim each frame;
    5  -- the closer the hit inside the weapon's reach, the further the pack viewmodel
    6  -- retracts toward the chest and tilts up and aside. Fully pulled back, the gun does
    7  -- not fire until the muzzle clears. Data only, no engine types: the pure
    8  -- WallPullbackMath and its tests read it under the standalone Luau CLI. Distances are
    9  -- studs in the world; the pose is in the viewmodel's hold space (the pack rigs are at
   10  -- ViewmodelPackConfig.RIG_SCALE, so its offsets are small), angles in degrees.
   14  -- How far ahead of the eye the weapon reaches in the world, per weapon class: about
   15  -- the third-person gun's length plus the arm (WorldWeaponModel's receiver, barrel and
   16  -- stock, Rifle 3.3 studs end to end). Anything nearer than this starts the pull-back.
   25  -- Fully pulled back when the hit is within this share of the reach (the muzzle would be
   26  -- in the wall even with the gun drawn in); in between, smoothly partway.
   29  -- The cast: a thin sphere so a doorway's edge or a lamp post catches it, not only a
   30  -- surface dead ahead. Parts that cannot be collided with (foliage, decals, glass
   31  -- panes set non-colliding) do not pull the gun back.
   35  -- Easing, per second (exponential, frame-rate independent): in a little faster than out,
   36  -- so a wall is answered at once and the gun comes back without a snap.
   40  -- Firing: blocked once the hit is inside the full share, released only when it is
   41  -- this many studs beyond it (or nothing is hit), so the edge does not flicker.
   44  -- The fully pulled-back pose, in the hold space (x right, y up, +z toward the chest):
   45  -- drawn back and a little down, the muzzle tilted up and turned aside, a slight cant.
```

## src/shared/config/WeaponsConfig.luau

```
    3  -- Reload timings follow the MW model: a reload has a total length and an ammo-add
    4  -- moment (the magazine seats, the counter updates). Only the tail after ammo-add can be
    5  -- cut by firing; cancelling before it keeps the old count. The server (WeaponService)
    6  -- and the client prediction (WeaponController) both read the helpers at the bottom of
    7  -- this file, so they share one timeline and cannot drift apart.
    8  --
    9  -- The seconds here are matched to the baked pack clips (ViewmodelPackConfig), which are
   10  -- played at natural speed or at most about 1.3x; see the notes per weapon. Change a
   11  -- time here and the clip speed follows, but keep ammo-add on the clip's MagIn (or
   12  -- SlideRelease / BoltForward) marker or the counter will tick before the hands do:
   13  -- ammo-add = marker / cut end * (total - blendOut), the cut starting at 0.
   14  -- Ammo-add times re-derived 2026-09-29 from the cut points and markers measured then
   15  -- (method in ViewmodelPackConfig); the reload totals were kept.
   19  -- Pump shotgun reload, all in seconds (scaled together by SkillEffects.reloadScale).
   21  -- IdleToReload: the gun rolls over to the loading port
   23  -- one shell cycle: hand to the carrier, shell into the tube, hand back
   25  -- inside a cycle, when the shell is seated and counted
   27  -- ReloadToIdle
   29  -- pump appended when the reload started from empty (nothing chambered)
   31  -- fast exit when fire interrupts the loop, after the shell in hand is seated
   48  -- tactical reload (rounds left in the mag): seconds until the weapon is ready
   50  -- empty reload: adds the chambering action (bolt rack, slide release, pump)
   52  -- seconds into the reload when the rounds are counted
   57  -- seconds after an equip before the weapon can fire (the Equip clip plays at natural
   58  -- speed and is longer; firing cuts its tail)
   60  -- WeaponVfx casing model and WeaponSfx landing sound set
   62  -- false for the pump: the hull comes out on the pump stroke, not on the shot
   64  -- rounds left at or below which each shot adds the low-ammo spring layer
   71  -- teammates' shots at 40..350 and 250..1400 studs (GunshotRemote layers); the keys
   72  -- are empty in AssetIds until the recordings exist and the close take plays instead
   84  -- TEMPORARY, for testing only: number keys 1-5 select any weapon in `order` and the
   85  -- server skips the ownership check on equip. Set to false before shipping.
   91  -- Pack Reload clip: 2.708 s, MagOut 0.17, MagIn 0.67, SlideRelease (right thumb)
   92  -- 0.70, gun back up by 0.84, no slide motion. Both cuts play 0-0.84 and blend to idle
   93  -- in 0.2 s: tactical at 1.2x (MagIn at 1.52 s), empty at 1.03x (SlideRelease at
   94  -- 1.84 s).
  130  -- Pack (Uzi) clips at natural speed. Tactical: Reload (2.033 s) to 0.9, MagIn at 0.51
  131  -- (1.04 s), then a 0.17 s blend to idle. Empty: ReloadEmpty (3.7 s) to 0.9 with a
  132  -- 0.2 s blend; MagIn at 0.35 (1.30 s), the open-bolt top-knob cock BoltBack 0.62,
  133  -- BoltForward 0.70 (2.59 s), where the rounds are counted.
  169  -- Pack clips: IdleToReload 1.0 s (1.33x), Reload 1.667 s one shell with ShellIn at
  170  -- 0.70, looped over 0.24-0.89 (1.2x, seated 0.64 s into the cycle), ReloadToIdle
  171  -- 0.917 s (1.31x), AccionFire pump to 0.51 as the chamber stroke (1.16x).
  172  -- fireRate 1.25 lets the trimmed Fire (recoil only) plus the AccionFire pump up to
  173  -- followReady close at 1.29x inside one interval; 1.5 would need 1.54x, over the
  174  -- 1.5x cap.
  175  -- reloadTime / ammoAdd* below describe a one-shell reload for anything that reads
  176  -- them generically; the shell loop itself runs on shellReload.
  220  -- Pack (AK) Reload clip: 4.583 s, MagOut 0.20, MagIn 0.46, BoltBack 0.64,
  221  -- BoltForward 0.68. Tactical stops at 0.54, before the hand sweeps to the charging
  222  -- handle, at 1.18x (MagIn at 1.79 s) and blends to idle in 0.35 s. Empty keeps the
  223  -- charging-handle rack (an AK has no bolt hold-open), plays to 0.83 at 1.19x
  224  -- (BoltForward at 2.63 s) and blends out in 0.2 s.
  284  -- Reload timeline helpers. Every time is in seconds from the moment the reload started
  285  -- and already multiplied by `scale` (SkillEffects.reloadScale, 1 without the skill).
  287  -- Magazine reload: (ammo-add time, total time).
  295  -- Shell reload: when shell `index` (1-based) is counted.
  304  -- Shell reload: total time for `shells` shells, with the chambering pump from empty.
  317  -- Fire interrupting a shell reload `elapsed` seconds in. The shell already in the hand
  318  -- is still seated at its add point, then a fast exit (plus the pump if nothing was
  319  -- chambered). Returns how many shells end up loaded in total and when the weapon is
  320  -- ready again (seconds from the reload start). Once the loop is over (ReloadToIdle is
  321  -- already playing) nothing changes.
  334  -- still rolling the gun over: no shell in hand yet
```

## src/shared/config/WorldMeshConfig.luau

```
    3  -- Mesh set for world dressing (trees, rocks, cars, crops). Ids come from
    4  -- assets/manifest.json (mesh/world/* and texture/world/*) through AssetIds. A mesh
    5  -- with id 0 is simply skipped and the builders fall back to their primitive shapes.
   14  -- Box for things that are boxes (cars), Hull for rocks. Trees never collide with
   15  -- their mesh: they get an invisible trunk collider instead.
   17  -- PBR look: the SurfaceAppearance of this name in ReplicatedStorage.PropSurfaces
   18  -- (assets/props/surfaces.model.json), used instead of `texture`
   20  -- studs per mesh unit at the prop's real size: the Sketchfab / Poly Haven props are
   21  -- modelled in metres and the world is 1 stud = 0.28 m (WorldMeshes.placeNatural)
   36  -- 1 stud = 0.28 m
   39  -- Post-apocalyptic props (assets/props, CC0 / CC BY, see LICENSES): mesh read back from
   40  -- the Model upload, PBR maps as a SurfaceAppearance template of the same name.
   69  -- the crashed supply drop (WeaponPickups); a Cube 3D box, placed by height
   79  -- the textured street face is +Z in the mesh; WorldFlanks turns it to the road
  102  -- Builders ask for a group and get one of its loaded members at random.
```

## src/shared/config/ZombieRigConfig.luau

```
    3  -- GENERATED by scripts/build_zombie_rig.py from assets/zombies/<rig>/rig.json.
    4  -- Do not edit by hand: re-run the script after re-splitting a zombie.
    5  --
    6  -- Character space at scale 1: feet at y = 0, facing -Z. `centre` is where each
    7  -- MeshPart template sits, `pivot` is the joint position; C0/C1 are the pivot
    8  -- minus the part centres, with no rotation (all joint frames are axis-aligned,
    9  -- like Roblox's own R15 rig, so stock R15 clips play unchanged).
```

## src/shared/config/ZombieSkins.luau

```
    3  -- Skinned zombie rigs from Sketchfab (tools/zombie_pack): which rig each ZombiesConfig
    4  -- entry wears, the rig's key bones (hit parts follow them), and its clips with their
    5  -- ground speed (studs/s at playback speed 1, measured from root travel or the planted
    6  -- foot by build_zombie_anims.py) so the playback speed keeps the feet planted.
    7  -- Bone names are the ones Roblox built on import (tools/zombie_pack/roblox_bones.json).
   29  -- fastest the AI may move this skin, for rigs with no run cycle
   31  -- where the rig sits against its imported bind pose: some packs' clips hold the
   32  -- skeleton root away from the bind in every frame, and the rig is moved the other way
   34  -- material name in a mesh's name -> SurfaceAppearance template in
   35  -- ReplicatedStorage.ZombieSurfaces that replaces the importer's (it read the
   36  -- metalness maps without the materials' metallicFactor 0: the skin came in as metal)
   67  -- the Fab "UEFN Manny Zombie Animation Sample Pack" retargeted onto the rigs
   68  -- (tools/zombie_pack/retarget_ue.py; Fab content, the clips stay out of the repo, the
   69  -- ids are ordinary uploads)
   75  -- "Zombie" by pxltiger (3ds Max Biped skeleton)
   99  -- "Zombie Hazmat" by LxNazarov (Mixamo skeleton)
  103  -- the head came in as metal (metallicFactor 0 dropped); the suit's broken visor is
  104  -- cut out of its colour alpha (glTF MASK), which the importer's Overlay drew opaque
  121  -- the pack's own set had no run and no death (a 2-stud/s cap and no corpse pose);
  122  -- the retargeted UE clips fill both
  127  -- only a shuffle when there is no run: past about 2.6x the cycle reads as frantic
  130  -- "ZOMBIE. Animation test for the game" by stasbelyk13 (Blender skeleton), the runner
  153  -- every Ghoul clip holds Bone.009 3.08 studs below its bind (measured 2026-09-29
  154  -- from the Pose tracks: a constant, the same in all 11 clips), which sank the body
  159  -- which skins each ZombiesConfig id wears, with weights
  173  -- `withDeath`: only skins that have a death clip (corpses are posed from it)
```

## src/shared/net/Remotes.luau

```
   23  -- client -> server, no args: fire pressed during a shell reload. The shell in hand
   24  -- is still counted, the loop stops and fire stays blocked for the fast exit.
   30  -- server -> client: a weapon pickup's or upgrade station's outcome ("Weapon"
   31  -- weaponId position, "Drop" weaponId position, "Upgrade" weaponId position level,
   32  -- or "Refused" message position level?)
   35  -- the helicopter intermission (IntermissionService): client -> server, a boolean
   36  -- (ready or not) during the ready check; client -> server, no args, a skip vote
   37  -- during a skippable crash; server -> client, the cabin snapshot or nil when over
   48  -- Lossy, unordered, for values that change every frame and are replaced by the next
   49  -- packet: the third-person aim (pitch, yaw offset) relayed at most 20 times a second.
```

## src/shared/types/Flow.luau

```
    3  -- Cabin: seated in the helicopter between the launch countdown and the run (the
    4  -- intermission, IntermissionService); the IntermissionStage attribute says which beat
```

## src/shared/util/BodyMath.luau

```
    3  -- Pure math for the third-person body: aim smoothing and spread, the wire encoding of
    4  -- the aim, recoil springs, the reload / equip / pump gesture timelines built from
    5  -- WeaponsConfig numbers, the sprint blend and the LOD bands. Numbers in, numbers out,
    6  -- no Roblox services or datatypes, so `luau tests/body/run.luau` exercises it outside
    7  -- Studio and the server relay can share the validation. Angles are degrees, times
    8  -- seconds, distances studs.
   13  -- the clamped aim: the head ends on it, the gun on `gunPitch` and `yaw`
   16  -- the chest's share
   19  -- the gun's pitch, reduced in a sprint
   59  -- Exponential approach with a time constant, wrapping so the short way round is taken.
   80  -- Signed yaw of a flat direction relative to a flat reference direction: positive when
   81  -- the direction is to the left of the reference (a positive Y rotation).
   91  -- Pitch of a look vector from its vertical component: positive looking up.
   96  -- The aim over the body, clamped first: the chest turns by its share (the torso twists
   97  -- before the feet turn), the head and the gun end on the whole aim, measured from the
   98  -- root's upright frame so the locomotion clip's lean does not tip them. `armScale`
   99  -- lowers the gun's pitch in a sprint.
  112  -- Whole degrees on the wire.
  117  -- Send when either angle moved a whole degree and the rate allows, or on the keepalive.
  137  -- Server-side check of an aim packet: both numbers, finite, clamped into the limits.
  148  -- Damped spring toward zero, stepped with the closed-form solution of the oscillator
  149  -- (under-, critically and over-damped branches), so any frame time lands on the exact
  150  -- curve: no substeps, no numerical over-damping, and the peak of an impulse is where
  151  -- impulseForPeak says. The recoil kick and snap are impulses on the velocity.
  193  -- The velocity impulse that makes a spring near critical damping peak at `peak`: with
  194  -- x(t) = v t e^(-w t) the peak is v / (w e) at t = 1 / w.
  199  -- The magazine reload as poses of the support hand over time: to the belt, to the mag
  200  -- well with the fresh magazine, the seat at ammo-add, then the chambering action from
  201  -- empty (bolt / charging handle: the hand to the charge socket, pulled, released) and
  202  -- back on the gun by the total. `chargeTime` is how long the pull and release take.
  224  -- The pump shotgun reload: the gun rolls over (`start`), one belt-to-port cycle per
  225  -- shell seated at `addAt` inside it, the finish, and the pump when nothing was chambered.
  252  -- The pump stroke after a shot on a weapon that does not eject on fire, starting `delay`
  253  -- seconds after the shot so the kick reads first.
  264  -- The draw: from the lowered pose up to the grip over the weapon's draw time.
  278  -- The segment of a timeline at `elapsed` with a smoothstep alpha between its two poses;
  279  -- before the first keyframe it holds the first pose, after the last it holds the last.
  313  -- Sprint switches on above the threshold and off below it minus the hysteresis, so a
  314  -- speed hovering at the edge does not flicker the pose.
  322  -- Update cadence in frames for a character at `distance` (0 means never) and whether
  323  -- the hand IK stays on.
  336  -- Whether a character with `index` in the round robin updates this frame at `cadence`.
```

## src/shared/util/DevMode.luau

```
    3  -- Studio-only switches read while playing, shared by client and server. The run and the
    4  -- test yard (DevConfig.SANDBOX) swap at run time: the server keeps the current mode in
    5  -- the workspace attribute DevMode ("Run" or "Yard", Sandbox.luau) and DevFreezeRun with
    6  -- it, and the client's dev button (SandboxInput, key M) asks for the other one. Outside
    7  -- Studio both answers are always false.
   29  -- the run held still: DevConfig.FREEZE_RUN, the yard, or DevFreezeRun set by hand
```

## src/shared/util/GoalsHudMath.luau

```
    3  -- The mission goals on the run HUD (docs/gameplay/goals-hud-and-ladder.md): the
    4  -- server packs each participant's goal progress into one attribute string and the
    5  -- HUD unpacks it into rows. Pure Luau: no services, no engine types, no requires, so
    6  -- it runs under the standalone Luau CLI (tests/goals/run.luau); the goals come in as
    7  -- the MissionGoalsConfig table.
   25  -- progress clamped to the target, whole
   29  -- "320 / 1500"
   39  -- The progress as the HUD shows it: floored to the metric's step (`steps`, e.g. 5 studs
   40  -- for the distances, so the string changes at most once per step), 1 by default, and
   41  -- capped at the goal's target (a step never lands a goal short of it, since the
   42  -- targets are whole steps).
   48  -- "Distance1500=320;Kills25=4": every goal in config order, its metric's progress
   49  -- stepped, so the string only changes when a whole step changes.
   62  -- The progress per goal id from an encoded string; anything malformed is skipped.
   77  -- The HUD rows in config order from decoded values (a goal missing from the string
   78  -- reads 0).
```

## src/shared/util/HighlightBudget.luau

```
    3  -- Which pickup scenes hold a Highlight this pass (docs/gameplay/weapon-pickups.md).
    4  -- Roblox renders at most 31 Highlight instances, so the client keeps a pool below
    5  -- that and hands the outlines to the nearest scenes; a scene that already holds one
    6  -- keeps it unless a scene without one is closer by `margin`, so two scenes at the same
    7  -- distance never trade the outline back and forth. Pure Luau, tested by
    8  -- tests/pickups/run.luau.
   16  -- the ids holding a highlight after this pass
   18  -- ids to hand a highlight to, nearest first
   20  -- ids to take the highlight back from
```

## src/shared/util/HitMarkerMath.luau

```
    3  -- The hit markers' rules (docs/gameplay/hit-markers.md): which variant a confirmed
    4  -- shot shows, how big and how long, and the marker's look at a moment. One marker at a
    5  -- time: a new confirmation restarts it (no stacked copies), except that a hit or a
    6  -- headshot does not cut short a kill marker still showing. Pure Luau: no services, no
    7  -- engine types, no requires; tests/hitmarkers/run.luau.
   11  -- What the server confirmed for one shot of the local shooter (all pellets summed).
   53  -- The variant for a confirmation, or nil when it confirmed nothing (no damage, no kill).
   77  -- Whether the state still shows at `now`.
   82  -- The state after a confirmation at `now`: the marker restarts in the new variant,
   83  -- unless a higher-priority one (a kill over a hit) is still showing, which stays.
  101  -- The marker's look at `now`: visible, its alpha (1 opaque) and scale (popping in from
  102  -- POP times the scale, settling by POP_SHARE of the duration, fading after FADE_FROM).
  117  -- Sums one shot's outcomes per pellet into the confirmation the shooter gets: the
  118  -- damage dealt, whether any pellet hit a head, whether any killed. nil when no pellet
  119  -- hurt a zombie.
```

## src/shared/util/IntermissionMath.luau

```
    3  -- The helicopter intermission's rules (docs/gameplay/heli-intermission.md): the ready
    4  -- check, the skip vote, the crash length and the grace window. Pure Luau: no
    5  -- services, no engine types, no requires, so it runs under the standalone Luau CLI
    6  -- (tests/intermission/run.luau). Members are keys (the server uses the player's
    7  -- UserId); times are server seconds passed in.
   16  -- "Waiting": someone is not ready and time remains. "AllReady": every member still
   17  -- here is ready. "TimedOut": the AFK timeout passed; the run starts for whoever is
   18  -- here. "Empty": nobody is left.
   39  -- Marks a member ready or not; false for someone who is not a member.
   48  -- A member left (the game, or the cabin): their vote goes with them.
   88  -- A member's vote to skip; false for someone who is not a member. A vote cannot be
   89  -- taken back (one press, like the reference).
  116  -- Passes when every member still here voted (and someone is here).
  121  -- The crash's length and whether it can be skipped: the short, skippable version only
  122  -- when every member has run before (`runs` per member, the profile's lifetime count);
  123  -- an empty squad gets the full length. The full length is clamped to the config range.
  137  -- The grace window: until when a player at the wreck is ignored, and whether they are
  138  -- now. A missing or non-number value never protects.
  155  -- The look target after a mouse move of (dx, dy) pixels, in degrees from the seat's
  156  -- view, clamped: yaw within +-LOOK_YAW, pitch within LOOK_PITCH_MIN..LOOK_PITCH_MAX.
  157  -- Moving the mouse right turns right (negative yaw about +y), down looks down.
  164  -- One frame of easing toward the target (exponential, frame-rate independent), so the
  165  -- view never snaps; within a hundredth of a degree it lands.
  174  -- Seconds left, whole and rounded up, for a countdown label (0 when past).
```

## src/shared/util/LocomotionMath.luau

```
    3  -- Pure rules for the third-person locomotion clips: which clip set a weapon class
    4  -- uses, which gait the movement state asks for, which loaded clip answers it (with the
    5  -- fallbacks down to the generic Run clip) and how fast it plays. No services and no
    6  -- requires, so tests/animation/run.luau runs it under the standalone Luau CLI.
    7  -- Design: docs/animation/third-person-locomotion.md.
   14  -- below this speed a moving character walks
   16  -- a sideways share of the velocity at or beyond this strafes (the auto-run swerving
   17  -- at 24 forward keeps its run; moving mostly sideways side-steps)
   25  -- clip id suffix per gait
   35  -- gaits tried in turn inside a set when the wanted one has no clip
   45  -- the legacy additive strafe clips, played over Run when a set has no strafe gait
   51  -- The clip set a weapon class runs with: the pistol set for a pistol, the rifle set for
   52  -- everything else (SMGs and shotguns are carried two-handed).
   57  -- Clip id of a gait in a set: ("Rifle", "strafe_left") -> "RifleStrafeLeft".
   62  -- The gait the movement asks for. `lateral` is the sideways share of the ground
   63  -- velocity in the character's frame (-1 all left, 1 all right); `sprinting` is the
   64  -- hysteresis decision made from the sprint threshold (BodyMath.sprintTarget). Moving
   65  -- mostly sideways side-steps at any speed, since a run clip facing forward would glide.
   82  -- Clip weights that answer a gait with what is loaded: the set's own clip, else the
   83  -- set's fallback gaits, else the generic Run (with the legacy additive strafe on top
   84  -- when it exists). Idle with no idle clip plays nothing, as before the sets existed.
  112  -- Playback rate of a gait clip so the feet match the ground speed: the speed over the
  113  -- gait's reference speed, clamped. Idle plays at 1.
```

## src/shared/util/MaterialSets.luau

```
    3  -- Pure helpers for MaterialUtil's set list (no services, no engine types), tested by
    4  -- `luau tests/megascans/run.luau`. The Megascans sets come from the generated
    5  -- config/MegascansMaterials.luau (docs/environment/megascans.md); every
    6  -- entry is checked here before MaterialUtil turns it into a PbrSet, so a damaged or
    7  -- hand-edited file drops that entry instead of breaking the Materials stage.
   22  -- the fields every set has, whatever its base material type
   38  -- One generated entry, field by field. Returns the entry, or nil and the reason.
   82  -- The valid entries of a loaded list, plus one line per entry dropped. A list that is
   83  -- not a table gives no entries.
  105  -- base followed by the extra sets whose names base does not already use.
  122  -- replaced set name -> the set that stands in for it (the first claim wins).
  134  -- The set to use for a requested name: its stand-in when that one is registered, else
  135  -- the name itself, so a missing Megascans variant falls back to the original set.
  144  -- base material -> the set that overrides it: the last registered set asking for it,
  145  -- so a Megascans set (listed after the project's own) takes over an override only
  146  -- once its variant has actually arrived.
```

## src/shared/util/MaterialUtil.luau

```
   19  -- a set this one stands in for: apply(part, replaces) uses this set once registered
  126  -- the 2026-09-29 variants for the environment pass (docs/world/environment.md); the
  127  -- studs per tile match their declarations in default.project.json
  195  -- Megascans sets (docs/environment/megascans.md) from config/MegascansMaterials.luau,
  196  -- generated by scripts/sync_configs.py from the manifest (asset ids and settings only; the
  197  -- Fab files are never committed). Each entry is checked; an empty list, a bad entry or an
  198  -- unreadable module leaves the sets above as all there is.
  250  -- MaterialVariant.BaseMaterial is a plugin-capability property, so a runtime script
  251  -- cannot build these. They ship as instances declared under MaterialService in
  252  -- default.project.json; this pass only records which ones actually arrived.
  268  -- the last registered set asking for a base material's override gets it, so a
  269  -- Megascans set takes over from the built-in one only once its variant is there
```

## src/shared/util/MeshTemplates.luau

```
    3  -- Real MeshParts for templates mounted by Rojo.
    4  --
    5  -- A MeshPart that Rojo writes (live sync or a model.json) carries its MeshId but not the
    6  -- mesh's native size (MeshSize reads 0,0,0), and Roblox then draws the mesh at its native
    7  -- size instead of stretching it to Size. Measured 2026-09-28: the M4A1 meshes are
    8  -- natively about a fifth of their part size, so the rifle rendered as a toy under
    9  -- oversized arms, and the arm and zombie meshes were drawn 1/SCALE too large.
   10  --
   11  -- AssetService:CreateMeshPartAsync returns a MeshPart with the native size filled in, so
   12  -- each distinct MeshId is loaded once through it and every later use clones that part
   13  -- and copies the template's properties and children (SurfaceAppearance) onto it.
   14  -- `clone` never yields: while a mesh is still loading it hands back a plain clone of the
   15  -- template, so callers should `prefetch` early and `waitFor` where they can yield.
   66  -- Starts loading every MeshPart under `root` (or `root` itself). Does not yield.
   77  -- Yields until every MeshPart under `root` has loaded or failed, or `timeout` passes.
   97  -- A copy of `template` backed by a correctly sized mesh when one is loaded.
  119  -- Replaces every MeshPart directly under `model` with a correctly sized copy.
```

## src/shared/util/RunEconomyMath.luau

```
    3  -- The pay table arithmetic of the run economy (RunEconomy on the server): what a kill
    4  -- is worth, how a streak advances, what distance pays, and how a run balance is banked.
    5  -- Pure Luau with no requires: the config table comes in as an argument, so
    6  -- tests/economy/run.luau runs it under the standalone Luau CLI.
   25  -- The streak position of a kill at `now` given the previous kill's time and streak:
   26  -- 1 for the first kill or a kill after the window, else one more than before.
   34  -- The streak bonus at a streak position: nothing for the first kill, STREAK_STEP more
   35  -- per position after it, capped.
   40  -- Credits one kill pays: base by zombie id, headshot and streak bonuses, all scaled by
   41  -- the difficulty reward multiplier and floored so the balance stays whole credits.
   48  -- Credits the distance run so far is worth, the rate DistanceTracker always paid.
   53  -- The distance pay still owed once `banked` credits of it were banked earlier in the
   54  -- same run (a Continue keeps the distance): the whole distance's pay minus what was paid.
   59  -- The goal bonus not yet paid this run: the reward of every completed goal that is not
   60  -- in `paid`, and the paid set with those goals added, so a second death pays no goal twice.
   73  -- Spends `amount` of the run balance (a supply drop): the kill half goes first, the
   74  -- rest comes out of the distance half and counts as banked distance pay, since the
   75  -- distance itself stays and must not pay for it again. Returns whether it could, the
   76  -- balance after and the new distanceBanked.
   90  -- The one number the HUD shows: kill pay plus distance pay.
   95  -- Banking: what goes to the profile and the empty balance the run continues with.
   96  -- Nothing earned is ever lost, whatever ended the run.
```

## src/shared/util/SoldierBody.luau

```
    3  -- The soldier body: turns a stock R15 character (Roblox's block body) into the Mixamo
    4  -- soldier split by tools/character_rig/soldier.py. Every body part is swapped for the
    5  -- soldier's mesh (ReplicatedStorage.CharacterMeshes.Soldier through MeshTemplates), the
    6  -- rig attachments and Motor6D joints move to the soldier's pivots (SoldierRigConfig), and
    7  -- the Humanoid takes the soldier's hip height. Joint frames stay axis-aligned and the rest
    8  -- pose keeps the arms hanging straight down, so every R15 clip plays unchanged.
    9  --
   10  -- The server runs it once on a fresh R15 model to make StarterPlayer.StarterCharacter
   11  -- (SoldierCharacter); the yard's mannequins clone the local character and inherit it.
   12  -- Nothing changes while SoldierRigConfig.ready is false (mesh ids not read back yet).
   21  -- set on the character once converted
   23  -- on each hand: the fist's centre relative to the hand part, read by WorldWeaponModel
   26  -- the uniform tint keeps this much of the skin colour (the rest is white, no tint)
   40  -- Yields until the soldier meshes are loaded (or `timeout`); false when unavailable.
   68  -- Converts `character` in place. Returns false (and changes nothing) when the soldier is
   69  -- unavailable or the character is not a complete R15 rig.
  125  -- the block face, and cages that no longer match the mesh
  176  -- Tints the uniform: torso parts by `torso`, leg parts by `legs` (hue kept, brightness
  177  -- from the texture). Head and arms keep their gear colours.
```

## src/shared/util/Spring.luau

```
    3  -- Semi-implicit Euler spring integrator.
    4  -- An underdamped spring given an impulse overshoots its target and settles with a
    5  -- decaying wobble: Spring.number(120, 12, 0) with :Impulse(10) rises past 0, crosses
    6  -- back, and converges to 0 within roughly a second. Critical damping is damping =
    7  -- 2 * sqrt(stiffness); values below that overshoot, values above crawl in.
   30  -- integration step cap; nil is MAX_STEP (see Spring.vector)
  121  -- `maxStep` caps the integration step. At the default 1/30 an impulse loses most of its
  122  -- velocity to the damping term in the first step, so the response depends on the frame
  123  -- rate (a recoil kick peaks at 0.86 degrees at 60 fps and 0.26 at 15). Springs driven by
  124  -- impulses that must feel the same at any frame rate pass a small step such as 1/240.
```

## src/shared/util/StanceMath.luau

```
    3  -- The rules behind stances, lean and the magazine check (wiki: Stances): the eased
    4  -- stance weights, the raise a shot from high or low ready waits for, the check's
    5  -- timing and readout, the lean's camera offset, viewmodel counter-pose and body roll,
    6  -- and the lean value on the wire. Pure Luau: no services, no engine types, no requires;
    7  -- tests/stances/run.luau. The state tables are updated in place, like the springs.
   64  -- the stance the key chose: "mid", "high" or "low"
   66  -- shown weights, 0..1, of the high and low ready poses and of the magazine check
   70  -- a raise in progress (a shot asked for the gun to come up)
   72  -- the gun stays up until then after a shot
   74  -- the magazine check: held, when it started, and whether R was let go already
  100  -- Poses ------------------------------------------------------------------------------
  118  -- The stance and check pose shown now: each pose at its weight, summed.
  124  -- Easing -----------------------------------------------------------------------------
  131  -- One frame toward the target, exponential at rateIn going up and rateOut coming down,
  132  -- landing exactly within a thousandth (as WallPullbackMath.ease).
  142  -- Stances ----------------------------------------------------------------------------
  144  -- The stance after `current` in the cycle (an unknown one goes back to the first).
  159  -- Whether the gun is up: no raise running and every weight at or under the threshold.
  165  -- Seconds a raise from the current weights takes for this class: each full-stance time
  166  -- scaled by how far in that stance is, the longest wins.
  172  -- A shot asks to leave. True when the gun is up (the stay-up timer restarts); otherwise
  173  -- the raise starts (or keeps running) and the shot has to wait for it. Either way the
  174  -- magazine check ends.
  190  -- Seconds until a raise in progress is done (0 when none runs).
  199  -- One frame. `suppressed` (a reload, the draw, an inspect playing) eases every pose out
  200  -- without changing the chosen stance.
  216  -- a released check ends once it has been shown for minShow
  226  -- the check replaces the stance while it is held
  237  -- Magazine check ---------------------------------------------------------------------
  239  -- R held this long: true once it is a check rather than a reload.
  253  -- R let go: the check ends now, or once it has been shown for minShow.
  266  -- A reload or a weapon change ends the check at once.
  272  -- Whether the count is on screen: only while the weapon is tipped far enough in.
  277  -- The text the check shows for `mag` rounds of `size`.
  297  -- Lean -------------------------------------------------------------------------------
  299  -- Hold mode: -1 left, 1 right, 0 none; with both keys down the one pressed last wins.
  311  -- Toggle mode: a press of the side already leaned to comes back, any other leans.
  319  -- How much of the lean's sideways offset fits: a wall hit at `hitDistance` (studs from
  320  -- the eye along the lean, nil when clear) keeps `wallMargin` from the camera.
  329  -- The camera's lean at `lean` (-1..1) with `room` of the offset available: sideways
  330  -- offset and drop in studs, roll in degrees with CFrame.Angles' sign (a lean right
  331  -- rolls the top of the view to the right, a negative Z angle).
  339  -- The viewmodel's counter-pose: back part of the camera's roll, a nudge toward the lean.
  353  -- The third-person waist roll in degrees (CFrame.Angles' sign, as the camera).
  358  -- On the wire: tenths, so a slow lean sends a handful of packets.
  363  -- The relay's check of a lean value: a finite number clamped to -1..1; anything else
  364  -- (an old client sending none) is 0. Visual only, never used for a game rule.
```

## src/shared/util/WallPullbackMath.luau

```
    3  -- The wall pull-back's rules (docs/gameplay/wall-pullback.md): from the distance the
    4  -- cast hit at to the blend the viewmodel aims for, the eased blend it shows, the pose
    5  -- at a blend, and whether the gun may fire. Pure Luau: no services, no engine types, no
    6  -- requires; tests/wallpullback/run.luau.
   34  -- The distance at and under which the gun is fully pulled back.
   44  -- The blend the hit asks for: 0 with nothing within the reach, 1 at or under the full
   45  -- distance, smooth in between. `distance` nil means the cast hit nothing.
   57  -- One frame toward the target, exponential (so a jump in the target never pops the
   58  -- pose), in at EASE_IN and out at EASE_OUT; lands exactly within a thousandth.
   68  -- The pose at `blend` (0 the ready pose, 1 fully pulled back), each value scaled.
   82  -- Whether the gun may not fire: blocked once the hit is within the full distance (the
   83  -- muzzle would be inside the wall), released only when the hit is RELEASE_MARGIN beyond
   84  -- it or there is none. Partly pulled back, it fires.
```

## src/shared/util/WeaponLadderText.luau

```
    3  -- The Gunsmith row's description (docs/gameplay/goals-hud-and-ladder.md): the level
    4  -- ladder made visible, the damage now and the next level's damage gain, or the top of
    5  -- the ladder. No price: the row's button carries it, in the panel's one currency
    6  -- label. The row label holds about 42 RobotoMono characters before it truncates, and
    7  -- ShopGui appends " · XP n/need" to an owned row below max, so that text stays short. Pure Luau: no services, no engine types, no requires; the ladder
    8  -- (WeaponsConfig's MAX_LEVEL, UPGRADE_BASE_PRICE, UPGRADE_PRICE_STEP, DAMAGE_PER_LEVEL)
    9  -- and the weapon config come in as tables. tests/goals/run.luau.
   27  -- Whole when whole, else one decimal.
   44  -- `level` 0 for a weapon not owned (the dealer's row), else the profile's level. The
   45  -- name label already carries the weapon's name and "L2/5", so an owned row carries
   46  -- only the numbers behind them: "32.4 dmg · L3: +2.4 dmg".
```

## src/shared/util/WorldWeaponModel.luau

```
    3  -- The third-person gun: a five-part model welded to the right hand, built by the server
    4  -- (WorldWeapon) for every character and by the yard's body gallery for its mannequins.
    5  -- The grip part carries the sockets the body layer reads, all in grip space (x right, y
    6  -- up, -z along the barrel): GripSocket is where the right hand sits, SupportSocket,
    7  -- MagazineSocket, ChargeSocket, PortSocket and PumpSocket are where the support hand
    8  -- goes, Muzzle is the barrel end.
   19  -- the grip part relative to the right hand: in the fist, just past the hand's end along
   20  -- its -y (the fingers' way), the barrel along the forearm. It sat 0.9 studs out before
   21  -- (2026-09-30), which left the hand under the stock and the grip floating ahead of it
   22  -- once the body layer put the hands on the gun.
   25  -- A hand carrying this Vector3 attribute (the soldier body, SoldierBody.GRIP_ATTRIBUTE)
   26  -- has a modelled fist: the grip sits at that point of the hand instead, same rotation.
   34  -- The grip part relative to `hand`.
   40  -- Lengths along the barrel in studs: receiver, barrel, stock (0 for none). Sized to the
   41  -- default R15 body, whose arms reach about 1.8 studs from the shoulder joint across a
   42  -- chest 2 studs wide: the first rifle (receiver 2.1, stock 0.9) put its handguard 2.8
   43  -- studs ahead of the chest and its stock through it.
   88  -- The support hand's frame on the gun: the right hand's orientation rolled about the
   89  -- barrel, placed so the hand's fist (`supportGrip`, zero for a block hand) lands on
   90  -- `position`.
  125  -- Builds the gun for `config` on `character`'s right hand, replacing any previous one.
  126  -- Returns nil when the character has no hand yet.
  163  -- from the receiver's back end (0.24 behind the grip) rearwards
```

## src/shared/viewmodel_clips/PistolClips.luau

```
    2  -- GENERATED by tools/fps_pack/emit_luau.py from fps_pack_pistol.glb. Do not edit by hand.
    3  -- Tracks are base64 strings decoded by ViewmodelClipPlayer.
```

## src/shared/viewmodel_clips/RifleClips.luau

```
    2  -- GENERATED by tools/fps_pack/emit_luau.py from fps_pack_ak47.glb. Do not edit by hand.
    3  -- Tracks are base64 strings decoded by ViewmodelClipPlayer.
```

## src/shared/viewmodel_clips/SMGClips.luau

```
    2  -- GENERATED by tools/fps_pack/emit_luau.py from fps_pack_uzi.glb. Do not edit by hand.
    3  -- Tracks are base64 strings decoded by ViewmodelClipPlayer.
```

## src/shared/viewmodel_clips/ShotgunClips.luau

```
    2  -- GENERATED by tools/fps_pack/emit_luau.py from fps_pack_saps12.glb. Do not edit by hand.
    3  -- Tracks are base64 strings decoded by ViewmodelClipPlayer.
```

## src/shared/world/ChunkBudget.luau

```
    3  -- Per-chunk cost estimate against the desktop and mobile budgets. Pure Luau with no
    4  -- requires: the counts and the triangle tables (DressingConfig) come in as arguments,
    5  -- so the server counter (ChunkBudgetCounter) and the tests share the arithmetic.
   24  -- mesh instances per mesh name
   26  -- primitive parts per shape name (Block, Wedge, Cylinder, Ball)
   66  -- Names of the measures over the budget, in the table's order.
```

## src/shared/world/DressingPlanner.luau

```
    3  -- Decides where road dressing goes in a chunk. Pure Luau: no services, no engine types
    4  -- and no requires, so it runs under the standalone Luau CLI (tests/world/run.luau). The
    5  -- rules come in as the DressingConfig table; the server (WorldDressing) turns the
    6  -- placements into instances.
    7  --
    8  -- Inputs: the config, an Rng (Random fits), an occupancy object (ChunkOccupancy fits)
    9  -- and the loaded prop sizes. Coordinates are chunk-local: x across the road, z along
   10  -- it, the chunk spanning -halfLength..halfLength.
   14  -- The shapes below mirror DressingConfig's exported types.
   68  -- footprint x, footprint z, height, in studs
   72  -- 1-based index of the cluster within the chunk
   76  -- mesh name when one is loaded; nil means the primitive stand-in
   93  -- mesh names per group (WorldMeshConfig.groups)
   95  -- real size per loaded mesh name (WorldMeshes.naturalSize)
   97  -- 0..1, scales the clusters and the prop cap (a map transition dresses with both
   98  -- locations at their shares); nil is 1
  105  -- spots tried for a scattered member before it is dropped
  121  -- The zone's x range for this biome, with the biome's overrides applied.
  131  -- Picks a loaded mesh for the group, or nil with the fallback size.
  149  -- Axis-aligned footprint along x and z once the prop is turned by yaw.
  162  -- Centres a footprint inside the zone; a prop wider than the zone sits on its middle.
  186  -- keep the footprint inside the chunk; the neighbour chunk dresses its own ground
  206  -- the anchor always stays, so a cluster survives the mobile tier
  214  -- Places one recipe around (sign, anchorZ). Returns its placements, empty when the
  215  -- first member found no room (a cluster never ships without its anchor).
  239  -- the members follow each other along the road, long side along z
  244  -- each piece claims a circle, so the step clears two margins as well
  286  -- Picks a z for the next cluster on `sign` that keeps the spacing rules, or nil.
```

## src/shared/world/FogBudget.luau

```
    3  -- Ties each preset's visibility to chunk spawning and streaming, so a chunk is always
    4  -- replicated and fogged before it can be seen. Pure Luau; the constants come in as
    5  -- numbers (GameConstants on the server, literals in the tests).
   16  -- Problems with one preset, as sentences; empty when it is fine.
   28  -- Problems with the constants themselves, independent of any preset.
```

## src/shared/world/MapMath.luau

```
    3  -- The rules behind map segments (wiki: Map Segments): how long a map is in distance
    4  -- from its duration and the run speed expected there, the floor no map goes under, the
    5  -- fork options at a map's end (always two enabled neighbours), the blend alpha of the
    6  -- transition chunks and of a point in the transition zone, the crossfade gains, the
    7  -- vote lead once both options are pre-built, which maps' pools may be freed, and a
    8  -- check of the map table. Pure Luau: no services, no engine types, no requires;
    9  -- tests/world/run.luau.
   31  -- the fork's own geometry must fit inside the map: vote lead + divider + a start
   37  -- Speed and distance ---------------------------------------------------------------
   43  -- Studs per second `t` seconds into the run (the ramp is on the run's clock, as
   44  -- DistanceTracker's), never above maxSpeed.
   56  -- Distance covered from run time t0 for `seconds`: constant speed exactly, a ramp by
   57  -- 64 trapezoids (exact on each linear piece, within one step at the ramp's end or the
   58  -- cap).
   80  -- The floor no map goes under: the spawn distance plus the slower next option's
   81  -- warm-up at full speed, with the owner's factor; and never less than the fork itself.
   87  -- A map's length in whole chunks: the distance its duration covers at the speed
   88  -- expected there (starting `startTime` seconds into the run), at least the floor.
   95  -- A duration in the map's range from a 0..1 roll.
  101  -- Neighbours and forks -------------------------------------------------------------
  103  -- The neighbours a fork at this map's end may offer: enabled, existing, not itself.
  119  -- Two different neighbours from two rolls in 0..1 (the second drawn from the rest), or
  120  -- nil when fewer than two are enabled.
  132  -- The next sub-location of a map: any but the one just run when there is a choice.
  143  -- The start map for a lobby choice: the map itself, or for Random (or anything not
  144  -- runnable) one of the enabled maps from the roll.
  163  -- Transitions ----------------------------------------------------------------------
  165  -- The blend of the k-th chunk (0-based) of a map's transition: k+1 steps of n+1, so
  166  -- the first chunk is already a little of the new map and the last nearly all of it;
  167  -- nil outside the transition.
  175  -- Where a distance sits in the zone from `from` to `to` (0 before, 1 after), eased so
  176  -- the lighting starts and ends without a kink.
  185  -- Equal-power crossfade gains (old, new): the loudness holds through the middle.
  191  -- How far before the boundary the vote must close once both options' first chunks are
  192  -- pre-built: the spawner holds at the boundary, so the corridor's end has to stay out
  193  -- of sight (the widest fog, plus a chunk) while the held chunks are placed and reach
  194  -- the clients (settleSeconds at the top speed).
  199  -- The widest visibility of the presets a run can use (exempt ones left out).
  210  -- Pools ----------------------------------------------------------------------------
  212  -- Locations whose pools may be freed when the map at `history[#history]` becomes
  213  -- current: those of maps two or more steps behind that neither the previous map, the
  214  -- current one nor a fork option still uses.
  245  -- Checks ---------------------------------------------------------------------------
  247  -- Every problem with the map table, as lines: unknown neighbours or locations, enabled
  248  -- maps without two enabled neighbours (a fork needs two) or without locations, one-way
  249  -- neighbours between enabled maps, durations out of order.
```

## src/shared/world/PickupPlanner.luau

```
    3  -- Decides which pickup scene a chunk gets and where (docs/gameplay/weapon-pickups.md).
    4  -- Pure Luau: no services, no engine types, no requires, so it runs under the standalone
    5  -- Luau CLI (tests/pickups/run.luau). The rules come in as the PickupScenesConfig table
    6  -- and the randomness as an Rng (Random fits) the server seeds from the run seed and the
    7  -- chunk index, so the same run puts the same scenes in the same places for everyone.
    8  --
    9  -- Coordinates are chunk-local: x across the road (the playable band is
   10  -- -halfWidth..halfWidth), z along it (-halfLength..halfLength). Every placement comes
   11  -- with a few candidate spots in order; the server takes the first one that is free of
   12  -- the chunk's props.
   22  -- radians, the scene's yaw (its -z faces the road)
   27  -- "Scene" or "Drop"
   68  -- Picks from `order` by `weights` with one unit random in [0, 1): the first id whose
   69  -- cumulative weight passes it. Zero and missing weights never win; nil when nothing can.
   94  -- The scene ids allowed in `biome`, in config order.
  106  -- One scene for `biome`, weighted, or nil when none is allowed there.
  119  -- The weapon a supply drop gives, from the weighted table.
  129  -- CFrame.Angles(0, yaw, 0) looks along (-sin yaw, 0, -cos yaw): the right shoulder
  130  -- (x > 0) looks toward -x, the left toward +x
  136  -- tries at a lane spot clear of every scene candidate before the spot is given up
  148  -- A lane spot at least SCENE_DROP_GAP along the road from every z in `avoid` (all the
  149  -- scene's candidates, since the server may use any of them), or nil when none of the
  150  -- tries lands clear.
  165  -- The placements for chunk `chunkIndex` of `biome`: at most one scene and one supply
  166  -- drop, the scene with `CANDIDATES` spots, the drop with up to that many (each clear
  167  -- of every scene candidate). Nothing before START_CLEARANCE_CHUNKS.
```

## src/shared/world/PrebuiltMapMath.luau

```
    3  -- Pure helpers for PrebuiltMaps (no services, no engine types), tested by
    4  -- `luau tests/cityimport/run.luau`: checking a generated layout module, where each mesh
    5  -- goes, what its collision hint means, and the budget line per cell and per map.
   37  -- the CollisionFidelity item name, nil for none
   55  -- ground, roads and terrain (meshes wider than a cell): Roblox's own decomposition
   56  -- when near-planar, the precise one where there is relief
   65  -- Every problem with a loaded layout module, as lines; empty when it is usable.
  111  -- A point of the scene (studs) placed by the map entry: turned by yaw degrees about Y
  112  -- (the same turn as CFrame.Angles(0, yaw, 0)), then moved to the origin.
  120  -- Where a mesh's centre goes: the cell's position plus the mesh's offset, placed.
  134  -- Names in the cell's layout that the loaded asset does not have.
  178  -- One line in the chunk reports' style: "[Prebuilt city c_p000_p000] meshes 12/60 (m 30)
  179  -- tris 31k/120k (m 50k) textures 4/12 (m 6)", plus the measures over either budget.
```

## src/shared/world/UpgradeStationMath.luau

```
    3  -- The upgrade station's arithmetic (docs/gameplay/upgrade-station.md): the quote for
    4  -- the carried weapon's next level off the WeaponsConfig ladder, and where the stations
    5  -- stand along the run. Pure Luau: no services, no engine types, no requires, so it runs
    6  -- under the standalone Luau CLI (tests/upgrade/run.luau); the ladder and the station
    7  -- config come in as tables, the randomness as an Rng (Random fits).
   18  -- the level bought when ok
   48  -- the run distance at the chunk's near end
   54  -- The price of the next level from `level` (the same ladder the Gunsmith uses).
   59  -- The damage multiplier the level gives over the weapon's base.
   64  -- The quote for a weapon at `level`: the level bought and its price, or the refusal.
   65  -- `balance` is the run balance; nil skips the affordability check (the prompt text).
   78  -- Whether the chunk spanning [chunkStart, chunkStart + length) gets a station: it is
   79  -- in a station biome, past the start clearance, and its span crosses a multiple of
   80  -- SPACING_STUDS (each multiple lands in exactly one chunk).
   99  -- CFrame.Angles(0, yaw, 0) looks along (-sin yaw, 0, -cos yaw): the right shoulder
  100  -- (x > 0) looks toward -x, the left toward +x
  106  -- The candidate spots of the chunk's station, in order, or none when the chunk has
  107  -- no station.
```
