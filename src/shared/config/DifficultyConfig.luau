--!strict

export type DifficultySetting = {
	id: string,
	zombiesChase: boolean,
	zombieSpeedMultiplier: number,
	rewardMultiplier: number,
	aggroDistance: number,
}

local DifficultyConfig: { [string]: DifficultySetting } = {
	Easy = {
		id = "Easy",
		zombiesChase = false,
		zombieSpeedMultiplier = 0,
		rewardMultiplier = 1,
		aggroDistance = math.huge,
	},
	Medium = {
		id = "Medium",
		zombiesChase = true,
		zombieSpeedMultiplier = 0.6,
		rewardMultiplier = 1.25,
		aggroDistance = 500,
	},
	Hard = {
		id = "Hard",
		zombiesChase = true,
		zombieSpeedMultiplier = 1.15,
		rewardMultiplier = 1.5,
		aggroDistance = 0,
	},
}

return table.freeze(DifficultyConfig)
