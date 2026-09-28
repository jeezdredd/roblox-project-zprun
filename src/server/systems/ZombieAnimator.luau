--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)

local ZombieAnimator = {}

export type ZombieTracks = {
	idle: AnimationTrack?,
	walk: AnimationTrack?,
	run: AnimationTrack?,
	attack: AnimationTrack?,
	feeding: AnimationTrack?,
	rise: AnimationTrack?,
	jitter: number,
	phase: number,
}

local IDLE_VARIANTS = { AssetIds.animation.zombie.idle_a, AssetIds.animation.zombie.idle_b }
local WALK_VARIANTS = { AssetIds.animation.zombie.walk_shuffle }
local RUN_VARIANTS = { AssetIds.animation.zombie.run_ragged }

local WALK_SPEED_REFERENCE = 6
local RUN_SPEED_REFERENCE = 12
local SPEED_RATIO_MIN = 0.35
local SPEED_RATIO_MAX = 1.6
local JITTER_MIN = 0.9
local JITTER_MAX = 1.12
local PHASE_SETTLE = 0.1

local function pickVariant(variants: { number }, rng: Random): number
	if #variants == 0 then
		return 0
	end
	return variants[rng:NextInteger(1, #variants)]
end

local function loadTrack(animator: Animator, assetId: number, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack?
	if assetId <= 0 then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(assetId)
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	track.Looped = looped
	track.Priority = priority
	return track
end

local function playLooped(track: AnimationTrack, fade: number, phase: number, speed: number)
	track:Play(fade)
	track:AdjustSpeed(speed)
	task.delay(PHASE_SETTLE, function()
		if track.IsPlaying and track.Length > 0 then
			track.TimePosition = phase * track.Length
		end
	end)
end

local function eachTrack(tracks: ZombieTracks, fn: (AnimationTrack) -> ())
	for _, track in { tracks.idle, tracks.walk, tracks.run, tracks.attack, tracks.feeding, tracks.rise } do
		if track then
			fn(track)
		end
	end
end

function ZombieAnimator.setup(model: Model, humanoid: Humanoid, rng: Random): ZombieTracks?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	if not animator or not animator:IsA("Animator") then
		return nil
	end

	local tracks: ZombieTracks = {
		idle = loadTrack(animator, pickVariant(IDLE_VARIANTS, rng), true, Enum.AnimationPriority.Idle),
		walk = loadTrack(animator, pickVariant(WALK_VARIANTS, rng), true, Enum.AnimationPriority.Movement),
		run = loadTrack(animator, pickVariant(RUN_VARIANTS, rng), true, Enum.AnimationPriority.Movement),
		attack = loadTrack(animator, AssetIds.animation.zombie.attack_lunge, false, Enum.AnimationPriority.Action),
		feeding = loadTrack(animator, AssetIds.animation.zombie.feeding, true, Enum.AnimationPriority.Action2),
		rise = loadTrack(animator, AssetIds.animation.zombie.idle_c, false, Enum.AnimationPriority.Action3),
		jitter = rng:NextNumber(JITTER_MIN, JITTER_MAX),
		phase = rng:NextNumber(),
	}

	if tracks.idle then
		playLooped(tracks.idle, 0.3, tracks.phase, tracks.jitter)
	end

	local _ = model
	return tracks
end

function ZombieAnimator.setMode(tracks: ZombieTracks?, mode: string, fast: boolean, walkSpeed: number)
	if not tracks then
		return
	end
	local moving = mode == "Alert" or mode == "Attack"
	local move = if fast then tracks.run else tracks.walk
	local other = if fast then tracks.walk else tracks.run
	local reference = if fast then RUN_SPEED_REFERENCE else WALK_SPEED_REFERENCE
	local speed = math.clamp(walkSpeed / reference, SPEED_RATIO_MIN, SPEED_RATIO_MAX) * tracks.jitter

	if other and other.IsPlaying then
		other:Stop(0.2)
	end

	if mode == "Attack" and tracks.attack and not tracks.attack.IsPlaying then
		tracks.attack:Play(0.1)
		tracks.attack:AdjustSpeed(tracks.jitter)
	end

	if moving then
		if tracks.idle and tracks.idle.IsPlaying then
			tracks.idle:Stop(0.2)
		end
		if move then
			if move.IsPlaying then
				move:AdjustSpeed(speed)
			else
				playLooped(move, 0.2, tracks.phase, speed)
			end
		end
	else
		if move and move.IsPlaying then
			move:Stop(0.2)
		end
		if tracks.idle and not tracks.idle.IsPlaying then
			playLooped(tracks.idle, 0.3, tracks.phase, tracks.jitter)
		end
	end
end

function ZombieAnimator.hasFeedingClip(tracks: ZombieTracks?): boolean
	return tracks ~= nil and tracks.feeding ~= nil
end

function ZombieAnimator.setSpeed(tracks: ZombieTracks?, fast: boolean, walkSpeed: number)
	if not tracks then
		return
	end
	local move = if fast then tracks.run else tracks.walk
	if move and move.IsPlaying then
		local reference = if fast then RUN_SPEED_REFERENCE else WALK_SPEED_REFERENCE
		move:AdjustSpeed(math.clamp(walkSpeed / reference, SPEED_RATIO_MIN, SPEED_RATIO_MAX) * tracks.jitter)
	end
end

function ZombieAnimator.playFeeding(tracks: ZombieTracks?)
	if not tracks or not tracks.feeding then
		return
	end
	for _, track in { tracks.idle, tracks.walk, tracks.run } do
		if track and track.IsPlaying then
			track:Stop(0.2)
		end
	end
	if not tracks.feeding.IsPlaying then
		playLooped(tracks.feeding, 0.2, tracks.phase, tracks.jitter)
	end
end

function ZombieAnimator.stopFeeding(tracks: ZombieTracks?)
	if tracks and tracks.feeding and tracks.feeding.IsPlaying then
		tracks.feeding:Stop(0.25)
	end
end

function ZombieAnimator.holdLying(tracks: ZombieTracks?): boolean
	if not tracks or not tracks.rise then
		return false
	end
	for _, track in { tracks.idle, tracks.walk, tracks.run } do
		if track and track.IsPlaying then
			track:Stop(0)
		end
	end
	tracks.rise:Play(0)
	tracks.rise.TimePosition = 0
	tracks.rise:AdjustSpeed(0)
	return true
end

function ZombieAnimator.playRise(tracks: ZombieTracks?): number
	if not tracks or not tracks.rise then
		return 0
	end
	if not tracks.rise.IsPlaying then
		tracks.rise:Play(0)
	end
	tracks.rise:AdjustSpeed(tracks.jitter)
	return tracks.rise.Length / math.max(tracks.jitter, 0.1)
end

function ZombieAnimator.stopAll(tracks: ZombieTracks?)
	if not tracks then
		return
	end
	eachTrack(tracks, function(track)
		if track.IsPlaying then
			track:Stop(0.15)
		end
	end)
end

return ZombieAnimator
