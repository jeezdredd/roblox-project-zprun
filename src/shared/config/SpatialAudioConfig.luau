--!strict

-- Data for the spatial audio engine (src/client/audio): one entry per sound class,
-- per acoustic environment and per material family, plus the platform budgets. The
-- reasoning and the sources behind every number are in docs/audio/spatial-audio.md.
-- Distances are studs (1 stud = 0.28 m), gains are dB unless named "gain", times are
-- seconds, frequencies are hertz.

export type CurveShape = "natural" | "power" | "linear"

export type LayerBand = { lo: number, hi: number }

export type ClassSpec = {
	-- weapons | sfx | voices | ambience | music | ui
	bus: string,
	-- audible range; 0 means a 2D sound with no propagation
	range: number,
	-- full-volume radius, the "size" of the source
	hold: number,
	curve: CurveShape,
	-- air absorption strength, 1 is the exaggerated ISO curve, 0 none
	air: number,
	-- scales the material loss when the path is blocked, 0 ignores occlusion
	occlusion: number,
	reflections: boolean,
	-- 0..100, higher survives a voice steal
	priority: number,
	maxVoices: number,
	-- speed-of-sound start delay for one-shots
	delay: boolean,
	-- feeds the sidechain that ducks ambience and music
	duck: boolean,
	pitchJitter: number,
	gainJitterDb: number,
	-- distance layers a sound may supply (close, mid, far) and where each one plays
	layerBands: { [string]: LayerBand }?,
}

export type EnvironmentSpec = {
	decay: number,
	decayRatio: number,
	wet: number,
	highCut: number,
	earlyDelay: number,
	lateDelay: number,
	density: number,
	diffusion: number,
	-- slapback echo; 0 delay disables it
	echoDelay: number,
	echoFeedback: number,
	echoWet: number,
}

export type MaterialSpec = {
	-- transmission loss through the part, negative dB
	loss: number,
	-- low-pass cutoff of what gets through
	cutoff: number,
	-- 0..1 share of energy a reflection off it keeps
	reflect: number,
}

export type Profile = {
	poolSize: number,
	raysPerFrame: number,
	reflectionRays: number,
	reflectionVoices: number,
	nearUpdateFrames: number,
	farUpdateFrames: number,
	-- class voice limits are multiplied by this (minimum 2)
	voiceLimitScale: number,
}

local SpatialAudioConfig = {}

SpatialAudioConfig.BUSES = { "weapons", "sfx", "voices", "ambience", "music", "ui" }
SpatialAudioConfig.INTERACTION_GROUP_PREFIX = "TFZ_"
SpatialAudioConfig.NEAR_DISTANCE = 60
SpatialAudioConfig.LAYER_ORDER = { "close", "mid", "far" }
SpatialAudioConfig.SPEED_OF_SOUND_STUDS = 343 / 0.28
-- one-shots nearer than this start at once (raise it if near shots read as lag)
SpatialAudioConfig.DELAY_MIN_DISTANCE = 0

SpatialAudioConfig.ABSORPTION = {
	dbPer100mAt8k = 10.5,
	exaggeration = 6,
	frequencySlope = 1.7,
	kneeMetres = 25,
	thresholdDb = 6,
	floorHz = 1200,
	ceilingHz = 22000,
}

SpatialAudioConfig.OCCLUSION = {
	-- seconds for a cleared path to open and a blocked one to close
	attack = 0.12,
	release = 0.25,
	-- sideways offset of the second ray on gunshots and explosions
	edgeOffset = 3,
	-- the loss of a partially blocked path (one of two rays) as a share of full
	partialBlock = 0.5,
}

SpatialAudioConfig.ENVIRONMENT = {
	-- a source inside an interior heard from outside, or the reverse
	doorwayLossDb = -9,
	doorwayCutoff = 2500,
	doorwayGlide = 0.3,
	-- reverb and echo parameter glide when the listener changes environment
	glide = 0.5,
}

SpatialAudioConfig.REFLECTIONS = {
	range = 140,
	gain = 0.55,
	referenceDistance = 60,
	-- taps closer than this fuse with the direct sound (precedence effect)
	minDelay = 0.04,
	mergeDistance = 8,
	interiorCap = 2,
	pitch = 0.96,
	upwardRayDegrees = 30,
}

SpatialAudioConfig.DUCK = {
	threshold = -24,
	ratio = 4,
	attack = 0.005,
	release = 0.6,
	makeupGain = 0,
}

SpatialAudioConfig.LIMITER = {
	maxLevel = -1,
	release = 0.08,
}

SpatialAudioConfig.profiles = {
	desktop = {
		poolSize = 48,
		raysPerFrame = 8,
		reflectionRays = 6,
		reflectionVoices = 12,
		nearUpdateFrames = 1,
		farUpdateFrames = 4,
		voiceLimitScale = 1,
	},
	mobile = {
		poolSize = 24,
		raysPerFrame = 4,
		reflectionRays = 3,
		reflectionVoices = 6,
		nearUpdateFrames = 2,
		farUpdateFrames = 6,
		voiceLimitScale = 0.5,
	},
} :: { [string]: Profile }

local function class(spec: ClassSpec): ClassSpec
	return spec
end

SpatialAudioConfig.classes = {
	-- the shooter's own gun: close layers 2D, the environment layer through reflections
	-- (played by WeaponSfx once it moves onto the engine, docs/audio/weapons-integration.md)
	OwnGunshot = class({ bus = "weapons", range = 0, hold = 0, curve = "natural", air = 0, occlusion = 0, reflections = true, priority = 100, maxVoices = 8, delay = false, duck = true, pitchJitter = 0.04, gainJitterDb = 1.5 }),
	GunshotRemote = class({ bus = "weapons", range = 1400, hold = 24, curve = "power", air = 1, occlusion = 1, reflections = true, priority = 90, maxVoices = 8, delay = true, duck = true, pitchJitter = 0.04, gainJitterDb = 1.5, layerBands = { close = { lo = 0, hi = 60 }, mid = { lo = 40, hi = 350 }, far = { lo = 250, hi = 1400 } } }),
	Explosion = class({ bus = "sfx", range = 2600, hold = 60, curve = "power", air = 1, occlusion = 0.7, reflections = true, priority = 100, maxVoices = 4, delay = true, duck = true, pitchJitter = 0.06, gainJitterDb = 1, layerBands = { close = { lo = 0, hi = 120 }, far = { lo = 90, hi = 2600 } } }),
	ZombieVocal = class({ bus = "voices", range = 140, hold = 8, curve = "natural", air = 0.6, occlusion = 1, reflections = false, priority = 60, maxVoices = 8, delay = true, duck = false, pitchJitter = 0.15, gainJitterDb = 1.5 }),
	ZombieLoop = class({ bus = "voices", range = 90, hold = 7, curve = "natural", air = 0.6, occlusion = 1, reflections = false, priority = 40, maxVoices = 10, delay = false, duck = false, pitchJitter = 0, gainJitterDb = 0 }),
	ZombieFootstep = class({ bus = "sfx", range = 50, hold = 4, curve = "natural", air = 0.4, occlusion = 1, reflections = false, priority = 25, maxVoices = 8, delay = false, duck = false, pitchJitter = 0.07, gainJitterDb = 1 }),
	PlayerFootstep = class({ bus = "sfx", range = 70, hold = 6, curve = "natural", air = 0.2, occlusion = 0, reflections = false, priority = 35, maxVoices = 6, delay = false, duck = false, pitchJitter = 0.07, gainJitterDb = 1 }),
	TeammateFootstep = class({ bus = "sfx", range = 90, hold = 6, curve = "natural", air = 0.4, occlusion = 1, reflections = false, priority = 30, maxVoices = 6, delay = false, duck = false, pitchJitter = 0.07, gainJitterDb = 1 }),
	Impact = class({ bus = "sfx", range = 120, hold = 6, curve = "natural", air = 0.8, occlusion = 1, reflections = false, priority = 50, maxVoices = 8, delay = true, duck = false, pitchJitter = 0.06, gainJitterDb = 1.5 }),
	Casing = class({ bus = "sfx", range = 45, hold = 2, curve = "natural", air = 0.3, occlusion = 0.5, reflections = false, priority = 20, maxVoices = 12, delay = false, duck = false, pitchJitter = 0.04, gainJitterDb = 1.5 }),
	Bite = class({ bus = "voices", range = 70, hold = 6, curve = "natural", air = 0.3, occlusion = 0.5, reflections = false, priority = 80, maxVoices = 2, delay = false, duck = false, pitchJitter = 0.12, gainJitterDb = 1 }),
	-- fire, sirens, radio, rotor: range comes from the call
	AmbienceSource = class({ bus = "ambience", range = 320, hold = 40, curve = "linear", air = 0.7, occlusion = 0.6, reflections = false, priority = 30, maxVoices = 10, delay = false, duck = false, pitchJitter = 0, gainJitterDb = 0 }),
	-- roomtone, walla, wind, heartbeat, breath
	AmbienceBed = class({ bus = "ambience", range = 0, hold = 0, curve = "linear", air = 0, occlusion = 0, reflections = false, priority = 30, maxVoices = 8, delay = false, duck = false, pitchJitter = 0, gainJitterDb = 0 }),
	-- gear rattle, landings, cloth: on the listener, no propagation
	PlayerFoley = class({ bus = "sfx", range = 0, hold = 0, curve = "natural", air = 0, occlusion = 0, reflections = false, priority = 45, maxVoices = 6, delay = false, duck = false, pitchJitter = 0.08, gainJitterDb = 1 }),
	Reflection = class({ bus = "sfx", range = 300, hold = 10, curve = "natural", air = 1, occlusion = 0.5, reflections = false, priority = 45, maxVoices = 12, delay = true, duck = false, pitchJitter = 0.02, gainJitterDb = 1 }),
	Music = class({ bus = "music", range = 0, hold = 0, curve = "linear", air = 0, occlusion = 0, reflections = false, priority = 100, maxVoices = 2, delay = false, duck = false, pitchJitter = 0, gainJitterDb = 0 }),
	UI = class({ bus = "ui", range = 0, hold = 0, curve = "linear", air = 0, occlusion = 0, reflections = false, priority = 100, maxVoices = 4, delay = false, duck = false, pitchJitter = 0.04, gainJitterDb = 0 }),
	Scream = class({ bus = "voices", range = 0, hold = 0, curve = "linear", air = 0, occlusion = 0, reflections = false, priority = 100, maxVoices = 1, delay = false, duck = true, pitchJitter = 0, gainJitterDb = 0 }),
	-- SfxPlayer.play2D / play3D wrappers for call sites not moved yet
	Generic2D = class({ bus = "sfx", range = 0, hold = 0, curve = "natural", air = 0, occlusion = 0, reflections = false, priority = 40, maxVoices = 8, delay = false, duck = false, pitchJitter = 0, gainJitterDb = 0 }),
	Generic3D = class({ bus = "sfx", range = 120, hold = 10, curve = "natural", air = 0.6, occlusion = 1, reflections = false, priority = 40, maxVoices = 8, delay = true, duck = false, pitchJitter = 0, gainJitterDb = 0 }),
} :: { [string]: ClassSpec }

local function environment(spec: EnvironmentSpec): EnvironmentSpec
	return spec
end

SpatialAudioConfig.environments = {
	Hangar = environment({ decay = 2.6, decayRatio = 0.5, wet = -10, highCut = 5000, earlyDelay = 0.03, lateDelay = 0.02, density = 0.8, diffusion = 0.8, echoDelay = 0, echoFeedback = 0, echoWet = -80 }),
	Interior = environment({ decay = 1.4, decayRatio = 0.5, wet = -12, highCut = 4000, earlyDelay = 0.012, lateDelay = 0.01, density = 0.7, diffusion = 0.7, echoDelay = 0, echoFeedback = 0, echoWet = -80 }),
	Street = environment({ decay = 0.9, decayRatio = 0.4, wet = -20, highCut = 6000, earlyDelay = 0.04, lateDelay = 0.02, density = 0.5, diffusion = 0.6, echoDelay = 0.085, echoFeedback = 0.18, echoWet = -16 }),
	Forest = environment({ decay = 0.6, decayRatio = 0.3, wet = -22, highCut = 3500, earlyDelay = 0.025, lateDelay = 0.015, density = 0.9, diffusion = 0.9, echoDelay = 0, echoFeedback = 0, echoWet = -80 }),
	Open = environment({ decay = 0.3, decayRatio = 0.3, wet = -30, highCut = 3000, earlyDelay = 0.01, lateDelay = 0.005, density = 0.3, diffusion = 0.5, echoDelay = 0, echoFeedback = 0, echoWet = -80 }),
} :: { [string]: EnvironmentSpec }

-- environments whose reverb already carries the early reflections
SpatialAudioConfig.INTERIOR_ENVIRONMENTS = { Hangar = true, Interior = true }

local STONE: MaterialSpec = { loss = -30, cutoff = 600, reflect = 0.9 }
local METAL: MaterialSpec = { loss = -26, cutoff = 900, reflect = 0.95 }
local WOOD: MaterialSpec = { loss = -18, cutoff = 1500, reflect = 0.6 }
local GLASS: MaterialSpec = { loss = -16, cutoff = 3000, reflect = 0.8 }
local SOFT: MaterialSpec = { loss = -10, cutoff = 2500, reflect = 0.25 }
local WATER: MaterialSpec = { loss = -22, cutoff = 800, reflect = 0.7 }

SpatialAudioConfig.DEFAULT_MATERIAL = STONE

SpatialAudioConfig.materials = {
	Concrete = STONE,
	Brick = STONE,
	Cobblestone = STONE,
	Pavement = STONE,
	Asphalt = STONE,
	Rock = STONE,
	Basalt = STONE,
	Granite = STONE,
	Slate = STONE,
	Limestone = STONE,
	Sandstone = STONE,
	Marble = STONE,
	CrackedLava = STONE,
	Metal = METAL,
	CorrodedMetal = METAL,
	DiamondPlate = METAL,
	Foil = METAL,
	Wood = WOOD,
	WoodPlanks = WOOD,
	Cardboard = WOOD,
	Plaster = WOOD,
	Plastic = WOOD,
	SmoothPlastic = WOOD,
	Neon = WOOD,
	Glass = GLASS,
	Ice = GLASS,
	ForceField = GLASS,
	Fabric = SOFT,
	Carpet = SOFT,
	Leaf = SOFT,
	LeafyGrass = SOFT,
	Grass = SOFT,
	Sand = SOFT,
	Snow = SOFT,
	Mud = SOFT,
	Ground = SOFT,
	Salt = SOFT,
	Pebble = SOFT,
	Water = WATER,
} :: { [string]: MaterialSpec }

function SpatialAudioConfig.getClass(name: string): ClassSpec?
	return SpatialAudioConfig.classes[name]
end

function SpatialAudioConfig.material(name: string): MaterialSpec
	return SpatialAudioConfig.materials[name] or SpatialAudioConfig.DEFAULT_MATERIAL
end

return SpatialAudioConfig
