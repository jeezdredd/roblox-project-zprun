--!strict

local WallPullbackConfig = {}

WallPullbackConfig.reach = {
	Pistol = 2.2,
	SMG = 2.7,
	Shotgun = 3.2,
	Rifle = 3.4,
} :: { [string]: number }
WallPullbackConfig.REACH_DEFAULT = 3

WallPullbackConfig.FULL_SHARE = 0.45

WallPullbackConfig.CAST_RADIUS = 0.2
WallPullbackConfig.RESPECT_CAN_COLLIDE = true

WallPullbackConfig.EASE_IN = 14
WallPullbackConfig.EASE_OUT = 9

WallPullbackConfig.RELEASE_MARGIN = 0.15

WallPullbackConfig.pose = {
	back = 0.32,
	down = 0.06,
	aside = 0.05,
	pitchUp = 28,
	yawAside = 16,
	roll = 10,
}

return WallPullbackConfig
