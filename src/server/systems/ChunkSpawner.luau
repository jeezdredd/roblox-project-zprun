--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local MapsConfig = require(ReplicatedStorage.Shared.config.MapsConfig)
local MapMath = require(ReplicatedStorage.Shared.world.MapMath)
local ChunkFactory = require(script.Parent.ChunkFactory)
local ChunkPools = require(script.Parent.ChunkPools)
local DistanceTracker = require(script.Parent.DistanceTracker)
local RoutePlan = require(script.Parent.RoutePlan)
local AmmoCrates = require(script.Parent.AmmoCrates)
local WeaponPickups = require(script.Parent.WeaponPickups)
local UpgradeStations = require(script.Parent.UpgradeStations)
local MissionState = require(script.Parent.MissionState)
local MissionConfig = require(script.Parent.MissionConfig)
local ChunkBudgetCounter = require(script.Parent.Parent.world.ChunkBudgetCounter)

local ChunkSpawner = {}

type ActiveChunk = {
	model: Model,
	locationId: string,
	pooled: boolean,
}

-- Workspace attributes for the clients (wiki: Map Segments): the map at the lead
-- runner, and the map boundary being crossed (the zone's ends in run distance; each
-- client works out its own alpha from where it is, LightingDirector and MapAmbience)
local MAP_ATTRIBUTE = "Map"
local BLEND_FROM = "MapBlendFrom"
local BLEND_TO = "MapBlendTo"
local BLEND_START = "MapBlendStart"
local BLEND_END = "MapBlendEnd"
local BLEND_ALPHA = "MapBlendAlpha"
-- set by ForkService when a vote closes; the spawner reports how long the boundary
-- chunk took to be placed after it (Studio measurement of the vote lead)
local RESOLVED_AT = "ForkResolvedAt"
local PLACED_AFTER = "ForkPlacedAfter"

local chunkLength = GameConstants.CHUNK_LENGTH
local startOffset = GameConstants.START_PLATFORM_LENGTH
local runDirection = GameConstants.RUN_DIRECTION
local transitionChunks = GameConstants.TRANSITION_CHUNKS
local mapTransitionChunks = MapsConfig.MAP_TRANSITION_CHUNKS

local random = Random.new()
local active: { [number]: ActiveChunk } = {}
local chunksFolder: Folder? = nil
local nextIndex = 0
local currentBiomeId: string? = nil
local currentMapId: string? = nil
local blendRun: RoutePlan.MapRun? = nil

-- What a chunk is built from: the location, and the blend into another one.
local function chunkPlan(index: number): (RoutePlan.PlanEntry, LocationsConfig.LocationConfig, ChunkFactory.Blend?, string?)
	local entry, nextEntry = RoutePlan.entryAt(index)
	local location = LocationsConfig.get(entry.locationId) :: LocationsConfig.LocationConfig

	-- a map's first chunks blend from the previous map's last sub-location
	local k = index - entry.startIndex
	if entry.mapStart and entry.prevLocationId and entry.fork == nil then
		local alpha = MapMath.transitionAlpha(k, mapTransitionChunks)
		local from = LocationsConfig.get(entry.prevLocationId)
		if alpha and from then
			return entry, from, { next = location, alpha = alpha }, ChunkPools.transitionKey(from.id, location.id, k)
		end
	end

	-- inside a map, the last TRANSITION_CHUNKS of a sub-location blend into the next one
	local blendStart = entry.endIndex - transitionChunks + 1
	local sameMap = nextEntry ~= nil and nextEntry.fork == nil and nextEntry.mapId == entry.mapId
	if nextEntry and sameMap and index >= blendStart and nextEntry.locationId ~= entry.locationId then
		local nextLocation = LocationsConfig.get(nextEntry.locationId)
		if nextLocation then
			return entry, location, { next = nextLocation, alpha = (index - blendStart + 1) / (transitionChunks + 1) }, nil
		end
	end
	return entry, location, nil, nil
end

local function spawnChunk(index: number)
	local entry, location, blend, transitionKey = chunkPlan(index)

	local density = MissionConfig.getDifficulty().obstacleDensity
	local obstacleCount = math.floor(density * random:NextNumber(0.6, 1.4) + 0.5)

	local pooled = blend == nil
	local model: Model
	if pooled then
		model = ChunkPools.take(entry.locationId) or ChunkFactory.build(location, nil, random, obstacleCount)
	else
		-- MapPreload built the chosen option's transition chunks while the map ran
		model = (if transitionKey then ChunkPools.takeTransition(transitionKey) else nil)
			or ChunkFactory.build(location, blend, random, obstacleCount)
	end

	local centerDistance = startOffset + index * chunkLength + chunkLength / 2
	model:PivotTo(CFrame.new(GameConstants.RUN_ORIGIN + runDirection * centerDistance))
	model.Parent = chunksFolder
	active[index] = { model = model, locationId = entry.locationId, pooled = pooled }

	if entry.mapStart and index == entry.startIndex then
		local resolvedAt = Workspace:GetAttribute(RESOLVED_AT)
		if typeof(resolvedAt) == "number" then
			Workspace:SetAttribute(PLACED_AFTER, math.floor((os.clock() - resolvedAt) * 1000 + 0.5) / 1000)
		end
	end

	AmmoCrates.spawnForChunk(index, model:GetPivot(), chunkLength, MissionConfig.getDifficulty().ammoCrateChance)
	-- the station first, so the chunk's pickups keep clear of it
	UpgradeStations.spawnForChunk(index, model, entry.locationId)
	WeaponPickups.spawnForChunk(index, model, entry.locationId)
end

local function despawnChunk(index: number)
	local chunk = active[index]
	if not chunk then
		return
	end
	if chunk.pooled then
		ChunkPools.put(chunk.locationId, chunk.model)
	else
		chunk.model:Destroy()
	end
	active[index] = nil
	AmmoCrates.clearChunk(index)
	WeaponPickups.clearChunk(index)
	UpgradeStations.clearChunk(index)
end

local function despawnAll()
	for index in active do
		despawnChunk(index)
	end
	nextIndex = 0
end

local function clearBlend()
	blendRun = nil
	for _, name in { BLEND_FROM, BLEND_TO, BLEND_START, BLEND_END, BLEND_ALPHA } do
		Workspace:SetAttribute(name, nil)
	end
end

local function updateAttributes(distance: number)
	local entry = RoutePlan.entryForDistance(distance)
	if entry and entry.locationId ~= currentBiomeId and entry.fork == nil then
		currentBiomeId = entry.locationId
		Workspace:SetAttribute("Biome", entry.locationId)
	end

	-- the map at the lead, and the boundary zone ahead or under it once its map is known
	local index = RoutePlan.indexForDistance(distance)
	local run = RoutePlan.mapAt(index)
	if run and run.id ~= currentMapId then
		currentMapId = run.id
		Workspace:SetAttribute(MAP_ATTRIBUTE, run.id)
	end
	local ahead = RoutePlan.mapAt(RoutePlan.indexForDistance(distance + GameConstants.SPAWN_AHEAD_DISTANCE))
	local zoneRun = if ahead and ahead.startIndex > 0 then ahead else nil
	if zoneRun then
		local from, to = RoutePlan.transitionZone(zoneRun)
		local previous = RoutePlan.previousRun(zoneRun)
		if distance > to + chunkLength then
			zoneRun = nil
		elseif previous and zoneRun ~= blendRun then
			blendRun = zoneRun
			Workspace:SetAttribute(BLEND_FROM, previous.id)
			Workspace:SetAttribute(BLEND_TO, zoneRun.id)
			Workspace:SetAttribute(BLEND_START, from)
			Workspace:SetAttribute(BLEND_END, to)
		end
		if zoneRun then
			Workspace:SetAttribute(BLEND_ALPHA, MapMath.zoneAlpha(distance, from, to))
		end
	end
	if not zoneRun and blendRun then
		clearBlend()
	end
end

local function step()
	if not MissionState.isActive() then
		return
	end

	local leadDistance = DistanceTracker.getMaxDistance()
	updateAttributes(leadDistance)

	local spawnEdge = leadDistance + GameConstants.SPAWN_AHEAD_DISTANCE
	local hold = RoutePlan.holdIndex()
	while startOffset + nextIndex * chunkLength < spawnEdge do
		if hold and nextIndex >= hold then
			break
		end
		spawnChunk(nextIndex)
		nextIndex += 1
	end

	local cullEdge = DistanceTracker.getMinDistance() - GameConstants.DESPAWN_BEHIND_DISTANCE
	for index in active do
		if startOffset + (index + 1) * chunkLength < cullEdge then
			despawnChunk(index)
		end
	end
end

-- A run from the lobby's map choice (an id or "Random"); the seed draws the route.
function ChunkSpawner.configure(seed: number, mapChoice: string?)
	random = Random.new(seed + 1)
	RoutePlan.configure(seed, mapChoice)
	WeaponPickups.configure(seed + 3)
	UpgradeStations.configure(seed + 5)
end

local function resetState()
	despawnAll()
	currentBiomeId = nil
	currentMapId = nil
	clearBlend()
	Workspace:SetAttribute(MAP_ATTRIBUTE, nil)
	Workspace:SetAttribute(RESOLVED_AT, nil)
	Workspace:SetAttribute(PLACED_AFTER, nil)
end

function ChunkSpawner.reset()
	resetState()
	RoutePlan.reset()
end

function ChunkSpawner.clear()
	resetState()
	RoutePlan.clear()
end

function ChunkSpawner.init()
	local folder = Instance.new("Folder")
	folder.Name = "Chunks"
	folder.Parent = Workspace
	chunksFolder = folder
	-- Studio only: presets whose fog would let a chunk be seen spawning
	ChunkBudgetCounter.checkFog()
	UpgradeStations.init(WeaponPickups.init())
	RunService.Heartbeat:Connect(step)
end

return ChunkSpawner
