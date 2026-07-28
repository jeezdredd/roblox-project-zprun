--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.config.AudioConfig)
local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local MusicController = require(script.Parent.MusicController)

local CityAmbience = {}

type Patrol = {
	part: BasePart,
	sound: Sound,
	radius: number,
	speed: number,
	phase: number,
	centerZ: number,
	nextToggle: number,
	playing: boolean,
}

local PHASE_ATTRIBUTE = "FlowPhase"

local random = Random.new()
local patrols: { Patrol } = {}
local staticSounds: { Sound } = {}
local active = false
local elapsed = 0

local function isPlayableId(id: number): boolean
	return id > 0
end

local function configureSound(sound: Sound, soundId: number, volume: number, pitch: number)
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Looped = true
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = AudioConfig.AMBIENCE_ROLLOFF_MIN
	sound.RollOffMaxDistance = AudioConfig.AMBIENCE_ROLLOFF_MAX
	sound.SoundGroup = MusicController.getSfxGroup()
end

local function createPatrol(index: number, soundId: number, volume: number): Patrol?
	if not isPlayableId(soundId) then
		return nil
	end

	local part = Instance.new("Part")
	part.Name = "SirenPatrol" .. index
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.Name = "Siren"
	configureSound(sound, soundId, volume, random:NextNumber(0.94, 1.06))
	sound.Parent = part

	return {
		part = part,
		sound = sound,
		radius = random:NextNumber(AudioConfig.SIREN_PATROL_RADIUS_MIN, AudioConfig.SIREN_PATROL_RADIUS_MAX),
		speed = random:NextNumber(AudioConfig.SIREN_PATROL_SPEED_MIN, AudioConfig.SIREN_PATROL_SPEED_MAX)
			* (if index % 2 == 0 then -1 else 1),
		phase = random:NextNumber(0, math.pi * 2),
		centerZ = HangarConfig.HUB_CENTER.Z
			+ random:NextNumber(AudioConfig.SIREN_PATROL_CENTER_FAR, AudioConfig.SIREN_PATROL_CENTER_NEAR),
		nextToggle = if index == 1 then random:NextNumber(1, 5) else random:NextNumber(4, AudioConfig.SIREN_GAP_MAX),
		playing = false,
	}
end

local function stopAll()
	for _, patrol in patrols do
		if patrol.sound.IsPlaying then
			patrol.sound:Stop()
		end
		patrol.playing = false
	end
	for _, sound in staticSounds do
		if sound.IsPlaying then
			sound:Stop()
		end
	end
end

local function step(deltaTime: number)
	if not active then
		return
	end
	elapsed += deltaTime

	for _, patrol in patrols do
		local angle = patrol.phase + elapsed * patrol.speed
		patrol.part.Position = Vector3.new(
			HangarConfig.HUB_CENTER.X + math.cos(angle) * patrol.radius,
			8,
			patrol.centerZ + math.sin(angle) * patrol.radius * 0.6
		)

		if elapsed >= patrol.nextToggle then
			if patrol.playing then
				patrol.sound:Stop()
				patrol.playing = false
				patrol.nextToggle = elapsed + random:NextNumber(AudioConfig.SIREN_GAP_MIN, AudioConfig.SIREN_GAP_MAX)
			else
				patrol.sound.PlaybackSpeed = random:NextNumber(0.92, 1.08)
				pcall(function()
					patrol.sound:Play()
				end)
				patrol.playing = true
				patrol.nextToggle = elapsed + random:NextNumber(AudioConfig.SIREN_BURST_MIN, AudioConfig.SIREN_BURST_MAX)
			end
		end
	end
end

local function onPhaseChanged()
	local inHub = Players.LocalPlayer:GetAttribute(PHASE_ATTRIBUTE) ~= "Mission"
	active = inHub
	if not inHub then
		stopAll()
		return
	end
	for _, sound in staticSounds do
		if not sound.IsPlaying then
			pcall(function()
				sound:Play()
			end)
		end
	end
end

function CityAmbience.init()
	task.spawn(function()
		local diorama = Workspace:WaitForChild("CityDiorama", 30)
		if not diorama then
			return
		end

		local sirenIds = {
			AudioConfig.POLICE_SIREN_ID,
			AudioConfig.AMBULANCE_SIREN_ID,
		}
		for index = 1, AudioConfig.SIREN_PATROL_COUNT do
			local soundId = sirenIds[((index - 1) % #sirenIds) + 1]
			local patrol = createPatrol(index, soundId, AudioConfig.POLICE_VOLUME)
			if patrol then
				table.insert(patrols, patrol)
			end
		end

		for _, model in diorama:GetChildren() do
			if model:IsA("Model") and model.Name == "PatrolChopper" and model.PrimaryPart then
				local sound = Instance.new("Sound")
				sound.Name = "RotorLoop"
				configureSound(sound, AudioConfig.HELI_LOOP_ID, AudioConfig.HELI_VOLUME, 1)
				sound.RollOffMinDistance = 60
				sound.RollOffMaxDistance = 1100
				sound.Parent = model.PrimaryPart
				table.insert(staticSounds, sound)
			end
		end

		RunService.Heartbeat:Connect(step)
		Players.LocalPlayer:GetAttributeChangedSignal(PHASE_ATTRIBUTE):Connect(onPhaseChanged)
		onPhaseChanged()
	end)
end

return CityAmbience
