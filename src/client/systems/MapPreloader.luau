--!strict

-- Client half of the map preload (wiki: Map Segments): while the squad runs a map the
-- server names both fork options in the MapPreload Workspace attribute (MapPreload);
-- this asks ContentProvider for their meshes, textures, prop surfaces and material
-- variants, so whichever option the vote picks draws at full resolution the moment it
-- streams in. The boot screen preloads everything once (Boot.client); this keeps the
-- next map's assets warm after a long run has pushed them out. Each asset is asked for
-- once per session.

local ContentProvider = game:GetService("ContentProvider")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DressingConfig = require(ReplicatedStorage.Shared.config.DressingConfig)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local MapsConfig = require(ReplicatedStorage.Shared.config.MapsConfig)
local WorldMeshConfig = require(ReplicatedStorage.Shared.config.WorldMeshConfig)

local MapPreloader = {}

local ATTRIBUTE = "MapPreload"

local asked: { [any]: boolean } = {}
local started = false

local function addId(list: { any }, id: number?)
	if typeof(id) == "number" and id > 0 then
		local content = "rbxassetid://" .. tostring(id)
		if not asked[content] then
			asked[content] = true
			table.insert(list, content)
		end
	end
end

local function addInstance(list: { any }, instance: Instance?)
	if instance and not asked[instance] then
		asked[instance] = true
		table.insert(list, instance)
	end
end

-- Everything one map draws with that is worth asking for ahead.
function MapPreloader.assetsFor(mapId: string): { any }
	local list: { any } = {}
	local map = MapsConfig.get(mapId)
	if not map then
		return list
	end
	local surfaces = ReplicatedStorage:FindFirstChild("PropSurfaces")
	for _, group in map.preloadGroups do
		for _, name in WorldMeshConfig.groups[group] or {} do
			local entry = WorldMeshConfig.meshes[name]
			if entry then
				addId(list, entry.mesh)
				addId(list, entry.texture)
				if entry.surface and surfaces then
					addInstance(list, surfaces:FindFirstChild(entry.surface))
				end
			end
		end
	end
	for _, locationId in map.locationIds do
		local location = LocationsConfig.get(locationId)
		if location then
			addId(list, location.floorTextureId)
			addId(list, location.apronTextureId)
		end
		for _, variant in (DressingConfig.materials :: any)[locationId] or {} do
			if typeof(variant) == "string" then
				addInstance(list, MaterialService:FindFirstChild(variant))
			end
		end
	end
	return list
end

local function onChanged()
	local value = Workspace:GetAttribute(ATTRIBUTE)
	if typeof(value) ~= "string" or value == "" then
		return
	end
	local list: { any } = {}
	for mapId in string.gmatch(value, "[^,]+") do
		for _, item in MapPreloader.assetsFor(mapId) do
			table.insert(list, item)
		end
	end
	if #list == 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

function MapPreloader.init()
	if started then
		return
	end
	started = true
	Workspace:GetAttributeChangedSignal(ATTRIBUTE):Connect(onChanged)
	onChanged()
end

return MapPreloader
