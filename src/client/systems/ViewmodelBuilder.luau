--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local ViewmodelConfig = require(ReplicatedStorage.Shared.config.ViewmodelConfig)
local TexturesConfig = require(ReplicatedStorage.Shared.config.TexturesConfig)

local ViewmodelBuilder = {}

export type Node = {
	part: BasePart,
	parent: string?,
	rest: CFrame,
	bone: string?,
}

export type Rig = {
	model: Model,
	nodes: { Node },
	byBone: { [string]: Node },
	muzzle: Attachment,
	eject: Attachment,
	slideTravel: number,
	pumpTravel: number,
	class: string,
}

export type PoseOverrides = {
	slide: CFrame?,
	pump: CFrame?,
	magazine: CFrame?,
	supportHand: CFrame?,
}

local COLOR_METAL = Color3.fromRGB(78, 84, 94)
local COLOR_STEEL = Color3.fromRGB(158, 164, 174)
local COLOR_GRIP = Color3.fromRGB(58, 54, 50)
local COLOR_WOOD = Color3.fromRGB(158, 116, 70)
local COLOR_SLEEVE = Color3.fromRGB(112, 124, 96)
local COLOR_GLOVE = Color3.fromRGB(78, 78, 82)
local COLOR_SKIN = Color3.fromRGB(214, 172, 138)

local function applyTexture(part: BasePart, textureId: number, studsPerTile: number)
	if textureId <= 0 then
		return
	end
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top, Enum.NormalId.Bottom } do
		local texture = Instance.new("Texture")
		texture.Texture = "rbxassetid://" .. tostring(textureId)
		texture.Face = face
		texture.StudsPerTileU = studsPerTile
		texture.StudsPerTileV = studsPerTile
		texture.Transparency = 0.35
		texture.Parent = part
	end
end

local function scaled(rest: CFrame): CFrame
	local scale = ViewmodelConfig.SCALE
	return CFrame.new(rest.Position * scale) * (rest - rest.Position)
end

local function addNode(
	rig: Rig,
	className: string,
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	rest: CFrame,
	parentBone: string?,
	bone: string?
): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Size = size * ViewmodelConfig.SCALE
	rest = scaled(rest)
	part.Color = color
	part.Material = material
	if material == Enum.Material.Metal then
		part.Reflectance = 0.12
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = rig.model

	local node: Node = { part = part, parent = parentBone, rest = rest, bone = bone }
	table.insert(rig.nodes, node)
	if bone then
		rig.byBone[bone] = node
	end
	return part
end

local function buildArm(rig: Rig, side: number, handRest: CFrame, handBone: string, parentBone: string?, elbowPitch: number)
	addNode(rig, "Part", "Hand", Vector3.new(0.34, 0.26, 0.4), COLOR_GLOVE, Enum.Material.Fabric, handRest, parentBone, handBone)
	addNode(rig, "Part", "Thumb", Vector3.new(0.1, 0.1, 0.22), COLOR_GLOVE, Enum.Material.Fabric, CFrame.new(-side * 0.18, 0.1, 0.04), handBone)
	addNode(
		rig,
		"Part",
		"Fingers",
		Vector3.new(0.3, 0.12, 0.14),
		COLOR_GLOVE,
		Enum.Material.Fabric,
		CFrame.new(0, -0.12, -0.2) * CFrame.Angles(math.rad(-24), 0, 0),
		handBone
	)

	local wristBone = handBone .. "Wrist"
	addNode(rig, "Part", "Wrist", Vector3.new(0.28, 0.22, 0.24), COLOR_SKIN, Enum.Material.SmoothPlastic, CFrame.new(side * 0.06, -0.08, 0.2), handBone, wristBone)

	-- Only the forearm stub is ever inside a first-person frame; an upper arm would
	-- chain behind the camera and render as nothing.
	local forearmBone = handBone .. "Forearm"
	local forearmRest = CFrame.Angles(math.rad(elbowPitch), math.rad(side * 12), 0)
	addNode(rig, "Part", "ForearmPivot", Vector3.new(0.05, 0.05, 0.05), COLOR_SLEEVE, Enum.Material.Fabric, forearmRest, wristBone, forearmBone).Transparency = 1
	addNode(rig, "Part", "SleeveCuff", Vector3.new(0.36, 0.36, 0.2), COLOR_SLEEVE:Lerp(Color3.new(), 0.25), Enum.Material.Fabric, CFrame.new(0, 0, 0.1), forearmBone)
	applyTexture(addNode(rig, "Part", "Forearm", Vector3.new(0.32, 0.32, 0.95), COLOR_SLEEVE, Enum.Material.Fabric, CFrame.new(0, 0, 0.52), forearmBone), TexturesConfig.FABRIC, 0.7)
end

function ViewmodelBuilder.build(config: WeaponsConfig.WeaponConfig, camera: Camera): Rig
	local model = Instance.new("Model")
	model.Name = "Viewmodel"

	local rig: Rig = {
		model = model,
		nodes = {},
		byBone = {},
		muzzle = Instance.new("Attachment"),
		eject = Instance.new("Attachment"),
		slideTravel = 0.3,
		pumpTravel = 0.3,
		class = config.class,
	}

	local class = config.class
	local isPistol = class == "Pistol"
	local isShotgun = class == "Shotgun"

	local bodyLength = if isPistol then 0.82 else 1.9
	local bodyHeight = if isPistol then 0.36 else 0.42
	local barrelLength = if isPistol then 0.34 else 1.15
	if isShotgun then
		barrelLength = 1.35
	end

	local weaponRoot = addNode(rig, "Part", "WeaponRoot", Vector3.new(0.05, 0.05, 0.05), COLOR_METAL, Enum.Material.Metal, CFrame.identity, nil, "weaponRoot")
	weaponRoot.Transparency = 1

	local fill = ViewmodelConfig.FILL_LIGHT
	if fill.enabled then
		local light = Instance.new("PointLight")
		light.Name = "ViewmodelFill"
		light.Brightness = fill.brightness
		light.Range = fill.range
		light.Color = fill.color
		light.Shadows = false
		light.Parent = weaponRoot
	end

	local receiver = addNode(rig, "Part", "Receiver", Vector3.new(0.24, bodyHeight, bodyLength), COLOR_METAL, Enum.Material.Metal, CFrame.identity, "weaponRoot")
	applyTexture(receiver, TexturesConfig.METAL_PLATES, 0.9)

	local slideTopY = bodyHeight / 2 + 0.09
	if isPistol then
		rig.slideTravel = 0.3 * ViewmodelConfig.SCALE
		addNode(rig, "Part", "Slide", Vector3.new(0.26, 0.18, bodyLength + 0.1), COLOR_STEEL, Enum.Material.Metal, CFrame.new(0, bodyHeight / 2 + 0.05, 0), "weaponRoot", "slide")
	else
		addNode(rig, "Part", "TopRail", Vector3.new(0.14, 0.08, bodyLength * 0.8), COLOR_STEEL, Enum.Material.Metal, CFrame.new(0, bodyHeight / 2 + 0.04, 0), "weaponRoot")
		if class == "Rifle" or class == "SMG" then
			rig.slideTravel = 0.22 * ViewmodelConfig.SCALE
			addNode(rig, "Part", "BoltHandle", Vector3.new(0.12, 0.08, 0.16), COLOR_STEEL, Enum.Material.Metal, CFrame.new(0.17, 0.08, 0.2), "weaponRoot", "slide")
		end
	end

	local barrelY = if isPistol then 0.08 else 0.06
	local barrel = addNode(
		rig,
		"Part",
		"Barrel",
		Vector3.new(0.13, 0.13, barrelLength),
		COLOR_METAL,
		Enum.Material.Metal,
		CFrame.new(0, barrelY, -(bodyLength / 2 + barrelLength / 2 - 0.06)),
		"weaponRoot",
		"barrel"
	)

	if isShotgun then
		rig.pumpTravel = 0.28 * ViewmodelConfig.SCALE
		addNode(
			rig,
			"Part",
			"Pump",
			Vector3.new(0.3, 0.26, 0.62),
			COLOR_WOOD,
			Enum.Material.WoodPlanks,
			CFrame.new(0, -0.16, -(bodyLength / 2 + barrelLength * 0.34)),
			"weaponRoot",
			"pump"
		)
		addNode(
			rig,
			"Part",
			"MagTube",
			Vector3.new(0.13, 0.13, barrelLength * 0.8),
			COLOR_METAL,
			Enum.Material.Metal,
			CFrame.new(0, barrelY - 0.16, -(bodyLength / 2 + barrelLength * 0.42)),
			"weaponRoot"
		)
	elseif not isPistol then
		addNode(
			rig,
			"Part",
			"Handguard",
			Vector3.new(0.26, 0.3, barrelLength * 0.62),
			COLOR_GRIP,
			Enum.Material.SmoothPlastic,
			CFrame.new(0, -0.05, -(bodyLength / 2 + barrelLength * 0.3)),
			"weaponRoot"
		)
	end

	local sightY = if isPistol then slideTopY + 0.14 else bodyHeight / 2 + 0.12
	local frontSightZ = if isPistol then -(bodyLength / 2 - 0.06) else -(bodyLength / 2 + barrelLength - 0.15)
	addNode(rig, "Part", "FrontSight", Vector3.new(0.05, 0.12, 0.05), COLOR_METAL, Enum.Material.Metal, CFrame.new(0, sightY, frontSightZ), "weaponRoot")
	addNode(rig, "Part", "RearSight", Vector3.new(0.16, 0.1, 0.06), COLOR_METAL, Enum.Material.Metal, CFrame.new(0, sightY - 0.01, bodyLength / 2 - 0.12), "weaponRoot")
	if not isPistol then
		addNode(rig, "Part", "SightPost", Vector3.new(0.04, 0.14, 0.04), COLOR_METAL, Enum.Material.Metal, CFrame.new(0, barrelY + 0.1, frontSightZ), "weaponRoot")
	end

	local gripRest = CFrame.new(0, -bodyHeight / 2 - 0.26, bodyLength / 2 - 0.18) * CFrame.Angles(math.rad(-18), 0, 0)
	addNode(rig, "Part", "Grip", Vector3.new(0.24, 0.58, 0.28), COLOR_GRIP, Enum.Material.SmoothPlastic, gripRest, "weaponRoot", "grip")
	addNode(rig, "Part", "TriggerGuard", Vector3.new(0.06, 0.05, 0.34), COLOR_METAL, Enum.Material.Metal, CFrame.new(0, -bodyHeight / 2 - 0.12, bodyLength / 2 - 0.42), "weaponRoot")

	if isPistol then
		addNode(rig, "Part", "Magazine", Vector3.new(0.18, 0.5, 0.22), COLOR_STEEL, Enum.Material.Metal, CFrame.new(0, -0.06, 0), "grip", "magazine")
	elseif not isShotgun then
		addNode(
			rig,
			"Part",
			"Magazine",
			Vector3.new(0.2, 0.62, 0.32),
			COLOR_METAL,
			Enum.Material.Metal,
			CFrame.new(0, -bodyHeight / 2 - 0.28, -0.16) * CFrame.Angles(math.rad(10), 0, 0),
			"weaponRoot",
			"magazine"
		)
	end

	if not isPistol then
		local stockColor = if isShotgun then COLOR_WOOD else COLOR_GRIP
		local stockMaterial = if isShotgun then Enum.Material.WoodPlanks else Enum.Material.SmoothPlastic
		local stock = addNode(rig, "Part", "Stock", Vector3.new(0.22, 0.34, 0.8), stockColor, stockMaterial, CFrame.new(0, -0.08, bodyLength / 2 + 0.36) * CFrame.Angles(math.rad(-4), 0, 0), "weaponRoot")
		applyTexture(stock, if isShotgun then TexturesConfig.WOOD else TexturesConfig.FABRIC, 0.8)
		addNode(rig, "WedgePart", "StockComb", Vector3.new(0.22, 0.18, 0.46), stockColor, stockMaterial, CFrame.new(0, 0.17, bodyLength / 2 + 0.38) * CFrame.Angles(0, math.rad(180), 0), "weaponRoot")
	end

	local ejectionPort = addNode(
		rig,
		"Part",
		"EjectionPort",
		Vector3.new(0.02, 0.08, 0.16),
		Color3.fromRGB(20, 20, 22),
		Enum.Material.SmoothPlastic,
		CFrame.new(0.13, if isPistol then slideTopY - 0.1 else 0.06, if isPistol then 0.08 else 0.3),
		"weaponRoot"
	)

	buildArm(rig, 1, gripRest * CFrame.new(0.02, -0.04, 0.08), "handR", "weaponRoot", 52)

	local supportRest: CFrame
	local supportParent = "weaponRoot"
	if isShotgun then
		supportRest = CFrame.new(-0.02, -0.1, 0)
		supportParent = "pump"
	elseif isPistol then
		supportRest = gripRest * CFrame.new(-0.24, -0.06, 0.04) * CFrame.Angles(0, math.rad(12), 0)
	else
		supportRest = CFrame.new(-0.04, -0.26, -(bodyLength / 2 + barrelLength * 0.3)) * CFrame.Angles(math.rad(6), 0, 0)
	end
	buildArm(rig, -1, supportRest, "handL", supportParent, 46)

	rig.muzzle.Name = "Muzzle"
	rig.muzzle.Position = Vector3.new(0, 0, -barrelLength / 2 * ViewmodelConfig.SCALE)
	rig.muzzle.Parent = barrel
	rig.eject.Name = "Eject"
	rig.eject.Position = Vector3.new(0.1, 0.05, 0) * ViewmodelConfig.SCALE
	rig.eject.Parent = ejectionPort

	model.Parent = camera
	return rig
end

function ViewmodelBuilder.pose(rig: Rig, rootCFrame: CFrame, overrides: PoseOverrides)
	local resolved: { [string]: CFrame } = {}

	local function boneCFrame(boneName: string?): CFrame
		if not boneName then
			return rootCFrame
		end
		local cached = resolved[boneName]
		if cached then
			return cached
		end
		local node = rig.byBone[boneName]
		if not node then
			return rootCFrame
		end
		local parentCFrame = boneCFrame(node.parent)
		local offset = node.rest
		if boneName == "slide" and overrides.slide then
			offset = node.rest * overrides.slide
		elseif boneName == "pump" and overrides.pump then
			offset = node.rest * overrides.pump
		elseif boneName == "magazine" and overrides.magazine then
			offset = node.rest * overrides.magazine
		elseif boneName == "handL" and overrides.supportHand then
			offset = node.rest * overrides.supportHand
		end
		local result = parentCFrame * offset
		resolved[boneName] = result
		return result
	end

	for _, node in rig.nodes do
		local parentCFrame = boneCFrame(node.parent)
		if node.bone then
			node.part.CFrame = boneCFrame(node.bone)
		else
			node.part.CFrame = parentCFrame * node.rest
		end
	end
end

return ViewmodelBuilder
