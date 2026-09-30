--!strict

-- The burning city outside the hangar: siren patrols orbiting on invisible parts in
-- bursts, and the rotor loop of every patrol chopper. With the spatial audio engine on
-- each one is an AmbienceSource voice following its part (long linear curve, air
-- absorption, occluded by the hangar); with it off the Sounds from before stay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.config.AudioConfig)
local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local AudioEngine = require(script.Parent.Parent.audio.AudioEngine)
local MusicController = require(script.Parent.MusicController)

local CityAmbience = {}

type Patrol = {
	part: BasePart,
	soundId: number,
	volume: number,
	sound: Sound?,
	handle: AudioEngine.Handle?,
	radius: number,
	speed: number,
	phase: number,
	centerZ: number,
	nextToggle: number,
	playing: boolean,
}

type Rotor = {
	part: BasePart,
	sound: Sound?,
	handle: AudioEngine.Handle?,
}

local PHASE_ATTRIBUTE = "FlowPhase"
local ROTOR_HOLD = 60
local ROTOR_RANGE = 1100
local BURST_FADE = 0.4

local random = Random.new()
local patrols: { Patrol } = {}
local rotors: { Rotor } = {}
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

	local sound: Sound? = nil
	if not AudioEngine.enabled() then
		local created = Instance.new("Sound")
		created.Name = "Siren"
		configureSound(created, soundId, volume, random:NextNumber(0.94, 1.06))
		created.Parent = part
		sound = created
	end

	return {
		part = part,
		soundId = soundId,
		volume = volume,
		sound = sound,
		handle = nil,
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

local function startPatrol(patrol: Patrol)
	local pitch = random:NextNumber(0.92, 1.08)
	if AudioEngine.enabled() then
		patrol.handle = AudioEngine.play({
			id = patrol.soundId,
			class = "AmbienceSource",
			follow = patrol.part,
			volume = patrol.volume,
			pitch = pitch,
			loop = true,
			range = AudioConfig.AMBIENCE_ROLLOFF_MAX,
			hold = AudioConfig.AMBIENCE_ROLLOFF_MIN,
			fadeIn = BURST_FADE,
		})
	end
	local sound = patrol.sound
	if sound then
		sound.PlaybackSpeed = pitch
		pcall(function()
			sound:Play()
		end)
	end
	patrol.playing = true
end

local function stopPatrol(patrol: Patrol)
	local handle = patrol.handle
	if handle then
		handle:stop(BURST_FADE)
		patrol.handle = nil
	end
	local sound = patrol.sound
	if sound and sound.IsPlaying then
		sound:Stop()
	end
	patrol.playing = false
end

local function startRotor(rotor: Rotor)
	if AudioEngine.enabled() then
		local handle = rotor.handle
		if handle and handle:isPlaying() then
			return
		end
		rotor.handle = AudioEngine.play({
			id = AudioConfig.HELI_LOOP_ID,
			class = "AmbienceSource",
			follow = rotor.part,
			volume = AudioConfig.HELI_VOLUME,
			loop = true,
			range = ROTOR_RANGE,
			hold = ROTOR_HOLD,
			fadeIn = BURST_FADE,
		})
		return
	end
	local sound = rotor.sound
	if sound and not sound.IsPlaying then
		pcall(function()
			sound:Play()
		end)
	end
end

local function stopRotor(rotor: Rotor)
	local handle = rotor.handle
	if handle then
		handle:stop(BURST_FADE)
		rotor.handle = nil
	end
	local sound = rotor.sound
	if sound and sound.IsPlaying then
		sound:Stop()
	end
end

local function stopAll()
	for _, patrol in patrols do
		stopPatrol(patrol)
	end
	for _, rotor in rotors do
		stopRotor(rotor)
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
				stopPatrol(patrol)
				patrol.nextToggle = elapsed + random:NextNumber(AudioConfig.SIREN_GAP_MIN, AudioConfig.SIREN_GAP_MAX)
			else
				startPatrol(patrol)
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
	for _, rotor in rotors do
		startRotor(rotor)
	end
end

local function createRotor(part: BasePart): Rotor?
	if not isPlayableId(AudioConfig.HELI_LOOP_ID) then
		return nil
	end
	local sound: Sound? = nil
	if not AudioEngine.enabled() then
		local created = Instance.new("Sound")
		created.Name = "RotorLoop"
		configureSound(created, AudioConfig.HELI_LOOP_ID, AudioConfig.HELI_VOLUME, 1)
		created.RollOffMinDistance = ROTOR_HOLD
		created.RollOffMaxDistance = ROTOR_RANGE
		created.Parent = part
		sound = created
	end
	return { part = part, sound = sound, handle = nil }
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
				local rotor = createRotor(model.PrimaryPart)
				if rotor then
					table.insert(rotors, rotor)
				end
			end
		end

		RunService.Heartbeat:Connect(step)
		Players.LocalPlayer:GetAttributeChangedSignal(PHASE_ATTRIBUTE):Connect(onPhaseChanged)
		onPhaseChanged()
	end)
end

return CityAmbience
