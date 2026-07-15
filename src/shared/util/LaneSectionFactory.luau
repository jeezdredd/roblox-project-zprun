--!strict

local GameConstants = require(script.Parent.Parent.config.GameConstants)

local LaneSectionFactory = {}

local function createPart(name: string, size: Vector3, cframe: CFrame, color: Color3, transparency: number, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = true
	part.Color = color
	part.Transparency = transparency
	part.CastShadow = transparency < 1
	part.Parent = parent
	return part
end

function LaneSectionFactory.build(name: string, length: number, floorColor: Color3): Model
	local width = GameConstants.LANE_WIDTH
	local model = Instance.new("Model")
	model.Name = name

	local floor = createPart("Floor", Vector3.new(width, 1, length), CFrame.new(), floorColor, 0, model)

	local barrierSize = Vector3.new(GameConstants.BARRIER_THICKNESS, GameConstants.BARRIER_HEIGHT, length)
	local barrierOffsetX = (width + GameConstants.BARRIER_THICKNESS) / 2
	local barrierOffsetY = (GameConstants.BARRIER_HEIGHT + 1) / 2

	createPart(
		"LeftBarrier",
		barrierSize,
		CFrame.new(-barrierOffsetX, barrierOffsetY, 0),
		GameConstants.WALL_COLOR,
		GameConstants.WALL_TRANSPARENCY,
		model
	)
	createPart(
		"RightBarrier",
		barrierSize,
		CFrame.new(barrierOffsetX, barrierOffsetY, 0),
		GameConstants.WALL_COLOR,
		GameConstants.WALL_TRANSPARENCY,
		model
	)

	model.PrimaryPart = floor
	return model
end

return LaneSectionFactory
