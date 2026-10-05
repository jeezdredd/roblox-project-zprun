--!strict

-- Decides where road dressing goes in a chunk. Pure Luau: no services, no engine types
-- and no requires, so it runs under the standalone Luau CLI (tests/world/run.luau). The
-- rules come in as the DressingConfig table; the server (WorldDressing) turns the
-- placements into instances.
--
-- Inputs: the config, an Rng (Random fits), an occupancy object (ChunkOccupancy fits)
-- and the loaded prop sizes. Coordinates are chunk-local: x across the road, z along
-- it, the chunk spanning -halfLength..halfLength.

export type Range = { number }

-- The shapes below mirror DressingConfig's exported types.
export type Member = {
	group: string,
	count: Range,
	zone: string,
	layout: string?,
	spread: number?,
	yaw: Range?,
	patch: string?,
}

export type Recipe = { members: { Member } }

export type Zone = {
	inner: number,
	outer: number,
	collide: boolean,
	shadow: boolean,
	detail: boolean,
}

export type BiomeRules = {
	clusters: Range,
	sides: string,
	recipes: { string },
	props: Range,
	zones: { [string]: Range }?,
}

export type Config = {
	zones: { [string]: Zone },
	recipes: { [string]: Recipe },
	biomes: { [string]: BiomeRules },
	fallbackSizes: { [string]: { number } },
	ground: { [string]: { { number } } },
	GROUND_DEFAULT: number,
	SHADOW_MIN_HEIGHT: number,
	FOOTPRINT_MARGIN: number,
	SPACING_SAME_SIDE: number,
	SPACING_ACROSS: number,
	GAP_DIFFERENCE: number,
	END_CLEARANCE: number,
	DETAIL_FROM_MEMBER: number,
}

export type Rng = {
	NextNumber: (self: Rng, min: number, max: number) -> number,
	NextInteger: (self: Rng, min: number, max: number) -> number,
}

export type Occupancy = {
	claim: (x: number, z: number, radius: number) -> boolean,
}

-- footprint x, footprint z, height, in studs
export type Size = { number }

export type Placement = {
	-- 1-based index of the cluster within the chunk
	cluster: number,
	recipe: string,
	group: string,
	-- mesh name when one is loaded; nil means the primitive stand-in
	name: string?,
	x: number,
	y: number,
	z: number,
	yaw: number,
	zone: string,
	collide: boolean,
	shadow: boolean,
	detail: boolean,
	radius: number,
	size: Size,
	patch: string?,
}

export type Options = {
	halfLength: number,
	-- mesh names per group (WorldMeshConfig.groups)
	groups: { [string]: { string } },
	-- real size per loaded mesh name (WorldMeshes.naturalSize)
	sizes: { [string]: Size },
	-- 0..1, scales the clusters and the prop cap (a map transition dresses with both
	-- locations at their shares); nil is 1
	density: number?,
}

local DressingPlanner = {}

local TWO_PI = math.pi * 2
-- spots tried for a scattered member before it is dropped
local TRIES = 3

function DressingPlanner.groundHeight(config: Config, biome: string, x: number): number
	local bands = config.ground[biome]
	if bands then
		local distance = math.abs(x)
		for _, band in bands do
			if distance >= band[1] and distance < band[2] then
				return band[3]
			end
		end
	end
	return config.GROUND_DEFAULT
end

-- The zone's x range for this biome, with the biome's overrides applied.
local function zoneRange(config: Config, rules: BiomeRules, zoneName: string): (number, number)
	local override = rules.zones and rules.zones[zoneName]
	if override then
		return override[1], override[2]
	end
	local zone = config.zones[zoneName]
	return zone.inner, zone.outer
end

-- Picks a loaded mesh for the group, or nil with the fallback size.
local function pickName(config: Config, group: string, rng: Rng, options: Options): (string?, Size)
	local names = options.groups[group]
	local loaded = {}
	if names then
		for _, name in names do
			if options.sizes[name] then
				table.insert(loaded, name)
			end
		end
	end
	if #loaded > 0 then
		local name = loaded[rng:NextInteger(1, #loaded)]
		return name, options.sizes[name]
	end
	return nil, config.fallbackSizes[group] or { 2, 2, 2 }
end

-- Axis-aligned footprint along x and z once the prop is turned by yaw.
local function turnedFootprint(size: Size, yaw: number): (number, number)
	local s, c = math.abs(math.sin(yaw)), math.abs(math.cos(yaw))
	return size[1] * c + size[2] * s, size[1] * s + size[2] * c
end

local function memberYaw(member: Member, rng: Rng): number
	if member.yaw then
		return rng:NextNumber(member.yaw[1], member.yaw[2])
	end
	return rng:NextNumber(0, TWO_PI)
end

-- Centres a footprint inside the zone; a prop wider than the zone sits on its middle.
local function fitX(inner: number, outer: number, width: number, rng: Rng): number
	local low, high = inner + width / 2, outer - width / 2
	if low > high then
		return (inner + outer) / 2
	end
	return rng:NextNumber(low, high)
end

type Spot = {
	cluster: number,
	recipe: string,
	member: Member,
	x: number,
	z: number,
	yaw: number,
	name: string?,
	size: Size,
	index: number,
}

local function place(config: Config, biome: string, spot: Spot, occupancy: Occupancy, halfLength: number): Placement?
	local fx, fz = turnedFootprint(spot.size, spot.yaw)
	local radius = math.max(fx, fz) / 2 + config.FOOTPRINT_MARGIN
	-- keep the footprint inside the chunk; the neighbour chunk dresses its own ground
	local reach = halfLength - 2 - fz / 2
	local z = math.clamp(spot.z, -reach, reach)
	if not occupancy.claim(spot.x, z, radius) then
		return nil
	end
	local zone = config.zones[spot.member.zone]
	local height = spot.size[3]
	return {
		cluster = spot.cluster,
		recipe = spot.recipe,
		group = spot.member.group,
		name = spot.name,
		x = spot.x,
		y = DressingPlanner.groundHeight(config, biome, spot.x),
		z = z,
		yaw = spot.yaw,
		zone = spot.member.zone,
		collide = zone.collide,
		shadow = zone.shadow and height >= config.SHADOW_MIN_HEIGHT,
		-- the anchor always stays, so a cluster survives the mobile tier
		detail = spot.index > 1 and (zone.detail or spot.index >= config.DETAIL_FROM_MEMBER),
		radius = radius,
		size = spot.size,
		patch = spot.member.patch,
	}
end

-- Places one recipe around (sign, anchorZ). Returns its placements, empty when the
-- first member found no room (a cluster never ships without its anchor).
local function placeCluster(
	config: Config,
	biome: string,
	rules: BiomeRules,
	cluster: number,
	recipeName: string,
	sign: number,
	anchorZ: number,
	rng: Rng,
	occupancy: Occupancy,
	options: Options,
	room: number
): { Placement }
	local recipe = config.recipes[recipeName]
	local out: { Placement } = {}
	local index = 0
	for memberIndex, member in recipe.members do
		local count = rng:NextInteger(member.count[1], member.count[2])
		if memberIndex == 1 then
			count = math.max(count, 1)
		end
		local inner, outer = zoneRange(config, rules, member.zone)
		if member.layout == "line" then
			-- the members follow each other along the road, long side along z
			local name, size = pickName(config, member.group, rng, options)
			local yaw = if size[2] >= size[1] then 0 else math.pi / 2
			local width, length = turnedFootprint(size, yaw)
			local x = sign * fitX(inner, outer, width, rng)
			-- each piece claims a circle, so the step clears two margins as well
			local step = length + config.FOOTPRINT_MARGIN * 2 + 0.5
			local z = anchorZ - (count - 1) * step / 2
			for _ = 1, count do
				if #out >= room then
					break
				end
				index += 1
				local placed = place(config, biome, { cluster = cluster, recipe = recipeName, member = member, x = x, z = z, yaw = yaw, name = name, size = size, index = index }, occupancy, options.halfLength)
				if placed then
					table.insert(out, placed)
				end
				z += step
			end
		else
			for _ = 1, count do
				if #out >= room then
					break
				end
				index += 1
				local name, size = pickName(config, member.group, rng, options)
				local yaw = memberYaw(member, rng)
				local width = turnedFootprint(size, yaw)
				local spread = member.spread or 0
				for _ = 1, TRIES do
					local x = sign * fitX(inner, outer, width, rng)
					local z = anchorZ + rng:NextNumber(-spread, spread)
					local placed = place(config, biome, { cluster = cluster, recipe = recipeName, member = member, x = x, z = z, yaw = yaw, name = name, size = size, index = index }, occupancy, options.halfLength)
					if placed then
						table.insert(out, placed)
						break
					end
				end
			end
		end
		if memberIndex == 1 and #out == 0 then
			return {}
		end
	end
	return out
end

-- Picks a z for the next cluster on `sign` that keeps the spacing rules, or nil.
local function pickAnchorZ(config: Config, rng: Rng, sign: number, lastZ: { [number]: number }, lastGap: { [number]: number }, halfLength: number): number?
	local limit = halfLength - config.END_CLEARANCE
	for _ = 1, 8 do
		local z = rng:NextNumber(-limit, limit)
		local ok = true
		local same = lastZ[sign]
		if same then
			local gap = math.abs(z - same)
			if gap < config.SPACING_SAME_SIDE then
				ok = false
			end
			local previousGap = lastGap[sign]
			if previousGap and math.abs(gap - previousGap) < config.GAP_DIFFERENCE then
				ok = false
			end
		end
		local other = lastZ[-sign]
		if other and math.abs(z - other) < config.SPACING_ACROSS then
			ok = false
		end
		if ok then
			return z
		end
	end
	return nil
end

function DressingPlanner.plan(config: Config, biome: string, rng: Rng, occupancy: Occupancy, options: Options): { Placement }
	local rules = config.biomes[biome]
	if not rules then
		return {}
	end
	local out: { Placement } = {}
	local clusters = rng:NextInteger(rules.clusters[1], rules.clusters[2])
	local cap = rng:NextInteger(rules.props[1], rules.props[2])
	local density = options.density
	if density then
		local share = math.clamp(density, 0, 1)
		clusters = math.floor(clusters * share + 0.5)
		cap = math.floor(cap * share + 0.5)
	end
	local sign = if rng:NextNumber(0, 1) < 0.5 then -1 else 1
	local lastZ: { [number]: number } = {}
	local lastGap: { [number]: number } = {}
	local cluster = 0
	for _ = 1, clusters do
		if #out >= cap then
			break
		end
		local recipeName = rules.recipes[rng:NextInteger(1, #rules.recipes)]
		local anchorZ = pickAnchorZ(config, rng, sign, lastZ, lastGap, options.halfLength)
		if anchorZ then
			local placed = placeCluster(config, biome, rules, cluster + 1, recipeName, sign, anchorZ, rng, occupancy, options, cap - #out)
			if #placed > 0 then
				cluster += 1
				local previous = lastZ[sign]
				if previous then
					lastGap[sign] = math.abs(anchorZ - previous)
				end
				lastZ[sign] = anchorZ
				for _, placement in placed do
					table.insert(out, placement)
				end
			end
		end
		if rules.sides == "alternate" then
			sign = -sign
		end
	end
	return out
end

return DressingPlanner
