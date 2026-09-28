--!strict

export type DifficultySetting = {
	id: string,
	zombiesChase: boolean,
	zombieSpeedMultiplier: number,
	rewardMultiplier: number,
	aggroDistance: number,
	damageMultiplier: number,
	grabLethal: boolean,
	obstacleDensity: number,
	ammoCrateChance: number,
}

local DifficultyConfig: { [string]: DifficultySetting } = {
	Easy = {
		id = "Easy",
		zombiesChase = true,
		zombieSpeedMultiplier = 0.45,
		rewardMultiplier = 1,
		aggroDistance = 300,
		damageMultiplier = 0.6,
		grabLethal = false,
		obstacleDensity = 0.8,
		ammoCrateChance = 0.5,
	},
	Medium = {
		id = "Medium",
		zombiesChase = true,
		zombieSpeedMultiplier = 0.6,
		rewardMultiplier = 1.25,
		aggroDistance = 0,
		damageMultiplier = 1,
		grabLethal = true,
		obstacleDensity = 1.6,
		ammoCrateChance = 0.38,
	},
	Hard = {
		id = "Hard",
		zombiesChase = true,
		zombieSpeedMultiplier = 1.15,
		rewardMultiplier = 1.5,
		aggroDistance = 0,
		damageMultiplier = 1.35,
		grabLethal = true,
		obstacleDensity = 2.6,
		ammoCrateChance = 0.28,
	},
}

return table.freeze(DifficultyConfig)
