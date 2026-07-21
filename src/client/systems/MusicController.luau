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
local menuMusic: Sound?
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
end

local function createMenuMusic()
	if not isPlayableId(AudioConfig.MENU_MUSIC_ID) then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "MenuMusic"
	sound.SoundId = "rbxassetid://" .. tostring(AudioConfig.MENU_MUSIC_ID)
	sound.Looped = true
	sound.Volume = 1
	sound.SoundGroup = musicGroup
	sound.Parent = SoundService
	menuMusic = sound
end

local function fadeMusicTo(target: number)
	local sound = menuMusic
	if not sound then
		return
	end
	if target > 0 and not sound.IsPlaying then
		pcall(function()
			sound:Play()
		end)
	end
	TweenService:Create(musicGroup, TweenInfo.new(AudioConfig.MUSIC_FADE_TIME), { Volume = target }):Play()
end

local function onPhaseChanged()
	local phase = Players.LocalPlayer:GetAttribute(PHASE_ATTRIBUTE)
	if phase == "Mission" then
		fadeMusicTo(0)
	else
		fadeMusicTo(musicVolume)
	end
end

function MusicController.setMasterVolume(value: number)
	masterVolume = math.clamp(value, 0, 1)
	applyMasterVolume()
end

function MusicController.setMusicVolume(value: number)
	musicVolume = math.clamp(value, 0, 1)
	local phase = Players.LocalPlayer:GetAttribute(PHASE_ATTRIBUTE)
	if phase ~= "Mission" then
		musicGroup.Volume = musicVolume
	end
end

function MusicController.setMuted(value: boolean)
	muted = value
	applyMasterVolume()
end

function MusicController.init()
	createGroups()
	createMenuMusic()
	Players.LocalPlayer:GetAttributeChangedSignal(PHASE_ATTRIBUTE):Connect(onPhaseChanged)
	onPhaseChanged()
end

return MusicController
