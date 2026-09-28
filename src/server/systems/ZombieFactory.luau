--!strict

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ZombiesConfig = require(ReplicatedStorage.Shared.config.ZombiesConfig)

local ZombieFactory = {}

ZombieFactory.SCALE = 0.86
ZombieFactory.ROOT_HEIGHT = 2.35 * ZombieFactory.SCALE
ZombieFactory.HIP_HEIGHT = ZombieFactory.ROOT_HEIGHT - ZombieFactory.SCALE

local SCALE = ZombieFactory.SCALE

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
	local part: BasePart = if template then template:Clone() else Instance.new("Part")
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

function ZombieFactory.build(config: ZombiesConfig.ZombieConfig): Model
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
