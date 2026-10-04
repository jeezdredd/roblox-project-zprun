--!strict

-- Maps (wiki: Map Segments). A run is a chain of maps, each a long stretch built from
-- its own sub-locations (LocationsConfig ids, mixed inside the map for variety). The
-- squad leader picks the start map in the helicopter lobby; every map ends in a fork
-- between two of its neighbours, both prepared while the squad runs the map, and the
-- map boundary blends over MAP_TRANSITION_CHUNKS, lighting and ambience included.
-- Data only, no engine types: MapMath and its tests (tests/world) read it under the
-- standalone Luau CLI.

export type Range = { min: number, max: number }

export type SpeedProfile = {
	-- studs per second at the map's start, the peak and the seconds of the ramp between
	-- (DistanceTracker's locationTargetSpeed); nil peak is a constant speed
	initial: number,
	max: number?,
	rampTime: number?,
}

export type MapConfig = {
	id: string,
	displayName: string,
	-- listed in the lobby and reachable at forks; content still missing otherwise
	enabled: boolean,
	-- sub-locations (LocationsConfig ids), drawn in turn, never the same one twice running
	locationIds: { string },
	-- how long the squad should run it, seconds, drawn per run
	durationSeconds: Range,
	-- maps a fork at this map's end may offer; only enabled ones are used
	neighbours: { string },
	-- LightingConfig preset (its night variant at night)
	lighting: string,
	-- AssetIds.audio.ambience key of the map's ambience bed (silent while its id is 0)
	ambience: string,
	-- seconds the server needs to warm this map's chunk pools (the floor of the map
	-- before it); an estimate, measured in Studio (wiki: Map Segments)
	preloadSeconds: number,
	-- WorldMeshConfig groups the clients preload while the map is a fork option
	preloadGroups: { string },
	-- the run speed expected here; nil uses GameConstants.BASE_RUN_SPEED throughout
	speed: SpeedProfile?,
}

local MapsConfig = {}

-- the lobby's "pick one for me": any enabled map, drawn from the run's seed
MapsConfig.RANDOM_ID = "Random"
MapsConfig.DEFAULT_ID = "City"

-- lobby order; disabled maps are left out of the lobby
MapsConfig.order = { "Random", "City", "Wasteland", "Forest", "Farmland", "Suburbs", "Highway", "Desert", "Mountains", "Swamp" }

MapsConfig.DEFAULT_DURATION = { min = 120, max = 180 } :: Range

-- chunks over which one map blends into the next: the first chunks of the new map,
-- each a step further from the old one (floor, apron, edge props, flanks, dressing)
MapsConfig.MAP_TRANSITION_CHUNKS = 5

-- a map is never shorter than SPAWN_AHEAD_DISTANCE + MAX_RUN_SPEED * preloadSeconds of
-- the slower next option * FLOOR_FACTOR (the owner's "speed x build time" rule)
MapsConfig.FLOOR_FACTOR = 1.5

-- chunk pools warmed per sub-location of each fork option, and the frame budget
MapsConfig.POOL_WARM_CHUNKS = 3
MapsConfig.WARM_BUDGET_MS = 4

MapsConfig.maps = {
	City = {
		id = "City",
		displayName = "City",
		enabled = true,
		locationIds = { "City" },
		durationSeconds = MapsConfig.DEFAULT_DURATION,
		neighbours = { "Wasteland", "Forest", "Suburbs", "Highway" },
		lighting = "City",
		ambience = "city_bed",
		preloadSeconds = 6,
		preloadGroups = { "building", "car", "car_police", "barrier", "rubble", "car_burned", "road_sign", "cone", "trash" },
	},
	Wasteland = {
		id = "Wasteland",
		displayName = "Wasteland",
		enabled = true,
		locationIds = { "Wasteland" },
		durationSeconds = MapsConfig.DEFAULT_DURATION,
		neighbours = { "City", "Forest", "Farmland", "Highway", "Desert" },
		lighting = "Wasteland",
		ambience = "wasteland_bed",
		preloadSeconds = 4,
		preloadGroups = { "tree_dead", "car_wreck", "rubble", "boulder", "car_burned", "truck_crashed", "barrier" },
	},
	Forest = {
		id = "Forest",
		displayName = "Forest",
		enabled = true,
		locationIds = { "Forest" },
		durationSeconds = MapsConfig.DEFAULT_DURATION,
		neighbours = { "City", "Wasteland", "Farmland", "Mountains", "Swamp" },
		lighting = "Forest",
		ambience = "forest_bed",
		preloadSeconds = 5,
		preloadGroups = { "tree_any", "tree_dead", "bush", "boulder" },
	},
	Farmland = {
		id = "Farmland",
		displayName = "Farmland",
		enabled = true,
		locationIds = { "Farmstead", "Cornfield" },
		durationSeconds = MapsConfig.DEFAULT_DURATION,
		neighbours = { "Forest", "Wasteland", "Suburbs" },
		lighting = "Farmstead",
		ambience = "farmland_bed",
		preloadSeconds = 5,
		preloadGroups = { "corn", "grass_dry", "tree_leafy", "bush", "supply_crate" },
	},

	-- no content yet: kept here so the neighbour graph is planned, never offered
	Suburbs = {
		id = "Suburbs",
		displayName = "Suburbs",
		enabled = false,
		locationIds = {},
		durationSeconds = MapsConfig.DEFAULT_DURATION,
		neighbours = { "City", "Farmland", "Highway" },
		lighting = "City",
		ambience = "suburbs_bed",
		preloadSeconds = 6,
		preloadGroups = {},
	},
	Highway = {
		id = "Highway",
		displayName = "Highway",
		enabled = false,
		locationIds = {},
		durationSeconds = MapsConfig.DEFAULT_DURATION,
		neighbours = { "City", "Wasteland", "Suburbs", "Desert" },
		lighting = "Wasteland",
		ambience = "highway_bed",
		preloadSeconds = 4,
		preloadGroups = {},
	},
	Desert = {
		id = "Desert",
		displayName = "Desert",
		enabled = false,
		locationIds = {},
		durationSeconds = MapsConfig.DEFAULT_DURATION,
		neighbours = { "Wasteland", "Highway", "Mountains" },
		lighting = "Wasteland",
		ambience = "desert_bed",
		preloadSeconds = 4,
		preloadGroups = {},
	},
	Mountains = {
		id = "Mountains",
		displayName = "Mountains",
		enabled = false,
		locationIds = {},
		durationSeconds = MapsConfig.DEFAULT_DURATION,
		neighbours = { "Forest", "Desert", "Swamp" },
		lighting = "Forest",
		ambience = "mountains_bed",
		preloadSeconds = 5,
		preloadGroups = {},
	},
	Swamp = {
		id = "Swamp",
		displayName = "Swamp",
		enabled = false,
		locationIds = {},
		durationSeconds = MapsConfig.DEFAULT_DURATION,
		neighbours = { "Forest", "Mountains" },
		lighting = "Forest",
		ambience = "swamp_bed",
		preloadSeconds = 5,
		preloadGroups = {},
	},
} :: { [string]: MapConfig }

function MapsConfig.get(id: string): MapConfig?
	return MapsConfig.maps[id]
end

-- A map that can be run: listed and enabled.
function MapsConfig.isValid(id: string): boolean
	local map = MapsConfig.maps[id]
	return map ~= nil and map.enabled
end

-- What the lobby may send: an enabled map or Random.
function MapsConfig.isSelectable(id: string): boolean
	return id == MapsConfig.RANDOM_ID or MapsConfig.isValid(id)
end

-- Enabled map ids in lobby order.
function MapsConfig.enabledIds(): { string }
	local out = {}
	for _, id in MapsConfig.order do
		if MapsConfig.isValid(id) then
			table.insert(out, id)
		end
	end
	return out
end

return MapsConfig
