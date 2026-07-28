--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local TexturesConfig = require(ReplicatedStorage.Shared.config.TexturesConfig)
local TextureUtil = require(ReplicatedStorage.Shared.util.TextureUtil)
local VendorsConfig = require(ReplicatedStorage.Shared.config.VendorsConfig)

local VendorRooms = {}

local DOOR_HALF_WIDTH = 7
local ROOM_HEIGHT = 13
local COUNTER_HEIGHT = 3.2
local COUNTER_TOP_Y = 3.4
local UNIFORM_COLOR = Color3.fromRGB(80, 92, 70)
local STEEL = Color3.fromRGB(104, 108, 112)
local DARK_STEEL = Color3.fromRGB(56, 58, 62)

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

local function decor(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
end

local function makeSign(adornee: BasePart, title: string, subtitle: string, offsetY: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VendorSign"
	billboard.Size = UDim2.fromScale(14, 3.4)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	billboard.MaxDistance = 160
	billboard.Adornee = adornee
	billboard.Parent = adornee

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 0.6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	nameLabel.TextStrokeTransparency = 0.35
	nameLabel.Text = title
	nameLabel.Parent = billboard

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.fromScale(1, 0.34)
	subLabel.Position = UDim2.fromScale(0, 0.64)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.TextScaled = true
	subLabel.TextColor3 = Color3.fromRGB(186, 186, 190)
	subLabel.TextStrokeTransparency = 0.55
	subLabel.Text = subtitle
	subLabel.Parent = billboard
end

local function buildMannequin(base: CFrame, uniformColor: Color3, parent: Instance)
	makePart("Part", "Legs", Vector3.new(1.5, 1.9, 0.9), base * CFrame.new(0, 0.95, 0), Color3.fromRGB(45, 48, 52), Enum.Material.Fabric, parent)
	makePart("Part", "Torso", Vector3.new(1.7, 2.1, 0.95), base * CFrame.new(0, 2.95, 0), uniformColor, Enum.Material.Fabric, parent)
	for _, sign in { -1, 1 } do
		makePart("Part", "Arm", Vector3.new(0.6, 2, 0.7), base * CFrame.new(sign * 1.15, 2.85, 0), uniformColor, Enum.Material.Fabric, parent)
	end
	makePart("Part", "Head", Vector3.new(0.95, 0.95, 0.95), base * CFrame.new(0, 4.5, 0), Color3.fromRGB(205, 170, 140), Enum.Material.SmoothPlastic, parent)
	makePart("Part", "Cap", Vector3.new(1.15, 0.35, 1.15), base * CFrame.new(0, 5.05, 0), uniformColor:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Fabric, parent)
end

local function buildShell(base: CFrame, config: VendorsConfig.VendorConfig, parent: Instance): BasePart
	local halfW = config.size.X / 2
	local halfD = config.size.Z / 2
	local height = ROOM_HEIGHT
	local wall = config.wallColor
	local trim = wall:Lerp(Color3.new(0, 0, 0), 0.35)

	local isClinic = config.id == "Medbay"
	local floorTexture = if isClinic then TexturesConfig.TILES else TexturesConfig.CONCRETE
	local wallTexture = if isClinic then TexturesConfig.TILES else TexturesConfig.METAL_PLATES

	local pad = makePart("Part", "RoomFloor", Vector3.new(config.size.X, 0.5, config.size.Z), base * CFrame.new(0, 0.75, 0), wall:Lerp(Color3.new(0, 0, 0), 0.55), Enum.Material.Concrete, parent)
	decor(pad)
	TextureUtil.applyFace(pad, Enum.NormalId.Top, floorTexture, 8)

	local backWall = makePart("Part", "BackWall", Vector3.new(config.size.X, height, 1.5), base * CFrame.new(0, height / 2 + 1, halfD - 0.75), wall, Enum.Material.Metal, parent)
	TextureUtil.applySides(backWall, wallTexture, 10)
	for _, sign in { -1, 1 } do
		local sideWall = makePart("Part", "SideWall", Vector3.new(1.5, height, config.size.Z), base * CFrame.new(sign * (halfW - 0.75), height / 2 + 1, 0), wall, Enum.Material.Metal, parent)
		TextureUtil.applySides(sideWall, wallTexture, 10)
	end

	local frontSegment = (config.size.X - DOOR_HALF_WIDTH * 2) / 2
	for _, sign in { -1, 1 } do
		local frontWall = makePart(
			"Part",
			"FrontWall",
			Vector3.new(frontSegment, height, 1.5),
			base * CFrame.new(sign * (DOOR_HALF_WIDTH + frontSegment / 2), height / 2 + 1, -halfD + 0.75),
			wall,
			Enum.Material.Metal,
			parent
		)
		TextureUtil.applySides(frontWall, wallTexture, 10)
	end
	local doorHeight = 9
	makePart(
		"Part",
		"DoorLintel",
		Vector3.new(DOOR_HALF_WIDTH * 2, height - doorHeight, 1.5),
		base * CFrame.new(0, height - (height - doorHeight) / 2 + 1, -halfD + 0.75),
		wall,
		Enum.Material.Metal,
		parent
	)
	for _, sign in { -1, 1 } do
		local jamb = makePart("Part", "DoorJamb", Vector3.new(0.9, doorHeight, 2), base * CFrame.new(sign * DOOR_HALF_WIDTH, doorHeight / 2 + 1, -halfD + 0.75), HangarConfig.TRIM_COLOR, Enum.Material.Metal, parent)
		decor(jamb)
	end

	local ceiling = makePart("Part", "RoomCeiling", Vector3.new(config.size.X, 1, config.size.Z), base * CFrame.new(0, height + 1.5, 0), trim, Enum.Material.Metal, parent)
	decor(ceiling)

	for _, xOffset in { -halfW / 2, halfW / 2 } do
		for _, zOffset in { -halfD / 2, halfD / 2 } do
			local lamp = makePart("Part", "RoomLamp", Vector3.new(6, 0.4, 3), base * CFrame.new(xOffset, height + 0.6, zOffset), Color3.fromRGB(255, 246, 224), Enum.Material.Neon, parent)
			decor(lamp)
			lamp.CastShadow = false
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 240, 214)
			light.Range = 30
			light.Brightness = 1.1
			light.Parent = lamp
		end
	end

	local banner = makePart(
		"Part",
		"SignBanner",
		Vector3.new(config.size.X - 10, 2, 0.5),
		base * CFrame.new(0, height + 0.4, -halfD - 0.4),
		Color3.fromRGB(46, 46, 48),
		Enum.Material.Metal,
		parent
	)
	decor(banner)
	local stripe = makePart(
		"Part",
		"SignStripe",
		Vector3.new(config.size.X - 10, 0.4, 0.55),
		base * CFrame.new(0, height - 0.7, -halfD - 0.4),
		config.color:Lerp(Color3.fromRGB(40, 40, 42), 0.45),
		Enum.Material.SmoothPlastic,
		parent
	)
	decor(stripe)
	local statusLamp = makePart(
		"Part",
		"StatusLamp",
		Vector3.new(1.2, 0.8, 0.6),
		base * CFrame.new((config.size.X - 10) / 2 - 1.4, height + 0.4, -halfD - 0.7),
		Color3.fromRGB(236, 220, 190),
		Enum.Material.Neon,
		parent
	)
	decor(statusLamp)
	statusLamp.Transparency = 0.2
	local accent = Instance.new("PointLight")
	accent.Color = Color3.fromRGB(255, 236, 200)
	accent.Range = 14
	accent.Brightness = 0.7
	accent.Parent = statusLamp
	makeSign(banner, config.displayName, config.subtitle, 5)

	local counter = makePart("Part", "Counter", Vector3.new(13, COUNTER_HEIGHT, 2.4), base * CFrame.new(0, 1 + COUNTER_HEIGHT / 2, -halfD + 8), DARK_STEEL, Enum.Material.Metal, parent)
	TextureUtil.applySides(counter, TexturesConfig.METAL_PLATES, 5)
	local counterTop = makePart("Part", "CounterTop", Vector3.new(14, 0.4, 3.2), base * CFrame.new(0, 1 + COUNTER_TOP_Y, -halfD + 8), STEEL, Enum.Material.Metal, parent)
	TextureUtil.applyFace(counterTop, Enum.NormalId.Top, TexturesConfig.METAL_PLATES, 5)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VendorPrompt"
	prompt.ActionText = "Coming soon"
	prompt.ObjectText = config.displayName
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	buildMannequin(base * CFrame.new(0, 1, -halfD + 12), UNIFORM_COLOR, parent)

	return counter
end

local function buildMonitor(base: CFrame, parent: Instance)
	makePart("Part", "MonitorBody", Vector3.new(3.4, 2.6, 0.8), base, DARK_STEEL, Enum.Material.Metal, parent)
	local screen = makePart("Part", "MonitorScreen", Vector3.new(2.8, 2, 0.2), base * CFrame.new(0, 0, -0.5), Color3.fromRGB(20, 40, 30), Enum.Material.SmoothPlastic, parent)
	decor(screen)
	local line = makePart("Part", "MonitorLine", Vector3.new(2.4, 0.25, 0.12), base * CFrame.new(0, -0.2, -0.62), Color3.fromRGB(80, 255, 140), Enum.Material.Neon, parent)
	decor(line)
end

local function buildBed(base: CFrame, parent: Instance)
	makePart("Part", "BedFrame", Vector3.new(5, 1.4, 10), base * CFrame.new(0, 2.2, 0), STEEL, Enum.Material.Metal, parent)
	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			local leg = makePart("Part", "BedLeg", Vector3.new(0.5, 2.2, 0.5), base * CFrame.new(xSign * 2, 1.1, zSign * 4.2), DARK_STEEL, Enum.Material.Metal, parent)
			decor(leg)
		end
	end
	local mattress = makePart("Part", "Mattress", Vector3.new(4.8, 1.1, 9.6), base * CFrame.new(0, 3.4, 0), Color3.fromRGB(220, 224, 228), Enum.Material.Fabric, parent)
	TextureUtil.applyFace(mattress, Enum.NormalId.Top, TexturesConfig.FABRIC, 4)
	local blanket = makePart("Part", "Blanket", Vector3.new(5, 0.5, 5.6), base * CFrame.new(0, 4.1, -1.6), Color3.fromRGB(90, 128, 150), Enum.Material.Fabric, parent)
	decor(blanket)
	local pillow = makePart("Part", "Pillow", Vector3.new(3.4, 0.8, 1.9), base * CFrame.new(0, 4.3, 3.6), Color3.fromRGB(240, 240, 244), Enum.Material.Fabric, parent)
	decor(pillow)

	local pole = makePart("Part", "IvPole", Vector3.new(0.35, 9, 0.35), base * CFrame.new(3.4, 4.5, 3.4), STEEL, Enum.Material.Metal, parent)
	decor(pole)
	local bag = makePart("Part", "IvBag", Vector3.new(1.4, 2, 0.7), base * CFrame.new(3.4, 8, 3.4), Color3.fromRGB(210, 230, 220), Enum.Material.SmoothPlastic, parent)
	decor(bag)
	bag.Transparency = 0.35

	buildMonitor(base * CFrame.new(-3.6, 6, 3.6), parent)
end

local function buildMedbay(base: CFrame, size: Vector3, parent: Instance)
	local halfW = size.X / 2
	local halfD = size.Z / 2

	for i = 1, 4 do
		local x = -halfW + 8 + (i - 1) * 12
		buildBed(base * CFrame.new(x, 1, halfD - 9), parent)
		if i < 4 then
			local curtain = makePart("Part", "Curtain", Vector3.new(0.3, 11, 11), base * CFrame.new(x + 6, 6.5, halfD - 9), Color3.fromRGB(150, 190, 200), Enum.Material.Fabric, parent)
			curtain.Transparency = 0.45
			decor(curtain)
		end
	end

	makePart("Part", "OpTable", Vector3.new(5, 1, 11), base * CFrame.new(halfW - 12, 4, -2), Color3.fromRGB(200, 206, 210), Enum.Material.Metal, parent)
	makePart("Part", "OpTableBase", Vector3.new(2.4, 3.5, 2.4), base * CFrame.new(halfW - 12, 2, -2), STEEL, Enum.Material.Metal, parent)
	local opLamp = makePart("Part", "OpLamp", Vector3.new(6, 0.8, 6), base * CFrame.new(halfW - 12, 12, -2), Color3.fromRGB(255, 252, 240), Enum.Material.Neon, parent)
	decor(opLamp)
	local opLight = Instance.new("SpotLight")
	opLight.Face = Enum.NormalId.Bottom
	opLight.Range = 34
	opLight.Brightness = 4
	opLight.Angle = 70
	opLight.Parent = opLamp

	for i = 0, 2 do
		makePart("Part", "MedCabinet", Vector3.new(6, 12, 3), base * CFrame.new(-halfW + 4, 7, -halfD + 14 + i * 9), Color3.fromRGB(226, 230, 232), Enum.Material.SmoothPlastic, parent)
		local glass = makePart("Part", "CabinetGlass", Vector3.new(5, 6, 0.3), base * CFrame.new(-halfW + 6.6, 9, -halfD + 14 + i * 9), Color3.fromRGB(180, 210, 220), Enum.Material.Glass, parent)
		glass.Transparency = 0.5
		decor(glass)
	end

	for i = 0, 2 do
		local crate = makePart("Part", "MedCrate", Vector3.new(4, 3.4, 4), base * CFrame.new(halfW - 6, 2.6, halfD - 8 - i * 5), Color3.fromRGB(236, 236, 238), Enum.Material.SmoothPlastic, parent)
		local crossV = makePart("Part", "CrateCross", Vector3.new(0.6, 2, 0.2), base * CFrame.new(halfW - 8.1, 2.6, halfD - 8 - i * 5) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(220, 50, 50), Enum.Material.SmoothPlastic, parent)
		decor(crossV)
		decor(crate)
	end

	local crossV = makePart("Part", "CrossV", Vector3.new(2.4, 9, 0.5), base * CFrame.new(0, 12, halfD - 2), Color3.fromRGB(230, 55, 55), Enum.Material.Neon, parent)
	decor(crossV)
	local crossH = makePart("Part", "CrossH", Vector3.new(9, 2.4, 0.5), base * CFrame.new(0, 12, halfD - 2), Color3.fromRGB(230, 55, 55), Enum.Material.Neon, parent)
	decor(crossH)
end

local function buildRifle(base: CFrame, parent: Instance)
	local body = makePart("Part", "RifleBody", Vector3.new(0.4, 0.5, 4.4), base, Color3.fromRGB(42, 42, 46), Enum.Material.Metal, parent)
	decor(body)
	local stock = makePart("Part", "RifleStock", Vector3.new(0.4, 0.9, 1.4), base * CFrame.new(0, -0.2, -2.4), Color3.fromRGB(72, 52, 38), Enum.Material.Wood, parent)
	decor(stock)
	local mag = makePart("Part", "RifleMag", Vector3.new(0.35, 1.2, 0.7), base * CFrame.new(0, -0.8, 0.2), Color3.fromRGB(36, 36, 40), Enum.Material.Metal, parent)
	decor(mag)
end

local function buildAmmoStack(base: CFrame, parent: Instance)
	for i = 0, 2 do
		local crate = makePart("Part", "AmmoCrate", Vector3.new(4.4, 2.6, 7), base * CFrame.new(0, 1.3 + i * 2.7, i * 0.4), Color3.fromRGB(92, 100, 74), Enum.Material.WoodPlanks, parent)
		TextureUtil.applyAll(crate, TexturesConfig.WOOD, 4)
		local strap = makePart("Part", "CrateStrap", Vector3.new(4.6, 0.4, 1), base * CFrame.new(0, 1.3 + i * 2.7, i * 0.4), Color3.fromRGB(52, 56, 44), Enum.Material.Metal, parent)
		decor(strap)
		decor(crate)
	end
end

local function buildWeaponDealer(base: CFrame, size: Vector3, parent: Instance)
	local halfW = size.X / 2
	local halfD = size.Z / 2

	for _, sign in { -1, 1 } do
		makePart("Part", "RackBoard", Vector3.new(1, 12, 26), base * CFrame.new(sign * (halfW - 2.4), 8, 2), Color3.fromRGB(74, 58, 42), Enum.Material.WoodPlanks, parent)
		for i = 0, 4 do
			buildRifle(base * CFrame.new(sign * (halfW - 3.6), 6 + (i % 2) * 4.5, -8 + i * 4.6) * CFrame.Angles(0, math.rad(90), math.rad(6)), parent)
		end
	end

	local display = makePart("Part", "DisplayCase", Vector3.new(24, 3, 6), base * CFrame.new(0, 2.6, halfD - 12), DARK_STEEL, Enum.Material.Metal, parent)
	local glass = makePart("Part", "DisplayGlass", Vector3.new(24, 3.4, 6), base * CFrame.new(0, 5.8, halfD - 12), Color3.fromRGB(190, 215, 225), Enum.Material.Glass, parent)
	glass.Transparency = 0.55
	decor(glass)
	decor(display)
	for i = 0, 3 do
		buildRifle(base * CFrame.new(-9 + i * 6, 4.6, halfD - 12) * CFrame.Angles(0, math.rad(90), 0), parent)
	end

	buildAmmoStack(base * CFrame.new(-halfW + 8, 1, halfD - 6), parent)
	buildAmmoStack(base * CFrame.new(halfW - 8, 1, halfD - 6), parent)

	local ammoSign = makePart("Part", "AmmoSign", Vector3.new(12, 3, 0.4), base * CFrame.new(0, 13, halfD - 2), Color3.fromRGB(150, 122, 52), Enum.Material.SmoothPlastic, parent)
	decor(ammoSign)
end

local function buildWorkbench(base: CFrame, parent: Instance)
	local benchTop = makePart("Part", "BenchTop", Vector3.new(16, 0.8, 5), base * CFrame.new(0, 4.4, 0), Color3.fromRGB(102, 80, 56), Enum.Material.WoodPlanks, parent)
	TextureUtil.applyFace(benchTop, Enum.NormalId.Top, TexturesConfig.WOOD, 5)
	for _, sign in { -1, 1 } do
		makePart("Part", "BenchLeg", Vector3.new(1, 4, 4.6), base * CFrame.new(sign * 7, 2.2, 0), DARK_STEEL, Enum.Material.Metal, parent)
	end
	local vice = makePart("Part", "Vice", Vector3.new(1.8, 1.8, 2.2), base * CFrame.new(-6, 5.7, 0), STEEL, Enum.Material.Metal, parent)
	decor(vice)
	local grinder = makePart("Part", "Grinder", Vector3.new(2.6, 2.2, 2), base * CFrame.new(6, 5.9, 0), Color3.fromRGB(120, 90, 60), Enum.Material.Metal, parent)
	decor(grinder)
	local tray = makePart("Part", "PartsTray", Vector3.new(3.4, 0.5, 2.6), base * CFrame.new(1.5, 5.1, 0), STEEL, Enum.Material.Metal, parent)
	decor(tray)
end

local function buildGunsmith(base: CFrame, size: Vector3, parent: Instance)
	local halfW = size.X / 2
	local halfD = size.Z / 2

	buildWorkbench(base * CFrame.new(-halfW + 14, 0, halfD - 10), parent)
	buildWorkbench(base * CFrame.new(-halfW + 14, 0, -2) * CFrame.Angles(0, math.rad(90), 0), parent)
	buildWorkbench(base * CFrame.new(halfW - 14, 0, halfD - 10), parent)

	makePart("Part", "Pegboard", Vector3.new(18, 10, 0.6), base * CFrame.new(-halfW + 14, 9, halfD - 2), Color3.fromRGB(118, 94, 64), Enum.Material.WoodPlanks, parent)
	for i = 0, 5 do
		local tool = makePart("Part", "Tool", Vector3.new(0.5, 2.2 + (i % 3) * 0.6, 0.4), base * CFrame.new(-halfW + 7 + i * 2.6, 9, halfD - 2.6), Color3.fromRGB(64, 66, 70), Enum.Material.Metal, parent)
		decor(tool)
	end

	buildAmmoStack(base * CFrame.new(-halfW + 6, 1, -halfD + 12), parent)
	buildAmmoStack(base * CFrame.new(halfW - 6, 1, -halfD + 12), parent)
	for i = 0, 2 do
		buildRifle(base * CFrame.new(-halfW + 24, 6 + i * 3.4, -halfD + 8) * CFrame.Angles(0, math.rad(90), 0), parent)
	end

	makePart("Part", "GunRack", Vector3.new(1, 12, 20), base * CFrame.new(halfW - 2.4, 8, -4), Color3.fromRGB(74, 58, 42), Enum.Material.WoodPlanks, parent)
	for i = 0, 3 do
		buildRifle(base * CFrame.new(halfW - 3.6, 5.5 + (i % 2) * 4.5, -10 + i * 4) * CFrame.Angles(0, math.rad(90), math.rad(6)), parent)
	end

	local rangePointer = makePart("Part", "RangePointer", Vector3.new(14, 2.2, 0.4), base * CFrame.new(0, 13, -halfD + 2), Color3.fromRGB(214, 200, 170), Enum.Material.SmoothPlastic, parent)
	decor(rangePointer)
	makeSign(rangePointer, "Shooting Range", "Outside — behind the hangar", 4)
end

local function buildVendingMachine(base: CFrame, bodyColor: Color3, panelColor: Color3, parent: Instance)
	makePart("Part", "MachineBody", Vector3.new(6, 11, 3.4), base * CFrame.new(0, 6, 0), bodyColor, Enum.Material.SmoothPlastic, parent)
	local panel = makePart("Part", "MachinePanel", Vector3.new(4.6, 7, 0.3), base * CFrame.new(0, 7.4, -1.85), panelColor, Enum.Material.Neon, parent)
	decor(panel)
	local slot = makePart("Part", "MachineSlot", Vector3.new(4.6, 1.4, 0.4), base * CFrame.new(0, 2.6, -1.9), Color3.fromRGB(38, 38, 42), Enum.Material.Metal, parent)
	decor(slot)
	local light = Instance.new("PointLight")
	light.Color = panelColor
	light.Range = 16
	light.Brightness = 1.1
	light.Parent = panel
end

local function buildTableSet(base: CFrame, parent: Instance)
	makePart("Part", "TableTop", Vector3.new(7, 0.6, 7), base * CFrame.new(0, 4, 0), Color3.fromRGB(120, 116, 110), Enum.Material.Metal, parent)
	makePart("Part", "TableLeg", Vector3.new(1.2, 4, 1.2), base * CFrame.new(0, 2, 0), DARK_STEEL, Enum.Material.Metal, parent)
	for _, offset in { Vector3.new(-5.5, 0, 0), Vector3.new(5.5, 0, 0), Vector3.new(0, 0, -5.5), Vector3.new(0, 0, 5.5) } do
		makePart("Part", "Stool", Vector3.new(2.4, 3, 2.4), base * CFrame.new(offset.X, 1.6, offset.Z), Color3.fromRGB(96, 84, 70), Enum.Material.Fabric, parent)
	end
end

local function buildCanteen(base: CFrame, size: Vector3, parent: Instance)
	local halfW = size.X / 2
	local halfD = size.Z / 2

	local colors = {
		{ Color3.fromRGB(180, 44, 44), Color3.fromRGB(255, 130, 120) },
		{ Color3.fromRGB(40, 90, 160), Color3.fromRGB(120, 190, 255) },
		{ Color3.fromRGB(200, 160, 40), Color3.fromRGB(255, 230, 140) },
	}
	for i, pair in colors do
		buildVendingMachine(base * CFrame.new(-halfW + 8 + (i - 1) * 8, 1, halfD - 4) * CFrame.Angles(0, math.pi, 0), pair[1], pair[2], parent)
	end

	buildTableSet(base * CFrame.new(halfW - 12, 1, halfD - 12), parent)
	buildTableSet(base * CFrame.new(halfW - 12, 1, 2), parent)
	buildTableSet(base * CFrame.new(halfW - 26, 1, halfD - 12), parent)

	makePart("Part", "Cooler", Vector3.new(5, 8, 4), base * CFrame.new(halfW - 5, 5, -halfD + 14), Color3.fromRGB(200, 210, 220), Enum.Material.SmoothPlastic, parent)
	local urn = makePart("Part", "CoffeeUrn", Vector3.new(2.6, 3.4, 2.6), base * CFrame.new(-6, 6.5, -halfD + 8), STEEL, Enum.Material.Metal, parent)
	decor(urn)
	local bin = makePart("Part", "TrashBin", Vector3.new(3, 4, 3), base * CFrame.new(-halfW + 5, 3, -halfD + 12), Color3.fromRGB(70, 74, 78), Enum.Material.Metal, parent)
	decor(bin)
end

local function buildGumballMachine(base: CFrame, gumColor: Color3, parent: Instance)
	makePart("Part", "GumPedestal", Vector3.new(2.6, 5, 2.6), base * CFrame.new(0, 3.5, 0), Color3.fromRGB(60, 62, 68), Enum.Material.Metal, parent)
	makePart("Part", "GumBase", Vector3.new(3.4, 2.6, 3.4), base * CFrame.new(0, 7.3, 0), Color3.fromRGB(190, 90, 160), Enum.Material.SmoothPlastic, parent)

	local globe = Instance.new("Part")
	globe.Name = "GumGlobe"
	globe.Shape = Enum.PartType.Ball
	globe.Size = Vector3.new(4, 4, 4)
	globe.CFrame = base * CFrame.new(0, 10.4, 0)
	globe.Anchored = true
	globe.CanCollide = false
	globe.Color = Color3.fromRGB(225, 235, 245)
	globe.Material = Enum.Material.Glass
	globe.Transparency = 0.45
	globe.Parent = parent

	local inner = Instance.new("Part")
	inner.Name = "GumFill"
	inner.Shape = Enum.PartType.Ball
	inner.Size = Vector3.new(3.2, 3.2, 3.2)
	inner.CFrame = base * CFrame.new(0, 10.2, 0)
	inner.Anchored = true
	inner.CanCollide = false
	inner.CanQuery = false
	inner.Color = gumColor
	inner.Material = Enum.Material.SmoothPlastic
	inner.Parent = parent
end

local function buildBubblegumStand(base: CFrame, size: Vector3, parent: Instance)
	local halfW = size.X / 2
	local halfD = size.Z / 2

	local gumColors = {
		Color3.fromRGB(230, 80, 90),
		Color3.fromRGB(90, 170, 240),
		Color3.fromRGB(240, 210, 80),
		Color3.fromRGB(130, 220, 130),
	}
	for i, color in gumColors do
		buildGumballMachine(base * CFrame.new(-halfW + 9 + (i - 1) * 9, 1, halfD - 8), color, parent)
	end

	makePart("Part", "PrizeShelf", Vector3.new(size.X - 14, 9, 3), base * CFrame.new(0, 6, halfD - 3), Color3.fromRGB(110, 96, 104), Enum.Material.WoodPlanks, parent)
	for i = 0, 6 do
		local box = makePart(
			"Part",
			"PrizeBox",
			Vector3.new(2.6, 2.6, 2.6),
			base * CFrame.new(-halfW + 10 + i * 5, if i % 2 == 0 then 8.4 else 4.4, halfD - 3),
			gumColors[(i % #gumColors) + 1],
			Enum.Material.SmoothPlastic,
			parent
		)
		decor(box)
	end

	buildTableSet(base * CFrame.new(halfW - 12, 1, -4), parent)
end

local function buildRoom(config: VendorsConfig.VendorConfig, parent: Instance)
	local base = CFrame.new(HangarConfig.HUB_CENTER + config.offset) * CFrame.Angles(0, config.rotationY, 0)
	buildShell(base, config, parent)

	if config.id == "Medbay" then
		buildMedbay(base, config.size, parent)
	elseif config.id == "WeaponDealer" then
		buildWeaponDealer(base, config.size, parent)
	elseif config.id == "Gunsmith" then
		buildGunsmith(base, config.size, parent)
	elseif config.id == "SodaMachine" then
		buildCanteen(base, config.size, parent)
	elseif config.id == "BubblegumMachine" then
		buildBubblegumStand(base, config.size, parent)
	end
end

function VendorRooms.build(): Model
	local model = Instance.new("Model")
	model.Name = "VendorRooms"
	for _, id in VendorsConfig.order do
		local config = VendorsConfig.get(id)
		if config then
			buildRoom(config, model)
		end
	end
	model.Parent = Workspace
	return model
end

return VendorRooms
