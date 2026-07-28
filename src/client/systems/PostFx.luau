--!strict

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PostFx = {}

local LOW_HEALTH_RATIO = 0.3
local DAMAGE_DECAY = 2.6
local HEARTBEAT_RATE_LOW = 2.4
local HEARTBEAT_RATE_CRITICAL = 3.6

local damageEffect: ColorCorrectionEffect
local bloom: BloomEffect
local vignette: Frame
local damagePulse = 0
local deathFade = 0
local pulsePhase = 0
local started = false

local function approach(current: number, target: number, speed: number, deltaTime: number): number
	return current + (target - current) * (1 - math.exp(-speed * deltaTime))
end

local function buildVignette()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "DamageVignette"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 25
	screen.Parent = playerGui

	vignette = Instance.new("Frame")
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3 = Color3.fromRGB(120, 10, 10)
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

local function healthRatio(): number
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.MaxHealth <= 0 then
		return 1
	end
	return math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
end

local function step(deltaTime: number)
	damagePulse = approach(damagePulse, 0, DAMAGE_DECAY, deltaTime)

	local ratio = healthRatio()
	local lowness = math.clamp((LOW_HEALTH_RATIO - ratio) / LOW_HEALTH_RATIO, 0, 1)
	local rate = HEARTBEAT_RATE_LOW + (HEARTBEAT_RATE_CRITICAL - HEARTBEAT_RATE_LOW) * lowness
	pulsePhase += deltaTime * rate
	local pulse = (math.sin(pulsePhase * math.pi * 2) + 1) / 2

	local isDead = ratio <= 0
	deathFade = approach(deathFade, if isDead then 1 else 0, 1.6, deltaTime)

	damageEffect.Saturation = -(lowness * 0.35 * (0.6 + pulse * 0.4)) - deathFade * 0.65
	damageEffect.TintColor = Color3.fromRGB(255, 255 - math.floor(damagePulse * 90), 255 - math.floor(damagePulse * 90))
	damageEffect.Brightness = -damagePulse * 0.06
	local biome = Workspace:GetAttribute("Biome")
	local sunInFrame = biome == "Forest" and Workspace:GetAttribute("Night") ~= true
	bloom.Intensity = (if sunInFrame then 0.62 else 0.34) + deathFade * 1.6 + damagePulse * 0.5
	bloom.Threshold = if sunInFrame then 1 else 1.25

	vignette.BackgroundTransparency = 1 - math.clamp(damagePulse * 0.7 + lowness * 0.3 * (0.5 + pulse * 0.5), 0, 0.85)
end

function PostFx.damage(amount: number)
	damagePulse = math.clamp(damagePulse + amount, 0, 1)
end

function PostFx.init()
	if started then
		return
	end
	started = true

	damageEffect = Instance.new("ColorCorrectionEffect")
	damageEffect.Name = "TFZ_EventGrading"
	damageEffect.Parent = Lighting

	bloom = Instance.new("BloomEffect")
	bloom.Name = "TFZ_Bloom"
	bloom.Intensity = 0.34
	bloom.Size = 20
	bloom.Threshold = 1.25
	bloom.Parent = Lighting

	buildVignette()

	local function watchCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		local lastHealth = humanoid.Health
		humanoid.HealthChanged:Connect(function(health)
			local delta = lastHealth - health
			if delta > 0.001 then
				PostFx.damage(math.clamp(delta / math.max(1, humanoid.MaxHealth) * 3.5, 0.12, 0.9))
			end
			lastHealth = health
		end)
	end

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end

	RunService.Heartbeat:Connect(step)
end

return PostFx
