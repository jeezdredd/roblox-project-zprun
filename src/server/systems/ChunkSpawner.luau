--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local ChunkFactory = require(script.Parent.ChunkFactory)
local DistanceTracker = require(script.Parent.DistanceTracker)
local RoutePlan = require(script.Parent.RoutePlan)
local AmmoCrates = require(script.Parent.AmmoCrates)
local MissionState = require(script.Parent.MissionState)
local MissionConfig = require(script.Parent.MissionConfig)

local ChunkSpawner = {}

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
local pools: { [string]: { Model } } = {}
local active: { [number]: ActiveChunk } = {}
local chunksFolder: Folder? = nil
local nextIndex = 0
local currentBiomeId: string? = nil

for _, id in LocationsConfig.order do
	pools[id] = {}
end

local function spawnChunk(index: number)
	local entry, nextEntry = RoutePlan.entryAt(index)
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
	AmmoCrates.clearChunk(index)
end

local function despawnAll()
	for index in active do
		despawnChunk(index)
	end
	nextIndex = 0
end

local function updateBiomeAttribute(distance: number)
	local entry = RoutePlan.entryForDistance(distance)
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
	random = Random.new(seed + 1)
	RoutePlan.configure(seed, locationIds)
	for id, pool in pools do
		for _, model in pool do
			model:Destroy()
		end
		pools[id] = {}
	end
end

function ChunkSpawner.reset()
	despawnAll()
	RoutePlan.reset()
	currentBiomeId = nil
end

function ChunkSpawner.clear()
	despawnAll()
	RoutePlan.clear()
	currentBiomeId = nil
end

function ChunkSpawner.init()
	local folder = Instance.new("Folder")
	folder.Name = "Chunks"
	folder.Parent = Workspace
	chunksFolder = folder
	RunService.Heartbeat:Connect(step)
end

return ChunkSpawner
