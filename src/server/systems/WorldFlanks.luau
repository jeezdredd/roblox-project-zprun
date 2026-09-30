--!strict

-- Fills the space beside the run corridor, per biome.
--
-- The corridor is only +-PLAYABLE_HALF_WIDTH wide, but the floor and aprons run out to
-- about +-230 studs and all of it is in view. Before this layer everything past the
-- corridor edge was bare floor with a few isolated props, so every biome read as a
-- strip of clutter on an empty slab floating in fog. The flanks are built in depth
-- bands: a detailed near band that frames the corridor, a cheaper middle band, and a
-- silhouette band at the back that reads through fog and closes the horizon.
--
-- Everything here is decoration: no collision, no queries, no touch events, and
-- shadows only on the near band. Runners are clamped to the corridor, so none of it
-- is reachable. Coordinates are chunk-local (the chunk pivot is its centre).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DressingConfig = require(ReplicatedStorage.Shared.config.DressingConfig)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local MaterialUtil = require(ReplicatedStorage.Shared.util.MaterialUtil)
local WorldMeshes = require(script.Parent.WorldMeshes)
local ChunkOccupancy = require(script.Parent.ChunkOccupancy)

local WorldFlanks = {}

-- material variants per biome (docs/world/environment.md, section 5.2)
local MATERIALS = DressingConfig.materials

local HALF = GameConstants.CHUNK_LENGTH / 2
local EDGE = GameConstants.PLAYABLE_HALF_WIDTH + 4
local WORLD_EDGE = GameConstants.LANE_WIDTH / 2 + GameConstants.BARRIER_THICKNESS + GameConstants.APRON_WIDTH - 4
local FLOOR = 0.5

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance, shadow: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = shadow == true
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ball(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance, shadow: boolean?): Part
	local p = part(name, size, cframe, color, material, parent, shadow)
	p.Shape = Enum.PartType.Ball
	return p
end

local function wedge(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cframe
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.CastShadow = false
	w.Color = color
	w.Material = material
	w.Parent = parent
	return w
end

local function jitter(color: Color3, rng: Random, amount: number): Color3
	local d = rng:NextNumber(-amount, amount)
	return Color3.new(math.clamp(color.R + d, 0, 1), math.clamp(color.G + d, 0, 1), math.clamp(color.B + d, 0, 1))
end

-- Walks z across the chunk in steps, calling place(zStart, span) for each slot.
local function fillZ(rng: Random, minSpan: number, maxSpan: number, gap: { number }, place: (number, number) -> ())
	local z = -HALF
	while z < HALF - 2 do
		local span = math.min(rng:NextNumber(minSpan, maxSpan), HALF - z)
		if span < minSpan * 0.5 then
			break
		end
		place(z, span)
		-- gaps may be negative (overlapping masses), but z must always advance
		z += math.max(span + rng:NextNumber(gap[1], gap[2]), minSpan * 0.5)
	end
end

---------------------------------------------------------------------------------------
-- City

local FACADES = {
	{ Color3.fromRGB(150, 84, 64), Enum.Material.Brick },
	{ Color3.fromRGB(122, 70, 56), Enum.Material.Brick },
	{ Color3.fromRGB(176, 166, 146), Enum.Material.Concrete },
	{ Color3.fromRGB(128, 128, 130), Enum.Material.Concrete },
	{ Color3.fromRGB(196, 180, 140), Enum.Material.Plaster },
	{ Color3.fromRGB(96, 92, 88), Enum.Material.Concrete },
}

local WINDOW_DARK = Color3.fromRGB(26, 30, 38)
local WINDOW_LIT = Color3.fromRGB(255, 206, 132)

-- A city block facade seen from the corridor: body, a floor ledge per storey, a dark
-- window strip per storey with the odd lit one, a shopfront band and a cornice. The
-- facade faces the corridor (towards x = 0), which is the -sign direction.
local function facadeBuilding(sign: number, xNear: number, depth: number, z: number, width: number, height: number, rng: Random, parent: Instance, detail: boolean)
	local style = FACADES[rng:NextInteger(1, #FACADES)]
	local color = jitter(style[1], rng, 0.04)
	local cx = sign * (xNear + depth / 2)
	local cz = z + width / 2
	local block = part("Block", Vector3.new(depth, height, width), CFrame.new(cx, FLOOR + height / 2, cz), color, style[2], parent, detail)
	local facadeVariant = MATERIALS.City.facade
	if facadeVariant and style[2] == Enum.Material.Brick and rng:NextNumber() < (MATERIALS.City.facadeShare or 0) then
		-- peeling plaster over brick; the map carries the colour, so the tint goes neutral
		block.Color = Color3.fromRGB(204, 194, 180)
		MaterialUtil.apply(block, facadeVariant)
	end

	local faceX = sign * xNear - sign * 0.15
	local roofColor = color:Lerp(Color3.new(), 0.45)
	part("Cornice", Vector3.new(1.4, 1.2, width + 0.6), CFrame.new(faceX - sign * 0.2, FLOOR + height - 0.6, cz), roofColor, Enum.Material.Concrete, parent)
	part("Roof", Vector3.new(depth, 0.6, width), CFrame.new(cx, FLOOR + height + 0.3, cz), roofColor, Enum.Material.Concrete, parent)

	if not detail then
		-- middle band: a few lit windows so the depth reads at night, nothing else
		for _ = 1, rng:NextInteger(0, 3) do
			local y = FLOOR + rng:NextNumber(8, height - 4)
			local w = part("LitWindow", Vector3.new(0.2, 2.2, rng:NextNumber(2, 4)), CFrame.new(faceX, y, z + rng:NextNumber(3, width - 3)), WINDOW_LIT, Enum.Material.Neon, parent)
			w.Transparency = 0.35
		end
		return
	end

	-- shopfront: darker base band with glazing
	part("Shopfront", Vector3.new(0.3, 5, width - 1), CFrame.new(faceX, FLOOR + 2.6, cz), color:Lerp(Color3.new(), 0.55), Enum.Material.Concrete, parent)
	local glass = part("ShopGlass", Vector3.new(0.35, 3.4, width - 4), CFrame.new(faceX - sign * 0.05, FLOOR + 2.8, cz), WINDOW_DARK, Enum.Material.Glass, parent)
	glass.Transparency = 0.15
	if rng:NextNumber() < 0.5 then
		part("Awning", Vector3.new(2.6, 0.3, width * rng:NextNumber(0.4, 0.8)), CFrame.new(faceX - sign * 1.3, FLOOR + 5.4, cz) * CFrame.Angles(0, 0, sign * 0.25), jitter(Color3.fromRGB(90, 40, 36), rng, 0.08), Enum.Material.Fabric, parent)
	end

	-- storeys
	local storey = 9
	local floors = math.floor((height - 8) / storey)
	for f = 1, math.min(floors, 7) do
		local y = FLOOR + 6 + (f - 1) * storey
		part("Ledge", Vector3.new(0.6, 0.4, width), CFrame.new(faceX - sign * 0.15, y, cz), color:Lerp(Color3.new(1, 1, 1), 0.15), Enum.Material.Concrete, parent)
		local lit = rng:NextNumber() < 0.18
		local strip = part("Windows", Vector3.new(0.25, 3.2, width - 3), CFrame.new(faceX, y + 4.2, cz), if lit then WINDOW_LIT else WINDOW_DARK, if lit then Enum.Material.Neon else Enum.Material.Glass, parent)
		strip.Transparency = if lit then 0.4 else 0.05
		-- piers break the strip into windows
		local piers = math.max(1, math.floor(width / 6))
		for i = 1, piers - 1 do
			part("Pier", Vector3.new(0.4, 3.4, 0.9), CFrame.new(faceX - sign * 0.1, y + 4.2, z + 1.5 + i * (width - 3) / piers), color, style[2], parent)
		end
	end

	-- rooftop clutter
	if rng:NextNumber() < 0.6 then
		part("RoofUnit", Vector3.new(rng:NextNumber(3, 6), rng:NextNumber(2, 4), rng:NextNumber(3, 6)), CFrame.new(cx + rng:NextNumber(-depth / 4, depth / 4), FLOOR + height + 2, cz + rng:NextNumber(-width / 4, width / 4)), Color3.fromRGB(110, 112, 116), Enum.Material.DiamondPlate, parent)
	end
	if rng:NextNumber() < 0.3 then
		local tank = part("WaterTank", Vector3.new(5, 6, 5), CFrame.new(cx, FLOOR + height + 4, cz + rng:NextNumber(-width / 4, width / 4)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 56, 44), Enum.Material.WoodPlanks, parent)
		tank.Shape = Enum.PartType.Cylinder
		tank.Size = Vector3.new(6, 5, 5)
	end
end

-- A generated building mesh filling one street-wall slot. The mesh's street face is
-- +Z; turning it by -sign * 90 degrees points that face at the corridor. Its width
-- (native x) is fitted to the slot, which sets the height within the band's clamp.
local function meshBuilding(sign: number, xNear: number, z: number, span: number, rng: Random, parent: Instance, minHeight: number, maxHeight: number, shadow: boolean): boolean
	local name = WorldMeshes.pick("building", rng)
	local native = name and WorldMeshes.nativeSize(name)
	if not name or not native then
		return false
	end
	local height = math.clamp(span * native.Y / native.X, minHeight, maxHeight)
	local depth = native.Z * height / native.Y
	local base = CFrame.new(sign * (xNear + depth / 2), FLOOR, z + span / 2) * CFrame.Angles(0, -sign * math.rad(90), 0)
	return WorldMeshes.place(name, base, height, parent, { shadow = shadow, sink = 0.2 }) ~= nil
end

local function cityFlank(sign: number, rng: Random, parent: Instance)
	-- sidewalk and kerb along the corridor edge
	local sidewalk = part("Sidewalk", Vector3.new(EDGE - GameConstants.PLAYABLE_HALF_WIDTH + 1, 0.4, GameConstants.CHUNK_LENGTH), CFrame.new(sign * (GameConstants.PLAYABLE_HALF_WIDTH + (EDGE - GameConstants.PLAYABLE_HALF_WIDTH + 1) / 2 - 0.5), FLOOR + 0.2, 0), Color3.fromRGB(150, 148, 142), Enum.Material.Concrete, parent)
	local kerb = part("Kerb", Vector3.new(0.6, 0.5, GameConstants.CHUNK_LENGTH), CFrame.new(sign * (GameConstants.PLAYABLE_HALF_WIDTH - 0.2), FLOOR + 0.25, 0), Color3.fromRGB(176, 174, 168), Enum.Material.Concrete, parent)
	local sidewalkVariant = MATERIALS.City.sidewalk
	if sidewalkVariant then
		MaterialUtil.apply(sidewalk, sidewalkVariant)
		MaterialUtil.apply(kerb, sidewalkVariant)
	end

	-- near block: continuous street wall behind the corridor-edge row
	local near = EDGE + 22
	fillZ(rng, 16, 30, { 0, 2 }, function(z, span)
		if rng:NextNumber() < 0.85 and meshBuilding(sign, near, z, span, rng, parent, 26, 60, true) then
			return
		end
		facadeBuilding(sign, near, rng:NextNumber(18, 26), z, span, rng:NextNumber(28, 62), rng, parent, true)
	end)
	-- middle block: taller, no shadows; building meshes on most slots, facades on the
	-- rest so the skyline keeps its variety
	local mid = near + 34
	fillZ(rng, 22, 40, { 0, 4 }, function(z, span)
		local setback = rng:NextNumber(0, 10)
		if rng:NextNumber() < DressingConfig.CITY_MIDDLE_MESH_SHARE and meshBuilding(sign, mid + setback, z, span, rng, parent, 50, 110, false) then
			return
		end
		facadeBuilding(sign, mid + setback, rng:NextNumber(24, 34), z, span, rng:NextNumber(50, 110), rng, parent, false)
	end)
	-- skyline silhouettes at the back
	local back = mid + 50
	fillZ(rng, 26, 48, { 2, 10 }, function(z, span)
		local height = rng:NextNumber(80, 170)
		local depth = rng:NextNumber(30, WORLD_EDGE - back - 4)
		part("Skyline", Vector3.new(depth, height, span), CFrame.new(sign * (back + depth / 2 + rng:NextNumber(0, 6)), FLOOR + height / 2, z + span / 2), jitter(Color3.fromRGB(70, 72, 80), rng, 0.05), Enum.Material.Concrete, parent)
	end)
end

---------------------------------------------------------------------------------------
-- Forest

local function yawAt(position: Vector3, rng: Random): CFrame
	return CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
end

local function tree(position: Vector3, rng: Random, parent: Instance, shadow: boolean, group: string?, mesh: boolean?)
	if mesh ~= false and WorldMeshes.placeFrom(group or "tree_any", rng, yawAt(position, rng), rng:NextNumber(19, 30), parent, { shadow = shadow, sink = 0.4 }) then
		return
	end
	local conifer = rng:NextNumber() < 0.45
	local trunkHeight = if conifer then rng:NextNumber(6, 10) else rng:NextNumber(10, 18)
	local radius = rng:NextNumber(0.8, 1.5)
	local trunk = part("Trunk", Vector3.new(trunkHeight + 6, radius * 2, radius * 2), CFrame.new(position.X, position.Y + (trunkHeight + 6) / 2, position.Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(rng:NextInteger(62, 84), rng:NextInteger(48, 60), rng:NextInteger(36, 44)), Enum.Material.Wood, parent, shadow)
	trunk.Shape = Enum.PartType.Cylinder
	if conifer then
		local green = Color3.fromRGB(rng:NextInteger(28, 40), rng:NextInteger(58, 76), rng:NextInteger(36, 46))
		local width = rng:NextNumber(9, 13)
		local tall = rng:NextNumber(22, 34)
		-- two stacked, narrowing ellipsoids read as a spruce silhouette
		ball("Needles", Vector3.new(width, tall * 0.62, width), CFrame.new(position.X, position.Y + trunkHeight + tall * 0.28, position.Z), green, Enum.Material.Grass, parent, shadow)
		ball("Needles", Vector3.new(width * 0.6, tall * 0.5, width * 0.6), CFrame.new(position.X, position.Y + trunkHeight + tall * 0.68, position.Z), green:Lerp(Color3.new(), 0.1), Enum.Material.Grass, parent, shadow)
	else
		local green = Color3.fromRGB(rng:NextInteger(44, 64), rng:NextInteger(84, 112), rng:NextInteger(40, 54))
		local r = rng:NextNumber(7, 11)
		for i = 1, 3 do
			local s = r * (if i == 1 then 1 else rng:NextNumber(0.6, 0.8))
			ball("Leaves", Vector3.new(s * 2, s * 1.6, s * 2), CFrame.new(position.X + rng:NextNumber(-r * 0.5, r * 0.5), position.Y + trunkHeight + s * 0.5 + (i - 1) * 2.5, position.Z + rng:NextNumber(-r * 0.5, r * 0.5)), jitter(green, rng, 0.03), Enum.Material.Grass, parent, shadow)
		end
	end
end

local function forestFlank(sign: number, rng: Random, parent: Instance)
	-- dark forest floor so the gaps between trunks are not bright grass
	local floor = part("ForestFloor", Vector3.new(WORLD_EDGE - EDGE, 0.2, GameConstants.CHUNK_LENGTH), CFrame.new(sign * (EDGE + (WORLD_EDGE - EDGE) / 2), FLOOR + 0.1, 0), Color3.fromRGB(58, 62, 40), Enum.Material.Ground, parent)
	local floorVariant = MATERIALS.Forest.forestFloor
	if floorVariant then
		MaterialUtil.apply(floor, floorVariant)
	end
	-- near band: individual trees, jittered grid, shadows on; mesh trees stop at the
	-- triangle budget's line and the primitive tree carries on behind them
	local x = EDGE + 3
	while x < EDGE + 60 do
		local z = -HALF + rng:NextNumber(0, 6)
		while z < HALF do
			local tx = sign * (x + rng:NextNumber(-3, 3))
			if ChunkOccupancy.claim(tx, z, 3) then
				tree(Vector3.new(tx, FLOOR, z), rng, parent, x < EDGE + 25, nil, x < DressingConfig.FOREST_MESH_TREE_MAX_X)
			end
			z += rng:NextNumber(14, 20)
		end
		x += rng:NextNumber(15, 20)
	end
	-- undergrowth along the corridor edge
	for _ = 1, 8 do
		local bushAt = Vector3.new(sign * (EDGE + rng:NextNumber(8, 16)), FLOOR, rng:NextNumber(-HALF, HALF))
		if not ChunkOccupancy.claim(bushAt.X, bushAt.Z, 2.5) then
			continue
		end
		if WorldMeshes.placeFrom("bush", rng, yawAt(bushAt, rng), rng:NextNumber(3, 5), parent, { shadow = false, sink = 0.3 }) then
			continue
		end
		ball("Bush", Vector3.new(rng:NextNumber(4, 8), rng:NextNumber(2.5, 4.5), rng:NextNumber(4, 8)), CFrame.new(sign * (EDGE + rng:NextNumber(-2, 10)), FLOOR + 1, rng:NextNumber(-HALF, HALF)), Color3.fromRGB(rng:NextInteger(40, 56), rng:NextInteger(70, 90), rng:NextInteger(36, 46)), Enum.Material.Grass, parent)
	end
	-- back: a continuous canopy wall with a few trunks under it
	local back = EDGE + 64
	fillZ(rng, 20, 34, { -6, -2 }, function(z, span)
		local height = rng:NextNumber(34, 52)
		local depth = rng:NextNumber(40, 70)
		ball("CanopyMass", Vector3.new(depth, height, span + 10), CFrame.new(sign * (back + depth / 2 + rng:NextNumber(0, 30)), FLOOR + height * 0.42, z + span / 2), Color3.fromRGB(rng:NextInteger(30, 42), rng:NextInteger(56, 72), rng:NextInteger(34, 44)), Enum.Material.Grass, parent)
	end)
	for _ = 1, 5 do
		local trunk = part("Trunk", Vector3.new(24, 2, 2), CFrame.new(sign * (back + rng:NextNumber(0, 12)), FLOOR + 12, rng:NextNumber(-HALF, HALF)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(56, 44, 34), Enum.Material.Wood, parent)
		trunk.Shape = Enum.PartType.Cylinder
	end
end

---------------------------------------------------------------------------------------
-- Wasteland

local SAND = Color3.fromRGB(172, 156, 130)
local CONCRETE = Color3.fromRGB(124, 118, 108)

local function ruinPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance, shadow: boolean): Part
	local p = part(name, size, cframe, color, Enum.Material.Concrete, parent, shadow)
	local variant = MATERIALS.Wasteland.ruin
	if variant then
		MaterialUtil.apply(p, variant)
	end
	return p
end

-- A gutted building seen from the road. With a building mesh loaded it is that mesh
-- sunk into the ground and leaning away from the road, two wall stubs and rubble at its
-- street foot; otherwise an L of broken walls with a jagged top. Returns the depth the
-- ruin takes outwards from x.
local function ruinShell(sign: number, x: number, z: number, rng: Random, parent: Instance): number
	local width = rng:NextNumber(18, 30)
	local depth = rng:NextNumber(14, 22)
	local color = jitter(CONCRETE, rng, 0.05)
	local name = WorldMeshes.pick("building", rng)
	local native = name and WorldMeshes.nativeSize(name)
	local steps = rng:NextInteger(3, 5)
	if name and native then
		local height = rng:NextNumber(30, 46)
		local sink = height * rng:NextNumber(0.35, 0.55)
		local tilt = math.rad(rng:NextNumber(3, 8))
		depth = native.Z * height / native.Y
		-- the tilt is about the road axis, so the top leans outwards
		local base = CFrame.new(sign * (x + 4 + depth / 2), FLOOR, z + width / 2) * CFrame.Angles(0, 0, -sign * tilt) * CFrame.Angles(0, -sign * math.rad(90), 0)
		WorldMeshes.place(name, base, height, parent, { shadow = true, sink = sink })
		steps = 2
		local rubble = WorldMeshes.pick("rubble", rng)
		if rubble then
			WorldMeshes.placeNatural(rubble, yawAt(Vector3.new(sign * (x - 2), FLOOR, z + width * rng:NextNumber(0.2, 0.8)), rng), parent, { shadow = true, sink = 0.3 }, 1.2)
		end
		depth += 4
	end
	for i = 0, steps - 1 do
		local h = rng:NextNumber(6, 22)
		local seg = width / steps
		ruinPart("RuinFront", Vector3.new(1.6, h, seg), CFrame.new(sign * x, FLOOR + h / 2, z + seg * (i + 0.5)), color, parent, true)
	end
	if steps > 2 then
		local sideH = rng:NextNumber(8, 18)
		ruinPart("RuinSide", Vector3.new(depth, sideH, 1.6), CFrame.new(sign * (x + depth / 2), FLOOR + sideH / 2, z), color, parent, true)
		ruinPart("RuinSlab", Vector3.new(depth * 0.8, 1.2, width * 0.5), CFrame.new(sign * (x + depth / 2), FLOOR + 3, z + width * 0.4) * CFrame.Angles(0, 0, sign * 0.35), color:Lerp(Color3.new(), 0.2), parent, false)
	end
	return depth
end

local function deadTree(position: Vector3, rng: Random, parent: Instance)
	local h = rng:NextNumber(12, 20)
	if WorldMeshes.placeFrom("tree_dead", rng, yawAt(position, rng), h, parent, { shadow = true, sink = 0.4 }) then
		return
	end
	local t = part("DeadTrunk", Vector3.new(h, 1.2, 1.2), CFrame.new(position + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90 + rng:NextNumber(-6, 6))), Color3.fromRGB(58, 50, 44), Enum.Material.Wood, parent)
	t.Shape = Enum.PartType.Cylinder
	for _ = 1, 2 do
		local len = rng:NextNumber(4, 8)
		part("DeadBranch", Vector3.new(0.5, len, 0.5), CFrame.new(position + Vector3.new(0, h * rng:NextNumber(0.55, 0.85), 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(30, 60))) * CFrame.new(0, len / 2, 0), Color3.fromRGB(54, 46, 40), Enum.Material.Wood, parent)
	end
end

local function wastelandFlank(sign: number, rng: Random, parent: Instance)
	-- near: ruins, wrecks and dead trees
	fillZ(rng, 26, 40, { 4, 14 }, function(z, span)
		local roll = rng:NextNumber()
		local function spot(radius: number, xMin: number, xMax: number): Vector3?
			local x, zz = ChunkOccupancy.findSpot(radius, 4, function()
				return sign * (EDGE + rng:NextNumber(xMin, xMax)), z + rng:NextNumber(0, span)
			end)
			return if x and zz then Vector3.new(x, FLOOR, zz) else nil
		end
		if roll < 0.5 then
			local x = EDGE + rng:NextNumber(10, 20)
			local depth = ruinShell(sign, x, z, rng, parent)
			ChunkOccupancy.reserveBox(sign * (x - 4), z - 1, sign * (x + depth + 1), z + 31)
		else
			for _ = 1, rng:NextInteger(1, 3) do
				local at = spot(2.5, 8, 32)
				if at then
					deadTree(at, rng, parent)
				end
			end
		end
		if rng:NextNumber() < 0.5 then
			local size = rng:NextNumber(4, 9)
			local at = spot(size * 0.8, 8, 30)
			if at then
				WorldMeshes.placeFrom("boulder", rng, yawAt(at, rng), size, parent, { shadow = true, sink = size * 0.1, stretch = Vector3.new(rng:NextNumber(1, 1.5), 1, rng:NextNumber(1, 1.5)) })
			end
		end
		if rng:NextNumber() < 0.25 then
			local at = spot(7, 10, 30)
			local name = WorldMeshes.pick("car_wreck", rng)
			if at and name then
				WorldMeshes.placeByLength(name, yawAt(at, rng), 12, parent, { shadow = true, sink = 0.2 })
			end
		end
	end)
	-- rubble berms: long low slopes that break up the flat ground
	for _ = 1, rng:NextInteger(2, 3) do
		local length = rng:NextNumber(30, 60)
		local height = rng:NextNumber(4, 10)
		local width = rng:NextNumber(18, 30)
		local berm = wedge("Berm", Vector3.new(length, height, width), CFrame.new(sign * (EDGE + rng:NextNumber(40, 90)), FLOOR + height / 2, rng:NextNumber(-HALF, HALF)) * CFrame.Angles(0, if sign > 0 then math.rad(-90) else math.rad(90), 0), jitter(SAND, rng, 0.05), Enum.Material.Sand, parent)
		local bermVariant = MATERIALS.Wasteland.berm
		if bermVariant then
			MaterialUtil.apply(berm, bermVariant)
		end
	end
	-- back: mesas and a broken skyline
	local back = EDGE + 110
	fillZ(rng, 30, 56, { 6, 20 }, function(z, span)
		local height = rng:NextNumber(24, 70)
		local depth = rng:NextNumber(30, 60)
		local shape = rng:NextNumber()
		if shape < 0.5 then
			wedge("Mesa", Vector3.new(span, height, depth), CFrame.new(sign * (back + depth / 2), FLOOR + height / 2, z + span / 2) * CFrame.Angles(0, if sign > 0 then math.rad(180) else 0, 0), jitter(Color3.fromRGB(150, 130, 108), rng, 0.05), Enum.Material.Sandstone, parent)
		else
			part("DeadTower", Vector3.new(depth * 0.6, height * 1.4, span * 0.5), CFrame.new(sign * (back + depth / 2), FLOOR + height * 0.7, z + span / 2) * CFrame.Angles(0, 0, sign * rng:NextNumber(0, 0.08)), jitter(Color3.fromRGB(88, 84, 80), rng, 0.04), Enum.Material.Concrete, parent)
		end
	end)
end

---------------------------------------------------------------------------------------
-- Farmland and corn

-- `gap` is {xMin, xMax, zMin, zMax} (x measured outwards from the corridor): rows
-- crossing it are split so nothing grows through a building.
local function cropRows(sign: number, xStart: number, xEnd: number, rng: Random, parent: Instance, tall: boolean, gap: { number }?)
	local x = xStart
	local base = if tall then Color3.fromRGB(84, 104, 46) else Color3.fromRGB(116, 118, 58)
	while x < xEnd do
		local h = if tall then rng:NextNumber(9, 12) else rng:NextNumber(1.2, 2.2)
		local w = if tall then 3.5 else 2.2
		local color = jitter(base, rng, 0.03)
		local material = if tall then Enum.Material.LeafyGrass else Enum.Material.Grass
		if gap and x + w / 2 > gap[1] and x - w / 2 < gap[2] then
			for _, seg in { { -HALF, gap[3] }, { gap[4], HALF } } do
				local len = seg[2] - seg[1]
				if len > 1 then
					part("CropRow", Vector3.new(w, h, len), CFrame.new(sign * x, FLOOR + h / 2, (seg[1] + seg[2]) / 2), color, material, parent, false)
				end
			end
			x += if tall then 4.2 else 5
			continue
		end
		part("CropRow", Vector3.new(w, h, GameConstants.CHUNK_LENGTH), CFrame.new(sign * x, FLOOR + h / 2, 0), color, material, parent, tall and x < xStart + 10)
		if tall then
			part("Tassels", Vector3.new(w * 0.7, 0.8, GameConstants.CHUNK_LENGTH), CFrame.new(sign * x, FLOOR + h + 0.3, 0), jitter(Color3.fromRGB(184, 164, 96), rng, 0.04), Enum.Material.Grass, parent)
		end
		x += if tall then 4.2 else 5
	end
end

local function barn(sign: number, x: number, z: number, w: number, d: number, rng: Random, parent: Instance)
	local h = rng:NextNumber(12, 16)
	local red = jitter(Color3.fromRGB(122, 42, 34), rng, 0.05)
	part("Barn", Vector3.new(d, h, w), CFrame.new(sign * (x + d / 2), FLOOR + h / 2, z), red, Enum.Material.WoodPlanks, parent, true)
	for _, s in { -1, 1 } do
		local roof = wedge("BarnRoof", Vector3.new(w + 1, h * 0.45, d / 2 + 0.5), CFrame.new(sign * (x + d / 2) + s * d / 4, FLOOR + h + h * 0.225, z) * CFrame.Angles(0, if s > 0 then math.rad(-90) else math.rad(90), 0), Color3.fromRGB(64, 60, 58), Enum.Material.CorrodedMetal, parent)
		local roofVariant = MATERIALS.Farmstead.barnRoof
		if roofVariant then
			MaterialUtil.apply(roof, roofVariant)
		end
	end
	part("BarnDoor", Vector3.new(0.3, h * 0.6, w * 0.3), CFrame.new(sign * x - sign * 0.2, FLOOR + h * 0.3, z), Color3.fromRGB(230, 222, 206), Enum.Material.WoodPlanks, parent)
end

local function hills(sign: number, rng: Random, parent: Instance, color: Color3)
	local back = EDGE + 120
	fillZ(rng, 40, 64, { -10, 0 }, function(z, span)
		local height = rng:NextNumber(18, 40)
		local depth = rng:NextNumber(60, 90)
		ball("Hill", Vector3.new(depth, height * 2, span + 20), CFrame.new(sign * (back + depth / 2), FLOOR, z + span / 2), jitter(color, rng, 0.04), Enum.Material.Grass, parent)
	end)
end

local function farmFlank(sign: number, rng: Random, parent: Instance)
	local gap: { number }? = nil
	if rng:NextNumber() < 0.35 then
		local w, d = rng:NextNumber(24, 34), rng:NextNumber(18, 24)
		local x = EDGE + rng:NextNumber(20, 50)
		-- keep the whole barn inside this chunk
		local z = rng:NextNumber(-HALF + w / 2 + 2, HALF - w / 2 - 2)
		barn(sign, x, z, w, d, rng, parent)
		gap = { x - 3, x + d + 3, z - w / 2 - 3, z + w / 2 + 3 }
		ChunkOccupancy.reserveBox(sign * (x - 3), z - w / 2 - 3, sign * (x + d + 3), z + w / 2 + 3)
	end
	cropRows(sign, EDGE + 8, EDGE + 90, rng, parent, false, gap)
	for _ = 1, rng:NextInteger(2, 5) do
		local bx, bz = ChunkOccupancy.findSpot(2.5, 4, function()
			return sign * (EDGE + rng:NextNumber(10, 80)), rng:NextNumber(-HALF + 3, HALF - 3)
		end)
		if bx and bz then
			local bale = part("HayBale", Vector3.new(4, 3.2, 3.2), CFrame.new(bx, FLOOR + 1.55, bz) * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(90)), Color3.fromRGB(196, 170, 96), Enum.Material.Grass, parent)
			bale.Shape = Enum.PartType.Cylinder
		end
	end
	-- windbreak tree line between the field and the hills
	local z = -HALF + rng:NextNumber(0, 8)
	while z < HALF do
		local tx = sign * (EDGE + 100 + rng:NextNumber(-3, 3))
		if ChunkOccupancy.claim(tx, z, 3) then
			tree(Vector3.new(tx, FLOOR, z), rng, parent, false, "tree_leafy")
		end
		z += rng:NextNumber(12, 18)
	end
	hills(sign, rng, parent, Color3.fromRGB(104, 118, 70))
end

-- One row of corn meshes along z at distance x, rotated so the row runs with the road.
local function cornMeshRow(sign: number, x: number, rng: Random, parent: Instance, shadow: boolean): boolean
	local name = WorldMeshes.pick("corn", rng)
	local native = name and WorldMeshes.nativeSize(name)
	if not name or not native then
		return false
	end
	local z = -HALF
	while z < HALF do
		local height = rng:NextNumber(10, 12.5)
		local length = native.X * height / native.Y
		local flip = if rng:NextNumber() < 0.5 then math.pi else 0
		WorldMeshes.place(name, CFrame.new(sign * (x + rng:NextNumber(-0.6, 0.6)), FLOOR, z + length / 2) * CFrame.Angles(0, math.rad(90) + flip, 0), height, parent, { shadow = shadow, sink = 0.3, stretch = Vector3.new(1, 1, 0.7) })
		z += length * 0.85
	end
	return true
end

local function cornFlank(sign: number, rng: Random, parent: Instance)
	local meshRows = cornMeshRow(sign, EDGE + 3, rng, parent, true)
	if meshRows then
		cornMeshRow(sign, EDGE + 9, rng, parent, false)
	end
	cropRows(sign, if meshRows then EDGE + 14 else EDGE + 2, EDGE + 70, rng, parent, true)
	-- the corn mass continues as one block to hide the row ends
	part("CornMass", Vector3.new(40, 11, GameConstants.CHUNK_LENGTH), CFrame.new(sign * (EDGE + 90), FLOOR + 5.5, 0), Color3.fromRGB(74, 92, 42), Enum.Material.LeafyGrass, parent)
	hills(sign, rng, parent, Color3.fromRGB(96, 104, 62))
end

---------------------------------------------------------------------------------------

local BUILDERS: { [string]: (number, Random, Instance) -> () } = {
	buildings = cityFlank,
	trees = forestFlank,
	ruins = wastelandFlank,
	farm = farmFlank,
	corn = cornFlank,
}

function WorldFlanks.build(kind: string, rng: Random, parent: Instance)
	local builder = BUILDERS[kind]
	if not builder then
		return
	end
	local folder = Instance.new("Model")
	folder.Name = "Flanks"
	for _, sign in { -1, 1 } do
		builder(sign, rng, folder)
	end
	folder.Parent = parent
end

return WorldFlanks
