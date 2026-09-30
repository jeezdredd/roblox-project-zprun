--!strict

-- World sources: the hangar roomtone bed, fire crackle loops on the diorama's
-- FireAnchor parts, the distant boom every so often, the radio in the hangar cabin.
-- With the spatial audio engine on the fires and the radio are AmbienceSource voices
-- following their parts, the boom is an Explosion (delayed by distance, with
-- reflections off the surroundings) and the roomtone a 2D bed; the legacy Sounds and
-- the global AmbientReverb switch stay for the flag off (AmbientReverb only ever
-- touched Sounds, so it is harmless to the engine's buses either way).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local SfxConfig = require(ReplicatedStorage.Shared.config.SfxConfig)
local AudioEngine = require(script.Parent.Parent.audio.AudioEngine)
local AudioReflections = require(script.Parent.Parent.audio.AudioReflections)
local MusicController = require(script.Parent.MusicController)
local SfxPlayer = require(script.Parent.SfxPlayer)

local WorldSfx = {}

local PHASE_ATTRIBUTE = "FlowPhase"
local BOOM_HOLD = 200
local BOOM_RANGE = 2200
local RADIO_HOLD = 12
local RADIO_RANGE = 90

local random = Random.new()
local roomtone: Sound? = nil
local roomtoneHandle: AudioEngine.Handle? = nil
local roomtoneVolume = 0
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
	if AudioEngine.enabled() then
		AudioEngine.play({
			id = SfxConfig.FIRE_CRACKLE_ID,
			class = "AmbienceSource",
			follow = anchor,
			volume = SfxConfig.FIRE_CRACKLE_VOLUME,
			pitch = random:NextNumber(0.92, 1.08),
			loop = true,
			range = SfxConfig.FIRE_ROLLOFF_MAX,
			hold = SfxConfig.FIRE_ROLLOFF_MIN,
		})
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

local function playBoom(host: BasePart)
	if AudioEngine.enabled() then
		AudioEngine.play({
			id = SfxConfig.DISTANT_BOOM_ID,
			class = "Explosion",
			position = host.Position,
			volume = SfxConfig.DISTANT_BOOM_VOLUME,
			pitchJitter = 0.15,
			range = BOOM_RANGE,
			hold = BOOM_HOLD,
		})
		AudioReflections.fire(host.Position, SfxConfig.DISTANT_BOOM_ID, "sfx", SfxConfig.DISTANT_BOOM_VOLUME, 1, AudioEngine.reflectionRays())
		return
	end
	SfxPlayer.play3D(host, SfxConfig.DISTANT_BOOM_ID, SfxConfig.DISTANT_BOOM_VOLUME, BOOM_HOLD, BOOM_RANGE, 0.15)
end

local function playRadio(host: BasePart)
	local id = SfxPlayer.pick(SfxConfig.RADIO_IDS)
	if AudioEngine.enabled() then
		AudioEngine.play({
			id = id,
			class = "AmbienceSource",
			follow = host,
			volume = SfxConfig.RADIO_VOLUME,
			pitchJitter = 0.08,
			range = RADIO_RANGE,
			hold = RADIO_HOLD,
		})
		return
	end
	SfxPlayer.play3D(host, id, SfxConfig.RADIO_VOLUME, RADIO_HOLD, RADIO_RANGE, 0.08)
end

local function step()
	local now = os.clock()

	if roomtone or roomtoneHandle then
		local target = if inHub() then SfxConfig.ROOMTONE_VOLUME else 0
		roomtoneVolume += (target - roomtoneVolume) * 0.05
		if roomtone then
			roomtone.Volume = roomtoneVolume
		end
		local handle = roomtoneHandle
		if handle then
			handle:setVolume(roomtoneVolume)
		end
	end

	if now >= nextBoomAt and #boomHosts > 0 then
		nextBoomAt = now + random:NextNumber(SfxConfig.DISTANT_BOOM_MIN_GAP, SfxConfig.DISTANT_BOOM_MAX_GAP)
		if inHub() or Workspace:GetAttribute("Biome") == "City" then
			playBoom(boomHosts[random:NextInteger(1, #boomHosts)])
		end
	end

	if now >= nextRadioAt and radioHost and inHub() then
		nextRadioAt = now + random:NextNumber(SfxConfig.RADIO_GAP_MIN, SfxConfig.RADIO_GAP_MAX)
		playRadio(radioHost)
	end
end

local function startRoomtone()
	if SfxConfig.ROOMTONE_ID <= 0 then
		return
	end
	if AudioEngine.enabled() then
		roomtoneHandle = AudioEngine.play({ id = SfxConfig.ROOMTONE_ID, class = "AmbienceBed", volume = 0, loop = true })
		return
	end
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

function WorldSfx.init()
	if started then
		return
	end
	started = true

	startRoomtone()

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
