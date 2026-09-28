--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)

local RoutePlan = {}

export type PlanEntry = {
	locationId: string,
	startIndex: number,
	endIndex: number,
}

local chunkLength = GameConstants.CHUNK_LENGTH
local startOffset = GameConstants.START_PLATFORM_LENGTH
local transitionChunks = GameConstants.TRANSITION_CHUNKS

local random = Random.new()
local routePool: { string } = table.clone(LocationsConfig.order)
local plan: { PlanEntry } = {}

local function extendPlan(upToIndex: number)
	while #plan == 0 or plan[#plan].endIndex < upToIndex do
		local last = plan[#plan]
		local startIndex = if last then last.endIndex + 1 else 0
		local id = routePool[random:NextInteger(1, #routePool)]
		if last and #routePool > 1 and id == last.locationId then
			id = routePool[random:NextInteger(1, #routePool)]
		end
		local location = LocationsConfig.get(id) :: LocationsConfig.LocationConfig
		local length = random:NextInteger(location.lengthChunksMin, location.lengthChunksMax)
		table.insert(plan, { locationId = id, startIndex = startIndex, endIndex = startIndex + length - 1 })
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
end

function RoutePlan.clear()
	plan = {}
	routePool = table.clone(LocationsConfig.order)
end

return RoutePlan
