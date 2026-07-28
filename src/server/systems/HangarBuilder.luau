--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local TexturesConfig = require(ReplicatedStorage.Shared.config.TexturesConfig)
local TextureUtil = require(ReplicatedStorage.Shared.util.TextureUtil)
local MaterialUtil = require(ReplicatedStorage.Shared.util.MaterialUtil)

export type Helicopter = {
	index: number,
	model: Model,
	prompt: ProximityPrompt,
	statusLabel: TextLabel,
	padCFrame: CFrame,
}

local HangarBuilder = {}

local center = HangarConfig.HUB_CENTER
local floorSize = HangarConfig.HUB_FLOOR_SIZE
local wallHeight = HangarConfig.HUB_WALL_HEIGHT
local wallThickness = HangarConfig.HUB_WALL_THICKNESS
local halfX = floorSize.X / 2
local halfZ = floorSize.Z / 2

local function makePart(className: string, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): BasePart
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

local function wallCFrame(alongX: boolean, fixed: number, mid: number, y: number): CFrame
	if alongX then
		return CFrame.new(mid, y, fixed)
	end
	return CFrame.new(fixed, y, mid)
end

local function wallSize(alongX: boolean, span: number, height: number): Vector3
	if alongX then
		return Vector3.new(span, height, wallThickness)
	end
	return Vector3.new(wallThickness, height, span)
end

local function buildSolidBand(alongX: boolean, fixed: number, from: number, to: number, y0: number, y1: number, color: Color3, parent: Instance)
	if to - from <= 0.1 or y1 - y0 <= 0.1 then
		return
	end
	local band = makePart(
		"Part",
		"WallBand",
		wallSize(alongX, to - from, y1 - y0),
		wallCFrame(alongX, fixed, (from + to) / 2, (y0 + y1) / 2),
		color,
		Enum.Material.Metal,
		parent
	)
	TextureUtil.applySides(band, TexturesConfig.CORRUGATED, 14)
end

local function buildWindowBand(alongX: boolean, fixed: number, from: number, to: number, y0: number, y1: number, color: Color3, parent: Instance)
	if to - from <= 0.1 then
		return
	end
	local span = to - from
	local segments = math.max(1, math.floor(span / HangarConfig.WINDOW_SEGMENT))
	local step = span / segments

	local glass = makePart(
		"Part",
		"WindowGlass",
		wallSize(alongX, span, y1 - y0),
		wallCFrame(alongX, fixed, (from + to) / 2, (y0 + y1) / 2),
		Color3.fromRGB(150, 180, 200),
		Enum.Material.Glass,
		parent
	)
	glass.Transparency = 0.72
	glass.CastShadow = false
	glass.Reflectance = 0.12

	for i = 0, segments do
		local mid = from + i * step
		makePart(
			"Part",
			"Mullion",
			wallSize(alongX, 1.2, y1 - y0),
			wallCFrame(alongX, fixed, mid, (y0 + y1) / 2),
			color,
			Enum.Material.Metal,
			parent
		)
	end
	makePart("Part", "WindowLedge", wallSize(alongX, span, 1), wallCFrame(alongX, fixed, (from + to) / 2, y0), color, Enum.Material.Metal, parent)
	makePart("Part", "WindowHead", wallSize(alongX, span, 1), wallCFrame(alongX, fixed, (from + to) / 2, y1), color, Enum.Material.Metal, parent)
end

local function buildWall(alongX: boolean, fixed: number, from: number, to: number, gapFrom: number?, gapTo: number?, parent: Instance)
	local color = HangarConfig.WALL_COLOR
	local sill = HangarConfig.WINDOW_SILL
	local head = sill + HangarConfig.WINDOW_BAND_HEIGHT

	local spans: { { number } } = {}
	if gapFrom and gapTo then
		table.insert(spans, { from, gapFrom })
		table.insert(spans, { gapTo, to })
	else
		table.insert(spans, { from, to })
	end

	for _, span in spans do
		buildSolidBand(alongX, fixed, span[1], span[2], 0, sill, color, parent)
		buildWindowBand(alongX, fixed, span[1], span[2], sill, head, color, parent)
		buildSolidBand(alongX, fixed, span[1], span[2], head, wallHeight, color, parent)
	end

	if gapFrom and gapTo then
		buildSolidBand(alongX, fixed, gapFrom, gapTo, HangarConfig.GATE_HEIGHT, wallHeight, color, parent)
		for _, edge in { gapFrom, gapTo } do
			makePart(
				"Part",
				"GateFrame",
				wallSize(alongX, 2.5, HangarConfig.GATE_HEIGHT),
				wallCFrame(alongX, fixed, edge, HangarConfig.GATE_HEIGHT / 2),
				HangarConfig.TRIM_COLOR,
				Enum.Material.Metal,
				parent
			)
		end
	end
end

local function buildCeiling(parent: Instance)
	local roof = makePart(
		"Part",
		"Roof",
		Vector3.new(floorSize.X, 2, floorSize.Z),
		CFrame.new(center.X, wallHeight + 1, center.Z),
		HangarConfig.WALL_COLOR:Lerp(Color3.new(0, 0, 0), 0.35),
		Enum.Material.Metal,
		parent
	)
	roof.CastShadow = false
	TextureUtil.applyFace(roof, Enum.NormalId.Bottom, TexturesConfig.METAL_PLATES, 20)

	for i = -3, 3 do
		local z = center.Z + i * (floorSize.Z / 7)
		local truss = makePart(
			"Part",
			"Truss",
			Vector3.new(floorSize.X, 2.2, 2.2),
			CFrame.new(center.X, wallHeight - 2, z),
			HangarConfig.WALL_COLOR:Lerp(Color3.new(1, 1, 1), 0.1),
			Enum.Material.DiamondPlate,
			parent
		)
		truss.CanCollide = false
		truss.CastShadow = false
	end
end

local function buildCeilingLamp(position: Vector3, parent: Instance, range: number?, brightness: number?)
	local fixture = makePart("Part", "CeilingLamp", Vector3.new(7, 0.6, 4), CFrame.new(position), Color3.fromRGB(236, 224, 198), Enum.Material.Neon, parent)
	fixture.CanCollide = false
	fixture.CastShadow = false
	fixture.Transparency = 0.15

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 236, 200)
	light.Range = range or 42
	light.Brightness = brightness or 1.1
	light.Shadows = false
	light.Parent = fixture
end

local function buildHelipadMarkings(padCFrame: CFrame, parent: Instance)
	local segments = 20
	local radius = 22
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local ring = makePart(
			"Part",
			"PadRing",
			Vector3.new(3.4, 0.08, 1.2),
			padCFrame * CFrame.new(math.cos(angle) * radius, 0.06, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0),
			HangarConfig.TRIM_COLOR,
			Enum.Material.SmoothPlastic,
			parent
		)
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CastShadow = false
	end

	local barOffsets = { Vector3.new(-4, 0, 0), Vector3.new(4, 0, 0) }
	for _, offset in barOffsets do
		local bar = makePart("Part", "PadH", Vector3.new(1.6, 0.08, 12), padCFrame * CFrame.new(offset.X, 0.06, 0), HangarConfig.TRIM_COLOR, Enum.Material.SmoothPlastic, parent)
		bar.CanCollide = false
		bar.CanQuery = false
		bar.CastShadow = false
	end
	local cross = makePart("Part", "PadHBar", Vector3.new(8, 0.08, 1.6), padCFrame * CFrame.new(0, 0.06, 0), HangarConfig.TRIM_COLOR, Enum.Material.SmoothPlastic, parent)
	cross.CanCollide = false
	cross.CanQuery = false
	cross.CastShadow = false
end

local function buildPalletStack(base: Vector3, height: number, parent: Instance)
	for i = 0, height - 1 do
		local pallet = makePart(
			"Part",
			"Pallet",
			Vector3.new(7, 0.9, 7),
			CFrame.new(base + Vector3.new((i % 2) * 0.4, 0.45 + i * 0.95, (i % 2) * -0.3)) * CFrame.Angles(0, math.rad(i * 4), 0),
			Color3.fromRGB(126, 104, 72),
			Enum.Material.WoodPlanks,
			parent
		)
		TextureUtil.applyFace(pallet, Enum.NormalId.Top, TexturesConfig.WOOD, 4)
	end
end

local function buildSackPile(base: Vector3, parent: Instance)
	local sackColor = Color3.fromRGB(112, 106, 88)
	local layout = {
		{ Vector3.new(0, 0.9, 0), 0 },
		{ Vector3.new(3.4, 0.9, 0.6), 24 },
		{ Vector3.new(1.4, 0.9, 3.2), -18 },
		{ Vector3.new(1.8, 2.6, 1.4), 40 },
	}
	for _, entry in layout do
		local sack = makePart(
			"Part",
			"Sack",
			Vector3.new(3.6, 1.8, 2.4),
			CFrame.new(base + entry[1]) * CFrame.Angles(0, math.rad(entry[2]), 0),
			sackColor,
			Enum.Material.Fabric,
			parent
		)
		TextureUtil.applyAll(sack, TexturesConfig.FABRIC, 3)
	end
end

local function buildCableSpool(base: Vector3, upright: boolean, parent: Instance)
	local spoolColor = Color3.fromRGB(140, 112, 70)
	local orientation = if upright
		then CFrame.new(base + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		else CFrame.new(base + Vector3.new(0, 1.1, 0))
	for _, offset in { -2.4, 2.4 } do
		local disc = Instance.new("Part")
		disc.Name = "SpoolDisc"
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.8, 6.4, 6.4)
		disc.CFrame = orientation * CFrame.new(offset, 0, 0)
		disc.Anchored = true
		disc.Color = spoolColor
		disc.Material = Enum.Material.WoodPlanks
		disc.Parent = parent
	end
	local core = Instance.new("Part")
	core.Name = "SpoolCore"
	core.Shape = Enum.PartType.Cylinder
	core.Size = Vector3.new(4.8, 3.6, 3.6)
	core.CFrame = orientation
	core.Anchored = true
	core.Color = Color3.fromRGB(44, 46, 50)
	core.Material = Enum.Material.Plastic
	core.Parent = parent
end

local function buildShelving(base: Vector3, yaw: number, parent: Instance)
	local frameColor = Color3.fromRGB(180, 92, 40)
	local rootCFrame = CFrame.new(base) * CFrame.Angles(0, math.rad(yaw), 0)
	for _, x in { -7, 7 } do
		for _, z in { -1.6, 1.6 } do
			makePart("Part", "RackLeg", Vector3.new(0.6, 12, 0.6), rootCFrame * CFrame.new(x, 6, z), frameColor, Enum.Material.Metal, parent)
		end
	end
	for _, y in { 3, 7, 11 } do
		makePart("Part", "RackShelf", Vector3.new(15, 0.4, 4), rootCFrame * CFrame.new(0, y, 0), Color3.fromRGB(96, 100, 106), Enum.Material.DiamondPlate, parent)
	end
	local boxSpots = { { -4.5, 3.6, 0 }, { 2, 3.7, 0.4 }, { -1, 7.7, -0.4 }, { 5, 7.6, 0 } }
	for _, spot in boxSpots do
		makePart(
			"Part",
			"RackBox",
			Vector3.new(3.4, 2.6, 2.8),
			rootCFrame * CFrame.new(spot[1], spot[2] + 0.9, spot[3]),
			Color3.fromRGB(104, 98, 78),
			Enum.Material.WoodPlanks,
			parent
		)
	end
end

local function buildProps(parent: Instance)
	local crateColor = Color3.fromRGB(96, 104, 78)
	local drumColor = Color3.fromRGB(150, 90, 40)
	local spots = {
		Vector3.new(-120, 0, 120),
		Vector3.new(-96, 0, 128),
		Vector3.new(96, 0, 124),
		Vector3.new(124, 0, 112),
		Vector3.new(-40, 0, 136),
		Vector3.new(48, 0, 138),
	}
	for index, spot in spots do
		local base = center + spot
		if index % 2 == 1 then
			local crateA = makePart("Part", "Crate", Vector3.new(7, 5, 7), CFrame.new(base + Vector3.new(0, 3, 0)), crateColor, Enum.Material.WoodPlanks, parent)
			local crateB = makePart("Part", "Crate", Vector3.new(5.5, 4, 5.5), CFrame.new(base + Vector3.new(1.5, 7.5, -1)), crateColor:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.WoodPlanks, parent)
			TextureUtil.applyAll(crateA, TexturesConfig.WOOD, 4)
			TextureUtil.applyAll(crateB, TexturesConfig.WOOD, 4)
		else
			for i = 0, 2 do
				local drum = Instance.new("Part")
				drum.Name = "FuelDrum"
				drum.Shape = Enum.PartType.Cylinder
				drum.Size = Vector3.new(6, 4, 4)
				drum.CFrame = CFrame.new(base + Vector3.new(i * 4.5, 3, 0)) * CFrame.Angles(0, 0, math.rad(90))
				drum.Anchored = true
				drum.Color = drumColor
				drum.Material = Enum.Material.CorrodedMetal
				drum.Parent = parent
				TextureUtil.applySides(drum, TexturesConfig.RUST, 4)
			end
		end
	end

	buildPalletStack(center + Vector3.new(-150, 0, 0), 4, parent)
	buildPalletStack(center + Vector3.new(-142, 0, 8), 2, parent)
	buildSackPile(center + Vector3.new(-148, 0, -14), parent)
	buildCableSpool(center + Vector3.new(150, 0, 110), true, parent)
	buildCableSpool(center + Vector3.new(144, 0, 122), false, parent)
	buildShelving(center + Vector3.new(152, 0, 2), 90, parent)
	buildShelving(center + Vector3.new(152, 0, 22), 90, parent)
	buildPalletStack(center + Vector3.new(60, 0, -140), 3, parent)
	buildSackPile(center + Vector3.new(-70, 0, -142), parent)
	buildCableSpool(center + Vector3.new(-118, 0, -138), false, parent)
end

local function paintStrip(name: string, size: Vector3, cframe: CFrame, color: Color3, transparency: number, parent: Instance)
	local strip = makePart("Part", name, size, cframe, color, Enum.Material.SmoothPlastic, parent)
	strip.CanCollide = false
	strip.CanQuery = false
	strip.CastShadow = false
	strip.Transparency = transparency
	return strip
end

local function buildFloorGrime(parent: Instance)
	local floorY = center.Y + 0.56

	local stainSpots = {
		{ Vector3.new(-90, 0, -108), 11 },
		{ Vector3.new(6, 0, -104), 14 },
		{ Vector3.new(94, 0, -112), 9 },
		{ Vector3.new(-118, 0, 116), 8 },
		{ Vector3.new(120, 0, 108), 10 },
		{ Vector3.new(-146, 0, 12), 7 },
		{ Vector3.new(148, 0, 100), 8 },
		{ Vector3.new(30, 0, 30), 12 },
	}
	for index, spot in stainSpots do
		local stain = Instance.new("Part")
		stain.Name = "OilStain"
		stain.Shape = Enum.PartType.Cylinder
		stain.Size = Vector3.new(0.06, spot[2], spot[2])
		stain.CFrame = CFrame.new(center + spot[1] + Vector3.new(0, floorY, 0)) * CFrame.Angles(0, math.rad(index * 37), math.rad(90))
		stain.Anchored = true
		stain.CanCollide = false
		stain.CanQuery = false
		stain.CastShadow = false
		stain.Color = Color3.fromRGB(26, 26, 28)
		stain.Material = Enum.Material.SmoothPlastic
		stain.Transparency = 0.42
		stain.Parent = parent
	end

	local trackColor = Color3.fromRGB(38, 38, 40)
	for _, padCFrame in HangarConfig.HELICOPTER_PADS do
		local padX = padCFrame.Position.X
		local padZ = padCFrame.Position.Z
		local gateZ = center.Z - halfZ
		local length = padZ - gateZ
		for _, side in { -3.2, 3.2 } do
			paintStrip(
				"TireTrack",
				Vector3.new(1.6, 0.05, length),
				CFrame.new(padX + side + (padX - center.X) * 0.04, floorY, gateZ + length / 2),
				trackColor,
				0.55,
				parent
			)
		end
	end

	local hazardY = floorY + 0.01
	local gateZ = center.Z - halfZ + 6
	local stripeCount = math.floor((HangarConfig.GATE_HALF_WIDTH * 2 - 8) / 6)
	for i = 0, stripeCount - 1 do
		local color = if i % 2 == 0 then Color3.fromRGB(196, 160, 40) else Color3.fromRGB(30, 30, 32)
		paintStrip(
			"HazardStripe",
			Vector3.new(6, 0.05, 4),
			CFrame.new(center.X - HangarConfig.GATE_HALF_WIDTH + 4 + i * 6 + 3, hazardY, gateZ) * CFrame.Angles(0, math.rad(18), 0),
			color,
			0.1,
			parent
		)
	end
	for i = 0, 4 do
		local color = if i % 2 == 0 then Color3.fromRGB(196, 160, 40) else Color3.fromRGB(30, 30, 32)
		paintStrip(
			"HazardStripe",
			Vector3.new(4.4, 0.05, 3),
			CFrame.new(center.X - HangarConfig.RANGE_DOOR_HALF_WIDTH + i * 5 + 2.2, hazardY, center.Z + halfZ - 5) * CFrame.Angles(0, math.rad(-18), 0),
			color,
			0.1,
			parent
		)
	end

	local guideColor = Color3.fromRGB(158, 148, 112)
	paintStrip("GuideLine", Vector3.new(0.9, 0.05, 220), CFrame.new(center.X - 24, floorY, center.Z + 20), guideColor, 0.35, parent)
	paintStrip("GuideLine", Vector3.new(0.9, 0.05, 220), CFrame.new(center.X + 24, floorY, center.Z + 20), guideColor, 0.35, parent)
	paintStrip("GuideLine", Vector3.new(200, 0.05, 0.9), CFrame.new(center.X, floorY, center.Z - 70), guideColor, 0.35, parent)
end

local function buildHelicopter(index: number, padCFrame: CFrame, parent: Instance): Helicopter
	local model = Instance.new("Model")
	model.Name = "Helicopter" .. index

	local green = HangarConfig.HELI_COLOR
	local dark = green:Lerp(Color3.new(0, 0, 0), 0.45)
	local metal = Color3.fromRGB(90, 94, 96)

	local function place(className: string, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): BasePart
		return makePart(className, name, size, padCFrame * offset, color, material, model)
	end

	for _, sign in { -1, 1 } do
		local skid = Instance.new("Part")
		skid.Name = "Skid"
		skid.Shape = Enum.PartType.Cylinder
		skid.Size = Vector3.new(15, 1, 1)
		skid.CFrame = padCFrame * CFrame.new(sign * 3.4, 0.6, 0) * CFrame.Angles(0, math.rad(90), 0)
		skid.Anchored = true
		skid.Color = dark
		skid.Material = Enum.Material.Metal
		skid.Parent = model

		for _, z in { 3.6, -3.6 } do
			place("Part", "SkidStrut", Vector3.new(0.5, 2.4, 0.5), CFrame.new(sign * 3.4, 1.8, z), dark, Enum.Material.Metal)
			place("Part", "SkidBrace", Vector3.new(3.2, 0.4, 0.4), CFrame.new(sign * 1.9, 2.6, z), dark, Enum.Material.Metal)
		end
	end

	local belly = place("Part", "Belly", Vector3.new(7.8, 2.4, 13), CFrame.new(0, 4, 0), green, Enum.Material.Metal)
	local cabin = place("Part", "Cabin", Vector3.new(8.2, 4.8, 12.5), CFrame.new(0, 6.6, 0), green, Enum.Material.Metal)
	TextureUtil.applySides(belly, TexturesConfig.METAL_PLATES, 6)
	TextureUtil.applySides(cabin, TexturesConfig.METAL_PLATES, 6)
	place("Part", "Roof", Vector3.new(7.8, 1, 12), CFrame.new(0, 9.2, -0.2), green:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Metal)

	local canopy = place("Part", "Canopy", Vector3.new(7.4, 4, 3.4), CFrame.new(0, 6.8, 6.4), Color3.fromRGB(70, 96, 116), Enum.Material.Glass)
	canopy.Transparency = 0.35
	canopy.Reflectance = 0.15
	place("WedgePart", "Nose", Vector3.new(7.4, 3.4, 4.4), CFrame.new(0, 4.4, 8.4) * CFrame.Angles(0, math.pi, 0), green, Enum.Material.Metal)

	for _, sign in { -1, 1 } do
		place("Part", "DoorFrame", Vector3.new(0.35, 3.8, 5), CFrame.new(sign * 4.15, 6.4, 0.5), dark, Enum.Material.Metal)
		local navLight = place("Part", "NavLight", Vector3.new(0.5, 0.5, 0.5), CFrame.new(sign * 4.3, 5.2, 5.6), if sign < 0 then Color3.fromRGB(220, 40, 40) else Color3.fromRGB(40, 220, 90), Enum.Material.Neon)
		navLight.CanCollide = false
		navLight.CastShadow = false
	end
	place("Part", "Bench", Vector3.new(6.8, 0.6, 3.2), CFrame.new(0, 5.4, -2.6), HangarConfig.SEAT_COLOR, Enum.Material.Fabric)

	place("Part", "Engine", Vector3.new(5.4, 2.6, 6.5), CFrame.new(0, 10.2, -1.5), metal, Enum.Material.DiamondPlate)
	local exhaust = Instance.new("Part")
	exhaust.Name = "Exhaust"
	exhaust.Shape = Enum.PartType.Cylinder
	exhaust.Size = Vector3.new(3, 1.8, 1.8)
	exhaust.CFrame = padCFrame * CFrame.new(0, 10.2, -5.4) * CFrame.Angles(0, math.rad(90), 0)
	exhaust.Anchored = true
	exhaust.Color = Color3.fromRGB(48, 48, 50)
	exhaust.Material = Enum.Material.CorrodedMetal
	exhaust.Parent = model

	place("Part", "TailBoom", Vector3.new(2.2, 2.2, 10), CFrame.new(0, 8.6, -11), green, Enum.Material.Metal)
	place("Part", "TailBoomEnd", Vector3.new(1.5, 1.5, 7), CFrame.new(0, 8.6, -18.5), green, Enum.Material.Metal)
	place("Part", "Stabilizer", Vector3.new(8, 0.5, 2.6), CFrame.new(0, 8.6, -18), green, Enum.Material.Metal)
	place("WedgePart", "TailFin", Vector3.new(0.7, 6, 3.4), CFrame.new(0, 11.4, -21.4), green, Enum.Material.Metal)
	place("Part", "TailRotorHub", Vector3.new(1.6, 1.2, 1.2), CFrame.new(1.1, 9.6, -21), dark, Enum.Material.Metal)
	for i = 0, 1 do
		local blade = place("Part", "TailBlade", Vector3.new(0.3, 5.6, 0.9), CFrame.new(1.6, 9.6, -21) * CFrame.Angles(math.rad(90 * i), 0, 0), dark, Enum.Material.SmoothPlastic)
		blade.CanCollide = false
		blade.CastShadow = false
	end

	place("Part", "RotorMast", Vector3.new(1.2, 2.4, 1.2), CFrame.new(0, 12, 0), dark, Enum.Material.Metal)
	local hub = Instance.new("Part")
	hub.Name = "RotorHub"
	hub.Shape = Enum.PartType.Cylinder
	hub.Size = Vector3.new(1, 3, 3)
	hub.CFrame = padCFrame * CFrame.new(0, 13.2, 0) * CFrame.Angles(0, 0, math.rad(90))
	hub.Anchored = true
	hub.Color = dark
	hub.Material = Enum.Material.Metal
	hub.Parent = model

	for i = 0, 3 do
		local blade = place(
			"Part",
			"RotorBlade",
			Vector3.new(30, 0.3, 1.9),
			CFrame.new(0, 13.1, 0) * CFrame.Angles(0, math.rad(45 * i), math.rad(-1.5)),
			dark,
			Enum.Material.SmoothPlastic
		)
		blade.CanCollide = false
		blade.CastShadow = false
	end

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
	billboard.Size = UDim2.fromScale(12, 3)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 16, 0)
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

	local hangarFloor = makePart("Part", "HangarFloor", floorSize, CFrame.new(center), HangarConfig.FLOOR_COLOR, Enum.Material.Concrete, model)
	if not MaterialUtil.apply(hangarFloor, "TFZ_Concrete") then
		TextureUtil.applyFace(hangarFloor, Enum.NormalId.Top, TexturesConfig.CONCRETE, 16)
	end

	buildWall(true, center.Z - halfZ, center.X - halfX, center.X + halfX, center.X - HangarConfig.GATE_HALF_WIDTH, center.X + HangarConfig.GATE_HALF_WIDTH, model)

	local containHeight = wallHeight + 30
	local doorHalf = HangarConfig.RANGE_DOOR_HALF_WIDTH
	local backSegment = (floorSize.X + 8) / 2 - doorHalf
	local containLayouts = {
		{ Vector3.new(floorSize.X + 8, containHeight, 2), CFrame.new(center.X, containHeight / 2, center.Z - halfZ) },
		{ Vector3.new(backSegment, containHeight, 2), CFrame.new(center.X - doorHalf - backSegment / 2, containHeight / 2, center.Z + halfZ) },
		{ Vector3.new(backSegment, containHeight, 2), CFrame.new(center.X + doorHalf + backSegment / 2, containHeight / 2, center.Z + halfZ) },
		{ Vector3.new(2, containHeight, floorSize.Z + 8), CFrame.new(center.X - halfX, containHeight / 2, center.Z) },
		{ Vector3.new(2, containHeight, floorSize.Z + 8), CFrame.new(center.X + halfX, containHeight / 2, center.Z) },
	}
	for index, layout in containLayouts do
		local barrier = makePart("Part", "Containment" .. index, layout[1], layout[2], Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, model)
		barrier.Transparency = 1
		barrier.CastShadow = false
		barrier.CanQuery = false
	end

	local gateGlass = makePart(
		"Part",
		"GateGlass",
		Vector3.new(HangarConfig.GATE_HALF_WIDTH * 2 - 4, HangarConfig.GATE_HEIGHT - 2, 0.6),
		CFrame.new(center.X, HangarConfig.GATE_HEIGHT / 2, center.Z - halfZ + 0.6),
		Color3.fromRGB(255, 168, 104),
		Enum.Material.Glass,
		model
	)
	gateGlass.Transparency = 0.62
	gateGlass.Reflectance = 0.1
	gateGlass.CastShadow = false

	local mullionCount = 5
	for index = 0, mullionCount do
		local x = center.X - HangarConfig.GATE_HALF_WIDTH + (index / mullionCount) * HangarConfig.GATE_HALF_WIDTH * 2
		makePart(
			"Part",
			"GateMullion",
			Vector3.new(1.4, HangarConfig.GATE_HEIGHT, 1.2),
			CFrame.new(x, HangarConfig.GATE_HEIGHT / 2, center.Z - halfZ + 0.6),
			HangarConfig.TRIM_COLOR,
			Enum.Material.Metal,
			model
		)
	end
	buildWall(
		true,
		center.Z + halfZ,
		center.X - halfX,
		center.X + halfX,
		center.X - HangarConfig.RANGE_DOOR_HALF_WIDTH,
		center.X + HangarConfig.RANGE_DOOR_HALF_WIDTH,
		model
	)
	buildWall(false, center.X - halfX, center.Z - halfZ, center.Z + halfZ, nil, nil, model)
	buildWall(false, center.X + halfX, center.Z - halfZ, center.Z + halfZ, nil, nil, model)

	buildCeiling(model)

	for _, padCFrame in HangarConfig.HELICOPTER_PADS do
		buildCeilingLamp(Vector3.new(padCFrame.Position.X, wallHeight - 4, padCFrame.Position.Z), model, 52, 1.35)
	end
	buildCeilingLamp(center + Vector3.new(0, wallHeight - 4, 92), model, 46, 1.2)
	buildCeilingLamp(center + Vector3.new(-120, wallHeight - 4, 40), model, 44, 1.05)
	buildCeilingLamp(center + Vector3.new(120, wallHeight - 4, 40), model, 44, 1.05)
	buildCeilingLamp(center + Vector3.new(0, wallHeight - 4, 0), model, 46, 1.1)
	buildCeilingLamp(center + Vector3.new(-60, wallHeight - 4, 140), model, 40, 1)
	buildCeilingLamp(center + Vector3.new(60, wallHeight - 4, 140), model, 40, 1)

	buildProps(model)
	buildFloorGrime(model)

	local acousticZone = makePart(
		"Part",
		"HangarInteriorZone",
		Vector3.new(floorSize.X, wallHeight, floorSize.Z),
		CFrame.new(center.X, wallHeight / 2, center.Z),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		model
	)
	acousticZone.Transparency = 1
	acousticZone.CanCollide = false
	acousticZone.CanQuery = false
	acousticZone.CanTouch = false
	acousticZone:SetAttribute("AcousticSpace", "Interior")

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "HubSpawn"
	spawnLocation.Size = Vector3.new(14, 1, 14)
	spawnLocation.CFrame = HangarConfig.HUB_SPAWN_CFRAME + Vector3.new(0, -3, 0)
	spawnLocation.Anchored = true
	spawnLocation.CanCollide = false
	spawnLocation.Transparency = 1
	spawnLocation.Duration = 0
	spawnLocation.Neutral = true
	spawnLocation.Parent = model

	local helicopters: { Helicopter } = {}
	for index, padCFrame in HangarConfig.HELICOPTER_PADS do
		buildHelipadMarkings(padCFrame, model)
		helicopters[index] = buildHelicopter(index, padCFrame, model)
	end

	model.Parent = Workspace
	return helicopters
end

return HangarBuilder
