--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local VendorsConfig = require(ReplicatedStorage.Shared.config.VendorsConfig)

local VendorStands = {}

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

local function makeSign(parent: BasePart, title: string, subtitle: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VendorSign"
	billboard.Size = UDim2.fromScale(9, 2.6)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 7.5, 0)
	billboard.MaxDistance = 90
	billboard.Adornee = parent
	billboard.Parent = parent

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

local function buildStand(config: VendorsConfig.VendorConfig, parent: Instance)
	local base = CFrame.new(HangarConfig.HUB_CENTER + config.offset) * CFrame.Angles(0, config.rotationY, 0)
	local dark = config.color:Lerp(Color3.new(0, 0, 0), 0.45)

	createPart("Platform", Vector3.new(14, 0.4, 10), base * CFrame.new(0, 0.7, 0), Color3.fromRGB(60, 62, 68), Enum.Material.DiamondPlate, parent)

	local booth = createPart("Booth", Vector3.new(10, 8, 4), base * CFrame.new(0, 4.9, 2.5), config.color, config.material, parent)

	createPart("SidePanelL", Vector3.new(1, 8, 8), base * CFrame.new(-5.5, 4.9, 0.5), dark, Enum.Material.Metal, parent)
	createPart("SidePanelR", Vector3.new(1, 8, 8), base * CFrame.new(5.5, 4.9, 0.5), dark, Enum.Material.Metal, parent)

	local canopy = createPart("Canopy", Vector3.new(14, 0.5, 9), base * CFrame.new(0, 9.2, -0.5) * CFrame.Angles(math.rad(-4), 0, 0), dark, Enum.Material.Metal, parent)
	canopy.CanCollide = false

	local signStrip = createPart("SignStrip", Vector3.new(11, 1.2, 0.4), base * CFrame.new(0, 8.2, -4.4), config.color, Enum.Material.Neon, parent)
	signStrip.CanCollide = false

	local counter = createPart("Counter", Vector3.new(10, 1, 2.6), base * CFrame.new(0, 3, -2.6), dark, Enum.Material.Metal, parent)

	local lamp = Instance.new("PointLight")
	lamp.Color = config.color
	lamp.Range = 18
	lamp.Brightness = 1.4
	lamp.Parent = signStrip

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VendorPrompt"
	prompt.ActionText = "Coming soon"
	prompt.ObjectText = config.displayName
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	makeSign(booth, config.displayName, config.subtitle)
end

function VendorStands.build(): Model
	local model = Instance.new("Model")
	model.Name = "Vendors"
	for _, id in VendorsConfig.order do
		local config = VendorsConfig.get(id)
		if config then
			buildStand(config, model)
		end
	end
	model.Parent = Workspace
	return model
end

return VendorStands
