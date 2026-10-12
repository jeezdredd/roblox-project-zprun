# Wall Pullback

The first-person weapon drawing in near walls, after Modern Warfare 2019. Branch
`cloud/wall-pullback` (2026-10-01); details and the Studio checks in
`docs/gameplay/wall-pullback.md`. Stage 4 of the quality pass in [[Roadmap]].

## Files

| File | Role |
| --- | --- |
| `src/shared/config/WallPullbackConfig.luau` | Reach per class, full share, cast radius, easing, release margin, the full pose |
| `src/shared/util/WallPullbackMath.luau` | Pure: reach, target blend from the hit distance, easing, the pose at a blend, the fire block. `luau tests/wallpullback/run.luau` |
| `src/client/systems/WallPullback.luau` | The spherecast along the aim, the eased blend, the pose, `blocksFire` |
| `PackViewmodel.setWallPose` | The pose on top of the class's `hold` |
| `Viewmodel.stepPack`, `WeaponController.tryFire` | Ask for the pose every frame; refuse a shot while fully pulled back |

## Rules

- Reach per class, sized to roughly the third-person gun plus the arm: Pistol 2.2,
  SMG 2.7, Shotgun 3.2, Rifle 3.4, default 3 studs.
- The cast is a 0.2-stud spherecast along the aim, so a doorway edge or a lamp post
  catches it, not only a surface dead ahead.
- Nothing within the reach: the gun is exactly where it was.
- The pull is smooth from the reach's edge to 45 percent of it (the full distance).
  Easing is exponential per second, in at 14 and out at 9, so a wall is answered at
  once and the gun comes back without a snap.
- Fully pulled back, no shot; partly pulled back, it fires. Server rules unchanged.
- The fire block has hysteresis: it starts once the hit is within the full distance
  and is released only when the hit is 0.15 studs (`RELEASE_MARGIN`) beyond it or
  nothing is hit, so the edge does not flicker.
- The block is trusted only while the viewmodel keeps asking for the pose every
  frame. One older than 0.25 s (`STALE_AFTER`) is stale, so the hub or death cannot
  leave the gun unable to fire.
- Ignores the local character, the viewmodel, zombies and their props, pickups and
  stations, casings, and anything not queryable or not collidable. Non-collidable
  parts are skipped through `RaycastParams.RespectCanCollide`, which follows
  `WallPullbackConfig.RESPECT_CAN_COLLIDE` (true); parts with `CanQuery` off are
  never hit at all.

## Units and pose

Reach and distances are world studs. The pose is in the viewmodel's hold space
(x right, y up, +z toward the chest), angles in degrees. Its offsets are small
because the pack rigs are at `ViewmodelPackConfig.RIG_SCALE`. The full pose: back
0.32, down 0.06, aside 0.05, pitch up 28, yaw aside 16, roll 10.
