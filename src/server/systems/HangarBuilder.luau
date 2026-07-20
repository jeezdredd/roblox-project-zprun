--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)

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

local function buildHelicopters(model: Model)
	for index, padCFrame in HangarConfig.HELICOPTER_PADS do
		local bodySize = HangarConfig.HELICOPTER_BODY_SIZE
		local bodyCFrame = padCFrame * CFrame.new(0, bodySize.Y / 2, 0)
		createPart("Helicopter" .. index, bodySize, bodyCFrame, HangarConfig.HELI_COLOR, model)
		createPart(
			"HelicopterSkid" .. index,
			Vector3.new(bodySize.X + 2, 1, bodySize.Z),
			padCFrame * CFrame.new(0, 0.5, 0),
			HangarConfig.HELI_COLOR,
			model
		)
	end
end

local function buildDeployConsole(model: Model): ProximityPrompt
	local console = createPart(
		"DeployConsole",
		HangarConfig.DEPLOY_CONSOLE_SIZE,
		HangarConfig.DEPLOY_CONSOLE_CFRAME,
		HangarConfig.CONSOLE_COLOR,
		model
	)
	console.Material = Enum.Material.Neon

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DeployPrompt"
	prompt.ActionText = "Deploy"
	prompt.ObjectText = "Debug Launch"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = HangarConfig.DEPLOY_PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = console

	return prompt
end

function HangarBuilder.build(): ProximityPrompt
	local model = Instance.new("Model")
	model.Name = "Hangar"

	createPart("HangarFloor", HangarConfig.HUB_FLOOR_SIZE, CFrame.new(HangarConfig.HUB_CENTER), HangarConfig.FLOOR_COLOR, model)
	buildWalls(model)
	buildHelicopters(model)
	local prompt = buildDeployConsole(model)

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "HubSpawn"
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.CFrame = HangarConfig.HUB_SPAWN_CFRAME
	spawnLocation.Anchored = true
	spawnLocation.Duration = 0
	spawnLocation.Neutral = true
	spawnLocation.Color = HangarConfig.CONSOLE_COLOR
	spawnLocation.Parent = model

	model.Parent = Workspace
	return prompt
end

return HangarBuilder
