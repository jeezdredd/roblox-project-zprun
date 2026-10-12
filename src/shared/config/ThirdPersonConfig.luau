--!strict

export type ClassSpec = {
	hold: CFrame,
	support: Vector3,
	supportRoll: number,
	magazine: Vector3,
	charge: Vector3?,
	port: Vector3?,
	pump: Vector3?,
	chargeStyle: string,
	chargePull: number,
	pumpTravel: number,
	sprint: CFrame,
	lowered: CFrame,
	kickFactor: number,
	snapFactor: number,
	chargeTime: number,
	pumpTime: number,
}

export type LodProfile = {
	full: number,
	half: number,
	quarter: number,
	ikRange: number,
	maxPerFrame: number,
}

local ThirdPersonConfig = {}

ThirdPersonConfig.ENABLED = true

ThirdPersonConfig.AIM = {
	waistPitch = 0.35,
	waistYaw = 0.55,
	pitchClamp = 70,
	yawClamp = 60,
	chestStabilize = 0.6,
	headStabilize = 0.9,
	smoothing = 0.08,
	localSmoothing = 0.03,
	pivot = Vector3.new(0, 0.5, 0),
}

ThirdPersonConfig.REPLICATION = {
	sendInterval = 0.05,
	keepalive = 1,
	minChange = 1,
	pitchLimit = 89,
	yawLimit = 179,
	relayInterval = 0.045,
}

ThirdPersonConfig.RECOIL = {
	snapDegrees = 12,
	waistShare = 0.3,
}

ThirdPersonConfig.SPRINT = {
	speed = 36,
	hysteresis = 4,
	blendTime = 0.25,
	armPitchScale = 0.5,
}

ThirdPersonConfig.IK = {
	smoothTime = 0.04,
	fadeIn = 0.25,
	fadeOut = 0.15,
	deathFade = 0.15,
	equipWeight = 0.3,
	reachMargin = 0.95,
	maxGunSlide = 1,
	handGap = 0.3,
}

ThirdPersonConfig.GESTURES = {
	belt = CFrame.new(-0.55, -0.95, -0.15) * CFrame.Angles(math.rad(-60), math.rad(10), math.rad(35)),
	pumpDelay = 0.12,
	cancelReturn = 0.2,
}

ThirdPersonConfig.lod = {
	desktop = { full = 60, half = 150, quarter = 300, ikRange = 150, maxPerFrame = 6 },
	mobile = { full = 40, half = 100, quarter = 200, ikRange = 100, maxPerFrame = 4 },
} :: { [string]: LodProfile }

local function class(spec: ClassSpec): ClassSpec
	return spec
end

ThirdPersonConfig.classes = {
	Pistol = class({
		hold = CFrame.new(0.15, 0.45, -1.35),
		support = Vector3.new(-0.16, -0.32, 0.14),
		supportRoll = -40,
		magazine = Vector3.new(0, -0.55, -0.05),
		charge = nil,
		port = nil,
		pump = nil,
		chargeStyle = "slide",
		chargePull = 0.12,
		pumpTravel = 0,
		sprint = CFrame.new(-0.05, -0.45, 0.25) * CFrame.Angles(math.rad(-35), math.rad(10), 0),
		lowered = CFrame.new(0, -0.6, 0.15) * CFrame.Angles(math.rad(-50), 0, 0),
		kickFactor = 0.6,
		snapFactor = 1.2,
		chargeTime = 0.25,
		pumpTime = 0,
	}),
	SMG = class({
		hold = CFrame.new(0.1, 0.35, -1.1),
		support = Vector3.new(0, 0.25, -0.8),
		supportRoll = -25,
		magazine = Vector3.new(0, -0.2, -0.5),
		charge = Vector3.new(0, 0.85, 0.15),
		port = nil,
		pump = nil,
		chargeStyle = "bolt",
		chargePull = 0.3,
		pumpTravel = 0,
		sprint = CFrame.new(-0.15, -0.35, 0.25) * CFrame.Angles(math.rad(-40), math.rad(20), math.rad(15)),
		lowered = CFrame.new(0, -0.6, 0.2) * CFrame.Angles(math.rad(-50), 0, 0),
		kickFactor = 0.8,
		snapFactor = 0.9,
		chargeTime = 0.35,
		pumpTime = 0,
	}),
	Rifle = class({
		hold = CFrame.new(0, 0.35, -0.95),
		support = Vector3.new(0, 0.3, -1.45),
		supportRoll = -25,
		magazine = Vector3.new(0, -0.2, -0.7),
		charge = Vector3.new(0.3, 0.75, 0.35),
		port = nil,
		pump = nil,
		chargeStyle = "bolt",
		chargePull = 0.35,
		pumpTravel = 0,
		sprint = CFrame.new(-0.15, -0.35, 0.25) * CFrame.Angles(math.rad(-45), math.rad(20), math.rad(10)),
		lowered = CFrame.new(0, -0.6, 0.2) * CFrame.Angles(math.rad(-50), 0, 0),
		kickFactor = 1,
		snapFactor = 1,
		chargeTime = 0.4,
		pumpTime = 0,
	}),
	Shotgun = class({
		hold = CFrame.new(0, 0.35, -0.95),
		support = Vector3.new(0, 0.3, -1.55),
		supportRoll = -25,
		magazine = Vector3.new(0, 0.05, -0.5),
		charge = nil,
		port = Vector3.new(0, 0.05, -0.5),
		pump = Vector3.new(0, 0.3, -1.55),
		chargeStyle = "bolt",
		chargePull = 0,
		pumpTravel = 0.5,
		sprint = CFrame.new(-0.15, -0.35, 0.25) * CFrame.Angles(math.rad(-45), math.rad(20), math.rad(10)),
		lowered = CFrame.new(0, -0.6, 0.2) * CFrame.Angles(math.rad(-50), 0, 0),
		kickFactor = 1.3,
		snapFactor = 1.5,
		chargeTime = 0,
		pumpTime = 0.45,
	}),
} :: { [string]: ClassSpec }

function ThirdPersonConfig.getClass(name: string): ClassSpec?
	return ThirdPersonConfig.classes[name]
end

return ThirdPersonConfig
