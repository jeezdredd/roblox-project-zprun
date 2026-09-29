--!strict

-- Data for the third-person body layer (src/client/body, docs/animation/third-person-body.md):
-- where each weapon class sits in the hands, where the support hand goes for every
-- gesture, how the aim spreads over the joints, the recoil scale, the sprint pose, the
-- wire rate and the LOD bands. Frames are in the weapon's grip space unless named
-- otherwise: x right, y up, -z forward along the barrel, 1 stud = 0.28 m.

export type ClassSpec = {
	-- the grip part's CFrame in UpperTorso space with the aim level
	hold: CFrame,
	-- support (left) hand position in grip space for the two-handed hold, and its roll
	support: Vector3,
	supportRoll: number,
	-- where the support hand goes for the magazine, the chambering action and the pump
	-- (grip space); a class without a socket leaves it nil
	magazine: Vector3,
	charge: Vector3?,
	port: Vector3?,
	pump: Vector3?,
	-- "bolt": the support hand racks at the charge socket; "slide": the weapon itself is
	-- pulled back (a pistol slide release, thumb work)
	chargeStyle: string,
	-- studs the charge or pump stroke travels back along +z
	chargePull: number,
	pumpTravel: number,
	-- offset multiplied onto the hold in a sprint and at the start of the draw
	sprint: CFrame,
	lowered: CFrame,
	-- recoil scale on WeaponsConfig recoilKick (studs) and recoilSnap (degrees)
	kickFactor: number,
	snapFactor: number,
	-- seconds of the chambering action inside an empty reload, and of the pump stroke
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

-- how the aim pitch splits over waist, neck and arms, the yaw over waist and neck
ThirdPersonConfig.AIM = {
	waistPitch = 0.35,
	neckPitch = 0.25,
	armPitch = 0.4,
	waistYaw = 0.55,
	neckYaw = 0.45,
	pitchClamp = 70,
	yawClamp = 60,
	-- time constants of the approach: remote characters smooth the 20 Hz packets, the
	-- local character in the yard follows its own camera
	smoothing = 0.08,
	localSmoothing = 0.03,
	-- the arms pitch about this point of the UpperTorso (between the shoulders)
	pivot = Vector3.new(0, 0.5, 0),
}

ThirdPersonConfig.REPLICATION = {
	sendInterval = 0.05,
	keepalive = 1,
	minChange = 1,
	pitchLimit = 89,
	yawLimit = 179,
	-- the relay drops packets closer together than this from one player
	relayInterval = 0.045,
}

ThirdPersonConfig.RECOIL = {
	-- WeaponsConfig.recoilSnap is a unitless kick; this many degrees per unit
	snapDegrees = 12,
	-- share of the snap that pitches the waist
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
	-- IK weight while the draw starts (the gun is still coming up)
	equipWeight = 0.3,
}

ThirdPersonConfig.GESTURES = {
	-- the support hand's belt position in UpperTorso space (magazines and shells come
	-- from here)
	belt = CFrame.new(-0.55, -0.95, -0.15) * CFrame.Angles(math.rad(-60), math.rad(10), math.rad(35)),
	-- seconds after a shot before the pump stroke starts
	pumpDelay = 0.12,
	-- return to the grip after a cancelled reload
	cancelReturn = 0.2,
}

ThirdPersonConfig.lod = {
	desktop = { full = 60, half = 150, quarter = 300, ikRange = 150, maxPerFrame = 6 },
	mobile = { full = 40, half = 100, quarter = 200, ikRange = 100, maxPerFrame = 4 },
} :: { [string]: LodProfile }

local function class(spec: ClassSpec): ClassSpec
	return spec
end

-- Starting values, tuned in the yard's body gallery (test plan items 1 and 2). The
-- WorldWeapon geometry: grip 0.7 tall at the origin, receiver 0.56 above it running
-- along z (2.1 long on long guns, 0.9 on the pistol), barrel beyond, magazine hanging
-- 0.2 above the grip line under the receiver's middle, handguard around z -2.2.
ThirdPersonConfig.classes = {
	Pistol = class({
		hold = CFrame.new(0.3, 0.45, -1.15) * CFrame.Angles(0, math.rad(-3), 0),
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
		hold = CFrame.new(0.3, 0.3, -0.95) * CFrame.Angles(0, math.rad(-4), 0),
		support = Vector3.new(0, 0.3, -1.25),
		supportRoll = -25,
		magazine = Vector3.new(0, -0.2, -0.95),
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
		hold = CFrame.new(0.32, 0.25, -0.9) * CFrame.Angles(0, math.rad(-6), 0),
		support = Vector3.new(0, 0.3, -1.95),
		supportRoll = -25,
		magazine = Vector3.new(0, -0.2, -0.95),
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
		hold = CFrame.new(0.32, 0.25, -0.9) * CFrame.Angles(0, math.rad(-6), 0),
		support = Vector3.new(0, 0.3, -1.95),
		supportRoll = -25,
		magazine = Vector3.new(0, 0.05, -0.6),
		charge = nil,
		port = Vector3.new(0, 0.05, -0.6),
		pump = Vector3.new(0, 0.3, -1.95),
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
