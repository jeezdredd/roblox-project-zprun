--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)

export type Helicopter = {
	index: number,
	model: Model,
	prompt: ProximityPrompt,
	statusLabel: TextLabel,
	padCFrame: CFrame,
}

local HangarBuilder = {}

local function createPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = true
	part.Color = color
	part.Material = Enum.Material.Metal
	part.Parent = parent
	return part
end

local function buildWalls(model: Model)
	local center = HangarConfig.HUB_CENTER
	local floorSize = HangarConfig.HUB_FLOOR_SIZE
	local height = HangarConfig.HUB_WALL_HEIGHT
	local thickness = HangarConfig.HUB_WALL_THICKNESS
	local halfX = floorSize.X / 2
	local halfZ = floorSize.Z / 2
	local wallY = center.Y + height / 2

	local layouts = {
		{ Vector3.new(floorSize.X, height, thickness), CFrame.new(center.X, wallY, center.Z - halfZ) },
		{ Vector3.new(floorSize.X, height, thickness), CFrame.new(center.X, wallY, center.Z + halfZ) },
		{ Vector3.new(thickness, height, floorSize.Z), CFrame.new(center.X - halfX, wallY, center.Z) },
		{ Vector3.new(thickness, height, floorSize.Z), CFrame.new(center.X + halfX, wallY, center.Z) },
	}

	for index, layout in layouts do
		createPart("HangarWall" .. index, layout[1], layout[2], HangarConfig.WALL_COLOR, model)
	end
end

local function buildHelicopter(index: number, padCFrame: CFrame, parent: Instance): Helicopter
	local model = Instance.new("Model")
	model.Name = "Helicopter" .. index

	local bodySize = HangarConfig.HELICOPTER_BODY_SIZE
	local body = createPart("Body", bodySize, padCFrame * CFrame.new(0, bodySize.Y / 2, 0), HangarConfig.HELI_COLOR, model)
	createPart(
		"Skid",
		Vector3.new(bodySize.X + 2, 1, bodySize.Z),
		padCFrame * CFrame.new(0, 0.5, 0),
		HangarConfig.HELI_COLOR,
		model
	)
	createPart(
		"Tail",
		Vector3.new(2, 2, 12),
		padCFrame * CFrame.new(0, bodySize.Y / 2, bodySize.Z / 2 + 6),
		HangarConfig.HELI_COLOR,
		model
	)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ActionText = "Board"
	prompt.ObjectText = "Helicopter " .. index
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = HangarConfig.BOARD_PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StatusBillboard"
	billboard.Size = UDim2.fromScale(10, 2.5)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, bodySize.Y + 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = body
	billboard.Parent = body

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.fromScale(1, 1)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextScaled = true
	statusLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
	statusLabel.TextStrokeTransparency = 0.4
	statusLabel.Text = "EMPTY"
	statusLabel.Parent = billboard

	model.PrimaryPart = body
	model.Parent = parent

	return {
		index = index,
		model = model,
		prompt = prompt,
		statusLabel = statusLabel,
		padCFrame = padCFrame,
	}
end

function HangarBuilder.build(): { Helicopter }
	local model = Instance.new("Model")
	model.Name = "Hangar"

	createPart("HangarFloor", HangarConfig.HUB_FLOOR_SIZE, CFrame.new(HangarConfig.HUB_CENTER), HangarConfig.FLOOR_COLOR, model)
	buildWalls(model)

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "HubSpawn"
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.CFrame = HangarConfig.HUB_SPAWN_CFRAME
	spawnLocation.Anchored = true
	spawnLocation.Duration = 0
	spawnLocation.Neutral = true
	spawnLocation.Color = Color3.fromRGB(40, 90, 120)
	spawnLocation.Parent = model

	local helicopters: { Helicopter } = {}
	for index, padCFrame in HangarConfig.HELICOPTER_PADS do
		helicopters[index] = buildHelicopter(index, padCFrame, model)
	end

	model.Parent = Workspace
	return helicopters
end

return HangarBuilder
