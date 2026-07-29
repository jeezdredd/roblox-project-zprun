# Prompt for the Roblox Studio Assistant — animatable weapon rigs

Paste the relevant block into the Studio Assistant (Plugins → Assistant). Written in English deliberately: the Assistant follows precise technical instructions more reliably in English than in Russian, even though it understands both.

Why every constraint below exists is recorded in [../../wiki/project-zprun/Decisions.md](../../wiki/project-zprun/Decisions.md) — each one was measured in Studio, not assumed.

---

## Shared rules (include these with either prompt)

```
RIGGING RULES — follow all of them exactly. These are hard requirements, not preferences.

1. AXES. The muzzle must point along -Z. Up is +Y. Width is X. Verify this before you
   finish: the barrel's centre must have a smaller Z than the stock's or grip's centre.

2. MOVABILITY DECIDES THE JOINT TYPE. A welded part cannot be animated; only a jointed
   part can. So:
     - Create an invisible hub part named exactly `Main`, size 0.1, 0.1, 0.1,
       Transparency 1, placed inside the grip where the hand holds the weapon.
     - Set `Main` as the model's PrimaryPart.
     - Weld `Main` to every part that never moves.
     - Use a Motor6D from `Main` to every part that must move during firing or
       reloading. Name each Motor6D after the part it drives.

3. NOTHING IS ANCHORED. Every part: Anchored = false, CanCollide = false,
   CastShadow = false, Massless = true. If you anchor anything, the rig cannot be
   animated or moved.

4. NAMES MUST BE UNIQUE AND EXACT. Two parts sharing a name breaks the Animation
   Editor. Never name a real geometry part `Muzzle` — that name is reserved for an
   invisible reference point.

5. DO NOT CREATE ANY SCRIPTS. No Script, LocalScript, ModuleScript, ClickDetector or
   RemoteEvent. Geometry, attachment points and joints only. A previous kit's scripts
   hijacked the camera and broke the game, so this is strictly enforced.

6. REFERENCE POINTS. Add these as invisible parts, size 0.1, 0.1, 0.1,
   Transparency 1, Anchored false, CanCollide false, welded to the part named after
   each one's location:
     - `Muzzle`        at the muzzle crown, welded to the barrel. -Z is forward.
     - `CasingEject`   at the ejection port, pushed slightly forward and above the
                       bore line so a spent case does not clip the receiver.
     - `AimPart`       at the rear sight notch, aligned down the sight line.

7. BUILD FROM PARTS, NOT MESHES, and get the proportions right. Nine well-proportioned
   Parts read as a real weapon; twenty badly proportioned ones read as a pile of boxes.
   Work from a side-view photograph of the real weapon. Colours: dark gunmetal around
   RGB 78,84,94 for steel, near-black RGB 40,40,44 for polymer. Do not use light greys
   — a slide at RGB 158,164,174 rendered as a white slab in our lighting.

8. WHEN DONE, report back: every part name with its size and its parent joint type
   (Weld or Motor6D), and confirm the muzzle points -Z.
```

---

## Prompt 1 — M4A1 rifle

The existing `Workspace.M4A1` is already correctly oriented and has usable mesh geometry, but its receiver is a single mesh with the bolt and charging handle baked in. That makes a real reload impossible: no bolt travel, no bolt-hold-open on an empty magazine. This prompt asks for the missing moving parts.

```
Build a rigged first-person M4A1 viewmodel named `M4A1_Rigged` in Workspace, following
the RIGGING RULES above.

Overall size: 2.58 studs long, 1.18 tall including the magazine, 0.34 wide. Keep these
dimensions — they are tuned to our first-person camera and must not be scaled up.

MOVING PARTS — each needs a Motor6D from `Main`:
  - `Magazine`         drops straight down out of the magazine well on reload
  - `Bolt`             travels rearward inside the receiver, roughly 0.35 studs of
                       travel, and must be able to hold in the rear position
  - `ChargingHandle`   on the upper right of the receiver, travels rearward with the
                       bolt
  - `Trigger`          pivots about its pin
  - `DustCover`        the ejection port cover, hinges open on the right side
  - `Selector`         the safety lever on the left side, rotates

STATIC PARTS — each welded to `Main`:
  - `LowerReceiver`, `UpperReceiver`, `Handguard`, `Barrel`, `MuzzleDevice`,
    `Stock`, `BufferTube`, `PistolGrip`, `TriggerGuard`, `MagRelease`,
    `RearSight`, `FrontSight`, `TopRail`

The bolt and charging handle are the point of this build: they must be genuinely
separate parts that can travel rearward, not decoration welded to the receiver.

ATTACHMENT MOUNTS — invisible 0.1 parts, Transparency 1, welded to the part they sit
on, for a gunsmith system to hang optics and muzzle devices from:
  - `MuzzleMount`      at the barrel crown
  - `SightMount`       on top of the upper receiver
  - `SideMountLeft`, `SideMountRight`  on the handguard sides
  - `UnderMount`       under the handguard, for a foregrip or light

Then report the part list as specified in rule 8.
```

---

## Prompt 2 — Glock 19 pistol

```
Build a rigged first-person Glock 19 viewmodel named `Glock19_Rigged` in Workspace,
following the RIGGING RULES above.

Overall size: 2.16 studs long, 1.10 tall including the magazine, 0.31 wide. Keep these
dimensions.

MOVING PARTS — each needs a Motor6D from `Main`:
  - `Slide`      travels rearward roughly 0.30 studs and must be able to hold in the
                 rear position for an empty magazine
  - `Magazine`   drops straight down out of the grip
  - `Trigger`    pivots about its pin

STATIC PARTS — each welded to `Main`:
  - `Frame`, `Barrel`, `TriggerGuard`, `GripPanelLeft`, `GripPanelRight`,
    `MagRelease`, `SlideStop`, `Backstrap`

SIGHTS — weld `FrontSight` and `RearSight` to `Slide`, NOT to `Main`. They sit on the
slide and must travel rearward with it. This is the most commonly missed detail.

ATTACHMENT MOUNTS — invisible 0.1 parts, Transparency 1:
  - `MuzzleMount`   at the muzzle crown, welded to `Frame`
  - `SightMount`    on top of the slide, welded to `Slide`

A Glock is a striker-fired pistol: it has no external hammer. Do not add one.

Then report the part list as specified in rule 8.
```

---

## What happens after the Assistant finishes

I verify numerically rather than by eye, because reading a screenshot has real error — especially side-on, where a support hand once read to me as a detached slide:

1. Every part's size, and its offset relative to `Main`.
2. Joint census: how many Motor6D, how many Weld, and that nothing is anchored.
3. That the muzzle really points -Z, by comparing the barrel's and stock's Z.
4. That no two parts share a name.
5. A screenshot from a fixed set of angles, including the player-camera view — that being the only angle a player ever sees.

Then the rig is captured into an `.rbxmx` that Rojo mounts, so it lives in git as text rather than only inside the place file.

## Animation, and the part only you can do

Clips have to be authored in the Animation Editor against the rig and then **published from your account**. A Roblox `Animation` asset only loads for the account or group that uploaded it — the kit's published clips return "Animation failed to load" with a track length of 0 for us, which I measured before relying on them. So I can build and verify the rig, and I can wire the ids, but the publishing step is yours.

Per weapon the set is: `Idle`, `Equip`, `Dequip`, `Fire`, `EmptyFire`, `Reload`, `ReloadEmpty`, `Inspect`. Looping stays off on all of them except `Idle`.

Keyframe markers for sound must be added **before** publishing, or they are not baked into the asset. Name them `MagOut`, `MagIn`, `BoltBack`, `BoltForward` — `WeaponSfx.playPhase` already listens for exactly those names.
