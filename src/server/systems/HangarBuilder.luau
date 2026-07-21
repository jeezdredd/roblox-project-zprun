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

local function createPart(className: string, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = true
	part.Color = color
	part.Material = material
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
		createPart("Part", "HangarWall" .. index, layout[1], layout[2], HangarConfig.WALL_COLOR, Enum.Material.Metal, model)
	end

	createPart(
		"Part",
		"CeilingBeam",
		Vector3.new(floorSize.X, thickness, floorSize.Z),
		CFrame.new(center.X, center.Y + height, center.Z),
		HangarConfig.WALL_COLOR:Lerp(Color3.new(0, 0, 0), 0.3),
		Enum.Material.Metal,
		model
	)
end

local function buildHelicopter(index: number, padCFrame: CFrame, parent: Instance): Helicopter
	local model = Instance.new("Model")
	model.Name = "Helicopter" .. index

	local green = HangarConfig.HELI_COLOR
	local dark = green:Lerp(Color3.new(0, 0, 0), 0.4)

	local function place(className: string, name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material)
		return createPart(className, name, size, padCFrame * CFrame.new(offset), color, material, model)
	end

	local cabin = place("Part", "Cabin", Vector3.new(8, 5, 9), Vector3.new(0, 3.5, 0), green, Enum.Material.Metal)
	place("WedgePart", "Nose", Vector3.new(8, 4, 4), Vector3.new(0, 3, 6.5), green, Enum.Material.Metal)
	place("Part", "Cockpit", Vector3.new(6.5, 3, 1), Vector3.new(0, 3.6, 4.6), Color3.fromRGB(60, 90, 110), Enum.Material.Glass)
	place("Part", "TailBoom", Vector3.new(1.6, 1.6, 12), Vector3.new(0, 4.4, -9), green, Enum.Material.Metal)
	place("Part", "TailFin", Vector3.new(0.6, 3.5, 2.5), Vector3.new(0, 6, -14), green, Enum.Material.Metal)
	place("Part", "TailRotor", Vector3.new(0.4, 4, 0.5), Vector3.new(1.2, 5.6, -14.5), dark, Enum.Material.SmoothPlastic)

	place("Part", "RotorMast", Vector3.new(0.7, 1.6, 0.7), Vector3.new(0, 6.4, 0), dark, Enum.Material.Metal)
	place("Part", "RotorBladeA", Vector3.new(18, 0.3, 1.3), Vector3.new(0, 7.1, 0), dark, Enum.Material.SmoothPlastic)
	place("Part", "RotorBladeB", Vector3.new(1.3, 0.3, 18), Vector3.new(0, 7.1, 0), dark, Enum.Material.SmoothPlastic)

	place("Part", "SkidLeft", Vector3.new(0.6, 0.6, 11), Vector3.new(-3, 0.6, 0), dark, Enum.Material.Metal)
	place("Part", "SkidRight", Vector3.new(0.6, 0.6, 11), Vector3.new(3, 0.6, 0), dark, Enum.Material.Metal)
	place("Part", "SkidStrutFL", Vector3.new(0.4, 2, 0.4), Vector3.new(-3, 1.6, 3), dark, Enum.Material.Metal)
	place("Part", "SkidStrutFR", Vector3.new(0.4, 2, 0.4), Vector3.new(3, 1.6, 3), dark, Enum.Material.Metal)
	place("Part", "SkidStrutBL", Vector3.new(0.4, 2, 0.4), Vector3.new(-3, 1.6, -3), dark, Enum.Material.Metal)
	place("Part", "SkidStrutBR", Vector3.new(0.4, 2, 0.4), Vector3.new(3, 1.6, -3), dark, Enum.Material.Metal)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ActionText = "Board"
	prompt.ObjectText = "Helicopter " .. index
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = HangarConfig.BOARD_PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = cabin

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StatusBillboard"
	billboard.Size = UDim2.fromScale(10, 2.5)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = cabin
	billboard.Parent = cabin

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.fromScale(1, 1)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextScaled = true
	statusLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
	statusLabel.TextStrokeTransparency = 0.4
	statusLabel.Text = "EMPTY"
	statusLabel.Parent = billboard

	model.PrimaryPart = cabin
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

	createPart(
		"Part",
		"HangarFloor",
		HangarConfig.HUB_FLOOR_SIZE,
		CFrame.new(HangarConfig.HUB_CENTER),
		HangarConfig.FLOOR_COLOR,
		Enum.Material.Concrete,
		model
	)
	buildWalls(model)

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "HubSpawn"
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.CFrame = CFrame.new(HangarConfig.HUB_CENTER + Vector3.new(0, 1, 40))
	spawnLocation.Anchored = true
	spawnLocation.CanCollide = false
	spawnLocation.Transparency = 1
	spawnLocation.Duration = 0
	spawnLocation.Neutral = true
	spawnLocation.Parent = model

	local helicopters: { Helicopter } = {}
	for index, padCFrame in HangarConfig.HELICOPTER_PADS do
		helicopters[index] = buildHelicopter(index, padCFrame, model)
	end

	model.Parent = Workspace
	return helicopters
end

return HangarBuilder
