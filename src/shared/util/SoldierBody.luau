--!strict

-- The soldier body: turns a stock R15 character (Roblox's block body) into the Mixamo
-- soldier split by tools/character_rig/soldier.py. Every body part is swapped for the
-- soldier's mesh (ReplicatedStorage.CharacterMeshes.Soldier through MeshTemplates), the
-- rig attachments and Motor6D joints move to the soldier's pivots (SoldierRigConfig), and
-- the Humanoid takes the soldier's hip height. Joint frames stay axis-aligned and the rest
-- pose keeps the arms hanging straight down, so every R15 clip plays unchanged.
--
-- The server runs it once on a fresh R15 model to make StarterPlayer.StarterCharacter
-- (SoldierCharacter); the yard's mannequins clone the local character and inherit it.
-- Nothing changes while SoldierRigConfig.ready is false (mesh ids not read back yet).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoldierRigConfig = require(ReplicatedStorage.Shared.config.SoldierRigConfig)
local MeshTemplates = require(script.Parent.MeshTemplates)

local SoldierBody = {}

-- set on the character once converted
SoldierBody.ATTRIBUTE = "SoldierBody"
-- on each hand: the fist's centre relative to the hand part, read by WorldWeaponModel
SoldierBody.GRIP_ATTRIBUTE = "GripOffset"

-- the uniform tint keeps this much of the skin colour (the rest is white, no tint)
local TINT_STRENGTH = 0.55
local TORSO_GROUP = "Torso"
local LEGS_GROUP = "Legs"

local function templates(): Instance?
	local folder = ReplicatedStorage:FindFirstChild("CharacterMeshes")
	return if folder then folder:FindFirstChild("Soldier") else nil
end

function SoldierBody.available(): boolean
	return SoldierRigConfig.ready and templates() ~= nil
end

-- Yields until the soldier meshes are loaded (or `timeout`); false when unavailable.
function SoldierBody.load(timeout: number): boolean
	local root = templates()
	if not root or not SoldierRigConfig.ready then
		return false
	end
	return MeshTemplates.waitFor(root, timeout)
end

local function scaled(position: Vector3, from: Vector3, to: Vector3): Vector3
	return Vector3.new(
		if from.X > 0 then position.X * to.X / from.X else position.X,
		if from.Y > 0 then position.Y * to.Y / from.Y else position.Y,
		if from.Z > 0 then position.Z * to.Z / from.Z else position.Z
	)
end

local function placeRigAttachment(owner: BasePart, jointName: string, cframe: CFrame)
	local attachment = owner:FindFirstChild(jointName .. "RigAttachment")
	if attachment and attachment:IsA("Attachment") then
		attachment.CFrame = cframe
	end
end

local function centreOf(name: string): Vector3
	return SoldierRigConfig.parts[name].centre
end

-- Converts `character` in place. Returns false (and changes nothing) when the soldier is
-- unavailable or the character is not a complete R15 rig.
function SoldierBody.apply(character: Model): boolean
	local root = templates()
	if not root or not SoldierRigConfig.ready then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 or not rootPart or not rootPart:IsA("BasePart") then
		return false
	end
	for name in SoldierRigConfig.parts do
		if name ~= "HumanoidRootPart" then
			local old = character:FindFirstChild(name)
			local template = root:FindFirstChild(name)
			if not old or not old:IsA("BasePart") or not template or not template:IsA("MeshPart") then
				return false
			end
		end
	end

	humanoid.AutomaticScalingEnabled = false
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") or child:IsA("Clothing") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Destroy()
		end
	end

	local rootCentre = centreOf("HumanoidRootPart")
	local rootCFrame = rootPart.CFrame
	local parts: { [string]: BasePart } = { HumanoidRootPart = rootPart }
	for name, info in SoldierRigConfig.parts do
		if name == "HumanoidRootPart" then
			continue
		end
		local old = character:FindFirstChild(name) :: BasePart
		local part = MeshTemplates.clone(root:FindFirstChild(name) :: MeshPart)
		part.Name = name
		part.Size = info.size
		part.Anchored = false
		part.CanCollide = old.CanCollide
		part.CanQuery = old.CanQuery
		part.CanTouch = old.CanTouch
		part.Massless = old.Massless
		part.CastShadow = true
		part.CFrame = rootCFrame * CFrame.new(info.centre - rootCentre)
		for _, child in old:GetChildren() do
			if child:IsA("Attachment") then
				if not string.find(child.Name, "RigAttachment$") then
					child.Position = scaled(child.Position, old.Size, info.size)
				end
				child.Parent = part
			elseif child:IsA("Vector3Value") and child.Name == "OriginalSize" then
				child.Value = info.size
				child.Parent = part
			elseif child:IsA("Decal") or child:IsA("WrapTarget") or child:IsA("FaceControls") then
				-- the block face, and cages that no longer match the mesh
				child:Destroy()
			else
				child.Parent = part
			end
		end
		old:Destroy()
		part.Parent = character
		parts[name] = part
	end

	for _, joint in SoldierRigConfig.joints do
		local part0, part1 = parts[joint.part0], parts[joint.part1]
		local c0 = CFrame.new(joint.pivot - centreOf(joint.part0))
		local c1 = CFrame.new(joint.pivot - centreOf(joint.part1))
		local motor = part1:FindFirstChild(joint.name)
		if not motor or not motor:IsA("Motor6D") then
			motor = Instance.new("Motor6D")
			motor.Name = joint.name
			motor.Parent = part1
		end
		local m = motor :: Motor6D
		m.Part0 = part0
		m.Part1 = part1
		m.C0 = c0
		m.C1 = c1
		m.Transform = CFrame.identity
		placeRigAttachment(part0, joint.name, c0)
		placeRigAttachment(part1, joint.name, c1)
	end

	for side, offset in SoldierRigConfig.grips do
		local hand = parts[side .. "Hand"]
		hand:SetAttribute(SoldierBody.GRIP_ATTRIBUTE, offset)
		local grip = hand:FindFirstChild(side .. "GripAttachment")
		if grip and grip:IsA("Attachment") then
			grip.Position = offset
		end
	end

	humanoid.HipHeight = SoldierRigConfig.hipHeight
	character:SetAttribute(SoldierBody.ATTRIBUTE, true)
	return true
end

local function tintOf(colour: Color3): Color3
	local peak = math.max(colour.R, colour.G, colour.B, 1e-3)
	local full = Color3.new(colour.R / peak, colour.G / peak, colour.B / peak)
	return Color3.new(1, 1, 1):Lerp(full, TINT_STRENGTH)
end

-- Tints the uniform: torso parts by `torso`, leg parts by `legs` (hue kept, brightness
-- from the texture). Head and arms keep their gear colours.
function SoldierBody.tint(character: Model, torso: Color3, legs: Color3)
	for name, info in SoldierRigConfig.parts do
		local tint = if info.group == TORSO_GROUP then tintOf(torso) elseif info.group == LEGS_GROUP then tintOf(legs) else nil
		local part = character:FindFirstChild(name)
		local appearance = if part then part:FindFirstChildOfClass("SurfaceAppearance") else nil
		if tint and appearance then
			appearance.Color = tint
		end
	end
end

return SoldierBody
