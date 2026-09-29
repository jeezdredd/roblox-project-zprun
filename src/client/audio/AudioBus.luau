--!strict

-- The bus graph of the spatial audio engine, built once under SoundService.TFZ_Audio:
--
--   3D voices are heard by one AudioListener per bus (interaction group TFZ_<bus>) and
--   2D voices wire straight into the bus fader. Each bus is a fader followed by its
--   effects, everything sums into the master fader, then the limiter, then the device.
--
--   weapons  : listener -> fader -> reverb(env) -> echo(slapback) -> master
--   sfx      : listener -> fader -> reverb(env) -> echo(slapback) -> equalizer -> master
--   voices   : listener -> fader -> reverb(env) -> master
--   ambience : listener -> fader -> duck group -> compressor -> master
--   music    :             fader -> duck group -> compressor -> master
--   ui       :             fader -> master
--   duck send fader -> compressor.Sidechain   (voices of classes with duck = true)
--
-- Every wire here is many-to-one (several sources into one Input pin), which the
-- effects guide documents; no source pin feeds two wires. The settings sliders drive
-- the master and music faders through MusicController; the environment reverb and
-- slapback glide towards the preset of the listener's environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local SpatialAudioConfig = require(ReplicatedStorage.Shared.config.SpatialAudioConfig)
local AudioMath = require(script.Parent.AudioMath)

local AudioBus = {}

type Bus = {
	name: string,
	group: string,
	fader: AudioFader,
	listener: AudioListener?,
	reverb: AudioReverb?,
	echo: AudioEcho?,
	equalizer: AudioEqualizer?,
}

-- buses whose reverb and echo follow the environment
local ENVIRONMENT_BUSES = { weapons = true, sfx = true, voices = true }
local SLAPBACK_BUSES = { weapons = true, sfx = true }
local DUCKED_BUSES = { ambience = true, music = true }
-- the wet level that stands in for "off" (AudioEcho and AudioReverb have no gain floor of -inf)
local SILENT_DB = -80

local root: Folder? = nil
local buses: { [string]: Bus } = {}
local masterFader: AudioFader? = nil
local duckSendFader: AudioFader? = nil
local masterVolume = 0.7
local musicVolume = 0.5
local muted = false
local duckScale = 1
local environmentId = "Open"
local current: SpatialAudioConfig.EnvironmentSpec = table.clone(SpatialAudioConfig.environments.Open)
local target: SpatialAudioConfig.EnvironmentSpec = SpatialAudioConfig.environments.Open
local simulation = false

local function wire(source: Instance, targetInstance: Instance, parent: Instance, targetPin: string?): Wire
	local link = Instance.new("Wire")
	link.SourceInstance = source
	link.SourceName = "Output"
	link.TargetInstance = targetInstance
	link.TargetName = targetPin or "Input"
	link.Parent = parent
	return link
end

local function fader(name: string, volume: number, parent: Instance): AudioFader
	local node = Instance.new("AudioFader")
	node.Name = name
	node.Volume = volume
	node.Parent = parent
	return node
end

local function applyEnvironment(spec: SpatialAudioConfig.EnvironmentSpec)
	for name, bus in buses do
		local reverb = bus.reverb
		if reverb then
			reverb.DecayTime = spec.decay
			reverb.DecayRatio = spec.decayRatio
			reverb.WetLevel = spec.wet
			reverb.HighCutFrequency = spec.highCut
			reverb.EarlyDelayTime = spec.earlyDelay
			reverb.LateDelayTime = spec.lateDelay
			reverb.Density = spec.density
			reverb.Diffusion = spec.diffusion
		end
		local echo = bus.echo
		if echo and SLAPBACK_BUSES[name] then
			local active = spec.echoDelay > 0
			echo.DelayTime = if active then spec.echoDelay else 0.001
			echo.Feedback = spec.echoFeedback
			echo.WetLevel = if active then spec.echoWet else SILENT_DB
		end
	end
end

local function applyMaster()
	local master = masterFader
	if master then
		master.Volume = if muted then 0 else masterVolume
	end
end

local function applyMusic()
	local music = buses.music
	if music then
		music.fader.Volume = musicVolume * duckScale
	end
end

local function attachListeners()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	for _, bus in buses do
		if bus.listener then
			bus.listener.Parent = camera
		end
	end
end

local function simulationMode(): Enum.SimulationMode
	return if simulation then Enum.SimulationMode.Enabled else Enum.SimulationMode.Disabled
end

local function buildBus(name: string, folder: Instance, master: AudioFader, duckGroup: AudioFader): Bus
	local busFolder = Instance.new("Folder")
	busFolder.Name = name
	busFolder.Parent = folder

	local busFader = fader("Fader", 1, busFolder)
	local bus: Bus = { name = name, group = SpatialAudioConfig.INTERACTION_GROUP_PREFIX .. name, fader = busFader }

	local is2DOnly = name == "music" or name == "ui"
	if not is2DOnly then
		local listener = Instance.new("AudioListener")
		listener.Name = "Listener_" .. name
		listener.AudioInteractionGroup = bus.group
		listener.PositionType = Enum.ListenerPositionType.Parent
		listener.AcousticSimulationEnabled = simulation
		listener.OcclusionEnabled = simulationMode()
		listener.ReverbEnabled = simulationMode()
		listener.DiffractionEnabled = simulationMode()
		bus.listener = listener
		wire(listener, busFader, busFolder)
	end

	local tail: Instance = busFader
	if ENVIRONMENT_BUSES[name] and not simulation then
		local reverb = Instance.new("AudioReverb")
		reverb.Name = "Reverb"
		reverb.DryLevel = 0
		reverb.Parent = busFolder
		wire(tail, reverb, busFolder)
		bus.reverb = reverb
		tail = reverb
	end
	if SLAPBACK_BUSES[name] and not simulation then
		local echo = Instance.new("AudioEcho")
		echo.Name = "Slapback"
		echo.DryLevel = 0
		echo.WetLevel = SILENT_DB
		echo.DelayTime = 0.001
		echo.Feedback = 0
		echo.RampTime = 0.05
		echo.Parent = busFolder
		wire(tail, echo, busFolder)
		bus.echo = echo
		tail = echo
	end
	if name == "sfx" then
		local equalizer = Instance.new("AudioEqualizer")
		equalizer.Name = "Concussion"
		equalizer.LowGain = 0
		equalizer.MidGain = 0
		equalizer.HighGain = 0
		equalizer.Parent = busFolder
		wire(tail, equalizer, busFolder)
		bus.equalizer = equalizer
		tail = equalizer
	end
	wire(tail, if DUCKED_BUSES[name] then duckGroup else master, busFolder)
	return bus
end

function AudioBus.init(useSimulation: boolean)
	if root then
		return
	end
	simulation = useSimulation
	local folder = Instance.new("Folder")
	folder.Name = "TFZ_Audio"
	folder.Parent = SoundService
	root = folder

	local master = fader("Master", masterVolume, folder)
	masterFader = master

	local limiter = Instance.new("AudioLimiter")
	limiter.Name = "Limiter"
	limiter.MaxLevel = SpatialAudioConfig.LIMITER.maxLevel
	limiter.Release = SpatialAudioConfig.LIMITER.release
	limiter.Parent = folder
	wire(master, limiter, folder)

	local output = Instance.new("AudioDeviceOutput")
	output.Name = "Output"
	output.Parent = folder
	wire(limiter, output, folder)

	-- ambience and music sum here, then duck together under the sidechain
	local duckGroup = fader("DuckGroup", 1, folder)
	local compressor = Instance.new("AudioCompressor")
	compressor.Name = "Duck"
	compressor.Threshold = SpatialAudioConfig.DUCK.threshold
	compressor.Ratio = SpatialAudioConfig.DUCK.ratio
	compressor.Attack = SpatialAudioConfig.DUCK.attack
	compressor.Release = SpatialAudioConfig.DUCK.release
	compressor.MakeupGain = SpatialAudioConfig.DUCK.makeupGain
	compressor.Parent = folder
	wire(duckGroup, compressor, folder)
	wire(compressor, master, folder)

	local send = fader("DuckSend", 1, folder)
	duckSendFader = send
	wire(send, compressor, folder, "Sidechain")

	for _, name in SpatialAudioConfig.BUSES do
		buses[name] = buildBus(name, folder, master, duckGroup)
	end

	attachListeners()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(attachListeners)

	applyEnvironment(current)
	applyMaster()
	applyMusic()

	if simulation then
		pcall(function()
			SoundService.AcousticSimulationEnabled = true
		end)
	end
end

function AudioBus.isBuilt(): boolean
	return root ~= nil
end

-- The instance a 2D voice wires into.
function AudioBus.input(name: string): Instance?
	local bus = buses[name]
	return if bus then bus.fader else nil
end

-- The interaction group a 3D voice's emitter joins to be heard on the bus.
function AudioBus.group(name: string): string?
	local bus = buses[name]
	return if bus then bus.group else nil
end

function AudioBus.duckSend(): Instance?
	return duckSendFader
end

function AudioBus.simulationEnabled(): boolean
	return simulation
end

function AudioBus.setMasterVolume(value: number)
	masterVolume = math.clamp(value, 0, 1)
	applyMaster()
end

function AudioBus.setMusicVolume(value: number)
	musicVolume = math.clamp(value, 0, 1)
	applyMusic()
end

function AudioBus.setMuted(value: boolean)
	muted = value
	applyMaster()
end

-- The chase duck from UiSfx: 0 no reduction, 1 full (floored at a tenth like the
-- legacy path).
function AudioBus.setDuck(reduction: number)
	duckScale = math.clamp(1 - reduction, 0.1, 1)
	applyMusic()
end

-- The concussion equaliser on the sfx bus.
function AudioBus.setConcussion(highGain: number, midGain: number)
	local sfx = buses.sfx
	local equalizer = sfx and sfx.equalizer
	if equalizer then
		equalizer.HighGain = highGain
		equalizer.MidGain = midGain
	end
end

function AudioBus.setEnvironment(id: string)
	local spec = SpatialAudioConfig.environments[id]
	if not spec or id == environmentId then
		return
	end
	environmentId = id
	target = spec
end

function AudioBus.environment(): string
	return environmentId
end

-- Glides the reverb and slapback of every environment bus towards the target preset.
function AudioBus.step(deltaTime: number)
	if simulation or not root then
		return
	end
	local glide = SpatialAudioConfig.ENVIRONMENT.glide
	local moving = false
	for key, goal in target :: { [string]: number } do
		local value = (current :: { [string]: number })[key]
		if value ~= goal then
			local moved = AudioMath.approach(value, goal, deltaTime, glide)
			if math.abs(moved - goal) < 1e-3 then
				moved = goal
			end
			(current :: { [string]: number })[key] = moved
			moving = true
		end
	end
	if moving then
		applyEnvironment(current)
	end
end

return AudioBus
