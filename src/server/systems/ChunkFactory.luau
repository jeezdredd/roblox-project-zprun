--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DressingConfig = require(ReplicatedStorage.Shared.config.DressingConfig)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local TexturesConfig = require(ReplicatedStorage.Shared.config.TexturesConfig)
local MaterialUtil = require(ReplicatedStorage.Shared.util.MaterialUtil)
local WorldFlanks = require(script.Parent.WorldFlanks)
local WorldMeshes = require(script.Parent.WorldMeshes)
local ChunkOccupancy = require(script.Parent.ChunkOccupancy)
local ChunkBudgetCounter = require(script.Parent.Parent.world.ChunkBudgetCounter)
local WorldDecals = require(script.Parent.Parent.world.WorldDecals)
local WorldDressing = require(script.Parent.Parent.world.WorldDressing)

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
	-- tint with the part colour, otherwise the texture's own grey wins and every
	-- biome floor reads the same
	texture.Color3 = part.Color:Lerp(Color3.new(1, 1, 1), 0.35)
	texture.Parent = part
end

-- A mesh tree with an invisible trunk collider, so only the trunk blocks the runner.
local function buildMeshTree(group: string, position: Vector3, height: number, rng: Random, parent: Instance, collide: boolean): boolean
	local base = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local mesh = WorldMeshes.placeFrom(group, rng, base, height, parent, { shadow = true, sink = 0.4 })
	if not mesh then
		return false
	end
	if collide then
		local collider = Instance.new("Part")
		collider.Name = "TrunkCollider"
		collider.Shape = Enum.PartType.Cylinder
		collider.Size = Vector3.new(height * 0.5, 2.6, 2.6)
		collider.CFrame = CFrame.new(position.X, position.Y + height * 0.25, position.Z) * CFrame.Angles(0, 0, math.rad(90))
		collider.Anchored = true
		collider.Transparency = 1
		collider.CastShadow = false
		collider.CanTouch = false
		collider.Parent = parent
	end
	return true
end

local function buildTree(position: Vector3, rng: Random, parent: Instance)
	if buildMeshTree("tree_any", position, rng:NextNumber(18, 26), rng, parent, true) then
		return
	end
	local trunkHeight = rng:NextNumber(10, 16)
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

	local canopyRadius = rng:NextNumber(6, 8.5)
	local green = Color3.fromRGB(rng:NextInteger(44, 62), rng:NextInteger(84, 110), rng:NextInteger(40, 54))
	for i = 1, 3 do
		local ball = Instance.new("Part")
		ball.Name = "Canopy"
		ball.Shape = Enum.PartType.Ball
		local radius = canopyRadius * (if i == 1 then 1 else rng:NextNumber(0.6, 0.8))
		ball.Size = Vector3.new(radius * 2, radius * 1.5, radius * 2)
		ball.CFrame = CFrame.new(
			position.X + rng:NextNumber(-canopyRadius * 0.45, canopyRadius * 0.45),
			position.Y + trunkHeight + radius * 0.3 + (i - 1) * 2.2,
			position.Z + rng:NextNumber(-canopyRadius * 0.45, canopyRadius * 0.45)
		)
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.Color = green:Lerp(Color3.new(), rng:NextNumber(0, 0.15))
		ball.Material = Enum.Material.Grass
		ball.Parent = parent
	end
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
				position.Y + rng:NextNumber(0.2, 0.5),
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

local function buildMeshCar(group: string, position: Vector3, yaw: number, length: number, rng: Random, parent: Instance): MeshPart?
	local name = WorldMeshes.pick(group, rng)
	if not name then
		return nil
	end
	-- the meshes face either way along z; flip half of them so rows do not repeat
	local flip = if rng:NextNumber() < 0.5 then math.pi else 0
	return WorldMeshes.placeByLength(name, CFrame.new(position) * CFrame.Angles(0, yaw + flip, 0), length, parent, { collide = true, sink = 0.2 })
end

local function buildCar(position: Vector3, yaw: number, rng: Random, parent: Instance)
	if buildMeshCar("car", position, yaw, 12.4, rng, parent) then
		return
	end
	local color = CAR_COLORS[rng:NextInteger(1, #CAR_COLORS)]
	local base = CFrame.new(position.X, position.Y + 2.1, position.Z) * CFrame.Angles(0, yaw, 0)
	createPart("CarBody", Vector3.new(6.4, 2.3, 12.4), base, color, Enum.Material.Metal, parent)
	local cabin = createPart("CarCabin", Vector3.new(5.6, 1.9, 5.6), base * CFrame.new(0, 2.05, 0.6), Color3.fromRGB(35, 40, 50), Enum.Material.Glass, parent)
	cabin.Transparency = 0.2
	buildWheels(base, 12.4, parent)
end

local function buildBus(position: Vector3, yaw: number, rng: Random, parent: Instance)
	local name = if WorldMeshes.isLoaded("car_van") then "car_van" else nil
	if name and WorldMeshes.placeByLength(name, CFrame.new(position) * CFrame.Angles(0, yaw, 0), 15, parent, { collide = true, sink = 0.2 }) then
		return
	end
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
	local name = if WorldMeshes.isLoaded("car_pickup") then "car_pickup" else nil
	if name and WorldMeshes.placeByLength(name, CFrame.new(position) * CFrame.Angles(0, yaw, 0), 15, parent, { collide = true, sink = 0.2 }) then
		return
	end
	local base = CFrame.new(position.X, position.Y + 3.3, position.Z) * CFrame.Angles(0, yaw, 0)
	createPart("TruckCab", Vector3.new(7.5, 5.4, 6.75), base * CFrame.new(0, 0, 10.5), Color3.fromRGB(90, 110, 130), Enum.Material.Metal, parent)
	createPart("TruckTrailer", Vector3.new(8.1, 7.5, 18), base * CFrame.new(0, 1.05, -3.75), Color3.fromRGB(150, 150, 154), Enum.Material.Metal, parent)
	buildWheels(base * CFrame.new(0, -1.35, -1.5), 24, parent)
	local _ = rng
end

local function buildCrash(position: Vector3, rng: Random, parent: Instance)
	local wreckAt = position + Vector3.new(-4.2, 0, -5.5)
	local wreckYaw = rng:NextNumber(0.3, 0.7)
	if not buildMeshCar("car_burned", wreckAt, wreckYaw, 12, rng, parent) and not buildMeshCar("car_wreck", wreckAt, wreckYaw, 12, rng, parent) then
		buildCar(wreckAt, wreckYaw, rng, parent)
	end
	buildCar(position + Vector3.new(4.2, 0, 5.5), rng:NextNumber(-0.7, -0.3), rng, parent)
	for _ = 1, 3 do
		local height = rng:NextNumber(0.4, 0.9)
		createPart(
			"Debris",
			Vector3.new(rng:NextNumber(0.8, 1.8), height, rng:NextNumber(0.8, 1.8)),
			CFrame.new(position.X + rng:NextNumber(-5, 5), position.Y + height / 2 + 0.45, position.Z + rng:NextNumber(-5, 5))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			Color3.fromRGB(60, 60, 64),
			Enum.Material.CorrodedMetal,
			parent
		)
	end
end

local function buildDivider(position: Vector3, rng: Random, parent: Instance)
	local segments = rng:NextInteger(2, 3)
	local name = WorldMeshes.pick("barrier", rng)
	local natural = name and WorldMeshes.naturalSize(name)
	if name and natural then
		-- the barrier's long side runs along the road, segments end to end
		local yaw = if natural.Z >= natural.X then 0 else math.pi / 2
		local length = math.max(natural.X, natural.Z) + 0.4
		for i = 0, segments - 1 do
			local at = CFrame.new(position.X, position.Y, position.Z + (i - (segments - 1) / 2) * length) * CFrame.Angles(0, yaw, 0)
			WorldMeshes.placeNatural(name, at, parent, { collide = true, sink = 0.15 })
		end
		return
	end
	for i = 0, segments - 1 do
		local divider = createPart(
			"Divider",
			Vector3.new(2.2, 3, 10),
			CFrame.new(position.X, position.Y + 2, position.Z + i * 11 - (segments - 1) * 5.5),
			Color3.fromRGB(168, 168, 170),
			Enum.Material.Concrete,
			parent
		)
		MaterialUtil.apply(divider, "TFZ_ConcreteDirty")
	end
end

-- Hedgehogs and a sandbag wall across a lane: the checkpoint blocker of the City and
-- the Wasteland. Falls back to the divider when the props are not loaded.
local function buildBlock(position: Vector3, rng: Random, parent: Instance)
	local hedgehog = WorldMeshes.pick("hedgehog", rng)
	local hedgehogSize = hedgehog and WorldMeshes.naturalSize(hedgehog)
	if not hedgehog or not hedgehogSize then
		buildDivider(position, rng, parent)
		return
	end
	local sandbags = WorldMeshes.pick("sandbags", rng)
	local sandbagSize = sandbags and WorldMeshes.naturalSize(sandbags)
	local step = math.max(hedgehogSize.X, hedgehogSize.Z) + 1
	for i = -1, 1 do
		if i == 0 and sandbags and sandbagSize then
			-- the wall's long side runs across the road
			local yaw = if sandbagSize.X >= sandbagSize.Z then 0 else math.pi / 2
			WorldMeshes.placeNatural(sandbags, CFrame.new(position) * CFrame.Angles(0, yaw, 0), parent, { collide = true, sink = 0.15 })
		else
			local at = CFrame.new(position.X + i * step, position.Y, position.Z + rng:NextNumber(-1, 1)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			WorldMeshes.placeNatural(hedgehog, at, parent, { collide = true, sink = 0.15 })
		end
	end
end

local function buildLog(position: Vector3, rng: Random, parent: Instance)
	local length = rng:NextNumber(12, 20)
	local log = Instance.new("Part")
	log.Name = "FallenLog"
	log.Shape = Enum.PartType.Cylinder
	log.Size = Vector3.new(length, 3.2, 3.2)
	log.CFrame = CFrame.new(position.X, position.Y + 1.45, position.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	log.Anchored = true
	log.Color = Color3.fromRGB(86, 62, 42)
	log.Material = Enum.Material.Wood
	log.Parent = parent
end

local function buildBoulder(position: Vector3, rng: Random, parent: Instance)
	local size = rng:NextNumber(4.5, 9)
	local base = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local stretch = Vector3.new(rng:NextNumber(0.9, 1.35), 1, rng:NextNumber(0.9, 1.35))
	if WorldMeshes.placeFrom("boulder", rng, base, size * 0.75, parent, { collide = true, stretch = stretch, sink = size * 0.08 }) then
		return
	end
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
	local name = WorldMeshes.pick("rubble", rng)
	if name and WorldMeshes.placeNatural(name, CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), parent, { collide = true, sink = 0.3 }, rng:NextNumber(0.9, 1.3)) then
		return
	end
	for _ = 1, rng:NextInteger(3, 4) do
		createPart(
			"Rubble",
			Vector3.new(rng:NextNumber(2, 5), rng:NextNumber(1, 2.4), rng:NextNumber(2, 4)),
			CFrame.new(position.X + rng:NextNumber(-3, 3), position.Y + rng:NextNumber(0.3, 0.8), position.Z + rng:NextNumber(-3, 3))
				* CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, math.pi), rng:NextNumber(-0.2, 0.2)),
			Color3.fromRGB(126, 118, 106),
			Enum.Material.Concrete,
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

-- A tussock of dry grass: a low mound with thin blades leaning outwards.
local function buildDryGrass(position: Vector3, rng: Random, parent: Instance)
	if WorldMeshes.placeFrom("grass_dry", rng, CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng:NextNumber(3, 4.5), parent, { shadow = false, sink = 0.2, stretch = Vector3.new(rng:NextNumber(1, 1.6), 1, rng:NextNumber(1, 1.6)) }) then
		return
	end
	local straw = Color3.fromRGB(rng:NextInteger(150, 180), rng:NextInteger(128, 150), rng:NextInteger(66, 86))
	local radius = rng:NextNumber(1.6, 2.6)
	local mound = createPart("GrassMound", Vector3.new(radius * 2, rng:NextNumber(1.4, 2.2), radius * 2), CFrame.new(position + Vector3.new(0, 0.3, 0)), straw:Lerp(Color3.new(), 0.25), Enum.Material.Grass, parent)
	mound.Shape = Enum.PartType.Ball
	mound.CanCollide = false
	mound.CanQuery = false
	mound.CastShadow = false
	local blades = rng:NextInteger(6, 9)
	for i = 1, blades do
		local angle = (i / blades) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local height = rng:NextNumber(2.5, 4.5)
		local out = rng:NextNumber(0.3, radius * 0.8)
		local blade = createPart(
			"DryGrass",
			Vector3.new(0.18, height, 0.5),
			CFrame.new(position + Vector3.new(math.cos(angle) * out, height / 2, math.sin(angle) * out))
				* CFrame.Angles(0, -angle, math.rad(rng:NextNumber(12, 28))),
			straw:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.12)),
			Enum.Material.Grass,
			parent
		)
		blade.CanCollide = false
		blade.CanQuery = false
		blade.CastShadow = false
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

	if WorldMeshes.placeFrom("bush", rng, CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng:NextNumber(1.8, 3), parent, { shadow = false, sink = 0.25 }) then
		return
	end
	for _ = 1, rng:NextInteger(2, 4) do
		local fern = createPart(
			"Fern",
			Vector3.new(rng:NextNumber(1.8, 3.6), 0.12, rng:NextNumber(1.8, 3.3)),
			CFrame.new(position + Vector3.new(rng:NextNumber(-2.2, 2.2), rng:NextNumber(0.55, 0.8), rng:NextNumber(-2.2, 2.2)))
				* CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-25, 25))),
			Color3.fromRGB(rng:NextInteger(36, 58), rng:NextInteger(72, 98), rng:NextInteger(34, 52)),
			Enum.Material.Grass,
			parent
		)
		noShadow(fern).CanCollide = false
		fern.CanQuery = false
	end
end

local CORN_GREEN = Color3.fromRGB(96, 118, 52)
local CORN_TASSEL = Color3.fromRGB(196, 176, 102)

-- A stand of corn: a few rows across the corridor with a pale tassel line on top and
-- stalk lines on the face towards the runner. Blocks sight, not movement.
local function buildMeshCorn(position: Vector3, rng: Random, parent: Instance): boolean
	local name = WorldMeshes.pick("corn", rng)
	local native = name and WorldMeshes.nativeSize(name)
	if not name or not native then
		return false
	end
	local length = rng:NextNumber(14, 22)
	local base = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(-0.12, 0.12), 0)
	local rows = rng:NextInteger(2, 3)
	for r = 1, rows do
		local height = rng:NextNumber(10, 12.5)
		local scale = height / native.Y
		local stretch = Vector3.new(length * rng:NextNumber(0.8, 1) / (native.X * scale), 1, 0.7)
		local z = (r - (rows + 1) / 2) * 4.5
		local flip = if rng:NextNumber() < 0.5 then math.pi else 0
		WorldMeshes.place(name, base * CFrame.new(rng:NextNumber(-2, 2), 0, z) * CFrame.Angles(0, flip, 0), height, parent, { stretch = stretch, shadow = r == rows, sink = 0.3 })
	end
	return true
end

local function buildCornWall(position: Vector3, rng: Random, parent: Instance)
	if buildMeshCorn(position, rng, parent) then
		return
	end
	local length = rng:NextNumber(12, 20)
	local rows = rng:NextInteger(2, 4)
	local yaw = CFrame.Angles(0, rng:NextNumber(-0.12, 0.12), 0)
	local base = CFrame.new(position) * yaw
	for r = 1, rows do
		local height = rng:NextNumber(10, 13)
		local z = (r - (rows + 1) / 2) * 3.2
		local rowLength = length * rng:NextNumber(0.75, 1)
		local shift = rng:NextNumber(-2, 2)
		local color = CORN_GREEN:Lerp(Color3.new(), rng:NextNumber(0, 0.18))
		local row = createPart("CornRow", Vector3.new(rowLength, height, 2.4), base * CFrame.new(shift, height / 2, z), color, Enum.Material.LeafyGrass, parent)
		row.CanCollide = false
		row.CanQuery = false
		if r == rows then
			-- the face the runner sees: stalk lines so the block reads as corn, not hedge
			local step = 1.4
			local x = -rowLength / 2 + rng:NextNumber(0.3, 1)
			while x < rowLength / 2 - 0.3 do
				local h = height * rng:NextNumber(0.85, 1.05)
				local stalk = createPart("CornFace", Vector3.new(0.35, h, 0.3), base * CFrame.new(shift + x, h / 2, z + 1.3) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-4, 4))), color:Lerp(CORN_TASSEL, rng:NextNumber(0.15, 0.35)), Enum.Material.Grass, parent)
				stalk.CanCollide = false
				stalk.CanQuery = false
				stalk.CastShadow = false
				x += step * rng:NextNumber(0.8, 1.2)
			end
		end
		local tassel = createPart("CornTassel", Vector3.new(rowLength - 1, 0.8, 1.6), base * CFrame.new(shift, height + 0.3, z), CORN_TASSEL:Lerp(Color3.new(), rng:NextNumber(0, 0.15)), Enum.Material.Grass, parent)
		tassel.CanCollide = false
		tassel.CanQuery = false
		tassel.CastShadow = false
	end
	for _ = 1, rng:NextInteger(3, 5) do
		local stalk = createPart(
			"CornStalk",
			Vector3.new(0.3, rng:NextNumber(9, 12), 0.3),
			base * CFrame.new(rng:NextNumber(-length / 2 - 0.8, length / 2 + 0.8), 5, rng:NextNumber(-rows * 1.6, rows * 1.6))
				* CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), 0, math.rad(rng:NextNumber(-8, 8))),
			CORN_GREEN,
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
		elseif roll < 0.78 then
			buildCrash(position, rng, parent)
		elseif roll < 0.9 then
			buildBlock(position, rng, parent)
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
		if roll < 0.35 then
			buildRubblePile(position, rng, parent)
		elseif roll < 0.5 then
			buildBlock(position, rng, parent)
		elseif roll < 0.72 then
			buildBoulder(position, rng, parent)
		else
			buildCrash(position, rng, parent)
		end
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
	MaterialUtil.apply(post, "TFZ_PaintPeelingMetal")
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
	local step = rng:NextNumber(15, 18)
	local z = position.Z - (count - 1) * step / 2
	for _ = 1, count do
		local x = position.X + rng:NextNumber(-3, 3)
		if ChunkOccupancy.claim(x, z, 6.5) then
			buildCar(Vector3.new(x, position.Y, z), rng:NextNumber(-0.15, 0.15), rng, parent)
		end
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

local function addPoliceLights(at: CFrame, spacing: number, rng: Random, parent: Instance)
	if rng:NextNumber() >= 0.6 then
		return
	end
	for index, color in { Color3.fromRGB(255, 60, 60), Color3.fromRGB(70, 110, 255) } do
		local lamp = noShadow(createPart("LightBarLamp", Vector3.new(1.4, 0.4, 0.8), at * CFrame.new((index - 1.5) * spacing, 0, 0), color, Enum.Material.Neon, parent))
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

local function buildPoliceCar(position: Vector3, yaw: number, rng: Random, parent: Instance)
	local mesh = buildMeshCar("car_police", position, yaw, 12.4, rng, parent)
	if mesh then
		addPoliceLights(mesh.CFrame * CFrame.new(0, mesh.Size.Y / 2 - 0.25, mesh.Size.Z * 0.02), 1.5, rng, parent)
		return
	end
	local base = CFrame.new(position.X, position.Y + 2.1, position.Z) * CFrame.Angles(0, yaw, 0)
	createPart("CarBody", Vector3.new(6.4, 2.3, 12.4), base, POLICE_WHITE, Enum.Material.Metal, parent)
	noShadow(createPart("CarStripe", Vector3.new(6.5, 0.7, 12.5), base * CFrame.new(0, -0.5, 0), POLICE_BLUE, Enum.Material.Metal, parent))
	local cabin = createPart("CarCabin", Vector3.new(5.6, 1.9, 5.6), base * CFrame.new(0, 2.05, 0.6), Color3.fromRGB(35, 40, 50), Enum.Material.Glass, parent)
	cabin.Transparency = 0.2
	buildWheels(base, 12.4, parent)
	local bar = noShadow(createPart("LightBar", Vector3.new(4.2, 0.4, 1), base * CFrame.new(0, 3.2, 0.6), Color3.fromRGB(40, 40, 44), Enum.Material.SmoothPlastic, parent))
	bar.CanCollide = false
	addPoliceLights(base * CFrame.new(0, 3.2, 0.6), 2, rng, parent)
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
		local pole = noShadow(createPart("FencePole", Vector3.new(0.5, height + 0.6, 0.5), CFrame.new(x, 0.5 + (height + 0.6) / 2, z), Color3.fromRGB(80, 82, 84), Enum.Material.Metal, parent))
		MaterialUtil.apply(pole, "TFZ_PaintPeelingMetal")
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
		local divider = createPart("Divider", Vector3.new(2.2, 3, 10), CFrame.new(x, 2.5, z + 5), Color3.fromRGB(168, 168, 170), Enum.Material.Concrete, parent)
		MaterialUtil.apply(divider, "TFZ_ConcreteDirty")
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

-- Free run of the edge strip after each element, so the dressing clusters have room.
local EDGE_GAP_MIN = 6
local EDGE_GAP_MAX = 18

-- `otherKind` and `alpha` mix two styles along the edge in a transition: each element
-- is the other style with probability alpha.
local function buildCorridorEdge(baseKind: string, sign: number, rng: Random, parent: Instance, otherKind: string?, alpha: number?)
	if baseKind == "corn" and (otherKind == nil or otherKind == "corn") then
		-- the flank crop rows start right at the corridor edge
		return
	end
	local edgeX = corridorEdgeX(sign)
	local z = -chunkLength / 2 + rng:NextNumber(0, 4)
	while z < chunkLength / 2 - 4 do
		local kind = if otherKind and rng:NextNumber() < (alpha or 0) then otherKind else baseKind
		local roll = rng:NextNumber()
		local remaining = chunkLength / 2 - z
		-- the z the element takes, its full extent plus its own gap
		local used: number
		if kind == "corn" then
			-- the crop rows of a cornfield flank reach the edge on their own
			used = rng:NextNumber(8, 14)
		elseif kind == "buildings" then
			-- the street wall lives in WorldFlanks; this row is the kerb-side clutter in
			-- front of it
			if roll < 0.12 then
				local count = 2
				buildCarRow(sign, z, count, rng, parent)
				used = count * 13.5 + 2
			elseif roll < 0.52 then
				local length = math.min(rng:NextNumber(12, 24), remaining)
				buildFenceRun(sign, z, length, rng, parent)
				used = length + 1
			elseif roll < 0.66 then
				local count = rng:NextInteger(2, 3)
				buildCarRow(sign, z, count, rng, parent)
				used = count * 13.5 + 2
			elseif roll < 0.74 then
				buildPoliceCar(Vector3.new(edgeX + sign * 4.6, 0.5, z + 7), rng:NextNumber(-0.35, 0.35), rng, parent)
				used = 15
			elseif roll < 0.86 then
				buildRubblePile(Vector3.new(edgeX + sign * 4, 0.5, z + 5), rng, parent)
				used = 10
			else
				local length = math.min(rng:NextNumber(12, 21), remaining)
				buildJerseyRow(sign, z, length, parent)
				used = length + 1
			end
		elseif kind == "trees" then
			buildTree(Vector3.new(edgeX + sign * rng:NextNumber(1, 6), 0.5, z), rng, parent)
			if rng:NextNumber() < 0.25 then
				buildBoulder(Vector3.new(edgeX + sign * rng:NextNumber(-2, 2), 0.5, z + rng:NextNumber(2, 5)), rng, parent)
			end
			used = rng:NextNumber(8, 12)
		elseif kind == "farm" then
			local length = math.min(rng:NextNumber(24, 48), remaining)
			buildRailFence(sign, z, length, rng, parent)
			if rng:NextNumber() < 0.5 then
				buildTree(Vector3.new(edgeX + sign * rng:NextNumber(4, 10), 0.5, z + rng:NextNumber(4, length - 4)), rng, parent)
			end
			used = length + rng:NextNumber(2, 6)
		else
			if roll < 0.4 then
				buildRuin(Vector3.new(edgeX + sign * 3, 0.5, z + 8), 0, rng, parent)
				used = 17
			elseif roll < 0.65 then
				buildRubblePile(Vector3.new(edgeX + sign * 4, 0.5, z + 5), rng, parent)
				used = 12
			elseif roll < 0.82 then
				buildCrash(Vector3.new(edgeX + sign * 6, 0.5, z + 13), rng, parent)
				used = 28
			else
				buildBoulder(Vector3.new(edgeX + sign * 4, 0.5, z + 6), rng, parent)
				used = 14
			end
		end
		-- the element's footprint is recorded so lane debris, flank props and the
		-- dressing clusters keep out of it; the gap after it is theirs
		ChunkOccupancy.reserveBox(edgeX - sign * 1, z, edgeX + sign * 8, z + used)
		z += used + rng:NextNumber(EDGE_GAP_MIN, EDGE_GAP_MAX)
	end
end

-- In a transition, irregular patches of the other location's ground on a floor or an
-- apron: as many as its share of the blend asks for (none at either end, most at the
-- middle), so the ground reads as a mix instead of a seam.
local PATCH_MAX = 12
local function addGroundPatches(surface: BasePart, other: LocationsConfig.LocationConfig, isFloor: boolean, share: number, rng: Random, model: Model)
	local count = math.floor(PATCH_MAX * math.clamp(share, 0, 0.5) * 2 + 0.5)
	if count <= 0 then
		return
	end
	local half = surface.Size * 0.5
	local otherMaterials = DressingConfig.materials[other.id]
	for _ = 1, count do
		local size = Vector3.new(rng:NextNumber(10, math.min(28, surface.Size.X)), 0.05, rng:NextNumber(8, 22))
		local x = rng:NextNumber(-half.X + size.X / 2, half.X - size.X / 2)
		local z = rng:NextNumber(-half.Z + size.Z / 2, half.Z - size.Z / 2)
		local patch = createPart(
			"Patch",
			size,
			surface.CFrame * CFrame.new(x, half.Y + 0.025, z) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
			if isFloor then other.floorColor else other.apronColor,
			if isFloor then other.floorMaterial else other.apronMaterial,
			model
		)
		patch.CanCollide = false
		patch.CanQuery = false
		patch.CastShadow = false
		local variant = if otherMaterials then (if isFloor then otherMaterials.floor else otherMaterials.apron) else nil
		if not (variant and MaterialUtil.apply(patch, variant)) then
			applyTexture(patch, Enum.NormalId.Top, if isFloor then other.floorTextureId else other.apronTextureId, 8)
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
	-- the biome's material variants (docs/world/environment.md, section 5.2); the flat
	-- texture tiles stay as the fallback when a variant has not shipped
	local materials = DressingConfig.materials[effective.id]
	if not (materials and MaterialUtil.apply(floor, materials.floor)) then
		applyTexture(floor, Enum.NormalId.Top, floorTextureId, 8)
	end
	-- the location the base ground is not, and its share of the blend
	local mixWith = if nextLocation then (if far then location else nextLocation) else nil
	local mixShare = if far then 1 - alpha else alpha
	if mixWith then
		addGroundPatches(floor, mixWith, true, mixShare, rng, model)
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
		if not (materials and MaterialUtil.apply(apron, materials.apron)) then
			applyTexture(apron, Enum.NormalId.Top, apronTextureId, 7)
		end
		if mixWith then
			addGroundPatches(apron, mixWith, false, mixShare, rng, model)
		end
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

	ChunkOccupancy.reset()

	for _, sign in { -1, 1 } do
		-- in a transition the edge mixes both styles, element by element, by the blend
		if nextLocation then
			buildCorridorEdge(location.edgeProps, sign, rng, model, nextLocation.edgeProps, alpha)
		else
			buildCorridorEdge(effective.edgeProps, sign, rng, model)
		end

		if effective.edgeProps == "buildings" then
			local debrisZ = -chunkLength / 2 + rng:NextNumber(8, 22)
			while debrisZ < chunkLength / 2 - 8 do
				local x = sign * (GameConstants.PLAYABLE_HALF_WIDTH - rng:NextNumber(3, 14))
				local roll = rng:NextNumber()
				local position = Vector3.new(x, 0.5, debrisZ)
				if not ChunkOccupancy.claim(x, debrisZ, if roll >= 0.86 then 9 else 6.5) then
					roll = 2
				end
				if roll < 0.4 then
					buildCar(position, rng:NextNumber(-1.2, 1.2), rng, model)
				elseif roll < 0.66 then
					buildRubblePile(position, rng, model)
				elseif roll < 0.86 then
					buildDivider(position, rng, model)
				elseif roll <= 1 then
					buildCrash(position, rng, model)
				end
				debrisZ += rng:NextNumber(28, 52)
			end
		end
	end

	if nextLocation then
		WorldFlanks.build(location.edgeProps, rng, model, nextLocation.edgeProps, alpha)
	else
		WorldFlanks.build(effective.edgeProps, rng, model)
	end

	if effective.edgeProps == "buildings" then
		local bandHalf = GameConstants.PLAYABLE_HALF_WIDTH
		for _, sign in { -1, 1 } do
			local lampX = sign * (bandHalf + 2.5)
			local lampZ = -chunkLength / 2 + rng:NextNumber(4, 14)
			while lampZ < chunkLength / 2 - 6 do
				ChunkOccupancy.reserve(lampX, lampZ, 1.5)
				buildStreetLamp(sign, Vector3.new(lampX, 0.5, lampZ), rng, model)
				lampZ += rng:NextNumber(34, 44)
			end
		end
		for _ = 1, rng:NextInteger(1, 2) do
			local sign = if rng:NextNumber() < 0.5 then -1 else 1
			local bx, bz = ChunkOccupancy.findSpot(2, 4, function()
				return sign * rng:NextNumber(bandHalf - 24, bandHalf - 2), rng:NextNumber(-chunkLength / 2 + 8, chunkLength / 2 - 8)
			end)
			if bx and bz then
				buildBurningBarrel(Vector3.new(bx, 0.5, bz), rng, model)
			end
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
			local x, z = ChunkOccupancy.findSpot(if isCorn then 11 else 2, 4, function()
				return rng:NextNumber(-fieldHalf, fieldHalf), rng:NextNumber(-chunkLength / 2 + 8, chunkLength / 2 - 8)
			end)
			if x and z then
				if isCorn then
					buildCornWall(Vector3.new(x, 0.5, z), rng, model)
				else
					buildDryGrass(Vector3.new(x, 0.5, z), rng, model)
				end
			end
		end
		if not isCorn then
			for _ = 1, 3 do
				local x, z = ChunkOccupancy.findSpot(3, 4, function()
					return rng:NextNumber(-fieldHalf, fieldHalf), rng:NextNumber(-chunkLength / 2 + 16, chunkLength / 2 - 16)
				end)
				if x and z then
					buildTree(Vector3.new(x, 0.5, z), rng, model)
				end
			end
		end
		buildWireRun(
			effective.edgeProps,
			1,
			-chunkLength / 2 + 10,
			chunkLength / 2 - 10,
			-- between the last crop row and the windbreak trees of the farm flank
			GameConstants.PLAYABLE_HALF_WIDTH + 4 + 93,
			rng,
			model
		)
	elseif isField then
		for _ = 1, obstacleTotal + 6 do
			local x, z = ChunkOccupancy.findSpot(3.5, 4, function()
				return rng:NextNumber(-fieldHalf, fieldHalf), rng:NextNumber(-chunkLength / 2 + 8, chunkLength / 2 - 8)
			end)
			if x and z then
				buildTree(Vector3.new(x, 0.5, z), rng, model)
			end
		end
		for _ = 1, 14 do
			local x, z = ChunkOccupancy.findSpot(1.8, 3, function()
				return rng:NextNumber(-fieldHalf, fieldHalf), rng:NextNumber(-chunkLength / 2 + 8, chunkLength / 2 - 8)
			end)
			if x and z then
				buildUndergrowth(Vector3.new(x, 0.5, z), rng, model)
			end
		end
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
			local x, z = ChunkOccupancy.findSpot(8, 5, function()
				return math.clamp(laneCenter + rng:NextNumber(-laneStep * 0.3, laneStep * 0.3), -fieldHalf, fieldHalf),
					rng:NextNumber(-chunkLength / 2 + 14, chunkLength / 2 - 14)
			end)
			if x and z then
				buildObstacle(effective.edgeProps, Vector3.new(x, 0.5, z), rng, model)
				placed += 1
			end
		end
	end

	-- the props and marks go last, into whatever ground the obstacles and flanks left
	-- in a transition both locations dress the chunk, each at its share of the density
	if nextLocation then
		WorldDressing.dress(location.id, rng, chunkLength / 2, model, 1 - alpha)
		WorldDressing.dress(nextLocation.id, rng, chunkLength / 2, model, alpha)
	else
		WorldDressing.dress(effective.id, rng, chunkLength / 2, model)
	end
	WorldDecals.dress(effective.id, rng, floor, GameConstants.PLAYABLE_HALF_WIDTH, chunkLength / 2, model)

	-- the footprints stay with the model (pooled chunks keep their props), for what is
	-- placed after the build: WeaponPickups tests its spots against them
	ChunkOccupancy.remember(model)
	model.PrimaryPart = floor
	ChunkBudgetCounter.report(model, effective.id)
	return model
end

return ChunkFactory
