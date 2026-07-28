--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CameraConfig = require(ReplicatedStorage.Shared.config.CameraConfig)

export type StepListener = (Vector3) -> ()

local ExertionState = {}

local exertion = 0
local forced = false
local speed = 0
local stridePhase = 0
local strideFrequency = 0
local running = false
local listeners: { StepListener } = {}
local started = false

local function currentSpeed(): number
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return 0
	end
	local velocity = root.AssemblyLinearVelocity
	return math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
end

local function isGrounded(): boolean
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

function ExertionState.strideFrequencyFor(currentValue: number): number
	local range = CameraConfig.STRIDE_SPEED_MAX - CameraConfig.STRIDE_SPEED_MIN
	local alpha = math.clamp((currentValue - CameraConfig.STRIDE_SPEED_MIN) / range, 0, 1)
	return CameraConfig.STRIDE_FREQUENCY_MIN
		+ (CameraConfig.STRIDE_FREQUENCY_MAX - CameraConfig.STRIDE_FREQUENCY_MIN) * alpha
end

local function step(deltaTime: number)
	speed = currentSpeed()
	running = speed > 2 and isGrounded()

	if forced then
		exertion = 1
	elseif speed >= CameraConfig.EXERTION_SPEED_THRESHOLD then
		exertion = math.min(1, exertion + CameraConfig.EXERTION_GAIN_PER_SECOND * deltaTime)
	else
		exertion = math.max(0, exertion - CameraConfig.EXERTION_RECOVERY_PER_SECOND * deltaTime)
	end

	if not running then
		strideFrequency = 0
		return
	end

	strideFrequency = ExertionState.strideFrequencyFor(speed)
	local previousPhase = stridePhase
	stridePhase += strideFrequency * deltaTime * math.pi * 2

	local previousStep = math.floor(previousPhase / math.pi)
	local currentStep = math.floor(stridePhase / math.pi)
	if currentStep > previousStep then
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local position = if root and root:IsA("BasePart") then root.Position else Vector3.zero
		for _, listener in listeners do
			listener(position)
		end
	end

	if stridePhase > math.pi * 4096 then
		stridePhase -= math.pi * 4096
	end
end

function ExertionState.get(): number
	return exertion
end

function ExertionState.getSpeed(): number
	return speed
end

function ExertionState.getStridePhase(): number
	return stridePhase
end

function ExertionState.getStrideFrequency(): number
	return strideFrequency
end

function ExertionState.isRunning(): boolean
	return running
end

function ExertionState.setForced(value: boolean)
	forced = value
end

function ExertionState.onStep(listener: StepListener): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

function ExertionState.init()
	if started then
		return
	end
	started = true
	RunService.RenderStepped:Connect(step)
end

return ExertionState
