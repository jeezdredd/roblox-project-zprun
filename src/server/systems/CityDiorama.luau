--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local TexturesConfig = require(ReplicatedStorage.Shared.config.TexturesConfig)

local CityDiorama = {}

type Chopper = {
	model: Model,
	radius: number,
	speed: number,
	phase: number,
	height: number,
	centerX: number,
	centerZ: number,
	rotor: BasePart,
}

local center = HangarConfig.HUB_CENTER
local random = Random.new(20260728)
local choppers: { Chopper } = {}
local elapsed = 0

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Color = color
	part.Material = material
	part.Parent = parent
	return part
end

local function buildGround(parent: Instance)
	local depth = math.abs(HangarConfig.CITY_FAR_Z - HangarConfig.CITY_NEAR_Z) + 200
	local midZ = center.Z + (HangarConfig.CITY_NEAR_Z + HangarConfig.CITY_FAR_Z) / 2
	local ground = makePart(
		"CityGround",
		Vector3.new(HangarConfig.CITY_HALF_WIDTH * 2 + 400, 2, depth),
		CFrame.new(center.X, center.Y - 0.5, midZ),
		Color3.fromRGB(58, 56, 58),
		Enum.Material.Asphalt,
		parent
	)
	local texture = Instance.new("Texture")
	texture.Texture = "rbxassetid://" .. tostring(TexturesConfig.ASPHALT)
	texture.Face = Enum.NormalId.Top
	texture.StudsPerTileU = 40
	texture.StudsPerTileV = 40
	texture.Parent = ground
end

local function addFire(building: Part, height: number, parent: Instance)
	local top = building.Position + Vector3.new(0, height / 2, 0)

	local fireAnchor = makePart("FireAnchor", Vector3.new(1, 1, 1), CFrame.new(top), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, parent)
	fireAnchor.Transparency = 1

	local fire = Instance.new("Fire")
	fire.Heat = 18
	fire.Size = 26
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(120, 40, 10)
	fire.Parent = fireAnchor

	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(48, 44, 44)
	smoke.Size = 30
	smoke.RiseVelocity = 22
	smoke.Opacity = 0.32
	smoke.Parent = fireAnchor

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 130, 50)
	glow.Range = 120
	glow.Brightness = 3
	glow.Parent = fireAnchor

	for _ = 1, 2 do
		local windowGlow = makePart(
			"BurningWindow",
			Vector3.new(building.Size.X * 0.7, 6, 0.6),
			CFrame.new(building.Position + Vector3.new(0, random:NextNumber(-height / 3, height / 3), -building.Size.Z / 2 - 0.4)),
			Color3.fromRGB(255, 150, 60),
			Enum.Material.Neon,
			parent
		)
		windowGlow.CastShadow = false
	end
end

local function buildBuilding(index: number, burning: boolean, parent: Instance)
	local width = random:NextNumber(40, 90)
	local depth = random:NextNumber(40, 90)
	local height = random:NextNumber(60, 190)
	local x = center.X + random:NextNumber(-HangarConfig.CITY_HALF_WIDTH, HangarConfig.CITY_HALF_WIDTH)
	local z = center.Z + random:NextNumber(HangarConfig.CITY_FAR_Z, HangarConfig.CITY_NEAR_Z)
	local shade = random:NextInteger(38, 62)

	local building = makePart(
		"CityBlock" .. index,
		Vector3.new(width, height, depth),
		CFrame.new(x, height / 2, z),
		Color3.fromRGB(shade, shade, shade + 4),
		Enum.Material.Concrete,
		parent
	)

	local bandCount = math.floor(height / 22)
	for i = 1, bandCount do
		if random:NextNumber() < 0.45 then
			local band = makePart(
				"CityWindows",
				Vector3.new(width * 0.82, 4.5, 0.5),
				CFrame.new(x, i * 22, z - depth / 2 - 0.3),
				Color3.fromRGB(255, 216, 150),
				Enum.Material.Neon,
				parent
			)
			band.Transparency = 0.25
			band.CastShadow = false
		end
	end

	if burning then
		addFire(building, height, parent)
	end
end

local function buildChopperModel(parent: Instance): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "PatrolChopper"

	local body = makePart("Body", Vector3.new(7, 5, 16), CFrame.new(), Color3.fromRGB(38, 42, 44), Enum.Material.Metal, model)
	makePart("Tail", Vector3.new(1.6, 1.6, 14), CFrame.new(0, 1.4, -14), Color3.fromRGB(38, 42, 44), Enum.Material.Metal, model)
	makePart("Fin", Vector3.new(0.6, 5, 3), CFrame.new(0, 3.6, -20), Color3.fromRGB(38, 42, 44), Enum.Material.Metal, model)

	local rotor = makePart("Rotor", Vector3.new(34, 0.4, 2), CFrame.new(0, 3.6, 0), Color3.fromRGB(30, 32, 34), Enum.Material.SmoothPlastic, model)
	local rotorCross = makePart("RotorCross", Vector3.new(2, 0.4, 34), CFrame.new(0, 3.6, 0), Color3.fromRGB(30, 32, 34), Enum.Material.SmoothPlastic, model)
	rotorCross.CastShadow = false

	local beacon = makePart("Beacon", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, -2.8, 4), Color3.fromRGB(255, 60, 60), Enum.Material.Neon, model)
	local beaconLight = Instance.new("PointLight")
	beaconLight.Color = Color3.fromRGB(255, 60, 60)
	beaconLight.Range = 40
	beaconLight.Brightness = 2
	beaconLight.Parent = beacon

	local searchlight = Instance.new("SpotLight")
	searchlight.Color = Color3.fromRGB(255, 250, 225)
	searchlight.Range = 220
	searchlight.Brightness = 4
	searchlight.Angle = 42
	searchlight.Face = Enum.NormalId.Bottom
	searchlight.Parent = body

	model.PrimaryPart = body
	model.Parent = parent
	return model, rotor
end

local function step(deltaTime: number)
	elapsed += deltaTime
	for _, chopper in choppers do
		local angle = chopper.phase + elapsed * chopper.speed
		local x = chopper.centerX + math.cos(angle) * chopper.radius
		local z = chopper.centerZ + math.sin(angle) * chopper.radius
		local y = chopper.height + math.sin(elapsed * 0.6 + chopper.phase) * 8
		local heading = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(
			chopper.centerX + math.cos(angle + 0.1) * chopper.radius,
			y,
			chopper.centerZ + math.sin(angle + 0.1) * chopper.radius
		))
		chopper.model:PivotTo(heading)
		chopper.rotor.CFrame = chopper.rotor.CFrame * CFrame.Angles(0, deltaTime * 40, 0)
	end
end

function CityDiorama.build()
	local model = Instance.new("Model")
	model.Name = "CityDiorama"

	buildGround(model)

	local burningSlots: { [number]: boolean } = {}
	for _ = 1, HangarConfig.CITY_FIRES do
		burningSlots[random:NextInteger(1, HangarConfig.CITY_BLOCKS)] = true
	end
	for index = 1, HangarConfig.CITY_BLOCKS do
		buildBuilding(index, burningSlots[index] == true, model)
	end

	for i = 1, HangarConfig.CITY_CHOPPERS do
		local chopperModel, rotor = buildChopperModel(model)
		table.insert(choppers, {
			model = chopperModel,
			radius = random:NextNumber(160, 300),
			speed = random:NextNumber(0.06, 0.12) * (if i % 2 == 0 then -1 else 1),
			phase = random:NextNumber(0, math.pi * 2),
			height = random:NextNumber(120, 210),
			centerX = center.X + random:NextNumber(-120, 120),
			centerZ = center.Z + random:NextNumber(HangarConfig.CITY_FAR_Z + 150, HangarConfig.CITY_NEAR_Z - 60),
			rotor = rotor,
		})
	end

	model.Parent = Workspace
	RunService.Heartbeat:Connect(step)
end

return CityDiorama
