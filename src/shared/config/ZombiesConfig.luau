--!strict

export type ZombieConfig = {
	id: string,
	weight: number,
	maxHealth: number,
	walkSpeed: number,
	touchDamage: number,
	damageCooldown: number,
	reactionDelay: number,
	bodyColor: Color3,
}

local ZombiesConfig: { ZombieConfig } = {
	{
		id = "Walker",
		weight = 4,
		maxHealth = 100,
		walkSpeed = 14,
		touchDamage = 15,
		damageCooldown = 1,
		reactionDelay = 0.75,
		bodyColor = Color3.fromRGB(88, 122, 82),
	},
	{
		id = "Runner",
		weight = 1,
		maxHealth = 60,
		walkSpeed = 22,
		touchDamage = 10,
		damageCooldown = 0.8,
		reactionDelay = 0.35,
		bodyColor = Color3.fromRGB(140, 110, 70),
	},
}

return table.freeze(ZombiesConfig)
