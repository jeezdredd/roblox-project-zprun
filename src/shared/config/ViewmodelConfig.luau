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
ViewmodelConfig.BASE_OFFSET = CFrame.new(0.38, -0.80, -2.5)

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

-- recoilRot holds the angular kick in radians. The raw spring peak is around 2.3 degrees
-- for the rifle, which is the right order of magnitude for a viewmodel but too much for
-- a sidearm and far too little for the shotgun, so the trim is per class instead of the
-- single hard-coded constant that used to sit in the render path.
ViewmodelConfig.RECOIL_ROTATION_SCALE_DEFAULT = 0.30

ViewmodelConfig.recoilRotationScale = {
	Pistol = 0.30,
	SMG = 0.22,
	Rifle = 0.28,
	Shotgun = 0.45,
} :: { [string]: number }

function ViewmodelConfig.recoilRotScale(class: string): number
	return ViewmodelConfig.recoilRotationScale[class] or ViewmodelConfig.RECOIL_ROTATION_SCALE_DEFAULT
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
	aim = { stiffness = 28, damping = 10 },
	drift = { stiffness = 14, damping = 6 },
} :: { [string]: SpringSetting }

ViewmodelConfig.hipAim = {
	range = 70,
	coneDegrees = 42,
	maxYawDegrees = 24,
	maxPitchDegrees = 14,
	hold = 0.35,
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
