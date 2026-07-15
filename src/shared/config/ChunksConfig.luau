--!strict

export type ChunkConfig = {
	id: string,
	weight: number,
	floorColor: Color3,
}

local ChunksConfig: { ChunkConfig } = {
	{ id = "Asphalt", weight = 3, floorColor = Color3.fromRGB(99, 95, 98) },
	{ id = "Dirt", weight = 2, floorColor = Color3.fromRGB(124, 92, 70) },
	{ id = "Grass", weight = 2, floorColor = Color3.fromRGB(91, 154, 76) },
}

return table.freeze(ChunksConfig)
