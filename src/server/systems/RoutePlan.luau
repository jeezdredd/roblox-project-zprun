--!strict

-- The run's route as a chain of maps (wiki: Map Segments). Each map is planned whole
-- when it begins: its length in chunks from a drawn duration and the speed expected
-- there (MapMath.lengthChunks, never under the floor), filled with its sub-locations
-- in turn. Its end is a fork between two enabled neighbours, chosen when the map
-- begins so both can be prepared while the squad runs it (MapPreload); the fork
-- carries each option's first sub-location so their transition chunks can be built
-- ahead. Nothing is planned past an open fork: the spawner holds at the boundary.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ForkConfig = require(ReplicatedStorage.Shared.config.ForkConfig)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local MapsConfig = require(ReplicatedStorage.Shared.config.MapsConfig)
local MapMath = require(ReplicatedStorage.Shared.world.MapMath)

local RoutePlan = {}

export type ForkInfo = {
	-- map ids; options[1] is the left side of the divider, options[2] the right
	options: { string },
	-- each option's first sub-location, drawn when the fork is planned
	firstLocations: { string },
	resolved: boolean,
	choice: string?,
}

export type PlanEntry = {
	locationId: string,
	mapId: string,
	startIndex: number,
	endIndex: number,
	-- the first entry of a map after a boundary: its first MAP_TRANSITION_CHUNKS blend
	-- from prevLocationId
	mapStart: boolean,
	prevLocationId: string?,
	-- set on the placeholder entry that stands for the next map until the vote closes;
	-- its locationId and mapId are the first option's until then
	fork: ForkInfo?,
}

export type MapRun = {
	id: string,
	startIndex: number,
	endIndex: number,
	-- seconds into the run the map is expected to start and its drawn duration
	startTime: number,
	duration: number,
	options: { string }?,
}

local chunkLength = GameConstants.CHUNK_LENGTH
local startOffset = GameConstants.START_PLATFORM_LENGTH
local transitionChunks = MapsConfig.MAP_TRANSITION_CHUNKS

local CONSTANTS: MapMath.Constants = {
	chunkLength = chunkLength,
	spawnAhead = GameConstants.SPAWN_AHEAD_DISTANCE,
	baseSpeed = GameConstants.BASE_RUN_SPEED,
	maxSpeed = GameConstants.MAX_RUN_SPEED,
	floorFactor = MapsConfig.FLOOR_FACTOR,
	forkSpan = ForkConfig.FIRST_DIVIDER_AT + ForkConfig.DIVIDER_LENGTH + ForkConfig.VOTE_LEAD,
}

local random = Random.new()
local startMapId = MapsConfig.DEFAULT_ID
local plan: { PlanEntry } = {}
local maps: { MapRun } = {}

local function mapsTable(): { [string]: MapMath.Map }
	return MapsConfig.maps :: any
end

local function indexStartDistance(index: number): number
	return startOffset + index * chunkLength
end

local function drawLength(id: string): number
	local location = LocationsConfig.get(id) :: LocationsConfig.LocationConfig
	return random:NextInteger(location.lengthChunksMin, location.lengthChunksMax)
end

local function drawLocation(mapId: string, previous: string?): string
	local map = MapsConfig.get(mapId) :: MapsConfig.MapConfig
	return MapMath.nextLocation(map :: any, previous, random:NextNumber())
end

local function slowestPreload(options: { string }?): number
	local slowest = 0
	for _, id in options or {} do
		local map = MapsConfig.get(id)
		if map then
			slowest = math.max(slowest, map.preloadSeconds)
		end
	end
	return slowest
end

-- Plans a whole map from `startIndex`: length, sub-locations, and the fork at its end
-- (a placeholder entry, provisional on the first option).
local function beginMap(mapId: string, startIndex: number, startTime: number, prevLocationId: string?, firstLocation: string?)
	local config = MapsConfig.get(mapId) :: MapsConfig.MapConfig
	local options = MapMath.forkOptions(mapsTable(), mapId, random:NextNumber(), random:NextNumber())
	local duration = MapMath.duration(config :: any, random:NextNumber())
	local length = MapMath.lengthChunks(CONSTANTS, config :: any, startTime, duration, slowestPreload(options))
	local run: MapRun = {
		id = mapId,
		startIndex = startIndex,
		endIndex = startIndex + length - 1,
		startTime = startTime,
		duration = duration,
		options = options,
	}
	table.insert(maps, run)

	local index = startIndex
	local previous: string? = nil
	local first = true
	while index <= run.endIndex do
		local locationId = if first and firstLocation then firstLocation else drawLocation(mapId, previous)
		local chunks = drawLength(locationId)
		if first and prevLocationId then
			-- the whole transition stays inside the first sub-location
			chunks = math.max(chunks, transitionChunks + 1)
		end
		local endIndex = math.min(index + chunks - 1, run.endIndex)
		-- never leave a sliver shorter than a location's minimum at the map's end
		local rest = run.endIndex - endIndex
		if rest > 0 and rest < 3 then
			endIndex = run.endIndex
		end
		table.insert(plan, {
			locationId = locationId,
			mapId = mapId,
			startIndex = index,
			endIndex = endIndex,
			mapStart = first and prevLocationId ~= nil,
			prevLocationId = if first then prevLocationId else nil,
		})
		previous = locationId
		first = false
		index = endIndex + 1
	end

	if options then
		local firstLocations = { drawLocation(options[1], nil), drawLocation(options[2], nil) }
		table.insert(plan, {
			locationId = firstLocations[1],
			mapId = options[1],
			startIndex = run.endIndex + 1,
			endIndex = run.endIndex + transitionChunks + 1,
			mapStart = true,
			prevLocationId = previous,
			fork = { options = options, firstLocations = firstLocations, resolved = false },
		})
	end
	-- no two enabled neighbours (a config error MapMath.check reports): extendPlan runs
	-- the same map again rather than stop
end

local function extendPlan(upToIndex: number)
	if #plan == 0 then
		beginMap(startMapId, 0, 0, nil, nil)
	end
	local guard = 0
	while plan[#plan].endIndex < upToIndex and guard < 64 do
		guard += 1
		local last = plan[#plan]
		if last.fork then
			-- nothing is planned past a fork until the vote closes (resolveFork)
			return
		end
		-- the same map again (it has no fork): no map transition, the sub-location blend
		-- inside the map covers the seam
		local run = maps[#maps]
		beginMap(run.id, run.endIndex + 1, run.startTime + run.duration, nil, nil)
	end
end

-- Plans the route far enough ahead that forks are known before their divider has to
-- be built.
function RoutePlan.planAhead(distance: number)
	extendPlan(RoutePlan.indexForDistance(distance))
end

-- The first fork not yet decided, with its boundary distance.
function RoutePlan.pendingFork(): (PlanEntry?, number)
	for _, entry in plan do
		local fork = entry.fork
		if fork and not fork.resolved then
			return entry, indexStartDistance(entry.startIndex)
		end
	end
	return nil, 0
end

-- The chunk index the spawner must not reach while a fork is open: the boundary
-- itself. Everything before it belongs to the current map.
function RoutePlan.holdIndex(): number?
	local entry = RoutePlan.pendingFork()
	return if entry then entry.startIndex else nil
end

-- The vote closed: the placeholder becomes the chosen map, planned whole from the
-- boundary with its pre-drawn first sub-location.
function RoutePlan.resolveFork(entry: PlanEntry, mapId: string)
	local fork = entry.fork
	if not fork or fork.resolved then
		return
	end
	local slot = table.find(fork.options, mapId)
	if not slot then
		return
	end
	fork.resolved = true
	fork.choice = mapId
	local index = table.find(plan, entry)
	if index then
		table.remove(plan, index)
	end
	local previous = maps[#maps]
	beginMap(mapId, entry.startIndex, previous.startTime + previous.duration, entry.prevLocationId, fork.firstLocations[slot])
end

function RoutePlan.entryAt(index: number): (PlanEntry, PlanEntry?)
	extendPlan(index + transitionChunks + 1)
	for i, entry in plan do
		if index >= entry.startIndex and index <= entry.endIndex then
			return entry, plan[i + 1]
		end
	end
	return plan[#plan], nil
end

-- The map run that contains a chunk index (the last planned one past the plan).
function RoutePlan.mapAt(index: number): MapRun?
	for i = #maps, 1, -1 do
		local run = maps[i]
		if index >= run.startIndex then
			return run
		end
	end
	return maps[1]
end

-- The map run before `run`, if any.
function RoutePlan.previousRun(run: MapRun): MapRun?
	local index = table.find(maps, run)
	return if index and index > 1 then maps[index - 1] else nil
end

-- The fork placeholder at the end of `run`, while the vote is open.
function RoutePlan.forkAfter(run: MapRun): PlanEntry?
	for _, entry in plan do
		local fork = entry.fork
		if fork and not fork.resolved and entry.startIndex == run.endIndex + 1 then
			return entry
		end
	end
	return nil
end

-- Maps run so far, in order, as ids (MapPreload frees pools two steps behind).
function RoutePlan.mapHistory(upToIndex: number): { string }
	local out = {}
	for _, run in maps do
		if run.startIndex <= upToIndex then
			table.insert(out, run.id)
		end
	end
	return out
end

function RoutePlan.indexForDistance(distance: number): number
	return math.max(0, math.floor((distance - startOffset) / chunkLength))
end

function RoutePlan.entryForDistance(distance: number): PlanEntry
	local entry = RoutePlan.entryAt(RoutePlan.indexForDistance(distance))
	return entry
end

function RoutePlan.locationForDistance(distance: number): LocationsConfig.LocationConfig?
	return LocationsConfig.get(RoutePlan.entryForDistance(distance).locationId)
end

function RoutePlan.entryBounds(entry: PlanEntry): (number, number)
	local from = startOffset + entry.startIndex * chunkLength
	local to = startOffset + (entry.endIndex + 1) * chunkLength
	return from, to
end

-- The boundary distance of a map run and the end of its transition zone.
function RoutePlan.transitionZone(run: MapRun): (number, number)
	local from = indexStartDistance(run.startIndex)
	return from, from + transitionChunks * chunkLength
end

function RoutePlan.sectionAt(distance: number, sections: { string }): (string?, number)
	if #sections == 0 then
		return nil, 0
	end
	local entry = RoutePlan.entryForDistance(distance)
	local from, to = RoutePlan.entryBounds(entry)
	local span = math.max(1, to - from)
	local progress = math.clamp((distance - from) / span, 0, 0.9999)
	local slot = math.floor(progress * #sections) + 1
	local bandSize = span / #sections
	local bandStart = from + (slot - 1) * bandSize
	local t = math.clamp((distance - bandStart) / bandSize, 0, 1)
	return sections[slot], t
end

-- A run from the lobby's map choice (Random or an id); the seed draws everything.
function RoutePlan.configure(seed: number, mapChoice: string?)
	random = Random.new(seed)
	plan = {}
	maps = {}
	startMapId = MapMath.startMap(mapsTable(), MapsConfig.order, mapChoice or MapsConfig.DEFAULT_ID, random:NextNumber())
		or MapsConfig.DEFAULT_ID
end

function RoutePlan.startMap(): string
	return startMapId
end

function RoutePlan.reset()
	plan = {}
	maps = {}
end

function RoutePlan.clear()
	plan = {}
	maps = {}
	startMapId = MapsConfig.DEFAULT_ID
end

return RoutePlan
