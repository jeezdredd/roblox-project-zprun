--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local ForkConfig = require(ReplicatedStorage.Shared.config.ForkConfig)

local RoutePlan = {}

export type ForkInfo = {
	-- options[1] is the left side of the divider, options[2] the right
	options: { string },
	resolved: boolean,
}

export type PlanEntry = {
	locationId: string,
	startIndex: number,
	endIndex: number,
	-- Set when the squad chooses this entry's location at a fork. Until resolved,
	-- locationId is a provisional placeholder and nothing past it is planned.
	fork: ForkInfo?,
}

local chunkLength = GameConstants.CHUNK_LENGTH
local startOffset = GameConstants.START_PLATFORM_LENGTH
local transitionChunks = GameConstants.TRANSITION_CHUNKS

local random = Random.new()
local routePool: { string } = table.clone(LocationsConfig.order)
local plan: { PlanEntry } = {}
local lastForkStart = -math.huge

local function indexStartDistance(index: number): number
	return startOffset + index * chunkLength
end

local function drawLength(id: string): number
	local location = LocationsConfig.get(id) :: LocationsConfig.LocationConfig
	return random:NextInteger(location.lengthChunksMin, location.lengthChunksMax)
end

-- Two distinct options for a fork. Prefers locations other than the biome being left;
-- on a two-location map (every map except Mixed) one option is to stay in the current
-- biome. A single-location pool never forks.
local function forkOptions(previousId: string): { string }?
	local candidates: { string } = {}
	for _, id in routePool do
		if id ~= previousId then
			table.insert(candidates, id)
		end
	end
	if #candidates == 1 and table.find(routePool, previousId) then
		table.insert(candidates, previousId)
	end
	if #candidates < 2 then
		return nil
	end
	local first = table.remove(candidates, random:NextInteger(1, #candidates)) :: string
	local second = candidates[random:NextInteger(1, #candidates)]
	return { first, second }
end

local function wantsFork(startIndex: number): boolean
	if not ForkConfig.ENABLED or startIndex == 0 then
		return false
	end
	local boundary = indexStartDistance(startIndex)
	local dividerStart = boundary - ForkConfig.VOTE_LEAD - ForkConfig.DIVIDER_LENGTH
	return dividerStart >= ForkConfig.FIRST_DIVIDER_AT and boundary - lastForkStart >= ForkConfig.MIN_SPACING
end

local function extendPlan(upToIndex: number)
	while #plan == 0 or plan[#plan].endIndex < upToIndex do
		local last = plan[#plan]
		if last and last.fork and not last.fork.resolved then
			-- Nothing is planned past an open fork; the spawner holds at it.
			return
		end
		local startIndex = if last then last.endIndex + 1 else 0

		local options = if last and wantsFork(startIndex) then forkOptions(last.locationId) else nil
		if options then
			local provisional = options[1]
			table.insert(plan, {
				locationId = provisional,
				startIndex = startIndex,
				endIndex = startIndex + drawLength(provisional) - 1,
				fork = { options = options, resolved = false },
			})
			lastForkStart = indexStartDistance(startIndex)
		else
			local id = routePool[random:NextInteger(1, #routePool)]
			if last and #routePool > 1 and id == last.locationId then
				id = routePool[random:NextInteger(1, #routePool)]
			end
			table.insert(plan, { locationId = id, startIndex = startIndex, endIndex = startIndex + drawLength(id) - 1 })
		end
	end
end

-- Plans the route far enough ahead that forks are known before their divider has to
-- be built. Stops at an open fork like everything else.
function RoutePlan.planAhead(distance: number)
	extendPlan(RoutePlan.indexForDistance(distance))
end

-- The first fork not yet decided, if any, with its boundary distance.
function RoutePlan.pendingFork(): (PlanEntry?, number)
	for _, entry in plan do
		if entry.fork and not entry.fork.resolved then
			return entry, indexStartDistance(entry.startIndex)
		end
	end
	return nil, 0
end

-- Chunk index the spawner must not reach while a fork is open: the start of the
-- blend into the fork's biome, so the blend is built with the chosen location.
function RoutePlan.holdIndex(): number?
	local entry = RoutePlan.pendingFork()
	if not entry then
		return nil
	end
	return math.max(0, entry.startIndex - transitionChunks)
end

function RoutePlan.resolveFork(entry: PlanEntry, locationId: string)
	local fork = entry.fork
	if not fork or fork.resolved or not table.find(fork.options, locationId) then
		return
	end
	fork.resolved = true
	if locationId ~= entry.locationId then
		entry.locationId = locationId
		entry.endIndex = entry.startIndex + drawLength(locationId) - 1
	end
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

function RoutePlan.configure(seed: number, locationIds: { string }?)
	random = Random.new(seed)
	plan = {}
	lastForkStart = -math.huge
	if locationIds == nil then
		routePool = table.clone(LocationsConfig.order)
		return
	end
	local validated: { string } = {}
	for _, id in locationIds do
		if LocationsConfig.isValid(id) then
			table.insert(validated, id)
		end
	end
	routePool = if #validated > 0 then validated else table.clone(LocationsConfig.order)
end

function RoutePlan.reset()
	plan = {}
	lastForkStart = -math.huge
end

function RoutePlan.clear()
	plan = {}
	lastForkStart = -math.huge
	routePool = table.clone(LocationsConfig.order)
end

return RoutePlan
