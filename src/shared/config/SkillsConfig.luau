--!strict

export type SkillConfig = {
	id: string,
	displayName: string,
	description: string,
	maxLevel: number,
	basePrice: number,
	priceStep: number,
	valuePerLevel: number,
	unit: string,
}

local SkillsConfig = {}

SkillsConfig.order = { "Toughness", "Endurance", "FastHands", "Scavenger" }

SkillsConfig.skills = {
	Toughness = {
		id = "Toughness",
		displayName = "Toughness",
		description = "More health before you go down.",
		maxLevel = 3,
		basePrice = 600,
		priceStep = 700,
		valuePerLevel = 20,
		unit = "HP",
	},
	Endurance = {
		id = "Endurance",
		displayName = "Endurance",
		description = "Higher top running speed.",
		maxLevel = 3,
		basePrice = 800,
		priceStep = 900,
		valuePerLevel = 2,
		unit = "speed",
	},
	FastHands = {
		id = "FastHands",
		displayName = "Fast Hands",
		description = "Faster reloads.",
		maxLevel = 3,
		basePrice = 700,
		priceStep = 800,
		valuePerLevel = 12,
		unit = "% faster",
	},
	Scavenger = {
		id = "Scavenger",
		displayName = "Scavenger",
		description = "More ammo from crates.",
		maxLevel = 3,
		basePrice = 500,
		priceStep = 650,
		valuePerLevel = 25,
		unit = "% ammo",
	},
} :: { [string]: SkillConfig }

function SkillsConfig.get(id: string): SkillConfig?
	return SkillsConfig.skills[id]
end

function SkillsConfig.priceFor(config: SkillConfig, currentLevel: number): number
	return config.basePrice + config.priceStep * currentLevel
end

return table.freeze(SkillsConfig)
