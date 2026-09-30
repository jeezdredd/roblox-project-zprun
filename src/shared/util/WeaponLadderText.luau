--!strict

-- The Gunsmith row's description (docs/gameplay/goals-hud-and-ladder.md): the level
-- ladder made visible, the damage now, the next level's price and damage gain, or the
-- top of the ladder. Pure Luau: no services, no engine types, no requires; the ladder
-- (WeaponsConfig's MAX_LEVEL, UPGRADE_BASE_PRICE, UPGRADE_PRICE_STEP, DAMAGE_PER_LEVEL)
-- and the weapon config come in as tables. tests/goals/run.luau.

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

-- Whole when whole, else one decimal.
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

-- `level` 0 for a weapon not owned (the dealer's row), else the profile's level. The
-- name label already carries "L2/5", so the text carries the numbers behind it.
function WeaponLadderText.describe(ladder: Ladder, weapon: Weapon, level: number): string
	local n = WeaponLadderText.number
	if level <= 0 then
		return string.format(
			"%s · %s dmg · %d rpm · mag %d · L1 of %d",
			weapon.class,
			n(WeaponLadderText.damageAt(ladder, weapon, 1)),
			math.floor(weapon.fireRate * 60),
			weapon.magSize,
			ladder.MAX_LEVEL
		)
	end
	local current = math.min(level, ladder.MAX_LEVEL)
	local damage = WeaponLadderText.damageAt(ladder, weapon, current)
	if current >= ladder.MAX_LEVEL then
		return string.format("%s · %s dmg · top of the ladder", weapon.class, n(damage))
	end
	local next = WeaponLadderText.damageAt(ladder, weapon, current + 1)
	return string.format(
		"%s · %s dmg · next L%d: %d CR, +%s dmg",
		weapon.class,
		n(damage),
		current + 1,
		WeaponLadderText.priceFor(ladder, current),
		n(next - damage)
	)
end

return WeaponLadderText
