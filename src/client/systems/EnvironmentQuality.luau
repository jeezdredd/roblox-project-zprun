--!strict

-- The client side of the per-chunk budgets. The server builds one world to the desktop
-- budget and tags what the mobile tier can lose (DressingConfig.TAGS): on a touch-only
-- device the tagged clutter and decal cards are removed locally and the near-band
-- shadow casters stop casting, on streamed-in chunks too. In Studio it also prints the
-- real scene triangle and draw-call counts when the biome changes, so the server's
-- per-chunk estimate can be compared with a measurement.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DressingConfig = require(ReplicatedStorage.Shared.config.DressingConfig)

local EnvironmentQuality = {}

local TAGS = DressingConfig.TAGS
-- the scene needs a moment to stream the new biome in before its count means anything
local MEASURE_DELAY = 3

local started = false

function EnvironmentQuality.isMobile(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end

local function strip(instance: Instance)
	instance:Destroy()
end

local function unshadow(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CastShadow = false
	end
end

local function applyMobileTier()
	for _, item in CollectionService:GetTagged(TAGS.detail) do
		strip(item)
	end
	CollectionService:GetInstanceAddedSignal(TAGS.detail):Connect(strip)
	for _, item in CollectionService:GetTagged(TAGS.shadowNear) do
		unshadow(item)
	end
	CollectionService:GetInstanceAddedSignal(TAGS.shadowNear):Connect(unshadow)
end

local function measure()
	local biome = Workspace:GetAttribute("Biome")
	print(string.format(
		"[Scene %s] tris %d drawcalls %d instances %d",
		if typeof(biome) == "string" then biome else "?",
		Stats.SceneTriangleCount,
		Stats.SceneDrawcallCount,
		Stats.InstanceCount
	))
end

function EnvironmentQuality.init()
	if started then
		return
	end
	started = true

	if EnvironmentQuality.isMobile() then
		applyMobileTier()
	end

	if RunService:IsStudio() then
		Workspace:GetAttributeChangedSignal("Biome"):Connect(function()
			task.delay(MEASURE_DELAY, measure)
		end)
	end
end

return EnvironmentQuality
