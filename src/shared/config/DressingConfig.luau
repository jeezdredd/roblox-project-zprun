--!strict

-- Road dressing rules: which prop clusters each biome gets, where they may stand, which
-- material variant every surface takes, and the per-chunk budgets. Data only, with no
-- engine types, so DressingPlanner and ChunkBudget and their tests load it under the
-- standalone Luau CLI. Groups are WorldMeshConfig group names; zones and bands are the
-- ones in docs/world/environment.md. Distances are studs, chunk-local; x is measured
-- outwards from the road centre and applies to both sides.

export type Range = { number }

export type Member = {
	group: string,
	count: Range,
	zone: string,
	-- "line": the members follow each other along the road; default: around the anchor
	layout: string?,
	-- how far from the cluster anchor a scattered member may land along the road
	spread: number?,
	-- yaw range in radians; default anywhere
	yaw: Range?,
	-- material variant painted on the ground under the prop (burn marks)
	patch: string?,
}

export type Recipe = {
	members: { Member },
}

export type Zone = {
	inner: number,
	outer: number,
	collide: boolean,
	shadow: boolean,
	-- clutter the mobile tier removes
	detail: boolean,
}

export type BiomeRules = {
	clusters: Range,
	-- "alternate": clusters take turns between the two sides; "one": a single side
	sides: string,
	recipes: { string },
	-- cap on props per chunk
	props: Range,
	-- zone overrides where a biome's flank already fills the default band
	zones: { [string]: Range }?,
}

export type Materials = {
	floor: string,
	apron: string,
	sidewalk: string?,
	divider: string?,
	-- variant for a share of the near-band facade blocks, and that share
	facade: string?,
	facadeShare: number?,
	ruin: string?,
	pole: string?,
	forestFloor: string?,
	berm: string?,
	barnRoof: string?,
}

export type Budget = {
	parts: number,
	triangles: number,
	instances: number,
	decals: number,
	lights: number,
	shadows: number,
}

local DressingConfig = {}

DressingConfig.TAGS = {
	prop = "TFZ_Prop",
	detail = "TFZ_Detail",
	shadowNear = "TFZ_ShadowNear",
}

-- Nothing taller than this casts a shadow, whatever its zone says.
DressingConfig.SHADOW_MIN_HEIGHT = 3

-- Clearance added around every footprint when it is claimed.
DressingConfig.FOOTPRINT_MARGIN = 0.6

-- Cluster centres: at least this far apart along the road on one side, and across sides.
DressingConfig.SPACING_SAME_SIDE = 30
DressingConfig.SPACING_ACROSS = 18
-- Two consecutive gaps on one side must differ by at least this much.
DressingConfig.GAP_DIFFERENCE = 4
-- Clusters keep this far from the chunk ends, whose ground the neighbour chunk dresses.
DressingConfig.END_CLEARANCE = 14

-- Members beyond this many in a cluster are detail.
DressingConfig.DETAIL_FROM_MEMBER = 3

DressingConfig.zones = {
	shoulder = { inner = 26, outer = 29.2, collide = false, shadow = false, detail = true },
	sidewalk = { inner = 30.6, outer = 34.4, collide = false, shadow = false, detail = true },
	edge = { inner = 35.5, outer = 43.5, collide = true, shadow = true, detail = false },
	apron = { inner = 44.5, outer = 59.5, collide = true, shadow = true, detail = false },
} :: { [string]: Zone }

-- Footprints (x, z, height in studs) used when a prop mesh is not loaded and the
-- primitive stands in for it. Real sizes come from WorldMeshes.naturalSize.
DressingConfig.fallbackSizes = {
	barrier = { 10.7, 2.2, 3 },
	sandbags = { 7.1, 2.1, 3.2 },
	hedgehog = { 5.4, 5.4, 5.4 },
	oil_barrel = { 2.1, 2.1, 3.2 },
	tyre = { 2.3, 2.3, 0.9 },
	trash = { 2.5, 2.5, 2.4 },
	rubble = { 9, 9, 3.6 },
	car_burned = { 6.4, 16, 5 },
	car_abandoned = { 6.4, 16, 5.2 },
	truck_crashed = { 9, 28, 11 },
	cone = { 1.4, 1.4, 2.5 },
	road_sign = { 2.2, 0.6, 8.5 },
} :: { [string]: { number } }

DressingConfig.recipes = {
	checkpoint = {
		members = {
			{ group = "barrier", count = { 2, 3 }, zone = "edge", layout = "line" },
			{ group = "sandbags", count = { 1, 1 }, zone = "edge", spread = 7, yaw = { -0.3, 0.3 } },
			{ group = "cone", count = { 1, 2 }, zone = "shoulder", spread = 9 },
			{ group = "road_sign", count = { 0, 1 }, zone = "edge", spread = 8, yaw = { -0.4, 0.4 } },
		},
	},
	abandoned = {
		members = {
			{ group = "car_abandoned", count = { 1, 1 }, zone = "edge", yaw = { -0.35, 0.35 } },
			{ group = "tyre", count = { 0, 2 }, zone = "shoulder", spread = 8 },
			{ group = "trash", count = { 1, 3 }, zone = "sidewalk", spread = 8 },
			{ group = "cone", count = { 0, 1 }, zone = "shoulder", spread = 9 },
		},
	},
	burned = {
		members = {
			{ group = "car_burned", count = { 1, 1 }, zone = "edge", yaw = { -0.5, 0.5 }, patch = "TFZ_GroundBurned" },
			{ group = "oil_barrel", count = { 1, 2 }, zone = "apron", spread = 9 },
			{ group = "rubble", count = { 0, 1 }, zone = "apron", spread = 10 },
		},
	},
	hedgehogs = {
		members = {
			{ group = "hedgehog", count = { 2, 3 }, zone = "edge", layout = "line" },
			{ group = "barrier", count = { 0, 1 }, zone = "edge", spread = 9, yaw = { 0, 0 } },
			{ group = "sandbags", count = { 0, 1 }, zone = "apron", spread = 9 },
		},
	},
	truck = {
		members = {
			{ group = "truck_crashed", count = { 1, 1 }, zone = "apron", yaw = { 0.6, 1 } },
			{ group = "cone", count = { 1, 3 }, zone = "shoulder", spread = 11 },
			{ group = "tyre", count = { 0, 2 }, zone = "edge", spread = 10 },
		},
	},
	dump = {
		members = {
			{ group = "tyre", count = { 2, 3 }, zone = "sidewalk", spread = 4 },
			{ group = "trash", count = { 1, 2 }, zone = "sidewalk", spread = 5 },
			{ group = "oil_barrel", count = { 0, 1 }, zone = "edge", spread = 5 },
		},
	},
	roadside = {
		members = {
			{ group = "road_sign", count = { 1, 1 }, zone = "edge", yaw = { -0.3, 0.3 } },
			{ group = "tyre", count = { 0, 1 }, zone = "shoulder", spread = 6 },
			{ group = "cone", count = { 0, 1 }, zone = "shoulder", spread = 6 },
		},
	},
	rubble = {
		members = {
			{ group = "rubble", count = { 1, 2 }, zone = "edge", spread = 8 },
			{ group = "oil_barrel", count = { 0, 2 }, zone = "apron", spread = 8 },
			{ group = "hedgehog", count = { 0, 1 }, zone = "edge", spread = 9 },
		},
	},
} :: { [string]: Recipe }

DressingConfig.biomes = {
	City = {
		clusters = { 4, 4 },
		sides = "alternate",
		recipes = { "checkpoint", "abandoned", "burned", "hedgehogs", "truck", "dump" },
		props = { 10, 18 },
	},
	Wasteland = {
		clusters = { 3, 3 },
		sides = "alternate",
		recipes = { "checkpoint", "burned", "hedgehogs", "truck", "rubble" },
		props = { 8, 14 },
	},
	Farmstead = {
		clusters = { 2, 2 },
		sides = "alternate",
		recipes = { "abandoned", "dump", "roadside" },
		props = { 4, 9 },
		-- between the rail fence at 34.5 and the crop rows from 42
		zones = { edge = { 35.5, 41.5 }, apron = { 35.5, 41.5 } },
	},
	Cornfield = {
		clusters = { 1, 1 },
		sides = "one",
		recipes = { "roadside" },
		props = { 2, 4 },
		-- the corn mesh rows start at 37, so the edge is the last free strip before them
		zones = { edge = { 30.6, 35 }, apron = { 30.6, 35 } },
	},
	Forest = {
		clusters = { 1, 1 },
		sides = "one",
		recipes = { "dump", "roadside" },
		props = { 2, 4 },
	},
} :: { [string]: BiomeRules }

-- Ground top per biome as a function of the distance from the centre line: the City
-- sidewalk is a 0.4 slab on the floor, the forest floor part is 0.2 on top of it.
DressingConfig.ground = {
	City = { { 30, 35, 0.9 } },
	Forest = { { 34, 228, 0.7 } },
} :: { [string]: { { number } } }
DressingConfig.GROUND_DEFAULT = 0.5

DressingConfig.materials = {
	City = {
		floor = "TFZ_AsphaltCracked",
		apron = "TFZ_ConcreteDirty",
		sidewalk = "TFZ_ConcreteDirty",
		divider = "TFZ_ConcreteDirty",
		facade = "TFZ_PlasterPeeling",
		facadeShare = 0.35,
		pole = "TFZ_PaintPeelingMetal",
	},
	Forest = {
		floor = "TFZ_Grass",
		apron = "TFZ_Grass",
		forestFloor = "TFZ_DirtDry",
	},
	Wasteland = {
		floor = "TFZ_RoadWorn",
		apron = "TFZ_DirtDry",
		divider = "TFZ_ConcreteDirty",
		ruin = "TFZ_ConcreteDirty",
		pole = "TFZ_MetalRusty",
		berm = "TFZ_Sand",
	},
	Farmstead = {
		floor = "TFZ_DirtDry",
		apron = "TFZ_Grass",
		barnRoof = "TFZ_MetalRusty",
	},
	Cornfield = {
		floor = "TFZ_DirtDry",
		apron = "TFZ_Grass",
	},
} :: { [string]: Materials }

-- Ground patch under burned props: a flat part painted with the variant.
DressingConfig.PATCH_SIZE = { 10, 16 }

DressingConfig.budgets = {
	desktop = { parts = 320, triangles = 320000, instances = 520, decals = 12, lights = 8, shadows = 80 },
	mobile = { parts = 240, triangles = 180000, instances = 360, decals = 6, lights = 4, shadows = 30 },
} :: { [string]: Budget }

-- Triangles per mesh, from the `triangles` field of assets/manifest.json. Props uploaded
-- as Models carry no count there and take TRIANGLES_DEFAULT until one is read in Studio.
DressingConfig.triangles = {
	tree_oak = 3918,
	tree_birch = 3994,
	tree_pine = 3998,
	tree_dead = 2914,
	bush = 2700,
	rock_boulder = 1498,
	car_sedan = 4440,
	car_pickup = 4908,
	car_police = 3802,
	car_hatch = 3888,
	car_van = 4738,
	car_wreck = 2488,
	crop_corn_row = 5994,
	grass_dry = 1472,
	building_brick = 2404,
	building_concrete = 2570,
	building_townhouse = 2929,
} :: { [string]: number }
DressingConfig.TRIANGLES_DEFAULT = 1500

-- Triangles per primitive shape, the engine's own meshes.
DressingConfig.primitiveTriangles = {
	Block = 12,
	Wedge = 8,
	Cylinder = 96,
	Ball = 96,
} :: { [string]: number }

-- Mesh trees stay inside this distance in the Forest near band; the rest are primitive.
DressingConfig.FOREST_MESH_TREE_MAX_X = 70

-- Share of City middle-band slots that take a building mesh; the rest stay facades.
DressingConfig.CITY_MIDDLE_MESH_SHARE = 0.75

return DressingConfig
