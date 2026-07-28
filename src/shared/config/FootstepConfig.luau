--!strict

export type MaterialSounds = {
	ids: { number },
	volume: number,
	pitch: number,
}

local GRAVEL_STEP = 75914567135656

local FootstepConfig = {}

FootstepConfig.PITCH_JITTER = 0.07
FootstepConfig.VOLUME_JITTER = 0.1
FootstepConfig.POOL_SIZE = 6
FootstepConfig.ROLLOFF_MIN = 6
FootstepConfig.ROLLOFF_MAX = 70
FootstepConfig.TEAMMATE_ROLLOFF_MAX = 90
FootstepConfig.RAYCAST_DEPTH = 6

FootstepConfig.DEFAULT = {
	ids = { GRAVEL_STEP },
	volume = 0.5,
	pitch = 1,
} :: MaterialSounds

FootstepConfig.byMaterial = {
	[Enum.Material.Grass] = { ids = { GRAVEL_STEP }, volume = 0.45, pitch = 1 },
	[Enum.Material.Mud] = { ids = { GRAVEL_STEP }, volume = 0.5, pitch = 0.92 },
	[Enum.Material.Ground] = { ids = { GRAVEL_STEP }, volume = 0.48, pitch = 0.96 },
	[Enum.Material.Concrete] = { ids = { GRAVEL_STEP }, volume = 0.55, pitch = 1 },
	[Enum.Material.Asphalt] = { ids = { GRAVEL_STEP }, volume = 0.55, pitch = 1.02 },
	[Enum.Material.Metal] = { ids = { GRAVEL_STEP }, volume = 0.6, pitch = 1.08 },
	[Enum.Material.DiamondPlate] = { ids = { GRAVEL_STEP }, volume = 0.6, pitch = 1.1 },
	[Enum.Material.CorrodedMetal] = { ids = { GRAVEL_STEP }, volume = 0.58, pitch = 1.04 },
	[Enum.Material.Wood] = { ids = { GRAVEL_STEP }, volume = 0.5, pitch = 1 },
	[Enum.Material.WoodPlanks] = { ids = { GRAVEL_STEP }, volume = 0.52, pitch = 0.98 },
	[Enum.Material.Sand] = { ids = { GRAVEL_STEP }, volume = 0.42, pitch = 0.94 },
	[Enum.Material.Rock] = { ids = { GRAVEL_STEP }, volume = 0.55, pitch = 1.05 },
	[Enum.Material.Slate] = { ids = { GRAVEL_STEP }, volume = 0.55, pitch = 1.03 },
	[Enum.Material.Water] = { ids = { GRAVEL_STEP }, volume = 0.6, pitch = 0.9 },
} :: { [Enum.Material]: MaterialSounds }

function FootstepConfig.get(material: Enum.Material): MaterialSounds
	return FootstepConfig.byMaterial[material] or FootstepConfig.DEFAULT
end

return FootstepConfig
