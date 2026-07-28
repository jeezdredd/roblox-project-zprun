--!strict

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LightingConfig = require(ReplicatedStorage.Shared.config.LightingConfig)

local LightingDirector = {}

local PHASE_ATTRIBUTE = "FlowPhase"
local NIGHT_ATTRIBUTE = "NightMission"
local BIOME_ATTRIBUTE = "Biome"

local atmosphere: Atmosphere
local grading: ColorCorrectionEffect
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
		atmosphereHaze = approach(from.atmosphereHaze, to.atmosphereHaze, alpha),
		atmosphereGlare = approach(from.atmosphereGlare, to.atmosphereGlare, alpha),
		atmosphereColor = from.atmosphereColor:Lerp(to.atmosphereColor, alpha),
		atmosphereDecay = from.atmosphereDecay:Lerp(to.atmosphereDecay, alpha),
		gradingBrightness = approach(from.gradingBrightness, to.gradingBrightness, alpha),
		gradingContrast = approach(from.gradingContrast, to.gradingContrast, alpha),
		gradingSaturation = approach(from.gradingSaturation, to.gradingSaturation, alpha),
		gradingTint = from.gradingTint:Lerp(to.gradingTint, alpha),
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

	atmosphere.Density = preset.atmosphereDensity
	atmosphere.Haze = preset.atmosphereHaze
	atmosphere.Glare = preset.atmosphereGlare
	atmosphere.Color = preset.atmosphereColor
	atmosphere.Decay = preset.atmosphereDecay

	grading.Brightness = preset.gradingBrightness
	grading.Contrast = preset.gradingContrast
	grading.Saturation = preset.gradingSaturation
	grading.TintColor = preset.gradingTint
end

local function resolveTargetId(): string
	if Players.LocalPlayer:GetAttribute(PHASE_ATTRIBUTE) ~= "Mission" then
		return "Hub"
	end
	if Workspace:GetAttribute(NIGHT_ATTRIBUTE) == true then
		return "Night"
	end
	local biome = Workspace:GetAttribute(BIOME_ATTRIBUTE)
	if typeof(biome) == "string" then
		return biome
	end
	return "City"
end

local function refreshTarget()
	target = LightingConfig.get(resolveTargetId())
end

local function step(deltaTime: number)
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

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Name = "TFZ_SunRays"
	sunRays.Intensity = 0.08
	sunRays.Spread = 0.6
	sunRays.Parent = Lighting

	current = LightingConfig.get("Hub")
	target = current
	apply(current)

	Players.LocalPlayer:GetAttributeChangedSignal(PHASE_ATTRIBUTE):Connect(refreshTarget)
	Workspace:GetAttributeChangedSignal(NIGHT_ATTRIBUTE):Connect(refreshTarget)
	Workspace:GetAttributeChangedSignal(BIOME_ATTRIBUTE):Connect(refreshTarget)
	refreshTarget()

	RunService.Heartbeat:Connect(step)
end

return LightingDirector
