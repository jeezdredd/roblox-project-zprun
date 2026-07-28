--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local TexturesConfig = require(ReplicatedStorage.Shared.config.TexturesConfig)
local TextureUtil = require(ReplicatedStorage.Shared.util.TextureUtil)

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
local flickerBands: { { part: BasePart, phase: number, rate: number } } = {}
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
	TextureUtil.applyFace(ground, Enum.NormalId.Top, TexturesConfig.ASPHALT, 40)
end

local function makeFlameEmitter(parent: BasePart, size: number)
	local attachment = Instance.new("Attachment")
	attachment.Parent = parent

	local flame = Instance.new("ParticleEmitter")
	flame.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 120)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 130, 30)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 30, 10)),
	})
	flame.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	flame.Size = NumberSequence.new(size, size * 0.4)
	flame.Lifetime = NumberRange.new(1.2, 2.4)
	flame.Rate = 26
	flame.Speed = NumberRange.new(14, 26)
	flame.SpreadAngle = Vector2.new(18, 18)
	flame.Rotation = NumberRange.new(0, 360)
	flame.RotSpeed = NumberRange.new(-60, 60)
	flame.LightEmission = 1
	flame.LightInfluence = 0
	flame.Acceleration = Vector3.new(0, 12, 0)
	flame.Parent = attachment

	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(46, 42, 42))
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Size = NumberSequence.new(size * 1.4, size * 4)
	smoke.Lifetime = NumberRange.new(4, 7)
	smoke.Rate = 14
	smoke.Speed = NumberRange.new(16, 26)
	smoke.SpreadAngle = Vector2.new(22, 22)
	smoke.Acceleration = Vector3.new(random:NextNumber(-6, 6), 16, 0)
	smoke.LightInfluence = 0.4
	smoke.Parent = attachment
end

local function addFire(building: Part, height: number, withLight: boolean, parent: Instance)
	local top = building.Position + Vector3.new(0, height / 2 - 2, 0)
	local scale = math.clamp(building.Size.X / 4, 10, 26)

	local fireAnchor = makePart("FireAnchor", Vector3.new(2, 2, 2), CFrame.new(top), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, parent)
	fireAnchor.Transparency = 1
	makeFlameEmitter(fireAnchor, scale)

	if withLight then
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 130, 50)
		glow.Range = 160
		glow.Brightness = 4
		glow.Parent = fireAnchor
	end

	local sideAnchor = makePart(
		"FacadeFire",
		Vector3.new(2, 2, 2),
		CFrame.new(building.Position + Vector3.new(0, random:NextNumber(-height / 4, height / 4), -building.Size.Z / 2 - 1)),
		Color3.new(0, 0, 0),
		Enum.Material.SmoothPlastic,
		parent
	)
	sideAnchor.Transparency = 1
	makeFlameEmitter(sideAnchor, scale * 0.6)

	building.Color = building.Color:Lerp(Color3.fromRGB(30, 24, 22), 0.55)

	for i = 1, 3 do
		local windowGlow = makePart(
			"BurningWindow",
			Vector3.new(building.Size.X * 0.78, 5, 0.6),
			CFrame.new(building.Position + Vector3.new(0, -height / 3 + i * (height / 4), -building.Size.Z / 2 - 0.4)),
			Color3.fromRGB(255, 150, 60),
			Enum.Material.Neon,
			parent
		)
		windowGlow.CastShadow = false
	end
end

local function buildBuilding(index: number, burning: boolean, withLight: boolean, parent: Instance)
	local width = random:NextNumber(36, 86)
	local depth = random:NextNumber(36, 86)
	local height = random:NextNumber(50, 200)
	local x = center.X + random:NextNumber(-HangarConfig.CITY_HALF_WIDTH, HangarConfig.CITY_HALF_WIDTH)
	local z = center.Z + random:NextNumber(HangarConfig.CITY_FAR_Z, HangarConfig.CITY_NEAR_Z)
	local shade = random:NextInteger(42, 68)
	local isBrick = random:NextNumber() < 0.4

	local building = makePart(
		"CityBlock" .. index,
		Vector3.new(width, height, depth),
		CFrame.new(x, height / 2, z),
		if isBrick then Color3.fromRGB(shade + 26, shade - 6, shade - 12) else Color3.fromRGB(shade, shade, shade + 4),
		Enum.Material.Concrete,
		parent
	)
	TextureUtil.applySides(building, if isBrick then TexturesConfig.BRICKS else TexturesConfig.CONCRETE, 14)

	local bandCount = math.floor(height / 20)
	for i = 1, bandCount do
		if random:NextNumber() < 0.6 then
			local band = makePart(
				"CityWindows",
				Vector3.new(width * 0.84, 4.5, 0.5),
				CFrame.new(x, i * 20, z - depth / 2 - 0.3),
				Color3.fromRGB(255, 216, 150),
				Enum.Material.Neon,
				parent
			)
			band.Transparency = 0.2
			band.CastShadow = false

			if random:NextNumber() < 0.12 then
				local flickerPhase = random:NextNumber(0, math.pi * 2)
				local flickerRate = random:NextNumber(0.6, 2.4)
				table.insert(flickerBands, { part = band, phase = flickerPhase, rate = flickerRate })
			end
		end
	end

	if burning then
		addFire(building, height, withLight, parent)
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

	for _, band in flickerBands do
		if not band.part.Parent then
			continue
		end
		local wave = math.sin(elapsed * band.rate + band.phase)
		local flicker = math.sin(elapsed * band.rate * 7.3 + band.phase) * 0.15
		band.part.Transparency = math.clamp(0.2 + wave * 0.25 + flicker, 0.05, 0.85)
	end
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
	local burningOrder: { number } = {}
	while #burningOrder < HangarConfig.CITY_FIRES do
		local slot = random:NextInteger(1, HangarConfig.CITY_BLOCKS)
		if not burningSlots[slot] then
			burningSlots[slot] = true
			table.insert(burningOrder, slot)
		end
	end
	local lightSlots: { [number]: boolean } = {}
	for i = 1, math.min(HangarConfig.CITY_FIRE_LIGHTS, #burningOrder) do
		lightSlots[burningOrder[i]] = true
	end

	for index = 1, HangarConfig.CITY_BLOCKS do
		buildBuilding(index, burningSlots[index] == true, lightSlots[index] == true, model)
	end

	for i = 1, HangarConfig.CITY_CHOPPERS do
		local chopperModel, rotor = buildChopperModel(model)
		table.insert(choppers, {
			model = chopperModel,
			radius = random:NextNumber(HangarConfig.CHOPPER_RADIUS_MIN, HangarConfig.CHOPPER_RADIUS_MAX),
			speed = random:NextNumber(0.06, 0.12) * (if i % 2 == 0 then -1 else 1),
			phase = random:NextNumber(0, math.pi * 2),
			height = random:NextNumber(HangarConfig.CHOPPER_HEIGHT_MIN, HangarConfig.CHOPPER_HEIGHT_MAX),
			centerX = center.X + random:NextNumber(-120, 120),
			centerZ = center.Z + random:NextNumber(HangarConfig.CHOPPER_CENTER_FAR, HangarConfig.CHOPPER_CENTER_NEAR),
			rotor = rotor,
		})
	end

	model.Parent = Workspace
	RunService.Heartbeat:Connect(step)
end

return CityDiorama
