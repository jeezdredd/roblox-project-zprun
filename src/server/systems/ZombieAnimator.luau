--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local ZombieSkins = require(ReplicatedStorage.Shared.config.ZombieSkins)

local ZombieAnimator = {}

type Move = { track: AnimationTrack, speed: number }

export type ZombieTracks = {
	idle: AnimationTrack?,
	walk: AnimationTrack?,
	run: AnimationTrack?,
	attack: AnimationTrack?,
	feeding: AnimationTrack?,
	rise: AnimationTrack?,
	-- a looped idle at Core priority that never stops: whenever the other tracks are
	-- fading (every idle/walk/run switch) the rig falls back to this instead of its rest
	-- pose, which is a T-pose
	base: AnimationTrack?,
	jitter: number,
	phase: number,
	-- skinned rigs (ZombieSkins): every walk and run clip with its ground speed, the one
	-- playing, and the one-shots
	skinned: boolean,
	moves: { Move },
	move: Move?,
	attacks: { AnimationTrack },
	deaths: { AnimationTrack },
	hit: AnimationTrack?,
	spotted: AnimationTrack?,
	dead: boolean,
}

local IDLE_VARIANTS = { AssetIds.animation.zombie.idle_a, AssetIds.animation.zombie.idle_b }
local WALK_VARIANTS = { AssetIds.animation.zombie.walk_shuffle }
local RUN_VARIANTS = { AssetIds.animation.zombie.run_ragged }

-- The Dormant rise and the Feeding pose take the Mixamo clips once they are uploaded
-- (docs/animation/third-person-locomotion.md) and the Quaternius clips until then.
local function uploaded(ids: { number }): { number }
	local out = {}
	for _, id in ids do
		if id > 0 then
			table.insert(out, id)
		end
	end
	return out
end

local RISE_VARIANTS = uploaded({ AssetIds.animation.zombie.stand_up_back, AssetIds.animation.zombie.stand_up_stomach })
if #RISE_VARIANTS == 0 then
	RISE_VARIANTS = { AssetIds.animation.zombie.idle_c }
end
local FEEDING_ID = if AssetIds.animation.zombie.biting_ground > 0 then AssetIds.animation.zombie.biting_ground else AssetIds.animation.zombie.feeding

-- Ground speed each clip covers at playback speed 1 on the walker2 rig (FULL_SCALE 0.92),
-- measured 2026-09-28 from the planted foot's travel over 60 samples of the cycle: walk
-- 2.56 studs/s on the leading foot (the shuffle drags the other), run about 4.3. The old
-- references (6 and 12) played the walk at half speed and the run at a third of what the
-- body covered, so the feet skated. Very fast zombies still outrun the clip at the cap;
-- past about 2.2x the cycle reads as frantic rather than fast.
local WALK_SPEED_REFERENCE = 2.5
local RUN_SPEED_REFERENCE = 4.3
local SPEED_RATIO_MIN = 0.35
local SPEED_RATIO_MAX = 2.2
local JITTER_MIN = 0.9
local JITTER_MAX = 1.12
local PHASE_SETTLE = 0.1

-- Skinned rigs pick, from all their walk and run clips, the one whose ground speed is
-- closest (as a ratio) to the zombie's speed and play it at speed / groundSpeed, so the
-- feet stay planted. A new clip has to win by MOVE_SWITCH_MARGIN (log ratio) so the
-- cycle does not flap between two clips while the AI eases the speed.
local MOVE_RATIO_MIN = 0.55
local MOVE_RATIO_MAX = 2.4
local MOVE_SWITCH_MARGIN = 0.25
local MOVE_FADE = 0.3
-- a swing never holds the zombie longer than this (Hazmat's is a 3.5 s clip)
local ATTACK_MAX_DURATION = 1.8
local ATTACK_FALLBACK_DURATION = 0.9
-- the Hazmat scream when it first notices a player, sped up so it does not stand for 5 s
local SPOTTED_RATE = 1.4
-- a flinch stops the legs, so only zombies standing or shuffling get one
local HIT_MAX_SPEED = 4
local HIT_RATE = 1.25
-- a death clip is frozen this long before its end (a non-looped track that reaches its
-- end stops and the rig would stand back up)
local DEATH_HOLD_MARGIN = 0.1

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

-- Length is 0 until the clip has loaded.
local function waitLength(track: AnimationTrack, timeout: number): number
	local waited = 0
	while track.Length <= 0 and waited < timeout do
		waited += task.wait()
	end
	return track.Length
end

local function holdAtEnd(track: AnimationTrack, rate: number)
	task.spawn(function()
		local length = waitLength(track, 3)
		if length <= 0 then
			return
		end
		task.wait(math.max((length - track.TimePosition) / rate - DEATH_HOLD_MARGIN, 0))
		if track.IsPlaying then
			track.TimePosition = math.max(length - DEATH_HOLD_MARGIN, 0)
			track:AdjustSpeed(0)
		end
	end)
end

local function eachTrack(tracks: ZombieTracks, fn: (AnimationTrack) -> ())
	for _, track in { tracks.idle, tracks.walk, tracks.run, tracks.attack, tracks.feeding, tracks.rise, tracks.base, tracks.hit, tracks.spotted } do
		if track then
			fn(track)
		end
	end
	for _, move in tracks.moves do
		fn(move.track)
	end
	for _, list in { tracks.attacks, tracks.deaths } do
		for _, track in list do
			fn(track)
		end
	end
end

local function newTracks(rng: Random): ZombieTracks
	return {
		jitter = rng:NextNumber(JITTER_MIN, JITTER_MAX),
		phase = rng:NextNumber(),
		skinned = false,
		moves = {},
		attacks = {},
		deaths = {},
		dead = false,
	}
end

local function pickClip(clips: { ZombieSkins.Clip }, rng: Random): number
	if #clips == 0 then
		return 0
	end
	return clips[rng:NextInteger(1, #clips)].id
end

local function setupSkinned(animator: Animator, skin: ZombieSkins.Skin, rng: Random): ZombieTracks
	local tracks = newTracks(rng)
	tracks.skinned = true
	tracks.base = loadTrack(animator, pickClip(skin.idle, rng), true, Enum.AnimationPriority.Core)
	tracks.idle = loadTrack(animator, pickClip(skin.idle, rng), true, Enum.AnimationPriority.Idle)
	-- Each zombie keeps one of its skin's walks and one of its runs, picked at random, so a
	-- crowd of one skin does not move in step: with every clip loaded the speed fit always
	-- chose the same one (walk_a and walk_b share a ground speed, walk_b never played).
	for _, group in { skin.walk, skin.run } do
		local usable: { ZombieSkins.Clip } = {}
		for _, clip in group do
			if clip.speed > 0 then
				table.insert(usable, clip)
			end
		end
		if #usable > 0 then
			local clip = usable[rng:NextInteger(1, #usable)]
			local track = loadTrack(animator, clip.id, true, Enum.AnimationPriority.Movement)
			if track then
				table.insert(tracks.moves, { track = track, speed = clip.speed })
			end
		end
	end
	for _, clip in skin.attack do
		local track = loadTrack(animator, clip.id, false, Enum.AnimationPriority.Action)
		if track then
			table.insert(tracks.attacks, track)
		end
	end
	for _, clip in skin.death do
		local track = loadTrack(animator, clip.id, false, Enum.AnimationPriority.Action4)
		if track then
			table.insert(tracks.deaths, track)
		end
	end
	if skin.hit then
		tracks.hit = loadTrack(animator, skin.hit.id, false, Enum.AnimationPriority.Action2)
	end
	if skin.spotted then
		tracks.spotted = loadTrack(animator, skin.spotted.id, false, Enum.AnimationPriority.Action)
	end
	return tracks
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

	local skinName = model:GetAttribute("ZombieSkin")
	local skin = if typeof(skinName) == "string" then ZombieSkins.get(skinName) else nil
	local tracks: ZombieTracks
	if skin then
		tracks = setupSkinned(animator, skin, rng)
	else
		tracks = newTracks(rng)
		tracks.idle = loadTrack(animator, pickVariant(IDLE_VARIANTS, rng), true, Enum.AnimationPriority.Idle)
		tracks.walk = loadTrack(animator, pickVariant(WALK_VARIANTS, rng), true, Enum.AnimationPriority.Movement)
		tracks.run = loadTrack(animator, pickVariant(RUN_VARIANTS, rng), true, Enum.AnimationPriority.Movement)
		tracks.attack = loadTrack(animator, AssetIds.animation.zombie.attack_lunge, false, Enum.AnimationPriority.Action)
		tracks.feeding = loadTrack(animator, FEEDING_ID, true, Enum.AnimationPriority.Action2)
		tracks.rise = loadTrack(animator, pickVariant(RISE_VARIANTS, rng), false, Enum.AnimationPriority.Action3)
		tracks.base = loadTrack(animator, pickVariant(IDLE_VARIANTS, rng), true, Enum.AnimationPriority.Core)
	end

	if tracks.base then
		playLooped(tracks.base, 0, tracks.phase, tracks.jitter)
	end
	if tracks.idle then
		playLooped(tracks.idle, 0.3, tracks.phase, tracks.jitter)
	end
	return tracks
end

local function moveRate(move: Move, speed: number): number
	return math.clamp(speed / move.speed, MOVE_RATIO_MIN, MOVE_RATIO_MAX)
end

-- How wrong a clip looks at `speed`: mostly the skating left once its playback rate is
-- clamped, a little for how far from its natural rate it plays.
local function moveScore(move: Move, speed: number): number
	local wanted = math.max(speed, 0.1) / move.speed
	local rate = math.clamp(wanted, MOVE_RATIO_MIN, MOVE_RATIO_MAX)
	return math.abs(math.log(wanted / rate)) + 0.3 * math.abs(math.log(rate))
end

local function chooseMove(tracks: ZombieTracks, speed: number): Move?
	local best: Move? = nil
	local bestScore = math.huge
	for _, move in tracks.moves do
		local score = moveScore(move, speed)
		if score < bestScore then
			best, bestScore = move, score
		end
	end
	local current = tracks.move
	if current and best ~= current and moveScore(current, speed) - bestScore < MOVE_SWITCH_MARGIN then
		return current
	end
	return best
end

local function driveMove(tracks: ZombieTracks, speed: number)
	local move = chooseMove(tracks, speed)
	if not move then
		return
	end
	local current = tracks.move
	if current ~= move then
		if current and current.track.IsPlaying then
			current.track:Stop(MOVE_FADE)
		end
		tracks.move = move
		playLooped(move.track, MOVE_FADE, tracks.phase, moveRate(move, speed))
	elseif not move.track.IsPlaying then
		playLooped(move.track, 0.2, tracks.phase, moveRate(move, speed))
	else
		move.track:AdjustSpeed(moveRate(move, speed))
	end
end

local function stopMove(tracks: ZombieTracks, fade: number)
	local current = tracks.move
	if current and current.track.IsPlaying then
		current.track:Stop(fade)
	end
	tracks.move = nil
end

local function setModeSkinned(tracks: ZombieTracks, mode: string, walkSpeed: number)
	local moving = mode == "Alert" or mode == "Attack"
	if moving then
		if tracks.idle and tracks.idle.IsPlaying then
			tracks.idle:Stop(0.25)
		end
		if tracks.spotted and tracks.spotted.IsPlaying then
			tracks.spotted:Stop(0.3)
		end
		driveMove(tracks, walkSpeed)
	else
		stopMove(tracks, MOVE_FADE)
		if tracks.idle and not tracks.idle.IsPlaying then
			playLooped(tracks.idle, 0.3, tracks.phase, tracks.jitter)
		end
	end
end

function ZombieAnimator.setMode(tracks: ZombieTracks?, mode: string, fast: boolean, walkSpeed: number)
	if not tracks or tracks.dead then
		return
	end
	if tracks.skinned then
		setModeSkinned(tracks, mode, walkSpeed)
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
	if not tracks or tracks.dead then
		return
	end
	if tracks.skinned then
		if tracks.move then
			driveMove(tracks, walkSpeed)
		end
		return
	end
	local move = if fast then tracks.run else tracks.walk
	if move and move.IsPlaying then
		local reference = if fast then RUN_SPEED_REFERENCE else WALK_SPEED_REFERENCE
		move:AdjustSpeed(math.clamp(walkSpeed / reference, SPEED_RATIO_MIN, SPEED_RATIO_MAX) * tracks.jitter)
	end
end

local function attacking(tracks: ZombieTracks): boolean
	if tracks.attack and tracks.attack.IsPlaying then
		return true
	end
	for _, track in tracks.attacks do
		if track.IsPlaying then
			return true
		end
	end
	return false
end

-- Swing at a player in reach. Returns how long the swing lasts (0 when none started).
function ZombieAnimator.attack(tracks: ZombieTracks?, rng: Random): number
	if not tracks or tracks.dead or attacking(tracks) then
		return 0
	end
	local track = if #tracks.attacks > 0 then tracks.attacks[rng:NextInteger(1, #tracks.attacks)] else tracks.attack
	if not track then
		return 0
	end
	local rate = tracks.jitter
	if track.Length > 0 then
		rate = math.max(rate, track.Length / ATTACK_MAX_DURATION)
	end
	if tracks.spotted and tracks.spotted.IsPlaying then
		tracks.spotted:Stop(0.1)
	end
	if tracks.hit and tracks.hit.IsPlaying then
		tracks.hit:Stop(0.1)
	end
	track:Play(0.1)
	track:AdjustSpeed(rate)
	return if track.Length > 0 then track.Length / rate else ATTACK_FALLBACK_DURATION
end

-- Flinch from a bullet; `speed` is how fast the zombie is moving.
function ZombieAnimator.hit(tracks: ZombieTracks?, speed: number)
	if not tracks or tracks.dead or not tracks.hit or speed > HIT_MAX_SPEED or attacking(tracks) then
		return
	end
	tracks.hit:Play(0.05)
	tracks.hit:AdjustSpeed(HIT_RATE)
end

-- Scream on first noticing a player. Returns how long it lasts (0 when there is none).
function ZombieAnimator.spotted(tracks: ZombieTracks?): number
	local track = tracks and tracks.spotted
	if not tracks or tracks.dead or not track or track.IsPlaying then
		return 0
	end
	track:Play(0.25)
	track:AdjustSpeed(SPOTTED_RATE)
	return track.Length / SPOTTED_RATE
end

-- Play one of the skin's death clips and hold its last frame. Returns false when the rig
-- has none (the body then falls as before).
function ZombieAnimator.playDeath(tracks: ZombieTracks?, rng: Random): boolean
	if not tracks or tracks.dead or #tracks.deaths == 0 then
		return false
	end
	tracks.dead = true
	eachTrack(tracks, function(track)
		if track.IsPlaying and track ~= tracks.base then
			track:Stop(0.15)
		end
	end)
	tracks.move = nil
	local track = tracks.deaths[rng:NextInteger(1, #tracks.deaths)]
	track:Play(0.1)
	track:AdjustSpeed(1)
	holdAtEnd(track, 1)
	return true
end

-- Lay a corpse down in the last frame of one of its skin's death clips. The corpse has no
-- Humanoid, so an AnimationController drives it; call once the model is in the world.
function ZombieAnimator.poseCorpse(model: Model, rng: Random): boolean
	local skinName = model:GetAttribute("ZombieSkin")
	local skin = if typeof(skinName) == "string" then ZombieSkins.get(skinName) else nil
	if not skin or #skin.death == 0 then
		return false
	end
	local controller = Instance.new("AnimationController")
	controller.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = controller
	local track = loadTrack(animator, pickClip(skin.death, rng), false, Enum.AnimationPriority.Action4)
	if not track then
		controller:Destroy()
		return false
	end
	track:Play(0)
	track:AdjustSpeed(0)
	task.spawn(function()
		local length = waitLength(track, 5)
		if length > 0 and track.IsPlaying then
			track.TimePosition = math.max(length - DEATH_HOLD_MARGIN, 0)
		end
	end)
	return true
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

-- Recycling: stop everything and free the tracks, since the next spawn from the pool
-- loads a fresh set on the same Animator.
function ZombieAnimator.stopAll(tracks: ZombieTracks?)
	if not tracks then
		return
	end
	eachTrack(tracks, function(track)
		if track.IsPlaying then
			track:Stop(0)
		end
		track:Destroy()
	end)
	tracks.move = nil
end

return ZombieAnimator
