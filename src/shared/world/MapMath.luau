--!strict

export type Range = { min: number, max: number }

export type SpeedProfile = { initial: number, max: number?, rampTime: number? }

export type Map = {
	id: string,
	enabled: boolean,
	locationIds: { string },
	durationSeconds: Range,
	neighbours: { string },
	preloadSeconds: number,
	speed: SpeedProfile?,
}

export type Constants = {
	chunkLength: number,
	spawnAhead: number,
	baseSpeed: number,
	maxSpeed: number,
	floorFactor: number,
	forkSpan: number,
}

local MapMath = {}

local function profileOf(profile: SpeedProfile?, baseSpeed: number): SpeedProfile
	return profile or { initial = baseSpeed }
end

function MapMath.speedAt(profile: SpeedProfile?, baseSpeed: number, maxSpeed: number, t: number): number
	local p = profileOf(profile, baseSpeed)
	local peak = p.max
	local ramp = p.rampTime
	local speed = p.initial
	if peak and ramp and ramp > 0 then
		speed = p.initial + (peak - p.initial) * math.clamp(t / ramp, 0, 1)
	end
	return math.min(speed, maxSpeed)
end

function MapMath.distanceOver(profile: SpeedProfile?, baseSpeed: number, maxSpeed: number, t0: number, seconds: number): number
	if seconds <= 0 then
		return 0
	end
	local p = profileOf(profile, baseSpeed)
	local peak = p.max
	local ramp = p.rampTime
	if not (peak and ramp and ramp > 0) then
		return math.min(p.initial, maxSpeed) * seconds
	end
	local steps = 64
	local dt = seconds / steps
	local total = 0
	for i = 0, steps - 1 do
		local a = MapMath.speedAt(p, baseSpeed, maxSpeed, t0 + i * dt)
		local b = MapMath.speedAt(p, baseSpeed, maxSpeed, t0 + (i + 1) * dt)
		total += (a + b) * 0.5 * dt
	end
	return total
end

function MapMath.floorLength(constants: Constants, nextPreloadSeconds: number): number
	local warm = constants.spawnAhead + constants.maxSpeed * math.max(nextPreloadSeconds, 0) * constants.floorFactor
	return math.max(warm, constants.forkSpan)
end

function MapMath.lengthChunks(constants: Constants, map: Map, startTime: number, durationSeconds: number, nextPreloadSeconds: number): number
	local distance = MapMath.distanceOver(map.speed, constants.baseSpeed, constants.maxSpeed, startTime, durationSeconds)
	local length = math.max(distance, MapMath.floorLength(constants, nextPreloadSeconds))
	return math.max(1, math.ceil(length / constants.chunkLength))
end

function MapMath.duration(map: Map, roll: number): number
	local range = map.durationSeconds
	return range.min + (range.max - range.min) * math.clamp(roll, 0, 1)
end

function MapMath.enabledNeighbours(maps: { [string]: Map }, id: string): { string }
	local map = maps[id]
	local out: { string } = {}
	if not map then
		return out
	end
	for _, other in map.neighbours do
		local neighbour = maps[other]
		if other ~= id and neighbour and neighbour.enabled and not table.find(out, other) then
			table.insert(out, other)
		end
	end
	return out
end

function MapMath.forkOptions(maps: { [string]: Map }, id: string, rollA: number, rollB: number): { string }?
	local pool = MapMath.enabledNeighbours(maps, id)
	if #pool < 2 then
		return nil
	end
	local first = math.clamp(math.floor(rollA * #pool) + 1, 1, #pool)
	local a = table.remove(pool, first) :: string
	local second = math.clamp(math.floor(rollB * #pool) + 1, 1, #pool)
	return { a, pool[second] :: string }
end

function MapMath.nextLocation(map: Map, previous: string?, roll: number): string
	local pool: { string } = {}
	for _, id in map.locationIds do
		if id ~= previous or #map.locationIds == 1 then
			table.insert(pool, id)
		end
	end
	return pool[math.clamp(math.floor(roll * #pool) + 1, 1, #pool)]
end

function MapMath.startMap(maps: { [string]: Map }, order: { string }, choice: string, roll: number): string?
	local chosen = maps[choice]
	if chosen and chosen.enabled and #chosen.locationIds > 0 then
		return choice
	end
	local pool: { string } = {}
	for _, id in order do
		local map = maps[id]
		if map and map.enabled and #map.locationIds > 0 then
			table.insert(pool, id)
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.clamp(math.floor(roll * #pool) + 1, 1, #pool)]
end

function MapMath.transitionAlpha(k: number, chunks: number): number?
	if k < 0 or k >= chunks then
		return nil
	end
	return (k + 1) / (chunks + 1)
end

function MapMath.zoneAlpha(distance: number, from: number, to: number): number
	if to <= from then
		return if distance >= to then 1 else 0
	end
	local t = math.clamp((distance - from) / (to - from), 0, 1)
	return t * t * (3 - 2 * t)
end

function MapMath.crossfade(alpha: number): (number, number)
	local a = math.clamp(alpha, 0, 1)
	return math.cos(a * math.pi / 2), math.sin(a * math.pi / 2)
end

function MapMath.voteLead(maxVisibility: number, chunkLength: number, maxSpeed: number, settleSeconds: number): number
	return maxVisibility + chunkLength + maxSpeed * settleSeconds
end

function MapMath.maxVisibility(visibility: { [string]: number }, exempt: { [string]: boolean }): number
	local widest = 0
	for id, value in visibility do
		if not exempt[id] and value > widest then
			widest = value
		end
	end
	return widest
end

function MapMath.poolsToFree(maps: { [string]: Map }, history: { string }, options: { string }): { string }
	local keep: { [string]: boolean } = {}
	local function hold(id: string?)
		local map = if id then maps[id] else nil
		if map then
			for _, location in map.locationIds do
				keep[location] = true
			end
		end
	end
	hold(history[#history])
	hold(history[#history - 1])
	for _, id in options do
		hold(id)
	end
	local out: { string } = {}
	for i = 1, #history - 2 do
		local map = maps[history[i]]
		if map then
			for _, location in map.locationIds do
				if not keep[location] and not table.find(out, location) then
					table.insert(out, location)
				end
			end
		end
	end
	table.sort(out)
	return out
end

function MapMath.check(maps: { [string]: Map }, locations: { [string]: any }): { string }
	local problems: { string } = {}
	local ids: { string } = {}
	for id in maps do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local map = maps[id]
		if map.id ~= id then
			table.insert(problems, `{id}: id field is {map.id}`)
		end
		if map.durationSeconds.min <= 0 or map.durationSeconds.min > map.durationSeconds.max then
			table.insert(problems, `{id}: duration range out of order`)
		end
		for _, other in map.neighbours do
			if not maps[other] then
				table.insert(problems, `{id}: unknown neighbour {other}`)
			end
		end
		for _, location in map.locationIds do
			if locations[location] == nil then
				table.insert(problems, `{id}: unknown location {location}`)
			end
		end
		if map.enabled then
			if #map.locationIds == 0 then
				table.insert(problems, `{id}: enabled without locations`)
			end
			local enabled = MapMath.enabledNeighbours(maps, id)
			if #enabled < 2 then
				table.insert(problems, `{id}: {#enabled} enabled neighbours, a fork needs 2`)
			end
			for _, other in enabled do
				if not table.find(maps[other].neighbours, id) then
					table.insert(problems, `{id} -> {other} is one-way`)
				end
			end
		end
	end
	return problems
end

return MapMath
