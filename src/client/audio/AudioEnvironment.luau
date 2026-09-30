--!strict

-- Where a sound is: the AcousticSpace zones, the biome and the flow phase resolve into
-- an environment id (Hangar, Interior, Street, Forest, Open); the material table gives
-- the loss and cutoff of whatever blocks a path; and the occlusion raycasts run inside
-- a per-frame budget so a full zombie wave never spends more than a handful of rays.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SpatialAudioConfig = require(ReplicatedStorage.Shared.config.SpatialAudioConfig)

local AudioEnvironment = {}

local ZONE_ATTRIBUTE = "AcousticSpace"
local HANGAR_ZONE = "HangarInteriorZone"
local PHASE_ATTRIBUTE = "FlowPhase"
local BIOME_ATTRIBUTE = "Biome"
-- parts that sound passes through freely (tag them in the world builders)
local TRANSPARENT_TAG = "AudioTransparent"
-- a ray stops this short of the source so the source's own part never occludes it
local SOURCE_CLEARANCE = 2.5
local EXCLUDE_REFRESH = 0.5

local FOREST_BIOMES = { Forest = true, Cornfield = true }
local STREET_BIOMES = { City = true }

local zones: { BasePart } = {}
local rayParams = RaycastParams.new()
local rayBudget = 0
local raysUsed = 0
local excludeRefreshAt = 0
local started = false

local function addZone(instance: Instance)
	if instance:IsA("BasePart") and instance:GetAttribute(ZONE_ATTRIBUTE) ~= nil then
		table.insert(zones, instance)
	end
end

local function refreshExcludes()
	local list: { Instance } = {}
	local camera = Workspace.CurrentCamera
	if camera then
		table.insert(list, camera)
	end
	local zombies = Workspace:FindFirstChild("Zombies")
	if zombies then
		table.insert(list, zombies)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, tagged in CollectionService:GetTagged(TRANSPARENT_TAG) do
		table.insert(list, tagged)
	end
	rayParams.FilterDescendantsInstances = list
end

function AudioEnvironment.init()
	if started then
		return
	end
	started = true
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = false
	rayParams.IgnoreWater = true
	for _, descendant in Workspace:GetDescendants() do
		addZone(descendant)
	end
	Workspace.DescendantAdded:Connect(addZone)
	refreshExcludes()
end

-- The most recently added zone containing the point, pruning zones that left the
-- world on the way.
function AudioEnvironment.zoneAt(position: Vector3): BasePart?
	for index = #zones, 1, -1 do
		local zone = zones[index]
		if not zone.Parent then
			table.remove(zones, index)
		else
			local localPoint = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z then
				return zone
			end
		end
	end
	return nil
end

function AudioEnvironment.inMission(): boolean
	return Players.LocalPlayer:GetAttribute(PHASE_ATTRIBUTE) == "Mission"
end

function AudioEnvironment.environmentAt(position: Vector3): string
	local zone = AudioEnvironment.zoneAt(position)
	if zone then
		return if zone.Name == HANGAR_ZONE then "Hangar" else "Interior"
	end
	if AudioEnvironment.inMission() then
		local biome = Workspace:GetAttribute(BIOME_ATTRIBUTE)
		if typeof(biome) == "string" then
			if STREET_BIOMES[biome] then
				return "Street"
			elseif FOREST_BIOMES[biome] then
				return "Forest"
			end
		end
	end
	return "Open"
end

function AudioEnvironment.material(material: Enum.Material): SpatialAudioConfig.MaterialSpec
	return SpatialAudioConfig.material(material.Name)
end

function AudioEnvironment.beginFrame(budget: number, now: number)
	rayBudget = budget
	raysUsed = 0
	if now >= excludeRefreshAt then
		excludeRefreshAt = now + EXCLUDE_REFRESH
		refreshExcludes()
	end
end

function AudioEnvironment.raysUsed(): number
	return raysUsed
end

function AudioEnvironment.raysLeft(): number
	return rayBudget - raysUsed
end

-- A raycast outside the per-frame budget (reflection fans pay their own cap).
function AudioEnvironment.cast(origin: Vector3, direction: Vector3): RaycastResult?
	return Workspace:Raycast(origin, direction, rayParams)
end

-- Blocked fraction (0 open .. 1 blocked) of the listener-to-source path plus the material
-- of the first blocking part, or nil when this frame's ray budget is spent. `rays` is 1
-- or 2; the second ray runs parallel, offset sideways, so an edge reads as half blocked.
function AudioEnvironment.occlusion(listener: Vector3, source: Vector3, rays: number): (number?, SpatialAudioConfig.MaterialSpec?)
	if raysUsed + rays > rayBudget then
		return nil, nil
	end
	local offset = source - listener
	local distance = offset.Magnitude
	local length = distance - SOURCE_CLEARANCE
	if length <= 0 then
		return 0, nil
	end
	local direction = offset.Unit * length
	raysUsed += rays
	local hits = 0
	local material: SpatialAudioConfig.MaterialSpec? = nil
	local first = Workspace:Raycast(listener, direction, rayParams)
	if first then
		hits += 1
		material = SpatialAudioConfig.material(first.Material.Name)
	end
	if rays >= 2 then
		local side = Vector3.new(-offset.Z, 0, offset.X)
		if side.Magnitude > 1e-3 then
			local second = Workspace:Raycast(listener + side.Unit * SpatialAudioConfig.OCCLUSION.edgeOffset, direction, rayParams)
			if second then
				hits += 1
				if not material then
					material = SpatialAudioConfig.material(second.Material.Name)
				end
			end
		else
			hits *= 2
		end
		if hits == 1 then
			return SpatialAudioConfig.OCCLUSION.partialBlock, material
		end
		return if hits >= 2 then 1 else 0, material
	end
	return if hits > 0 then 1 else 0, material
end

return AudioEnvironment
