--!strict

export type DifficultySetting = {
	id: string,
	zombiesChase: boolean,
	zombieSpeedMultiplier: number,
	rewardMultiplier: number,
}

local DifficultyConfig: { [string]: DifficultySetting } = {
	Easy = {
		id = "Easy",
		zombiesChase = false,
		zombieSpeedMultiplier = 0,
		rewardMultiplier = 1,
	},
	Medium = {
		id = "Medium",
		zombiesChase = true,
		zombieSpeedMultiplier = 0.5,
		rewardMultiplier = 1.25,
	},
	Hard = {
		id = "Hard",
		zombiesChase = true,
		zombieSpeedMultiplier = 1.2,
		rewardMultiplier = 1.5,
	},
}

return table.freeze(DifficultyConfig)
