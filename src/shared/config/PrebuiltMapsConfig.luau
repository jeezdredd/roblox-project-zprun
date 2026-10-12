--!strict

export type MapEntry = {
	map: string,
	enabled: boolean,
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

PrebuiltMapsConfig.maps = {} :: { MapEntry }

PrebuiltMapsConfig.LOAD_CONCURRENCY = 4

PrebuiltMapsConfig.MESH_TURN_DEGREES = 0

PrebuiltMapsConfig.SHADOW_MIN_SIZE = 2

PrebuiltMapsConfig.budgets = {
	desktop = { meshes = 60, triangles = 120000, textures = 12 },
	mobile = { meshes = 30, triangles = 50000, textures = 6 },
} :: { [string]: Budget }

PrebuiltMapsConfig.mapBudgets = {
	desktop = { meshes = 4000, triangles = 3000000, textures = 400 },
	mobile = { meshes = 2000, triangles = 1200000, textures = 200 },
} :: { [string]: Budget }

return PrebuiltMapsConfig
