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

	METAL_PLATES_NORMAL = AssetIds.texture.pbr.metal_plates_normal,
	METAL_PLATES_ROUGHNESS = AssetIds.texture.pbr.metal_plates_roughness,
	METAL_PLATES_METALNESS = AssetIds.texture.pbr.metal_plates_metalness,
	RUST_NORMAL = AssetIds.texture.pbr.rust_normal,
	RUST_ROUGHNESS = AssetIds.texture.pbr.rust_roughness,
	RUST_METALNESS = AssetIds.texture.pbr.rust_metalness,
	STEEL = AssetIds.texture.surface.steel,
	STEEL_NORMAL = AssetIds.texture.pbr.steel_normal,
	STEEL_ROUGHNESS = AssetIds.texture.pbr.steel_roughness,
	STEEL_METALNESS = AssetIds.texture.pbr.steel_metalness,
	IRON_RUST = AssetIds.texture.surface.iron_rust,
	IRON_RUST_NORMAL = AssetIds.texture.pbr.iron_rust_normal,
	IRON_RUST_ROUGHNESS = AssetIds.texture.pbr.iron_rust_roughness,
	IRON_RUST_METALNESS = AssetIds.texture.pbr.iron_rust_metalness,

	WOOD_NORMAL = AssetIds.texture.pbr.wood_normal,
	WOOD_ROUGHNESS = AssetIds.texture.pbr.wood_roughness,
	GRASS_NORMAL = AssetIds.texture.pbr.grass_normal,
	GRASS_ROUGHNESS = AssetIds.texture.pbr.grass_roughness,
	FABRIC_NORMAL = AssetIds.texture.pbr.fabric_normal,
	FABRIC_ROUGHNESS = AssetIds.texture.pbr.fabric_roughness,

	SAND = AssetIds.texture.surface.sand,
	SAND_NORMAL = AssetIds.texture.pbr.sand_normal,
	SAND_ROUGHNESS = AssetIds.texture.pbr.sand_roughness,
	FENCE_CHAINLINK = AssetIds.texture.surface.fence_chainlink,
}

return table.freeze(TexturesConfig)
