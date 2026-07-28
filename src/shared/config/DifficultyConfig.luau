--!strict

export type DifficultySetting = {
	id: string,
	zombiesChase: boolean,
	zombieSpeedMultiplier: number,
	rewardMultiplier: number,
	aggroDistance: number,
	obstacleDensity: number,
	ammoCrateChance: number,
}

local DifficultyConfig: { [string]: DifficultySetting } = {
	Easy = {
		id = "Easy",
		zombiesChase = false,
		zombieSpeedMultiplier = 0,
		rewardMultiplier = 1,
		aggroDistance = math.huge,
		obstacleDensity = 0.8,
		ammoCrateChance = 0.5,
	},
	Medium = {
		id = "Medium",
		zombiesChase = true,
		zombieSpeedMultiplier = 0.6,
		rewardMultiplier = 1.25,
		aggroDistance = 500,
		obstacleDensity = 1.6,
		ammoCrateChance = 0.38,
	},
	Hard = {
		id = "Hard",
		zombiesChase = true,
		zombieSpeedMultiplier = 1.15,
		rewardMultiplier = 1.5,
		aggroDistance = 0,
		obstacleDensity = 2.6,
		ammoCrateChance = 0.28,
	},
}

return table.freeze(DifficultyConfig)
