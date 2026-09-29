--!strict

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ZombiesConfig = require(ReplicatedStorage.Shared.config.ZombiesConfig)
local ZombieRigConfig = require(ReplicatedStorage.Shared.config.ZombieRigConfig)
local MeshTemplates = require(ReplicatedStorage.Shared.util.MeshTemplates)
local ZombieSkins = require(ReplicatedStorage.Shared.config.ZombieSkins)
local ZombieRigs = require(script.Parent.ZombieRigs)
local ZombieHitboxes = require(script.Parent.ZombieHitboxes)

local ZombieFactory = {}

-- Two rigs. The full R15 walker (15 textured MeshParts cut from a generated character,
-- see tools/zombie_rig) is used when every template in ReplicatedStorage.ZombieMeshes.Walker2
-- carries a real mesh id; otherwise the old reduced 7-part rig is built. The choice is
-- made once at require time, because ROOT_HEIGHT and HIP_HEIGHT depend on it.
local FULL_RIG = ZombieRigConfig.walker2
local FULL_SCALE = 0.92

local function fullTemplates(): Folder?
	local folder = ReplicatedStorage:FindFirstChild("ZombieMeshes")
	local set = folder and folder:FindFirstChild("Walker2")
	if not set then
		return nil
	end
	for partName in FULL_RIG.parts do
		local template = set:FindFirstChild(partName)
		if not template or not template:IsA("MeshPart") or template.MeshId == "rbxassetid://0" or template.MeshId == "" then
			return nil
		end
	end
	return set :: any
end

local fullSet = fullTemplates()
-- Roblox's glTF importer turns every uploaded mesh 180 degrees about Y (x and z negated,
-- measured on the walker2 and arm meshes 2026-09-28), so the zombie faced backwards with
-- its eyes on the back of its head. Each mesh part is turned back about its own centre,
-- and the joints are written so their frames stay axis-aligned in character space.
local GLTF_FLIP = CFrame.Angles(0, math.pi, 0)

local restPoint: (string, Vector3) -> Vector3
local armRest: (string, Vector3) -> CFrame
-- Rojo-mounted MeshParts render at the mesh's native size; load every zombie mesh
-- through MeshTemplates now so spawned zombies get correctly scaled parts.
local meshFolder = ReplicatedStorage:FindFirstChild("ZombieMeshes")
if meshFolder then
	MeshTemplates.prefetch(meshFolder)
end
-- The first zombies of a run can spawn before the loads finish, and a part cloned then
-- keeps the wrong size for its whole life. The first build waits for them instead.
local meshesSettled = meshFolder == nil
local function settleMeshes()
	if meshesSettled or not meshFolder or not coroutine.isyieldable() then
		return
	end
	MeshTemplates.waitFor(meshFolder, 6)
	meshesSettled = true
end
ZombieFactory.FULL_RIG = fullSet ~= nil

ZombieFactory.SCALE = if fullSet then FULL_SCALE else 0.86
ZombieFactory.ROOT_HEIGHT = if fullSet then (FULL_RIG.rootY + 1) * FULL_SCALE else 2.35 * 0.86
ZombieFactory.HIP_HEIGHT = if fullSet then FULL_RIG.rootY * FULL_SCALE else 2.35 * 0.86 - 0.86

local SCALE = if fullSet then FULL_SCALE else 0.86

-- The zombie clips (tools/animation_pipeline, Quaternius sources) are authored against a
-- T-pose: their shoulder rotations take a horizontal arm down to the sides. walker2's arms
-- are modelled hanging, so those same rotations swung each arm up and across the chest.
-- The arm chain is therefore rest-posed horizontally here, rotated about the shoulder so
-- that shoulder-to-wrist points straight out (-X left, +X right); with no clip playing the
-- zombie stands in a T-pose, with a clip it reads as authored.
local ARM_SIDES = {
	Left = { parts = { LeftUpperArm = true, LeftLowerArm = true, LeftHand = true }, out = Vector3.new(-1, 0, 0) },
	Right = { parts = { RightUpperArm = true, RightLowerArm = true, RightHand = true }, out = Vector3.new(1, 0, 0) },
}

local armTurn: { [string]: { shoulder: Vector3, turn: CFrame } } = {}
for side, info in ARM_SIDES do
	local shoulder, wrist
	for _, spec in FULL_RIG.joints do
		if spec.name == side .. "Shoulder" then
			shoulder = spec.pivot
		elseif spec.name == side .. "Wrist" then
			wrist = spec.pivot
		end
	end
	if shoulder and wrist then
		local hang = (wrist - shoulder).Unit
		local axis = hang:Cross(info.out)
		local angle = math.acos(math.clamp(hang:Dot(info.out), -1, 1))
		armTurn[side] = { shoulder = shoulder, turn = if axis.Magnitude > 1e-4 then CFrame.fromAxisAngle(axis.Unit, angle) else CFrame.identity }
	end
end

local function armSide(partName: string): string?
	for side, info in ARM_SIDES do
		if info.parts[partName] and armTurn[side] then
			return side
		end
	end
	return nil
end

-- a point of the arm chain moved into the T-pose (character space, scale 1)
restPoint = function(partName: string, point: Vector3): Vector3
	local side = armSide(partName)
	if not side then
		return point
	end
	local arm = armTurn[side]
	return arm.shoulder + arm.turn:VectorToWorldSpace(point - arm.shoulder)
end

-- rest CFrame (scaled) of a mesh part: glTF flip, plus the T-pose turn for arm parts
armRest = function(partName: string, centre: Vector3): CFrame
	local side = armSide(partName)
	local turn = if side then armTurn[side].turn else CFrame.identity
	return CFrame.new(restPoint(partName, centre) * SCALE) * turn * GLTF_FLIP
end

local TINTS = {
	Color3.fromRGB(38, 36, 32),
	Color3.fromRGB(92, 74, 54),
	Color3.fromRGB(64, 76, 56),
	Color3.fromRGB(70, 66, 78),
}

local variation = Random.new()

local ZOMBIE_GROUP = "Zombies"
local groupReady = false

local function ensureCollisionGroup()
	if groupReady or not RunService:IsServer() then
		return
	end
	groupReady = true
	pcall(function()
		PhysicsService:RegisterCollisionGroup(ZOMBIE_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(ZOMBIE_GROUP, ZOMBIE_GROUP, false)
	end)
end

local function meshTemplate(name: string): MeshPart?
	local folder = ReplicatedStorage:FindFirstChild("ZombieMeshes")
	local set = folder and folder:FindFirstChild("Walker")
	local template = set and set:FindFirstChild(name)
	if template and template:IsA("MeshPart") and template.MeshId ~= "rbxassetid://0" then
		return template
	end
	return nil
end

local function makePart(name: string, size: Vector3, position: Vector3, color: Color3, model: Model): BasePart
	local template = meshTemplate(name)
	local part: BasePart = if template then MeshTemplates.clone(template :: MeshPart) else Instance.new("Part")
	part.Name = name
	part.Anchored = false
	part.Size = size * SCALE
	part.CFrame = CFrame.new(position * SCALE)
	part.Color = color
	part.CanCollide = false
	part.CanQuery = false
	part.Parent = model
	return part
end

local function joint(name: string, part0: BasePart, part1: BasePart, pivot: Vector3, pitchDegrees: number?)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	local scaledPivot = pivot * SCALE
	motor.C0 = CFrame.new(scaledPivot - part0.Position) * CFrame.Angles(math.rad(pitchDegrees or 0), 0, 0)
	motor.C1 = CFrame.new(scaledPivot - part1.Position)
	motor.Parent = part0
end

local function attach(part: BasePart, anchor: BasePart, offset: CFrame)
	local weld = Instance.new("Weld")
	weld.Name = part.Name .. "Weld"
	weld.Part0 = anchor
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
end

local COLLIDING = { UpperTorso = true, LowerTorso = true }

local function buildFull(config: ZombiesConfig.ZombieConfig, set: Folder): Model
	local model = Instance.new("Model")
	model.Name = config.id
	model:SetAttribute("ZombieId", config.id)
	ensureCollisionGroup()

	local rootCentre = Vector3.new(0, FULL_RIG.rootY + 1, 0)
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1) * SCALE
	root.CFrame = CFrame.new(rootCentre * SCALE)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model

	local parts: { [string]: BasePart } = { HumanoidRootPart = root }
	local rests: { [string]: CFrame } = { HumanoidRootPart = CFrame.new(rootCentre * SCALE) }
	for partName, info in FULL_RIG.parts do
		local part = MeshTemplates.clone(set:FindFirstChild(partName) :: MeshPart)
		part.Anchored = false
		part.Size = info.size * SCALE
		local rest = armRest(partName, info.centre)
		part.CFrame = rest
		rests[partName] = rest
		-- limbs are what a bullet should hit (Head carries the headshot bonus); only the
		-- torso collides, and only against the player (zombies share a no-collide group)
		part.CanQuery = true
		part.CanTouch = false
		part.CanCollide = COLLIDING[partName] == true
		part.CollisionGroup = ZOMBIE_GROUP
		part.Massless = partName ~= "LowerTorso"
		part.Parent = model
		parts[partName] = part
	end

	for _, spec in FULL_RIG.joints do
		local motor = Instance.new("Motor6D")
		motor.Name = spec.name
		motor.Part0 = parts[spec.part0]
		motor.Part1 = parts[spec.part1]
		-- joint frames are axis-aligned at the (T-posed) pivot, whatever the parts' rotation
		local pivot = CFrame.new(restPoint(spec.part1, spec.pivot) * SCALE)
		motor.C0 = rests[spec.part0]:Inverse() * pivot
		motor.C1 = rests[spec.part1]:Inverse() * pivot
		motor.Parent = parts[spec.part0]
	end

	-- a faint glow in the eye sockets keeps the ITD read of eyes in the fog
	local head = parts.Head
	for _, sign in { -1, 1 } do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Size = Vector3.new(0.12, 0.07, 0.05) * SCALE
		eye.Color = config.eyeColor
		eye.Material = Enum.Material.Neon
		eye.Transparency = 0.35
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CanTouch = false
		eye.CastShadow = false
		eye.Massless = true
		-- the head part is turned by GLTF_FLIP, so the offset is given in character space
		local offset = GLTF_FLIP:Inverse() * CFrame.new(Vector3.new(sign * 0.13, 0.08, -0.4) * SCALE)
		eye.CFrame = head.CFrame * offset
		eye.Parent = model
		attach(eye, head, offset)
	end

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(6, 5, 3)
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox.CanTouch = true
	hitbox.CastShadow = false
	hitbox.Massless = true
	local hitboxOffset = CFrame.new(0, 0.5 * SCALE, 0)
	hitbox.CFrame = root.CFrame * hitboxOffset
	hitbox.Parent = model
	attach(hitbox, root, hitboxOffset)

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.MaxHealth = config.maxHealth
	humanoid.Health = config.maxHealth
	humanoid.WalkSpeed = config.speedMin
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 0
	humanoid.HipHeight = ZombieFactory.HIP_HEIGHT
	humanoid.Parent = model

	model.PrimaryPart = root
	return model
end

-- Skinned zombie from a Sketchfab rig (ZombieSkins / ZombieRigs). The visual rig hangs
-- off the HumanoidRootPart by a Motor6D named Root and is animated through its Bones.
-- Bullets hit invisible boxes that ZombieHitboxes keeps on the bones (Head, Chest, Hips,
-- limbs); none of them collide, since a bone-driven box that dips below the hip height
-- (a lunge, a stumble) drags the Humanoid over. Blocking the player is left to two static
-- boxes welded to the root above the hip height (UpperTorso, LowerTorso), which the rest of
-- the game already toggles by name. The root keeps the full rig's size and height so
-- ROOT_HEIGHT and HIP_HEIGHT stay valid for every zombie.
local function buildSkinned(config: ZombiesConfig.ZombieConfig, skin: ZombieSkins.Skin, template: Model): Model
	local model = Instance.new("Model")
	model.Name = config.id
	model:SetAttribute("ZombieId", config.id)
	model:SetAttribute("ZombieSkin", skin.name)
	if skin.maxSpeed then
		model:SetAttribute("MaxSpeed", skin.maxSpeed)
	end
	ensureCollisionGroup()

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1) * SCALE
	root.CFrame = CFrame.new(0, ZombieFactory.ROOT_HEIGHT, 0)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model

	local copy = template:Clone()
	local rig = copy:FindFirstChild("Rig") :: BasePart
	local rootBone = rig:FindFirstChildWhichIsA("Bone")
	-- the root bone stands on the ground in every pack
	local feet = if rootBone then (rootBone.WorldPosition - rig.Position).Y else -rig.Size.Y / 2
	local offset = skin.offset or Vector3.zero
	local target = CFrame.new(Vector3.new(0, -feet, 0) + offset) * rig.CFrame.Rotation
	local delta = target * rig.CFrame:Inverse()
	local top = -math.huge
	for _, part in copy:GetChildren() do
		if part:IsA("BasePart") then
			part.CFrame = delta * part.CFrame
			if part:IsA("MeshPart") then
				top = math.max(top, part.Position.Y + part.Size.Y / 2)
			end
			part.Parent = model
		end
	end
	copy:Destroy()
	local rootMotor = Instance.new("Motor6D")
	rootMotor.Name = "Root"
	rootMotor.Part0 = root
	rootMotor.Part1 = rig
	rootMotor.C0 = root.CFrame:ToObjectSpace(rig.CFrame)
	rootMotor.Parent = root

	local function bone(name: string): Bone?
		local found = rig:FindFirstChild(name, true)
		return if found and found:IsA("Bone") then found else nil
	end

	local boxes: { [BasePart]: { bone: Bone, rest: CFrame } } = {}
	local function hitPart(name: string, size: Vector3, rest: CFrame, driver: Bone)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = rest
		part.Transparency = 1
		part.CanQuery = true
		part.CanTouch = false
		part.CanCollide = false
		part.CollisionGroup = ZOMBIE_GROUP
		part.Massless = true
		part.CastShadow = false
		part.Parent = model
		boxes[part] = { bone = driver, rest = rest }
	end
	local function blocker(name: string, bottom: number, top_: number)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = Vector3.new(1.8, math.max(top_ - bottom, 0.4), 1.1)
		part.CFrame = CFrame.new(0, (bottom + top_) / 2, 0)
		part.Transparency = 1
		part.CanQuery = false
		part.CanTouch = false
		part.CanCollide = COLLIDING[name] == true
		part.CollisionGroup = ZOMBIE_GROUP
		part.Massless = name ~= "LowerTorso"
		part.CastShadow = false
		part.Parent = model
		attach(part, root, root.CFrame:ToObjectSpace(part.CFrame))
	end

	local head, chest, hips = bone(skin.head), bone(skin.chest), bone(skin.hips)
	local headY = if head then head.WorldPosition.Y else top - 0.9
	local hipsPos = if hips then hips.WorldPosition else Vector3.new(0, headY * 0.5, 0)
	local headPos = if head then head.WorldPosition else Vector3.new(hipsPos.X, headY, hipsPos.Z)
	local headHeight = math.max(top - headY, 0.8)
	if head then
		hitPart("Head", Vector3.new(1.15, headHeight + 0.1, 1.15), CFrame.new(headPos.X, headY + headHeight / 2, headPos.Z), head)
	end
	local chestBottom = hipsPos.Y + 0.45
	if chest then
		hitPart("Chest", Vector3.new(1.9, math.max(headY - chestBottom, 0.8), 1.1),
			CFrame.new(hipsPos.X, (chestBottom + headY) / 2, hipsPos.Z), chest)
	end
	if hips then
		hitPart("Hips", Vector3.new(1.8, 1, 1.1), CFrame.new(hipsPos), hips)
	end
	-- heights as the clips hold the body (the offset only undoes the clips' own shift)
	local standingHead = headY - offset.Y
	local blockBottom = ZombieFactory.HIP_HEIGHT + 0.2
	local blockSplit = math.max(blockBottom + 0.5, hipsPos.Y - offset.Y + 0.45)
	blocker("LowerTorso", blockBottom, blockSplit)
	blocker("UpperTorso", blockSplit, math.max(standingHead - 0.2, blockSplit + 0.8))
	for name, limb in skin.limbs do
		local from, to = bone(limb.from), bone(limb.to)
		if from and to then
			local a, b = from.WorldPosition, to.WorldPosition
			local length = (b - a).Magnitude
			if length > 0.05 then
				hitPart(name, Vector3.new(limb.width, limb.width, length), CFrame.lookAt((a + b) / 2, b), from)
			end
		end
	end
	ZombieHitboxes.attach(model, root, boxes)

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(6, 5, 3)
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox.CanTouch = true
	hitbox.CastShadow = false
	hitbox.Massless = true
	local hitboxOffset = CFrame.new(0, 0.5 * SCALE, 0)
	hitbox.CFrame = root.CFrame * hitboxOffset
	hitbox.Parent = model
	attach(hitbox, root, hitboxOffset)

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.MaxHealth = config.maxHealth
	humanoid.Health = config.maxHealth
	humanoid.WalkSpeed = config.speedMin
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 0
	humanoid.HipHeight = ZombieFactory.HIP_HEIGHT
	humanoid.Parent = model

	model.PrimaryPart = root
	return model
end

-- `corpse`: the model will be laid down as a corpse, so only skins with a death clip
function ZombieFactory.build(config: ZombiesConfig.ZombieConfig, corpse: boolean?, skinName: string?): Model
	-- `skinName` forces one skin (the Studio test yard shows each skin side by side)
	local skin = if skinName then ZombieSkins.get(skinName) else ZombieSkins.pick(config.id, variation, corpse)
	if skin then
		local template = ZombieRigs.get(skin.name, 8)
		if template then
			return buildSkinned(config, skin, template)
		end
	end
	settleMeshes()
	if fullSet then
		return buildFull(config, fullSet)
	end
	local model = Instance.new("Model")
	model.Name = config.id
	model:SetAttribute("ZombieId", config.id)

	local tint = TINTS[variation:NextInteger(1, #TINTS)]
	local bodyColor = config.bodyColor:Lerp(tint, variation:NextNumber(0.15, 0.45))
	local limbColor = bodyColor:Lerp(Color3.new(0, 0, 0), 0.12)
	local legColor = bodyColor:Lerp(tint, 0.5):Lerp(Color3.new(0, 0, 0), 0.3)
	local headColor = Color3.fromRGB(146, 142, 122):Lerp(bodyColor, variation:NextNumber(0.12, 0.3))
	local waistPitch = variation:NextNumber(-4, 0)
	local neckPitch = variation:NextNumber(0, 3)
	local shoulderPitch = variation:NextNumber(4, 12)

	local root = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(), bodyColor, model)
	root.Transparency = 1

	ensureCollisionGroup()
	local lowerTorso = makePart("LowerTorso", Vector3.new(2, 0.9, 1), Vector3.new(0, 0, 0), legColor, model)
	lowerTorso.Material = Enum.Material.Fabric
	lowerTorso.CanCollide = true
	lowerTorso.CollisionGroup = ZOMBIE_GROUP

	local upperTorso = makePart("UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 1.25, 0), bodyColor, model)
	upperTorso.Material = Enum.Material.Fabric
	upperTorso.CanCollide = true
	upperTorso.CollisionGroup = ZOMBIE_GROUP

	local head = makePart("Head", Vector3.new(1.1, 1.15, 1.1), Vector3.new(0, 2.65, 0), headColor, model)
	head.Material = Enum.Material.Sand

	local leftArm = makePart("LeftUpperArm", Vector3.new(0.55, 1.8, 0.55), Vector3.new(-1.275, 1.15, 0), limbColor, model)
	local rightArm = makePart("RightUpperArm", Vector3.new(0.55, 1.8, 0.55), Vector3.new(1.275, 1.15, 0), limbColor, model)
	for _, arm in { leftArm, rightArm } do
		arm.Material = Enum.Material.Fabric
	end

	local leftLeg = makePart("LeftUpperLeg", Vector3.new(0.65, 1.9, 0.65), Vector3.new(-0.5, -1.4, 0), legColor, model)
	local rightLeg = makePart("RightUpperLeg", Vector3.new(0.65, 1.9, 0.65), Vector3.new(0.5, -1.4, 0), legColor, model)
	for _, leg in { leftLeg, rightLeg } do
		leg.Material = Enum.Material.Fabric
	end

	joint("Root", root, lowerTorso, Vector3.new(0, 0, 0))
	joint("Waist", lowerTorso, upperTorso, Vector3.new(0, 0.45, 0), waistPitch)
	joint("Neck", upperTorso, head, Vector3.new(0, 2.05, 0), neckPitch)
	joint("LeftShoulder", upperTorso, leftArm, Vector3.new(-1, 2.05, 0), shoulderPitch + variation:NextNumber(-5, 5))
	joint("RightShoulder", upperTorso, rightArm, Vector3.new(1, 2.05, 0), shoulderPitch + variation:NextNumber(-5, 5))
	joint("LeftHip", lowerTorso, leftLeg, Vector3.new(-0.5, -0.45, 0))
	joint("RightHip", lowerTorso, rightLeg, Vector3.new(0.5, -0.45, 0))

	for _, sign in { -1, 1 } do
		local eyeOffset = Vector3.new(sign * 0.26, 0.13, -0.57)
		local eye = makePart("Eye", Vector3.new(0.24, 0.14, 0.16), Vector3.new(0, 2.65, 0) + eyeOffset, config.eyeColor, model)
		eye.Material = Enum.Material.Neon
		eye.CastShadow = false
		attach(eye, head, CFrame.new(eyeOffset * SCALE))
	end

	local hitboxOffset = Vector3.new(0, 0.5, 0)
	local hitbox = makePart("Hitbox", Vector3.new(6, 5, 3), hitboxOffset, bodyColor, model)
	hitbox.Size = Vector3.new(6, 5, 3)
	hitbox.Transparency = 1
	hitbox.CanTouch = true
	hitbox.CastShadow = false
	attach(hitbox, root, CFrame.new(hitboxOffset * SCALE))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.MaxHealth = config.maxHealth
	humanoid.Health = config.maxHealth
	humanoid.WalkSpeed = config.speedMin
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 0
	humanoid.HipHeight = ZombieFactory.HIP_HEIGHT
	humanoid.Parent = model

	model.PrimaryPart = root
	return model
end

return ZombieFactory
