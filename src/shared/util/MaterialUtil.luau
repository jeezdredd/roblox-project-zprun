--!strict

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local TexturesConfig = require(ReplicatedStorage.Shared.config.TexturesConfig)

export type PbrSet = {
	name: string,
	baseMaterial: Enum.Material,
	color: number,
	normal: number,
	roughness: number,
	metalness: number?,
	studsPerTile: number,
	override: boolean?,
}

local MaterialUtil = {}

MaterialUtil.ENABLED = true

MaterialUtil.sets = {
	{
		name = "TFZ_Asphalt",
		baseMaterial = Enum.Material.Asphalt,
		color = TexturesConfig.ASPHALT,
		normal = TexturesConfig.ASPHALT_NORMAL,
		roughness = TexturesConfig.ASPHALT_ROUGHNESS,
		studsPerTile = 12,
	},
	{
		name = "TFZ_Concrete",
		baseMaterial = Enum.Material.Concrete,
		color = TexturesConfig.CONCRETE,
		normal = TexturesConfig.CONCRETE_NORMAL,
		roughness = TexturesConfig.CONCRETE_ROUGHNESS,
		studsPerTile = 6,
	},
	{
		name = "TFZ_Sand",
		baseMaterial = Enum.Material.Sand,
		color = TexturesConfig.SAND,
		normal = TexturesConfig.SAND_NORMAL,
		roughness = TexturesConfig.SAND_ROUGHNESS,
		studsPerTile = 8,
	},
	{
		name = "TFZ_Metal",
		baseMaterial = Enum.Material.Metal,
		color = TexturesConfig.STEEL,
		normal = TexturesConfig.STEEL_NORMAL,
		roughness = TexturesConfig.STEEL_ROUGHNESS,
		metalness = TexturesConfig.STEEL_METALNESS,
		studsPerTile = 6,
		override = true,
	},
	{
		name = "TFZ_Rust",
		baseMaterial = Enum.Material.CorrodedMetal,
		color = TexturesConfig.IRON_RUST,
		normal = TexturesConfig.IRON_RUST_NORMAL,
		roughness = TexturesConfig.IRON_RUST_ROUGHNESS,
		metalness = TexturesConfig.IRON_RUST_METALNESS,
		studsPerTile = 6,
		override = true,
	},
	{
		name = "TFZ_Wood",
		baseMaterial = Enum.Material.Wood,
		color = TexturesConfig.WOOD,
		normal = TexturesConfig.WOOD_NORMAL,
		roughness = TexturesConfig.WOOD_ROUGHNESS,
		studsPerTile = 6,
		override = true,
	},
	{
		name = "TFZ_WoodPlanks",
		baseMaterial = Enum.Material.WoodPlanks,
		color = TexturesConfig.WOOD,
		normal = TexturesConfig.WOOD_NORMAL,
		roughness = TexturesConfig.WOOD_ROUGHNESS,
		studsPerTile = 8,
		override = true,
	},
	{
		name = "TFZ_Grass",
		baseMaterial = Enum.Material.Grass,
		color = TexturesConfig.GRASS,
		normal = TexturesConfig.GRASS_NORMAL,
		roughness = TexturesConfig.GRASS_ROUGHNESS,
		studsPerTile = 6,
		override = true,
	},
	{
		name = "TFZ_Fabric",
		baseMaterial = Enum.Material.Fabric,
		color = TexturesConfig.FABRIC,
		normal = TexturesConfig.FABRIC_NORMAL,
		roughness = TexturesConfig.FABRIC_ROUGHNESS,
		studsPerTile = 3,
		override = true,
	},
	{
		name = "TFZ_MetalPlates",
		baseMaterial = Enum.Material.Metal,
		color = TexturesConfig.METAL_PLATES,
		normal = TexturesConfig.METAL_PLATES_NORMAL,
		roughness = TexturesConfig.METAL_PLATES_ROUGHNESS,
		metalness = TexturesConfig.METAL_PLATES_METALNESS,
		studsPerTile = 4,
	},
	{
		name = "TFZ_DarkRust",
		baseMaterial = Enum.Material.CorrodedMetal,
		color = TexturesConfig.RUST,
		normal = TexturesConfig.RUST_NORMAL,
		roughness = TexturesConfig.RUST_ROUGHNESS,
		metalness = TexturesConfig.RUST_METALNESS,
		studsPerTile = 6,
	},
	-- the 2026-09-29 variants for the environment pass (docs/world/environment.md); the
	-- studs per tile match their declarations in default.project.json
	{
		name = "TFZ_AsphaltCracked",
		baseMaterial = Enum.Material.Asphalt,
		color = AssetIds.texture.surface.asphalt_cracked_color,
		normal = AssetIds.texture.surface.asphalt_cracked_normal,
		roughness = AssetIds.texture.surface.asphalt_cracked_roughness,
		studsPerTile = 14,
	},
	{
		name = "TFZ_RoadWorn",
		baseMaterial = Enum.Material.Asphalt,
		color = AssetIds.texture.surface.asphalt_worn_lines_color,
		normal = AssetIds.texture.surface.asphalt_worn_lines_normal,
		roughness = AssetIds.texture.surface.asphalt_worn_lines_roughness,
		studsPerTile = 60,
	},
	{
		name = "TFZ_ConcreteDirty",
		baseMaterial = Enum.Material.Concrete,
		color = AssetIds.texture.surface.concrete_dirty_color,
		normal = AssetIds.texture.surface.concrete_dirty_normal,
		roughness = AssetIds.texture.surface.concrete_dirty_roughness,
		studsPerTile = 10,
	},
	{
		name = "TFZ_GroundBurned",
		baseMaterial = Enum.Material.Ground,
		color = AssetIds.texture.surface.ground_burned_color,
		normal = AssetIds.texture.surface.ground_burned_normal,
		roughness = AssetIds.texture.surface.ground_burned_roughness,
		studsPerTile = 16,
	},
	{
		name = "TFZ_DirtDry",
		baseMaterial = Enum.Material.Ground,
		color = AssetIds.texture.surface.dirt_dry_color,
		normal = AssetIds.texture.surface.dirt_dry_normal,
		roughness = AssetIds.texture.surface.dirt_dry_roughness,
		studsPerTile = 14,
	},
	{
		name = "TFZ_PlasterPeeling",
		baseMaterial = Enum.Material.Plaster,
		color = AssetIds.texture.surface.plaster_peeling_brick_color,
		normal = AssetIds.texture.surface.plaster_peeling_brick_normal,
		roughness = AssetIds.texture.surface.plaster_peeling_brick_roughness,
		studsPerTile = 12,
	},
	{
		name = "TFZ_MetalRusty",
		baseMaterial = Enum.Material.CorrodedMetal,
		color = AssetIds.texture.surface.metal_rusty_color,
		normal = AssetIds.texture.surface.metal_rusty_normal,
		roughness = AssetIds.texture.surface.metal_rusty_roughness,
		studsPerTile = 6,
	},
	{
		name = "TFZ_PaintPeelingMetal",
		baseMaterial = Enum.Material.Metal,
		color = AssetIds.texture.surface.paint_peeling_metal_color,
		normal = AssetIds.texture.surface.paint_peeling_metal_normal,
		roughness = AssetIds.texture.surface.paint_peeling_metal_roughness,
		metalness = AssetIds.texture.surface.paint_peeling_metal_metalness,
		studsPerTile = 6,
	},
} :: { PbrSet }

local registered: { [string]: boolean } = {}

-- MaterialVariant.BaseMaterial is a plugin-capability property, so a runtime script
-- cannot build these. They ship as instances declared under MaterialService in
-- default.project.json; this pass only records which ones actually arrived.
function MaterialUtil.register()
	if not MaterialUtil.ENABLED then
		return
	end
	for _, set in MaterialUtil.sets do
		if registered[set.name] then
			continue
		end
		local existing = MaterialService:FindFirstChild(set.name)
		if existing and existing:IsA("MaterialVariant") then
			registered[set.name] = true
			if set.override then
				MaterialService:SetBaseMaterialOverride(set.baseMaterial, set.name)
			end
		else
			warn(`[TaskForceZ] MaterialVariant "{set.name}" missing from MaterialService, falling back to flat textures`)
		end
	end
end

function MaterialUtil.apply(part: BasePart, setName: string): boolean
	if not MaterialUtil.ENABLED or not registered[setName] then
		return false
	end
	for _, set in MaterialUtil.sets do
		if set.name == setName then
			part.Material = set.baseMaterial
			part.MaterialVariant = setName
			return true
		end
	end
	return false
end

return MaterialUtil
