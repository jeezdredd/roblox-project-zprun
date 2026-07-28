--!strict

export type StepDust = {
	color: Color3,
	size: number,
	count: number,
	speed: number,
	lifetime: number,
}

local VfxConfig = {}

VfxConfig.ENABLED = true
VfxConfig.DENSITY = 1
VfxConfig.MAX_ACTIVE_EMITTERS = 40

VfxConfig.STEP_DUST_DEFAULT = {
	color = Color3.fromRGB(168, 160, 148),
	size = 1.1,
	count = 4,
	speed = 3.5,
	lifetime = 0.6,
} :: StepDust

VfxConfig.stepDust = {
	[Enum.Material.Concrete] = { color = Color3.fromRGB(176, 172, 166), size = 1.1, count = 4, speed = 3.5, lifetime = 0.55 },
	[Enum.Material.Asphalt] = { color = Color3.fromRGB(150, 146, 142), size = 1.1, count = 4, speed = 3.5, lifetime = 0.55 },
	[Enum.Material.Pavement] = { color = Color3.fromRGB(170, 166, 160), size = 1, count = 3, speed = 3.2, lifetime = 0.5 },
	[Enum.Material.Ground] = { color = Color3.fromRGB(146, 122, 92), size = 1.4, count = 6, speed = 4, lifetime = 0.75 },
	[Enum.Material.Mud] = { color = Color3.fromRGB(104, 84, 62), size = 1.3, count = 5, speed = 3, lifetime = 0.7 },
	[Enum.Material.Grass] = { color = Color3.fromRGB(120, 146, 96), size = 1.2, count = 4, speed = 3.4, lifetime = 0.6 },
	[Enum.Material.LeafyGrass] = { color = Color3.fromRGB(110, 138, 90), size = 1.3, count = 5, speed = 3.4, lifetime = 0.65 },
	[Enum.Material.Sand] = { color = Color3.fromRGB(206, 188, 148), size = 1.5, count = 7, speed = 4.2, lifetime = 0.85 },
	[Enum.Material.Snow] = { color = Color3.fromRGB(238, 242, 248), size = 1.4, count = 6, speed = 3.8, lifetime = 0.8 },
	[Enum.Material.Rock] = { color = Color3.fromRGB(160, 154, 146), size = 1, count = 3, speed = 3, lifetime = 0.5 },
	[Enum.Material.Slate] = { color = Color3.fromRGB(150, 148, 144), size = 1, count = 3, speed = 3, lifetime = 0.5 },
	[Enum.Material.Metal] = { color = Color3.fromRGB(180, 180, 186), size = 0.7, count = 2, speed = 2.6, lifetime = 0.35 },
	[Enum.Material.DiamondPlate] = { color = Color3.fromRGB(184, 184, 190), size = 0.7, count = 2, speed = 2.6, lifetime = 0.35 },
	[Enum.Material.WoodPlanks] = { color = Color3.fromRGB(168, 142, 106), size = 0.9, count = 3, speed = 2.8, lifetime = 0.45 },
	[Enum.Material.Wood] = { color = Color3.fromRGB(160, 134, 100), size = 0.9, count = 3, speed = 2.8, lifetime = 0.45 },
	[Enum.Material.Water] = { color = Color3.fromRGB(196, 216, 226), size = 1.6, count = 8, speed = 5.5, lifetime = 0.6 },
} :: { [Enum.Material]: StepDust }

VfxConfig.JUKE_MIN_SPEED = 26
VfxConfig.JUKE_COOLDOWN = 0.4
VfxConfig.JUKE_PARTICLES = 10

VfxConfig.BREATH_VAPOR_INTERVAL_CALM = 3.4
VfxConfig.BREATH_VAPOR_INTERVAL_EXERTED = 1.2
VfxConfig.BREATH_VAPOR_COUNT = 4

function VfxConfig.dustFor(material: Enum.Material): StepDust
	return VfxConfig.stepDust[material] or VfxConfig.STEP_DUST_DEFAULT
end

return VfxConfig
