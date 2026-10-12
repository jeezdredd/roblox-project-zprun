--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationsConfig = require(ReplicatedStorage.Shared.config.AnimationsConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local BodyMath = require(ReplicatedStorage.Shared.util.BodyMath)
local LocomotionMath = require(ReplicatedStorage.Shared.util.LocomotionMath)
local ExertionState = require(script.Parent.ExertionState)

local AnimationController = {}

type LoadedClip = {
	config: AnimationsConfig.ClipConfig,
	track: AnimationTrack,
	weight: number,
}

local tracks: { [string]: LoadedClip } = {}
local available: { [string]: boolean } = {}
local sitTrack: AnimationTrack? = nil
local seated = false
local animator: Animator? = nil
local started = false
local sprinting = false
local currentGait: LocomotionMath.Gait = "idle"

local function approach(current: number, target: number, speed: number, deltaTime: number): number
	return current + (target - current) * (1 - math.exp(-speed * deltaTime))
end

local function loadTrack(foundAnimator: Animator, config: AnimationsConfig.ClipConfig): AnimationTrack?
	if config.assetId <= 0 then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.Name = config.id
	animation.AnimationId = "rbxassetid://" .. tostring(config.assetId)
	local ok, track = pcall(function()
		return foundAnimator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	track.Priority = config.priority
	track.Looped = config.looped
	return track
end

local function loadClip(foundAnimator: Animator, config: AnimationsConfig.ClipConfig)
	if config.assetId <= 0 then
		return
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
		available[config.id] = true
	end
end

local function removeDefaultAnimate(character: Model, foundAnimator: Animator)
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate:Destroy()
	end
	for _, track in foundAnimator:GetPlayingAnimationTracks() do
		local ours = false
		for _, loaded in tracks do
			if loaded.track == track then
				ours = true
				break
			end
		end
		if not ours and track.Priority == Enum.AnimationPriority.Core then
			track:Stop(0)
		end
	end
end

local function loadClips(character: Model)
	tracks = {}
	available = {}
	animator = nil
	sitTrack = nil
	seated = false

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
		loadClip(foundAnimator, config)
	end
	for _, config in AnimationsConfig.locomotionClips do
		loadClip(foundAnimator, config)
	end
	sitTrack = loadTrack(foundAnimator, AnimationsConfig.SIT_CLIP)
	if AnimationsConfig.ENABLED and next(tracks) ~= nil then
		removeDefaultAnimate(character, foundAnimator)
		character.ChildAdded:Connect(function(child)
			if child.Name == "Animate" and child:IsA("LocalScript") then
				removeDefaultAnimate(character, foundAnimator)
			end
		end)
	end
end

local function currentSet(): string
	local weaponId = Players.LocalPlayer:GetAttribute("WeaponId")
	local config = if typeof(weaponId) == "string" then WeaponsConfig.get(weaponId) else nil
	return LocomotionMath.setFor(if config then config.class else nil)
end

local function update(deltaTime: number)
	if not AnimationsConfig.ENABLED or not animator then
		return
	end

	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0

	local nowSeated = alive and humanoid ~= nil and humanoid.SeatPart ~= nil
	if nowSeated ~= seated then
		seated = nowSeated
		local sit = sitTrack
		if sit then
			if seated then
				sit:Play(AnimationsConfig.SIT_FADE)
				sit:AdjustWeight(AnimationsConfig.SIT_CLIP.weight, AnimationsConfig.SIT_FADE)
			else
				sit:Stop(AnimationsConfig.SIT_FADE)
			end
		end
	end
	if seated then
		for _, loaded in tracks do
			if loaded.config.looped and loaded.track.IsPlaying then
				loaded.weight = 0
				loaded.track:Stop(AnimationsConfig.SIT_FADE)
			end
		end
		currentGait = "idle"
		return
	end

	local running = alive and ExertionState.isRunning()
	local speed = ExertionState.getSpeed()
	local axis = 0
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and speed > 0.5 then
		local velocity = root.CFrame:VectorToObjectSpace(root.AssemblyLinearVelocity)
		local ground = Vector2.new(velocity.X, velocity.Z).Magnitude
		axis = if ground > 0.5 then math.clamp(velocity.X / ground, -1, 1) else 0
	end

	sprinting = running and BodyMath.sprintTarget(speed, AnimationsConfig.SPRINT_SPEED, AnimationsConfig.SPRINT_HYSTERESIS, sprinting)
	local gait = LocomotionMath.gaitFor(running, speed, axis, sprinting, {
		walkMax = AnimationsConfig.WALK_SPEED_MAX,
		strafeAxis = AnimationsConfig.STRAFE_AXIS,
	})
	currentGait = gait
	local set = currentSet()
	local targets = LocomotionMath.targets(set, gait, available)
	local references = if targets.Run then AnimationsConfig.GAIT_REFERENCE else (AnimationsConfig.SET_GAIT_REFERENCE[set] or AnimationsConfig.GAIT_REFERENCE)
	local ratio = LocomotionMath.playbackRatio(gait, speed, references, AnimationsConfig.RUN_SPEED_MIN, AnimationsConfig.RUN_SPEED_MAX)

	for id, loaded in tracks do
		if not loaded.config.looped then
			continue
		end
		local target = targets[id] or 0
		loaded.weight = approach(loaded.weight, target, AnimationsConfig.BLEND_SPEED, deltaTime)

		if loaded.weight > 0.01 then
			if not loaded.track.IsPlaying then
				loaded.track:Play(0.15)
			end
			loaded.track:AdjustWeight(loaded.weight, 0.1)
			if target > 0 and id ~= "StrafeLeft" and id ~= "StrafeRight" then
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

function AnimationController.playAction(kind: string)
	local set = AnimationsConfig.locomotionSets[currentSet()]
	local clipId = set and set[kind]
	if clipId then
		AnimationController.playOneShot(clipId)
	end
end

function AnimationController.isSeated(): boolean
	return seated
end

function AnimationController.hasClips(): boolean
	return next(tracks) ~= nil
end

function AnimationController.currentGait(): LocomotionMath.Gait
	return currentGait
end

function AnimationController.clipSetFor(class: string?): { [string]: number }
	local set = AnimationsConfig.locomotionSets[LocomotionMath.setFor(class)]
	local ids: { [string]: number } = {}
	if not set then
		return ids
	end
	for name, clipId in set do
		local config = AnimationsConfig.locomotionClips[clipId]
		ids[name] = if config then config.assetId else 0
	end
	return ids
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
