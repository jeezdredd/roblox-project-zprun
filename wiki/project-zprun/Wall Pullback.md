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

- Nothing within the reach: the gun is exactly where it was.
- The pull is smooth from the reach's edge to 45 percent of it, eased in and out.
- Fully pulled back, no shot; partly pulled back, it fires. Server rules unchanged.
- Ignores the local character, the viewmodel, zombies and their props, pickups and
  stations, casings, and anything not queryable or not collidable.
