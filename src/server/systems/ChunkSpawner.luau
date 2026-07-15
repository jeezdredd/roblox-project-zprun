--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ChunksConfig = require(ReplicatedStorage.Shared.config.ChunksConfig)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LaneSectionFactory = require(ReplicatedStorage.Shared.util.LaneSectionFactory)
local DistanceTracker = require(script.Parent.DistanceTracker)

local ChunkSpawner = {}

type ActiveChunk = {
	model: Model,
	configId: string,
}

local chunkLength = GameConstants.CHUNK_LENGTH
local startOffset = GameConstants.START_PLATFORM_LENGTH
local runDirection = GameConstants.RUN_DIRECTION

local random = Random.new()
local pools: { [string]: { Model } } = {}
local active: { [number]: ActiveChunk } = {}
local chunksFolder: Folder? = nil
local nextIndex = 0
local totalWeight = 0

for _, config in ChunksConfig do
	totalWeight += config.weight
	pools[config.id] = {}
end

local function pickConfig(): ChunksConfig.ChunkConfig
	local roll = random:NextNumber() * totalWeight
	for _, config in ChunksConfig do
		roll -= config.weight
		if roll <= 0 then
			return config
		end
	end
	return ChunksConfig[#ChunksConfig]
end

local function acquireModel(config: ChunksConfig.ChunkConfig): Model
	local pooled = table.remove(pools[config.id])
	if pooled then
		return pooled
	end
	return LaneSectionFactory.build("Chunk_" .. config.id, chunkLength, config.floorColor)
end

local function spawnChunk(index: number)
	local config = pickConfig()
	local model = acquireModel(config)
	local centerDistance = startOffset + index * chunkLength + chunkLength / 2
	model:PivotTo(CFrame.new(runDirection * centerDistance))
	model.Parent = chunksFolder
	active[index] = { model = model, configId = config.id }
end

local function despawnChunk(index: number)
	local chunk = active[index]
	if not chunk then
		return
	end
	chunk.model.Parent = nil
	table.insert(pools[chunk.configId], chunk.model)
	active[index] = nil
end

local function step()
	local spawnEdge = DistanceTracker.getMaxDistance() + GameConstants.SPAWN_AHEAD_DISTANCE
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

function ChunkSpawner.init()
	local folder = Instance.new("Folder")
	folder.Name = "Chunks"
	folder.Parent = Workspace
	chunksFolder = folder
	RunService.Heartbeat:Connect(step)
end

return ChunkSpawner
