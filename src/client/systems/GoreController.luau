--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local SettingsService = require(script.Parent.SettingsService)

local GoreController = {}

local BLOOD_COLOR = ColorSequence.new(Color3.fromRGB(120, 30, 30))

local vignette: Frame

local function buildVignette()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "DamageVignette"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 30
	screen.Parent = playerGui

	vignette = Instance.new("Frame")
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3 = Color3.fromRGB(120, 0, 0)
	vignette.BackgroundTransparency = 1
	vignette.BorderSizePixel = 0
	vignette.Parent = screen

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	gradient.Parent = vignette
end

local function flashVignette()
	vignette.BackgroundTransparency = 0.55
	TweenService:Create(vignette, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
end

local function spawnBlood(root: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = BLOOD_COLOR
	emitter.Size = NumberSequence.new(0.6, 0.1)
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(6, 10)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Parent = attachment
	emitter:Emit(14)

	Debris:AddItem(attachment, 1)
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth - 0.001 and health > 0 then
			if SettingsService.get("bloodEnabled") then
				local root = character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					spawnBlood(root)
				end
				flashVignette()
			end
		end
		lastHealth = health
	end)
end

function GoreController.init()
	buildVignette()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

return GoreController
