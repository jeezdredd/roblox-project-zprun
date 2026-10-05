--!strict

-- Prebuilt maps: large static scenes split into cells by tools/city_import/split_scene.py,
-- uploaded as Model assets through the manifest and placed by PrebuiltMaps under
-- Workspace.PrebuiltMaps/<map> (docs/environment/prebuilt-maps.md). Data only, no engine
-- types, so PrebuiltMapMath and its tests can load it.

export type MapEntry = {
	-- the layout module src/server/prebuilt/<map>.luau and the manifest's model/maps/<map>/
	map: string,
	enabled: boolean,
	-- where the scene's origin goes, in studs, and a turn about Y in degrees
	origin: { number },
	yaw: number,
}

export type Budget = {
	meshes: number,
	triangles: number,
	textures: number,
}

local PrebuiltMapsConfig = {}

PrebuiltMapsConfig.ENABLED = true

PrebuiltMapsConfig.FOLDER = "PrebuiltMaps"

-- No map is listed until one has been split and uploaded. Example:
--   { map = "city", enabled = true, origin = { 0, 0, -4000 }, yaw = 0 },
PrebuiltMapsConfig.maps = {} :: { MapEntry }

-- workers loading cells (InsertService:LoadAsset plus the collision refits), each taking
-- the next cell when it is done
PrebuiltMapsConfig.LOAD_CONCURRENCY = 4

-- split_scene.py writes the geometry turned 180 degrees about Y because the Roblox glTF
-- importer turns meshes that way; if a Studio check shows the cells' meshes facing
-- backwards, the importer changed and this is set to 180
PrebuiltMapsConfig.MESH_TURN_DEGREES = 0

-- parts smaller than this (largest side, studs) cast no shadow
PrebuiltMapsConfig.SHADOW_MIN_SIZE = 2

-- per cell, desktop and mobile, as in the chunk reports (DressingConfig.budgets)
PrebuiltMapsConfig.budgets = {
	desktop = { meshes = 60, triangles = 120000, textures = 12 },
	mobile = { meshes = 30, triangles = 50000, textures = 6 },
} :: { [string]: Budget }

-- the whole map, for the summary line
PrebuiltMapsConfig.mapBudgets = {
	desktop = { meshes = 4000, triangles = 3000000, textures = 400 },
	mobile = { meshes = 2000, triangles = 1200000, textures = 200 },
} :: { [string]: Budget }

return PrebuiltMapsConfig
