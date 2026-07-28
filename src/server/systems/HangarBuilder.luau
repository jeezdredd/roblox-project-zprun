--!strict

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local TexturesConfig = require(ReplicatedStorage.Shared.config.TexturesConfig)

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
	makePart(
		"Part",
		"WallBand",
		wallSize(alongX, to - from, y1 - y0),
		wallCFrame(alongX, fixed, (from + to) / 2, (y0 + y1) / 2),
		color,
		Enum.Material.Metal,
		parent
	)
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
			"Mullion",
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

local function buildCeilingLamp(position: Vector3, parent: Instance)
	local fixture = makePart("Part", "CeilingLamp", Vector3.new(9, 0.6, 5), CFrame.new(position), Color3.fromRGB(255, 244, 220), Enum.Material.Neon, parent)
	fixture.CanCollide = false
	fixture.CastShadow = false

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 238, 205)
	light.Range = 60
	light.Brightness = 1.6
	light.Shadows = true
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
			padCFrame * CFrame.new(math.cos(angle) * radius, 0.55, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0),
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
		local bar = makePart("Part", "PadH", Vector3.new(1.6, 0.08, 12), padCFrame * CFrame.new(offset.X, 0.55, 0), HangarConfig.TRIM_COLOR, Enum.Material.SmoothPlastic, parent)
		bar.CanCollide = false
		bar.CanQuery = false
		bar.CastShadow = false
	end
	local cross = makePart("Part", "PadHBar", Vector3.new(8, 0.08, 1.6), padCFrame * CFrame.new(0, 0.55, 0), HangarConfig.TRIM_COLOR, Enum.Material.SmoothPlastic, parent)
	cross.CanCollide = false
	cross.CanQuery = false
	cross.CastShadow = false
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
			makePart("Part", "Crate", Vector3.new(7, 5, 7), CFrame.new(base + Vector3.new(0, 3, 0)), crateColor, Enum.Material.WoodPlanks, parent)
			makePart("Part", "Crate", Vector3.new(5.5, 4, 5.5), CFrame.new(base + Vector3.new(1.5, 7.5, -1)), crateColor:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.WoodPlanks, parent)
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
			end
		end
	end
end

local function setupLighting()
	Lighting.ClockTime = 20.2
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(58, 58, 68)
	Lighting.OutdoorAmbient = Color3.fromRGB(72, 66, 70)
	Lighting.FogColor = Color3.fromRGB(52, 44, 44)
	Lighting.FogStart = 180
	Lighting.FogEnd = 900
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

	place("Part", "Belly", Vector3.new(7.8, 2.4, 13), CFrame.new(0, 4, 0), green, Enum.Material.Metal)
	local cabin = place("Part", "Cabin", Vector3.new(8.2, 4.8, 12.5), CFrame.new(0, 6.6, 0), green, Enum.Material.Metal)
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
	local floorTexture = Instance.new("Texture")
	floorTexture.Texture = "rbxassetid://" .. tostring(TexturesConfig.CONCRETE)
	floorTexture.Face = Enum.NormalId.Top
	floorTexture.StudsPerTileU = 16
	floorTexture.StudsPerTileV = 16
	floorTexture.Parent = hangarFloor

	buildWall(true, center.Z - halfZ, center.X - halfX, center.X + halfX, center.X - HangarConfig.GATE_HALF_WIDTH, center.X + HangarConfig.GATE_HALF_WIDTH, model)
	buildWall(true, center.Z + halfZ, center.X - halfX, center.X + halfX, nil, nil, model)
	buildWall(false, center.X - halfX, center.Z - halfZ, center.Z + halfZ, nil, nil, model)
	buildWall(false, center.X + halfX, center.Z - halfZ, center.Z + halfZ, nil, nil, model)

	buildCeiling(model)

	for _, xOffset in { -120, -40, 40, 120 } do
		for _, zOffset in { -110, -30, 50, 130 } do
			buildCeilingLamp(center + Vector3.new(xOffset, wallHeight - 4, zOffset), model)
		end
	end

	buildProps(model)
	setupLighting()

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
