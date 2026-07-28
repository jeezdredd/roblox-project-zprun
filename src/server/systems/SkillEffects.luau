--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillsConfig = require(ReplicatedStorage.Shared.config.SkillsConfig)
local ProfileManager = require(script.Parent.ProfileManager)

local SkillEffects = {}

local function levelOf(player: Player, skillId: string): number
	local data = ProfileManager.get(player)
	if not data then
		return 0
	end
	local config = SkillsConfig.get(skillId)
	if not config then
		return 0
	end
	return math.clamp(data.SkillLevels[skillId] or 0, 0, config.maxLevel)
end

function SkillEffects.bonusHealth(player: Player): number
	local config = SkillsConfig.get("Toughness")
	if not config then
		return 0
	end
	return levelOf(player, "Toughness") * config.valuePerLevel
end

function SkillEffects.bonusSpeed(player: Player): number
	local config = SkillsConfig.get("Endurance")
	if not config then
		return 0
	end
	return levelOf(player, "Endurance") * config.valuePerLevel
end

function SkillEffects.reloadScale(player: Player): number
	local config = SkillsConfig.get("FastHands")
	if not config then
		return 1
	end
	return math.max(0.5, 1 - levelOf(player, "FastHands") * config.valuePerLevel / 100)
end

function SkillEffects.ammoScale(player: Player): number
	local config = SkillsConfig.get("Scavenger")
	if not config then
		return 1
	end
	return 1 + levelOf(player, "Scavenger") * config.valuePerLevel / 100
end

return SkillEffects
