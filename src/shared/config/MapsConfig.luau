--!strict

export type MapConfig = {
	id: string,
	displayName: string,
	locationIds: { string },
	ambientTint: Color3,
}

local MapsConfig = {}

MapsConfig.DEFAULT_ID = "City"

MapsConfig.order = { "City", "Forest", "Mixed" }

MapsConfig.maps = {
	City = {
		id = "City",
		displayName = "City",
		locationIds = { "City", "Wasteland" },
		ambientTint = Color3.fromRGB(120, 122, 130),
	},
	Forest = {
		id = "Forest",
		displayName = "Forest",
		locationIds = { "Forest", "Wasteland" },
		ambientTint = Color3.fromRGB(100, 125, 95),
	},
	Mixed = {
		id = "Mixed",
		displayName = "Mixed Route",
		locationIds = { "City", "Forest", "Wasteland" },
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
