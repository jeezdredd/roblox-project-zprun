--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local VendorsConfig = require(ReplicatedStorage.Shared.config.VendorsConfig)

local VendorStands = {}

local function makeSign(parent: BasePart, title: string, subtitle: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VendorSign"
	billboard.Size = UDim2.fromScale(9, 3)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
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
	subLabel.Size = UDim2.fromScale(1, 0.35)
	subLabel.Position = UDim2.fromScale(0, 0.62)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.TextScaled = true
	subLabel.TextColor3 = Color3.fromRGB(180, 180, 185)
	subLabel.TextStrokeTransparency = 0.6
	subLabel.Text = subtitle
	subLabel.Parent = billboard
end

local function buildStand(config: VendorsConfig.VendorConfig, parent: Instance)
	local basePosition = HangarConfig.HUB_CENTER + config.offset

	local booth = Instance.new("Part")
	booth.Name = config.id
	booth.Size = Vector3.new(8, 8, 5)
	booth.CFrame = CFrame.new(basePosition + Vector3.new(0, 4.5, 0))
	booth.Anchored = true
	booth.CanCollide = true
	booth.Color = config.color
	booth.Material = config.material
	booth.Parent = parent

	local counter = Instance.new("Part")
	counter.Name = "Counter"
	counter.Size = Vector3.new(10, 1, 3)
	counter.CFrame = CFrame.new(basePosition + Vector3.new(0, 3, -3))
	counter.Anchored = true
	counter.CanCollide = true
	counter.Color = config.color:Lerp(Color3.new(0, 0, 0), 0.35)
	counter.Material = Enum.Material.Metal
	counter.Parent = parent

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VendorPrompt"
	prompt.ActionText = "Coming soon"
	prompt.ObjectText = config.displayName
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = booth

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
