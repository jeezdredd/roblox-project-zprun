--!strict

-- Shared one-shot playback. With the spatial audio engine on, both calls are thin
-- wrappers over AudioEngine.play (classes Generic2D and Generic3D, the old rolloff
-- distances mapped onto range and hold), so call sites that were never moved onto the
-- engine still propagate. With it off, the pooled 2D Sounds and the per-call 3D Sound
-- from before the engine are unchanged.

local SoundService = game:GetService("SoundService")

local AudioEngine = require(script.Parent.Parent.audio.AudioEngine)
local MusicController = require(script.Parent.MusicController)

local SfxPlayer = {}

local POOL_SIZE = 10

local pool: { Sound } = {}
local poolIndex = 0
local random = Random.new()

local function ensurePool()
	if #pool > 0 then
		return
	end
	for index = 1, POOL_SIZE do
		local sound = Instance.new("Sound")
		sound.Name = "Sfx" .. index
		sound.SoundGroup = MusicController.getSfxGroup()
		sound.Parent = SoundService
		pool[index] = sound
	end
end

function SfxPlayer.play2D(soundId: number, volume: number, pitchJitter: number?)
	if soundId <= 0 then
		return
	end
	if AudioEngine.enabled() then
		AudioEngine.play({ id = soundId, class = "Generic2D", volume = volume, pitchJitter = pitchJitter or 0 })
		return
	end
	ensurePool()
	poolIndex = (poolIndex % #pool) + 1
	local sound = pool[poolIndex]
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Volume = volume
	local jitter = pitchJitter or 0
	sound.PlaybackSpeed = 1 + random:NextNumber(-jitter, jitter)
	sound.TimePosition = 0
	pcall(function()
		sound:Play()
	end)
end

function SfxPlayer.play3D(parent: BasePart, soundId: number, volume: number, rollOffMin: number, rollOffMax: number, pitchJitter: number?)
	if soundId <= 0 or not parent.Parent then
		return
	end
	if AudioEngine.enabled() then
		AudioEngine.play({
			id = soundId,
			class = "Generic3D",
			follow = parent,
			volume = volume,
			range = rollOffMax,
			hold = rollOffMin,
			pitchJitter = pitchJitter or 0,
		})
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Volume = volume
	local jitter = pitchJitter or 0
	sound.PlaybackSpeed = 1 + random:NextNumber(-jitter, jitter)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = rollOffMin
	sound.RollOffMaxDistance = rollOffMax
	sound.SoundGroup = MusicController.getSfxGroup()
	sound.Parent = parent
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	pcall(function()
		sound:Play()
	end)
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

function SfxPlayer.pick(ids: { number }): number
	if #ids == 0 then
		return 0
	end
	return ids[random:NextInteger(1, #ids)]
end

return SfxPlayer
