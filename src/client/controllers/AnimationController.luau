--!strict

-- The local character's locomotion clips. With a weapon held the gait comes from the
-- weapon class's clip set (AnimationsConfig.locomotionSets, LocomotionMath): idle,
-- walk, run, sprint and the strafes, blended by weight and played at the ground speed.
-- A gait whose clip has not been uploaded falls back inside the set and then to the
-- generic Run, so the character never stops animating. The tracks replicate through the
-- Animator, so teammates see the same gait; the body layer (src/client/body) writes its
-- aim and hand IK after the Animator on top of whatever plays here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationsConfig = require(ReplicatedStorage.Shared.config.AnimationsConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local BodyMath = require(ReplicatedStorage.Shared.util.BodyMath)
local LocomotionMath = require(ReplicatedStorage.Shared.util.LocomotionMath)
local ExertionState = require(script.Parent.ExertionState)
local InputController = require(script.Parent.InputController)

local AnimationController = {}

type LoadedClip = {
	config: AnimationsConfig.ClipConfig,
	track: AnimationTrack,
	weight: number,
}

local tracks: { [string]: LoadedClip } = {}
local available: { [string]: boolean } = {}
local animator: Animator? = nil
local started = false
local sprinting = false
local currentGait: LocomotionMath.Gait = "idle"

local function approach(current: number, target: number, speed: number, deltaTime: number): number
	return current + (target - current) * (1 - math.exp(-speed * deltaTime))
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

-- The engine gives every character its default Animate script, whose run and walk
-- tracks played under ours at full weight (two gaits blended: the stumbling run seen on
-- 2026-09-30). The locomotion here replaces it, so it goes, with its tracks.
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
	if AnimationsConfig.ENABLED and next(tracks) ~= nil then
		removeDefaultAnimate(character, foundAnimator)
		character.ChildAdded:Connect(function(child)
			if child.Name == "Animate" and child:IsA("LocalScript") then
				removeDefaultAnimate(character, foundAnimator)
			end
		end)
	end
end

-- The clip set of the weapon the local player holds.
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
	local running = alive and ExertionState.isRunning()
	local speed = ExertionState.getSpeed()
	local axis = InputController.getLateralAxis()

	sprinting = running and BodyMath.sprintTarget(speed, AnimationsConfig.SPRINT_SPEED, AnimationsConfig.SPRINT_HYSTERESIS, sprinting)
	local gait = LocomotionMath.gaitFor(running, speed, axis, sprinting, {
		walkMax = AnimationsConfig.WALK_SPEED_MAX,
		strafeAxis = AnimationsConfig.STRAFE_AXIS,
		strafeMaxSpeed = AnimationsConfig.STRAFE_SPEED_MAX,
	})
	currentGait = gait
	local set = currentSet()
	local targets = LocomotionMath.targets(set, gait, available)
	-- the set's measured clip speeds, or the legacy Run's when the set has no clip
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
			-- the legacy strafes are additive leans and keep their own rate
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

-- Plays the set's one-shot for `kind` ("reload", "hit") for the weapon held, when its
-- clip exists.
function AnimationController.playAction(kind: string)
	local set = AnimationsConfig.locomotionSets[currentSet()]
	local clipId = set and set[kind]
	if clipId then
		AnimationController.playOneShot(clipId)
	end
end

function AnimationController.hasClips(): boolean
	return next(tracks) ~= nil
end

-- The gait playing right now, for overlays and the yard.
function AnimationController.currentGait(): LocomotionMath.Gait
	return currentGait
end

-- The asset ids of a weapon class's locomotion set, keyed by gait and one-shot name
-- (idle, walk, run, sprint, strafe_left, strafe_right, reload, hit); a slot whose clip
-- is not uploaded yet carries 0. For the yard mannequins and any other rig that wants to
-- run the same gaits as a player of that class.
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
