--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraConfig = require(ReplicatedStorage.Shared.config.CameraConfig)
local BodyMotionController = require(script.Parent.BodyMotionController)
local ExertionState = require(script.Parent.ExertionState)
local InputController = require(script.Parent.InputController)

local CameraEffectsController = {}

local RENDER_NAME = "CameraEffects"

local bound = false
local bobWeight = 0
local tilt = 0
local breathPhase = 0
local swayPhase = 0
local fov = CameraConfig.BASE_FOV
local fovKick = 0
local adrenaline = 0

local shakeOffsetX, shakeOffsetY, shakeOffsetZ = 0, 0, 0
local shakeVelocityX, shakeVelocityY, shakeVelocityZ = 0, 0, 0

local function approach(current: number, target: number, speed: number, deltaTime: number): number
	local alpha = 1 - math.exp(-speed * deltaTime)
	return current + (target - current) * alpha
end

local function isAlive(): boolean
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function updateShake(deltaTime: number)
	local stiffness = CameraConfig.SHAKE_STIFFNESS
	local damping = CameraConfig.SHAKE_DAMPING

	shakeVelocityX -= (stiffness * shakeOffsetX + damping * shakeVelocityX) * deltaTime
	shakeVelocityY -= (stiffness * shakeOffsetY + damping * shakeVelocityY) * deltaTime
	shakeVelocityZ -= (stiffness * shakeOffsetZ + damping * shakeVelocityZ) * deltaTime

	shakeOffsetX += shakeVelocityX * deltaTime
	shakeOffsetY += shakeVelocityY * deltaTime
	shakeOffsetZ += shakeVelocityZ * deltaTime
end

local function update(deltaTime: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local intensity = CameraConfig.INTENSITY
	local exertion = ExertionState.get()
	local speed = ExertionState.getSpeed()

	local chase = if Workspace:GetAttribute("ZombiesAggro") == true
			and Players.LocalPlayer:GetAttribute("FlowPhase") == "Mission"
		then 1
		else 0
	adrenaline = approach(adrenaline, chase, 1.5, deltaTime)

	local targetFov = CameraConfig.BASE_FOV
	local fovRange = CameraConfig.FOV_SPEED_MAX - CameraConfig.FOV_SPEED_MIN
	local fovAlpha = math.clamp((speed - CameraConfig.FOV_SPEED_MIN) / fovRange, 0, 1)
	targetFov += (CameraConfig.MAX_FOV - CameraConfig.BASE_FOV) * fovAlpha
	targetFov += CameraConfig.ADRENALINE_FOV * adrenaline
	fov = approach(fov, targetFov, CameraConfig.FOV_LERP_SPEED, deltaTime)
	fovKick = approach(fovKick, 0, CameraConfig.FOV_KICK_DECAY, deltaTime)
	camera.FieldOfView = fov + fovKick

	updateShake(deltaTime)

	if camera.CameraType ~= Enum.CameraType.Scriptable or not isAlive() then
		bobWeight = approach(bobWeight, 0, CameraConfig.BOB_AMPLITUDE_LERP_SPEED, deltaTime)
		return
	end

	local targetWeight = if ExertionState.isRunning() then math.clamp(speed / CameraConfig.STRIDE_SPEED_MAX, 0.35, 1) else 0
	bobWeight = approach(bobWeight, targetWeight, CameraConfig.BOB_AMPLITUDE_LERP_SPEED, deltaTime)

	local phase = ExertionState.getStridePhase()
	local bobVertical = -math.abs(math.sin(phase)) * CameraConfig.BOB_VERTICAL_AMPLITUDE * bobWeight * intensity
	local bobHorizontal = math.sin(phase * 0.5) * CameraConfig.BOB_HORIZONTAL_AMPLITUDE * bobWeight * intensity
	local bobRoll = math.rad(math.sin(phase * 0.5) * CameraConfig.BOB_ROLL_AMPLITUDE * bobWeight * intensity)

	swayPhase += deltaTime * CameraConfig.SWAY_FREQUENCY * math.pi * 2
	local sway = math.sin(swayPhase) * CameraConfig.SWAY_AMPLITUDE * intensity

	local axis = InputController.getLateralAxis()
	local targetTilt = -axis * CameraConfig.TILT_MAX_ROLL
	local tiltSpeed = if math.abs(targetTilt) > math.abs(tilt) then CameraConfig.TILT_ENTER_SPEED else CameraConfig.TILT_RETURN_SPEED
	tilt = approach(tilt, targetTilt, tiltSpeed, deltaTime)

	local breathFrequency = CameraConfig.BREATH_FREQUENCY_CALM
		+ (CameraConfig.BREATH_FREQUENCY_EXERTED - CameraConfig.BREATH_FREQUENCY_CALM) * exertion
	breathPhase += deltaTime * breathFrequency * math.pi * 2
	local breathScale = (0.6 + exertion * 0.9) * intensity
	local breathVertical = math.sin(breathPhase) * CameraConfig.BREATH_AMPLITUDE * breathScale
	local breathPitch = math.rad(math.sin(breathPhase) * CameraConfig.BREATH_PITCH_AMPLITUDE * breathScale)

	local offsetX = bobHorizontal + sway + shakeOffsetX * intensity
	local offsetY = bobVertical + breathVertical + shakeOffsetY * intensity
	local offsetZ = shakeOffsetZ * intensity
	local rotationScale = CameraConfig.SHAKE_ROTATION_SCALE * intensity

	camera.CFrame = camera.CFrame
		* CFrame.new(offsetX, offsetY, offsetZ)
		* CFrame.Angles(
			breathPitch + shakeOffsetY * rotationScale,
			shakeOffsetX * rotationScale,
			math.rad(tilt * intensity) + bobRoll
		)
end

function CameraEffectsController.impulse(direction: Vector3, magnitude: number)
	local unit = if direction.Magnitude > 0 then direction.Unit else Vector3.yAxis
	shakeVelocityX += unit.X * magnitude
	shakeVelocityY += unit.Y * magnitude
	shakeVelocityZ += unit.Z * magnitude
end

function CameraEffectsController.fovKick(amount: number)
	fovKick += amount
end

function CameraEffectsController.init()
	if bound then
		return
	end
	bound = true
	ExertionState.init()
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, update)

	local function watchCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		local lastHealth = humanoid.Health
		humanoid.HealthChanged:Connect(function(health)
			if health < lastHealth - 0.001 then
				CameraEffectsController.impulse(Vector3.new(0.4, -1, 0.2), 3.2)
				BodyMotionController.impulse(-4.5, 2.5)
			end
			lastHealth = health
		end)
		humanoid.StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.Landed then
				CameraEffectsController.impulse(Vector3.new(0, -1, 0), 2.4)
			end
		end)
	end

	Players.LocalPlayer.CharacterAdded:Connect(watchCharacter)
	if Players.LocalPlayer.Character then
		task.spawn(watchCharacter, Players.LocalPlayer.Character)
	end
end

return CameraEffectsController
