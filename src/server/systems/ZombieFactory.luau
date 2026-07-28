--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TexturesConfig = require(ReplicatedStorage.Shared.config.TexturesConfig)
local TextureUtil = require(ReplicatedStorage.Shared.util.TextureUtil)
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

	local body = createWeldedPart("Body", Vector3.new(2, 3, 1), CFrame.new(0, 0, 0), config.bodyColor, root, model)
	body.Material = Enum.Material.Fabric
	TextureUtil.applySides(body, TexturesConfig.FABRIC, 2.4)

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.CFrame = root.CFrame * CFrame.new(0, 2.1, 0)
	head.Color = config.bodyColor:Lerp(Color3.new(0, 0, 0), 0.3)
	head.Material = Enum.Material.Sand
	head.CanCollide = false
	head.Parent = model
	TextureUtil.applySides(head, TexturesConfig.GROUND, 1.4)

	local neck = Instance.new("Motor6D")
	neck.Name = "Neck"
	neck.Part0 = body
	neck.Part1 = head
	neck.C0 = CFrame.new(0, 2.1, 0)
	neck.Parent = body

	for _, sign in { -1, 1 } do
		local eye = createWeldedPart(
			"Eye",
			Vector3.new(0.24, 0.16, 0.16),
			CFrame.new(sign * 0.28, 2.24, -0.62),
			config.eyeColor,
			root,
			model
		)
		eye.Material = Enum.Material.Neon
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CastShadow = false
	end

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
