--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)

local TrackBuilder = {}

local function createPart(name: string, size: Vector3, cframe: CFrame, transparency: number, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = true
	part.Transparency = transparency
	part.CastShadow = transparency < 1
	part.Parent = parent
	return part
end

function TrackBuilder.build(): Model
	local length = GameConstants.TRACK_LENGTH
	local width = GameConstants.LANE_WIDTH
	local runDirection = GameConstants.RUN_DIRECTION
	local trackCenter = runDirection * (length / 2)

	local trackModel = Instance.new("Model")
	trackModel.Name = "Track"

	createPart(
		"Floor",
		Vector3.new(width, 1, length),
		CFrame.new(trackCenter),
		0,
		trackModel
	)

	local barrierSize = Vector3.new(GameConstants.BARRIER_THICKNESS, GameConstants.BARRIER_HEIGHT, length)
	local barrierOffsetX = (width + GameConstants.BARRIER_THICKNESS) / 2
	local barrierOffsetY = (GameConstants.BARRIER_HEIGHT + 1) / 2

	local leftBarrier = createPart(
		"LeftBarrier",
		barrierSize,
		CFrame.new(trackCenter + Vector3.new(-barrierOffsetX, barrierOffsetY, 0)),
		0.5,
		trackModel
	)
	local rightBarrier = createPart(
		"RightBarrier",
		barrierSize,
		CFrame.new(trackCenter + Vector3.new(barrierOffsetX, barrierOffsetY, 0)),
		0.5,
		trackModel
	)
	leftBarrier.Color = Color3.fromRGB(170, 60, 60)
	rightBarrier.Color = Color3.fromRGB(170, 60, 60)

	local spawnPosition = Vector3.new(0, 1.5, 0) + runDirection * 8
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "RunnerSpawn"
	spawnLocation.Size = Vector3.new(width, 1, 8)
	spawnLocation.CFrame = CFrame.lookAt(spawnPosition, spawnPosition + runDirection)
	spawnLocation.Anchored = true
	spawnLocation.Duration = 0
	spawnLocation.Neutral = true
	spawnLocation.Parent = trackModel

	trackModel.Parent = Workspace
	return trackModel
end

return TrackBuilder
