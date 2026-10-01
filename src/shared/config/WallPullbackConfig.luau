--!strict

-- The first-person weapon pulling back near walls (docs/gameplay/wall-pullback.md),
-- after Modern Warfare 2019: a short cast from the camera along the aim each frame;
-- the closer the hit inside the weapon's reach, the further the pack viewmodel
-- retracts toward the chest and tilts up and aside. Fully pulled back, the gun does
-- not fire until the muzzle clears. Data only, no engine types: the pure
-- WallPullbackMath and its tests read it under the standalone Luau CLI. Distances are
-- studs in the world; the pose is in the viewmodel's hold space (the pack rigs are at
-- ViewmodelPackConfig.RIG_SCALE, so its offsets are small), angles in degrees.

local WallPullbackConfig = {}

-- How far ahead of the eye the weapon reaches in the world, per weapon class: about
-- the third-person gun's length plus the arm (WorldWeaponModel's receiver, barrel and
-- stock, Rifle 3.3 studs end to end). Anything nearer than this starts the pull-back.
WallPullbackConfig.reach = {
	Pistol = 2.2,
	SMG = 2.7,
	Shotgun = 3.2,
	Rifle = 3.4,
} :: { [string]: number }
WallPullbackConfig.REACH_DEFAULT = 3

-- Fully pulled back when the hit is within this share of the reach (the muzzle would be
-- in the wall even with the gun drawn in); in between, smoothly partway.
WallPullbackConfig.FULL_SHARE = 0.45

-- The cast: a thin sphere so a doorway's edge or a lamp post catches it, not only a
-- surface dead ahead. Parts that cannot be collided with (foliage, decals, glass
-- panes set non-colliding) do not pull the gun back.
WallPullbackConfig.CAST_RADIUS = 0.2
WallPullbackConfig.RESPECT_CAN_COLLIDE = true

-- Easing, per second (exponential, frame-rate independent): in a little faster than out,
-- so a wall is answered at once and the gun comes back without a snap.
WallPullbackConfig.EASE_IN = 14
WallPullbackConfig.EASE_OUT = 9

-- Firing: blocked once the hit is inside the full share, released only when it is
-- this many studs beyond it (or nothing is hit), so the edge does not flicker.
WallPullbackConfig.RELEASE_MARGIN = 0.15

-- The fully pulled-back pose, in the hold space (x right, y up, +z toward the chest):
-- drawn back and a little down, the muzzle tilted up and turned aside, a slight cant.
WallPullbackConfig.pose = {
	back = 0.32,
	down = 0.06,
	aside = 0.05,
	pitchUp = 28,
	yawAside = 16,
	roll = 10,
}

return WallPullbackConfig
