--!strict

export type Ladder = {
	MAX_LEVEL: number,
	UPGRADE_BASE_PRICE: number,
	UPGRADE_PRICE_STEP: number,
	DAMAGE_PER_LEVEL: number,
}

export type Weapon = {
	class: string,
	damage: number,
	fireRate: number,
	magSize: number,
}

local WeaponLadderText = {}

function WeaponLadderText.number(value: number): string
	local rounded = math.floor(value * 10 + 0.5) / 10
	if rounded == math.floor(rounded) then
		return string.format("%d", rounded)
	end
	return string.format("%.1f", rounded)
end

function WeaponLadderText.damageAt(ladder: Ladder, weapon: Weapon, level: number): number
	return weapon.damage * (1 + ladder.DAMAGE_PER_LEVEL * math.max(level - 1, 0))
end

function WeaponLadderText.priceFor(ladder: Ladder, level: number): number
	return ladder.UPGRADE_BASE_PRICE + ladder.UPGRADE_PRICE_STEP * math.max(level - 1, 0)
end

function WeaponLadderText.describe(ladder: Ladder, weapon: Weapon, level: number): string
	local n = WeaponLadderText.number
	if level <= 0 then
		return string.format(
			"%s · %s dmg · %d rpm · mag %d",
			weapon.class,
			n(WeaponLadderText.damageAt(ladder, weapon, 1)),
			math.floor(weapon.fireRate * 60),
			weapon.magSize
		)
	end
	local current = math.min(level, ladder.MAX_LEVEL)
	local damage = WeaponLadderText.damageAt(ladder, weapon, current)
	if current >= ladder.MAX_LEVEL then
		return string.format("%s dmg · top of the ladder", n(damage))
	end
	local next = WeaponLadderText.damageAt(ladder, weapon, current + 1)
	return string.format("%s dmg · L%d: +%s dmg", n(damage), current + 1, n(next - damage))
end

return WeaponLadderText
