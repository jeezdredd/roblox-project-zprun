--!strict

export type Range = { min: number, max: number }

export type SpeedProfile = {
	initial: number,
	max: number?,
	rampTime: number?,
}

export type MapConfig = {
	id: string,
	displayName: string,
	enabled: boolean,
	locationIds: { string },
	durationSeconds: Range,
	neighbours: { string },
	lighting: string,
	ambience: string,
	preloadSeconds: number,
	preloadGroups: { string },
	speed: SpeedProfile?,
}

local MapsConfig = {}

MapsConfig.RANDOM_ID = "Random"
MapsConfig.DEFAULT_ID = "City"

MapsConfig.order = { "Random", "City", "Wasteland", "Forest", "Farmland", "Suburbs", "Highway", "Desert", "Mountains", "Swamp" }

MapsConfig.DEFAULT_DURATION = { min = 120, max = 180 } :: Range

MapsConfig.MAP_TRANSITION_CHUNKS = 5

MapsConfig.FLOOR_FACTOR = 1.5

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

function MapsConfig.isValid(id: string): boolean
	local map = MapsConfig.maps[id]
	return map ~= nil and map.enabled
end

function MapsConfig.isSelectable(id: string): boolean
	return id == MapsConfig.RANDOM_ID or MapsConfig.isValid(id)
end

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
