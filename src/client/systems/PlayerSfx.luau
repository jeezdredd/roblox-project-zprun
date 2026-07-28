--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local SfxConfig = require(ReplicatedStorage.Shared.config.SfxConfig)
local ExertionState = require(script.Parent.Parent.controllers.ExertionState)
local InputController = require(script.Parent.Parent.controllers.InputController)
local MusicController = require(script.Parent.MusicController)
local SfxPlayer = require(script.Parent.SfxPlayer)

local PlayerSfx = {}

local heartbeat: Sound? = nil
local wind: Sound? = nil
local equalizer: EqualizerSoundEffect? = nil
local concussionUntil = 0
local lastAxis = 0
local whooshReadyAt = 0
local started = false

local function approach(current: number, target: number, speed: number, deltaTime: number): number
	return current + (target - current) * (1 - math.exp(-speed * deltaTime))
end

local function createLoop(name: string, soundId: number, volume: number): Sound?
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
	local _ = volume
	return sound
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
	SfxPlayer.play2D(
		SfxPlayer.pick(SfxConfig.FOLEY_GEAR_IDS),
		SfxConfig.FOLEY_GEAR_VOLUME,
		SfxConfig.FOLEY_GEAR_PITCH_JITTER
	)
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 5)

	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth - 0.001 then
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
		SfxPlayer.play2D(
			if hard then SfxConfig.LAND_HARD_ID else SfxConfig.LAND_SOFT_ID,
			SfxConfig.LAND_VOLUME,
			0.08
		)
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
	SfxPlayer.play2D(SfxConfig.WHOOSH_ID, SfxConfig.WHOOSH_VOLUME, 0.1)
end

local function step(deltaTime: number)
	local now = os.clock()
	updateWhoosh(now)

	local ratio = healthRatio()
	local lowness = math.clamp((SfxConfig.HEARTBEAT_THRESHOLD - ratio) / SfxConfig.HEARTBEAT_THRESHOLD, 0, 1)
	if heartbeat then
		heartbeat.Volume = approach(heartbeat.Volume, SfxConfig.HEARTBEAT_VOLUME * lowness, 4, deltaTime)
		heartbeat.PlaybackSpeed = SfxConfig.HEARTBEAT_PITCH_MIN
			+ (SfxConfig.HEARTBEAT_PITCH_MAX - SfxConfig.HEARTBEAT_PITCH_MIN) * lowness
	end

	if wind then
		local speed = ExertionState.getSpeed()
		local alpha = math.clamp(
			(speed - SfxConfig.WIND_SPEED_MIN) / (SfxConfig.WIND_SPEED_MAX - SfxConfig.WIND_SPEED_MIN),
			0,
			1
		)
		wind.Volume = approach(wind.Volume, SfxConfig.WIND_VOLUME_MAX * alpha, 3, deltaTime)
	end

	if equalizer then
		local active = now < concussionUntil
		equalizer.HighGain = approach(equalizer.HighGain, if active then SfxConfig.CONCUSSION_HIGH_GAIN else 0, 6, deltaTime)
		equalizer.MidGain = approach(equalizer.MidGain, if active then -6 else 0, 6, deltaTime)
	end
end

function PlayerSfx.init()
	if started then
		return
	end
	started = true
	ExertionState.init()

	heartbeat = createLoop("Heartbeat", SfxConfig.HEARTBEAT_ID, SfxConfig.HEARTBEAT_VOLUME)
	wind = createLoop("WindInEars", SfxConfig.WIND_ID, SfxConfig.WIND_VOLUME_MAX)

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

	ExertionState.onStep(onFootstep)

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end

	RunService.Heartbeat:Connect(step)
end

return PlayerSfx
