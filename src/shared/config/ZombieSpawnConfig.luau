--!strict

local ZombieSpawnConfig = {}

export type Ramp = {
	start: number,
	finish: number,
	curve: string,
}

export type DensityTier = {
	spawnDelayMin: Ramp,
	spawnDelayMax: Ramp,
	maxAlive: number,
}

export type DifficultyTier = {
	lateralMin: Ramp,
	lateralMax: Ramp,
	leftSideChance: Ramp,
	alertChance: Ramp,
	lyingChance: Ramp,
	eatingChance: Ramp,
	runnerChance: Ramp,
	standUpDistance: number,
}

export type ClumpPreset = {
	chance: Ramp,
	radius: Ramp,
	sizeMin: Ramp,
	sizeMax: Ramp,
}

export type PatternWeights = { [string]: number }

export type SectionPreset = {
	id: string,
	densityTier: number,
	difficultyTier: number,
	clumpPreset: string,
	patternSet: string,
	zombieIds: { string }?,
}

export type ResolvedSection = {
	spawnDelayMin: number,
	spawnDelayMax: number,
	lateralMin: number,
	lateralMax: number,
	leftSideChance: number,
	alertChance: number,
	clumpChance: number,
	clumpRadius: number,
	clumpSizeMin: number,
	clumpSizeMax: number,
	lyingChance: number,
	eatingChance: number,
	runnerChance: number,
	standUpDistance: number,
	maxAlive: number,
	patterns: PatternWeights,
	zombieIds: { string }?,
}

local EASINGS: { [string]: (number) -> number } = {
	linear = function(t: number): number
		return t
	end,
	easeIn = function(t: number): number
		return t * t
	end,
	easeOut = function(t: number): number
		return 1 - (1 - t) * (1 - t)
	end,
	hold = function(_t: number): number
		return 0
	end,
}

local function ramp(start: number, finish: number?, curve: string?): Ramp
	return {
		start = start,
		finish = if finish then finish else start,
		curve = if finish then (curve or "linear") else "hold",
	}
end

ZombieSpawnConfig.ramp = ramp

function ZombieSpawnConfig.evaluate(value: Ramp, t: number): number
	local easing = EASINGS[value.curve] or EASINGS.linear
	return value.start + (value.finish - value.start) * easing(math.clamp(t, 0, 1))
end

ZombieSpawnConfig.densityTiers = {
	[1] = { spawnDelayMin = ramp(2.0, 1.2, "linear"), spawnDelayMax = ramp(2.4, 1.5, "linear"), maxAlive = 24 },
	[2] = { spawnDelayMin = ramp(0.8, 0.5, "linear"), spawnDelayMax = ramp(1.0, 0.6, "linear"), maxAlive = 32 },
	[3] = { spawnDelayMin = ramp(0.35, 0.3, "linear"), spawnDelayMax = ramp(0.45, 0.35, "linear"), maxAlive = 40 },
	[4] = { spawnDelayMin = ramp(0.2), spawnDelayMax = ramp(0.25), maxAlive = 50 },
	[5] = { spawnDelayMin = ramp(0.1, 0.06, "linear"), spawnDelayMax = ramp(0.14, 0.08, "linear"), maxAlive = 60 },
} :: { DensityTier }

ZombieSpawnConfig.difficultyTiers = {
	[1] = {
		lateralMin = ramp(0),
		lateralMax = ramp(48, 30, "easeIn"),
		leftSideChance = ramp(0.5),
		alertChance = ramp(0),
		lyingChance = ramp(0),
		eatingChance = ramp(0),
		runnerChance = ramp(0.05),
		standUpDistance = 160,
	},
	[2] = {
		lateralMin = ramp(0),
		lateralMax = ramp(32),
		leftSideChance = ramp(0.5),
		alertChance = ramp(0.05),
		lyingChance = ramp(0, 0.1, "linear"),
		eatingChance = ramp(0.02),
		runnerChance = ramp(0.05),
		standUpDistance = 160,
	},
	[3] = {
		lateralMin = ramp(0),
		lateralMax = ramp(30),
		leftSideChance = ramp(0.5),
		alertChance = ramp(0.1),
		lyingChance = ramp(0.05, 0.3, "linear"),
		eatingChance = ramp(0.03),
		runnerChance = ramp(0.08),
		standUpDistance = 160,
	},
	[4] = {
		lateralMin = ramp(0),
		lateralMax = ramp(32),
		leftSideChance = ramp(0.5),
		alertChance = ramp(0.15),
		lyingChance = ramp(0, 0.05, "linear"),
		eatingChance = ramp(0.02),
		runnerChance = ramp(0.12),
		standUpDistance = 140,
	},
	[5] = {
		lateralMin = ramp(8),
		lateralMax = ramp(28),
		leftSideChance = ramp(0.5),
		alertChance = ramp(0.25),
		lyingChance = ramp(0),
		eatingChance = ramp(0),
		runnerChance = ramp(0.15),
		standUpDistance = 120,
	},
} :: { DifficultyTier }

ZombieSpawnConfig.clumpPresets = {
	None = {
		chance = ramp(0),
		radius = ramp(12),
		sizeMin = ramp(3),
		sizeMax = ramp(3),
	},
	Small = {
		chance = ramp(0.14, 0.4, "easeIn"),
		radius = ramp(14, 18, "linear"),
		sizeMin = ramp(2, 4, "linear"),
		sizeMax = ramp(3, 6, "linear"),
	},
	Large = {
		chance = ramp(0.21, 0.6, "linear"),
		radius = ramp(14, 24, "linear"),
		sizeMin = ramp(3, 4, "linear"),
		sizeMax = ramp(3, 6, "linear"),
	},
	Heavy = {
		chance = ramp(0.7),
		radius = ramp(14, 24, "linear"),
		sizeMin = ramp(2, 4, "linear"),
		sizeMax = ramp(4, 6, "linear"),
	},
} :: { [string]: ClumpPreset }

ZombieSpawnConfig.patternSets = {
	Corridor = { single = 1 },
	Formations = { single = 40, clump = 20, wall = 15, diagonal = 15, column = 10 },
} :: { [string]: PatternWeights }

ZombieSpawnConfig.formations = {
	wallCountMin = 5,
	wallCountMax = 6,
	wallSpacing = 8,
	wallGap = 14,
	wallJitter = 2,
	diagonalCountMin = 3,
	diagonalCountMax = 5,
	diagonalStepX = 7,
	diagonalStepAlong = 6,
	columnCountMin = 3,
	columnCountMax = 4,
	columnStep = 8,
	loiterCountMin = 2,
	loiterCountMax = 3,
	loiterEdgeInset = 12,
	riserCountMin = 2,
	riserCountMax = 4,
	riserSpread = 10,
	feastCount = 3,
	feastRadius = 3.2,
	dormantWakeFraction = 0.6,
	feedingWakeFraction = 0.55,
	feedingWakeDelay = 0.35,
}

ZombieSpawnConfig.sections = {
	Calm_Open = { id = "Calm_Open", densityTier = 1, difficultyTier = 1, clumpPreset = "None", patternSet = "Corridor" },
	Steady_Walkers = { id = "Steady_Walkers", densityTier = 2, difficultyTier = 2, clumpPreset = "Small", patternSet = "Corridor", zombieIds = { "Walker" } },
	Steady_Mixed = { id = "Steady_Mixed", densityTier = 2, difficultyTier = 3, clumpPreset = "Small", patternSet = "Corridor" },
	Pressure_Mixed = { id = "Pressure_Mixed", densityTier = 3, difficultyTier = 3, clumpPreset = "Small", patternSet = "Corridor" },
	Pressure_Clumped = { id = "Pressure_Clumped", densityTier = 3, difficultyTier = 4, clumpPreset = "Large", patternSet = "Corridor" },
	Heavy_Clumped = { id = "Heavy_Clumped", densityTier = 4, difficultyTier = 4, clumpPreset = "Heavy", patternSet = "Corridor" },
} :: { [string]: SectionPreset }

ZombieSpawnConfig.MAX_SPAWN_EVENTS_PER_STEP = 3
ZombieSpawnConfig.START_CLEARANCE = 140
ZombieSpawnConfig.MIN_SEPARATION = 8
ZombieSpawnConfig.CLUMP_SEPARATION = 6.5
ZombieSpawnConfig.SEPARATION_RETRIES = 4

function ZombieSpawnConfig.get(id: string): SectionPreset?
	return ZombieSpawnConfig.sections[id]
end

function ZombieSpawnConfig.resolve(id: string, t: number, tierOffset: number): ResolvedSection?
	local section = ZombieSpawnConfig.sections[id]
	if not section then
		return nil
	end
	local densityIndex = math.clamp(section.densityTier + tierOffset, 1, #ZombieSpawnConfig.densityTiers)
	local difficultyIndex = math.clamp(section.difficultyTier + tierOffset, 1, #ZombieSpawnConfig.difficultyTiers)
	local density = ZombieSpawnConfig.densityTiers[densityIndex]
	local difficulty = ZombieSpawnConfig.difficultyTiers[difficultyIndex]
	local clump = ZombieSpawnConfig.clumpPresets[section.clumpPreset] or ZombieSpawnConfig.clumpPresets.None

	local evaluate = ZombieSpawnConfig.evaluate
	return {
		spawnDelayMin = evaluate(density.spawnDelayMin, t),
		spawnDelayMax = evaluate(density.spawnDelayMax, t),
		lateralMin = evaluate(difficulty.lateralMin, t),
		lateralMax = evaluate(difficulty.lateralMax, t),
		leftSideChance = evaluate(difficulty.leftSideChance, t),
		alertChance = evaluate(difficulty.alertChance, t),
		clumpChance = evaluate(clump.chance, t),
		clumpRadius = evaluate(clump.radius, t),
		clumpSizeMin = evaluate(clump.sizeMin, t),
		clumpSizeMax = evaluate(clump.sizeMax, t),
		lyingChance = evaluate(difficulty.lyingChance, t),
		eatingChance = evaluate(difficulty.eatingChance, t),
		runnerChance = evaluate(difficulty.runnerChance, t),
		standUpDistance = difficulty.standUpDistance,
		maxAlive = density.maxAlive,
		patterns = ZombieSpawnConfig.patternSets[section.patternSet] or { single = 1 },
		zombieIds = section.zombieIds,
	}
end

function ZombieSpawnConfig.pickPattern(patterns: PatternWeights, roll: number): string
	local total = 0
	for _, weight in patterns do
		total += weight
	end
	if total <= 0 then
		return "single"
	end
	local cursor = roll * total
	for name, weight in patterns do
		cursor -= weight
		if cursor <= 0 then
			return name
		end
	end
	return "single"
end

return ZombieSpawnConfig
