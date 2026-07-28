--!strict

export type GoalConfig = {
	id: string,
	displayName: string,
	description: string,
	metric: string,
	target: number,
	rewardCredits: number,
}

local MissionGoalsConfig = {}

MissionGoalsConfig.order = { "Distance1500", "Kills25", "NoDamage500" }

MissionGoalsConfig.goals = {
	Distance1500 = {
		id = "Distance1500",
		displayName = "Long Haul",
		description = "Cover 1500 studs in a single run.",
		metric = "Distance",
		target = 1500,
		rewardCredits = 250,
	},
	Kills25 = {
		id = "Kills25",
		displayName = "Cleanup",
		description = "Put down 25 walkers in a single run.",
		metric = "Kills",
		target = 25,
		rewardCredits = 300,
	},
	NoDamage500 = {
		id = "NoDamage500",
		displayName = "Untouched",
		description = "Cover 500 studs without taking damage.",
		metric = "CleanDistance",
		target = 500,
		rewardCredits = 200,
	},
} :: { [string]: GoalConfig }

function MissionGoalsConfig.get(id: string): GoalConfig?
	return MissionGoalsConfig.goals[id]
end

return table.freeze(MissionGoalsConfig)
