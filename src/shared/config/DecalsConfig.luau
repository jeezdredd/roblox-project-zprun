--!strict

-- Ground and wall marks per biome. `key` names an entry of AssetIds.texture.decal; a key
-- that is missing or 0 places nothing, so the list can name marks the project does not
-- have yet (docs/world/assets-needed.md). Data only, no engine types.
--
-- Zones: "lane" is the playable band minus a margin, "shoulder" the strip just inside the
-- corridor edge, "edge" the corridor edge row, "wall" a card on a road-facing wall part.
-- "floor" is a tiled Texture on the floor's top face rather than a card.

export type Entry = {
	key: string,
	biomes: { string },
	zone: string,
	-- card size in studs: { min, max } for a square card, or { width, depth } when fixed
	size: { number },
	fixed: boolean?,
	count: { number },
	transparency: { number },
	-- render order between overlapping marks: cracks 1, stains 2, blood 3
	layer: number,
	-- tile size for floor textures
	tile: { number }?,
}

local DecalsConfig = {}

-- A card sits this far above the ground, plus LAYER_STEP per layer, so layers never fight.
DecalsConfig.CARD_LIFT = 0.02
DecalsConfig.LAYER_STEP = 0.01
-- Wall cards stand this far in front of the wall face.
DecalsConfig.WALL_GAP = 0.06
-- Cards beyond this many per chunk are detail the mobile tier removes.
DecalsConfig.BASE_CARDS = 2
-- Lane cards keep off the road centre line by this much, and off the chunk ends.
DecalsConfig.LANE_HALF = 24
DecalsConfig.END_CLEARANCE = 8

DecalsConfig.entries = {
	{ key = "asphalt_patch_a", biomes = { "City" }, zone = "lane", size = { 8, 14 }, count = { 1, 2 }, transparency = { 0.05, 0.25 }, layer = 1 },
	{ key = "asphalt_patch_b", biomes = { "City" }, zone = "lane", size = { 8, 14 }, count = { 1, 2 }, transparency = { 0.05, 0.25 }, layer = 1 },
	{ key = "road_crack_a", biomes = { "City", "Wasteland" }, zone = "lane", size = { 6, 12 }, count = { 1, 3 }, transparency = { 0.1, 0.3 }, layer = 1 },
	{ key = "lane_arrow_worn", biomes = { "City" }, zone = "lane", size = { 6, 6 }, count = { 0, 1 }, transparency = { 0.3, 0.5 }, layer = 1 },
	{ key = "crosswalk_worn", biomes = { "City" }, zone = "lane", size = { 40, 8 }, fixed = true, count = { 0, 1 }, transparency = { 0.35, 0.55 }, layer = 1 },
	{ key = "manhole_a", biomes = { "City" }, zone = "lane", size = { 4, 4 }, count = { 0, 1 }, transparency = { 0, 0.1 }, layer = 1 },
	{ key = "tyre_marks_a", biomes = { "City", "Wasteland" }, zone = "floor", size = { 0, 0 }, count = { 1, 1 }, transparency = { 0.55, 0.55 }, layer = 1, tile = { 60, 64 } },
	{ key = "oil_stain_a", biomes = { "City", "Wasteland" }, zone = "edge", size = { 5, 8 }, count = { 1, 2 }, transparency = { 0.15, 0.35 }, layer = 2 },
	{ key = "scorch_a", biomes = { "City", "Wasteland" }, zone = "edge", size = { 10, 16 }, count = { 0, 2 }, transparency = { 0.1, 0.3 }, layer = 2 },
	{ key = "graffiti_a", biomes = { "City", "Wasteland" }, zone = "wall", size = { 5, 8 }, count = { 0, 1 }, transparency = { 0.05, 0.2 }, layer = 2 },
	{ key = "graffiti_b", biomes = { "City", "Wasteland" }, zone = "wall", size = { 5, 8 }, count = { 0, 1 }, transparency = { 0.05, 0.2 }, layer = 2 },
	{ key = "graffiti_c", biomes = { "City" }, zone = "wall", size = { 5, 8 }, count = { 0, 1 }, transparency = { 0.05, 0.2 }, layer = 2 },
	{ key = "leak_streaks", biomes = { "City" }, zone = "wall", size = { 4, 9 }, fixed = true, count = { 0, 2 }, transparency = { 0.2, 0.4 }, layer = 2 },
	{ key = "blood_trail_a", biomes = { "City", "Forest", "Wasteland", "Farmstead", "Cornfield" }, zone = "lane", size = { 4, 10 }, fixed = true, count = { 0, 2 }, transparency = { 0.1, 0.3 }, layer = 3 },
	{ key = "blood_pool_a", biomes = { "City", "Forest", "Wasteland", "Farmstead", "Cornfield" }, zone = "shoulder", size = { 3, 5 }, count = { 0, 2 }, transparency = { 0.1, 0.3 }, layer = 3 },
} :: { Entry }

-- Wall parts, by name, that may carry a wall card. All are thin along their local x and
-- face the road.
DecalsConfig.WALL_PARTS = { "Divider", "RuinFront", "Shopfront" }

function DecalsConfig.forBiome(biome: string): { Entry }
	local out = {}
	for _, entry in DecalsConfig.entries do
		if table.find(entry.biomes, biome) then
			table.insert(out, entry)
		end
	end
	return out
end

-- The asset id behind a key from a lookup table; anything missing or non-positive is 0.
function DecalsConfig.idOf(ids: { [string]: any }?, key: string): number
	if not ids then
		return 0
	end
	local id = ids[key]
	if typeof(id) ~= "number" or id <= 0 then
		return 0
	end
	return id
end

return DecalsConfig
