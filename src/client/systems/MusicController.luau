--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AudioConfig = require(ReplicatedStorage.Shared.config.AudioConfig)

local MusicController = {}

local PHASE_ATTRIBUTE = "FlowPhase"

local masterGroup: SoundGroup
local musicGroup: SoundGroup
local sfxGroup: SoundGroup
local menuMusic: Sound?
local missionMusic: Sound?
local citySiren: Sound?
local musicVolume = AudioConfig.MENU_MUSIC_VOLUME
local masterVolume = 0.7
local muted = false

local function isPlayableId(id: number): boolean
	return typeof(id) == "number" and id > 0
end

local function applyMasterVolume()
	masterGroup.Volume = if muted then 0 else masterVolume
end

local function createGroups()
	masterGroup = Instance.new("SoundGroup")
	masterGroup.Name = AudioConfig.MASTER_GROUP
	masterGroup.Volume = masterVolume
	masterGroup.Parent = SoundService

	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = AudioConfig.MUSIC_GROUP
	musicGroup.Volume = musicVolume
	musicGroup.Parent = masterGroup

	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = AudioConfig.SFX_GROUP
	sfxGroup.Volume = 1
	sfxGroup.Parent = masterGroup
end

local function createTrack(name: string, assetId: number): Sound?
	if not isPlayableId(assetId) then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. tostring(assetId)
	sound.Looped = true
	sound.Volume = 1
	sound.SoundGroup = musicGroup
	sound.Parent = SoundService
	return sound
end

local function createMenuMusic()
	menuMusic = createTrack("MenuMusic", AudioConfig.MENU_MUSIC_ID)
	local missionId = if isPlayableId(AudioConfig.MISSION_MUSIC_ID) then AudioConfig.MISSION_MUSIC_ID else AudioConfig.MENU_MUSIC_ID
	missionMusic = createTrack("MissionMusic", missionId)
	if missionMusic then
		missionMusic.PlaybackSpeed = if isPlayableId(AudioConfig.MISSION_MUSIC_ID) then 1 else 1.12
	end
end

local function createCitySiren()
	if not isPlayableId(AudioConfig.CITY_SIREN_ID) then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "CitySiren"
	sound.SoundId = "rbxassetid://" .. tostring(AudioConfig.CITY_SIREN_ID)
	sound.Looped = true
	sound.Volume = AudioConfig.SIREN_VOLUME
	sound.SoundGroup = masterGroup
	sound.Parent = SoundService
	citySiren = sound
end

local function playTrack(sound: Sound?)
	if sound and not sound.IsPlaying then
		pcall(function()
			sound:Play()
		end)
	end
end

local function onPhaseChanged()
	local phase = Players.LocalPlayer:GetAttribute(PHASE_ATTRIBUTE)
	local inHub = phase ~= "Mission"

	if inHub then
		if missionMusic and missionMusic.IsPlaying then
			missionMusic:Stop()
		end
		playTrack(menuMusic)
	else
		if menuMusic and menuMusic.IsPlaying then
			menuMusic:Stop()
		end
		playTrack(missionMusic)
	end
	TweenService:Create(musicGroup, TweenInfo.new(AudioConfig.MUSIC_FADE_TIME), { Volume = musicVolume }):Play()

	local siren = citySiren
	if siren then
		if inHub then
			playTrack(siren)
		elseif siren.IsPlaying then
			siren:Stop()
		end
	end
end

function MusicController.getMasterGroup(): SoundGroup?
	return masterGroup
end

function MusicController.getSfxGroup(): SoundGroup?
	return sfxGroup
end

function MusicController.setMasterVolume(value: number)
	masterVolume = math.clamp(value, 0, 1)
	applyMasterVolume()
end

function MusicController.setMusicVolume(value: number)
	musicVolume = math.clamp(value, 0, 1)
	musicGroup.Volume = musicVolume
end

function MusicController.setMuted(value: boolean)
	muted = value
	applyMasterVolume()
end

function MusicController.init()
	createGroups()
	createMenuMusic()
	createCitySiren()
	Players.LocalPlayer:GetAttributeChangedSignal(PHASE_ATTRIBUTE):Connect(onPhaseChanged)
	onPhaseChanged()
end

return MusicController
