--!strict

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local SfxConfig = require(ReplicatedStorage.Shared.config.SfxConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local AudioEngine = require(script.Parent.Parent.audio.AudioEngine)
local AudioEnvironment = require(script.Parent.Parent.audio.AudioEnvironment)
local AudioReflections = require(script.Parent.Parent.audio.AudioReflections)
local WeaponAudioMath = require(script.Parent.Parent.audio.WeaponAudioMath)
local SfxPlayer = require(script.Parent.SfxPlayer)
local MusicController = require(script.Parent.MusicController)

local WeaponSfx = {}

local player = Players.LocalPlayer

local function onEngine(): boolean
	return SfxConfig.WEAPONS_ON_ENGINE == true and AudioEngine.enabled()
end

local weaponGroup: SoundGroup? = nil
local reverb: ReverbSoundEffect? = nil
local acousticZones: { BasePart } = {}
local zonesScanned = false

local function scanZones()
	if zonesScanned then
		return
	end
	zonesScanned = true
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("AcousticSpace") ~= nil then
			table.insert(acousticZones, descendant)
		end
	end
	Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant:GetAttribute("AcousticSpace") ~= nil then
			table.insert(acousticZones, descendant)
		end
	end)
end

local function isInterior(position: Vector3): boolean
	for index = #acousticZones, 1, -1 do
		local zone = acousticZones[index]
		if not zone.Parent then
			table.remove(acousticZones, index)
		else
			local localPoint = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z then
				return zone:GetAttribute("AcousticSpace") == "Interior"
			end
		end
	end
	return false
end

local function ensureGroup(): SoundGroup
	local group = weaponGroup
	if group then
		return group
	end
	local created = Instance.new("SoundGroup")
	created.Name = "Weapons"
	created.Volume = 1
	created.Parent = MusicController.getSfxGroup()

	local reverbEffect = Instance.new("ReverbSoundEffect")
	reverbEffect.Enabled = false
	reverbEffect.DecayTime = 1.5
	reverbEffect.Density = 0.6
	reverbEffect.Diffusion = 0.7
	reverbEffect.WetLevel = -8
	reverbEffect.DryLevel = 0
	reverbEffect.Parent = created

	weaponGroup = created
	reverb = reverbEffect
	return created
end

local MIN_VOICES = 4
local MAX_VOICES = 8
local PITCH_JITTER = 0.04
local GAIN_JITTER_DB = 1.5

local pools: { [number]: { Sound } } = {}
local poolCursor: { [number]: number } = {}

local function newVoice(soundId: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.SoundGroup = ensureGroup()
	sound.Parent = SoundService
	return sound
end

local function ensurePool(soundId: number): { Sound }
	local existing = pools[soundId]
	if existing then
		return existing
	end
	local pool: { Sound } = {}
	for _ = 1, MIN_VOICES do
		table.insert(pool, newVoice(soundId))
	end
	pools[soundId] = pool
	poolCursor[soundId] = 0
	pcall(function()
		ContentProvider:PreloadAsync(pool)
	end)
	return pool
end

local function acquireVoice(soundId: number): Sound
	local pool = ensurePool(soundId)
	local cursor = poolCursor[soundId] or 0
	for offset = 1, #pool do
		local index = (cursor + offset - 1) % #pool + 1
		if not pool[index].IsPlaying then
			poolCursor[soundId] = index
			return pool[index]
		end
	end
	if #pool < MAX_VOICES then
		local voice = newVoice(soundId)
		table.insert(pool, voice)
		poolCursor[soundId] = #pool
		return voice
	end
	local oldest = pool[1]
	for _, voice in pool do
		if voice.TimePosition > oldest.TimePosition then
			oldest = voice
		end
	end
	return oldest
end

local function jitteredGain(volume: number): number
	local db = (math.random() * 2 - 1) * GAIN_JITTER_DB
	return volume * 10 ^ (db / 20)
end

local function playPooled(soundId: number, volume: number, pitch: number)
	local sound = acquireVoice(soundId)
	sound.Volume = jitteredGain(volume)
	sound.PlaybackSpeed = pitch * (1 + (math.random() * 2 - 1) * PITCH_JITTER)
	sound.TimePosition = 0
	pcall(function()
		sound:Play()
	end)
end

local function playOneShot(soundId: number, volume: number, pitch: number)
	if soundId <= 0 or volume <= 0 then
		return
	end
	if onEngine() then
		AudioEngine.play({ id = soundId, class = "OwnGunshot", volume = volume, pitch = pitch })
		return
	end
	playPooled(soundId, volume, pitch)
end

local function weaponSoundId(key: string): number
	return (AssetIds.audio.weapons :: { [string]: number })[key] or 0
end

local function firstSoundId(keys: { string }): number
	for _, key in keys do
		local id = weaponSoundId(key)
		if id > 0 then
			return id
		end
	end
	return 0
end

function WeaponSfx.preload()
	local weapons = AssetIds.audio.weapons :: { [string]: number }
	if onEngine() then
		local assets: { string } = {}
		for _, id in weapons do
			if id > 0 then
				table.insert(assets, "rbxassetid://" .. tostring(id))
			end
		end
		if AssetIds.audio.range.gong > 0 then
			table.insert(assets, "rbxassetid://" .. tostring(AssetIds.audio.range.gong))
		end
		pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)
		return
	end
	for _, id in weapons do
		if id > 0 then
			ensurePool(id)
		end
	end
	if AssetIds.audio.range.gong > 0 then
		ensurePool(AssetIds.audio.range.gong)
	end
end

local function updateTail(): boolean
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local interior = root ~= nil and root:IsA("BasePart") and isInterior(root.Position)

	local reverbEffect = reverb
	if reverbEffect then
		reverbEffect.Enabled = interior
	end
	return interior
end

local lastVariation: { [string]: number } = {}

local function pickVariation(slot: string, keys: { string }): number
	local ids: { number } = {}
	for _, key in keys do
		local id = weaponSoundId(key)
		if id > 0 then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return 0
	end
	if #ids == 1 then
		return ids[1]
	end
	local previous = lastVariation[slot]
	local index = math.random(1, #ids)
	if ids[index] == previous then
		index = index % #ids + 1
	end
	lastVariation[slot] = ids[index]
	return ids[index]
end

local function shotSoundId(config: WeaponsConfig.WeaponConfig): number
	local id = pickVariation(config.id, config.closeSounds)
	return if id > 0 then id else weaponSoundId(config.shotSound)
end

local TAIL_COOLDOWN = 0.55
local lastTailAt = 0

local function tailFor(config: WeaponsConfig.WeaponConfig, environment: string): (number, number)
	local id, share = WeaponAudioMath.tailFor(environment, config.class, weaponSoundId)
	return id, config.shotVolume * share
end

local function legacyEnvironment(interior: boolean): string
	return if interior then "Interior" else "Open"
end

local function playTail(config: WeaponsConfig.WeaponConfig, environment: string)
	local now = os.clock()
	if now - lastTailAt < TAIL_COOLDOWN then
		return
	end
	lastTailAt = now
	local tailId, volume = tailFor(config, environment)
	playOneShot(tailId, volume, config.shotPitch)
end

local REFLECTION_INTERVAL = 0.09
local REFLECTION_VOLUME = 0.6
local lastOwnFanAt = -math.huge
local lastRemoteFanAt = -math.huge

local function fireFan(position: Vector3, id: number, config: WeaponsConfig.WeaponConfig)
	AudioReflections.fire(position, id, "weapons", config.shotVolume * REFLECTION_VOLUME, config.shotPitch, AudioEngine.reflectionRays())
end

local SUB_KEYS = { "gunshot_sub_01", "gunshot_sub_02" }
local SUB_VOLUME: { [string]: number } = { Pistol = 0.08, SMG = 0.1, Rifle = 0.15, Shotgun = 0.2 }

local LOW_AMMO_VOLUME = 0.22
local LAST_ROUND_VOLUME = 0.4

local function playLowAmmo(config: WeaponsConfig.WeaponConfig, remaining: number)
	if config.lowAmmo <= 0 or remaining > config.lowAmmo or remaining < 0 then
		return
	end
	local urgency = 1 - remaining / math.max(config.lowAmmo, 1)
	playOneShot(weaponSoundId("low_ammo_click"), LOW_AMMO_VOLUME * 10 ^ (3 * urgency / 20), 1 + 0.06 * urgency)
	if remaining == 0 and config.reloadStyle ~= "shell" then
		local keys = if config.class == "Pistol" then { "last_round", "bolt" } else { "last_round" }
		playOneShot(firstSoundId(keys), LAST_ROUND_VOLUME, if config.class == "Pistol" then 1.2 else 1)
	end
end

function WeaponSfx.playShot(weaponId: string, remaining: number?, muzzle: Vector3?)
	local config = WeaponsConfig.get(weaponId)
	if not config then
		return
	end
	local environment: string
	if onEngine() then
		environment = AudioEnvironment.environmentAt(AudioEngine.listenerPosition())
	else
		scanZones()
		environment = legacyEnvironment(updateTail())
	end

	local id = shotSoundId(config)
	playOneShot(id, config.shotVolume, config.shotPitch)
	local subVolume = SUB_VOLUME[config.class]
	if subVolume then
		playOneShot(weaponSoundId(SUB_KEYS[math.random(1, #SUB_KEYS)]), subVolume, 1)
	end
	playTail(config, environment)
	if remaining then
		playLowAmmo(config, remaining)
	end

	if onEngine() and muzzle and id > 0 then
		local allowed, at = WeaponAudioMath.gate(lastOwnFanAt, os.clock(), REFLECTION_INTERVAL)
		lastOwnFanAt = at
		if allowed then
			fireFan(muzzle, id, config)
		end
	end
end

function WeaponSfx.playDryfire()
	playOneShot(weaponSoundId("dryfire"), 0.45, 1)
end

type PhaseSound = { generic: { string }, volume: number, pitch: number? }

local PHASE_SOUNDS: { [string]: PhaseSound } = {
	MagOut = { generic = { "mag_out" }, volume = 0.5 },
	MagIn = { generic = { "mag_in" }, volume = 0.55 },
	BoltBack = { generic = { "bolt" }, volume = 0.45 },
	BoltForward = { generic = { "bolt" }, volume = 0.4, pitch = 1.08 },
	SlideBack = { generic = { "bolt" }, volume = 0.4, pitch = 1.05 },
	SlideRelease = { generic = { "bolt" }, volume = 0.45, pitch = 1.1 },
	ShellIn = { generic = { "mag_in" }, volume = 0.32, pitch = 1.3 },
	Draw = { generic = { "weapon_draw" }, volume = 0.4 },
	Holster = { generic = { "weapon_holster" }, volume = 0.35 },
}

local CLASS_PHASE_KEYS: { [string]: { [string]: string } } = {
	Pistol = {
		MagOut = "pistol_mag_out",
		MagIn = "pistol_mag_in",
		SlideBack = "pistol_slide_back",
		SlideRelease = "pistol_slide_release",
		BoltBack = "pistol_slide_back",
		BoltForward = "pistol_slide_release",
	},
	Rifle = {
		MagOut = "rifle_mag_out",
		MagIn = "rifle_mag_in",
		BoltBack = "rifle_bolt_back",
		BoltForward = "rifle_bolt_forward",
	},
	Shotgun = {
		MagOut = "",
		MagIn = "shotgun_shell_in",
		ShellIn = "shotgun_shell_in",
		BoltBack = "shotgun_pump_back",
		BoltForward = "shotgun_pump_forward",
	},
	SMG = {
		MagOut = "smg_mag_out",
		MagIn = "smg_mag_in",
		BoltBack = "smg_bolt",
		BoltForward = "smg_bolt",
	},
}

local CLASS_GENERIC_PITCH: { [string]: number } = {
	Pistol = 1.12,
	Rifle = 1,
	Shotgun = 0.82,
	SMG = 1.06,
}

local MAG_DROP_DELAY = 0.5

local function currentClass(): string?
	local weaponId = player:GetAttribute("WeaponId")
	local config = if typeof(weaponId) == "string" then WeaponsConfig.get(weaponId) else nil
	return if config then config.class else nil
end

function WeaponSfx.resolvePhase(phase: string, class: string?): (number, number, number)
	local entry = PHASE_SOUNDS[phase]
	if not entry then
		return 0, 0, 1
	end
	local classKeys = if class then CLASS_PHASE_KEYS[class] else nil
	local specific = classKeys and classKeys[phase]
	if specific == "" then
		return 0, 0, 1
	end
	local pitch = entry.pitch or 1
	local id = if specific then weaponSoundId(specific) else 0
	if id <= 0 then
		id = firstSoundId(entry.generic)
		pitch *= if class then CLASS_GENERIC_PITCH[class] or 1 else 1
	end
	return id, entry.volume, pitch
end

function WeaponSfx.playPhase(phase: string, class: string?, tag: string?)
	local id, volume, pitch = WeaponSfx.resolvePhase(phase, class or currentClass())
	if id <= 0 then
		return
	end
	playOneShot(id, volume, pitch)

	if phase == "MagOut" and tag == "empty" then
		task.delay(MAG_DROP_DELAY, function()
			playOneShot(weaponSoundId("mag_drop"), 0.3, 1)
		end)
	end
end

local CASING_VOICES = 12
local CASING_VOLUME = 0.32
local CASING_MIN_DISTANCE = 2
local CASING_MAX_DISTANCE = 45
local CASING_FULL_SPEED = 36

type CasingVoice = { attachment: Attachment, sound: Sound }
local casingVoices: { CasingVoice } = {}
local casingCursor = 0

local function ensureCasingVoices()
	if #casingVoices > 0 then
		return
	end
	local group = ensureGroup()
	for index = 1, CASING_VOICES do
		local attachment = Instance.new("Attachment")
		attachment.Name = "CasingVoice" .. index
		attachment.Parent = Workspace.Terrain
		local sound = Instance.new("Sound")
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = CASING_MIN_DISTANCE
		sound.RollOffMaxDistance = CASING_MAX_DISTANCE
		sound.SoundGroup = group
		sound.Parent = attachment
		table.insert(casingVoices, { attachment = attachment, sound = sound })
	end
end

type SurfaceProfile = { volume: number, pitch: number }
local SURFACE_HARD: SurfaceProfile = { volume = 0.85, pitch = 1 }
local SURFACE_METAL: SurfaceProfile = { volume = 1, pitch = 1.1 }
local SURFACE_WOOD: SurfaceProfile = { volume = 0.5, pitch = 0.8 }
local SURFACE_SOFT: SurfaceProfile = { volume = 0.06, pitch = 0.75 }
local SURFACE_DEFAULT: SurfaceProfile = { volume = 0.7, pitch = 0.95 }

local SURFACES: { [string]: SurfaceProfile } = {
	Metal = SURFACE_METAL,
	DiamondPlate = SURFACE_METAL,
	CorrodedMetal = SURFACE_METAL,
	Foil = SURFACE_METAL,
	Concrete = SURFACE_HARD,
	Asphalt = SURFACE_HARD,
	Brick = SURFACE_HARD,
	Cobblestone = SURFACE_HARD,
	Pavement = SURFACE_HARD,
	Slate = SURFACE_HARD,
	Granite = SURFACE_HARD,
	Marble = SURFACE_HARD,
	Basalt = SURFACE_HARD,
	Rock = SURFACE_HARD,
	Limestone = SURFACE_HARD,
	Sandstone = SURFACE_HARD,
	Glass = SURFACE_HARD,
	Ice = SURFACE_HARD,
	Plastic = SURFACE_HARD,
	SmoothPlastic = SURFACE_HARD,
	Wood = SURFACE_WOOD,
	WoodPlanks = SURFACE_WOOD,
	Cardboard = SURFACE_WOOD,
	Grass = SURFACE_SOFT,
	LeafyGrass = SURFACE_SOFT,
	Sand = SURFACE_SOFT,
	Mud = SURFACE_SOFT,
	Ground = SURFACE_SOFT,
	Snow = SURFACE_SOFT,
	Fabric = SURFACE_SOFT,
	Carpet = SURFACE_SOFT,
	Salt = SURFACE_SOFT,
	Water = SURFACE_SOFT,
}

local BRASS_KEYS = { "casing_brass_01", "casing_brass_02", "casing_brass_03" }
local HULL_KEYS = { "casing_shotgun_01", "casing_shotgun_02" }
local CASING_FALLBACK_KEYS = { "shell_01", "shell_02" }

function WeaponSfx.playCasingLand(position: Vector3, material: Enum.Material, caliber: string, impactSpeed: number)
	local engine = onEngine()
	if not engine then
		local camera = Workspace.CurrentCamera
		if camera and (camera.CFrame.Position - position).Magnitude > CASING_MAX_DISTANCE then
			return
		end
	end
	local surface = SURFACES[material.Name] or SURFACE_DEFAULT
	local speedFactor = math.clamp(impactSpeed / CASING_FULL_SPEED, 0.15, 1)
	local volume = CASING_VOLUME * surface.volume * speedFactor
	if volume < 0.005 then
		return
	end

	local hull = caliber == "12ga"
	local pitch = surface.pitch
	local soundId = pickVariation(if hull then "casing_hull" else "casing_brass", if hull then HULL_KEYS else BRASS_KEYS)
	if soundId <= 0 then
		soundId = pickVariation("casing_fallback", CASING_FALLBACK_KEYS)
		if hull then
			pitch *= 0.62
			volume *= 0.8
		end
	end
	if soundId <= 0 then
		return
	end

	if engine then
		AudioEngine.play({ id = soundId, class = "Casing", position = position, volume = volume, pitch = pitch })
		return
	end

	ensureCasingVoices()
	local voice: CasingVoice? = nil
	for offset = 1, #casingVoices do
		local index = (casingCursor + offset - 1) % #casingVoices + 1
		if not casingVoices[index].sound.IsPlaying then
			voice = casingVoices[index]
			casingCursor = index
			break
		end
	end
	if not voice then
		return
	end
	voice.attachment.WorldPosition = position
	local sound = voice.sound
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Volume = jitteredGain(volume)
	sound.PlaybackSpeed = pitch * (1 + (math.random() * 2 - 1) * PITCH_JITTER)
	sound.TimePosition = 0
	pcall(function()
		sound:Play()
	end)
end

local DISTANT_THRESHOLD = 40

local function anchorAt(position: Vector3, lifetime: number): BasePart
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = Workspace
	task.delay(lifetime, function()
		anchor:Destroy()
	end)
	return anchor
end

function WeaponSfx.playDistantShot(position: Vector3, weaponId: string)
	local config = WeaponsConfig.get(weaponId)
	if not config then
		return
	end
	if onEngine() then
		local id = shotSoundId(config)
		AudioEngine.play({
			layerIds = WeaponAudioMath.layerIds(id, weaponSoundId(config.midSound), weaponSoundId(config.farSound)),
			class = "GunshotRemote",
			position = position,
			volume = config.shotVolume,
			pitch = config.shotPitch,
		})
		local allowed, at = WeaponAudioMath.gate(lastRemoteFanAt, os.clock(), REFLECTION_INTERVAL)
		lastRemoteFanAt = at
		if allowed and id > 0 then
			fireFan(position, id, config)
		end
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local distance = if root and root:IsA("BasePart") then (root.Position - position).Magnitude else 0
	if distance < DISTANT_THRESHOLD then
		return
	end
	local anchor = anchorAt(position, 4)
	SfxPlayer.play3D(anchor, shotSoundId(config), config.shotVolume * 0.8, 30, 400, 0.06)
	scanZones()
	local tailId, tailVolume = tailFor(config, legacyEnvironment(isInterior(position)))
	SfxPlayer.play3D(anchor, tailId, tailVolume * 0.8, 30, 400, 0)
end

local GONG_VOLUME = 0.9

function WeaponSfx.playGong(position: Vector3)
	if onEngine() then
		AudioEngine.play({ id = AssetIds.audio.range.gong, class = "Impact", position = position, volume = GONG_VOLUME, range = 300, hold = 20, pitchJitter = 0.04 })
		return
	end
	local anchor = anchorAt(position, 5)
	SfxPlayer.play3D(anchor, AssetIds.audio.range.gong, GONG_VOLUME, 20, 300, 0.04)
end

local IMPACT_VOLUME = 0.7
local IMPACT_FLESH_VOLUME = 0.5
local IMPACT_VARIATIONS = 2
local IMPACTS_PER_VOLLEY = 2
local RICOCHET_CHANCE = 1 / 6
local RICOCHET_VOLUME = 0.5

export type Hit = { position: Vector3, normal: Vector3, material: string }

local IMPACT_PLACEHOLDERS: { [string]: () -> number } = {
	concrete = function()
		return AssetIds.audio.foley.land_hard
	end,
	metal = function()
		return AssetIds.audio.weapons.bolt
	end,
	wood = function()
		return AssetIds.audio.foley.land_soft
	end,
	dirt = function()
		return AssetIds.audio.foley.land_soft
	end,
	flesh = function()
		return pickVariation("impact_flesh_placeholder", { "bite_01", "bite_02", "bite_03" })
	end,
}

local function impactIdFor(family: string): (number, boolean)
	local id = pickVariation("impact_" .. family, WeaponAudioMath.impactKeys(family, IMPACT_VARIATIONS))
	if id > 0 then
		return id, false
	end
	local placeholder = IMPACT_PLACEHOLDERS[family]
	return if placeholder then placeholder() else 0, true
end

function WeaponSfx.playImpacts(hits: { Hit })
	if not onEngine() then
		return
	end
	local count = WeaponAudioMath.impactsToPlay(#hits, IMPACTS_PER_VOLLEY)
	for index = 1, count do
		local hit = hits[index]
		local family = WeaponAudioMath.impactFamily(hit.material)
		local id, placeholder = impactIdFor(family)
		if id <= 0 then
			continue
		end
		local volume = if family == "flesh" then IMPACT_FLESH_VOLUME else IMPACT_VOLUME
		if placeholder then
			volume *= 0.6
		end
		AudioEngine.play({ id = id, class = "Impact", position = hit.position, volume = volume })
		if (family == "concrete" or family == "metal") and math.random() < RICOCHET_CHANCE then
			AudioEngine.play({ id = weaponSoundId("ricochet_01"), class = "Impact", position = hit.position, volume = RICOCHET_VOLUME, delay = 0.02 })
		end
	end
end

return WeaponSfx
