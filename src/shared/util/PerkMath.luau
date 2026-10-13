--!strict

local PerkMath = {}

PerkMath.MAX_HEALTH_CAP = 180
PerkMath.RELOAD_FLOOR = 0.6
PerkMath.SPREAD_FLOOR = 0.4

function PerkMath.maxHealth(base: number, skillBonus: number, perkBonus: number): number
	return math.min(base + math.max(skillBonus, 0) + math.max(perkBonus, 0), math.max(PerkMath.MAX_HEALTH_CAP, base))
end

function PerkMath.reloadScale(skillScale: number, perkScale: number): number
	return math.max(PerkMath.RELOAD_FLOOR, math.min(skillScale, 1) * math.min(perkScale, 1))
end

function PerkMath.ammoScale(skillScale: number, perkScale: number): number
	return math.max(skillScale, 1) * math.max(perkScale, 1)
end

function PerkMath.spreadScale(perkScale: number): number
	return math.clamp(perkScale, PerkMath.SPREAD_FLOOR, 1)
end

function PerkMath.healAfterKill(health: number, maxHealth: number, heal: number): number
	if health <= 0 then
		return health
	end
	return math.min(maxHealth, health + math.max(heal, 0))
end

return PerkMath
