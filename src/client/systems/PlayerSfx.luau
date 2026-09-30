--!strict

-- The player's own body: heartbeat and wind loops driven by health and speed, gear
-- rattle on every step, landings, the cloth whoosh on a hard lateral flip, and the
-- concussion filter after damage. Everything here sits on the listener, so with the
-- spatial audio engine on it plays as 2D PlayerFoley voices on the sfx bus and the
-- concussion drives the sfx bus equaliser; with it off the Sounds and the
-- EqualizerSoundEffect from before stay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local SfxConfig = require(ReplicatedStorage.Shared.config.SfxConfig)
local ExertionState = require(script.Parent.Parent.controllers.ExertionState)
local InputController = require(script.Parent.Parent.controllers.InputController)
local AudioBus = require(script.Parent.Parent.audio.AudioBus)
local AudioEngine = require(script.Parent.Parent.audio.AudioEngine)
local MusicController = require(script.Parent.MusicController)
local SfxPlayer = require(script.Parent.SfxPlayer)

local PlayerSfx = {}

local heartbeat: Sound? = nil
local wind: Sound? = nil
local heartbeatHandle: AudioEngine.Handle? = nil
local windHandle: AudioEngine.Handle? = nil
local heartbeatVolume = 0
local windVolume = 0
local equalizer: EqualizerSoundEffect? = nil
local concussionHigh = 0
local concussionMid = 0
local concussionUntil = 0
local lastAxis = 0
local whooshReadyAt = 0
local started = false

local function approach(current: number, target: number, speed: number, deltaTime: number): number
	return current + (target - current) * (1 - math.exp(-speed * deltaTime))
end

local function createLoop(name: string, soundId: number): Sound?
	if soundId <= 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = MusicController.getSfxGroup()
	sound.Parent = SoundService
	pcall(function()
		sound:Play()
	end)
	return sound
end

local function createEngineLoop(soundId: number): AudioEngine.Handle?
	if soundId <= 0 then
		return nil
	end
	return AudioEngine.play({ id = soundId, class = "PlayerFoley", volume = 0, loop = true })
end

local function playFoley(soundId: number, volume: number, pitchJitter: number)
	if AudioEngine.enabled() then
		AudioEngine.play({ id = soundId, class = "PlayerFoley", volume = volume, pitchJitter = pitchJitter })
		return
	end
	SfxPlayer.play2D(soundId, volume, pitchJitter)
end

local function healthRatio(): number
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.MaxHealth <= 0 then
		return 1
	end
	return math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
end

local function onFootstep()
	playFoley(SfxPlayer.pick(SfxConfig.FOLEY_GEAR_IDS), SfxConfig.FOLEY_GEAR_VOLUME, SfxConfig.FOLEY_GEAR_PITCH_JITTER)
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 5)

	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth - 0.001 and health > 0 then
			concussionUntil = os.clock() + SfxConfig.CONCUSSION_DURATION
		end
		lastHealth = health
	end)

	humanoid.StateChanged:Connect(function(_, newState)
		if newState ~= Enum.HumanoidStateType.Landed then
			return
		end
		local fallSpeed = 0
		if root and root:IsA("BasePart") then
			fallSpeed = math.abs(root.AssemblyLinearVelocity.Y)
		end
		local hard = fallSpeed >= SfxConfig.LAND_HARD_SPEED
		playFoley(if hard then SfxConfig.LAND_HARD_ID else SfxConfig.LAND_SOFT_ID, SfxConfig.LAND_VOLUME, 0.08)
	end)
end

local function updateWhoosh(now: number)
	local axis = InputController.getLateralAxis()
	local flipped = axis ~= 0 and lastAxis ~= 0 and axis ~= lastAxis
	if axis ~= 0 then
		lastAxis = axis
	end
	if not flipped or now < whooshReadyAt then
		return
	end
	if ExertionState.getSpeed() < SfxConfig.WHOOSH_MIN_SPEED then
		return
	end
	whooshReadyAt = now + SfxConfig.WHOOSH_COOLDOWN
	playFoley(SfxConfig.WHOOSH_ID, SfxConfig.WHOOSH_VOLUME, 0.1)
end

local function step(deltaTime: number)
	local now = os.clock()
	updateWhoosh(now)

	local ratio = healthRatio()
	local lowness = math.clamp((SfxConfig.HEARTBEAT_THRESHOLD - ratio) / SfxConfig.HEARTBEAT_THRESHOLD, 0, 1)
	heartbeatVolume = approach(heartbeatVolume, SfxConfig.HEARTBEAT_VOLUME * lowness, 4, deltaTime)
	local heartbeatPitch = SfxConfig.HEARTBEAT_PITCH_MIN + (SfxConfig.HEARTBEAT_PITCH_MAX - SfxConfig.HEARTBEAT_PITCH_MIN) * lowness
	if heartbeat then
		heartbeat.Volume = heartbeatVolume
		heartbeat.PlaybackSpeed = heartbeatPitch
	end
	local heart = heartbeatHandle
	if heart then
		heart:setVolume(heartbeatVolume)
		heart:setPitch(heartbeatPitch)
	end

	local speed = ExertionState.getSpeed()
	local alpha = math.clamp((speed - SfxConfig.WIND_SPEED_MIN) / (SfxConfig.WIND_SPEED_MAX - SfxConfig.WIND_SPEED_MIN), 0, 1)
	windVolume = approach(windVolume, SfxConfig.WIND_VOLUME_MAX * alpha, 3, deltaTime)
	if wind then
		wind.Volume = windVolume
	end
	local gust = windHandle
	if gust then
		gust:setVolume(windVolume)
	end

	local active = now < concussionUntil
	concussionHigh = approach(concussionHigh, if active then SfxConfig.CONCUSSION_HIGH_GAIN else 0, 6, deltaTime)
	concussionMid = approach(concussionMid, if active then -6 else 0, 6, deltaTime)
	if equalizer then
		equalizer.HighGain = concussionHigh
		equalizer.MidGain = concussionMid
	end
	if AudioEngine.enabled() then
		AudioBus.setConcussion(concussionHigh, concussionMid)
	end
end

function PlayerSfx.init()
	if started then
		return
	end
	started = true
	ExertionState.init()

	if AudioEngine.enabled() then
		heartbeatHandle = createEngineLoop(SfxConfig.HEARTBEAT_ID)
		windHandle = createEngineLoop(SfxConfig.WIND_ID)
	else
		heartbeat = createLoop("Heartbeat", SfxConfig.HEARTBEAT_ID)
		wind = createLoop("WindInEars", SfxConfig.WIND_ID)

		local sfxGroup = MusicController.getSfxGroup()
		if sfxGroup then
			local effect = Instance.new("EqualizerSoundEffect")
			effect.Name = "Concussion"
			effect.HighGain = 0
			effect.MidGain = 0
			effect.LowGain = SfxConfig.CONCUSSION_LOW_GAIN
			effect.Parent = sfxGroup
			equalizer = effect
		end
	end

	ExertionState.onStep(onFootstep)

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end

	RunService.Heartbeat:Connect(step)
end

return PlayerSfx
