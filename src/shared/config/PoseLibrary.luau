--!strict

-- Authored viewmodel poses. Each pose is a table of bone name -> CFrame offset that
-- multiplies the bone's rest transform, so an empty table is the neutral pose.
--
-- Bone names come from ViewmodelBuilder: weaponRoot, slide, pump, magazine,
-- handR / handRWrist / handRForearm, handL / handLWrist / handLForearm.
--
-- Every pose here was checked in Studio with screen_capture before being committed;
-- see docs/asset-policy.md.

export type Pose = { [string]: CFrame }

local PoseLibrary = {}

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local function offset(px: number, py: number, pz: number, rx: number, ry: number, rz: number): CFrame
	return CFrame.new(px, py, pz) * angles(rx, ry, rz)
end

local EMPTY: Pose = {}

PoseLibrary.pistol = {
	idle = EMPTY,

	fire = {
		weaponRoot = offset(0, 0.03, 0.12, -7, 0, 0),
		slide = CFrame.new(0, 0, 0.26),
		handRForearm = angles(-4, 0, 0),
		handLForearm = angles(-4, 0, 0),
	},

	sprint = {
		weaponRoot = offset(-0.12, -0.12, 0.06, -14, 26, -10),
		handLForearm = angles(6, -10, 0),
	},

	equip = {
		weaponRoot = offset(0, -0.45, 0.05, -34, 8, 0),
		handRForearm = angles(-10, 0, 0),
		handLForearm = angles(-10, 0, 0),
	},

	reloadStart = {
		weaponRoot = offset(0.03, -0.1, 0.06, -12, 12, -16),
		handLForearm = angles(8, -6, 0),
	},

	magOut = {
		weaponRoot = offset(0.04, -0.14, 0.07, -16, 16, -22),
		magazine = CFrame.new(0, -0.55, 0.04),
		handL = CFrame.new(0, -0.3, 0.06),
		handLForearm = angles(14, -8, 0),
	},

	magIn = {
		weaponRoot = offset(0.04, -0.13, 0.07, -15, 15, -20),
		magazine = CFrame.new(0, -0.06, 0),
		handL = CFrame.new(0, -0.06, 0.02),
		handLForearm = angles(6, -6, 0),
	},

	boltBack = {
		weaponRoot = offset(0.02, -0.08, 0.05, -10, 10, -12),
		slide = CFrame.new(0, 0, 0.3),
		handL = CFrame.new(0.06, 0.16, 0.16),
		handLForearm = angles(-10, -14, 0),
	},

	boltForward = {
		weaponRoot = offset(0.02, -0.08, 0.05, -10, 10, -12),
		slide = CFrame.new(),
		handL = CFrame.new(0.06, 0.16, 0.16),
		handLForearm = angles(-10, -14, 0),
	},

	reloadEnd = {
		weaponRoot = offset(0.01, -0.03, 0.02, -4, 4, -5),
	},

	inspectA = {
		weaponRoot = offset(-0.1, 0.06, 0.2, 6, 34, 14),
		handLForearm = angles(4, -8, 0),
	},

	inspectB = {
		weaponRoot = offset(-0.12, 0.04, 0.24, -6, -44, 26),
		handLForearm = angles(2, -4, 0),
	},

	inspectC = {
		weaponRoot = offset(-0.06, 0.05, 0.16, 14, 10, 8),
	},
} :: { [string]: Pose }

-- Longarms share the pistol layout but need a wider support-hand travel and a bolt
-- instead of a slide; the shotgun overrides the reload with a pump stroke.
PoseLibrary.rifle = {
	idle = EMPTY,

	fire = {
		weaponRoot = offset(0, 0.04, 0.14, -6, 0, 0),
		slide = CFrame.new(0, 0, 0.2),
	},

	sprint = {
		weaponRoot = offset(-0.16, -0.14, 0.08, -12, 30, -12),
	},

	equip = {
		weaponRoot = offset(0, -0.5, 0.06, -32, 10, 0),
	},

	reloadStart = {
		weaponRoot = offset(0.04, -0.12, 0.06, -14, 14, -14),
	},

	magOut = {
		weaponRoot = offset(0.05, -0.16, 0.08, -18, 18, -20),
		magazine = CFrame.new(0, -0.7, 0.06),
		handL = CFrame.new(0.04, -0.34, 0.1),
	},

	magIn = {
		weaponRoot = offset(0.05, -0.15, 0.08, -17, 17, -19),
		magazine = CFrame.new(0, -0.08, 0),
		handL = CFrame.new(0.02, -0.08, 0.04),
	},

	boltBack = {
		weaponRoot = offset(0.03, -0.09, 0.05, -10, 12, -10),
		slide = CFrame.new(0, 0, 0.22),
		handL = CFrame.new(0.2, 0.22, 0.3),
	},

	boltForward = {
		weaponRoot = offset(0.03, -0.09, 0.05, -10, 12, -10),
		slide = CFrame.new(),
		handL = CFrame.new(0.2, 0.22, 0.3),
	},

	reloadEnd = {
		weaponRoot = offset(0.01, -0.04, 0.02, -4, 4, -4),
	},

	inspectA = {
		weaponRoot = offset(-0.12, 0.05, 0.22, 6, 32, 12),
	},

	inspectB = {
		weaponRoot = offset(-0.14, 0.03, 0.26, -6, -40, 24),
	},

	inspectC = {
		weaponRoot = offset(-0.08, 0.04, 0.18, 12, 8, 6),
	},
} :: { [string]: Pose }

PoseLibrary.shotgun = {
	idle = EMPTY,

	fire = {
		weaponRoot = offset(0, 0.07, 0.24, -11, 0, 0),
	},

	sprint = {
		weaponRoot = offset(-0.16, -0.14, 0.08, -12, 30, -12),
	},

	equip = {
		weaponRoot = offset(0, -0.5, 0.06, -32, 10, 0),
	},

	-- shotguns cycle by pump rather than a magazine swap
	reloadStart = {
		weaponRoot = offset(0.02, -0.08, 0.04, -10, 8, -8),
	},

	magOut = {
		weaponRoot = offset(0.03, -0.12, 0.05, -14, 10, -12),
		pump = CFrame.new(0, 0, 0.3),
		handL = CFrame.new(0, 0, 0.3),
	},

	magIn = {
		weaponRoot = offset(0.03, -0.11, 0.05, -13, 9, -11),
		pump = CFrame.new(),
		handL = CFrame.new(),
	},

	boltBack = {
		weaponRoot = offset(0.02, -0.08, 0.04, -10, 8, -8),
		pump = CFrame.new(0, 0, 0.28),
		handL = CFrame.new(0, 0, 0.28),
	},

	boltForward = {
		weaponRoot = offset(0.02, -0.08, 0.04, -10, 8, -8),
		pump = CFrame.new(),
		handL = CFrame.new(),
	},

	reloadEnd = {
		weaponRoot = offset(0.01, -0.03, 0.02, -3, 3, -3),
	},

	inspectA = {
		weaponRoot = offset(-0.12, 0.05, 0.22, 6, 32, 12),
	},

	inspectB = {
		weaponRoot = offset(-0.14, 0.03, 0.26, -6, -40, 24),
	},

	inspectC = {
		weaponRoot = offset(-0.08, 0.04, 0.18, 12, 8, 6),
	},
} :: { [string]: Pose }

local BY_CLASS: { [string]: { [string]: Pose } } = {
	Pistol = PoseLibrary.pistol,
	SMG = PoseLibrary.rifle,
	Rifle = PoseLibrary.rifle,
	Shotgun = PoseLibrary.shotgun,
}

function PoseLibrary.forClass(class: string): { [string]: Pose }
	return BY_CLASS[class] or PoseLibrary.rifle
end

function PoseLibrary.get(class: string, poseName: string): Pose
	return PoseLibrary.forClass(class)[poseName] or EMPTY
end

return PoseLibrary
