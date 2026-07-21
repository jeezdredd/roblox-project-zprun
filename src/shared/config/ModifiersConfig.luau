--!strict

export type ModifierConfig = {
	id: string,
	displayName: string,
	description: string,
	rewardMultiplier: number,
	zombieSpeedBonus: number,
	nightMode: boolean,
}

local ModifiersConfig = {}

ModifiersConfig.order = { "FastZombies", "Night", "Forest" }

ModifiersConfig.modifiers = {
	FastZombies = {
		id = "FastZombies",
		displayName = "Fast Zombies",
		description = "Zombies move faster.",
		rewardMultiplier = 1.3,
		zombieSpeedBonus = 0.5,
		nightMode = false,
	},
	Night = {
		id = "Night",
		displayName = "Night",
		description = "Darkness falls over the run.",
		rewardMultiplier = 1.2,
		zombieSpeedBonus = 0,
		nightMode = true,
	},
	Forest = {
		id = "Forest",
		displayName = "Forest",
		description = "Denser terrain, less room to move.",
		rewardMultiplier = 1.25,
		zombieSpeedBonus = 0,
		nightMode = false,
	},
} :: { [string]: ModifierConfig }

function ModifiersConfig.get(id: string): ModifierConfig?
	return ModifiersConfig.modifiers[id]
end

function ModifiersConfig.isValid(id: string): boolean
	return ModifiersConfig.modifiers[id] ~= nil
end

return ModifiersConfig
