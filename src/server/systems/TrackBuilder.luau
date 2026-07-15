--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LaneSectionFactory = require(ReplicatedStorage.Shared.util.LaneSectionFactory)

local TrackBuilder = {}

function TrackBuilder.build(): Model
	local runDirection = GameConstants.RUN_DIRECTION
	local length = GameConstants.START_PLATFORM_LENGTH

	local platform = LaneSectionFactory.build("StartPlatform", length, Color3.fromRGB(120, 120, 125))
	platform:PivotTo(CFrame.new(runDirection * (length / 2)))

	local spawnPosition = Vector3.new(0, 1.5, 0) + runDirection * 8
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "RunnerSpawn"
	spawnLocation.Size = Vector3.new(GameConstants.LANE_WIDTH, 1, 8)
	spawnLocation.CFrame = CFrame.lookAt(spawnPosition, spawnPosition + runDirection)
	spawnLocation.Anchored = true
	spawnLocation.Duration = 0
	spawnLocation.Neutral = true
	spawnLocation.Parent = platform

	platform.Parent = Workspace
	return platform
end

return TrackBuilder
