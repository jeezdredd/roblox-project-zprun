--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local TexturesConfig = require(ReplicatedStorage.Shared.config.TexturesConfig)
local MaterialUtil = require(ReplicatedStorage.Shared.util.MaterialUtil)

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
	Color3.fromRGB(140, 130, 120),
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

local function noShadow(part: BasePart): BasePart
	part.CastShadow = false
	return part
end

local function applyTexture(part: BasePart, face: Enum.NormalId, textureId: number, studsPerTile: number)
	if textureId <= 0 then
		return
	end
	local texture = Instance.new("Texture")
	texture.Texture = "rbxassetid://" .. tostring(textureId)
	texture.Face = face
	texture.StudsPerTileU = studsPerTile
	texture.StudsPerTileV = studsPerTile
	texture.Parent = part
end

local function getTemplate(kind: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("PropTemplates")
	local template = folder and folder:FindFirstChild(kind)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

local MAX_WINDOW_BANDS = 4

local function buildWindowBands(sign: number, height: number, width: number, depth: number, position: Vector3, rng: Random, parent: Instance)
	local faceX = position.X - sign * (depth / 2 + 0.15)
	local bands = math.min(MAX_WINDOW_BANDS, math.max(1, math.floor((height - 10) / 9)))
	for index = 1, bands do
		local y = 6 + (index - 1) * ((height - 12) / bands)
		local lit = rng:NextNumber() < 0.35
		local band = createPart(
			"WindowBand",
			Vector3.new(0.25, 2.4, width - 3),
			CFrame.new(faceX, position.Y + y, position.Z),
			if lit then Color3.fromRGB(255, 214, 140) else Color3.fromRGB(25, 30, 40),
			if lit then Enum.Material.Neon else Enum.Material.Glass,
			parent
		)
		band.Transparency = if lit then 0.45 else 0.1
		band.CanCollide = false
		band.CanQuery = false
		band.CastShadow = false
	end
end

local function buildBuilding(sign: number, position: Vector3, rng: Random, parent: Instance, widthOverride: number?, depthOverride: number?)
	local depth = depthOverride or rng:NextNumber(14, 20)
	local width = widthOverride or rng:NextNumber(18, 30)
	local height = rng:NextNumber(18, 42)
	local isBrick = rng:NextNumber() < 0.55
	local shade = rng:NextInteger(75, 115)
	local color = if isBrick
		then Color3.fromRGB(shade + 30, shade - 10, shade - 20)
		else Color3.fromRGB(shade, shade, shade + 6)
	local material = if isBrick then Enum.Material.Brick else Enum.Material.Concrete

	local body = createPart(
		"Building",
		Vector3.new(depth, height, width),
		CFrame.new(position.X, position.Y + height / 2, position.Z),
		color,
		material,
		parent
	)
	if isBrick then
		local laneFace = if sign > 0 then Enum.NormalId.Left else Enum.NormalId.Right
		applyTexture(body, laneFace, TexturesConfig.BRICKS, 2.5)
	end
	buildWindowBands(sign, height, width, depth, position, rng, parent)

	local roofColor = color:Lerp(Color3.new(0, 0, 0), 0.4)
	createPart(
		"Roof",
		Vector3.new(depth + 1.2, 1, width + 1.2),
		CFrame.new(position.X, position.Y + height + 0.5, position.Z),
		roofColor,
		Enum.Material.Concrete,
		parent
	)
	noShadow(createPart(
		"RoofBox",
		Vector3.new(3, 2, 4),
		CFrame.new(position.X + rng:NextNumber(-3, 3), position.Y + height + 2, position.Z + rng:NextNumber(-6, 6)),
		Color3.fromRGB(120, 122, 126),
		Enum.Material.DiamondPlate,
		parent
	))

	if rng:NextNumber() < 0.5 and height < 38 then
		local towerHeight = rng:NextNumber(10, 20)
		local towerWidth = width * 0.6
		local towerDepth = depth * 0.7
		local tower = createPart(
			"BuildingTower",
			Vector3.new(towerDepth, towerHeight, towerWidth),
			CFrame.new(position.X + sign * (depth - towerDepth) / 2, position.Y + height + 1 + towerHeight / 2, position.Z),
			color,
			material,
			parent
		)
		tower.CastShadow = true
		createPart(
			"TowerRoof",
			Vector3.new(towerDepth + 1, 0.8, towerWidth + 1),
			CFrame.new(position.X + sign * (depth - towerDepth) / 2, position.Y + height + 1.4 + towerHeight, position.Z),
			roofColor,
			Enum.Material.Concrete,
			parent
		)
	end
end

local function buildTree(position: Vector3, rng: Random, parent: Instance)
	local trunkHeight = rng:NextNumber(13, 21)
	local trunkRadius = rng:NextNumber(1.1, 1.8)

	local trunk = Instance.new("Part")
	trunk.Name = "Trunk"
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(trunkHeight, trunkRadius * 2, trunkRadius * 2)
	trunk.CFrame = CFrame.new(position.X, position.Y + trunkHeight / 2, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	trunk.Anchored = true
	trunk.Color = Color3.fromRGB(92, 68, 46)
	trunk.Material = Enum.Material.Wood
	trunk.Parent = parent

	local canopyRadius = rng:NextNumber(5, 7.5)
	for i = 1, 2 do
		local ball = Instance.new("Part")
		ball.Name = "Canopy"
		ball.Shape = Enum.PartType.Ball
		local radius = canopyRadius * (if i == 1 then 1 else 0.7)
		ball.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		ball.CFrame = CFrame.new(
			position.X + rng:NextNumber(-2, 2),
			position.Y + trunkHeight + radius * 0.6 + (i - 1) * radius * 0.8,
			position.Z + rng:NextNumber(-2, 2)
		)
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.Color = Color3.fromRGB(rng:NextInteger(40, 60), rng:NextInteger(95, 125), rng:NextInteger(40, 60))
		ball.Material = Enum.Material.Grass
		ball.Parent = parent
	end
end

local function buildCanopyCover(position: Vector3, rng: Random, parent: Instance)
	local spanX = rng:NextNumber(28, 42)
	local spanZ = rng:NextNumber(28, 42)
	local cover = Instance.new("Part")
	cover.Name = "CanopyCover"
	cover.Shape = Enum.PartType.Ball
	cover.Size = Vector3.new(spanX, rng:NextNumber(7, 10), spanZ)
	cover.CFrame = CFrame.new(position.X, position.Y + rng:NextNumber(16, 20), position.Z)
	cover.Anchored = true
	cover.CanCollide = false
	cover.CanQuery = false
	cover.Color = Color3.fromRGB(rng:NextInteger(35, 50), rng:NextInteger(85, 110), rng:NextInteger(35, 50))
	cover.Material = Enum.Material.Grass
	cover.Parent = parent
end

local function buildRuin(position: Vector3, rotationY: number, rng: Random, parent: Instance)
	local wallHeight = rng:NextNumber(6, 14)
	createPart(
		"RuinWall",
		Vector3.new(1.4, wallHeight, rng:NextNumber(8, 14)),
		CFrame.new(position.X, position.Y + wallHeight / 2, position.Z) * CFrame.Angles(0, rotationY, rng:NextNumber(-0.08, 0.08)),
		Color3.fromRGB(130, 122, 110),
		Enum.Material.Concrete,
		parent
	)
	for _ = 1, rng:NextInteger(1, 2) do
		createPart(
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
	end
end

local function buildWheels(base: CFrame, length: number, parent: Instance)
	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			local wheel = Instance.new("Part")
			wheel.Name = "Wheel"
			wheel.Shape = Enum.PartType.Cylinder
			wheel.Size = Vector3.new(1.1, 2.2, 2.2)
			wheel.CFrame = base * CFrame.new(xSign * 3.1, -0.9, zSign * (length / 2 - 2.2)) * CFrame.Angles(0, 0, math.rad(90))
			wheel.Anchored = true
			wheel.CanQuery = false
			wheel.Color = Color3.fromRGB(30, 30, 32)
			wheel.Material = Enum.Material.SmoothPlastic
			wheel.Parent = parent
		end
	end
end

local function buildCar(position: Vector3, yaw: number, rng: Random, parent: Instance)
	local color = CAR_COLORS[rng:NextInteger(1, #CAR_COLORS)]
	local base = CFrame.new(position.X, position.Y + 2.1, position.Z) * CFrame.Angles(0, yaw, 0)
	createPart("CarBody", Vector3.new(6.4, 2.3, 12.4), base, color, Enum.Material.Metal, parent)
	local cabin = createPart("CarCabin", Vector3.new(5.6, 1.9, 5.6), base * CFrame.new(0, 2.05, 0.6), Color3.fromRGB(35, 40, 50), Enum.Material.Glass, parent)
	cabin.Transparency = 0.2
	buildWheels(base, 12.4, parent)
end

local function buildBus(position: Vector3, yaw: number, rng: Random, parent: Instance)
	local base = CFrame.new(position.X, position.Y + 3.9, position.Z) * CFrame.Angles(0, yaw, 0)
	createPart("BusBody", Vector3.new(7.5, 6.6, 25.5), base, Color3.fromRGB(180, 140, 60), Enum.Material.Metal, parent)
	local windows = createPart("BusWindows", Vector3.new(7.55, 2.1, 21), base * CFrame.new(0, 1.35, 0), Color3.fromRGB(35, 40, 50), Enum.Material.Glass, parent)
	windows.Transparency = 0.2
	windows.CanCollide = false
	windows.CanQuery = false
	buildWheels(base * CFrame.new(0, -1.65, 0), 22, parent)
	local _ = rng
end

local function buildTruck(position: Vector3, yaw: number, rng: Random, parent: Instance)
	local base = CFrame.new(position.X, position.Y + 3.3, position.Z) * CFrame.Angles(0, yaw, 0)
	createPart("TruckCab", Vector3.new(7.5, 5.4, 6.75), base * CFrame.new(0, 0, 10.5), Color3.fromRGB(90, 110, 130), Enum.Material.Metal, parent)
	createPart("TruckTrailer", Vector3.new(8.1, 7.5, 18), base * CFrame.new(0, 1.05, -3.75), Color3.fromRGB(150, 150, 154), Enum.Material.Metal, parent)
	buildWheels(base * CFrame.new(0, -1.35, -1.5), 24, parent)
	local _ = rng
end

local function buildCrash(position: Vector3, rng: Random, parent: Instance)
	buildCar(position + Vector3.new(-3.8, 0, -3), rng:NextNumber(0.4, 1.1), rng, parent)
	buildCar(position + Vector3.new(3.8, 0, 3), rng:NextNumber(-1.1, -0.4), rng, parent)
	for _ = 1, 3 do
		createPart(
			"Debris",
			Vector3.new(rng:NextNumber(0.8, 1.8), rng:NextNumber(0.4, 0.9), rng:NextNumber(0.8, 1.8)),
			CFrame.new(position.X + rng:NextNumber(-5, 5), position.Y + 0.8, position.Z + rng:NextNumber(-5, 5))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			Color3.fromRGB(60, 60, 64),
			Enum.Material.CorrodedMetal,
			parent
		)
	end
end

local function buildDivider(position: Vector3, rng: Random, parent: Instance)
	local segments = rng:NextInteger(2, 3)
	for i = 0, segments - 1 do
		createPart(
			"Divider",
			Vector3.new(2.2, 3, 10),
			CFrame.new(position.X, position.Y + 2, position.Z + i * 11 - (segments - 1) * 5.5),
			Color3.fromRGB(168, 168, 170),
			Enum.Material.Concrete,
			parent
		)
	end
end

local function buildLog(position: Vector3, rng: Random, parent: Instance)
	local length = rng:NextNumber(12, 20)
	local log = Instance.new("Part")
	log.Name = "FallenLog"
	log.Shape = Enum.PartType.Cylinder
	log.Size = Vector3.new(length, 3.2, 3.2)
	log.CFrame = CFrame.new(position.X, position.Y + 1.8, position.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	log.Anchored = true
	log.Color = Color3.fromRGB(86, 62, 42)
	log.Material = Enum.Material.Wood
	log.Parent = parent
end

local function buildBoulder(position: Vector3, rng: Random, parent: Instance)
	local size = rng:NextNumber(4.5, 9)
	local rock = Instance.new("Part")
	rock.Name = "Boulder"
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.new(size, size * rng:NextNumber(0.7, 0.9), size)
	rock.CFrame = CFrame.new(position.X, position.Y + size * 0.35, position.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	rock.Anchored = true
	rock.Color = Color3.fromRGB(rng:NextInteger(100, 125), rng:NextInteger(95, 115), rng:NextInteger(85, 105))
	rock.Material = Enum.Material.Slate
	rock.Parent = parent
end

local function buildRubblePile(position: Vector3, rng: Random, parent: Instance)
	for _ = 1, rng:NextInteger(3, 4) do
		createPart(
			"Rubble",
			Vector3.new(rng:NextNumber(2, 5), rng:NextNumber(1, 2.4), rng:NextNumber(2, 4)),
			CFrame.new(position.X + rng:NextNumber(-3, 3), position.Y + rng:NextNumber(0.5, 1.6), position.Z + rng:NextNumber(-3, 3))
				* CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, math.pi), rng:NextNumber(-0.2, 0.2)),
			Color3.fromRGB(126, 118, 106),
			Enum.Material.Concrete,
			parent
		)
	end
end

local function buildFarmhouse(sign: number, position: Vector3, rng: Random, parent: Instance)
	local width = rng:NextNumber(16, 26)
	local depth = rng:NextNumber(14, 22)
	local height = rng:NextNumber(10, 15)
	local shell = Color3.fromRGB(rng:NextInteger(24, 34), rng:NextInteger(22, 30), rng:NextInteger(22, 28))

	createPart("FarmWall", Vector3.new(width, height, depth), CFrame.new(position + Vector3.new(0, height / 2, 0)), shell, Enum.Material.WoodPlanks, parent)

	local roof = Instance.new("WedgePart")
	roof.Name = "FarmRoof"
	roof.Size = Vector3.new(depth, height * 0.45, width)
	roof.CFrame = CFrame.new(position + Vector3.new(0, height + height * 0.22, 0)) * CFrame.Angles(0, math.rad(90), 0)
	roof.Anchored = true
	roof.CanCollide = false
	roof.CanQuery = false
	roof.CastShadow = false
	roof.Color = shell:Lerp(Color3.new(), 0.35)
	roof.Material = Enum.Material.Wood
	roof.Parent = parent

	local porch = createPart(
		"FarmPorch",
		Vector3.new(width * 0.8, 0.6, 4),
		CFrame.new(position + Vector3.new(0, 1.4, -sign * (depth / 2 + 2))),
		shell:Lerp(Color3.new(), 0.2),
		Enum.Material.WoodPlanks,
		parent
	)
	porch.CanCollide = false
	for _, offset in { -0.36, 0.36 } do
		createPart(
			"PorchPost",
			Vector3.new(0.5, 4.6, 0.5),
			CFrame.new(position + Vector3.new(width * offset, 3.7, -sign * (depth / 2 + 3.6))),
			shell:Lerp(Color3.new(), 0.2),
			Enum.Material.Wood,
			parent
		)
	end
end

local function buildTelegraphPole(position: Vector3, parent: Instance): BasePart
	local pole = createPart(
		"TelegraphPole",
		Vector3.new(0.9, 26, 0.9),
		CFrame.new(position + Vector3.new(0, 13, 0)),
		Color3.fromRGB(58, 46, 36),
		Enum.Material.Wood,
		parent
	)
	createPart(
		"PoleCross",
		Vector3.new(7, 0.5, 0.5),
		CFrame.new(position + Vector3.new(0, 23.4, 0)),
		Color3.fromRGB(52, 42, 32),
		Enum.Material.Wood,
		parent
	).CanCollide = false

	local attachment = Instance.new("Attachment")
	attachment.Name = "WireAnchor"
	attachment.Position = Vector3.new(0, 10.4, 0)
	attachment.Parent = pole
	return pole
end

local function buildFencePost(position: Vector3, rng: Random, parent: Instance)
	local post = createPart(
		"FencePost",
		Vector3.new(0.4, rng:NextNumber(4, 5.4), 0.4),
		CFrame.new(position + Vector3.new(0, 2.4, 0)) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.06, 0.06)),
		Color3.fromRGB(64, 52, 40),
		Enum.Material.Wood,
		parent
	)
	post.CanCollide = false
end

local function buildDryGrass(position: Vector3, rng: Random, parent: Instance)
	for i = 1, rng:NextInteger(3, 6) do
		local blade = createPart(
			"DryGrass",
			Vector3.new(rng:NextNumber(1.6, 3), rng:NextNumber(3.5, 6.5), 0.14),
			CFrame.new(position + Vector3.new(rng:NextNumber(-3, 3), 2, rng:NextNumber(-3, 3)))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-8, 8))),
			Color3.fromRGB(rng:NextInteger(150, 186), rng:NextInteger(128, 156), rng:NextInteger(64, 88)),
			Enum.Material.Grass,
			parent
		)
		blade.CanCollide = false
		blade.CanQuery = false
		blade.CastShadow = false
		if i > 4 then
			break
		end
	end
end

local function buildUndergrowth(position: Vector3, rng: Random, parent: Instance)
	local roll = rng:NextNumber()
	if roll < 0.4 then
		local capRadius = rng:NextNumber(0.4, 0.9)
		local stem = createPart(
			"MushroomStem",
			Vector3.new(0.18, capRadius * 1.6, 0.18),
			CFrame.new(position + Vector3.new(0, capRadius * 0.8, 0)),
			Color3.fromRGB(216, 208, 186),
			Enum.Material.SmoothPlastic,
			parent
		)
		noShadow(stem).CanCollide = false
		local cap = Instance.new("Part")
		cap.Name = "MushroomCap"
		cap.Shape = Enum.PartType.Ball
		cap.Size = Vector3.new(capRadius * 2, capRadius, capRadius * 2)
		cap.CFrame = CFrame.new(position + Vector3.new(0, capRadius * 1.6, 0))
		cap.Anchored = true
		cap.CanCollide = false
		cap.CanQuery = false
		cap.CastShadow = false
		cap.Color = Color3.fromRGB(rng:NextInteger(120, 168), rng:NextInteger(56, 84), rng:NextInteger(48, 70))
		cap.Material = Enum.Material.SmoothPlastic
		cap.Parent = parent
		return
	end

	for _ = 1, rng:NextInteger(2, 4) do
		local fern = createPart(
			"Fern",
			Vector3.new(rng:NextNumber(1.8, 3.6), 0.12, rng:NextNumber(1.8, 3.3)),
			CFrame.new(position + Vector3.new(rng:NextNumber(-2.2, 2.2), rng:NextNumber(0.5, 1.4), rng:NextNumber(-2.2, 2.2)))
				* CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-25, 25))),
			Color3.fromRGB(rng:NextInteger(36, 58), rng:NextInteger(72, 98), rng:NextInteger(34, 52)),
			Enum.Material.Grass,
			parent
		)
		noShadow(fern).CanCollide = false
		fern.CanQuery = false
	end
end

local function buildCornWall(position: Vector3, rng: Random, parent: Instance)
	local width = rng:NextNumber(16, 26)
	local wall = createPart(
		"CornWall",
		Vector3.new(width, rng:NextNumber(13, 17), rng:NextNumber(10, 18)),
		CFrame.new(position + Vector3.new(0, 7.5, 0)) * CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0),
		Color3.fromRGB(rng:NextInteger(26, 38), rng:NextInteger(30, 42), rng:NextInteger(20, 28)),
		Enum.Material.Grass,
		parent
	)
	wall.CanCollide = false

	for _ = 1, rng:NextInteger(4, 7) do
		local stalk = createPart(
			"CornStalk",
			Vector3.new(0.3, rng:NextNumber(8, 12), 0.3),
			CFrame.new(position + Vector3.new(rng:NextNumber(-width / 2, width / 2), 5, rng:NextNumber(-6, 6)))
				* CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-6, 6))),
			Color3.fromRGB(rng:NextInteger(40, 58), rng:NextInteger(48, 66), rng:NextInteger(28, 38)),
			Enum.Material.Grass,
			parent
		)
		stalk.CanCollide = false
		stalk.CanQuery = false
		stalk.CastShadow = false
	end
end

local function buildObstacle(kind: string, position: Vector3, rng: Random, parent: Instance)
	if kind == "farm" then
		local roll = rng:NextNumber()
		if roll < 0.35 then
			buildCar(position, rng:NextNumber(-0.5, 0.5), rng, parent)
		elseif roll < 0.6 then
			buildLog(position, rng, parent)
		elseif roll < 0.85 then
			buildBoulder(position, rng, parent)
		else
			buildCrash(position, rng, parent)
		end
		return
	end
	if kind == "corn" then
		if rng:NextNumber() < 0.6 then
			buildLog(position, rng, parent)
		else
			buildBoulder(position, rng, parent)
		end
		return
	end
	if kind == "buildings" then
		local roll = rng:NextNumber()
		if roll < 0.3 then
			buildCar(position, rng:NextNumber(-0.5, 0.5), rng, parent)
		elseif roll < 0.45 then
			buildBus(position, rng:NextNumber(-0.4, 0.4), rng, parent)
		elseif roll < 0.6 then
			buildTruck(position, rng:NextNumber(-0.4, 0.4), rng, parent)
		elseif roll < 0.82 then
			buildCrash(position, rng, parent)
		else
			buildDivider(position, rng, parent)
		end
	elseif kind == "trees" then
		if rng:NextNumber() < 0.55 then
			buildLog(position, rng, parent)
		else
			buildBoulder(position, rng, parent)
		end
	else
		local roll = rng:NextNumber()
		if roll < 0.45 then
			buildRubblePile(position, rng, parent)
		elseif roll < 0.72 then
			buildBoulder(position, rng, parent)
		else
			buildCrash(position, rng, parent)
		end
	end
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
	elseif kind == "farm" then
		local roll = rng:NextNumber()
		if roll < 0.3 then
			buildFarmhouse(sign, position, rng, parent)
		elseif roll < 0.5 then
			buildTree(position, rng, parent)
		else
			buildDryGrass(position, rng, parent)
			buildFencePost(position, rng, parent)
		end
	elseif kind == "corn" then
		buildCornWall(position, rng, parent)
	else
		buildRuin(position, rng:NextNumber(0, math.pi * 2), rng, parent)
	end
end

local function buildWireRun(kind: string, sign: number, zStart: number, zEnd: number, x: number, rng: Random, parent: Instance)
	if kind ~= "farm" and kind ~= "corn" then
		return
	end
	local spacing = 58
	local previous: Attachment? = nil
	local z = zStart
	while z <= zEnd do
		local pole = buildTelegraphPole(Vector3.new(x + rng:NextNumber(-3, 3), 0.5, z), parent)
		local anchor = pole:FindFirstChild("WireAnchor") :: Attachment
		if previous and anchor then
			local wire = Instance.new("Beam")
			wire.Name = "PowerWire"
			wire.Attachment0 = previous
			wire.Attachment1 = anchor
			wire.Width0 = 0.12
			wire.Width1 = 0.12
			wire.CurveSize0 = -6
			wire.CurveSize1 = -6
			wire.Color = ColorSequence.new(Color3.fromRGB(24, 22, 20))
			wire.LightInfluence = 0
			wire.FaceCamera = true
			wire.Parent = previous.Parent
		end
		previous = anchor
		z += spacing
	end
	if sign < 0 then
		return
	end
end

local FLICKER_TAG = "TFZ_Flicker"
local LAMP_HEIGHT = 14
local LAMP_ARM = 5
local LAMP_COLOR = Color3.fromRGB(58, 60, 62)
local LAMP_GLOW = Color3.fromRGB(255, 214, 160)
local LAMP_LIGHT = Color3.fromRGB(255, 196, 130)
local FIRE_LIGHT = Color3.fromRGB(255, 140, 60)

local function buildStreetLamp(sign: number, position: Vector3, rng: Random, parent: Instance)
	local post = createPart(
		"LampPost",
		Vector3.new(0.5, LAMP_HEIGHT, 0.5),
		CFrame.new(position.X, position.Y + LAMP_HEIGHT / 2, position.Z),
		LAMP_COLOR,
		Enum.Material.Metal,
		parent
	)
	noShadow(createPart(
		"LampArm",
		Vector3.new(LAMP_ARM, 0.35, 0.35),
		CFrame.new(position.X - sign * LAMP_ARM / 2, position.Y + LAMP_HEIGHT - 0.3, position.Z),
		LAMP_COLOR,
		Enum.Material.Metal,
		parent
	))
	local head = noShadow(createPart(
		"LampHead",
		Vector3.new(1.6, 0.5, 0.9),
		CFrame.new(position.X - sign * LAMP_ARM, position.Y + LAMP_HEIGHT - 0.7, position.Z),
		Color3.fromRGB(40, 40, 42),
		Enum.Material.Metal,
		parent
	))
	post.CanCollide = true
	if rng:NextNumber() >= 0.72 then
		return
	end
	local bulb = noShadow(createPart(
		"LampBulb",
		Vector3.new(1.5, 0.22, 0.8),
		CFrame.new(head.Position - Vector3.new(0, 0.32, 0)),
		LAMP_GLOW,
		Enum.Material.Neon,
		parent
	))
	bulb.CanCollide = false
	bulb.CanQuery = false
	local light = Instance.new("PointLight")
	light.Color = LAMP_LIGHT
	light.Brightness = 2.4
	light.Range = 34
	light.Shadows = false
	light.Parent = bulb
	if rng:NextNumber() < 0.3 then
		CollectionService:AddTag(light, FLICKER_TAG)
	end
end

local function buildBurningBarrel(position: Vector3, rng: Random, parent: Instance)
	local barrel = createPart(
		"Barrel",
		Vector3.new(3.4, 2.6, 2.6),
		CFrame.new(position.X, position.Y + 1.7, position.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.pi / 2),
		Color3.fromRGB(70, 50, 40),
		Enum.Material.CorrodedMetal,
		parent
	)
	barrel.Shape = Enum.PartType.Cylinder
	local anchor = noShadow(createPart(
		"BarrelFire",
		Vector3.new(1.6, 0.4, 1.6),
		CFrame.new(position.X, position.Y + 3.5, position.Z),
		FIRE_LIGHT,
		Enum.Material.SmoothPlastic,
		parent
	))
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 12
	fire.Color = Color3.fromRGB(255, 150, 60)
	fire.SecondaryColor = Color3.fromRGB(180, 40, 10)
	fire.Parent = anchor
	local smoke = Instance.new("Smoke")
	smoke.Size = 4
	smoke.Opacity = 0.22
	smoke.RiseVelocity = 6
	smoke.Color = Color3.fromRGB(40, 36, 34)
	smoke.Parent = anchor
	local light = Instance.new("PointLight")
	light.Color = FIRE_LIGHT
	light.Brightness = 2
	light.Range = 24
	light.Shadows = false
	light.Parent = anchor
	CollectionService:AddTag(light, FLICKER_TAG)
end

local function buildTrafficJam(position: Vector3, rng: Random, parent: Instance)
	local count = rng:NextInteger(3, 5)
	local step = rng:NextNumber(13, 16)
	local z = position.Z - (count - 1) * step / 2
	for _ = 1, count do
		local x = position.X + rng:NextNumber(-3, 3)
		buildCar(Vector3.new(x, position.Y, z), rng:NextNumber(-0.25, 0.25), rng, parent)
		z += step
	end
end

local function buildSmokeColumn(position: Vector3, parent: Instance)
	local anchor = noShadow(createPart(
		"SmokeColumn",
		Vector3.new(2, 2, 2),
		CFrame.new(position),
		Color3.fromRGB(40, 36, 34),
		Enum.Material.SmoothPlastic,
		parent
	))
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	local smoke = Instance.new("Smoke")
	smoke.Size = 14
	smoke.Opacity = 0.35
	smoke.RiseVelocity = 4
	smoke.Color = Color3.fromRGB(46, 40, 38)
	smoke.Parent = anchor
end

local EDGE_OFFSET = 4
local POLICE_WHITE = Color3.fromRGB(226, 228, 230)
local POLICE_BLUE = Color3.fromRGB(28, 44, 110)

local function corridorEdgeX(sign: number): number
	return sign * (GameConstants.PLAYABLE_HALF_WIDTH + EDGE_OFFSET)
end

local function buildPoliceCar(position: Vector3, yaw: number, rng: Random, parent: Instance)
	local base = CFrame.new(position.X, position.Y + 2.1, position.Z) * CFrame.Angles(0, yaw, 0)
	createPart("CarBody", Vector3.new(6.4, 2.3, 12.4), base, POLICE_WHITE, Enum.Material.Metal, parent)
	noShadow(createPart("CarStripe", Vector3.new(6.5, 0.7, 12.5), base * CFrame.new(0, -0.5, 0), POLICE_BLUE, Enum.Material.Metal, parent))
	local cabin = createPart("CarCabin", Vector3.new(5.6, 1.9, 5.6), base * CFrame.new(0, 2.05, 0.6), Color3.fromRGB(35, 40, 50), Enum.Material.Glass, parent)
	cabin.Transparency = 0.2
	buildWheels(base, 12.4, parent)
	local bar = noShadow(createPart("LightBar", Vector3.new(4.2, 0.4, 1), base * CFrame.new(0, 3.2, 0.6), Color3.fromRGB(40, 40, 44), Enum.Material.SmoothPlastic, parent))
	bar.CanCollide = false
	if rng:NextNumber() < 0.6 then
		for index, color in { Color3.fromRGB(255, 60, 60), Color3.fromRGB(70, 110, 255) } do
			local lamp = noShadow(createPart("LightBarLamp", Vector3.new(1.6, 0.42, 0.9), base * CFrame.new((index - 1.5) * 2, 3.2, 0.6), color, Enum.Material.Neon, parent))
			lamp.CanCollide = false
			lamp.CanQuery = false
			local light = Instance.new("PointLight")
			light.Color = color
			light.Brightness = 2
			light.Range = 18
			light.Shadows = false
			light.Parent = lamp
			CollectionService:AddTag(light, FLICKER_TAG)
		end
	end
end

local function buildFenceRun(sign: number, zStart: number, length: number, rng: Random, parent: Instance)
	local x = corridorEdgeX(sign) + sign * 0.5
	local height = rng:NextNumber(5, 6.5)
	local mesh = createPart(
		"Fence",
		Vector3.new(0.2, height, length),
		CFrame.new(x, 0.5 + height / 2, zStart + length / 2),
		Color3.fromRGB(150, 152, 150),
		Enum.Material.Metal,
		parent
	)
	mesh.Transparency = 0.35
	mesh.CastShadow = false
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		applyTexture(mesh, face, TexturesConfig.FENCE_CHAINLINK, 4)
	end
	local z = zStart
	while z <= zStart + length + 0.1 do
		noShadow(createPart("FencePole", Vector3.new(0.5, height + 0.6, 0.5), CFrame.new(x, 0.5 + (height + 0.6) / 2, z), Color3.fromRGB(80, 82, 84), Enum.Material.Metal, parent))
		z += 8
	end
end

local function buildCarRow(sign: number, zStart: number, count: number, rng: Random, parent: Instance)
	local x = corridorEdgeX(sign) + sign * 4.6
	for index = 0, count - 1 do
		local position = Vector3.new(x + rng:NextNumber(-0.6, 0.6), 0.5, zStart + 6.5 + index * 13.5)
		if rng:NextNumber() < 0.18 then
			buildPoliceCar(position, rng:NextNumber(-0.12, 0.12), rng, parent)
		else
			buildCar(position, rng:NextNumber(-0.12, 0.12), rng, parent)
		end
	end
end

local function buildJerseyRow(sign: number, zStart: number, length: number, parent: Instance)
	local x = corridorEdgeX(sign) + sign * 1.2
	local z = zStart
	while z + 10 <= zStart + length + 0.1 do
		createPart("Divider", Vector3.new(2.2, 3, 10), CFrame.new(x, 2.5, z + 5), Color3.fromRGB(168, 168, 170), Enum.Material.Concrete, parent)
		z += 10.4
	end
end

local function buildRailFence(sign: number, zStart: number, length: number, rng: Random, parent: Instance)
	local x = corridorEdgeX(sign) + sign * 0.5
	local z = zStart
	while z <= zStart + length + 0.1 do
		buildFencePost(Vector3.new(x, 0.5, z), rng, parent)
		z += 6
	end
	for _, height in { 2, 3.6 } do
		local rail = noShadow(createPart("FenceRail", Vector3.new(0.25, 0.3, length), CFrame.new(x, 0.5 + height, zStart + length / 2), Color3.fromRGB(70, 56, 42), Enum.Material.Wood, parent))
		rail.CanCollide = false
	end
end

local function buildCorridorEdge(kind: string, sign: number, rng: Random, parent: Instance)
	local edgeX = corridorEdgeX(sign)
	local z = -chunkLength / 2 + rng:NextNumber(0, 4)
	while z < chunkLength / 2 - 4 do
		local roll = rng:NextNumber()
		local remaining = chunkLength / 2 - z
		if kind == "buildings" then
			if roll < 0.34 then
				local width = math.min(rng:NextNumber(18, 30), remaining)
				local depth = rng:NextNumber(14, 22)
				buildBuilding(sign, Vector3.new(edgeX + sign * depth / 2, 0.5, z + width / 2), rng, parent, width, depth)
				z += width + rng:NextNumber(1, 4)
			elseif roll < 0.52 then
				local length = math.min(rng:NextNumber(12, 24), remaining)
				buildFenceRun(sign, z, length, rng, parent)
				z += length + 1
			elseif roll < 0.66 then
				local count = rng:NextInteger(2, 3)
				buildCarRow(sign, z, count, rng, parent)
				z += count * 13.5 + 2
			elseif roll < 0.74 then
				buildPoliceCar(Vector3.new(edgeX + sign * 4.6, 0.5, z + 7), rng:NextNumber(-0.35, 0.35), rng, parent)
				z += 15
			elseif roll < 0.86 then
				buildRubblePile(Vector3.new(edgeX + sign * 4, 0.5, z + 5), rng, parent)
				z += 10
			else
				local length = math.min(rng:NextNumber(12, 21), remaining)
				buildJerseyRow(sign, z, length, parent)
				z += length + 1
			end
		elseif kind == "trees" then
			buildTree(Vector3.new(edgeX + sign * rng:NextNumber(1, 6), 0.5, z), rng, parent)
			if rng:NextNumber() < 0.25 then
				buildBoulder(Vector3.new(edgeX + sign * rng:NextNumber(-2, 2), 0.5, z + rng:NextNumber(2, 5)), rng, parent)
			end
			z += rng:NextNumber(5, 9)
		elseif kind == "farm" then
			local length = math.min(rng:NextNumber(24, 48), remaining)
			buildRailFence(sign, z, length, rng, parent)
			if rng:NextNumber() < 0.5 then
				buildTree(Vector3.new(edgeX + sign * rng:NextNumber(4, 10), 0.5, z + rng:NextNumber(4, length - 4)), rng, parent)
			end
			z += length + rng:NextNumber(2, 6)
		elseif kind == "corn" then
			buildCornWall(Vector3.new(edgeX + sign * 8, 0.5, z + 9), rng, parent)
			z += rng:NextNumber(14, 20)
		else
			if roll < 0.4 then
				buildRuin(Vector3.new(edgeX + sign * 3, 0.5, z + 6), 0, rng, parent)
				z += 13
			elseif roll < 0.65 then
				buildRubblePile(Vector3.new(edgeX + sign * 4, 0.5, z + 5), rng, parent)
				z += 10
			elseif roll < 0.82 then
				buildCrash(Vector3.new(edgeX + sign * 5, 0.5, z + 8), rng, parent)
				z += 16
			else
				buildBoulder(Vector3.new(edgeX + sign * 4, 0.5, z + 4), rng, parent)
				z += 9
			end
		end
	end
end

function ChunkFactory.build(location: LocationsConfig.LocationConfig, blend: Blend?, rng: Random, obstacleCount: number): Model
	local nextLocation = if blend then blend.next else nil
	local alpha = if blend then blend.alpha else 0
	local far = nextLocation ~= nil and alpha >= 0.5
	local effective = if far and nextLocation then nextLocation else location

	local floorMaterial = if far and nextLocation then nextLocation.floorMaterial else location.floorMaterial
	local apronMaterial = if far and nextLocation then nextLocation.apronMaterial else location.apronMaterial
	local floorColor = if nextLocation then location.floorColor:Lerp(nextLocation.floorColor, alpha) else location.floorColor
	local apronColor = if nextLocation then location.apronColor:Lerp(nextLocation.apronColor, alpha) else location.apronColor
	local floorTextureId = if far and nextLocation then nextLocation.floorTextureId else location.floorTextureId
	local apronTextureId = if far and nextLocation then nextLocation.apronTextureId else location.apronTextureId
	local isField = effective.laneStyle == "field"

	local model = Instance.new("Model")
	model.Name = "Chunk_" .. location.id

	local floor = createPart("Floor", Vector3.new(laneWidth, 1, chunkLength), CFrame.new(), floorColor, floorMaterial, model)
	local pbrName = if floorMaterial == Enum.Material.Asphalt
		then "TFZ_Asphalt"
		elseif floorMaterial == Enum.Material.Concrete then "TFZ_Concrete"
		else nil
	if not (pbrName and MaterialUtil.apply(floor, pbrName)) then
		applyTexture(floor, Enum.NormalId.Top, floorTextureId, 8)
	end

	for _ = 1, rng:NextInteger(2, 5) do
		local stain = createPart(
			"Stain",
			Vector3.new(rng:NextNumber(4, 11), 0.06, rng:NextNumber(4, 11)),
			CFrame.new(
				rng:NextNumber(-laneWidth / 2 + 6, laneWidth / 2 - 6),
				0.56,
				rng:NextNumber(-chunkLength / 2 + 6, chunkLength / 2 - 6)
			) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			Color3.fromRGB(rng:NextInteger(58, 96), rng:NextInteger(18, 34), rng:NextInteger(16, 30)),
			Enum.Material.SmoothPlastic,
			model
		)
		stain.Transparency = rng:NextNumber(0.3, 0.55)
		stain.CanCollide = false
		stain.CanQuery = false
		stain.CastShadow = false
	end

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
		wall.Transparency = if isField then 1 else GameConstants.WALL_TRANSPARENCY
		wall.CastShadow = false
	end

	local apronOffsetX = laneWidth / 2 + barrierThickness + apronWidth / 2
	for _, sign in { -1, 1 } do
		local apron = createPart(
			"Apron",
			Vector3.new(apronWidth, 1, chunkLength),
			CFrame.new(sign * apronOffsetX, 0, 0),
			apronColor,
			apronMaterial,
			model
		)
		applyTexture(apron, Enum.NormalId.Top, apronTextureId, 7)
	end

	if effective.roadMarkings and not isField then
		for _, laneX in { -laneWidth / 4, laneWidth / 4 } do
			for i = 0, 7 do
				local z = -chunkLength / 2 + 8 + i * 16
				local marking = createPart(
					"Marking",
					Vector3.new(0.8, 0.05, 6),
					CFrame.new(laneX, 0.53, z),
					Color3.fromRGB(200, 200, 194),
					Enum.Material.SmoothPlastic,
					model
				)
				marking.CanCollide = false
				marking.CanQuery = false
				marking.CastShadow = false
			end
		end
	end

	local edgeStep = if effective.edgeProps == "trees"
		then { 22, 34 }
		elseif effective.edgeProps == "buildings" then { 18, 30 }
		else { 30, 46 }
	for _, sign in { -1, 1 } do
		local z = -chunkLength / 2 + rng:NextNumber(6, 20)
		while z < chunkLength / 2 - 8 do
			local kind = location.edgeProps
			if nextLocation and rng:NextNumber() < alpha then
				kind = nextLocation.edgeProps
			end
			local nearOffset = if kind == "buildings" then 2 else 10
			local farOffset = if kind == "buildings" then apronWidth - 55 else apronWidth - 20
			local x = sign * (laneWidth / 2 + barrierThickness + rng:NextNumber(nearOffset, farOffset))
			buildEdgeProp(kind, sign, Vector3.new(x, 0.5, z), rng, model)
			z += rng:NextNumber(edgeStep[1], edgeStep[2])
		end

		buildCorridorEdge(effective.edgeProps, sign, rng, model)

		if effective.edgeProps == "buildings" then
			local debrisZ = -chunkLength / 2 + rng:NextNumber(8, 22)
			while debrisZ < chunkLength / 2 - 8 do
				local x = sign * (GameConstants.PLAYABLE_HALF_WIDTH - rng:NextNumber(3, 14))
				local roll = rng:NextNumber()
				local position = Vector3.new(x, 0.5, debrisZ)
				if roll < 0.4 then
					buildCar(position, rng:NextNumber(-1.2, 1.2), rng, model)
				elseif roll < 0.66 then
					buildRubblePile(position, rng, model)
				elseif roll < 0.86 then
					buildDivider(position, rng, model)
				else
					buildCrash(position, rng, model)
				end
				debrisZ += rng:NextNumber(28, 52)
			end
		end
	end

	if effective.edgeProps == "buildings" then
		local bandHalf = GameConstants.PLAYABLE_HALF_WIDTH
		for _, sign in { -1, 1 } do
			local lampX = sign * (bandHalf + 2.5)
			local lampZ = -chunkLength / 2 + rng:NextNumber(4, 14)
			while lampZ < chunkLength / 2 - 6 do
				buildStreetLamp(sign, Vector3.new(lampX, 0.5, lampZ), rng, model)
				lampZ += rng:NextNumber(34, 44)
			end
		end
		for _ = 1, rng:NextInteger(1, 2) do
			local sign = if rng:NextNumber() < 0.5 then -1 else 1
			buildBurningBarrel(Vector3.new(sign * rng:NextNumber(bandHalf - 24, bandHalf + 4), 0.5, rng:NextNumber(-chunkLength / 2 + 8, chunkLength / 2 - 8)), rng, model)
		end
		if rng:NextNumber() < 0.35 then
			buildTrafficJam(Vector3.new(rng:NextNumber(-bandHalf * 0.8, bandHalf * 0.8), 0.5, rng:NextNumber(-20, 20)), rng, model)
		end
		if rng:NextNumber() < 0.3 then
			local sign = if rng:NextNumber() < 0.5 then -1 else 1
			buildSmokeColumn(Vector3.new(sign * (laneWidth / 2 + barrierThickness + rng:NextNumber(30, 60)), 26, rng:NextNumber(-chunkLength / 2, chunkLength / 2)), model)
		end
	end

	local fieldHalf = GameConstants.PLAYABLE_HALF_WIDTH - 4
	local obstacleTotal = math.max(1, math.floor(obstacleCount * GameConstants.FIELD_OBSTACLE_SCALE + 0.5))

	if effective.edgeProps == "farm" or effective.edgeProps == "corn" then
		local isCorn = effective.edgeProps == "corn"
		for _ = 1, if isCorn then 4 else obstacleTotal do
			local x = rng:NextNumber(-fieldHalf, fieldHalf)
			local z = rng:NextNumber(-chunkLength / 2 + 8, chunkLength / 2 - 8)
			if isCorn then
				buildCornWall(Vector3.new(x, 0.5, z), rng, model)
			else
				buildDryGrass(Vector3.new(x, 0.5, z), rng, model)
			end
		end
		if not isCorn then
			for _ = 1, 3 do
				local x = rng:NextNumber(-fieldHalf, fieldHalf)
				local z = rng:NextNumber(-chunkLength / 2 + 16, chunkLength / 2 - 16)
				buildTree(Vector3.new(x, 0.5, z), rng, model)
			end
		end
		buildWireRun(
			effective.edgeProps,
			1,
			-chunkLength / 2 + 10,
			chunkLength / 2 - 10,
			laneWidth / 2 + barrierThickness + 16,
			rng,
			model
		)
	elseif isField then
		for _ = 1, obstacleTotal + 6 do
			local x = rng:NextNumber(-fieldHalf, fieldHalf)
			local z = rng:NextNumber(-chunkLength / 2 + 8, chunkLength / 2 - 8)
			buildTree(Vector3.new(x, 0.5, z), rng, model)
		end
		for _ = 1, 6 do
			local x = rng:NextNumber(-fieldHalf, fieldHalf)
			local z = rng:NextNumber(-chunkLength / 2 + 16, chunkLength / 2 - 16)
			buildCanopyCover(Vector3.new(x, 0.5, z), rng, model)
		end
		for _ = 1, 14 do
			local x = rng:NextNumber(-fieldHalf, fieldHalf)
			local z = rng:NextNumber(-chunkLength / 2 + 8, chunkLength / 2 - 8)
			buildUndergrowth(Vector3.new(x, 0.5, z), rng, model)
		end
	elseif effective.edgeProps == "buildings" and rng:NextNumber() < GameConstants.FIELD_CLUSTER_CHANCE then
		local clusterX = rng:NextNumber(-fieldHalf * 0.7, fieldHalf * 0.7)
		local clusterZ = rng:NextNumber(-chunkLength / 2 + 30, chunkLength / 2 - 30)
		local clusterSign = if clusterX < 0 then -1 else 1
		buildBuilding(clusterSign, Vector3.new(clusterX, 0.5, clusterZ), rng, model)
	end

	local laneCount = 3
	local laneStep = fieldHalf * 2 / laneCount
	local placed = 0
	for lane = 1, laneCount do
		if placed >= obstacleTotal then
			break
		end
		if rng:NextNumber() < 0.75 then
			local laneCenter = -fieldHalf + laneStep * (lane - 0.5)
			local x = math.clamp(laneCenter + rng:NextNumber(-laneStep * 0.3, laneStep * 0.3), -fieldHalf, fieldHalf)
			local z = rng:NextNumber(-chunkLength / 2 + 14, chunkLength / 2 - 14)
			buildObstacle(effective.edgeProps, Vector3.new(x, 0.5, z), rng, model)
			placed += 1
		end
	end

	model.PrimaryPart = floor
	return model
end

return ChunkFactory
