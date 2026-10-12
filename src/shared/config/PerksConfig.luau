--!strict

export type PerkConfig = {
	id: string,
	displayName: string,
	badge: string,
	description: string,
	maxLevel: number,
	levelPrices: { number },
	effect: string,
	values: { number },
	unit: string,
}

local PerksConfig = {}

PerksConfig.MAX_SLOTS = 3
PerksConfig.slotPrices = { [2] = 1500, [3] = 3500 } :: { [number]: number }

PerksConfig.order = { "Toughness", "Sprinter", "FastHands", "FieldMedic", "Scavenger", "SteadyAim" }

local function perk(config: PerkConfig): PerkConfig
	return config
end

PerksConfig.perks = {
	Toughness = perk({
		id = "Toughness",
		displayName = "Thick Skin",
		badge = "TS",
		description = "Extra max health for this run, on top of Toughness.",
		maxLevel = 3,
		levelPrices = { 400, 900, 1600 },
		effect = "bonusHealth",
		values = { 15, 30, 45 },
		unit = "HP",
	}),
	Sprinter = perk({
		id = "Sprinter",
		displayName = "Adrenaline",
		badge = "AD",
		description = "Higher sprint speed for this run, on top of Endurance.",
		maxLevel = 3,
		levelPrices = { 500, 1000, 1800 },
		effect = "sprintSpeed",
		values = { 2, 4, 6 },
		unit = "speed",
	}),
	FastHands = perk({
		id = "FastHands",
		displayName = "Speedloader",
		badge = "SL",
		description = "Faster reloads for this run, on top of Fast Hands.",
		maxLevel = 3,
		levelPrices = { 450, 950, 1700 },
		effect = "reloadScale",
		values = { 0.9, 0.82, 0.75 },
		unit = "x reload time",
	}),
	FieldMedic = perk({
		id = "FieldMedic",
		displayName = "Field Medic",
		badge = "FM",
		description = "Health back on every kill.",
		maxLevel = 3,
		levelPrices = { 500, 1100, 2000 },
		effect = "healPerKill",
		values = { 2, 4, 6 },
		unit = "HP per kill",
	}),
	Scavenger = perk({
		id = "Scavenger",
		displayName = "Pack Rat",
		badge = "PR",
		description = "More ammo from every crate this run, on top of Scavenger.",
		maxLevel = 3,
		levelPrices = { 400, 850, 1500 },
		effect = "ammoScale",
		values = { 1.15, 1.3, 1.5 },
		unit = "x crate ammo",
	}),
	SteadyAim = perk({
		id = "SteadyAim",
		displayName = "Steady Aim",
		badge = "SA",
		description = "Tighter hip-fire spread.",
		maxLevel = 3,
		levelPrices = { 450, 950, 1700 },
		effect = "spreadScale",
		values = { 0.85, 0.7, 0.55 },
		unit = "x spread",
	}),
} :: { [string]: PerkConfig }

function PerksConfig.get(id: string): PerkConfig?
	return PerksConfig.perks[id]
end

function PerksConfig.priceFor(config: PerkConfig, currentLevel: number): number?
	if currentLevel >= config.maxLevel then
		return nil
	end
	return config.levelPrices[currentLevel + 1]
end

function PerksConfig.valueAt(config: PerkConfig, level: number): number?
	if level <= 0 then
		return nil
	end
	return config.values[math.min(level, config.maxLevel)]
end

function PerksConfig.slotPrice(owned: number): number?
	if owned >= PerksConfig.MAX_SLOTS then
		return nil
	end
	return PerksConfig.slotPrices[owned + 1]
end

function PerksConfig.validateEquipped(equipped: { string }, slots: number, levels: { [string]: number }): boolean
	if #equipped > math.clamp(slots, 1, PerksConfig.MAX_SLOTS) then
		return false
	end
	local seen: { [string]: boolean } = {}
	for _, id in equipped do
		if seen[id] or not PerksConfig.perks[id] or (levels[id] or 0) <= 0 then
			return false
		end
		seen[id] = true
	end
	return true
end

return PerksConfig
