--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationsConfig = require(ReplicatedStorage.Shared.config.AnimationsConfig)
local ExertionState = require(script.Parent.ExertionState)
local InputController = require(script.Parent.InputController)

local AnimationController = {}

type LoadedClip = {
	config: AnimationsConfig.ClipConfig,
	track: AnimationTrack,
	weight: number,
}

local tracks: { [string]: LoadedClip } = {}
local animator: Animator? = nil
local started = false

local function approach(current: number, target: number, speed: number, deltaTime: number): number
	return current + (target - current) * (1 - math.exp(-speed * deltaTime))
end

local function loadClips(character: Model)
	tracks = {}
	animator = nil

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local foundAnimator = humanoid:WaitForChild("Animator", 5)
	if not foundAnimator or not foundAnimator:IsA("Animator") then
		return
	end
	animator = foundAnimator

	for _, config in AnimationsConfig.clips do
		if config.assetId <= 0 then
			continue
		end
		local animation = Instance.new("Animation")
		animation.Name = config.id
		animation.AnimationId = "rbxassetid://" .. tostring(config.assetId)

		local ok, track = pcall(function()
			return foundAnimator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Priority = config.priority
			track.Looped = config.looped
			tracks[config.id] = { config = config, track = track, weight = 0 }
		end
	end
end

local function update(deltaTime: number)
	if not AnimationsConfig.ENABLED or not animator then
		return
	end

	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0
	local running = alive and ExertionState.isRunning()
	local speed = ExertionState.getSpeed()
	local axis = InputController.getLateralAxis()

	local targets: { [string]: number } = {
		Run = if running then 1 else 0,
		StrafeLeft = if running and axis < 0 then 1 else 0,
		StrafeRight = if running and axis > 0 then 1 else 0,
	}

	for id, loaded in tracks do
		local target = targets[id]
		if target == nil then
			continue
		end
		loaded.weight = approach(loaded.weight, target, AnimationsConfig.BLEND_SPEED, deltaTime)

		if loaded.weight > 0.01 then
			if not loaded.track.IsPlaying then
				loaded.track:Play(0.15)
			end
			loaded.track:AdjustWeight(loaded.weight, 0.1)
			if id == "Run" then
				local ratio = math.clamp(speed / AnimationsConfig.RUN_SPEED_REFERENCE, AnimationsConfig.RUN_SPEED_MIN, AnimationsConfig.RUN_SPEED_MAX)
				loaded.track:AdjustSpeed(ratio * loaded.config.speed)
			end
		elseif loaded.track.IsPlaying then
			loaded.track:Stop(0.2)
		end
	end
end

function AnimationController.playOneShot(clipId: string)
	local loaded = tracks[clipId]
	if not loaded then
		return
	end
	loaded.track:Play(0.1)
	loaded.track:AdjustWeight(loaded.config.weight, 0.1)
end

function AnimationController.hasClips(): boolean
	return next(tracks) ~= nil
end

function AnimationController.init()
	if started then
		return
	end
	started = true
	ExertionState.init()

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function(character)
		task.spawn(loadClips, character)
	end)
	if player.Character then
		task.spawn(loadClips, player.Character)
	end

	RunService.Heartbeat:Connect(update)
end

return AnimationController
