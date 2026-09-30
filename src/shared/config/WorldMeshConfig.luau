--!strict

-- Mesh set for world dressing (trees, rocks, cars, crops). Ids come from
-- assets/manifest.json (mesh/world/* and texture/world/*) through AssetIds. A mesh
-- with id 0 is simply skipped and the builders fall back to their primitive shapes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)

export type MeshEntry = {
	mesh: number,
	texture: number,
	-- Box for things that are boxes (cars), Hull for rocks. Trees never collide with
	-- their mesh: they get an invisible trunk collider instead.
	collision: Enum.CollisionFidelity,
	-- PBR look: the SurfaceAppearance of this name in ReplicatedStorage.PropSurfaces
	-- (assets/props/surfaces.model.json), used instead of `texture`
	surface: string?,
	-- studs per mesh unit at the prop's real size: the Sketchfab / Poly Haven props are
	-- modelled in metres and the world is 1 stud = 0.28 m (WorldMeshes.placeNatural)
	studsPerUnit: number?,
}

local meshIds = AssetIds.mesh.world
local textureIds = AssetIds.texture.world

local function entry(name: string, collision: Enum.CollisionFidelity): MeshEntry
	return {
		mesh = (meshIds :: any)[name] or 0,
		texture = (textureIds :: any)[name] or 0,
		collision = collision,
	}
end

-- 1 stud = 0.28 m
local METRE = 1 / 0.28

-- Post-apocalyptic props (assets/props, CC0 / CC BY, see LICENSES): mesh read back from
-- the Model upload, PBR maps as a SurfaceAppearance template of the same name.
local function prop(name: string, collision: Enum.CollisionFidelity): MeshEntry
	return {
		mesh = (AssetIds.mesh.props :: any)[name] or 0,
		texture = 0,
		collision = collision,
		surface = name,
		studsPerUnit = METRE,
	}
end

local WorldMeshConfig = {
	ENABLED = true,

	meshes = {
		tree_oak = entry("tree_oak", Enum.CollisionFidelity.Box),
		tree_birch = entry("tree_birch", Enum.CollisionFidelity.Box),
		tree_pine = entry("tree_pine", Enum.CollisionFidelity.Box),
		tree_dead = entry("tree_dead", Enum.CollisionFidelity.Box),
		bush = entry("bush", Enum.CollisionFidelity.Box),
		rock_boulder = entry("rock_boulder", Enum.CollisionFidelity.Hull),
		car_sedan = entry("car_sedan", Enum.CollisionFidelity.Box),
		car_pickup = entry("car_pickup", Enum.CollisionFidelity.Box),
		car_police = entry("car_police", Enum.CollisionFidelity.Box),
		car_wreck = {
			mesh = AssetIds.mesh.props.car_wreck,
			texture = AssetIds.texture.props.car_wreck,
			collision = Enum.CollisionFidelity.Box,
		},
		-- the crashed supply drop (WeaponPickups); a Cube 3D box, placed by height
		supply_crate = {
			mesh = AssetIds.mesh.props.supply_crate,
			texture = 0,
			collision = Enum.CollisionFidelity.Box,
		},
		crop_corn_row = entry("crop_corn_row", Enum.CollisionFidelity.Box),
		grass_dry = entry("grass_dry", Enum.CollisionFidelity.Box),
		car_hatch = entry("car_hatch", Enum.CollisionFidelity.Box),
		car_van = entry("car_van", Enum.CollisionFidelity.Box),
		-- the textured street face is +Z in the mesh; WorldFlanks turns it to the road
		building_brick = entry("building_brick", Enum.CollisionFidelity.Box),
		building_concrete = entry("building_concrete", Enum.CollisionFidelity.Box),
		building_townhouse = entry("building_townhouse", Enum.CollisionFidelity.Box),

		concrete_barrier = prop("concrete_barrier", Enum.CollisionFidelity.Box),
		concrete_barrier_b = prop("concrete_barrier_b", Enum.CollisionFidelity.Box),
		sandbag_wall = prop("sandbag_wall", Enum.CollisionFidelity.Box),
		czech_hedgehog = prop("czech_hedgehog", Enum.CollisionFidelity.Hull),
		oil_barrel = prop("oil_barrel", Enum.CollisionFidelity.Box),
		tyre = prop("tyre", Enum.CollisionFidelity.Box),
		trash_bag = prop("trash_bag", Enum.CollisionFidelity.Box),
		rubble_pile = prop("rubble_pile", Enum.CollisionFidelity.Hull),
		car_burned_a = prop("car_burned_a", Enum.CollisionFidelity.Box),
		car_burned_b = prop("car_burned_b", Enum.CollisionFidelity.Box),
		car_crashed = prop("car_crashed", Enum.CollisionFidelity.Box),
		truck_crashed = prop("truck_crashed", Enum.CollisionFidelity.Box),
		covered_car = prop("covered_car", Enum.CollisionFidelity.Box),
		traffic_cone = prop("traffic_cone", Enum.CollisionFidelity.Box),
		road_sign_stop = prop("road_sign_stop", Enum.CollisionFidelity.Box),
		road_sign_curve = prop("road_sign_curve", Enum.CollisionFidelity.Box),
	} :: { [string]: MeshEntry },

	-- Builders ask for a group and get one of its loaded members at random.
	groups = {
		tree_leafy = { "tree_oak", "tree_birch" },
		tree_pine = { "tree_pine" },
		tree_any = { "tree_oak", "tree_birch", "tree_pine" },
		tree_dead = { "tree_dead" },
		bush = { "bush" },
		boulder = { "rock_boulder" },
		car = { "car_sedan", "car_hatch", "car_pickup", "car_sedan", "car_hatch", "car_van" },
		car_police = { "car_police" },
		supply_crate = { "supply_crate" },
		car_wreck = { "car_wreck" },
		corn = { "crop_corn_row" },
		grass_dry = { "grass_dry" },
		building = { "building_brick", "building_concrete", "building_townhouse" },

		barrier = { "concrete_barrier", "concrete_barrier_b" },
		sandbags = { "sandbag_wall" },
		hedgehog = { "czech_hedgehog" },
		oil_barrel = { "oil_barrel" },
		tyre = { "tyre" },
		trash = { "trash_bag" },
		rubble = { "rubble_pile" },
		car_burned = { "car_burned_a", "car_burned_b" },
		car_abandoned = { "car_crashed", "covered_car" },
		truck_crashed = { "truck_crashed" },
		cone = { "traffic_cone" },
		road_sign = { "road_sign_stop", "road_sign_curve" },
	} :: { [string]: { string } },
}

return WorldMeshConfig
