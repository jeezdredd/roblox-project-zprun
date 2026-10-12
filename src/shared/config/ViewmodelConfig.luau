--!strict

export type SpringSetting = {
	stiffness: number,
	damping: number,
}

local ViewmodelConfig = {}

ViewmodelConfig.SCALE = 0.72

ViewmodelConfig.BASE_OFFSET = CFrame.new(0.52, -0.6, -1.75) * CFrame.Angles(math.rad(2), math.rad(6), 0)

ViewmodelConfig.CLASS_OFFSET = {
	Pistol = CFrame.new(0.34, -0.48, -1.3) * CFrame.Angles(math.rad(-4), math.rad(16), math.rad(-4)),
} :: { [string]: CFrame }

function ViewmodelConfig.baseOffset(class: string): CFrame
	return ViewmodelConfig.CLASS_OFFSET[class] or ViewmodelConfig.BASE_OFFSET
end

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

ViewmodelConfig.ARM_WRIST_BEND = {
	R = CFrame.identity,
	L = CFrame.identity,
} :: { R: CFrame, L: CFrame }

ViewmodelConfig.FILL_LIGHT = {
	enabled = true,
	disableAtNight = true,
	brightness = 0.35,
	range = 6,
	color = Color3.fromRGB(255, 246, 226),
}

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
