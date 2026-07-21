--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DifficultyConfig = require(ReplicatedStorage.Shared.config.DifficultyConfig)
local ModifiersConfig = require(ReplicatedStorage.Shared.config.ModifiersConfig)

local RewardMultiplier = {}

function RewardMultiplier.compute(difficultyId: string, modifierIds: { string }): number
	local difficulty = DifficultyConfig[difficultyId]
	local total = if difficulty then difficulty.rewardMultiplier else 1

	local seen: { [string]: boolean } = {}
	for _, id in modifierIds do
		if seen[id] then
			continue
		end
		seen[id] = true
		local modifier = ModifiersConfig.get(id)
		if modifier then
			total *= modifier.rewardMultiplier
		end
	end

	return total
end

return RewardMultiplier
