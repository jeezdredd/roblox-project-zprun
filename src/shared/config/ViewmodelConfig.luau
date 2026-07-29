--!strict

export type SpringSetting = {
	stiffness: number,
	damping: number,
}

local ViewmodelConfig = {}

ViewmodelConfig.BASE_OFFSET = CFrame.new(0.62, -0.62, -1.55)

ViewmodelConfig.FILL_LIGHT = {
	enabled = true,
	brightness = 1.4,
	range = 9,
	color = Color3.fromRGB(255, 246, 226),
}

ViewmodelConfig.springs = {
	sway = { stiffness = 90, damping = 13 },
	lag = { stiffness = 120, damping = 18 },
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
} :: { [string]: SpringSetting }

ViewmodelConfig.sway = {
	yawImpulse = 26,
	pitchImpulse = 20,
	maxImpulse = 0.9,
	positionScale = Vector3.new(1.6, 1.1, 0.3),
}

ViewmodelConfig.lag = {
	frames = 4,
	rotationScale = 0.55,
}

ViewmodelConfig.bob = {
	horizontal = 0.055,
	vertical = 0.07,
	roll = 0.035,
	pitch = 0.02,
	speedReference = 16,
}

ViewmodelConfig.breathe = {
	amplitude = 0.014,
	rollAmplitude = 0.008,
	rate = 1.4,
}

ViewmodelConfig.tilt = {
	roll = 0.09,
	lateralShift = 0.07,
}

ViewmodelConfig.impact = {
	landScale = 0.006,
	maxLand = 0.5,
	jukeScale = 0.35,
}

ViewmodelConfig.sprint = {
	position = Vector3.new(-0.25, -0.18, 0.12),
	rotation = Vector3.new(-0.16, 0.28, -0.12),
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
	positionScale = 0.35,
	rotationScale = 0.4,
}

ViewmodelConfig.MODE = {
	reload = "procedural",
	inspect = "procedural",
	equip = "procedural",
}

function ViewmodelConfig.spring(id: string): SpringSetting
	return ViewmodelConfig.springs[id] or { stiffness = 100, damping = 15 }
end

return ViewmodelConfig
