--!strict

export type MaterialSounds = {
	ids: { number },
	volume: number,
	pitch: number,
}

local METAL = { 100020778826074, 91756891849573, 80686912188034 }
local CONCRETE = { 76239889483945, 102524739087775, 129152333227871 }
local WOOD = { 72600633695935, 107674184975458, 86632405838667 }
local GRASS = { 125622012688974, 117551923131946, 119814451831693 }
local DIRT = { 91992059944636, 126078840343211, 97659269814534 }
local SAND = { 137562067218683, 100843308344050, 118414794165248 }
local WATER = { 105672530740348, 109737300005657, 95099484266022 }

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
