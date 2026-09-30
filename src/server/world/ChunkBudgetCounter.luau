--!strict

-- Studio-only cost line per built chunk (parts, estimated triangles, instances, decals,
-- lights, shadow casters against the desktop and mobile budgets), plus the fog check
-- that ties every preset's visibility to the spawn distance. Outside Studio nothing
-- here runs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DressingConfig = require(ReplicatedStorage.Shared.config.DressingConfig)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local VisibilityConfig = require(ReplicatedStorage.Shared.config.VisibilityConfig)
local ChunkBudget = require(ReplicatedStorage.Shared.world.ChunkBudget)
local FogBudget = require(ReplicatedStorage.Shared.world.FogBudget)

local ChunkBudgetCounter = {}

local LINE_ATTRIBUTE = "BudgetLine"

local function shapeName(part: Part): string
	if part.Shape == Enum.PartType.Ball then
		return "Ball"
	elseif part.Shape == Enum.PartType.Cylinder then
		return "Cylinder"
	end
	return "Block"
end

function ChunkBudgetCounter.count(model: Instance): ChunkBudget.Counts
	local counts = ChunkBudget.newCounts()
	for _, item in model:GetDescendants() do
		counts.instances += 1
		if item:IsA("MeshPart") then
			counts.parts += 1
			counts.meshes[item.Name] = (counts.meshes[item.Name] or 0) + 1
		elseif item:IsA("WedgePart") then
			counts.parts += 1
			counts.primitives.Wedge = (counts.primitives.Wedge or 0) + 1
		elseif item:IsA("Part") then
			counts.parts += 1
			local shape = shapeName(item)
			counts.primitives[shape] = (counts.primitives[shape] or 0) + 1
		elseif item:IsA("Decal") or item:IsA("Texture") then
			counts.decals += 1
		elseif item:IsA("Light") then
			counts.lights += 1
		end
		if item:IsA("BasePart") and item.CastShadow and item.Transparency < 1 then
			counts.shadows += 1
		end
	end
	return counts
end

-- Prints the chunk's line and stores it on the model; returns it, or nil outside Studio.
function ChunkBudgetCounter.report(model: Model, biome: string): string?
	if not RunService:IsStudio() then
		return nil
	end
	local report = ChunkBudget.report(DressingConfig, ChunkBudgetCounter.count(model))
	local line = ChunkBudget.format(biome, report, DressingConfig.budgets.desktop, DressingConfig.budgets.mobile)
	model:SetAttribute(LINE_ATTRIBUTE, line)
	print(line)
	return line
end

-- Warns once about any preset whose fog would show a chunk being spawned.
function ChunkBudgetCounter.checkFog()
	if not RunService:IsStudio() then
		return
	end
	local issues = FogBudget.checkAll(VisibilityConfig.visibility, VisibilityConfig.exempt, {
		spawnAhead = GameConstants.SPAWN_AHEAD_DISTANCE,
		chunkLength = GameConstants.CHUNK_LENGTH,
		streamingRadius = VisibilityConfig.STREAMING_TARGET_RADIUS,
		streamingMargin = VisibilityConfig.STREAMING_MARGIN,
	})
	for _, issue in issues do
		warn("[TaskForceZ] fog budget: " .. issue)
	end
end

return ChunkBudgetCounter
