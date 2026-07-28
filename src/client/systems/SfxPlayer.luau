--!strict

local SoundService = game:GetService("SoundService")

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
