--!strict

export type LocationConfig = {
	id: string,
	displayName: string,
	lengthChunksMin: number,
	lengthChunksMax: number,
	floorMaterial: Enum.Material,
	floorColor: Color3,
	apronMaterial: Enum.Material,
	apronColor: Color3,
	edgeProps: string,
	lanePropChance: number,
	roadMarkings: boolean,
	zombiesMin: number,
	zombiesMax: number,
}

local LocationsConfig = {}

LocationsConfig.order = { "City", "Forest", "Wasteland" }

LocationsConfig.locations = {
	City = {
		id = "City",
		displayName = "City",
		lengthChunksMin = 4,
		lengthChunksMax = 8,
		floorMaterial = Enum.Material.Asphalt,
		floorColor = Color3.fromRGB(86, 86, 92),
		apronMaterial = Enum.Material.Concrete,
		apronColor = Color3.fromRGB(128, 128, 132),
		edgeProps = "buildings",
		lanePropChance = 0.75,
		roadMarkings = true,
		zombiesMin = 2,
		zombiesMax = 4,
	},
	Forest = {
		id = "Forest",
		displayName = "Forest",
		lengthChunksMin = 4,
		lengthChunksMax = 8,
		floorMaterial = Enum.Material.Ground,
		floorColor = Color3.fromRGB(110, 92, 70),
		apronMaterial = Enum.Material.Grass,
		apronColor = Color3.fromRGB(82, 126, 70),
		edgeProps = "trees",
		lanePropChance = 0.55,
		roadMarkings = false,
		zombiesMin = 2,
		zombiesMax = 5,
	},
	Wasteland = {
		id = "Wasteland",
		displayName = "Wasteland",
		lengthChunksMin = 3,
		lengthChunksMax = 5,
		floorMaterial = Enum.Material.Ground,
		floorColor = Color3.fromRGB(124, 108, 86),
		apronMaterial = Enum.Material.Ground,
		apronColor = Color3.fromRGB(112, 98, 80),
		edgeProps = "ruins",
		lanePropChance = 0.6,
		roadMarkings = false,
		zombiesMin = 3,
		zombiesMax = 5,
	},
} :: { [string]: LocationConfig }

function LocationsConfig.get(id: string): LocationConfig?
	return LocationsConfig.locations[id]
end

function LocationsConfig.isValid(id: string): boolean
	return LocationsConfig.locations[id] ~= nil
end

return LocationsConfig
