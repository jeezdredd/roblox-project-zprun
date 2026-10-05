--!strict

-- Weapon stances, manual lean and the magazine check for the first-person rig
-- (wiki: Stances), in the tactical-shooter style: a key cycles the carry between mid
-- (the normal hip pose), high ready (muzzle up) and low ready (muzzle down); a shot from
-- high or low ready first brings the gun up, over a time per class; Q and E lean the
-- camera with a counter-pose on the viewmodel and a lean of the third-person upper body;
-- holding R checks the magazine instead of reloading. All visual: the server's rules are
-- unchanged. Data only, no engine types: the pure StanceMath and its tests read it under
-- the standalone Luau CLI.
--
-- Poses are in the pack viewmodel's hold space (the channel WallPullback uses): x right,
-- y up, +z toward the chest, in the pack rigs' small units (ViewmodelPackConfig.RIG_SCALE);
-- angles in degrees, with the signs of CFrame.Angles: pitch > 0 lifts the muzzle,
-- yaw > 0 turns it left, roll > 0 cants the top to the left.

local StanceConfig = {}

-- Keys (Enum.KeyCode item names). Q was the loadout quick swap; it moved to the mouse
-- wheel. E is also the ProximityPrompt key: while a prompt is on screen E does not lean.
StanceConfig.keys = {
	stance = "X",
	leanLeft = "Q",
	leanRight = "E",
	reload = "R",
}

-- The stance key steps through this order (from mid: high ready, then low ready).
StanceConfig.CYCLE = { "mid", "high", "low" }

-- The poses, full strength. Mid is the class's own hold, so it is all zero.
StanceConfig.poses = {
	mid = { aside = 0, up = 0, back = 0, pitch = 0, yaw = 0, roll = 0 },
	high = { aside = -0.02, up = 0.05, back = 0.1, pitch = 42, yaw = 8, roll = 12 },
	low = { aside = -0.03, up = -0.1, back = 0.04, pitch = -32, yaw = 14, roll = 10 },
}

-- Easing between stances, per second (exponential, frame-rate independent, as
-- WallPullback): into a stance a little slower than out of it.
StanceConfig.EASE_IN = 9
StanceConfig.EASE_OUT = 12

-- A shot from high or low ready raises the gun first, over this many seconds from the
-- full stance (less when the stance is only partly in); the shot leaves when it is up.
StanceConfig.raiseTime = {
	Pistol = { high = 0.1, low = 0.12 },
	SMG = { high = 0.13, low = 0.16 },
	Rifle = { high = 0.17, low = 0.21 },
	Shotgun = { high = 0.19, low = 0.24 },
}
StanceConfig.RAISE_DEFAULT = { high = 0.16, low = 0.2 }

-- After the last shot the gun stays up this long, then eases back to the chosen stance.
StanceConfig.RETURN_AFTER = 1.4

-- A stance weight at or under this counts as up (the gun may fire).
StanceConfig.UP_THRESHOLD = 0.04

-- Manual lean. "hold": lean while the key is down; "toggle": a press leans, the same key
-- again comes back, the other key leans the other way.
StanceConfig.LEAN = {
	mode = "hold",
	-- the camera: sideways offset (studs), a small drop, and the roll toward the lean
	offset = 1.05,
	drop = 0.12,
	roll = 13,
	-- easing rates, per second
	easeIn = 10,
	easeOut = 12,
	-- the viewmodel rolls with the camera; this share of the roll is taken back so the
	-- gun cants less than the view, and it shifts a little toward the lean
	viewmodelCounterRoll = 0.55,
	viewmodelAside = 0.025,
	-- the camera stops short of a wall at the side: a sphere of this radius is cast from
	-- the eye along the lean, and the offset keeps this margin from what it hits
	castRadius = 0.35,
	wallMargin = 0.25,
	-- the third-person upper body: degrees of waist roll at a full lean
	bodyRoll = 16,
}

-- Hold R. Released before holdTime: a reload (on release). Held past it: the magazine
-- check, for at least minShow seconds; the count shows once the tilt is nearly in.
StanceConfig.MAG_CHECK = {
	holdTime = 0.3,
	minShow = 0.9,
	easeIn = 8,
	easeOut = 11,
	-- the count appears at this share of the pose, disappears under it
	showAt = 0.8,
	-- a shot during the check brings the gun back first, over this many seconds
	raiseTime = 0.14,
	-- "exact": "27 / 30"; "estimate": Full, Almost full, About half, Almost empty, Empty
	readout = "exact",
	-- hide the bottom-right ammo counter outside a check (magazine-check-only ammo)
	hideAmmoCounter = false,
	-- the weapon tipped toward the camera: magazine side turned to the eye
	pose = { aside = -0.05, up = 0.03, back = 0.09, pitch = 12, yaw = 18, roll = 38 },
}

return StanceConfig
