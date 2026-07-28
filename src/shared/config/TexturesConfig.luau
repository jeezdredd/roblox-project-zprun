--!strict

local AssetIds = require(script.Parent.AssetIds)

local TexturesConfig = {
	ASPHALT = AssetIds.texture.surface.asphalt,
	CONCRETE = AssetIds.texture.surface.concrete,
	GRASS = AssetIds.texture.surface.grass,
	GROUND = AssetIds.texture.surface.ground,
	BRICKS = AssetIds.texture.surface.bricks,
	METAL_PLATES = AssetIds.texture.surface.metal_plates,
	CORRUGATED = AssetIds.texture.surface.corrugated,
	TILES = AssetIds.texture.surface.tiles,
	WOOD = AssetIds.texture.surface.wood,
	RUST = AssetIds.texture.surface.rust,
	FABRIC = AssetIds.texture.surface.fabric,

	ASPHALT_NORMAL = AssetIds.texture.pbr.asphalt_normal,
	ASPHALT_ROUGHNESS = AssetIds.texture.pbr.asphalt_roughness,
	CONCRETE_NORMAL = AssetIds.texture.pbr.concrete_normal,
	CONCRETE_ROUGHNESS = AssetIds.texture.pbr.concrete_roughness,

	SAND = AssetIds.texture.surface.sand,
	SAND_NORMAL = AssetIds.texture.pbr.sand_normal,
	SAND_ROUGHNESS = AssetIds.texture.pbr.sand_roughness,
	FENCE_CHAINLINK = AssetIds.texture.surface.fence_chainlink,
}

return table.freeze(TexturesConfig)
