--!strict

-- The spatial audio engine: a fixed pool of voices (AudioPlayer -> AudioFilter ->
-- AudioEmitter or bus fader), one play API for every consumer, and the per-frame
-- propagation update that gives each voice its distance curve, air absorption,
-- occlusion, doorway loss, speed-of-sound delay and distance layers. Nothing is
-- allocated per frame; a play picks a free voice or steals the least valuable one.
-- Design and numbers: docs/audio/spatial-audio.md.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local SfxConfig = require(ReplicatedStorage.Shared.config.SfxConfig)
local SpatialAudioConfig = require(ReplicatedStorage.Shared.config.SpatialAudioConfig)
local AudioBus = require(script.Parent.AudioBus)
local AudioEnvironment = require(script.Parent.AudioEnvironment)
local AudioMath = require(script.Parent.AudioMath)

local AudioEngine = {}

export type PlaySpec = {
	-- an AssetIds.audio path ("zombie.idle_01") or a raw asset id; layers instead for
	-- close / mid / far perspectives (keys or ids per layer name)
	key: string?,
	id: number?,
	layers: { [string]: string }?,
	layerIds: { [string]: number }?,
	class: string,
	-- a fixed point, or an instance with a position to follow (BasePart, Attachment)
	position: Vector3?,
	follow: Instance?,
	volume: number?,
	pitch: number?,
	-- seconds on top of the distance delay
	delay: number?,
	loop: boolean?,
	fadeIn: number?,
	-- per-call overrides of the class
	range: number?,
	hold: number?,
	bus: string?,
	pitchJitter: number?,
	-- an extra low-pass cap, for reflections coloured by their surface
	cutoff: number?,
}

type Voice = {
	index: number,
	player: AudioPlayer,
	filter: AudioFilter,
	emitter: AudioEmitter,
	attachment: Attachment,
	wireOut: Wire,
	wireSend: Wire,
	generation: number,
	active: boolean,
	className: string,
	class: SpatialAudioConfig.ClassSpec,
	is3D: boolean,
	loop: boolean,
	follow: Instance?,
	position: Vector3,
	range: number,
	distance: number,
	baseVolume: number,
	userVolume: number,
	layerWeight: number,
	layerBand: SpatialAudioConfig.LayerBand?,
	-- occlusion and doorway attenuation from the last propagation
	gain: number,
	fade: number,
	fadeTarget: number,
	fadeRate: number,
	stopOnFade: boolean,
	occlusion: number,
	occlusionLoss: number,
	occlusionCutoff: number,
	doorway: number,
	cutoffCap: number,
	startedAt: number,
	delay: number,
	actionId: number?,
	dormant: boolean,
	lastCutoff: number,
	lastVolume: number,
}

type VoiceRef = { voice: Voice, generation: number }

local Handle = {}
Handle.__index = Handle

type HandleFields = { refs: { VoiceRef } }

export type Handle = typeof(setmetatable({} :: HandleFields, Handle))

local ASSET_PREFIX = "rbxassetid://"
local LAYER_ORDER = SpatialAudioConfig.LAYER_ORDER
local NEAR = SpatialAudioConfig.NEAR_DISTANCE
local ABSORPTION = SpatialAudioConfig.ABSORPTION
local OCCLUSION = SpatialAudioConfig.OCCLUSION
local ENVIRONMENT = SpatialAudioConfig.ENVIRONMENT
-- one-shots that stopped playing are checked for release this often
local FINISH_CHECK_FRAMES = 8
-- layer weights below this are not worth a voice
local LAYER_MIN_WEIGHT = 0.02
-- a voice culled for range is stopped past this share of its range
local CULL_MARGIN = 1.1

local random = Random.new()
local pool: { Voice } = {}
local curves: { [string]: { [number]: number } } = {}
local profile: SpatialAudioConfig.Profile = SpatialAudioConfig.profiles.desktop
local profileName = "desktop"
local frame = 0
local listenerPosition = Vector3.zero
local listenerZone: BasePart? = nil
local started = false
local warnedClasses: { [string]: boolean } = {}
local simulation = false

local function isEnabled(): boolean
	return SfxConfig.SPATIAL_AUDIO == true
end

local function now(): number
	return os.clock()
end

local function mixerTime(): number
	return SoundService:GetMixerTime()
end

local function resolveId(key: string): number
	local category, name = string.match(key, "^(%w+)%.(%w+)$")
	if not category or not name then
		return 0
	end
	local group = (AssetIds.audio :: { [string]: { [string]: number } })[category]
	local id = group and group[name]
	return if typeof(id) == "number" then id else 0
end

local function classFor(name: string, is3D: boolean): SpatialAudioConfig.ClassSpec
	local spec = SpatialAudioConfig.classes[name]
	if spec then
		return spec
	end
	if not warnedClasses[name] then
		warnedClasses[name] = true
		warn(string.format("[AudioEngine] unknown sound class %q", name))
	end
	return if is3D then SpatialAudioConfig.classes.Generic3D else SpatialAudioConfig.classes.Generic2D
end

local function curveFor(shape: SpatialAudioConfig.CurveShape, range: number, hold: number): { [number]: number }
	local key = string.format("%s:%d:%d", shape, range, hold)
	local curve = curves[key]
	if not curve then
		curve = AudioMath.attenuationCurve(shape, range, hold)
		curves[key] = curve
	end
	return curve
end

local function instancePosition(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Attachment") then
		return instance.WorldPosition
	elseif instance:IsA("Model") then
		local pivot = instance:GetPivot()
		return pivot.Position
	end
	return nil
end

local function release(voice: Voice)
	if not voice.active then
		return
	end
	voice.active = false
	voice.generation += 1
	local actionId = voice.actionId
	if actionId then
		voice.player:Cancel(actionId)
		voice.actionId = nil
	end
	voice.player:Stop()
	voice.follow = nil
	voice.emitter.PositionInstance = nil
	voice.wireSend.TargetInstance = nil
end

local function createVoice(index: number, folder: Instance): Voice
	local player = Instance.new("AudioPlayer")
	player.Name = "Voice" .. index
	player.AutoLoad = true
	player.Parent = folder

	local filter = Instance.new("AudioFilter")
	filter.Name = "Absorption"
	filter.FilterType = Enum.AudioFilterType.Lowpass12dB
	filter.Frequency = ABSORPTION.ceilingHz
	filter.Q = 0.707
	filter.Parent = player

	local attachment = Instance.new("Attachment")
	attachment.Name = "AudioVoice" .. index
	attachment.Parent = Workspace.Terrain

	local emitter = Instance.new("AudioEmitter")
	emitter.Name = "Emitter"
	emitter.PositionType = Enum.EmitterPositionType.Instance
	emitter.DistanceAttenuationMode = Enum.DistanceAttenuationMode.Custom
	emitter.AcousticSimulationEnabled = simulation
	emitter.OcclusionEnabled = if simulation then Enum.SimulationMode.Enabled else Enum.SimulationMode.Disabled
	emitter.ReverbEnabled = if simulation then Enum.SimulationMode.Enabled else Enum.SimulationMode.Disabled
	emitter.DiffractionEnabled = if simulation then Enum.SimulationMode.Enabled else Enum.SimulationMode.Disabled
	emitter.Parent = player

	local wireIn = Instance.new("Wire")
	wireIn.Name = "ToFilter"
	wireIn.SourceInstance = player
	wireIn.SourceName = "Output"
	wireIn.TargetInstance = filter
	wireIn.TargetName = "Input"
	wireIn.Parent = player

	local wireOut = Instance.new("Wire")
	wireOut.Name = "Out"
	wireOut.SourceInstance = filter
	wireOut.SourceName = "Output"
	wireOut.TargetName = "Input"
	wireOut.Parent = player

	local wireSend = Instance.new("Wire")
	wireSend.Name = "DuckSend"
	wireSend.SourceInstance = filter
	wireSend.SourceName = "Output"
	wireSend.TargetName = "Input"
	wireSend.Parent = player

	local voice: Voice = {
		index = index,
		player = player,
		filter = filter,
		emitter = emitter,
		attachment = attachment,
		wireOut = wireOut,
		wireSend = wireSend,
		generation = 0,
		active = false,
		className = "",
		class = SpatialAudioConfig.classes.Generic2D,
		is3D = false,
		loop = false,
		follow = nil,
		position = Vector3.zero,
		range = 0,
		distance = 0,
		baseVolume = 0,
		userVolume = 1,
		layerWeight = 1,
		layerBand = nil,
		gain = 1,
		fade = 1,
		fadeTarget = 1,
		fadeRate = 0,
		stopOnFade = false,
		occlusion = 0,
		occlusionLoss = 0,
		occlusionCutoff = ABSORPTION.ceilingHz,
		doorway = 0,
		cutoffCap = ABSORPTION.ceilingHz,
		startedAt = 0,
		delay = 0,
		actionId = nil,
		dormant = false,
		lastCutoff = -1,
		lastVolume = -1,
	}
	player.Ended:Connect(function()
		if voice.active and not voice.loop then
			release(voice)
		end
	end)
	return voice
end

local function classLimit(spec: SpatialAudioConfig.ClassSpec): number
	return math.max(2, math.floor(spec.maxVoices * profile.voiceLimitScale + 0.5))
end

local function stealScore(voice: Voice): number
	return AudioMath.stealScore(voice.class.priority, voice.distance, voice.range, now() - voice.startedAt)
end

-- A free voice, or the least valuable active one when the new sound outranks it, or
-- nil when the new sound is the one to drop. Class limits are enforced first, so a
-- horde of moans steals from itself before it steals a footstep.
local function acquire(className: string, spec: SpatialAudioConfig.ClassSpec, distance: number, range: number): Voice?
	local newScore = AudioMath.stealScore(spec.priority, distance, range, 0)
	local classCount = 0
	local classWorst: Voice? = nil
	local classWorstScore = math.huge
	local free: Voice? = nil
	local worst: Voice? = nil
	local worstScore = math.huge
	for _, voice in pool do
		if not voice.active then
			free = free or voice
			continue
		end
		local score = stealScore(voice)
		if voice.className == className then
			classCount += 1
			if score < classWorstScore then
				classWorstScore = score
				classWorst = voice
			end
		end
		if score < worstScore then
			worstScore = score
			worst = voice
		end
	end
	if classCount >= classLimit(spec) then
		if classWorst and classWorstScore < newScore then
			release(classWorst)
			return classWorst
		end
		return nil
	end
	if free then
		return free
	end
	if worst and worstScore < newScore then
		release(worst)
		return worst
	end
	return nil
end

local function sourcePosition(voice: Voice): Vector3?
	local follow = voice.follow
	if follow then
		if not follow.Parent then
			return nil
		end
		local position = instancePosition(follow)
		if position then
			voice.position = position
		end
		return position
	end
	return voice.position
end

local function applyVolume(voice: Voice)
	local volume = voice.baseVolume * voice.userVolume * voice.fade * voice.layerWeight * voice.gain
	if math.abs(volume - voice.lastVolume) > 1e-4 then
		voice.lastVolume = volume
		voice.player.Volume = volume
	end
end

local function applyCutoff(voice: Voice, cutoff: number)
	if math.abs(cutoff - voice.lastCutoff) > 1 then
		voice.lastCutoff = cutoff
		voice.filter.Frequency = cutoff
	end
end

-- The propagation update of one 3D voice: distance, culling, absorption, occlusion,
-- doorway loss, distance layers, then the filter and the volume.
local function propagate(voice: Voice, deltaTime: number, rays: number, forceRays: boolean)
	local position = sourcePosition(voice)
	if not position then
		release(voice)
		return
	end
	local distance = (position - listenerPosition).Magnitude
	voice.distance = distance

	if distance > voice.range * CULL_MARGIN then
		if not voice.loop then
			release(voice)
			return
		end
		if not voice.dormant then
			voice.dormant = true
			voice.gain = 0
			applyVolume(voice)
		end
		return
	end
	voice.dormant = false

	local spec = voice.class
	local cutoff = math.min(voice.cutoffCap, AudioMath.absorptionCutoff(distance, spec.air, ABSORPTION))
	local gain = 1

	if not simulation then
		if spec.occlusion > 0 and (forceRays or AudioEnvironment.raysLeft() >= rays) then
			local blocked, material = AudioEnvironment.occlusion(listenerPosition, position, rays)
			if blocked then
				if material then
					voice.occlusionLoss = material.loss
					voice.occlusionCutoff = material.cutoff
				end
				voice.occlusion = AudioMath.smoothOcclusion(voice.occlusion, blocked, deltaTime, OCCLUSION.attack, OCCLUSION.release)
			end
		end
		if voice.occlusion > 1e-3 then
			gain *= AudioMath.occlusionGain(voice.occlusionLoss, spec.occlusion, voice.occlusion)
			cutoff = math.min(cutoff, AudioMath.occlusionCutoff(voice.occlusionCutoff, spec.occlusion, voice.occlusion, ABSORPTION.ceilingHz))
		end

		local sourceZone = AudioEnvironment.zoneAt(position)
		local separated = if sourceZone ~= listenerZone then 1 else 0
		voice.doorway = AudioMath.approach(voice.doorway, separated, deltaTime, ENVIRONMENT.doorwayGlide)
		if voice.doorway > 1e-3 then
			gain *= AudioMath.dbToGain(ENVIRONMENT.doorwayLossDb * voice.doorway)
			cutoff = math.min(cutoff, AudioMath.occlusionCutoff(ENVIRONMENT.doorwayCutoff, 1, voice.doorway, ABSORPTION.ceilingHz))
		end
	end

	local band = voice.layerBand
	if band then
		local bands = spec.layerBands
		if bands then
			-- weight of this voice's band among the class bands, in layer order
			local ordered: { SpatialAudioConfig.LayerBand } = {}
			local mine = 0
			for _, name in LAYER_ORDER do
				local candidate = bands[name]
				if candidate then
					table.insert(ordered, candidate)
					if candidate == band then
						mine = #ordered
					end
				end
			end
			if mine > 0 then
				voice.layerWeight = AudioMath.layerWeights(distance, ordered)[mine]
			end
		end
	end

	voice.gain = gain
	applyCutoff(voice, cutoff)
	applyVolume(voice)
end

local function stepFade(voice: Voice, deltaTime: number): boolean
	if voice.fade == voice.fadeTarget then
		return false
	end
	if voice.fadeRate <= 0 then
		voice.fade = voice.fadeTarget
	elseif voice.fadeTarget > voice.fade then
		voice.fade = math.min(voice.fadeTarget, voice.fade + voice.fadeRate * deltaTime)
	else
		voice.fade = math.max(voice.fadeTarget, voice.fade - voice.fadeRate * deltaTime)
	end
	if voice.fade <= 0 and voice.stopOnFade then
		release(voice)
		return false
	end
	return true
end

local function step(deltaTime: number)
	frame += 1
	local clock = now()
	local camera = Workspace.CurrentCamera
	if camera then
		listenerPosition = camera.CFrame.Position
	else
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			listenerPosition = root.Position
		end
	end
	AudioEnvironment.beginFrame(profile.raysPerFrame, clock)
	listenerZone = AudioEnvironment.zoneAt(listenerPosition)
	AudioBus.setEnvironment(AudioEnvironment.environmentAt(listenerPosition))
	AudioBus.step(deltaTime)

	for _, voice in pool do
		if not voice.active then
			continue
		end
		local faded = stepFade(voice, deltaTime)
		if not voice.active then
			continue
		end
		if not voice.loop and (frame + voice.index) % FINISH_CHECK_FRAMES == 0 then
			if clock > voice.startedAt + voice.delay + 0.3 and not voice.player.IsPlaying then
				release(voice)
				continue
			end
		end
		if not voice.is3D then
			if faded then
				applyVolume(voice)
			end
			continue
		end
		local cadence = if voice.distance < NEAR then profile.nearUpdateFrames else profile.farUpdateFrames
		if (frame + voice.index) % cadence == 0 then
			propagate(voice, deltaTime * cadence, if voice.class.reflections then 2 else 1, false)
		elseif faded and not voice.dormant then
			applyVolume(voice)
		end
	end
end

local function startVoice(voice: Voice, id: number, spec: SpatialAudioConfig.ClassSpec, className: string, play: PlaySpec, is3D: boolean, position: Vector3, distance: number, range: number, hold: number, weight: number, band: SpatialAudioConfig.LayerBand?)
	voice.active = true
	voice.generation += 1
	voice.className = className
	voice.class = spec
	voice.is3D = is3D
	voice.loop = play.loop == true
	voice.follow = if is3D then play.follow else nil
	voice.position = position
	voice.range = range
	voice.distance = distance
	voice.userVolume = 1
	voice.layerWeight = weight
	voice.layerBand = band
	voice.occlusion = 0
	voice.occlusionLoss = 0
	voice.occlusionCutoff = ABSORPTION.ceilingHz
	voice.doorway = 0
	voice.gain = 1
	voice.cutoffCap = play.cutoff or ABSORPTION.ceilingHz
	voice.dormant = false
	voice.lastCutoff = -1
	voice.lastVolume = -1
	voice.stopOnFade = false
	local fadeIn = play.fadeIn or 0
	voice.fade = if fadeIn > 0 then 0 else 1
	voice.fadeTarget = 1
	voice.fadeRate = if fadeIn > 0 then 1 / fadeIn else 0

	local gainJitter = AudioMath.dbToGain((random:NextNumber() * 2 - 1) * spec.gainJitterDb)
	voice.baseVolume = (play.volume or 1) * gainJitter
	local pitchJitter = play.pitchJitter or spec.pitchJitter

	local player = voice.player
	player.Looping = voice.loop
	player.PlaybackSpeed = (play.pitch or 1) * AudioMath.jitter(random:NextNumber(), pitchJitter)
	player.Asset = ASSET_PREFIX .. tostring(id)
	player.TimePosition = 0

	local busName = play.bus or spec.bus
	if is3D then
		local emitter = voice.emitter
		emitter.AudioInteractionGroup = AudioBus.group(busName) or AudioBus.group(spec.bus) or ""
		emitter:SetDistanceAttenuation(curveFor(spec.curve, range, hold))
		local follow = voice.follow
		if follow then
			emitter.PositionInstance = follow
		else
			voice.attachment.WorldPosition = position
			emitter.PositionInstance = voice.attachment
		end
		voice.wireOut.TargetInstance = emitter
	else
		voice.emitter.PositionInstance = nil
		voice.wireOut.TargetInstance = AudioBus.input(busName) or AudioBus.input(spec.bus)
	end
	voice.wireSend.TargetInstance = if spec.duck then AudioBus.duckSend() else nil

	local delay = play.delay or 0
	if is3D and spec.delay and not voice.loop then
		delay += AudioMath.distanceDelay(distance, SpatialAudioConfig.DELAY_MIN_DISTANCE, SpatialAudioConfig.SPEED_OF_SOUND_STUDS)
	end
	voice.delay = delay
	voice.startedAt = now()

	if is3D then
		-- first propagation before the sound starts, with its own rays and a long step so
		-- the smoothing lands at once: a voice born behind a wall is muffled from its
		-- first sample
		propagate(voice, 10, if spec.reflections then 2 else 1, true)
		if not voice.active then
			return
		end
	else
		applyCutoff(voice, voice.cutoffCap)
		applyVolume(voice)
	end

	if delay > 0 then
		voice.actionId = player:Play(mixerTime() + delay)
	else
		voice.actionId = nil
		player:Play()
	end
end

-- Every voice of a handle, when it is still the generation the handle was given.
local function eachVoice(self: Handle, callback: (Voice) -> ())
	for _, ref in self.refs do
		if ref.voice.active and ref.voice.generation == ref.generation then
			callback(ref.voice)
		end
	end
end

function Handle.stop(self: Handle, fadeSeconds: number?)
	eachVoice(self, function(voice)
		if fadeSeconds and fadeSeconds > 0 then
			voice.fadeTarget = 0
			voice.fadeRate = voice.fade / fadeSeconds
			voice.stopOnFade = true
		else
			release(voice)
		end
	end)
end

function Handle.setVolume(self: Handle, volume: number)
	eachVoice(self, function(voice)
		voice.userVolume = math.max(volume, 0)
		applyVolume(voice)
	end)
end

function Handle.fade(self: Handle, to: number, seconds: number)
	eachVoice(self, function(voice)
		voice.fadeTarget = math.clamp(to, 0, 1)
		voice.fadeRate = if seconds > 0 then math.abs(voice.fade - voice.fadeTarget) / seconds else 0
		voice.stopOnFade = false
	end)
end

function Handle.setPitch(self: Handle, pitch: number)
	eachVoice(self, function(voice)
		voice.player.PlaybackSpeed = pitch
	end)
end

function Handle.setPosition(self: Handle, position: Vector3)
	eachVoice(self, function(voice)
		voice.follow = nil
		voice.position = position
		voice.attachment.WorldPosition = position
		voice.emitter.PositionInstance = voice.attachment
	end)
end

function Handle.isPlaying(self: Handle): boolean
	for _, ref in self.refs do
		if ref.voice.active and ref.voice.generation == ref.generation then
			return true
		end
	end
	return false
end

local function newHandle(): Handle
	return setmetatable({ refs = {} }, Handle)
end

local function layerIds(play: PlaySpec): { [string]: number }
	local ids: { [string]: number } = {}
	local keys = play.layers
	if keys then
		for name, key in keys do
			local id = resolveId(key)
			if id > 0 then
				ids[name] = id
			end
		end
	end
	local raw = play.layerIds
	if raw then
		for name, id in raw do
			if id > 0 then
				ids[name] = id
			end
		end
	end
	return ids
end

function AudioEngine.enabled(): boolean
	return started and isEnabled()
end

function AudioEngine.profileName(): string
	return profileName
end

-- Rays a reflection fan casts on this platform.
function AudioEngine.reflectionRays(): number
	return profile.reflectionRays
end

function AudioEngine.listenerPosition(): Vector3
	return listenerPosition
end

function AudioEngine.resolveId(key: string): number
	return resolveId(key)
end

function AudioEngine.mixerTime(): number
	return mixerTime()
end

-- Plays a sound and returns a handle; a silent request (id 0, out of range, or no voice
-- worth stealing) returns an empty handle whose methods do nothing.
function AudioEngine.play(play: PlaySpec): Handle
	local handle = newHandle()
	if not AudioEngine.enabled() then
		return handle
	end

	local hasPoint = play.position ~= nil or play.follow ~= nil
	local spec = classFor(play.class, hasPoint)
	local range = play.range or spec.range
	local hold = math.min(play.hold or spec.hold, math.max(range - 1, 0))
	local is3D = range > 0 and hasPoint
	local position = play.position or Vector3.zero
	if is3D and play.follow then
		local followed = instancePosition(play.follow :: Instance)
		if not followed then
			return handle
		end
		position = followed
	end
	local distance = if is3D then (position - listenerPosition).Magnitude else 0
	local loop = play.loop == true
	if is3D and not loop and distance > range * CULL_MARGIN then
		return handle
	end

	local bands = spec.layerBands
	local ids = layerIds(play)
	local hasLayers = bands ~= nil and next(ids) ~= nil
	if not hasLayers then
		local id = play.id or (if play.key then resolveId(play.key) else 0)
		if id <= 0 then
			return handle
		end
		local voice = acquire(play.class, spec, distance, range)
		if voice then
			startVoice(voice, id, spec, play.class, play, is3D, position, distance, range, hold, 1, nil)
			if voice.active then
				table.insert(handle.refs, { voice = voice, generation = voice.generation })
			end
		end
		return handle
	end

	-- distance layers: one voice per band that has weight, each falling back to the
	-- nearest key the sound actually has
	local available: { [string]: boolean } = {}
	for name in ids do
		available[name] = true
	end
	local ordered: { SpatialAudioConfig.LayerBand } = {}
	local names: { string } = {}
	for _, name in LAYER_ORDER do
		local band = (bands :: { [string]: SpatialAudioConfig.LayerBand })[name]
		if band then
			table.insert(ordered, band)
			table.insert(names, name)
		end
	end
	local weights = AudioMath.layerWeights(if is3D then distance else 0, ordered)
	for index, band in ordered do
		local weight = weights[index]
		if weight < LAYER_MIN_WEIGHT and not loop then
			continue
		end
		local key = AudioMath.fallbackLayer(available, names[index], LAYER_ORDER)
		local id = if key then ids[key] else nil
		if not id then
			continue
		end
		local voice = acquire(play.class, spec, distance, range)
		if voice then
			startVoice(voice, id, spec, play.class, play, is3D, position, distance, range, hold, weight, if is3D then band else nil)
			if voice.active then
				table.insert(handle.refs, { voice = voice, generation = voice.generation })
			end
		end
	end
	return handle
end

function AudioEngine.stopAll()
	for _, voice in pool do
		release(voice)
	end
end

export type VoiceInfo = {
	class: string,
	bus: string,
	distance: number,
	delay: number,
	occlusion: number,
	cutoff: number,
	volume: number,
	loop: boolean,
	is3D: boolean,
}

-- Rows for the debug overlay (allocates; only called while the overlay is open).
function AudioEngine.snapshot(): ({ VoiceInfo }, number, number)
	local rows: { VoiceInfo } = {}
	local active = 0
	for _, voice in pool do
		if not voice.active then
			continue
		end
		active += 1
		table.insert(rows, {
			class = voice.className,
			bus = voice.class.bus,
			distance = voice.distance,
			delay = voice.delay,
			occlusion = voice.occlusion,
			cutoff = voice.lastCutoff,
			volume = voice.lastVolume,
			loop = voice.loop,
			is3D = voice.is3D,
		})
	end
	return rows, active, #pool
end

local function preload()
	local assets: { string } = {}
	for category, group in AssetIds.audio :: { [string]: { [string]: number } } do
		if category == "weapons" or category == "unused" then
			continue
		end
		for _, id in group do
			if typeof(id) == "number" and id > 0 then
				table.insert(assets, ASSET_PREFIX .. tostring(id))
			end
		end
	end
	if #assets == 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)
	end)
end

function AudioEngine.init()
	if started or not isEnabled() then
		return
	end
	started = true
	simulation = SfxConfig.ACOUSTIC_SIMULATION == true
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		profile = SpatialAudioConfig.profiles.mobile
		profileName = "mobile"
	end

	AudioBus.init(simulation)
	AudioEnvironment.init()

	local folder = Instance.new("Folder")
	folder.Name = "TFZ_Voices"
	folder.Parent = SoundService
	for index = 1, profile.poolSize do
		pool[index] = createVoice(index, folder)
	end

	preload()
	RunService.Heartbeat:Connect(step)
end

return AudioEngine
