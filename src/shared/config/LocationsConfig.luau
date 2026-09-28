--!strict

local TexturesConfig = require(script.Parent.TexturesConfig)

export type LocationConfig = {
	id: string,
	displayName: string,
	lengthChunksMin: number,
	lengthChunksMax: number,
	floorMaterial: Enum.Material,
	floorColor: Color3,
	floorTextureId: number,
	apronMaterial: Enum.Material,
	apronColor: Color3,
	apronTextureId: number,
	edgeProps: string,
	laneStyle: string,
	roadMarkings: boolean,
	zombiesMin: number,
	zombiesMax: number,
	spawnSections: { string }?,
	runSpeedInitial: number?,
	runSpeedMax: number?,
	runSpeedRampTime: number?,
}

local LocationsConfig = {}

LocationsConfig.order = { "City", "Forest", "Wasteland", "Farmstead", "Cornfield" }

LocationsConfig.locations = {
	City = {
		id = "City",
		displayName = "City",
		lengthChunksMin = 4,
		lengthChunksMax = 8,
		floorMaterial = Enum.Material.Asphalt,
		floorColor = Color3.fromRGB(200, 200, 204),
		floorTextureId = TexturesConfig.ASPHALT,
		apronMaterial = Enum.Material.Concrete,
		apronColor = Color3.fromRGB(210, 210, 212),
		apronTextureId = TexturesConfig.CONCRETE,
		edgeProps = "buildings",
		laneStyle = "road",
		roadMarkings = true,
		zombiesMin = 2,
		zombiesMax = 4,
		spawnSections = { "Steady_Mixed", "Pressure_Mixed", "Pressure_Clumped" },
	},
	Forest = {
		id = "Forest",
		displayName = "Forest",
		lengthChunksMin = 4,
		lengthChunksMax = 8,
		floorMaterial = Enum.Material.Grass,
		floorColor = Color3.fromRGB(190, 210, 185),
		floorTextureId = TexturesConfig.GRASS,
		apronMaterial = Enum.Material.Grass,
		apronColor = Color3.fromRGB(190, 210, 185),
		apronTextureId = TexturesConfig.GRASS,
		edgeProps = "trees",
		laneStyle = "field",
		roadMarkings = false,
		zombiesMin = 2,
		zombiesMax = 5,
		spawnSections = { "Calm_Open", "Steady_Walkers", "Pressure_Mixed" },
	},
	Wasteland = {
		id = "Wasteland",
		displayName = "Wasteland",
		lengthChunksMin = 3,
		lengthChunksMax = 5,
		floorMaterial = Enum.Material.Ground,
		floorColor = Color3.fromRGB(210, 200, 188),
		floorTextureId = TexturesConfig.GROUND,
		apronMaterial = Enum.Material.Ground,
		apronColor = Color3.fromRGB(200, 190, 178),
		apronTextureId = TexturesConfig.GROUND,
		edgeProps = "ruins",
		laneStyle = "road",
		roadMarkings = false,
		zombiesMin = 3,
		zombiesMax = 5,
		spawnSections = { "Steady_Mixed", "Heavy_Clumped" },
	},
	Farmstead = {
		id = "Farmstead",
		displayName = "Farmstead",
		lengthChunksMin = 4,
		lengthChunksMax = 7,
		floorMaterial = Enum.Material.Ground,
		floorColor = Color3.fromRGB(196, 176, 132),
		floorTextureId = TexturesConfig.GROUND,
		apronMaterial = Enum.Material.Grass,
		apronColor = Color3.fromRGB(186, 168, 108),
		apronTextureId = TexturesConfig.GRASS,
		edgeProps = "farm",
		laneStyle = "field",
		roadMarkings = false,
		zombiesMin = 2,
		zombiesMax = 5,
		spawnSections = { "Steady_Walkers", "Steady_Mixed", "Pressure_Clumped" },
	},
	Cornfield = {
		id = "Cornfield",
		displayName = "Cornfield",
		lengthChunksMin = 3,
		lengthChunksMax = 6,
		floorMaterial = Enum.Material.Ground,
		floorColor = Color3.fromRGB(150, 138, 104),
		floorTextureId = TexturesConfig.GROUND,
		apronMaterial = Enum.Material.Grass,
		apronColor = Color3.fromRGB(126, 122, 82),
		apronTextureId = TexturesConfig.GRASS,
		edgeProps = "corn",
		laneStyle = "field",
		roadMarkings = false,
		zombiesMin = 2,
		zombiesMax = 4,
		spawnSections = { "Calm_Open", "Pressure_Clumped" },
	},
} :: { [string]: LocationConfig }

function LocationsConfig.get(id: string): LocationConfig?
	return LocationsConfig.locations[id]
end

function LocationsConfig.isValid(id: string): boolean
	return LocationsConfig.locations[id] ~= nil
end

return LocationsConfig
