--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)

export type Blend = {
	next: LocationsConfig.LocationConfig,
	alpha: number,
}

local ChunkFactory = {}

local laneWidth = GameConstants.LANE_WIDTH
local chunkLength = GameConstants.CHUNK_LENGTH
local apronWidth = GameConstants.APRON_WIDTH
local barrierThickness = GameConstants.BARRIER_THICKNESS

local CAR_COLORS = {
	Color3.fromRGB(120, 60, 50),
	Color3.fromRGB(70, 90, 110),
	Color3.fromRGB(92, 92, 96),
	Color3.fromRGB(110, 100, 60),
}

local function createPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
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

local function getTemplate(kind: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("PropTemplates")
	local template = folder and folder:FindFirstChild(kind)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

local function buildBuilding(sign: number, position: Vector3, rng: Random, parent: Instance)
	local depth = rng:NextNumber(12, 18)
	local width = rng:NextNumber(16, 26)
	local height = rng:NextNumber(24, 56)
	local shade = rng:NextInteger(70, 110)
	local material = if rng:NextNumber() < 0.5 then Enum.Material.Concrete else Enum.Material.Brick
	local color = Color3.fromRGB(shade, shade, math.min(shade + rng:NextInteger(0, 10), 255))

	createPart(
		"Building",
		Vector3.new(depth, height, width),
		CFrame.new(position.X, position.Y + height / 2, position.Z),
		color,
		material,
		parent
	)
	createPart(
		"Roof",
		Vector3.new(depth + 1.5, 1, width + 1.5),
		CFrame.new(position.X, position.Y + height + 0.5, position.Z),
		color:Lerp(Color3.new(0, 0, 0), 0.35),
		Enum.Material.Concrete,
		parent
	)

	local faceX = position.X - sign * (depth / 2 + 0.2)
	local stripCount = rng:NextInteger(2, 3)
	for i = 1, stripCount do
		local zOffset = (i - (stripCount + 1) / 2) * (width / stripCount) * 0.6
		local strip = createPart(
			"Windows",
			Vector3.new(0.3, height * 0.7, 1.4),
			CFrame.new(faceX, position.Y + height / 2, position.Z + zOffset),
			Color3.fromRGB(255, 214, 120),
			Enum.Material.Neon,
			parent
		)
		strip.Transparency = 0.35
		strip.CastShadow = false
	end
end

local function buildTree(position: Vector3, rng: Random, parent: Instance)
	local trunkHeight = rng:NextNumber(7, 13)
	local trunkRadius = rng:NextNumber(0.6, 1.1)

	local trunk = Instance.new("Part")
	trunk.Name = "Trunk"
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(trunkHeight, trunkRadius * 2, trunkRadius * 2)
	trunk.CFrame = CFrame.new(position.X, position.Y + trunkHeight / 2, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	trunk.Anchored = true
	trunk.Color = Color3.fromRGB(92, 68, 46)
	trunk.Material = Enum.Material.Wood
	trunk.Parent = parent

	local canopyRadius = rng:NextNumber(3.5, 5.5)
	for i = 1, 2 do
		local ball = Instance.new("Part")
		ball.Name = "Canopy"
		ball.Shape = Enum.PartType.Ball
		local radius = canopyRadius * (if i == 1 then 1 else 0.7)
		ball.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		ball.CFrame = CFrame.new(
			position.X + rng:NextNumber(-1.5, 1.5),
			position.Y + trunkHeight + radius * 0.6 + (i - 1) * radius * 0.8,
			position.Z + rng:NextNumber(-1.5, 1.5)
		)
		ball.Anchored = true
		ball.CanCollide = false
		ball.Color = Color3.fromRGB(rng:NextInteger(40, 60), rng:NextInteger(95, 125), rng:NextInteger(40, 60))
		ball.Material = Enum.Material.Grass
		ball.Parent = parent
	end
end

local function buildRuin(position: Vector3, rotationY: number, rng: Random, parent: Instance)
	local wallHeight = rng:NextNumber(6, 14)
	local wall = createPart(
		"RuinWall",
		Vector3.new(1.4, wallHeight, rng:NextNumber(8, 14)),
		CFrame.new(position.X, position.Y + wallHeight / 2, position.Z) * CFrame.Angles(0, rotationY, rng:NextNumber(-0.08, 0.08)),
		Color3.fromRGB(130, 122, 110),
		Enum.Material.Concrete,
		parent
	)
	wall.CastShadow = true

	for _ = 1, rng:NextInteger(1, 2) do
		local slab = createPart(
			"RuinSlab",
			Vector3.new(rng:NextNumber(4, 9), rng:NextNumber(0.8, 1.6), rng:NextNumber(3, 7)),
			CFrame.new(
				position.X + rng:NextNumber(-6, 6),
				position.Y + rng:NextNumber(0.4, 1.2),
				position.Z + rng:NextNumber(-6, 6)
			) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, math.pi), rng:NextNumber(-0.25, 0.25)),
			Color3.fromRGB(118, 110, 100),
			Enum.Material.Concrete,
			parent
		)
		slab.CastShadow = false
	end
end

local function buildCar(position: Vector3, rng: Random, parent: Instance)
	local yaw = rng:NextNumber(-0.3, 0.3) + (if rng:NextNumber() < 0.25 then math.pi / 2 else 0)
	local color = CAR_COLORS[rng:NextInteger(1, #CAR_COLORS)]
	local base = CFrame.new(position.X, position.Y + 0.8, position.Z) * CFrame.Angles(0, yaw, 0)

	local body = createPart("CarBody", Vector3.new(4.4, 1.6, 8.2), base, color, Enum.Material.Metal, parent)
	body.CanCollide = false
	body.CanQuery = false
	local cabin = createPart("CarCabin", Vector3.new(3.8, 1.3, 3.8), base * CFrame.new(0, 1.45, 0.4), color:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Metal, parent)
	cabin.CanCollide = false
	cabin.CanQuery = false
end

local function buildRock(position: Vector3, rng: Random, parent: Instance)
	local size = rng:NextNumber(1.6, 3.2)
	local rock = Instance.new("Part")
	rock.Name = "Rock"
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.new(size, size * rng:NextNumber(0.6, 0.9), size)
	rock.CFrame = CFrame.new(position.X, position.Y + size * 0.3, position.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	rock.Anchored = true
	rock.CanCollide = false
	rock.CanQuery = false
	rock.Color = Color3.fromRGB(rng:NextInteger(100, 125), rng:NextInteger(95, 115), rng:NextInteger(85, 105))
	rock.Material = Enum.Material.Slate
	rock.Parent = parent
end

local function buildEdgeProp(kind: string, sign: number, position: Vector3, rng: Random, parent: Instance)
	local template = getTemplate(kind)
	if template then
		local clone = template:Clone()
		clone:PivotTo(CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
		clone.Parent = parent
		return
	end
	if kind == "buildings" then
		buildBuilding(sign, position, rng, parent)
	elseif kind == "trees" then
		buildTree(position, rng, parent)
	else
		buildRuin(position, rng:NextNumber(0, math.pi * 2), rng, parent)
	end
end

function ChunkFactory.build(location: LocationsConfig.LocationConfig, blend: Blend?, rng: Random): Model
	local nextLocation = if blend then blend.next else nil
	local alpha = if blend then blend.alpha else 0
	local far = nextLocation ~= nil and alpha >= 0.5
	local effective = if far and nextLocation then nextLocation else location

	local floorMaterial = if far and nextLocation then nextLocation.floorMaterial else location.floorMaterial
	local apronMaterial = if far and nextLocation then nextLocation.apronMaterial else location.apronMaterial
	local floorColor = if nextLocation then location.floorColor:Lerp(nextLocation.floorColor, alpha) else location.floorColor
	local apronColor = if nextLocation then location.apronColor:Lerp(nextLocation.apronColor, alpha) else location.apronColor

	local model = Instance.new("Model")
	model.Name = "Chunk_" .. location.id

	local floor = createPart("Floor", Vector3.new(laneWidth, 1, chunkLength), CFrame.new(), floorColor, floorMaterial, model)

	local barrierSize = Vector3.new(barrierThickness, GameConstants.BARRIER_HEIGHT, chunkLength)
	local barrierOffsetX = (laneWidth + barrierThickness) / 2
	local barrierOffsetY = (GameConstants.BARRIER_HEIGHT + 1) / 2
	for _, sign in { -1, 1 } do
		local wall = createPart(
			"Barrier",
			barrierSize,
			CFrame.new(sign * barrierOffsetX, barrierOffsetY, 0),
			GameConstants.WALL_COLOR,
			Enum.Material.SmoothPlastic,
			model
		)
		wall.Transparency = GameConstants.WALL_TRANSPARENCY
		wall.CastShadow = false
	end

	local apronOffsetX = laneWidth / 2 + barrierThickness + apronWidth / 2
	for _, sign in { -1, 1 } do
		createPart(
			"Apron",
			Vector3.new(apronWidth, 1, chunkLength),
			CFrame.new(sign * apronOffsetX, 0, 0),
			apronColor,
			apronMaterial,
			model
		)
	end

	if effective.roadMarkings then
		for i = 0, 7 do
			local z = -chunkLength / 2 + 8 + i * 16
			local marking = createPart(
				"Marking",
				Vector3.new(0.8, 0.05, 6),
				CFrame.new(0, 0.53, z),
				Color3.fromRGB(220, 220, 210),
				Enum.Material.Neon,
				model
			)
			marking.CanCollide = false
			marking.CanQuery = false
			marking.CastShadow = false
		end
	end

	for _, sign in { -1, 1 } do
		local z = -chunkLength / 2 + rng:NextNumber(8, 20)
		while z < chunkLength / 2 - 8 do
			local kind = location.edgeProps
			if nextLocation and rng:NextNumber() < alpha then
				kind = nextLocation.edgeProps
			end
			local x = sign * (laneWidth / 2 + barrierThickness + rng:NextNumber(10, apronWidth - 16))
			buildEdgeProp(kind, sign, Vector3.new(x, 0.5, z), rng, model)
			z += rng:NextNumber(24, 38)
		end
	end

	if rng:NextNumber() < effective.lanePropChance then
		for _ = 1, rng:NextInteger(1, 2) do
			local sign = if rng:NextNumber() < 0.5 then -1 else 1
			local x = sign * rng:NextNumber(laneWidth / 2 - 16, laneWidth / 2 - 6)
			local z = rng:NextNumber(-chunkLength / 2 + 10, chunkLength / 2 - 10)
			if effective.edgeProps == "buildings" then
				buildCar(Vector3.new(x, 0.5, z), rng, model)
			else
				buildRock(Vector3.new(x, 0.5, z), rng, model)
			end
		end
	end

	model.PrimaryPart = floor
	return model
end

return ChunkFactory
