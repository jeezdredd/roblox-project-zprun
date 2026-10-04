--!strict

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LightingConfig = require(ReplicatedStorage.Shared.config.LightingConfig)
local MapsConfig = require(ReplicatedStorage.Shared.config.MapsConfig)
local MapMath = require(ReplicatedStorage.Shared.world.MapMath)

local LightingDirector = {}

local PHASE_ATTRIBUTE = "FlowPhase"
local NIGHT_ATTRIBUTE = "NightMission"
local BIOME_ATTRIBUTE = "Biome"
-- the map at the lead runner and the boundary zone being crossed (ChunkSpawner): over
-- the zone the preset is the two maps' presets blended by where this player is, so the
-- light changes across the transition chunks instead of at the boundary
local MAP_ATTRIBUTE = "Map"
local BLEND_ATTRIBUTES = { "MapBlendFrom", "MapBlendTo", "MapBlendStart", "MapBlendEnd" }
-- Studio QA: a preset id forced from the command bar or the biome strip (nil releases it)
local DEV_PRESET_ATTRIBUTE = "DevLightingPreset"

local atmosphere: Atmosphere
local grading: ColorCorrectionEffect
local sunRays: SunRaysEffect
local current: LightingConfig.LightingPreset
local target: LightingConfig.LightingPreset
local started = false

local function approach(value: number, goal: number, alpha: number): number
	return value + (goal - value) * alpha
end

local function blend(from: LightingConfig.LightingPreset, to: LightingConfig.LightingPreset, alpha: number): LightingConfig.LightingPreset
	return {
		clockTime = approach(from.clockTime, to.clockTime, alpha),
		brightness = approach(from.brightness, to.brightness, alpha),
		ambient = from.ambient:Lerp(to.ambient, alpha),
		outdoorAmbient = from.outdoorAmbient:Lerp(to.outdoorAmbient, alpha),
		fogColor = from.fogColor:Lerp(to.fogColor, alpha),
		fogStart = approach(from.fogStart, to.fogStart, alpha),
		fogEnd = approach(from.fogEnd, to.fogEnd, alpha),
		atmosphereDensity = approach(from.atmosphereDensity, to.atmosphereDensity, alpha),
		atmosphereOffset = approach(from.atmosphereOffset, to.atmosphereOffset, alpha),
		atmosphereHaze = approach(from.atmosphereHaze, to.atmosphereHaze, alpha),
		atmosphereGlare = approach(from.atmosphereGlare, to.atmosphereGlare, alpha),
		atmosphereColor = from.atmosphereColor:Lerp(to.atmosphereColor, alpha),
		atmosphereDecay = from.atmosphereDecay:Lerp(to.atmosphereDecay, alpha),
		gradingBrightness = approach(from.gradingBrightness, to.gradingBrightness, alpha),
		gradingContrast = approach(from.gradingContrast, to.gradingContrast, alpha),
		gradingSaturation = approach(from.gradingSaturation, to.gradingSaturation, alpha),
		gradingTint = from.gradingTint:Lerp(to.gradingTint, alpha),
		bloomIntensity = approach(from.bloomIntensity, to.bloomIntensity, alpha),
		bloomThreshold = approach(from.bloomThreshold, to.bloomThreshold, alpha),
		sunRays = approach(from.sunRays, to.sunRays, alpha),
		shadowSoftness = approach(from.shadowSoftness, to.shadowSoftness, alpha),
	}
end

local function apply(preset: LightingConfig.LightingPreset)
	Lighting.ClockTime = preset.clockTime
	Lighting.Brightness = preset.brightness
	Lighting.Ambient = preset.ambient
	Lighting.OutdoorAmbient = preset.outdoorAmbient
	Lighting.FogColor = preset.fogColor
	Lighting.FogStart = preset.fogStart
	Lighting.FogEnd = preset.fogEnd
	Lighting.ShadowSoftness = preset.shadowSoftness

	atmosphere.Density = preset.atmosphereDensity
	atmosphere.Offset = preset.atmosphereOffset
	atmosphere.Haze = preset.atmosphereHaze
	atmosphere.Glare = preset.atmosphereGlare
	atmosphere.Color = preset.atmosphereColor
	atmosphere.Decay = preset.atmosphereDecay

	grading.Brightness = preset.gradingBrightness
	grading.Contrast = preset.gradingContrast
	grading.Saturation = preset.gradingSaturation
	grading.TintColor = preset.gradingTint

	sunRays.Intensity = preset.sunRays
end

local function resolveTargetId(): string
	if RunService:IsStudio() then
		local forced = Workspace:GetAttribute(DEV_PRESET_ATTRIBUTE)
		if typeof(forced) == "string" and LightingConfig.presets[forced] then
			return forced
		end
	end
	if Players.LocalPlayer:GetAttribute(PHASE_ATTRIBUTE) ~= "Mission" then
		return "Hub"
	end
	if Workspace:GetAttribute("SandboxActive") == true then
		return "Sandbox"
	end
	local map = Workspace:GetAttribute(MAP_ATTRIBUTE)
	local config = if typeof(map) == "string" then MapsConfig.get(map) else nil
	local biome = Workspace:GetAttribute(BIOME_ATTRIBUTE)
	local presetId = if config then config.lighting elseif typeof(biome) == "string" then biome else "City"
	if Workspace:GetAttribute(NIGHT_ATTRIBUTE) == true then
		return LightingConfig.nightFor(presetId)
	end
	return presetId
end

local function presetForMap(mapId: string): LightingConfig.LightingPreset?
	local config = MapsConfig.get(mapId)
	if not config then
		return nil
	end
	local id = config.lighting
	if Workspace:GetAttribute(NIGHT_ATTRIBUTE) == true then
		id = LightingConfig.nightFor(id)
	end
	return LightingConfig.get(id)
end

-- Over a map boundary zone: the two maps' presets blended by this player's place in
-- the zone; nil outside one (or with a preset forced in Studio).
local function zoneTarget(): LightingConfig.LightingPreset?
	if RunService:IsStudio() and Workspace:GetAttribute(DEV_PRESET_ATTRIBUTE) ~= nil then
		return nil
	end
	if Players.LocalPlayer:GetAttribute(PHASE_ATTRIBUTE) ~= "Mission" then
		return nil
	end
	local fromId = Workspace:GetAttribute(BLEND_ATTRIBUTES[1])
	local toId = Workspace:GetAttribute(BLEND_ATTRIBUTES[2])
	local start = Workspace:GetAttribute(BLEND_ATTRIBUTES[3])
	local finish = Workspace:GetAttribute(BLEND_ATTRIBUTES[4])
	if typeof(fromId) ~= "string" or typeof(toId) ~= "string" or typeof(start) ~= "number" or typeof(finish) ~= "number" then
		return nil
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local from = presetForMap(fromId)
	local to = presetForMap(toId)
	if not from or not to then
		return nil
	end
	local distance = (root.Position - GameConstants.RUN_ORIGIN):Dot(GameConstants.RUN_DIRECTION)
	return blend(from, to, MapMath.zoneAlpha(distance, start, finish))
end

local function refreshTarget()
	target = LightingConfig.get(resolveTargetId())
end

local function snapToTarget()
	refreshTarget()
	current = target
	apply(current)
end

local function step(deltaTime: number)
	local zone = zoneTarget()
	if zone then
		target = zone
	end
	local alpha = 1 - math.exp(-LightingConfig.LERP_SPEED * deltaTime)
	current = blend(current, target, alpha)
	apply(current)
end

function LightingDirector.init()
	if started or not LightingConfig.ENABLED then
		return
	end
	started = true

	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Name = "TFZ_Atmosphere"
	atmosphere.Parent = Lighting

	grading = Instance.new("ColorCorrectionEffect")
	grading.Name = "TFZ_Grading"
	grading.Enabled = true
	grading.Parent = Lighting

	sunRays = Instance.new("SunRaysEffect")
	sunRays.Name = "TFZ_SunRays"
	sunRays.Spread = 0.6
	sunRays.Parent = Lighting

	current = LightingConfig.get("Hub")
	target = current
	apply(current)

	Players.LocalPlayer:GetAttributeChangedSignal(PHASE_ATTRIBUTE):Connect(function()
		if Players.LocalPlayer:GetAttribute(PHASE_ATTRIBUTE) == "Mission" then
			snapToTarget()
		else
			refreshTarget()
		end
	end)
	Workspace:GetAttributeChangedSignal(NIGHT_ATTRIBUTE):Connect(refreshTarget)
	Workspace:GetAttributeChangedSignal(BIOME_ATTRIBUTE):Connect(refreshTarget)
	Workspace:GetAttributeChangedSignal(MAP_ATTRIBUTE):Connect(refreshTarget)
	-- leaving a zone hands the target back to the map's own preset
	Workspace:GetAttributeChangedSignal(BLEND_ATTRIBUTES[1]):Connect(refreshTarget)
	Workspace:GetAttributeChangedSignal("SandboxActive"):Connect(snapToTarget)
	if RunService:IsStudio() then
		Workspace:GetAttributeChangedSignal(DEV_PRESET_ATTRIBUTE):Connect(refreshTarget)
	end
	refreshTarget()

	RunService.Heartbeat:Connect(step)
end

-- The preset on screen right now (mid-lerp values included), for PostFx.
function LightingDirector.getCurrent(): LightingConfig.LightingPreset
	return current or LightingConfig.get("Hub")
end

return LightingDirector
