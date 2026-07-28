--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local SfxConfig = require(ReplicatedStorage.Shared.config.SfxConfig)
local MusicController = require(script.Parent.MusicController)
local SfxPlayer = require(script.Parent.SfxPlayer)

local WorldSfx = {}

local PHASE_ATTRIBUTE = "FlowPhase"

local random = Random.new()
local roomtone: Sound? = nil
local boomHosts: { BasePart } = {}
local nextBoomAt = 0
local nextRadioAt = 0
local radioHost: BasePart? = nil
local started = false

local function inHub(): boolean
	return Players.LocalPlayer:GetAttribute(PHASE_ATTRIBUTE) ~= "Mission"
end

local function attachFireLoop(anchor: BasePart)
	if SfxConfig.FIRE_CRACKLE_ID <= 0 then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "FireCrackle"
	sound.SoundId = "rbxassetid://" .. tostring(SfxConfig.FIRE_CRACKLE_ID)
	sound.Looped = true
	sound.Volume = SfxConfig.FIRE_CRACKLE_VOLUME
	sound.PlaybackSpeed = random:NextNumber(0.92, 1.08)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = SfxConfig.FIRE_ROLLOFF_MIN
	sound.RollOffMaxDistance = SfxConfig.FIRE_ROLLOFF_MAX
	sound.SoundGroup = MusicController.getSfxGroup()
	sound.Parent = anchor
	pcall(function()
		sound:Play()
	end)
end

local function updateReverb()
	SoundService.AmbientReverb = if inHub() then SfxConfig.REVERB_HUB else SfxConfig.REVERB_MISSION
end

local function step()
	local now = os.clock()

	if roomtone then
		local target = if inHub() then SfxConfig.ROOMTONE_VOLUME else 0
		roomtone.Volume += (target - roomtone.Volume) * 0.05
	end

	if now >= nextBoomAt and #boomHosts > 0 then
		nextBoomAt = now + random:NextNumber(SfxConfig.DISTANT_BOOM_MIN_GAP, SfxConfig.DISTANT_BOOM_MAX_GAP)
		if inHub() or Workspace:GetAttribute("Biome") == "City" then
			local host = boomHosts[random:NextInteger(1, #boomHosts)]
			SfxPlayer.play3D(host, SfxConfig.DISTANT_BOOM_ID, SfxConfig.DISTANT_BOOM_VOLUME, 200, 2200, 0.15)
		end
	end

	if now >= nextRadioAt and radioHost and inHub() then
		nextRadioAt = now + random:NextNumber(SfxConfig.RADIO_GAP_MIN, SfxConfig.RADIO_GAP_MAX)
		SfxPlayer.play3D(radioHost, SfxPlayer.pick(SfxConfig.RADIO_IDS), SfxConfig.RADIO_VOLUME, 12, 90, 0.08)
	end
end

function WorldSfx.init()
	if started then
		return
	end
	started = true

	if SfxConfig.ROOMTONE_ID > 0 then
		local sound = Instance.new("Sound")
		sound.Name = "HangarRoomtone"
		sound.SoundId = "rbxassetid://" .. tostring(SfxConfig.ROOMTONE_ID)
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = MusicController.getSfxGroup()
		sound.Parent = SoundService
		pcall(function()
			sound:Play()
		end)
		roomtone = sound
	end

	task.spawn(function()
		local diorama = Workspace:WaitForChild("CityDiorama", 30)
		if diorama then
			local fireCount = 0
			for _, descendant in diorama:GetDescendants() do
				if descendant:IsA("BasePart") and descendant.Name == "FireAnchor" then
					if fireCount < SfxConfig.FIRE_MAX_SOURCES then
						attachFireLoop(descendant)
						fireCount += 1
					end
					table.insert(boomHosts, descendant)
				end
			end
		end

		local hangar = Workspace:WaitForChild("Hangar", 30)
		if hangar then
			for _, descendant in hangar:GetDescendants() do
				if descendant:IsA("BasePart") and descendant.Name == "Cabin" then
					radioHost = descendant
					break
				end
			end
		end
	end)

	Players.LocalPlayer:GetAttributeChangedSignal(PHASE_ATTRIBUTE):Connect(updateReverb)
	updateReverb()

	RunService.Heartbeat:Connect(step)
end

return WorldSfx
