--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.config.AudioConfig)
local MusicController = require(script.Parent.MusicController)

local CityAmbience = {}

local PHASE_ATTRIBUTE = "FlowPhase"

local sounds: { Sound } = {}

local function attachLoop(parent: BasePart, soundId: number, volume: number, playbackSpeed: number): Sound?
	if soundId <= 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Ambience"
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Looped = true
	sound.Volume = volume
	sound.PlaybackSpeed = playbackSpeed
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = AudioConfig.AMBIENCE_ROLLOFF_MIN
	sound.RollOffMaxDistance = AudioConfig.AMBIENCE_ROLLOFF_MAX
	sound.SoundGroup = MusicController.getSfxGroup()
	sound.Parent = parent
	table.insert(sounds, sound)
	return sound
end

local function setPlaying(playing: boolean)
	for _, sound in sounds do
		if playing and not sound.IsPlaying then
			pcall(function()
				sound:Play()
			end)
		elseif not playing and sound.IsPlaying then
			sound:Stop()
		end
	end
end

local function onPhaseChanged()
	setPlaying(Players.LocalPlayer:GetAttribute(PHASE_ATTRIBUTE) ~= "Mission")
end

function CityAmbience.init()
	task.spawn(function()
		local diorama = Workspace:WaitForChild("CityDiorama", 30)
		if not diorama then
			return
		end

		local sirenSpots: { BasePart } = {}
		for _, descendant in diorama:GetDescendants() do
			if descendant:IsA("BasePart") and descendant.Name:match("^CityBlock") then
				table.insert(sirenSpots, descendant)
			end
		end

		if #sirenSpots > 0 then
			attachLoop(sirenSpots[1], AudioConfig.POLICE_SIREN_ID, AudioConfig.POLICE_VOLUME, 1)
		end
		if #sirenSpots > 2 then
			attachLoop(sirenSpots[3], AudioConfig.POLICE_SIREN_ID, AudioConfig.POLICE_VOLUME * 0.8, 0.82)
		end
		if #sirenSpots > 5 then
			attachLoop(sirenSpots[6], AudioConfig.CIVIL_SIREN_ID, AudioConfig.SIREN_VOLUME, 1)
		end

		for _, model in diorama:GetChildren() do
			if model:IsA("Model") and model.Name == "PatrolChopper" and model.PrimaryPart then
				attachLoop(model.PrimaryPart, AudioConfig.HELI_LOOP_ID, AudioConfig.HELI_VOLUME, 1)
			end
		end

		Players.LocalPlayer:GetAttributeChangedSignal(PHASE_ATTRIBUTE):Connect(onPhaseChanged)
		onPhaseChanged()
	end)
end

return CityAmbience
