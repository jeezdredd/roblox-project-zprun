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
}

local IDLE_VARIANTS = { AssetIds.animation.zombie.idle_a, AssetIds.animation.zombie.idle_b, AssetIds.animation.zombie.idle_c }

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

function ZombieAnimator.setup(model: Model, humanoid: Humanoid, seedPosition: Vector3): ZombieTracks?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	if not animator or not animator:IsA("Animator") then
		return nil
	end

	local variantIndex = (math.floor(math.abs(seedPosition.X) + math.abs(seedPosition.Z)) % #IDLE_VARIANTS) + 1

	local tracks: ZombieTracks = {
		idle = loadTrack(animator, IDLE_VARIANTS[variantIndex], true, Enum.AnimationPriority.Idle),
		walk = loadTrack(animator, AssetIds.animation.zombie.walk_shuffle, true, Enum.AnimationPriority.Movement),
		run = loadTrack(animator, AssetIds.animation.zombie.run_ragged, true, Enum.AnimationPriority.Movement),
		attack = loadTrack(animator, AssetIds.animation.zombie.attack_lunge, false, Enum.AnimationPriority.Action),
		feeding = loadTrack(animator, AssetIds.animation.zombie.feeding, true, Enum.AnimationPriority.Action2),
	}

	if tracks.idle then
		tracks.idle.TimePosition = (variantIndex - 1) * 0.37
		tracks.idle:Play(0.3)
	end

	local _ = model
	return tracks
end

function ZombieAnimator.setMoving(tracks: ZombieTracks?, moving: boolean, fast: boolean)
	if not tracks then
		return
	end
	local move = if fast then tracks.run else tracks.walk
	local other = if fast then tracks.walk else tracks.run

	if other and other.IsPlaying then
		other:Stop(0.2)
	end
	if moving then
		if tracks.idle and tracks.idle.IsPlaying then
			tracks.idle:Stop(0.2)
		end
		if move and not move.IsPlaying then
			move:Play(0.2)
		end
	else
		if move and move.IsPlaying then
			move:Stop(0.2)
		end
		if tracks.idle and not tracks.idle.IsPlaying then
			tracks.idle:Play(0.3)
		end
	end
end

function ZombieAnimator.playFeeding(tracks: ZombieTracks?)
	if not tracks or not tracks.feeding then
		return
	end
	if not tracks.feeding.IsPlaying then
		tracks.feeding:Play(0.2)
	end
end

function ZombieAnimator.stopAll(tracks: ZombieTracks?)
	if not tracks then
		return
	end
	for _, track in { tracks.idle, tracks.walk, tracks.run, tracks.attack, tracks.feeding } do
		if track and track.IsPlaying then
			track:Stop(0.15)
		end
	end
end

return ZombieAnimator
