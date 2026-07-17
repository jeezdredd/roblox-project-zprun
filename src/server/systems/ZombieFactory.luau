--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZombiesConfig = require(ReplicatedStorage.Shared.config.ZombiesConfig)

local ZombieFactory = {}

local function createWeldedPart(name: string, size: Vector3, offset: CFrame, color: Color3, root: BasePart, model: Model): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = root.CFrame * offset
	part.Color = color
	part.CanCollide = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
	return part
end

function ZombieFactory.build(config: ZombiesConfig.ZombieConfig): Model
	local model = Instance.new("Model")
	model.Name = config.id
	model:SetAttribute("ZombieId", config.id)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.CFrame = CFrame.new()
	root.Parent = model

	createWeldedPart("Body", Vector3.new(2, 3, 1), CFrame.new(0, 0, 0), config.bodyColor, root, model)
	createWeldedPart("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 2.1, 0), config.bodyColor:Lerp(Color3.new(0, 0, 0), 0.3), root, model)

	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.MaxHealth = config.maxHealth
	humanoid.Health = config.maxHealth
	humanoid.WalkSpeed = config.walkSpeed
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 0
	humanoid.HipHeight = 0.5
	humanoid.Parent = model

	model.PrimaryPart = root
	return model
end

return ZombieFactory
