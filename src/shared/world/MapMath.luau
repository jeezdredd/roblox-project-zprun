--!strict

-- The rules behind map segments (wiki: Map Segments): how long a map is in distance
-- from its duration and the run speed expected there, the floor no map goes under, the
-- fork options at a map's end (always two enabled neighbours), the blend alpha of the
-- transition chunks and of a point in the transition zone, the crossfade gains, the
-- vote lead once both options are pre-built, which maps' pools may be freed, and a
-- check of the map table. Pure Luau: no services, no engine types, no requires;
-- tests/world/run.luau.

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
	-- the fork's own geometry must fit inside the map: vote lead + divider + a start
	forkSpan: number,
}

local MapMath = {}

-- Speed and distance ---------------------------------------------------------------

local function profileOf(profile: SpeedProfile?, baseSpeed: number): SpeedProfile
	return profile or { initial = baseSpeed }
end

-- Studs per second `t` seconds into the run (the ramp is on the run's clock, as
-- DistanceTracker's), never above maxSpeed.
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

-- Distance covered from run time t0 for `seconds`: constant speed exactly, a ramp by
-- 64 trapezoids (exact on each linear piece, within one step at the ramp's end or the
-- cap).
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

-- The floor no map goes under: the spawn distance plus the slower next option's
-- warm-up at full speed, with the owner's factor; and never less than the fork itself.
function MapMath.floorLength(constants: Constants, nextPreloadSeconds: number): number
	local warm = constants.spawnAhead + constants.maxSpeed * math.max(nextPreloadSeconds, 0) * constants.floorFactor
	return math.max(warm, constants.forkSpan)
end

-- A map's length in whole chunks: the distance its duration covers at the speed
-- expected there (starting `startTime` seconds into the run), at least the floor.
function MapMath.lengthChunks(constants: Constants, map: Map, startTime: number, durationSeconds: number, nextPreloadSeconds: number): number
	local distance = MapMath.distanceOver(map.speed, constants.baseSpeed, constants.maxSpeed, startTime, durationSeconds)
	local length = math.max(distance, MapMath.floorLength(constants, nextPreloadSeconds))
	return math.max(1, math.ceil(length / constants.chunkLength))
end

-- A duration in the map's range from a 0..1 roll.
function MapMath.duration(map: Map, roll: number): number
	local range = map.durationSeconds
	return range.min + (range.max - range.min) * math.clamp(roll, 0, 1)
end

-- Neighbours and forks -------------------------------------------------------------

-- The neighbours a fork at this map's end may offer: enabled, existing, not itself.
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

-- Two different neighbours from two rolls in 0..1 (the second drawn from the rest), or
-- nil when fewer than two are enabled.
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

-- The next sub-location of a map: any but the one just run when there is a choice.
function MapMath.nextLocation(map: Map, previous: string?, roll: number): string
	local pool: { string } = {}
	for _, id in map.locationIds do
		if id ~= previous or #map.locationIds == 1 then
			table.insert(pool, id)
		end
	end
	return pool[math.clamp(math.floor(roll * #pool) + 1, 1, #pool)]
end

-- The start map for a lobby choice: the map itself, or for Random (or anything not
-- runnable) one of the enabled maps from the roll.
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

-- Transitions ----------------------------------------------------------------------

-- The blend of the k-th chunk (0-based) of a map's transition: k+1 steps of n+1, so
-- the first chunk is already a little of the new map and the last nearly all of it;
-- nil outside the transition.
function MapMath.transitionAlpha(k: number, chunks: number): number?
	if k < 0 or k >= chunks then
		return nil
	end
	return (k + 1) / (chunks + 1)
end

-- Where a distance sits in the zone from `from` to `to` (0 before, 1 after), eased so
-- the lighting starts and ends without a kink.
function MapMath.zoneAlpha(distance: number, from: number, to: number): number
	if to <= from then
		return if distance >= to then 1 else 0
	end
	local t = math.clamp((distance - from) / (to - from), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Equal-power crossfade gains (old, new): the loudness holds through the middle.
function MapMath.crossfade(alpha: number): (number, number)
	local a = math.clamp(alpha, 0, 1)
	return math.cos(a * math.pi / 2), math.sin(a * math.pi / 2)
end

-- How far before the boundary the vote must close once both options' first chunks are
-- pre-built: the spawner holds at the boundary, so the corridor's end has to stay out
-- of sight (the widest fog, plus a chunk) while the held chunks are placed and reach
-- the clients (settleSeconds at the top speed).
function MapMath.voteLead(maxVisibility: number, chunkLength: number, maxSpeed: number, settleSeconds: number): number
	return maxVisibility + chunkLength + maxSpeed * settleSeconds
end

-- The widest visibility of the presets a run can use (exempt ones left out).
function MapMath.maxVisibility(visibility: { [string]: number }, exempt: { [string]: boolean }): number
	local widest = 0
	for id, value in visibility do
		if not exempt[id] and value > widest then
			widest = value
		end
	end
	return widest
end

-- Pools ----------------------------------------------------------------------------

-- Locations whose pools may be freed when the map at `history[#history]` becomes
-- current: those of maps two or more steps behind that neither the previous map, the
-- current one nor a fork option still uses.
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

-- Checks ---------------------------------------------------------------------------

-- Every problem with the map table, as lines: unknown neighbours or locations, enabled
-- maps without two enabled neighbours (a fork needs two) or without locations, one-way
-- neighbours between enabled maps, durations out of order.
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
