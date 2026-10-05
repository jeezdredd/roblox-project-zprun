--!strict

-- Each map's ambience bed during a run (wiki: Map Segments), crossfaded over a map
-- boundary: inside the transition zone (MapBlend* Workspace attributes from
-- ChunkSpawner) the old map's bed and the new one's play at equal-power gains for this
-- player's place in the zone; elsewhere the map at the lead runner plays alone. A bed
-- whose id is 0 (AssetIds.audio.ambience, still needed) is silence, so this runs before
-- any bed is uploaded. Through the audio engine's AmbienceBed class when it is on, a
-- plain looped Sound in the Sfx group otherwise.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local MapsConfig = require(ReplicatedStorage.Shared.config.MapsConfig)
local MapMath = require(ReplicatedStorage.Shared.world.MapMath)
local AudioEngine = require(script.Parent.Parent.audio.AudioEngine)
local MusicController = require(script.Parent.MusicController)

local MapAmbience = {}

type Bed = {
	handle: AudioEngine.Handle?,
	sound: Sound?,
	gain: number,
}

-- the bed's level at full gain, and how fast a gain follows its target (per second)
local VOLUME = 0.45
local FOLLOW = 2.5
local FADE_OUT = 1.5

local beds: { [string]: Bed } = {}
local started = false

local function ambienceId(mapId: string): number
	local map = MapsConfig.get(mapId)
	local table_ = (AssetIds :: any).audio and (AssetIds :: any).audio.ambience
	local id = if map and table_ then table_[map.ambience] else nil
	return if typeof(id) == "number" then id else 0
end

local function startBed(mapId: string): Bed?
	local id = ambienceId(mapId)
	if id <= 0 then
		return nil
	end
	local bed: Bed = { gain = 0 }
	if AudioEngine.enabled() then
		bed.handle = AudioEngine.play({ id = id, class = "AmbienceBed", volume = 0, loop = true })
	else
		local sound = Instance.new("Sound")
		sound.Name = "MapAmbience_" .. mapId
		sound.SoundId = "rbxassetid://" .. tostring(id)
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = MusicController.getSfxGroup()
		sound.Parent = SoundService
		pcall(function()
			sound:Play()
		end)
		bed.sound = sound
	end
	return bed
end

local function stopBed(mapId: string)
	local bed = beds[mapId]
	if not bed then
		return
	end
	local handle = bed.handle
	if handle then
		handle:stop(FADE_OUT)
	end
	local sound = bed.sound
	if sound then
		sound:Destroy()
	end
	beds[mapId] = nil
end

local function setGain(bed: Bed, gain: number)
	bed.gain = gain
	local handle = bed.handle
	if handle then
		handle:setVolume(VOLUME * gain)
	end
	local sound = bed.sound
	if sound then
		sound.Volume = VOLUME * gain
	end
end

-- The wanted gain per map for this frame.
local function targets(): { [string]: number }
	local out: { [string]: number } = {}
	if Players.LocalPlayer:GetAttribute("FlowPhase") ~= "Mission" then
		return out
	end
	local fromId = Workspace:GetAttribute("MapBlendFrom")
	local toId = Workspace:GetAttribute("MapBlendTo")
	local start = Workspace:GetAttribute("MapBlendStart")
	local finish = Workspace:GetAttribute("MapBlendEnd")
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if typeof(fromId) == "string" and typeof(toId) == "string" and typeof(start) == "number" and typeof(finish) == "number" and root and root:IsA("BasePart") then
		local distance = (root.Position - GameConstants.RUN_ORIGIN):Dot(GameConstants.RUN_DIRECTION)
		local old, new = MapMath.crossfade(MapMath.zoneAlpha(distance, start, finish))
		out[fromId] = old
		out[toId] = (out[toId] or 0) + new
		return out
	end
	local map = Workspace:GetAttribute("Map")
	if typeof(map) == "string" then
		out[map] = 1
	end
	return out
end

local function step(deltaTime: number)
	local wanted = targets()
	for mapId, gain in wanted do
		if gain > 0.001 and not beds[mapId] then
			local bed = startBed(mapId)
			if bed then
				beds[mapId] = bed
			end
		end
	end
	local follow = 1 - math.exp(-FOLLOW * deltaTime)
	for mapId, bed in beds do
		local goal = wanted[mapId] or 0
		local gain = bed.gain + (goal - bed.gain) * follow
		if goal == 0 and gain < 0.01 then
			stopBed(mapId)
		else
			setGain(bed, gain)
		end
	end
end

function MapAmbience.init()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(step)
end

return MapAmbience
