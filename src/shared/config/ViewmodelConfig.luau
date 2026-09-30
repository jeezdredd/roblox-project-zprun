--!strict

export type SpringSetting = {
	stiffness: number,
	damping: number,
}

local ViewmodelConfig = {}

-- Whole-rig scale. Measured in Studio: at 1.0 the weapon filled 48% of screen
-- height, roughly double a normal first-person framing.
ViewmodelConfig.SCALE = 0.72

-- Tuned against measured screen coverage rather than by eye. At (0.42, -0.36, -2) the
-- mesh weapon sat with its slide at 43% of screen height, straddling the crosshair, and
-- the grip and magazine each covered a third of the frame. Lower and further out puts
-- the weapon in the bottom right where it belongs and leaves the sight line clear.
-- 2026-09-28: at (0.38, -0.80, -2.5) the rifle ran straight down the view axis and was
-- seen end-on, so only the stock and the hands were visible. Closer, further right and
-- turned a few degrees towards the centre shows the side of the weapon, the way a
-- first-person weapon normally reads.
ViewmodelConfig.BASE_OFFSET = CFrame.new(0.52, -0.6, -1.75) * CFrame.Angles(math.rad(2), math.rad(6), 0)

-- Per-class replacement for BASE_OFFSET. The pistol is a fifth of the rifle's length, so
-- at the rifle's distance it read as a toy held at arm's length between two huge
-- forearms; closer and nearer the centre it fills the frame the way a sidearm does.
ViewmodelConfig.CLASS_OFFSET = {
	Pistol = CFrame.new(0.34, -0.48, -1.3) * CFrame.Angles(math.rad(-4), math.rad(16), math.rad(-4)),
} :: { [string]: CFrame }

function ViewmodelConfig.baseOffset(class: string): CFrame
	return ViewmodelConfig.CLASS_OFFSET[class] or ViewmodelConfig.BASE_OFFSET
end

-- Mesh arms (ArmRigConfig, cut from a Mixamo soldier). ARM_GRIP places the hand frame
-- (fingers -Z, back of the hand +Y, origin on the grip axis) relative to the weapon's
-- HandRMount / HandLMount marker, per class; classes not listed use Rifle. ARM_WRIST_BEND
-- turns the forearm about the wrist. Both are tuned against Studio screenshots.
-- Right hand: palm against the pistol grip, index along the trigger, back of the hand to
-- the right, grip raked 18 degrees. Left hand: palm up under the handguard, fingers
-- round its right side, origin raised onto the handguard axis. From that base each hand
-- rolls about its grip axis and turns in the palm plane, and the wrist bends, so the
-- forearm runs back and down out of frame instead of lying across the screen. The angles
-- were solved for forearm directions of (0.35, -0.5, 0.8) right and (-0.55, -0.45, 0.7)
-- left in camera space, with the wrist kept under 30 degrees.
ViewmodelConfig.ARM_GRIP = {
	Rifle = {
		R = CFrame.Angles(math.rad(-18), 0, 0)
			* CFrame.fromMatrix(Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(1, 0, 0))
			* CFrame.Angles(math.rad(-24), 0, 0)
			* CFrame.Angles(0, math.rad(25.1), 0),
		L = CFrame.new(0, 0.18, 0)
			* CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(0, -1, 0))
			* CFrame.Angles(math.rad(-38.8), 0, 0)
			* CFrame.Angles(0, math.rad(-24.4), 0),
	},
	-- Two-handed pistol grip: the right hand as on the rifle, the left wrapped round the
	-- front of the grip over the right fingers, palm facing right, index under the guard.
	-- Solved for forearms of (0.25, -0.45, 0.85) right and (-0.35, -0.45, 0.82) left.
	Pistol = {
		R = CFrame.Angles(math.rad(-18), 0, 0)
			* CFrame.fromMatrix(Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(1, 0, 0))
			* CFrame.Angles(math.rad(-16), 0, 0)
			* CFrame.Angles(0, math.rad(21), 0),
		L = CFrame.Angles(math.rad(-18), 0, 0)
			* CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(-1, 0, 0))
			* CFrame.Angles(math.rad(-40), 0, 0)
			* CFrame.Angles(0, math.rad(-24), 0),
	},
} :: { [string]: { R: CFrame, L: CFrame } }

-- The wrist bend is baked into the arm meshes now (tools/arms_rig/build.py WRIST_BEND:
-- 28 degrees right, -26 left), so the hand and forearm meet without a crack at rest.
-- Anything set here turns the forearm on top of that.
ViewmodelConfig.ARM_WRIST_BEND = {
	R = CFrame.identity,
	L = CFrame.identity,
} :: { R: CFrame, L: CFrame }

-- A constant light welded to the weapon means the player is never actually in the dark.
-- Under the Night modifier that cancels the flashlight outright: the beam lands on
-- geometry that is already lit, so it reads as having no effect. The fill stays for
-- daylight framing and switches off whenever Workspace.NightMission is set.
ViewmodelConfig.FILL_LIGHT = {
	enabled = true,
	disableAtNight = true,
	brightness = 0.35,
	range = 6,
	color = Color3.fromRGB(255, 246, 226),
}

-- recoilRot holds the angular kick in radians. The raw spring peak per shot, from
-- WeaponsConfig's snap and spring, is rifle 1.26 degrees, SMG 0.59, pistol 0.98 and
-- shotgun 2.56 (the recoil springs integrate in 1/240 s steps, so this holds at any frame
-- rate). The AK and Uzi Fire clips barely move the gun, the pistol clip kicks it 8
-- degrees and the shotgun clip 34 (played at 45 %). The per-class scale sets the
-- viewmodel's pitch per shot near MW2019's hip fire: rifle 3 degrees, SMG 1.8 (at 11
-- rounds a second the kicks stack), pistol 1.5 over its clip, shotgun 2.5 over its clip.
-- Yaw and roll jitter scale with it.
ViewmodelConfig.RECOIL_ROTATION_SCALE_DEFAULT = 1

ViewmodelConfig.recoilRotationScale = {
	Pistol = 1.5,
	SMG = 3,
	Rifle = 2.4,
	Shotgun = 1,
} :: { [string]: number }

function ViewmodelConfig.recoilRotScale(class: string): number
	return ViewmodelConfig.recoilRotationScale[class] or ViewmodelConfig.RECOIL_ROTATION_SCALE_DEFAULT
end

-- The kick back per shot, over WeaponsConfig.recoilKick (which the third-person body reads
-- too): rifle 2.7 to 3.6 cm, SMG 1.4 to 1.8, pistol 2.2 to 1.8, shotgun 6.2 as it is.
ViewmodelConfig.recoilKickScale = {
	Pistol = 0.8,
	SMG = 1.3,
	Rifle = 1.35,
	Shotgun = 1,
} :: { [string]: number }

function ViewmodelConfig.recoilKick(class: string): number
	return ViewmodelConfig.recoilKickScale[class] or 1
end

ViewmodelConfig.springs = {
	sway = { stiffness = 130, damping = 22 },
	lag = { stiffness = 160, damping = 24 },
	movePos = { stiffness = 70, damping = 14 },
	moveRot = { stiffness = 60, damping = 13 },
	recoilPos = { stiffness = 190, damping = 20 },
	recoilRot = { stiffness = 210, damping = 19 },
	cameraRecoil = { stiffness = 150, damping = 17 },
	tiltRoll = { stiffness = 80, damping = 14 },
	impactPos = { stiffness = 110, damping = 15 },
	breathe = { stiffness = 26, damping = 9 },
	equip = { stiffness = 100, damping = 16 },
	mechanism = { stiffness = 320, damping = 22 },
	inspect = { stiffness = 55, damping = 12 },
	aim = { stiffness = 16, damping = 8 },
	drift = { stiffness = 14, damping = 6 },
} :: { [string]: SpringSetting }

-- 2026-09-29: in a recorded run the weapon swung up to 24 degrees every time the hip aim
-- picked a new zombie, which read as the viewmodel jerking about. The weapon now only
-- leans towards the target (10/6 degrees), holds a target longer before letting go, and
-- the aim spring below is softer.
ViewmodelConfig.hipAim = {
	range = 70,
	coneDegrees = 42,
	maxYawDegrees = 10,
	maxPitchDegrees = 6,
	hold = 0.6,
	blendRate = 4,
	centreBias = 0.8,
	rollCouple = 0.15,
	shift = 0.1,
	dip = 0.03,
	fireLock = 0.55,
}

ViewmodelConfig.drift = {
	amplitude = 0.012,
	rates = Vector3.new(0.9, 0.55, 0.7),
}

ViewmodelConfig.juke = {
	yaw = 0.16,
	roll = 0.22,
	shift = 0.12,
}

ViewmodelConfig.sway = {
	yawImpulse = 10,
	pitchImpulse = 8,
	maxImpulse = 0.35,
	positionScale = Vector3.new(0.5, 0.35, 0.1),
}

ViewmodelConfig.lag = {
	frames = 3,
	rotationScale = 0.22,
}

ViewmodelConfig.bob = {
	horizontal = 0.042,
	vertical = 0.05,
	roll = 0.028,
	pitch = 0.018,
	speedReference = 16,
}

ViewmodelConfig.breathe = {
	amplitude = 0.024,
	rollAmplitude = 0.014,
	rate = 1.4,
}

ViewmodelConfig.tilt = {
	roll = 0.035,
	lateralShift = 0.028,
}

ViewmodelConfig.impact = {
	landScale = 0.006,
	maxLand = 0.5,
	jukeScale = 0.35,
}

-- This is an endless runner: the player sprints for the whole run and has to shoot
-- while sprinting. A conventional sprint pose lowers and yaws the weapon out of the
-- fight, which measured 47 degrees off the crosshair and made hitting a zombie
-- impossible. Sprint here may express weight and movement, but the barrel has to stay
-- on target, so the yaw term in particular is kept near zero.
ViewmodelConfig.sprint = {
	position = Vector3.new(-0.10, -0.08, 0.06),
	rotation = Vector3.new(-0.05, 0.03, -0.04),
	blendRate = 5,
}

ViewmodelConfig.equip = {
	drop = 1.4,
	tilt = 0.7,
	duration = 0.35,
}

ViewmodelConfig.inspect = {
	position = Vector3.new(-0.18, 0.1, 0.35),
	rotation = Vector3.new(0.2, 0.9, 0.45),
	holdTime = 1.1,
}

ViewmodelConfig.mechanism = {
	slideTime = 0.16,
	pumpTime = 0.42,
	magDropTime = 0.26,
}

ViewmodelConfig.cameraRecoil = {
	pitch = 0.55,
	yawJitter = 0.08,
	stiffness = 70,
	damping = 17,
	fovKick = 0.25,
}

ViewmodelConfig.MODE = {
	reload = "procedural",
	inspect = "procedural",
	equip = "procedural",
	fire = "procedural",
	sprint = "procedural",
}

function ViewmodelConfig.usesClip(id: string, clipAvailable: boolean): boolean
	return clipAvailable and ViewmodelConfig.MODE[id] == "clip"
end

function ViewmodelConfig.spring(id: string): SpringSetting
	return ViewmodelConfig.springs[id] or { stiffness = 100, damping = 15 }
end

return ViewmodelConfig
