# Wall pull-back

Stage 4 of the quality pass (`wiki/project-zprun/Roadmap.md`, Weapons and ammunition:
"wall pull-back"). Reference: Modern Warfare 2019, where the weapon draws in toward the
chest and tilts up as the player walks into a wall, and will not fire while the muzzle
would be inside it.

## 1. The cast

Every frame the pack viewmodel steps, `WallPullback.update` casts a thin sphere
(`CAST_RADIUS` 0.2 studs) from the camera along the aim, as long as the held weapon's
reach (`WallPullbackConfig.reach`, per class):

| Class | Reach (studs) | Full pull-back at |
| --- | --- | --- |
| Pistol | 2.2 | 0.99 |
| SMG | 2.7 | 1.22 |
| Shotgun | 3.2 | 1.44 |
| Rifle | 3.4 | 1.53 |

The reach is about the third-person gun plus the arm (`WorldWeaponModel`'s lengths); the
pack viewmodels are drawn at `RIG_SCALE` 0.4, so their own muzzle distance is not the
world's. A sphere rather than a ray catches a door frame's edge or a lamp post the aim
grazes.

Ignored: the local character, the camera (the viewmodel), the `Zombies` and
`ZombieProps` folders, `Pickups` (pickup scenes, drops and upgrade stations) and
`WeaponVfx` (casings and debris). Parts with `CanQuery` off are never hit by a cast;
parts with `CanCollide` off are skipped too (`RESPECT_CAN_COLLIDE`), so foliage,
decals and other walk-through dressing do not pull the gun in. That last rule goes a
step past the brief; it is one flag in the config.

## 2. Distance to pose

`WallPullbackMath` (pure, `luau tests/wallpullback/run.luau`):

- `targetFor`: 0 with nothing within the reach, 1 at or under `FULL_SHARE` (45 percent)
  of the reach, a smoothstep in between, so the pull starts gently at the reach's edge.
- `ease`: exponential toward the target, `EASE_IN` 14 per second in and `EASE_OUT` 9
  out, frame-rate independent, so a door opening or a wall appearing never pops the
  pose; it lands exactly.
- `poseAt`: the fully pulled-back pose scaled by the blend: drawn back 0.32 (toward the
  chest) and down 0.06, 0.05 aside, the muzzle pitched up 28 degrees, turned 16 degrees
  aside and canted 10 degrees, in the viewmodel's hold space.

The pose goes in through the same channel as the class's `hold`:
`PackViewmodel.setWallPose(rig, pose)` stores it and `PackViewmodel.step` places the rig
at `placement * hold * wallPose * eyeInverse`. Identity in the open, so a weapon away
from walls sits exactly where it did.

## 3. Firing

`WallPullbackMath.blocked`: fully pulled back (the hit within the full share, the muzzle
inside the wall) blocks firing; it releases only when the hit is `RELEASE_MARGIN` (0.15
studs) past that, or there is none, so the edge does not flicker. Partly pulled back the
gun fires. `WeaponController.tryFire` returns early while `WallPullback.blocksFire()`;
a block older than 0.25 s (the viewmodel stopped updating: hub, death) never holds.
The server's rules are unchanged: this only keeps the client from sending a shot that
leaves from inside a wall.

## 4. Tests

`luau tests/wallpullback/run.luau`: every class has a reach, the defaults; the blend
from the distance (nothing hit, at the reach, at and under full, monotone, smoothstep
at half, gentle at the edge); the easing (in and out without a pop, in faster than
out, landing, frame-rate independence, the clamp); the pose (ready, full, half, the
clamps); the fire block (partly pulled fires, fully pulled blocks, the release margin).

## 5. Studio check list

To be checked as motion (Development Policy section 2): frames at the recording's rate
while walking into a wall and back out, and around a shot fired just as the block
releases.

- **Walk into a wall** with the rifle: from about 3.4 studs the gun starts to draw in
  and tilt up, smoothly; against the wall it is fully in, the muzzle up and aside, with
  no clipping into the wall. Back away: it eases out with no snap.
- **Fire against the wall**: nothing fires, no tracer, no ammo spent; step back a little
  (partly pulled): it fires. A held trigger fires again as soon as the block releases.
- **Pistol**: the pull starts closer (2.2 studs).
- **Door frame**: walking through a doorway close to the frame pulls the gun in briefly.
- **Ignored**: zombies, the pickup scenes, a supply drop, an upgrade bench, ammo
  casings, corn walls and grass do not pull the gun in. A teammate standing right in
  front does (characters are not on the ignore list).
- **Hub and death**: no lingering block after a run (the 1 and 2 keys and firing in the
  yard still work).
