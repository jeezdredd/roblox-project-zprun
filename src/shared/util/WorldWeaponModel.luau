--!strict

-- The third-person gun: a five-part model welded to the right hand, built by the server
-- (WorldWeapon) for every character and by the yard's body gallery for its mannequins.
-- The grip part carries the sockets the body layer reads, all in grip space (x right, y
-- up, -z along the barrel): GripSocket is where the right hand sits, SupportSocket,
-- MagazineSocket, ChargeSocket, PortSocket and PumpSocket are where the support hand
-- goes, Muzzle is the barrel end.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ThirdPersonConfig = require(ReplicatedStorage.Shared.config.ThirdPersonConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)

local WorldWeaponModel = {}

WorldWeaponModel.NAME = "WorldWeapon"
WorldWeaponModel.CLASS_ATTRIBUTE = "WeaponClass"
-- the grip part relative to the right hand: in the fist, just past the hand's end along
-- its -y (the fingers' way), the barrel along the forearm. It sat 0.9 studs out before
-- (2026-09-30), which left the hand under the stock and the grip floating ahead of it
-- once the body layer put the hands on the gun.
local HAND_ROTATION = CFrame.Angles(math.rad(-80), 0, 0)
WorldWeaponModel.HAND_OFFSET = CFrame.new(0, -0.3, -0.1) * HAND_ROTATION
-- A hand carrying this Vector3 attribute (the soldier body, SoldierBody.GRIP_ATTRIBUTE)
-- has a modelled fist: the grip sits at that point of the hand instead, same rotation.
WorldWeaponModel.GRIP_ATTRIBUTE = "GripOffset"

local function gripOffsetOf(hand: Instance?): Vector3?
	local offset = if hand then hand:GetAttribute(WorldWeaponModel.GRIP_ATTRIBUTE) else nil
	return if typeof(offset) == "Vector3" then offset else nil
end

-- The grip part relative to `hand`.
function WorldWeaponModel.handOffsetFor(hand: Instance?): CFrame
	local offset = gripOffsetOf(hand)
	return if offset then CFrame.new(offset) * HAND_ROTATION else WorldWeaponModel.HAND_OFFSET
end

-- Lengths along the barrel in studs: receiver, barrel, stock (0 for none). Sized to the
-- default R15 body, whose arms reach about 1.8 studs from the shoulder joint across a
-- chest 2 studs wide: the first rifle (receiver 2.1, stock 0.9) put its handguard 2.8
-- studs ahead of the chest and its stock through it.
type Lengths = { receiver: number, barrel: number, stock: number }
local LENGTHS: { [string]: Lengths } = {
	Pistol = { receiver = 0.9, barrel = 0.4, stock = 0 },
	SMG = { receiver = 1.2, barrel = 0.5, stock = 0.5 },
	Rifle = { receiver = 1.6, barrel = 1.1, stock = 0.6 },
	Shotgun = { receiver = 1.6, barrel = 1.3, stock = 0.65 },
}

local COLOR_METAL = Color3.fromRGB(46, 48, 52)
local COLOR_GRIP = Color3.fromRGB(52, 44, 36)
local COLOR_WOOD = Color3.fromRGB(96, 72, 48)

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Parent = parent
	return part
end

local function weldTo(anchorPart: BasePart, part: BasePart, offset: CFrame)
	part.CFrame = anchorPart.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = anchorPart
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
end

local function socket(name: string, cframe: CFrame, parent: Instance): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = cframe
	attachment.Parent = parent
	return attachment
end

-- The support hand's frame on the gun: the right hand's orientation rolled about the
-- barrel, placed so the hand's fist (`supportGrip`, zero for a block hand) lands on
-- `position`.
local function supportFrame(position: Vector3, roll: number, supportGrip: Vector3): CFrame
	return CFrame.new(position) * HAND_ROTATION:Inverse() * CFrame.Angles(0, 0, math.rad(roll)) * CFrame.new(-supportGrip)
end

local function addSockets(
	grip: BasePart,
	config: WeaponsConfig.WeaponConfig,
	bodyLength: number,
	barrelLength: number,
	handOffset: CFrame,
	supportGrip: Vector3
)
	socket("GripSocket", handOffset:Inverse(), grip)
	socket("Muzzle", CFrame.new(0, 0.62, -bodyLength - barrelLength + 0.3), grip)
	local spec = ThirdPersonConfig.getClass(config.class)
	if not spec then
		return
	end
	socket("SupportSocket", supportFrame(spec.support, spec.supportRoll, supportGrip), grip)
	socket("MagazineSocket", supportFrame(spec.magazine, spec.supportRoll, supportGrip), grip)
	local charge = spec.charge
	if charge then
		socket("ChargeSocket", supportFrame(charge, spec.supportRoll, supportGrip), grip)
	end
	local port = spec.port
	if port then
		socket("PortSocket", supportFrame(port, spec.supportRoll, supportGrip), grip)
	end
	local pump = spec.pump
	if pump then
		socket("PumpSocket", supportFrame(pump, spec.supportRoll, supportGrip), grip)
	end
end

-- Builds the gun for `config` on `character`'s right hand, replacing any previous one.
-- Returns nil when the character has no hand yet.
function WorldWeaponModel.build(character: Model, config: WeaponsConfig.WeaponConfig): Model?
	local existing = character:FindFirstChild(WorldWeaponModel.NAME)
	if existing then
		existing:Destroy()
	end

	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = WorldWeaponModel.NAME
	model:SetAttribute(WorldWeaponModel.CLASS_ATTRIBUTE, config.class)

	local isPistol = config.class == "Pistol"
	local isShotgun = config.class == "Shotgun"
	local lengths = LENGTHS[config.class] or LENGTHS.Rifle
	local bodyLength = lengths.receiver
	local barrelLength = lengths.barrel

	local grip = makePart("Grip", Vector3.new(0.3, 0.7, 0.34), COLOR_GRIP, Enum.Material.SmoothPlastic, model)
	local handOffset = WorldWeaponModel.handOffsetFor(hand)
	local supportGrip = gripOffsetOf(character:FindFirstChild("LeftHand")) or Vector3.zero
	weldTo(hand, grip, handOffset)

	local receiver = makePart("Receiver", Vector3.new(0.28, 0.46, bodyLength), COLOR_METAL, Enum.Material.Metal, model)
	weldTo(hand, receiver, handOffset * CFrame.new(0, 0.56, -bodyLength / 2 + 0.24))

	local barrel = makePart("Barrel", Vector3.new(0.15, 0.15, barrelLength), COLOR_METAL, Enum.Material.Metal, model)
	weldTo(hand, barrel, handOffset * CFrame.new(0, 0.62, -bodyLength - barrelLength / 2 + 0.3))

	if not isPistol then
		local furnitureColor = if isShotgun then COLOR_WOOD else COLOR_GRIP
		local furnitureMaterial = if isShotgun then Enum.Material.WoodPlanks else Enum.Material.SmoothPlastic
		if lengths.stock > 0 then
			-- from the receiver's back end (0.24 behind the grip) rearwards
			local stock = makePart("Stock", Vector3.new(0.24, 0.38, lengths.stock), furnitureColor, furnitureMaterial, model)
			weldTo(hand, stock, handOffset * CFrame.new(0, 0.5, 0.24 + lengths.stock / 2))
		end
		local handguard = makePart("Handguard", Vector3.new(0.28, 0.32, barrelLength * 0.6), furnitureColor, furnitureMaterial, model)
		weldTo(hand, handguard, handOffset * CFrame.new(0, 0.52, -bodyLength - 0.1))
	end

	if config.class == "SMG" or config.class == "Rifle" then
		local magazine = makePart("Magazine", Vector3.new(0.22, 0.66, 0.34), COLOR_METAL, Enum.Material.Metal, model)
		weldTo(hand, magazine, handOffset * CFrame.new(0, 0.2, -bodyLength / 2 + 0.1))
	end

	addSockets(grip, config, bodyLength, barrelLength, handOffset, supportGrip)
	model.PrimaryPart = grip
	model.Parent = character
	return model
end

return WorldWeaponModel
