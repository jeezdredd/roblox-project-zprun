--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VfxConfig = require(ReplicatedStorage.Shared.config.VfxConfig)
local ExertionState = require(script.Parent.Parent.controllers.ExertionState)
local InputController = require(script.Parent.Parent.controllers.InputController)

local MotionVfx = {}

local NIGHT_ATTRIBUTE = "NightMission"

local dustEmitter: ParticleEmitter? = nil
local jukeEmitter: ParticleEmitter? = nil
local vaporEmitter: ParticleEmitter? = nil

local rayParams = RaycastParams.new()
local lastAxis = 0
local jukeReadyAt = 0
local vaporTimer = 0
local started = false

local function makeEmitter(parent: Attachment, name: string): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.LightInfluence = 0.8
	emitter.Drag = 3
	emitter.Acceleration = Vector3.new(0, 2, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.Parent = parent
	return emitter
end

local function setupCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end

	local feet = Instance.new("Attachment")
	feet.Name = "MotionVfxFeet"
	feet.Position = Vector3.new(0, -2.6, 0)
	feet.Parent = root
	dustEmitter = makeEmitter(feet, "StepDust")
	jukeEmitter = makeEmitter(feet, "JukeDust")

	local head = character:FindFirstChild("Head")
	local vaporHost = if head and head:IsA("BasePart") then head else root
	local vapor = Instance.new("Attachment")
	vapor.Name = "MotionVfxVapor"
	vapor.Position = Vector3.new(0, 0.2, -0.8)
	vapor.Parent = vaporHost
	vaporEmitter = makeEmitter(vapor, "BreathVapor")
	vaporEmitter.Acceleration = Vector3.new(0, 1.4, 0)
	vaporEmitter.Drag = 5
end

local function materialUnderFoot(character: Model, humanoid: Humanoid): Enum.Material
	local material = humanoid.FloorMaterial
	if material ~= Enum.Material.Air then
		return material
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return Enum.Material.Air
	end
	rayParams.FilterDescendantsInstances = { character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local result = Workspace:Raycast(root.Position, Vector3.new(0, -6, 0), rayParams)
	return if result then result.Material else Enum.Material.Air
end

local function onStep()
	if not VfxConfig.ENABLED then
		return
	end
	local emitter = dustEmitter
	if not emitter or not emitter.Parent then
		return
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	local material = materialUnderFoot(character, humanoid)
	if material == Enum.Material.Air then
		return
	end

	local dust = VfxConfig.dustFor(material)
	emitter.Color = ColorSequence.new(dust.color)
	emitter.Size = NumberSequence.new(dust.size * 0.4, dust.size * 1.6)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(dust.lifetime * 0.7, dust.lifetime)
	emitter.Speed = NumberRange.new(dust.speed * 0.5, dust.speed)
	emitter.SpreadAngle = Vector2.new(55, 55)
	emitter:Emit(math.max(1, math.floor(dust.count * VfxConfig.DENSITY + 0.5)))
end

local function updateJuke(now: number)
	local emitter = jukeEmitter
	if not emitter or not emitter.Parent then
		return
	end
	local axis = InputController.getLateralAxis()
	local flipped = axis ~= 0 and lastAxis ~= 0 and axis ~= lastAxis
	if axis ~= 0 then
		lastAxis = axis
	end
	if not flipped or now < jukeReadyAt then
		return
	end
	if ExertionState.getSpeed() < VfxConfig.JUKE_MIN_SPEED then
		return
	end
	jukeReadyAt = now + VfxConfig.JUKE_COOLDOWN

	emitter.Color = ColorSequence.new(Color3.fromRGB(190, 184, 172))
	emitter.Size = NumberSequence.new(0.5, 2.2)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.3, 0.55)
	emitter.Speed = NumberRange.new(6, 11)
	emitter.SpreadAngle = Vector2.new(70, 20)
	emitter:Emit(math.max(1, math.floor(VfxConfig.JUKE_PARTICLES * VfxConfig.DENSITY + 0.5)))
end

local function updateVapor(deltaTime: number)
	local emitter = vaporEmitter
	if not emitter or not emitter.Parent then
		return
	end
	if Workspace:GetAttribute(NIGHT_ATTRIBUTE) ~= true then
		return
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local exertion = ExertionState.get()
	local interval = VfxConfig.BREATH_VAPOR_INTERVAL_CALM
		+ (VfxConfig.BREATH_VAPOR_INTERVAL_EXERTED - VfxConfig.BREATH_VAPOR_INTERVAL_CALM) * exertion
	vaporTimer += deltaTime
	if vaporTimer < interval then
		return
	end
	vaporTimer = 0

	emitter.Color = ColorSequence.new(Color3.fromRGB(226, 234, 244))
	emitter.Size = NumberSequence.new(0.3, 1.9)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.9, 1.5)
	emitter.Speed = NumberRange.new(2.2, 3.6)
	emitter.SpreadAngle = Vector2.new(16, 16)
	emitter:Emit(math.max(1, math.floor(VfxConfig.BREATH_VAPOR_COUNT * VfxConfig.DENSITY + 0.5)))
end

local function step(deltaTime: number)
	if not VfxConfig.ENABLED then
		return
	end
	updateJuke(os.clock())
	updateVapor(deltaTime)
end

function MotionVfx.init()
	if started then
		return
	end
	started = true
	ExertionState.init()

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		task.spawn(setupCharacter, player.Character)
	end

	ExertionState.onStep(onStep)
	RunService.Heartbeat:Connect(step)
end

return MotionVfx
