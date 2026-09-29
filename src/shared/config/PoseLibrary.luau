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

-- Left hand over the pistol slide, palm down (see pistol rackGrab).
local RACK_GRIP = angles(74.1, -36.1, -39.9)
-- Left hand hooking the rifle charging handle (see rifle rackGrab).
local CHARGE_GRIP = angles(-98.9, -65.2, -24.5)

PoseLibrary.pistol = {
	idle = EMPTY,

	fire = {
		weaponRoot = offset(0, 0.03, 0.12, -7, 0, 0),
		slide = CFrame.new(0, 0, 0.26),
		handRForearm = angles(-4, 0, 0),
		handLForearm = angles(-4, 0, 0),
	},

	-- Kept deliberately small: see the note on ViewmodelConfig.sprint. The player
	-- sprints for the entire run, so anything that takes the barrel off the crosshair
	-- here is permanent rather than transient.
	sprint = {
		weaponRoot = offset(-0.05, -0.05, 0.03, -4, 3, -3),
		handLForearm = angles(3, -4, 0),
	},

	equip = {
		weaponRoot = offset(0, -0.45, 0.05, -34, 8, 0),
		handRForearm = angles(-10, 0, 0),
		handLForearm = angles(-10, 0, 0),
	},

	-- Draw: the pistol comes up canted to the left and the left hand comes over the top,
	-- takes the rear of the slide overhand, racks it back and lets it go. Hand offsets are
	-- in weapon space, unscaled units of pistol.rig.txt; the hand frame was built with
	-- fingers across the slide toward +X and the palm down.
	rackGrab = {
		weaponRoot = offset(-0.2, 0.06, 0.02, 8, 18, 38),
		handL = CFrame.new(0.03, 0.4, 0.16) * RACK_GRIP,
	},

	rackPull = {
		weaponRoot = offset(-0.2, 0.08, 0.05, 10, 18, 38),
		slide = CFrame.new(0, 0, 0.26),
		handL = CFrame.new(0.03, 0.4, 0.42) * RACK_GRIP,
	},

	rackRelease = {
		weaponRoot = offset(-0.12, 0.04, 0.03, 2, 10, 20),
		slide = CFrame.new(),
		handL = CFrame.new(-0.4, 0.02, 0.4) * RACK_GRIP,
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
-- Left hand on the magazine, in weapon space: turned so the hand's grip axis runs up the
-- magazine (Rx 90), then swung about that axis so the forearm leaves the frame down and
-- back instead of lying across it.
local MAG_GRIP = angles(0, 55, 0) * angles(90, 0, 0)

PoseLibrary.rifle = {
	idle = EMPTY,

	fire = {
		weaponRoot = offset(0, 0.04, 0.14, -6, 0, 0),
		slide = CFrame.new(0, 0, 0.2),
	},

	sprint = {
		weaponRoot = offset(-0.06, -0.06, 0.04, -4, 3, -4),
	},

	equip = {
		weaponRoot = offset(0, -0.5, 0.06, -32, 10, 0),
	},

	-- Draw: the rifle is pushed out canted to the left, the left hand comes over the top
	-- of the upper receiver, hooks the charging handle, pulls it back and lets it go.
	-- Hand frame built with the fingers up and across the receiver toward +X.
	rackGrab = {
		weaponRoot = offset(-0.3, 0.08, -0.45, 12, 16, 32),
		handL = CFrame.new(-0.039, 0.189, 1.033) * CHARGE_GRIP,
	},

	rackPull = {
		weaponRoot = offset(-0.3, 0.1, -0.42, 14, 16, 32),
		handL = CFrame.new(-0.039, 0.189, 1.333) * CHARGE_GRIP,
	},

	rackRelease = {
		weaponRoot = offset(-0.15, 0.05, -0.2, 6, 8, 16),
		handL = CFrame.new(-0.45, -0.15, 1.2) * CHARGE_GRIP,
	},

	-- Magazine change with the mesh arms, checked frame by frame in Studio. Hand offsets
	-- are in weapon space (ViewmodelBuilder converts them for the mesh hand pivots), in
	-- the same unscaled units as assets/viewmodels/rifle.rig.txt: the left hand's rest
	-- pivot sits on the handguard axis at (0, 0.15, -0.47), the magazine centre at
	-- (0, -0.49, 0.02). The weapon comes up towards the centre and rolls to show the well, the left hand comes off
	-- the handguard, takes the magazine, strips it, drops out of frame to the vest,
	-- brings a fresh one back, seats it with a push and returns.
	reloadStart = {
		weaponRoot = offset(-0.12, 0.16, 0.1, 6, 14, -22),
		handL = CFrame.new(-0.16, -0.14, 0.1),
	},

	grabMag = {
		weaponRoot = offset(-0.2, 0.28, 0.14, 10, 18, -28),
		handL = CFrame.new(-0.02, -0.74, 0.5) * MAG_GRIP,
	},

	magOut = {
		weaponRoot = offset(-0.2, 0.3, 0.14, 11, 18, -27),
		magazine = CFrame.new(0, -0.55, 0.05),
		handL = CFrame.new(-0.02, -1.29, 0.55) * MAG_GRIP,
	},

	magAway = {
		weaponRoot = offset(-0.2, 0.28, 0.14, 10, 18, -27),
		magazine = CFrame.new(0, -3, 0.5),
		handL = CFrame.new(-0.3, -2.4, 0.9) * angles(70, 0, 20),
	},

	magReturn = {
		weaponRoot = offset(-0.2, 0.28, 0.14, 10, 18, -28),
		magazine = CFrame.new(0, -0.55, 0.05),
		handL = CFrame.new(-0.02, -1.29, 0.55) * MAG_GRIP,
	},

	magIn = {
		weaponRoot = offset(-0.2, 0.3, 0.14, 11, 18, -27),
		magazine = CFrame.new(),
		handL = CFrame.new(-0.02, -0.74, 0.5) * MAG_GRIP,
	},

	-- the heel of the hand pushes the magazine home: the weapon jumps a little
	magSeat = {
		weaponRoot = offset(-0.2, 0.36, 0.14, 13, 17, -26),
		handL = CFrame.new(-0.02, -0.66, 0.5) * MAG_GRIP,
	},

	-- empty magazine: the left hand slaps the bolt release on the left of the receiver,
	-- just above the magazine well
	boltBack = {
		weaponRoot = offset(-0.14, 0.2, 0.1, 8, 14, -20),
		handL = CFrame.new(-0.3, -0.34, 0.56) * MAG_GRIP,
	},

	boltForward = {
		weaponRoot = offset(-0.12, 0.16, 0.08, 6, 12, -16),
		handL = CFrame.new(-0.26, -0.28, 0.52) * MAG_GRIP,
	},

	reloadEnd = {
		weaponRoot = offset(0.01, -0.03, 0.02, -3, 4, -5),
		handL = CFrame.new(-0.04, -0.05, 0.03),
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
		weaponRoot = offset(-0.06, -0.06, 0.04, -4, 3, -4),
	},

	equip = {
		weaponRoot = offset(0, -0.5, 0.06, -32, 10, 0),
	},

	-- Draw: rack the pump (the box support hand rides on the pump)
	rackGrab = {
		weaponRoot = offset(0, 0.02, 0.04, -4, 6, -8),
	},

	rackPull = {
		weaponRoot = offset(0, 0.02, 0.06, -6, 6, -8),
		pump = CFrame.new(0, 0, 0.3),
		handL = CFrame.new(0, 0, 0.3),
	},

	rackRelease = {
		weaponRoot = offset(0, 0, 0.02, -2, 3, -4),
		pump = CFrame.new(),
		handL = CFrame.new(),
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

-- The SMG still uses box arms, whose hand offsets are not in weapon space, so it takes
-- the rifle poses without the mesh-hand draw (the Equip sequence falls back to idle).
local smg: { [string]: Pose } = table.clone(PoseLibrary.rifle)
smg.rackGrab = nil
smg.rackPull = nil
smg.rackRelease = nil
PoseLibrary.smg = smg

local BY_CLASS: { [string]: { [string]: Pose } } = {
	Pistol = PoseLibrary.pistol,
	SMG = PoseLibrary.smg,
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
