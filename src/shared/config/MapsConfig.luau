--!strict

export type MapConfig = {
	id: string,
	displayName: string,
	chunkIds: { string },
	ambientTint: Color3,
}

local MapsConfig = {}

MapsConfig.DEFAULT_ID = "City"

MapsConfig.order = { "City", "Forest", "Mixed" }

MapsConfig.maps = {
	City = {
		id = "City",
		displayName = "City",
		chunkIds = { "Asphalt", "Dirt" },
		ambientTint = Color3.fromRGB(120, 122, 130),
	},
	Forest = {
		id = "Forest",
		displayName = "Forest",
		chunkIds = { "Grass", "Dirt" },
		ambientTint = Color3.fromRGB(100, 125, 95),
	},
	Mixed = {
		id = "Mixed",
		displayName = "Mixed Route",
		chunkIds = { "Asphalt", "Dirt", "Grass" },
		ambientTint = Color3.fromRGB(118, 120, 118),
	},
} :: { [string]: MapConfig }

function MapsConfig.get(id: string): MapConfig?
	return MapsConfig.maps[id]
end

function MapsConfig.isValid(id: string): boolean
	return MapsConfig.maps[id] ~= nil
end

return MapsConfig
