--!strict

-- Turns DressingPlanner placements into instances in a chunk: the PBR props through
-- WorldMeshes, a primitive stand-in per group when a mesh is not loaded, the burn
-- patches, and the tags the mobile tier and the counter read. Chunk-local coordinates,
-- parented under the chunk model so the props pool with it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DressingConfig = require(ReplicatedStorage.Shared.config.DressingConfig)
local WorldMeshConfig = require(ReplicatedStorage.Shared.config.WorldMeshConfig)
local DressingPlanner = require(ReplicatedStorage.Shared.world.DressingPlanner)
local MaterialUtil = require(ReplicatedStorage.Shared.util.MaterialUtil)
local ChunkOccupancy = require(script.Parent.Parent.systems.ChunkOccupancy)
local WorldMeshes = require(script.Parent.Parent.systems.WorldMeshes)

local WorldDressing = {}

local TAGS = DressingConfig.TAGS
local MESH_SINK = 0.15

local CONCRETE = Color3.fromRGB(160, 158, 150)
local SANDBAG = Color3.fromRGB(150, 134, 96)
local STEEL = Color3.fromRGB(70, 66, 62)
local RUBBER = Color3.fromRGB(28, 28, 30)
local BURNED = Color3.fromRGB(42, 38, 36)
local TRASH = Color3.fromRGB(34, 34, 38)
local CONE = Color3.fromRGB(226, 96, 40)
local SIGN_POST = Color3.fromRGB(96, 96, 100)
local SIGN_PANEL = Color3.fromRGB(190, 40, 34)
local CAR_PAINT = {
	Color3.fromRGB(110, 60, 52),
	Color3.fromRGB(74, 90, 108),
	Color3.fromRGB(96, 96, 100),
	Color3.fromRGB(134, 126, 112),
}

-- SurfaceAppearance tints per biome: the same maps read burnt and dusty in the ruins.
local TINTS: { [string]: { [string]: Color3 } } = {
	Wasteland = {
		car_burned = Color3.fromRGB(170, 158, 142),
		rubble = Color3.fromRGB(196, 186, 170),
		hedgehog = Color3.fromRGB(184, 170, 150),
	},
}

local function tag(instance: Instance, placement: DressingPlanner.Placement)
	CollectionService:AddTag(instance, TAGS.prop)
	if placement.detail then
		CollectionService:AddTag(instance, TAGS.detail)
	end
	if placement.shadow then
		CollectionService:AddTag(instance, TAGS.shadowNear)
	end
end

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, placement: DressingPlanner.Placement, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.CanCollide = placement.collide
	p.CanQuery = placement.collide
	p.CanTouch = false
	p.CastShadow = placement.shadow
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	tag(p, placement)
	return p
end

-- A box of the fallback size standing on the ground in the prop's own frame.
local function box(name: string, base: CFrame, size: { number }, color: Color3, material: Enum.Material, placement: DressingPlanner.Placement, parent: Instance): Part
	return part(name, Vector3.new(size[1], size[3], size[2]), base * CFrame.new(0, size[3] / 2, 0), color, material, placement, parent)
end

type Fallback = (base: CFrame, size: { number }, rng: Random, placement: DressingPlanner.Placement, parent: Instance) -> ()

local FALLBACKS: { [string]: Fallback } = {
	barrier = function(base, size, _, placement, parent)
		local p = box("Barrier", base, size, CONCRETE, Enum.Material.Concrete, placement, parent)
		MaterialUtil.apply(p, "TFZ_ConcreteDirty")
	end,
	sandbags = function(base, size, _, placement, parent)
		box("Sandbags", base, size, SANDBAG, Enum.Material.Fabric, placement, parent)
	end,
	hedgehog = function(base, size, _, placement, parent)
		local length = size[1]
		for _, angle in { 0, math.pi / 2 } do
			part("Hedgehog", Vector3.new(length, 0.5, 0.5), base * CFrame.new(0, size[3] / 2, 0) * CFrame.Angles(0, angle, math.rad(45)), STEEL, Enum.Material.CorrodedMetal, placement, parent)
		end
		part("Hedgehog", Vector3.new(0.5, length, 0.5), base * CFrame.new(0, size[3] / 2, 0) * CFrame.Angles(math.rad(35), 0, 0), STEEL, Enum.Material.CorrodedMetal, placement, parent)
	end,
	oil_barrel = function(base, size, _, placement, parent)
		local p = part("OilBarrel", Vector3.new(size[3], size[1], size[1]), base * CFrame.new(0, size[3] / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(64, 58, 52), Enum.Material.CorrodedMetal, placement, parent)
		p.Shape = Enum.PartType.Cylinder
	end,
	tyre = function(base, size, _, placement, parent)
		local p = part("Tyre", Vector3.new(size[3], size[1], size[1]), base * CFrame.new(0, size[3] / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), RUBBER, Enum.Material.SmoothPlastic, placement, parent)
		p.Shape = Enum.PartType.Cylinder
	end,
	trash = function(base, size, _, placement, parent)
		local p = part("TrashBag", Vector3.new(size[1], size[3], size[2]), base * CFrame.new(0, size[3] / 2, 0), TRASH, Enum.Material.SmoothPlastic, placement, parent)
		p.Shape = Enum.PartType.Ball
	end,
	rubble = function(base, size, rng, placement, parent)
		for _ = 1, 3 do
			local w = rng:NextNumber(2, size[1] * 0.45)
			local h = rng:NextNumber(0.8, size[3] * 0.6)
			part(
				"Rubble",
				Vector3.new(w, h, rng:NextNumber(2, size[2] * 0.4)),
				base * CFrame.new(rng:NextNumber(-size[1] * 0.25, size[1] * 0.25), h / 2, rng:NextNumber(-size[2] * 0.25, size[2] * 0.25)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, math.pi), rng:NextNumber(-0.2, 0.2)),
				Color3.fromRGB(126, 118, 106),
				Enum.Material.Concrete,
				placement,
				parent
			)
		end
	end,
	car_burned = function(base, size, _, placement, parent)
		box("CarBody", base, { size[1], size[2], size[3] * 0.5 }, BURNED, Enum.Material.CorrodedMetal, placement, parent)
		part("CarCabin", Vector3.new(size[1] * 0.85, size[3] * 0.4, size[2] * 0.4), base * CFrame.new(0, size[3] * 0.7, size[2] * 0.05), BURNED, Enum.Material.CorrodedMetal, placement, parent)
	end,
	car_abandoned = function(base, size, rng, placement, parent)
		local paint = CAR_PAINT[rng:NextInteger(1, #CAR_PAINT)]
		box("CarBody", base, { size[1], size[2], size[3] * 0.5 }, paint, Enum.Material.Metal, placement, parent)
		local cabin = part("CarCabin", Vector3.new(size[1] * 0.85, size[3] * 0.4, size[2] * 0.4), base * CFrame.new(0, size[3] * 0.7, size[2] * 0.05), Color3.fromRGB(35, 40, 50), Enum.Material.Glass, placement, parent)
		cabin.Transparency = 0.2
	end,
	truck_crashed = function(base, size, _, placement, parent)
		part("TruckCab", Vector3.new(size[1] * 0.9, size[3] * 0.55, size[2] * 0.25), base * CFrame.new(0, size[3] * 0.3, size[2] * 0.35), Color3.fromRGB(90, 110, 130), Enum.Material.Metal, placement, parent)
		part("TruckTrailer", Vector3.new(size[1], size[3] * 0.7, size[2] * 0.65), base * CFrame.new(0, size[3] * 0.45, -size[2] * 0.15), Color3.fromRGB(150, 150, 154), Enum.Material.Metal, placement, parent)
	end,
	cone = function(base, size, _, placement, parent)
		box("Cone", base, { size[1] * 0.5, size[2] * 0.5, size[3] }, CONE, Enum.Material.SmoothPlastic, placement, parent)
		box("ConeBase", base, { size[1], size[2], 0.15 }, CONE:Lerp(Color3.new(), 0.3), Enum.Material.SmoothPlastic, placement, parent)
	end,
	road_sign = function(base, size, _, placement, parent)
		box("SignPost", base, { 0.3, 0.3, size[3] * 0.72 }, SIGN_POST, Enum.Material.Metal, placement, parent)
		part("SignPanel", Vector3.new(size[1], size[1], 0.12), base * CFrame.new(0, size[3] - size[1] / 2, 0), SIGN_PANEL, Enum.Material.SmoothPlastic, placement, parent)
	end,
}

-- Sizes of every loaded prop the recipes can ask for, keyed by mesh name.
local function loadedSizes(): { [string]: DressingPlanner.Size }
	local sizes: { [string]: DressingPlanner.Size } = {}
	for _, recipe in DressingConfig.recipes do
		for _, member in recipe.members do
			for _, name in WorldMeshConfig.groups[member.group] or {} do
				if not sizes[name] then
					local natural = WorldMeshes.naturalSize(name)
					if natural then
						sizes[name] = { natural.X, natural.Z, natural.Y }
					end
				end
			end
		end
	end
	return sizes
end

local function placePatch(placement: DressingPlanner.Placement, rng: Random, parent: Instance)
	local name = placement.patch
	if not name then
		return
	end
	local width = rng:NextNumber(DressingConfig.PATCH_SIZE[1], DressingConfig.PATCH_SIZE[2])
	local p = Instance.new("Part")
	p.Name = "Patch"
	p.Size = Vector3.new(width, 0.08, width * rng:NextNumber(0.8, 1.2))
	p.CFrame = CFrame.new(placement.x, placement.y + 0.04, placement.z) * CFrame.Angles(0, placement.yaw + rng:NextNumber(-0.4, 0.4), 0)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Color = Color3.fromRGB(70, 64, 58)
	p.Material = Enum.Material.Ground
	if not MaterialUtil.apply(p, name) then
		-- the burn map is the point of the patch; a flat tint would only read as a stain
		p:Destroy()
		return
	end
	p.Parent = parent
	CollectionService:AddTag(p, TAGS.prop)
end

local function placeOne(biome: string, placement: DressingPlanner.Placement, rng: Random, parent: Instance)
	local base = CFrame.new(placement.x, placement.y, placement.z) * CFrame.Angles(0, placement.yaw, 0)
	local name = placement.name
	if name then
		local mesh = WorldMeshes.placeNatural(name, base, parent, { collide = placement.collide, shadow = placement.shadow, sink = MESH_SINK })
		if mesh then
			mesh.CanTouch = false
			local tints = TINTS[biome]
			local tint = tints and tints[placement.group]
			local surface = mesh:FindFirstChildOfClass("SurfaceAppearance")
			if tint and surface then
				surface.Color = tint
			end
			tag(mesh, placement)
			placePatch(placement, rng, parent)
			return
		end
	end
	local fallback = FALLBACKS[placement.group]
	if fallback then
		fallback(base, placement.size, rng, placement, parent)
		placePatch(placement, rng, parent)
	end
end

-- Dresses the chunk for `biome`; returns the number of props placed.
-- `density` (0..1, default 1) scales the clusters and the prop cap: a map transition
-- dresses a chunk with both locations at their shares of the blend.
function WorldDressing.dress(biome: string, rng: Random, halfLength: number, parent: Instance, density: number?): number
	local placements = DressingPlanner.plan(DressingConfig, biome, rng, ChunkOccupancy, {
		halfLength = halfLength,
		groups = WorldMeshConfig.groups,
		sizes = loadedSizes(),
		density = density,
	})
	for _, placement in placements do
		placeOne(biome, placement, rng, parent)
	end
	return #placements
end

return WorldDressing
