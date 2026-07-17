--!strict

export type ChunkConfig = {
	id: string,
	weight: number,
	floorColor: Color3,
	zombiesMin: number,
	zombiesMax: number,
}

local ChunksConfig: { ChunkConfig } = {
	{ id = "Asphalt", weight = 3, floorColor = Color3.fromRGB(99, 95, 98), zombiesMin = 1, zombiesMax = 3 },
	{ id = "Dirt", weight = 2, floorColor = Color3.fromRGB(124, 92, 70), zombiesMin = 2, zombiesMax = 4 },
	{ id = "Grass", weight = 2, floorColor = Color3.fromRGB(91, 154, 76), zombiesMin = 2, zombiesMax = 5 },
}

return table.freeze(ChunksConfig)
