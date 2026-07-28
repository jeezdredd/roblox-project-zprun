--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local TexturesConfig = require(ReplicatedStorage.Shared.config.TexturesConfig)
local TextureUtil = require(ReplicatedStorage.Shared.util.TextureUtil)
local MaterialUtil = require(ReplicatedStorage.Shared.util.MaterialUtil)

local DesertBase = {}

local center = HangarConfig.HUB_CENTER
local random = Random.new(20260729)

local SAND_COLOR = Color3.fromRGB(196, 176, 138)
local ASPHALT_COLOR = Color3.fromRGB(72, 72, 76)
local POLE_COLOR = Color3.fromRGB(74, 60, 46)
local CONCRETE_COLOR = Color3.fromRGB(150, 148, 140)
local SANDBAG_COLOR = Color3.fromRGB(148, 134, 100)

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
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

local function decor(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
end

local function buildGround(parent: Instance)
	local ground = makePart(
		"DesertGround",
		Vector3.new(HangarConfig.DESERT_SIZE, 2, HangarConfig.DESERT_SIZE),
		CFrame.new(center.X, -1.05, center.Z),
		SAND_COLOR,
		Enum.Material.Sand,
		parent
	)
	if not MaterialUtil.apply(ground, "TFZ_Sand") then
		TextureUtil.applyFace(ground, Enum.NormalId.Top, TexturesConfig.SAND, 8)
	end

	for _ = 1, 24 do
		local angle = random:NextNumber(0, math.pi * 2)
		local dist = random:NextNumber(260, HangarConfig.DESERT_SIZE / 2 - 100)
		local x = center.X + math.cos(angle) * dist
		local z = center.Z + math.sin(angle) * dist
		if z < center.Z + HangarConfig.CITY_NEAR_Z + 80 then
			continue
		end
		local size = random:NextNumber(3, 12)
		local rock = Instance.new("Part")
		rock.Name = "DesertRock"
		rock.Shape = Enum.PartType.Ball
		rock.Size = Vector3.new(size, size * random:NextNumber(0.5, 0.8), size)
		rock.CFrame = CFrame.new(x, size * 0.2, z) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0)
		rock.Anchored = true
		rock.Color = Color3.fromRGB(random:NextInteger(120, 150), random:NextInteger(108, 132), random:NextInteger(88, 108))
		rock.Material = Enum.Material.Slate
		rock.Parent = parent
	end

	local dustAnchor = makePart("DustAnchor", Vector3.new(1, 1, 1), CFrame.new(center.X, 1.5, center.Z + 60), SAND_COLOR, Enum.Material.SmoothPlastic, parent)
	dustAnchor.Transparency = 1
	decor(dustAnchor)
	local attachment = Instance.new("Attachment")
	attachment.Parent = dustAnchor
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "SandDrift"
	dust.Color = ColorSequence.new(SAND_COLOR)
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Size = NumberSequence.new(6, 14)
	dust.Lifetime = NumberRange.new(4, 7)
	dust.Rate = 3
	dust.Speed = NumberRange.new(8, 14)
	dust.SpreadAngle = Vector2.new(8, 8)
	dust.EmissionDirection = Enum.NormalId.Left
	dust.LightInfluence = 1
	dust.Parent = attachment
end

local function buildRoad(parent: Instance)
	local startZ = center.Z + HangarConfig.ROAD_START_Z
	local endZ = center.Z + HangarConfig.ROAD_END_Z
	local length = math.abs(endZ - startZ)
	local midZ = (startZ + endZ) / 2

	local road = makePart(
		"CityRoad",
		Vector3.new(HangarConfig.ROAD_WIDTH, 0.6, length),
		CFrame.new(center.X, -0.2, midZ),
		ASPHALT_COLOR,
		Enum.Material.Asphalt,
		parent
	)
	if not MaterialUtil.apply(road, "TFZ_Asphalt") then
		TextureUtil.applyFace(road, Enum.NormalId.Top, TexturesConfig.ASPHALT, 10)
	end

	local markCount = math.floor(length / 18)
	for index = 0, markCount do
		local marking = makePart(
			"RoadMark",
			Vector3.new(0.7, 0.05, 6),
			CFrame.new(center.X, 0.14, startZ - 6 - index * 18),
			Color3.fromRGB(196, 196, 188),
			Enum.Material.SmoothPlastic,
			parent
		)
		decor(marking)
	end

	local previousTop: Attachment? = nil
	local poleCount = math.floor(length / 55)
	for index = 0, poleCount do
		local sign = if index % 2 == 0 then -1 else 1
		local z = startZ - 12 - index * 55
		local x = center.X + sign * (HangarConfig.ROAD_WIDTH / 2 + 6)
		local pole = makePart("PowerPole", Vector3.new(1.1, 26, 1.1), CFrame.new(x, 13, z), POLE_COLOR, Enum.Material.Wood, parent)
		makePart("PoleCross", Vector3.new(6, 0.7, 0.7), CFrame.new(x, 24, z), POLE_COLOR, Enum.Material.Wood, parent)

		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, 11.6, 0)
		top.Parent = pole

		if previousTop then
			local wire = Instance.new("Beam")
			wire.Attachment0 = previousTop
			wire.Attachment1 = top
			wire.Width0 = 0.12
			wire.Width1 = 0.12
			wire.Color = ColorSequence.new(Color3.fromRGB(28, 28, 30))
			wire.CurveSize0 = -4
			wire.CurveSize1 = -4
			wire.Segments = 8
			wire.LightInfluence = 1
			wire.Parent = pole
		end
		previousTop = top
	end

	for _ = 1, 5 do
		local sign = if random:NextNumber() < 0.5 then -1 else 1
		local z = startZ - random:NextNumber(30, length - 40)
		local x = center.X + sign * random:NextNumber(4, HangarConfig.ROAD_WIDTH / 2 + 12)
		local yaw = random:NextNumber(-0.6, 0.6)
		local base = CFrame.new(x, 1.1, z) * CFrame.Angles(0, yaw, 0)
		local hue = Color3.fromRGB(random:NextInteger(70, 130), random:NextInteger(70, 110), random:NextInteger(70, 110))
		makePart("DeadCarBody", Vector3.new(4.4, 1.6, 8.4), base, hue, Enum.Material.CorrodedMetal, parent)
		makePart("DeadCarCabin", Vector3.new(3.8, 1.2, 3.8), base * CFrame.new(0, 1.35, 0.4), hue:Lerp(Color3.new(0, 0, 0), 0.4), Enum.Material.Metal, parent)
	end

	local checkpointZ = startZ - 26
	for _, sign in { -1, 1 } do
		local barrier = makePart(
			"Checkpoint",
			Vector3.new(10, 3, 2.4),
			CFrame.new(center.X + sign * 13, 1.5, checkpointZ),
			CONCRETE_COLOR,
			Enum.Material.Concrete,
			parent
		)
		TextureUtil.applySides(barrier, TexturesConfig.CONCRETE, 4)
		for row = 0, 2 do
			for column = 0, 3 - row do
				local bag = makePart(
					"Sandbag",
					Vector3.new(2.2, 0.9, 1.2),
					CFrame.new(
						center.X + sign * (20 + column * 2.1 + row * 1.05),
						0.45 + row * 0.85,
						checkpointZ + random:NextNumber(-0.3, 0.3)
					) * CFrame.Angles(0, random:NextNumber(-0.12, 0.12), 0),
					SANDBAG_COLOR,
					Enum.Material.Fabric,
					parent
				)
				bag.CastShadow = false
			end
		end
	end
end

local function buildFencePanel(from: Vector3, to: Vector3, parent: Instance)
	local delta = (to - from)
	local length = delta.Magnitude
	local look = CFrame.lookAt((from + to) / 2 + Vector3.new(0, 4, 0), to + Vector3.new(0, 4, 0))
	local panel = makePart("FencePanel", Vector3.new(0.2, 8, length), look, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, parent)
	panel.Transparency = 1
	panel.CanQuery = false
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local texture = Instance.new("Texture")
		texture.Texture = "rbxassetid://" .. tostring(TexturesConfig.FENCE_CHAINLINK)
		texture.Face = face
		texture.StudsPerTileU = 6
		texture.StudsPerTileV = 6
		texture.Parent = panel
	end
	local postCount = math.max(1, math.floor(length / 9))
	for index = 0, postCount do
		local position = from:Lerp(to, index / postCount)
		makePart("FencePost", Vector3.new(0.5, 8.4, 0.5), CFrame.new(position.X, 4.2, position.Z), Color3.fromRGB(96, 98, 102), Enum.Material.Metal, parent)
	end
end

local function buildMannequin(base: CFrame, color: Color3, parent: Instance)
	makePart("DummyLegs", Vector3.new(1.5, 1.9, 0.9), base * CFrame.new(0, 0.95, 0), Color3.fromRGB(45, 48, 52), Enum.Material.Fabric, parent)
	makePart("DummyTorso", Vector3.new(1.7, 2.1, 0.95), base * CFrame.new(0, 2.95, 0), color, Enum.Material.Fabric, parent)
	makePart("DummyHead", Vector3.new(0.95, 0.95, 0.95), base * CFrame.new(0, 4.5, 0), color:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.SmoothPlastic, parent)
end

local function buildRange(parent: Instance)
	local yardWidth = HangarConfig.RANGE_YARD_WIDTH
	local yardDepth = HangarConfig.RANGE_YARD_DEPTH
	local wallZ = center.Z + HangarConfig.HUB_FLOOR_SIZE.Z / 2
	local yardNear = wallZ + 2
	local yardFar = wallZ + yardDepth
	local yardCenterX = center.X

	local pad = makePart(
		"RangePad",
		Vector3.new(yardWidth, 0.8, yardDepth),
		CFrame.new(yardCenterX, -0.2, (yardNear + yardFar) / 2),
		Color3.fromRGB(168, 158, 134),
		Enum.Material.Ground,
		parent
	)
	TextureUtil.applyFace(pad, Enum.NormalId.Top, TexturesConfig.GROUND, 6)

	local left = yardCenterX - yardWidth / 2
	local right = yardCenterX + yardWidth / 2
	buildFencePanel(Vector3.new(left, 0, yardNear), Vector3.new(left, 0, yardFar), parent)
	buildFencePanel(Vector3.new(right, 0, yardNear), Vector3.new(right, 0, yardFar), parent)
	buildFencePanel(Vector3.new(left, 0, yardFar), Vector3.new(right, 0, yardFar), parent)

	local canopyZ = yardNear + HangarConfig.RANGE_CANOPY_DEPTH / 2 + 4
	local canopy = makePart(
		"RangeCanopy",
		Vector3.new(70, 0.8, HangarConfig.RANGE_CANOPY_DEPTH),
		CFrame.new(yardCenterX, 12, canopyZ),
		Color3.fromRGB(70, 74, 66),
		Enum.Material.Metal,
		parent
	)
	TextureUtil.applyFace(canopy, Enum.NormalId.Bottom, TexturesConfig.CORRUGATED, 8)
	for _, xOffset in { -33, -11, 11, 33 } do
		for _, zOffset in { -HangarConfig.RANGE_CANOPY_DEPTH / 2 + 1, HangarConfig.RANGE_CANOPY_DEPTH / 2 - 1 } do
			makePart("CanopyPost", Vector3.new(0.8, 12, 0.8), CFrame.new(yardCenterX + xOffset, 6, canopyZ + zOffset), Color3.fromRGB(96, 98, 102), Enum.Material.Metal, parent)
		end
	end

	local benchZ = canopyZ + 2
	for index = 1, 4 do
		local x = yardCenterX - 27 + (index - 1) * 18
		makePart("FiringBench", Vector3.new(7, 3.2, 2.4), CFrame.new(x, 1.6, benchZ), Color3.fromRGB(96, 76, 52), Enum.Material.WoodPlanks, parent)
	end

	for index, distance in HangarConfig.RANGE_TARGETS do
		local x = yardCenterX - 27 + (index - 1) * 18
		local targetZ = benchZ + distance
		local stand = makePart("TargetStand", Vector3.new(0.6, 5, 0.6), CFrame.new(x, 2.5, targetZ), Color3.fromRGB(90, 80, 66), Enum.Material.Wood, parent)
		local board = makePart("RangeTarget", Vector3.new(4, 4.6, 0.4), CFrame.new(x, 5.6, targetZ), Color3.fromRGB(214, 206, 188), Enum.Material.WoodPlanks, parent)
		board:SetAttribute("TargetDistance", distance)
		local ring = makePart("TargetRing", Vector3.new(2.2, 2.2, 0.1), CFrame.new(x, 5.6, targetZ - 0.3), Color3.fromRGB(178, 58, 48), Enum.Material.SmoothPlastic, parent)
		decor(ring)
		local _ = stand
	end

	local dummyZ = benchZ + 38
	for _, xOffset in { 54, 62, 58 } do
		buildMannequin(
			CFrame.new(yardCenterX - 60 + (xOffset - 50) * 2, 0.4, dummyZ + random:NextNumber(-6, 6)) * CFrame.Angles(0, math.pi, 0),
			Color3.fromRGB(88, 122, 82),
			parent
		)
	end

	local gong = Instance.new("Part")
	gong.Name = "RangeGong"
	gong.Shape = Enum.PartType.Cylinder
	gong.Size = Vector3.new(0.4, 5, 5)
	gong.CFrame = CFrame.new(yardCenterX + 42, 6, benchZ + 52) * CFrame.Angles(0, math.rad(90), 0)
	gong.Anchored = true
	gong.Color = Color3.fromRGB(168, 138, 74)
	gong.Material = Enum.Material.Metal
	gong.Parent = parent
	makePart("GongFrame", Vector3.new(0.8, 12, 0.8), CFrame.new(yardCenterX + 39, 6, benchZ + 52), Color3.fromRGB(96, 98, 102), Enum.Material.Metal, parent)
	makePart("GongFrameTop", Vector3.new(8, 0.8, 0.8), CFrame.new(yardCenterX + 42.5, 11.6, benchZ + 52), Color3.fromRGB(96, 98, 102), Enum.Material.Metal, parent)

	local berm = Instance.new("WedgePart")
	berm.Name = "SandBerm"
	berm.Size = Vector3.new(yardWidth - 6, 14, 16)
	berm.CFrame = CFrame.new(yardCenterX, 7, yardFar - 9) * CFrame.Angles(0, math.rad(180), 0)
	berm.Anchored = true
	berm.Color = SAND_COLOR
	berm.Material = Enum.Material.Sand
	berm.Parent = parent

	local containment = makePart(
		"RangeContainment",
		Vector3.new(yardWidth + 4, 60, 2),
		CFrame.new(yardCenterX, 30, yardFar + 1),
		Color3.new(0, 0, 0),
		Enum.Material.SmoothPlastic,
		parent
	)
	containment.Transparency = 1
	containment.CastShadow = false
	for _, sign in { -1, 1 } do
		local side = makePart(
			"RangeContainmentSide",
			Vector3.new(2, 60, yardDepth + 4),
			CFrame.new(yardCenterX + sign * (yardWidth / 2 + 1), 30, (yardNear + yardFar) / 2),
			Color3.new(0, 0, 0),
			Enum.Material.SmoothPlastic,
			parent
		)
		side.Transparency = 1
		side.CastShadow = false
	end

	local zone = Instance.new("Part")
	zone.Name = "RangeInteriorZone"
	zone.Size = Vector3.new(70, 14, HangarConfig.RANGE_CANOPY_DEPTH + 4)
	zone.CFrame = CFrame.new(yardCenterX, 6, canopyZ)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.Transparency = 1
	zone:SetAttribute("AcousticSpace", "Interior")
	zone.Parent = parent
end

function DesertBase.build(): Model
	local model = Instance.new("Model")
	model.Name = "DesertBase"
	buildGround(model)
	buildRoad(model)
	buildRange(model)
	model.Parent = Workspace
	return model
end

return DesertBase
