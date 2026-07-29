--!strict

-- Numeric specification of the first-person rig, transcribed from the free
-- "Gun Viewmodel Kit" by HowToRoblox (asset 11994419773) and its Glock viewmodel.
-- It lives here as data rather than as a binary model so the rig stays in git as
-- text, diffable and reviewable, and so Rojo owns it like every other config.
--
-- Axis conventions, measured rather than assumed:
--   arms  - built around HumanoidRootPart; every limb sits at 90 deg about X
--   gun   - +Z is the muzzle direction, +X is up, +Y is the width axis
-- The gun meshes are authored in that frame, and the shipped animations are keyed
-- against it, so neither may be "corrected" without re-authoring the clips.

export type PartSpec = {
	name: string,
	size: Vector3,
	meshId: number?,
	textureId: number?,
	color: Color3?,
	transparency: number?,
}

export type JointSpec = {
	name: string,
	part0: string,
	part1: string,
	c0: CFrame,
	c1: CFrame,
}

export type GunPartSpec = {
	name: string,
	size: Vector3,
	meshId: number,
	textureId: number,
	offset: CFrame,
	movable: boolean,
}

export type AttachmentSpec = {
	name: string,
	offset: CFrame,
}

export type GunSpec = {
	parts: { GunPartSpec },
	attachments: { AttachmentSpec },
	-- where the right hand grips the weapon, in the weapon's own frame
	gripOffset: CFrame,
	clips: { [string]: number },
}

local ViewmodelRigConfig = {}

local SKIN = Color3.fromRGB(204, 142, 105)

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

ViewmodelRigConfig.arms = {
	{ name = "HumanoidRootPart", size = Vector3.new(1, 1, 1), transparency = 1 },
	{ name = "LeftUpperArm", size = Vector3.new(1.1741, 3.2181, 1.1741), meshId = 1699715550, color = SKIN },
	{ name = "LeftLowerArm", size = Vector3.new(1.1741, 2.6031, 1.1741), meshId = 1699715541, color = SKIN },
	{ name = "LeftHand", size = Vector3.new(1.1741, 0.5032, 1.1741), meshId = 1699715537, color = SKIN },
	{ name = "RightUpperArm", size = Vector3.new(1.1741, 3.2181, 1.1741), meshId = 1699715576, color = SKIN },
	{ name = "RightLowerArm", size = Vector3.new(1.1741, 2.6030, 1.1741), meshId = 1699715562, color = SKIN },
	{ name = "RightHand", size = Vector3.new(1.1741, 0.5032, 1.1741), meshId = 1699715557, color = SKIN },
} :: { PartSpec }

-- Joint names are load-bearing: the published clips address these exact tracks.
ViewmodelRigConfig.joints = {
	{
		name = "LeftShoulder",
		part0 = "HumanoidRootPart",
		part1 = "LeftUpperArm",
		c0 = CFrame.new(-1.5159, -1.7735, 0.3175) * angles(90, 0, 0),
		c1 = CFrame.new(0, 1.2, 0),
	},
	{
		name = "LeftElbow",
		part0 = "LeftUpperArm",
		part1 = "LeftLowerArm",
		c0 = CFrame.new(0.0008, -0.9313, 0),
		c1 = CFrame.new(0.0008, 0.6918, 0),
	},
	{
		name = "LeftWrist",
		part0 = "LeftLowerArm",
		part1 = "LeftHand",
		c0 = CFrame.new(0.0008, -1.2209, 0),
		c1 = CFrame.new(0.0008, 0.2484, 0),
	},
	{
		name = "RightShoulder",
		part0 = "HumanoidRootPart",
		part1 = "RightUpperArm",
		c0 = CFrame.new(1.5159, -1.7735, 0.3175) * angles(90, 0, 0),
		c1 = CFrame.new(0, 1.2, 0),
	},
	{
		name = "RightElbow",
		part0 = "RightUpperArm",
		part1 = "RightLowerArm",
		c0 = CFrame.new(0, -0.9315, 0),
		c1 = CFrame.new(0, 0.6917, 0),
	},
	{
		name = "RightWrist",
		part0 = "RightLowerArm",
		part1 = "RightHand",
		c0 = CFrame.new(0, -1.1822, 0),
		c1 = CFrame.new(0, 0.2870, 0),
	},
} :: { JointSpec }

-- Offsets are relative to the weapon's Main part, which is the hub every other piece
-- hangs off. `movable = true` earns a Motor6D so a clip can drive it; everything else
-- is welded, which also keeps the Animation Editor's track list down to what matters.
ViewmodelRigConfig.guns = {
	Pistol = {
		parts = {
			{
				name = "Main",
				size = Vector3.new(1.2757, 0.3082, 2.1594),
				meshId = 7001027854,
				textureId = 7001040481,
				offset = CFrame.identity,
				movable = false,
			},
			{
				name = "Slide",
				size = Vector3.new(0.3505, 0.3048, 1.8629),
				meshId = 7001028792,
				textureId = 7001042771,
				offset = CFrame.new(0.4969, -0.0322, 0.0325),
				movable = true,
			},
			{
				name = "Magazine",
				size = Vector3.new(1.1861, 0.2815, 0.6935),
				meshId = 7001035415,
				textureId = 7001038127,
				offset = CFrame.new(-0.0874, 0, -0.6313),
				movable = true,
			},
		},
		attachments = {
			{ name = "Muzzle", offset = CFrame.new(0.5448, 0.0024, 1.1553) },
			{ name = "CasingEject", offset = CFrame.new(0.5448, 0.0024, 0.4573) },
		},
		gripOffset = CFrame.new(-0.2247, 0.0024, -0.6404),
		clips = {
			Idle = 11987083741,
			Equip = 11987174932,
			Aim = 11987102823,
			Reload = 11987964870,
			Fire = 11988019050,
		},
	},
} :: { [string]: GunSpec }

function ViewmodelRigConfig.gun(class: string): GunSpec?
	return ViewmodelRigConfig.guns[class]
end

return ViewmodelRigConfig
