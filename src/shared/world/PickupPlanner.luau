--!strict

-- Decides which pickup scene a chunk gets and where (docs/gameplay/weapon-pickups.md).
-- Pure Luau: no services, no engine types, no requires, so it runs under the standalone
-- Luau CLI (tests/pickups/run.luau). The rules come in as the PickupScenesConfig table
-- and the randomness as an Rng (Random fits) the server seeds from the run seed and the
-- chunk index, so the same run puts the same scenes in the same places for everyone.
--
-- Coordinates are chunk-local: x across the road (the playable band is
-- -halfWidth..halfWidth), z along it (-halfLength..halfLength). Every placement comes
-- with a few candidate spots in order; the server takes the first one that is free of
-- the chunk's props.

export type Rng = {
	NextNumber: (self: Rng, min: number, max: number) -> number,
	NextInteger: (self: Rng, min: number, max: number) -> number,
}

export type Spot = {
	x: number,
	z: number,
	-- radians, the scene's yaw (its -z faces the road)
	yaw: number,
}

export type Placement = {
	-- "Scene" or "Drop"
	kind: string,
	sceneId: string?,
	radius: number,
	spots: { Spot },
}

export type SceneRule = {
	id: string,
	enabled: boolean,
	biomes: { string }?,
	weight: number,
	radius: number,
}

export type Config = {
	START_CLEARANCE_CHUNKS: number,
	END_CLEARANCE: number,
	SHOULDER_INSET: { number },
	YAW_JITTER: number,
	CANDIDATES: number,
	DROP_LANE_FRACTION: number,
	SCENE_DROP_GAP: number,
	density: { [string]: number },
	supplyDrop: {
		chance: { [string]: number },
		order: { string },
		weights: { [string]: number },
		radius: number,
	},
	order: { string },
	scenes: { [string]: SceneRule },
}

export type Options = {
	halfLength: number,
	halfWidth: number,
}

local PickupPlanner = {}

-- Picks from `order` by `weights` with one unit random in [0, 1): the first id whose
-- cumulative weight passes it. Zero and missing weights never win; nil when nothing can.
function PickupPlanner.weightedPick(order: { string }, weights: { [string]: number }, unit: number): string?
	local total = 0
	for _, id in order do
		total += math.max(weights[id] or 0, 0)
	end
	if total <= 0 then
		return nil
	end
	local target = math.clamp(unit, 0, 0.999999) * total
	local cursor = 0
	local last: string? = nil
	for _, id in order do
		local weight = math.max(weights[id] or 0, 0)
		if weight > 0 then
			last = id
			cursor += weight
			if target < cursor then
				return id
			end
		end
	end
	return last
end

-- The scene ids allowed in `biome`, in config order.
function PickupPlanner.allowedScenes(config: Config, biome: string): { string }
	local ids: { string } = {}
	for _, id in config.order do
		local rule = config.scenes[id]
		if rule and rule.enabled and (rule.biomes == nil or table.find(rule.biomes :: { string }, biome) ~= nil) then
			table.insert(ids, id)
		end
	end
	return ids
end

-- One scene for `biome`, weighted, or nil when none is allowed there.
function PickupPlanner.chooseScene(config: Config, biome: string, rng: Rng): string?
	local ids = PickupPlanner.allowedScenes(config, biome)
	if #ids == 0 then
		return nil
	end
	local weights: { [string]: number } = {}
	for _, id in ids do
		weights[id] = config.scenes[id].weight
	end
	return PickupPlanner.weightedPick(ids, weights, rng:NextNumber(0, 1))
end

-- The weapon a supply drop gives, from the weighted table.
function PickupPlanner.rollDrop(config: Config, unit: number): string?
	return PickupPlanner.weightedPick(config.supplyDrop.order, config.supplyDrop.weights, unit)
end

local function shoulderSpot(config: Config, rng: Rng, options: Options): Spot
	local side = if rng:NextNumber(0, 1) < 0.5 then -1 else 1
	local inset = rng:NextNumber(config.SHOULDER_INSET[1], config.SHOULDER_INSET[2])
	local x = side * (options.halfWidth - inset)
	local z = rng:NextNumber(-options.halfLength + config.END_CLEARANCE, options.halfLength - config.END_CLEARANCE)
	-- CFrame.Angles(0, yaw, 0) looks along (-sin yaw, 0, -cos yaw): the right shoulder
	-- (x > 0) looks toward -x, the left toward +x
	local facing = if side > 0 then math.pi / 2 else -math.pi / 2
	local jitter = math.rad(rng:NextNumber(-config.YAW_JITTER, config.YAW_JITTER))
	return { x = x, z = z, yaw = facing + jitter }
end

local function laneSpot(config: Config, rng: Rng, options: Options, avoidZ: number?): Spot
	local reach = options.halfWidth * config.DROP_LANE_FRACTION
	local x = rng:NextNumber(-reach, reach)
	local z = rng:NextNumber(-options.halfLength + config.END_CLEARANCE, options.halfLength - config.END_CLEARANCE)
	if avoidZ and math.abs(z - avoidZ) < config.SCENE_DROP_GAP then
		-- push it the other way along the road, inside the chunk
		local shifted = avoidZ + (if z >= avoidZ then config.SCENE_DROP_GAP else -config.SCENE_DROP_GAP)
		z = math.clamp(shifted, -options.halfLength + config.END_CLEARANCE, options.halfLength - config.END_CLEARANCE)
	end
	return { x = x, z = z, yaw = rng:NextNumber(0, math.pi * 2) }
end

-- The placements for chunk `chunkIndex` of `biome`: at most one scene and one supply
-- drop, each with `CANDIDATES` spots. Nothing before START_CLEARANCE_CHUNKS.
function PickupPlanner.plan(config: Config, biome: string, chunkIndex: number, rng: Rng, options: Options): { Placement }
	local placements: { Placement } = {}
	if chunkIndex < config.START_CLEARANCE_CHUNKS then
		return placements
	end

	local sceneZ: number? = nil
	local density = config.density[biome] or 0
	if density > 0 and rng:NextNumber(0, 1) < density then
		local sceneId = PickupPlanner.chooseScene(config, biome, rng)
		if sceneId then
			local spots: { Spot } = {}
			for _ = 1, math.max(config.CANDIDATES, 1) do
				table.insert(spots, shoulderSpot(config, rng, options))
			end
			sceneZ = spots[1].z
			table.insert(placements, { kind = "Scene", sceneId = sceneId, radius = config.scenes[sceneId].radius, spots = spots })
		end
	end

	local dropChance = config.supplyDrop.chance[biome] or 0
	if dropChance > 0 and rng:NextNumber(0, 1) < dropChance then
		local spots: { Spot } = {}
		for _ = 1, math.max(config.CANDIDATES, 1) do
			table.insert(spots, laneSpot(config, rng, options, sceneZ))
		end
		table.insert(placements, { kind = "Drop", sceneId = nil, radius = config.supplyDrop.radius, spots = spots })
	end

	return placements
end

return PickupPlanner
