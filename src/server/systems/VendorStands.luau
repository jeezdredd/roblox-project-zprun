--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local VendorsConfig = require(ReplicatedStorage.Shared.config.VendorsConfig)

local VendorStands = {}

local ROOM_WIDTH = 16
local ROOM_DEPTH = 12
local ROOM_HEIGHT = 9

local WALL_COLOR = Color3.fromRGB(58, 60, 66)
local UNIFORM_COLOR = Color3.fromRGB(80, 92, 70)

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

local function makeSign(adornee: BasePart, title: string, subtitle: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VendorSign"
	billboard.Size = UDim2.fromScale(9, 2.6)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	billboard.MaxDistance = 90
	billboard.Adornee = adornee
	billboard.Parent = adornee

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 0.6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Text = title
	nameLabel.Parent = billboard

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.fromScale(1, 0.34)
	subLabel.Position = UDim2.fromScale(0, 0.63)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.TextScaled = true
	subLabel.TextColor3 = Color3.fromRGB(180, 180, 185)
	subLabel.TextStrokeTransparency = 0.6
	subLabel.Text = subtitle
	subLabel.Parent = billboard
end

local function buildMannequin(base: CFrame, uniformColor: Color3, parent: Instance)
	createPart("Legs", Vector3.new(1.8, 2, 0.9), base * CFrame.new(0, 1.9, 0), Color3.fromRGB(45, 48, 52), Enum.Material.Fabric, parent)
	createPart("Torso", Vector3.new(2, 2.4, 1), base * CFrame.new(0, 4.1, 0), uniformColor, Enum.Material.Fabric, parent)
	for _, sign in { -1, 1 } do
		createPart("Arm", Vector3.new(0.7, 2.2, 0.8), base * CFrame.new(sign * 1.4, 4.1, 0), uniformColor, Enum.Material.Fabric, parent)
	end
	createPart("Head", Vector3.new(1.1, 1.1, 1.1), base * CFrame.new(0, 5.9, 0), Color3.fromRGB(205, 170, 140), Enum.Material.SmoothPlastic, parent)
	createPart("Cap", Vector3.new(1.3, 0.4, 1.3), base * CFrame.new(0, 6.5, 0), uniformColor:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Fabric, parent)
end

local function buildRoomShell(base: CFrame, config: VendorsConfig.VendorConfig, wallColor: Color3, parent: Instance): Part
	createPart("RoomPad", Vector3.new(ROOM_WIDTH, 0.4, ROOM_DEPTH), base * CFrame.new(0, 0.7, 0), Color3.fromRGB(66, 68, 74), Enum.Material.DiamondPlate, parent)
	createPart("RoomBack", Vector3.new(ROOM_WIDTH, ROOM_HEIGHT, 1), base * CFrame.new(0, ROOM_HEIGHT / 2 + 0.9, ROOM_DEPTH / 2 - 0.5), wallColor, Enum.Material.Metal, parent)
	for _, sign in { -1, 1 } do
		createPart("RoomSide", Vector3.new(1, ROOM_HEIGHT, ROOM_DEPTH), base * CFrame.new(sign * (ROOM_WIDTH / 2 - 0.5), ROOM_HEIGHT / 2 + 0.9, 0), wallColor, Enum.Material.Metal, parent)
	end
	createPart("RoomCeiling", Vector3.new(ROOM_WIDTH, 1, ROOM_DEPTH), base * CFrame.new(0, ROOM_HEIGHT + 1.4, 0), wallColor:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Metal, parent)

	local ceilingLamp = createPart("RoomLamp", Vector3.new(3, 0.3, 3), base * CFrame.new(0, ROOM_HEIGHT + 0.8, 0), Color3.fromRGB(255, 240, 210), Enum.Material.Neon, parent)
	ceilingLamp.CanCollide = false
	ceilingLamp.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 236, 205)
	light.Range = 22
	light.Brightness = 1.5
	light.Parent = ceilingLamp

	local signStrip = createPart("SignStrip", Vector3.new(ROOM_WIDTH - 2, 1.2, 0.4), base * CFrame.new(0, ROOM_HEIGHT + 0.6, -ROOM_DEPTH / 2 + 0.4), config.color, Enum.Material.Neon, parent)
	signStrip.CanCollide = false
	local accent = Instance.new("PointLight")
	accent.Color = config.color
	accent.Range = 14
	accent.Brightness = 1
	accent.Parent = signStrip

	local counter = createPart("Counter", Vector3.new(10, 1, 2.4), base * CFrame.new(0, 3, -1.5), WALL_COLOR:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Metal, parent)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VendorPrompt"
	prompt.ActionText = "Coming soon"
	prompt.ObjectText = config.displayName
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	makeSign(counter, config.displayName, config.subtitle)
	buildMannequin(base * CFrame.new(0, 0.9, 1.5), UNIFORM_COLOR, parent)

	return counter
end

local function buildMedbayInterior(base: CFrame, parent: Instance)
	for _, sign in { -1, 1 } do
		createPart("Bed", Vector3.new(3, 1, 5.5), base * CFrame.new(sign * 5, 1.6, 2), Color3.fromRGB(235, 235, 238), Enum.Material.SmoothPlastic, parent)
		createPart("Pillow", Vector3.new(2.4, 0.5, 1.4), base * CFrame.new(sign * 5, 2.3, 4), Color3.fromRGB(200, 210, 220), Enum.Material.Fabric, parent)
	end
	local crossV = createPart("CrossV", Vector3.new(0.8, 2.4, 0.3), base * CFrame.new(0, 6.5, ROOM_DEPTH / 2 - 1.1), Color3.fromRGB(220, 50, 50), Enum.Material.Neon, parent)
	crossV.CanCollide = false
	local crossH = createPart("CrossH", Vector3.new(2.4, 0.8, 0.3), base * CFrame.new(0, 6.5, ROOM_DEPTH / 2 - 1.1), Color3.fromRGB(220, 50, 50), Enum.Material.Neon, parent)
	crossH.CanCollide = false
end

local function buildWeaponRack(base: CFrame, parent: Instance)
	createPart("RackBoard", Vector3.new(10, 5, 0.4), base * CFrame.new(0, 5.5, ROOM_DEPTH / 2 - 1.2), Color3.fromRGB(70, 56, 40), Enum.Material.WoodPlanks, parent)
	for i = 1, 4 do
		local x = (i - 2.5) * 2.2
		createPart(
			"Rifle",
			Vector3.new(0.35, 3.4, 0.3),
			base * CFrame.new(x, 5.5, ROOM_DEPTH / 2 - 1.5) * CFrame.Angles(0, 0, math.rad(12)),
			Color3.fromRGB(40, 40, 44),
			Enum.Material.Metal,
			parent
		)
	end
end

local function buildGunsmithInterior(base: CFrame, parent: Instance)
	createPart("Workbench", Vector3.new(6, 1, 2.2), base * CFrame.new(2, 2.8, 3), Color3.fromRGB(96, 76, 52), Enum.Material.WoodPlanks, parent)
	createPart("Vice", Vector3.new(1, 1, 1), base * CFrame.new(3.5, 3.8, 3), Color3.fromRGB(110, 110, 116), Enum.Material.Metal, parent)
	createPart("Pegboard", Vector3.new(6, 3.5, 0.3), base * CFrame.new(2, 5.8, ROOM_DEPTH / 2 - 1.2), Color3.fromRGB(120, 96, 66), Enum.Material.WoodPlanks, parent)
	for i = 1, 3 do
		createPart("Tool", Vector3.new(0.4, 1.4, 0.3), base * CFrame.new(0.8 + i, 5.8, ROOM_DEPTH / 2 - 1.45), Color3.fromRGB(60, 62, 66), Enum.Material.Metal, parent)
	end
end

local function buildSodaInterior(base: CFrame, parent: Instance)
	local machine = createPart("SodaVendor", Vector3.new(4, 7, 2.4), base * CFrame.new(-4, 4.4, 3), Color3.fromRGB(180, 40, 40), Enum.Material.SmoothPlastic, parent)
	local panel = createPart("SodaPanel", Vector3.new(2.8, 4.5, 0.2), base * CFrame.new(-4, 4.9, 1.75), Color3.fromRGB(255, 120, 110), Enum.Material.Neon, parent)
	panel.CanCollide = false
	createPart("SodaSlot", Vector3.new(2.8, 1, 0.3), base * CFrame.new(-4, 1.9, 1.8), Color3.fromRGB(40, 40, 44), Enum.Material.Metal, parent)
	local _ = machine
end

local function buildBubblegumInterior(base: CFrame, parent: Instance)
	createPart("GumBase", Vector3.new(2.6, 3, 2.6), base * CFrame.new(-4, 2.4, 3), Color3.fromRGB(180, 90, 160), Enum.Material.SmoothPlastic, parent)
	local globe = Instance.new("Part")
	globe.Name = "GumGlobe"
	globe.Shape = Enum.PartType.Ball
	globe.Size = Vector3.new(2.8, 2.8, 2.8)
	globe.CFrame = base * CFrame.new(-4, 5.3, 3)
	globe.Anchored = true
	globe.Color = Color3.fromRGB(220, 230, 240)
	globe.Material = Enum.Material.Glass
	globe.Transparency = 0.5
	globe.Parent = parent
	local gumColors = { Color3.fromRGB(230, 80, 80), Color3.fromRGB(80, 160, 230), Color3.fromRGB(240, 200, 80), Color3.fromRGB(120, 210, 120) }
	for i, color in gumColors do
		local gum = Instance.new("Part")
		gum.Shape = Enum.PartType.Ball
		gum.Size = Vector3.new(0.7, 0.7, 0.7)
		gum.CFrame = base * CFrame.new(-4 + (i - 2.5) * 0.4, 4.6 + (i % 2) * 0.5, 3)
		gum.Anchored = true
		gum.CanCollide = false
		gum.Color = color
		gum.Material = Enum.Material.SmoothPlastic
		gum.Parent = parent
	end
end

local function buildShootingRange(base: CFrame, parent: Instance)
	local rangeBase = base * CFrame.new(-(ROOM_WIDTH + 14) / 2 - 6, 0, 0)
	createPart("RangePad", Vector3.new(14, 0.4, ROOM_DEPTH), rangeBase * CFrame.new(0, 0.7, 0), Color3.fromRGB(52, 54, 60), Enum.Material.Concrete, parent)
	for _, sign in { -1, 1 } do
		createPart("RangeRail", Vector3.new(0.8, 3, ROOM_DEPTH), rangeBase * CFrame.new(sign * 6.6, 2.4, 0), WALL_COLOR, Enum.Material.Metal, parent)
	end
	createPart("RangeBack", Vector3.new(14, 6, 1), rangeBase * CFrame.new(0, 3.9, ROOM_DEPTH / 2 - 0.5), Color3.fromRGB(48, 50, 56), Enum.Material.Metal, parent)

	for i = 1, 3 do
		local x = (i - 2) * 4
		buildMannequin(rangeBase * CFrame.new(x, 0.9, 3.4), Color3.fromRGB(88, 122, 82), parent)
	end

	local rangeSign = createPart("RangeSign", Vector3.new(10, 1.2, 0.4), rangeBase * CFrame.new(0, 7.2, -ROOM_DEPTH / 2 + 0.6), Color3.fromRGB(230, 160, 60), Enum.Material.Neon, parent)
	rangeSign.CanCollide = false
	makeSign(rangeSign, "Shooting Range", "Test weapons — SOON")
end

local function buildRoom(config: VendorsConfig.VendorConfig, parent: Instance)
	local base = CFrame.new(HangarConfig.HUB_CENTER + config.offset) * CFrame.Angles(0, config.rotationY, 0)
	local wallColor = if config.id == "Medbay" then Color3.fromRGB(210, 214, 218) else WALL_COLOR

	buildRoomShell(base, config, wallColor, parent)

	if config.id == "Medbay" then
		buildMedbayInterior(base, parent)
	elseif config.id == "WeaponDealer" then
		buildWeaponRack(base, parent)
	elseif config.id == "Gunsmith" then
		buildGunsmithInterior(base, parent)
		buildShootingRange(base, parent)
	elseif config.id == "SodaMachine" then
		buildSodaInterior(base, parent)
	elseif config.id == "BubblegumMachine" then
		buildBubblegumInterior(base, parent)
	end
end

function VendorStands.build(): Model
	local model = Instance.new("Model")
	model.Name = "Vendors"
	for _, id in VendorsConfig.order do
		local config = VendorsConfig.get(id)
		if config then
			buildRoom(config, model)
		end
	end
	model.Parent = Workspace
	return model
end

return VendorStands
