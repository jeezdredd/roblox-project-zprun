--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local PerksConfig = require(ReplicatedStorage.Shared.config.PerksConfig)
local PerkMath = require(ReplicatedStorage.Shared.util.PerkMath)
local ProfileManager = require(script.Parent.ProfileManager)
local PerkService = require(script.Parent.PerkService)
local SkillEffects = require(script.Parent.SkillEffects)

local PerkEffects = {}

local function perkValue(player: Player, effect: string): number?
	local data = ProfileManager.get(player)
	if not data then
		return nil
	end
	for _, perkId in PerkService.equipped(player) do
		local config = PerksConfig.get(perkId)
		if config and config.effect == effect then
			return PerksConfig.valueAt(config, data.PerkLevels[perkId] or 0)
		end
	end
	return nil
end

function PerkEffects.maxHealth(player: Player): number
	return PerkMath.maxHealth(GameConstants.PLAYER_MAX_HEALTH, SkillEffects.bonusHealth(player), perkValue(player, "bonusHealth") or 0)
end

function PerkEffects.reloadScale(player: Player): number
	return PerkMath.reloadScale(SkillEffects.reloadScale(player), perkValue(player, "reloadScale") or 1)
end

function PerkEffects.ammoScale(player: Player): number
	return PerkMath.ammoScale(SkillEffects.ammoScale(player), perkValue(player, "ammoScale") or 1)
end

function PerkEffects.spreadScale(player: Player): number
	return PerkMath.spreadScale(perkValue(player, "spreadScale") or 1)
end

function PerkEffects.healPerKill(player: Player): number
	return perkValue(player, "healPerKill") or 0
end

function PerkEffects.sprintSpeed(player: Player): number
	return perkValue(player, "sprintSpeed") or 0
end

return PerkEffects
