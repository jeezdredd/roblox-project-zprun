--!strict

-- Music, the hub siren bed and the volume controls. Owns the legacy SoundGroup tree,
-- which WeaponSfx and the legacy paths still play through, and mirrors every volume,
-- mute and duck change onto the spatial audio engine's buses so the two mixes move
-- together. With the engine on, the tracks themselves are 2D voices on the music bus
-- (cross-faded by the engine's fades) and the siren is an ambience bed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AudioConfig = require(ReplicatedStorage.Shared.config.AudioConfig)
local AudioBus = require(script.Parent.Parent.audio.AudioBus)
local AudioEngine = require(script.Parent.Parent.audio.AudioEngine)

local MusicController = {}

local PHASE_ATTRIBUTE = "FlowPhase"

local masterGroup: SoundGroup
local musicGroup: SoundGroup
local sfxGroup: SoundGroup
local menuMusic: Sound?
local missionMusic: Sound?
local citySiren: Sound?
local menuHandle: AudioEngine.Handle? = nil
local missionHandle: AudioEngine.Handle? = nil
local sirenHandle: AudioEngine.Handle? = nil
local musicVolume = AudioConfig.MENU_MUSIC_VOLUME
local duckScale = 1
local masterVolume = 0.7
local muted = false

local function isPlayableId(id: number): boolean
	return typeof(id) == "number" and id > 0
end

local function applyMasterVolume()
	masterGroup.Volume = if muted then 0 else masterVolume
	if AudioBus.isBuilt() then
		AudioBus.setMasterVolume(masterVolume)
		AudioBus.setMuted(muted)
	end
end

local function applyMusicVolume()
	musicGroup.Volume = musicVolume * duckScale
	if AudioBus.isBuilt() then
		AudioBus.setMusicVolume(musicVolume)
		AudioBus.setDuck(1 - duckScale)
	end
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

local function missionTrackId(): (number, number)
	if isPlayableId(AudioConfig.MISSION_MUSIC_ID) then
		return AudioConfig.MISSION_MUSIC_ID, 1
	end
	-- the menu track stands in, a little faster
	return AudioConfig.MENU_MUSIC_ID, 1.12
end

local function createMenuMusic()
	if AudioEngine.enabled() then
		return
	end
	menuMusic = createTrack("MenuMusic", AudioConfig.MENU_MUSIC_ID)
	local missionId, missionPitch = missionTrackId()
	missionMusic = createTrack("MissionMusic", missionId)
	if missionMusic then
		missionMusic.PlaybackSpeed = missionPitch
	end
end

local function createCitySiren()
	if AudioEngine.enabled() or not isPlayableId(AudioConfig.CITY_SIREN_ID) then
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

local function startEngineTrack(handle: AudioEngine.Handle?, id: number, pitch: number): AudioEngine.Handle?
	if handle and handle:isPlaying() then
		return handle
	end
	if not isPlayableId(id) then
		return nil
	end
	return AudioEngine.play({
		id = id,
		class = "Music",
		volume = 1,
		pitch = pitch,
		loop = true,
		fadeIn = AudioConfig.MUSIC_FADE_TIME,
	})
end

local function stopEngineTrack(handle: AudioEngine.Handle?)
	if handle then
		handle:stop(AudioConfig.MUSIC_FADE_TIME)
	end
end

local function onPhaseChangedEngine(inHub: boolean)
	if inHub then
		stopEngineTrack(missionHandle)
		missionHandle = nil
		menuHandle = startEngineTrack(menuHandle, AudioConfig.MENU_MUSIC_ID, 1)
		if not sirenHandle or not sirenHandle:isPlaying() then
			sirenHandle = AudioEngine.play({
				id = AudioConfig.CITY_SIREN_ID,
				class = "AmbienceBed",
				volume = AudioConfig.SIREN_VOLUME,
				loop = true,
				fadeIn = AudioConfig.MUSIC_FADE_TIME,
			})
		end
	else
		stopEngineTrack(menuHandle)
		menuHandle = nil
		local missionId, missionPitch = missionTrackId()
		missionHandle = startEngineTrack(missionHandle, missionId, missionPitch)
		stopEngineTrack(sirenHandle)
		sirenHandle = nil
	end
end

local function onPhaseChanged()
	local phase = Players.LocalPlayer:GetAttribute(PHASE_ATTRIBUTE)
	local inHub = phase ~= "Mission"

	if AudioEngine.enabled() then
		onPhaseChangedEngine(inHub)
		return
	end

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
	applyMusicVolume()
end

function MusicController.setDuck(reduction: number)
	duckScale = math.clamp(1 - reduction, 0.1, 1)
	applyMusicVolume()
end

function MusicController.setMuted(value: boolean)
	muted = value
	applyMasterVolume()
end

function MusicController.init()
	createGroups()
	createMenuMusic()
	createCitySiren()
	applyMasterVolume()
	applyMusicVolume()
	Players.LocalPlayer:GetAttributeChangedSignal(PHASE_ATTRIBUTE):Connect(onPhaseChanged)
	onPhaseChanged()
end

return MusicController
