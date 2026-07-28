--!strict

export type SkinConfig = {
	id: string,
	displayName: string,
	description: string,
	price: number,
	defaultOwned: boolean,
	headColor: Color3,
	torsoColor: Color3,
	armColor: Color3,
	legColor: Color3,
}

local SkinsConfig = {}

SkinsConfig.DEFAULT_ID = "Recruit"

SkinsConfig.order = { "Recruit", "Ranger", "Medic", "Heavy", "Ghost" }

SkinsConfig.skins = {
	Recruit = {
		id = "Recruit",
		displayName = "Recruit",
		description = "Standard issue fatigues.",
		price = 0,
		defaultOwned = true,
		headColor = Color3.fromRGB(205, 170, 140),
		torsoColor = Color3.fromRGB(88, 100, 74),
		armColor = Color3.fromRGB(205, 170, 140),
		legColor = Color3.fromRGB(72, 82, 62),
	},
	Ranger = {
		id = "Ranger",
		displayName = "Ranger",
		description = "Woodland camo for forest runs.",
		price = 1200,
		defaultOwned = false,
		headColor = Color3.fromRGB(198, 162, 132),
		torsoColor = Color3.fromRGB(66, 86, 58),
		armColor = Color3.fromRGB(198, 162, 132),
		legColor = Color3.fromRGB(54, 70, 48),
	},
	Medic = {
		id = "Medic",
		displayName = "Field Medic",
		description = "White kit with red markings.",
		price = 1800,
		defaultOwned = false,
		headColor = Color3.fromRGB(205, 170, 140),
		torsoColor = Color3.fromRGB(222, 226, 228),
		armColor = Color3.fromRGB(205, 170, 140),
		legColor = Color3.fromRGB(120, 128, 132),
	},
	Heavy = {
		id = "Heavy",
		displayName = "Heavy Trooper",
		description = "Reinforced plating, urban grey.",
		price = 2600,
		defaultOwned = false,
		headColor = Color3.fromRGB(196, 160, 130),
		torsoColor = Color3.fromRGB(72, 76, 84),
		armColor = Color3.fromRGB(196, 160, 130),
		legColor = Color3.fromRGB(52, 56, 64),
	},
	Ghost = {
		id = "Ghost",
		displayName = "Ghost Operator",
		description = "Night operations blackout gear.",
		price = 4200,
		defaultOwned = false,
		headColor = Color3.fromRGB(70, 72, 78),
		torsoColor = Color3.fromRGB(34, 36, 40),
		armColor = Color3.fromRGB(48, 50, 56),
		legColor = Color3.fromRGB(28, 30, 34),
	},
} :: { [string]: SkinConfig }

function SkinsConfig.get(id: string): SkinConfig?
	return SkinsConfig.skins[id]
end

function SkinsConfig.isValid(id: string): boolean
	return SkinsConfig.skins[id] ~= nil
end

return SkinsConfig
