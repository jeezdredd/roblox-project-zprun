--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LaneSectionFactory = require(ReplicatedStorage.Shared.util.LaneSectionFactory)

local TrackBuilder = {}

local platform: Model? = nil

function TrackBuilder.build(): Model
	TrackBuilder.clear()

	local runDirection = GameConstants.RUN_DIRECTION
	local length = GameConstants.START_PLATFORM_LENGTH

	local model = LaneSectionFactory.build("StartPlatform", length, Color3.fromRGB(120, 120, 125))
	model:PivotTo(CFrame.new(runDirection * (length / 2)))
	model.Parent = Workspace

	platform = model
	return model
end

function TrackBuilder.clear()
	if platform then
		platform:Destroy()
		platform = nil
	end
end

return TrackBuilder
