--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local ChunkFactory = require(script.Parent.ChunkFactory)
local DistanceTracker = require(script.Parent.DistanceTracker)
local ZombieAI = require(script.Parent.ZombieAI)
local AmmoCrates = require(script.Parent.AmmoCrates)
local MissionState = require(script.Parent.MissionState)
local MissionConfig = require(script.Parent.MissionConfig)

local ChunkSpawner = {}

type PlanEntry = {
	locationId: string,
	startIndex: number,
	endIndex: number,
}

type ActiveChunk = {
	model: Model,
	locationId: string,
	pooled: boolean,
}

local chunkLength = GameConstants.CHUNK_LENGTH
local startOffset = GameConstants.START_PLATFORM_LENGTH
local runDirection = GameConstants.RUN_DIRECTION
local transitionChunks = GameConstants.TRANSITION_CHUNKS

local random = Random.new()
local routePool: { string } = table.clone(LocationsConfig.order)
local plan: { PlanEntry } = {}
local pools: { [string]: { Model } } = {}
local active: { [number]: ActiveChunk } = {}
local chunksFolder: Folder? = nil
local nextIndex = 0
local currentBiomeId: string? = nil

for _, id in LocationsConfig.order do
	pools[id] = {}
end

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

local function entryAt(index: number): (PlanEntry, PlanEntry?)
	extendPlan(index + transitionChunks + 1)
	for i, entry in plan do
		if index >= entry.startIndex and index <= entry.endIndex then
			return entry, plan[i + 1]
		end
	end
	return plan[#plan], nil
end

local function spawnChunk(index: number)
	local entry, nextEntry = entryAt(index)
	local location = LocationsConfig.get(entry.locationId) :: LocationsConfig.LocationConfig

	local blend: ChunkFactory.Blend? = nil
	local blendStart = entry.endIndex - transitionChunks + 1
	if nextEntry and index >= blendStart then
		local nextLocation = LocationsConfig.get(nextEntry.locationId)
		if nextLocation then
			local alpha = (index - blendStart + 1) / (transitionChunks + 1)
			blend = { next = nextLocation, alpha = alpha }
		end
	end

	local density = MissionConfig.getDifficulty().obstacleDensity
	local obstacleCount = math.floor(density * random:NextNumber(0.6, 1.4) + 0.5)

	local pooled = blend == nil
	local model: Model
	if pooled then
		local fromPool = table.remove(pools[entry.locationId])
		if fromPool then
			model = fromPool
		else
			model = ChunkFactory.build(location, nil, random, obstacleCount)
		end
	else
		model = ChunkFactory.build(location, blend, random, obstacleCount)
	end

	local centerDistance = startOffset + index * chunkLength + chunkLength / 2
	model:PivotTo(CFrame.new(GameConstants.RUN_ORIGIN + runDirection * centerDistance))
	model.Parent = chunksFolder
	active[index] = { model = model, locationId = entry.locationId, pooled = pooled }

	local zombieCount = random:NextInteger(location.zombiesMin, location.zombiesMax)
	ZombieAI.spawnForChunk(index, model:GetPivot(), chunkLength, zombieCount)
	AmmoCrates.spawnForChunk(index, model:GetPivot(), chunkLength, MissionConfig.getDifficulty().ammoCrateChance)
end

local function despawnChunk(index: number)
	local chunk = active[index]
	if not chunk then
		return
	end
	if chunk.pooled then
		chunk.model.Parent = nil
		table.insert(pools[chunk.locationId], chunk.model)
	else
		chunk.model:Destroy()
	end
	active[index] = nil
	ZombieAI.clearChunk(index)
	AmmoCrates.clearChunk(index)
end

local function despawnAll()
	for index in active do
		despawnChunk(index)
	end
	nextIndex = 0
end

local function updateBiomeAttribute(distance: number)
	local index = math.max(0, math.floor((distance - startOffset) / chunkLength))
	local entry = entryAt(index)
	if entry and entry.locationId ~= currentBiomeId then
		currentBiomeId = entry.locationId
		Workspace:SetAttribute("Biome", entry.locationId)
	end
end

local function step()
	if not MissionState.isActive() then
		return
	end

	local leadDistance = DistanceTracker.getMaxDistance()
	updateBiomeAttribute(leadDistance)

	local spawnEdge = leadDistance + GameConstants.SPAWN_AHEAD_DISTANCE
	while startOffset + nextIndex * chunkLength < spawnEdge do

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

function ChunkSpawner.configure(seed: number, locationIds: { string }?)
	random = Random.new(seed)
	plan = {}
	for id, pool in pools do
		for _, model in pool do
			model:Destroy()
		end
		pools[id] = {}
	end
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

function ChunkSpawner.reset()
	despawnAll()
	plan = {}
	currentBiomeId = nil
end

function ChunkSpawner.clear()
	despawnAll()
	plan = {}
	currentBiomeId = nil
	routePool = table.clone(LocationsConfig.order)
end

function ChunkSpawner.init()
	local folder = Instance.new("Folder")
	folder.Name = "Chunks"
	folder.Parent = Workspace
	chunksFolder = folder
	RunService.Heartbeat:Connect(step)
end

return ChunkSpawner
