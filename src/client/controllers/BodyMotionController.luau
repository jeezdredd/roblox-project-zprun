--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CameraConfig = require(ReplicatedStorage.Shared.config.CameraConfig)
local ExertionState = require(script.Parent.ExertionState)
local InputController = require(script.Parent.InputController)

local BodyMotionController = {}

local RENDER_NAME = "BodyMotion"

local LEAN_MIN_DEGREES = 2
local LEAN_MAX_DEGREES = 6
local ROLL_MAX_DEGREES = 5
local LEAN_SPEED = 5
local ROLL_ENTER_SPEED = 8
local ROLL_RETURN_SPEED = 4
local IMPULSE_DECAY = 6

local waist: Motor6D? = nil
local waistBaseC0: CFrame? = nil
local lean = 0
local roll = 0
local impulsePitch = 0
local impulseRoll = 0
local bound = false

local function approach(current: number, target: number, speed: number, deltaTime: number): number
	return current + (target - current) * (1 - math.exp(-speed * deltaTime))
end

local function bindCharacter(character: Model)
	waist = nil
	waistBaseC0 = nil

	local upperTorso = character:WaitForChild("UpperTorso", 5)
	if upperTorso then
		local motor = upperTorso:FindFirstChild("Waist")
		if motor and motor:IsA("Motor6D") then
			waist = motor
			waistBaseC0 = motor.C0
			return
		end
	end

	local torso = character:FindFirstChild("Torso")
	if torso then
		local motor = torso:FindFirstChild("Neck")
		if motor and motor:IsA("Motor6D") then
			waist = motor
			waistBaseC0 = motor.C0
		end
	end
end

local function update(deltaTime: number)
	local motor = waist
	local baseC0 = waistBaseC0
	if not motor or not baseC0 or not motor.Parent then
		return
	end

	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local speed = ExertionState.getSpeed()
	local speedAlpha = math.clamp(
		(speed - CameraConfig.STRIDE_SPEED_MIN) / (CameraConfig.STRIDE_SPEED_MAX - CameraConfig.STRIDE_SPEED_MIN),
		0,
		1
	)
	local targetLean = if speed > 2 then LEAN_MIN_DEGREES + (LEAN_MAX_DEGREES - LEAN_MIN_DEGREES) * speedAlpha else 0
	lean = approach(lean, targetLean, LEAN_SPEED, deltaTime)

	local axis = InputController.getLateralAxis()
	local targetRoll = -axis * ROLL_MAX_DEGREES * (0.4 + speedAlpha * 0.6)
	local rollSpeed = if math.abs(targetRoll) > math.abs(roll) then ROLL_ENTER_SPEED else ROLL_RETURN_SPEED
	roll = approach(roll, targetRoll, rollSpeed, deltaTime)

	impulsePitch = approach(impulsePitch, 0, IMPULSE_DECAY, deltaTime)
	impulseRoll = approach(impulseRoll, 0, IMPULSE_DECAY, deltaTime)

	local bob = math.sin(ExertionState.getStridePhase() * 0.5) * 0.6 * speedAlpha

	motor.C0 = baseC0
		* CFrame.Angles(
			math.rad(lean + impulsePitch),
			0,
			math.rad(roll + bob + impulseRoll)
		)
end

function BodyMotionController.impulse(pitchDegrees: number, rollDegrees: number)
	impulsePitch += pitchDegrees
	impulseRoll += rollDegrees
end

function BodyMotionController.init()
	if bound then
		return
	end
	bound = true
	ExertionState.init()

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function(character)
		task.spawn(bindCharacter, character)
	end)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end

	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Character.Value + 1, update)
end

return BodyMotionController
