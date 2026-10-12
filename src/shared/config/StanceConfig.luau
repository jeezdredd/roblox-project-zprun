--!strict

local StanceConfig = {}

StanceConfig.keys = {
	stance = "X",
	leanLeft = "Q",
	leanRight = "E",
	reload = "R",
}

StanceConfig.CYCLE = { "mid", "high", "low" }

StanceConfig.poses = {
	mid = { aside = 0, up = 0, back = 0, pitch = 0, yaw = 0, roll = 0 },
	high = { aside = -0.02, up = 0.05, back = 0.1, pitch = 42, yaw = 8, roll = 12 },
	low = { aside = -0.03, up = -0.1, back = 0.04, pitch = -32, yaw = 14, roll = 10 },
}

StanceConfig.EASE_IN = 9
StanceConfig.EASE_OUT = 12

StanceConfig.raiseTime = {
	Pistol = { high = 0.1, low = 0.12 },
	SMG = { high = 0.13, low = 0.16 },
	Rifle = { high = 0.17, low = 0.21 },
	Shotgun = { high = 0.19, low = 0.24 },
}
StanceConfig.RAISE_DEFAULT = { high = 0.16, low = 0.2 }

StanceConfig.RETURN_AFTER = 1.4

StanceConfig.UP_THRESHOLD = 0.04

StanceConfig.LEAN = {
	mode = "hold",
	offset = 1.05,
	drop = 0.12,
	roll = 13,
	easeIn = 10,
	easeOut = 12,
	viewmodelCounterRoll = 0.55,
	viewmodelAside = 0.025,
	castRadius = 0.35,
	wallMargin = 0.25,
	bodyRoll = 16,
}

StanceConfig.MAG_CHECK = {
	holdTime = 0.3,
	minShow = 0.9,
	easeIn = 8,
	easeOut = 11,
	showAt = 0.8,
	raiseTime = 0.14,
	readout = "exact",
	hideAmmoCounter = false,
	pose = { aside = -0.05, up = 0.03, back = 0.09, pitch = 12, yaw = 18, roll = 38 },
}

return StanceConfig
