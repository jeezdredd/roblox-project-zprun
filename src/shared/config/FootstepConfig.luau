--!strict

export type MaterialSounds = {
	ids: { number },
	volume: number,
	pitch: number,
}

local AssetIds = require(script.Parent.AssetIds)

local steps = AssetIds.audio.footsteps

local METAL = { steps.metal_01, steps.metal_02, steps.metal_03 }
local CONCRETE = { steps.concrete_01, steps.concrete_02, steps.concrete_03 }
local WOOD = { steps.wood_01, steps.wood_02, steps.wood_03 }
local GRASS = { steps.grass_01, steps.grass_02, steps.grass_03 }
local DIRT = { steps.dirt_01, steps.dirt_02, steps.dirt_03 }
local SAND = { steps.sand_01, steps.sand_02, steps.sand_03 }
local WATER = { steps.water_01, steps.water_02, steps.water_03 }

local FootstepConfig = {}

FootstepConfig.PITCH_JITTER = 0.07
FootstepConfig.VOLUME_JITTER = 0.1
FootstepConfig.POOL_SIZE = 6
FootstepConfig.ROLLOFF_MIN = 6
FootstepConfig.ROLLOFF_MAX = 70
FootstepConfig.TEAMMATE_ROLLOFF_MAX = 90
FootstepConfig.RAYCAST_DEPTH = 6
FootstepConfig.MAX_SLICE = 0.32

FootstepConfig.DEFAULT = {
	ids = CONCRETE,
	volume = 0.5,
	pitch = 1,
} :: MaterialSounds

FootstepConfig.byMaterial = {
	[Enum.Material.Grass] = { ids = GRASS, volume = 0.45, pitch = 1 },
	[Enum.Material.LeafyGrass] = { ids = GRASS, volume = 0.48, pitch = 0.96 },
	[Enum.Material.Mud] = { ids = DIRT, volume = 0.5, pitch = 0.9 },
	[Enum.Material.Ground] = { ids = DIRT, volume = 0.48, pitch = 0.96 },
	[Enum.Material.Concrete] = { ids = CONCRETE, volume = 0.55, pitch = 1 },
	[Enum.Material.Asphalt] = { ids = CONCRETE, volume = 0.55, pitch = 1.04 },
	[Enum.Material.Pavement] = { ids = CONCRETE, volume = 0.55, pitch = 1.02 },
	[Enum.Material.Brick] = { ids = CONCRETE, volume = 0.52, pitch = 0.98 },
	[Enum.Material.Metal] = { ids = METAL, volume = 0.6, pitch = 1 },
	[Enum.Material.DiamondPlate] = { ids = METAL, volume = 0.62, pitch = 1.06 },
	[Enum.Material.CorrodedMetal] = { ids = METAL, volume = 0.58, pitch = 0.94 },
	[Enum.Material.Wood] = { ids = WOOD, volume = 0.5, pitch = 1 },
	[Enum.Material.WoodPlanks] = { ids = WOOD, volume = 0.52, pitch = 0.98 },
	[Enum.Material.Sand] = { ids = SAND, volume = 0.42, pitch = 1 },
	[Enum.Material.Snow] = { ids = SAND, volume = 0.4, pitch = 1.08 },
	[Enum.Material.Rock] = { ids = CONCRETE, volume = 0.55, pitch = 1.08 },
	[Enum.Material.Slate] = { ids = CONCRETE, volume = 0.55, pitch = 1.05 },
	[Enum.Material.Basalt] = { ids = CONCRETE, volume = 0.55, pitch = 1.03 },
	[Enum.Material.Glass] = { ids = METAL, volume = 0.45, pitch = 1.2 },
	[Enum.Material.Fabric] = { ids = SAND, volume = 0.35, pitch = 0.9 },
	[Enum.Material.Water] = { ids = WATER, volume = 0.6, pitch = 1 },
} :: { [Enum.Material]: MaterialSounds }

function FootstepConfig.get(material: Enum.Material): MaterialSounds
	return FootstepConfig.byMaterial[material] or FootstepConfig.DEFAULT
end

return FootstepConfig
