--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local ViewmodelConfig = require(ReplicatedStorage.Shared.config.ViewmodelConfig)
local TexturesConfig = require(ReplicatedStorage.Shared.config.TexturesConfig)

local ViewmodelBuilder = {}

export type Node = {
	part: BasePart,
	parent: string?,
	rest: CFrame,
	bone: string?,
	motor: Motor6D?,
}

export type Rig = {
	model: Model,
	root: BasePart,
	animator: Animator,
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
	-- authored pose offsets from AnimationSequencer, keyed by bone name; they
	-- multiply the bone's rest transform and stack with the mechanical overrides
	bones: { [string]: CFrame }?,
	-- An Animator drives Motor6D.Transform, and so do we. Writing both in the same frame
	-- means the later write wins and the clip appears to do nothing. When a clip owns the
	-- bones, we keep the root - which carries sway, bob and recoil - and leave the joints
	-- to it.
	animated: boolean?,
}

local COLOR_METAL = Color3.fromRGB(78, 84, 94)
local COLOR_STEEL = Color3.fromRGB(104, 110, 121)
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

local NIGHT_ATTRIBUTE = "NightMission"

-- One helper for both build paths. The fill is what makes the weapon readable against a
-- bright desert sky, but under the Night modifier it lights the player permanently and
-- the flashlight beam stops registering, so it tracks the mission attribute live rather
-- than being decided once at equip time.
local function attachFillLight(part: BasePart)
	local fill = ViewmodelConfig.FILL_LIGHT
	if not fill.enabled then
		return
	end

	local light = Instance.new("PointLight")
	light.Name = "ViewmodelFill"
	light.Brightness = fill.brightness
	light.Range = fill.range
	light.Color = fill.color
	light.Shadows = false

	local function refresh()
		light.Enabled = not (fill.disableAtNight and Workspace:GetAttribute(NIGHT_ATTRIBUTE) == true)
	end
	refresh()
	light.Parent = part

	local connection: RBXScriptConnection? = nil
	connection = Workspace:GetAttributeChangedSignal(NIGHT_ATTRIBUTE):Connect(function()
		if light.Parent == nil then
			if connection then
				connection:Disconnect()
			end
			return
		end
		refresh()
	end)
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
	-- Only the root is anchored. A joint cannot move an anchored part, so every
	-- other piece hangs off the root through the joint chain.
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = rig.model

	local parentNode = if parentBone then rig.byBone[parentBone] else nil
	local parentPart: BasePart = if parentNode then parentNode.part else rig.root
	part.CFrame = parentPart.CFrame * rest

	local node: Node = { part = part, parent = parentBone, rest = rest, bone = bone }

	if bone then
		-- Animatable joints are Motor6D and carry the bone name, so a published
		-- Roblox animation targeting the same names drives this rig unchanged.
		local motor = Instance.new("Motor6D")
		motor.Name = bone
		motor.Part0 = parentPart
		motor.Part1 = part
		motor.C0 = rest
		motor.Parent = parentPart
		node.motor = motor
		rig.byBone[bone] = node
	else
		local weld = Instance.new("Weld")
		weld.Name = name
		weld.Part0 = parentPart
		weld.Part1 = part
		weld.C0 = rest
		weld.Parent = parentPart
	end

	table.insert(rig.nodes, node)
	return part
end

-- Adopts a part that already exists, rather than creating one. This is the only way to
-- get mesh geometry into the rig: MeshPart.MeshId cannot be written by a script, so the
-- meshes arrive as instances mounted by Rojo and we join them here.
local function adoptNode(rig: Rig, part: BasePart, rest: CFrame, parentBone: string?, bone: string?)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = rig.model

	local parentNode = if parentBone then rig.byBone[parentBone] else nil
	local parentPart: BasePart = if parentNode then parentNode.part else rig.root
	part.CFrame = parentPart.CFrame * rest

	local node: Node = { part = part, parent = parentBone, rest = rest, bone = bone }
	if bone then
		local motor = Instance.new("Motor6D")
		motor.Name = bone
		motor.Part0 = parentPart
		motor.Part1 = part
		motor.C0 = rest
		motor.Parent = parentPart
		node.motor = motor
		rig.byBone[bone] = node
	else
		local weld = Instance.new("Weld")
		weld.Name = part.Name
		weld.Part0 = parentPart
		weld.Part1 = part
		weld.C0 = rest
		weld.Parent = parentPart
	end
	table.insert(rig.nodes, node)
end

-- Mesh geometry for a class, if Rojo has mounted any. `Main` is the hub the rest hangs
-- off, and the three moving pieces take the same bone names the procedural rig used, so
-- PoseLibrary and the spring layer carry over untouched.
local MESH_BONES: { [string]: string } = {
	Main = "weaponRoot",
	Slide = "slide",
	Magazine = "magazine",
	Barrel = "barrel",
	Grip = "grip",
}

local function buildMeshWeapon(rig: Rig, class: string, camera: Camera): boolean
	local folder = ReplicatedStorage:FindFirstChild("ViewModels")
	local template = if folder then folder:FindFirstChild(class) else nil
	if not template or not template:IsA("Model") then
		return false
	end

	local clone = template:Clone()
	-- The mounted template ships its own joints so it reads correctly in Studio. We
	-- rebuild them here against this rig's root, and leaving the originals in place
	-- would put two Motor6Ds on the same part - which over-constrains the rig and stops
	-- an Animator driving it at all.
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("Motor6D") or descendant:IsA("Weld") or descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		end
	end

	local main = clone:FindFirstChild("Main")
	if not main or not main:IsA("BasePart") then
		clone:Destroy()
		return false
	end
	local mainCFrame = main.CFrame

	-- The procedural path runs every size and rest offset through ViewmodelConfig.SCALE,
	-- and so do the arms below. Adopting the mesh at its authored size left a full-size
	-- weapon in hands shrunk to 0.72, and made the authored pose translations - which
	-- ViewmodelBuilder.pose also scales - land short.
	local scale = ViewmodelConfig.SCALE
	main.Size = main.Size * scale

	-- weaponRoot first, so every other piece can hang off it
	adoptNode(rig, main, CFrame.identity, nil, "weaponRoot")

	for _, child in clone:GetChildren() do
		if child:IsA("BasePart") then
			local rest = scaled(mainCFrame:ToObjectSpace(child.CFrame))
			child.Size = child.Size * scale
			adoptNode(rig, child, rest, "weaponRoot", MESH_BONES[child.Name])
		end
	end
	clone:Destroy()

	-- A template without a Barrel bone and without a Muzzle marker used to leave these
	-- nil and then index them, taking the client down at equip time. weaponRoot is always
	-- present by this point, so it is the floor.
	local rootNode = rig.byBone.weaponRoot
	local muzzle: Node? = rig.byBone.barrel
	local eject: Node? = nil
	local muzzleIsMarker = false
	for _, node in rig.nodes do
		if node.part.Name == "Muzzle" then
			muzzle = node
			muzzleIsMarker = true
		elseif node.part.Name == "CasingEject" then
			eject = node
		end
	end

	local muzzlePart = if muzzle then muzzle.part else rootNode.part
	local ejectPart = if eject then eject.part else rootNode.part

	rig.muzzle.Name = "Muzzle"
	-- A dedicated Muzzle marker already sits at the barrel tip, so it needs no offset.
	-- Falling back to the barrel itself means the attachment would otherwise sit at the
	-- part's centre and spawn the flash halfway down the weapon.
	rig.muzzle.Position = if muzzleIsMarker then Vector3.zero else Vector3.new(0, 0, -muzzlePart.Size.Z / 2)
	rig.muzzle.Parent = muzzlePart
	rig.eject.Name = "Eject"
	rig.eject.Parent = ejectPart
	rig.slideTravel = 0.3 * scale
	rig.pumpTravel = 0.3 * scale

	attachFillLight(main)

	local _ = camera
	return true
end

-- An Animator matches a clip's poses to parts by name, so two parts sharing a name
-- across the left and right arm stops the whole clip driving anything. Every part here
-- carries its side.
local function buildArm(rig: Rig, side: number, handRest: CFrame, handBone: string, parentBone: string?, elbowPitch: number)
	local suffix = if side > 0 then "R" else "L"
	addNode(rig, "Part", "Hand" .. suffix, Vector3.new(0.34, 0.26, 0.4), COLOR_GLOVE, Enum.Material.Fabric, handRest, parentBone, handBone)
	addNode(rig, "Part", "Thumb" .. suffix, Vector3.new(0.1, 0.1, 0.22), COLOR_GLOVE, Enum.Material.Fabric, CFrame.new(-side * 0.18, 0.1, 0.04), handBone)
	addNode(
		rig,
		"Part",
		"Fingers" .. suffix,
		Vector3.new(0.3, 0.12, 0.14),
		COLOR_GLOVE,
		Enum.Material.Fabric,
		CFrame.new(0, -0.12, -0.2) * CFrame.Angles(math.rad(-24), 0, 0),
		handBone
	)

	local wristBone = handBone .. "Wrist"
	addNode(rig, "Part", "Wrist" .. suffix, Vector3.new(0.28, 0.22, 0.24), COLOR_SKIN, Enum.Material.SmoothPlastic, CFrame.new(side * 0.06, -0.08, 0.2), handBone, wristBone)

	-- Only the forearm stub is ever inside a first-person frame; an upper arm would
	-- chain behind the camera and render as nothing.
	local forearmBone = handBone .. "Forearm"
	local forearmRest = CFrame.Angles(math.rad(elbowPitch), math.rad(side * 12), 0)
	addNode(rig, "Part", "ForearmPivot" .. suffix, Vector3.new(0.05, 0.05, 0.05), COLOR_SLEEVE, Enum.Material.Fabric, forearmRest, wristBone, forearmBone).Transparency = 1
	addNode(rig, "Part", "SleeveCuff" .. suffix, Vector3.new(0.3, 0.3, 0.16), COLOR_SLEEVE:Lerp(Color3.new(), 0.25), Enum.Material.Fabric, CFrame.new(0, 0, 0.08), forearmBone)
	-- a short stub: measured in Studio, a 0.95-long forearm sat 1.1 studs from the
	-- camera and covered 60% of screen height on its own
	applyTexture(addNode(rig, "Part", "Forearm" .. suffix, Vector3.new(0.28, 0.28, 0.5), COLOR_SLEEVE, Enum.Material.Fabric, CFrame.new(0, 0, 0.3), forearmBone), TexturesConfig.FABRIC, 0.7)
end

function ViewmodelBuilder.build(config: WeaponsConfig.WeaponConfig, camera: Camera): Rig
	local model = Instance.new("Model")
	model.Name = "Viewmodel"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.1, 0.1, 0.1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	local controller = Instance.new("AnimationController")
	controller.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = controller

	local rig: Rig = {
		model = model,
		root = root,
		animator = animator,
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

	-- Prefer real mesh geometry when Rojo has mounted some for this class; the procedural
	-- box weapon below stays as the fallback for classes that have no mesh yet.
	local usedMesh = buildMeshWeapon(rig, class, camera)
	local gripRest = if usedMesh
		then CFrame.new(0, -0.1, 0.05) * CFrame.Angles(math.rad(-12), 0, 0)
		else CFrame.new(0, -bodyHeight / 2 - 0.26, bodyLength / 2 - 0.18) * CFrame.Angles(math.rad(-18), 0, 0)

	if usedMesh then
		buildArm(rig, 1, gripRest * CFrame.new(0.02, -0.04, 0.08), "handR", "weaponRoot", 52)
		buildArm(rig, -1, gripRest * CFrame.new(-0.13, -0.02, 0.03) * CFrame.Angles(0, math.rad(14), 0), "handL", "weaponRoot", 46)
		model.Parent = camera
		return rig
	end

	local weaponRoot = addNode(rig, "Part", "WeaponRoot", Vector3.new(0.05, 0.05, 0.05), COLOR_METAL, Enum.Material.Metal, CFrame.identity, nil, "weaponRoot")
	weaponRoot.Transparency = 1

	attachFillLight(weaponRoot)

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
		supportRest = gripRest * CFrame.new(-0.13, -0.02, 0.03) * CFrame.Angles(0, math.rad(14), 0)
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

-- The root carries the whole procedural layer; every other piece follows through its
-- joint. Bone offsets go into Motor6D.Transform, which is the same channel an Animator
-- writes, so authored poses and a published clip cannot fight over the rest transform.
function ViewmodelBuilder.pose(rig: Rig, rootCFrame: CFrame, overrides: PoseOverrides)
	rig.root.CFrame = rootCFrame

	if overrides.animated then
		return
	end

	local bones = overrides.bones
	for boneName, node in rig.byBone do
		local motor = node.motor
		if not motor then
			continue
		end
		local offset = CFrame.identity
		if boneName == "slide" and overrides.slide then
			offset = overrides.slide
		elseif boneName == "pump" and overrides.pump then
			offset = overrides.pump
		elseif boneName == "magazine" and overrides.magazine then
			offset = overrides.magazine
		elseif boneName == "handL" and overrides.supportHand then
			offset = overrides.supportHand
		end

		local authored = if bones then bones[boneName] else nil
		if authored then
			-- PoseLibrary is authored in design units against the unscaled rig, so its
			-- translations have to follow ViewmodelConfig.SCALE like every rest offset.
			offset = offset * scaled(authored)
		end
		motor.Transform = offset
	end
end

return ViewmodelBuilder
