--!strict

export type Ladder = {
	MAX_LEVEL: number,
	UPGRADE_BASE_PRICE: number,
	UPGRADE_PRICE_STEP: number,
	DAMAGE_PER_LEVEL: number,
}

export type Quote = {
	ok: boolean,
	level: number,
	price: number,
	reason: string?,
}

export type Rng = {
	NextNumber: (self: Rng, min: number, max: number) -> number,
	NextInteger: (self: Rng, min: number, max: number) -> number,
}

export type Spot = {
	x: number,
	z: number,
	yaw: number,
}

export type Config = {
	SPACING_STUDS: number,
	START_CLEARANCE_STUDS: number,
	biomes: { string },
	END_CLEARANCE: number,
	SHOULDER_INSET: { number },
	YAW_JITTER: number,
	CANDIDATES: number,
}

export type Options = {
	halfLength: number,
	halfWidth: number,
	chunkStart: number,
}

local UpgradeStationMath = {}

function UpgradeStationMath.priceFor(ladder: Ladder, level: number): number
	return ladder.UPGRADE_BASE_PRICE + ladder.UPGRADE_PRICE_STEP * math.max(level - 1, 0)
end

function UpgradeStationMath.damageScale(ladder: Ladder, level: number): number
	return 1 + ladder.DAMAGE_PER_LEVEL * math.max(math.min(level, ladder.MAX_LEVEL) - 1, 0)
end

function UpgradeStationMath.quote(ladder: Ladder, level: number, balance: number?): Quote
	local current = math.clamp(math.floor(level), 1, ladder.MAX_LEVEL)
	if current >= ladder.MAX_LEVEL then
		return { ok = false, level = current, price = 0, reason = string.format("Already at the top, L%d", ladder.MAX_LEVEL) }
	end
	local price = UpgradeStationMath.priceFor(ladder, current)
	if balance ~= nil and balance < price then
		return { ok = false, level = current + 1, price = price, reason = string.format("Need %d CR", price) }
	end
	return { ok = true, level = current + 1, price = price }
end

function UpgradeStationMath.chunkHasStation(config: Config, biome: string, chunkStart: number, length: number): boolean
	if table.find(config.biomes, biome) == nil then
		return false
	end
	local chunkEnd = chunkStart + length
	if chunkEnd <= config.START_CLEARANCE_STUDS then
		return false
	end
	local spacing = config.SPACING_STUDS
	local first = math.max(math.ceil(math.max(chunkStart, config.START_CLEARANCE_STUDS) / spacing), 1) * spacing
	return first >= chunkStart and first < chunkEnd
end

local function shoulderSpot(config: Config, rng: Rng, options: Options): Spot
	local side = if rng:NextNumber(0, 1) < 0.5 then -1 else 1
	local inset = rng:NextNumber(config.SHOULDER_INSET[1], config.SHOULDER_INSET[2])
	local x = side * (options.halfWidth - inset)
	local z = rng:NextNumber(-options.halfLength + config.END_CLEARANCE, options.halfLength - config.END_CLEARANCE)
	local facing = if side > 0 then math.pi / 2 else -math.pi / 2
	local jitter = math.rad(rng:NextNumber(-config.YAW_JITTER, config.YAW_JITTER))
	return { x = x, z = z, yaw = facing + jitter }
end

function UpgradeStationMath.plan(config: Config, biome: string, rng: Rng, options: Options): { Spot }
	local spots: { Spot } = {}
	if not UpgradeStationMath.chunkHasStation(config, biome, options.chunkStart, options.halfLength * 2) then
		return spots
	end
	for _ = 1, math.max(config.CANDIDATES, 1) do
		table.insert(spots, shoulderSpot(config, rng, options))
	end
	return spots
end

return UpgradeStationMath
