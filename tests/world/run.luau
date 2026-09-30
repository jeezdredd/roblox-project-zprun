--!strict

-- Pure-logic tests for the environment pass. Run from the repository root with the
-- standalone Luau CLI:  luau tests/world/run.luau
-- One line per group; the run exits non-zero when any check failed.

local DressingConfig = require("../../src/shared/config/DressingConfig")
local DecalsConfig = require("../../src/shared/config/DecalsConfig")
local VisibilityConfig = require("../../src/shared/config/VisibilityConfig")
local DressingPlanner = require("../../src/shared/world/DressingPlanner")
local ChunkBudget = require("../../src/shared/world/ChunkBudget")
local FogBudget = require("../../src/shared/world/FogBudget")
local ChunkOccupancy = require("../../src/server/systems/ChunkOccupancy")

local failures = 0

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		return
	end
	failures += 1
	print(string.format("  FAIL %s%s", name, if detail then " (" .. detail .. ")" else ""))
end

local function group(name: string, body: () -> ())
	local before = failures
	body()
	print(string.format("%s %s", if failures == before then "ok  " else "FAIL", name))
end

-- A small deterministic generator with Random's shape.
local function makeRng(seed: number): DressingPlanner.Rng
	local state = seed
	local function nextUnit(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	return {
		NextNumber = function(_, min: number, max: number): number
			return min + (max - min) * nextUnit()
		end,
		NextInteger = function(_, min: number, max: number): number
			return min + math.floor(nextUnit() * (max - min + 1))
		end,
	} :: any
end

-- Every prop loaded at its nominal size.
local function allSizes(): { [string]: DressingPlanner.Size }
	local sizes = {}
	for groupName, size in DressingConfig.fallbackSizes do
		sizes[groupName .. "_mesh"] = size
	end
	return sizes
end

local function groupsFor(): { [string]: { string } }
	local groups = {}
	for groupName in DressingConfig.fallbackSizes do
		groups[groupName] = { groupName .. "_mesh" }
	end
	return groups
end

local BIOMES = { "City", "Forest", "Wasteland", "Farmstead", "Cornfield" }
local HALF = 64

local function planFor(biome: string, seed: number, sizes: { [string]: DressingPlanner.Size }?): { DressingPlanner.Placement }
	ChunkOccupancy.reset()
	local loaded = sizes or allSizes()
	return DressingPlanner.plan(DressingConfig, biome, makeRng(seed), ChunkOccupancy, {
		halfLength = HALF,
		groups = groupsFor(),
		sizes = loaded,
	})
end

local function zoneRange(biome: string, zone: string): (number, number)
	local rules = DressingConfig.biomes[biome]
	local override = rules.zones and rules.zones[zone]
	if override then
		return override[1], override[2]
	end
	local z = DressingConfig.zones[zone]
	return z.inner, z.outer
end

group("config", function()
	for _, biome in BIOMES do
		local rules = DressingConfig.biomes[biome]
		check(biome .. " has rules", rules ~= nil)
		for _, recipeName in rules.recipes do
			check(biome .. " recipe " .. recipeName, DressingConfig.recipes[recipeName] ~= nil)
		end
		check(biome .. " has materials", DressingConfig.materials[biome] ~= nil)
	end
	for recipeName, recipe in DressingConfig.recipes do
		for _, member in recipe.members do
			check(recipeName .. " zone " .. member.zone, DressingConfig.zones[member.zone] ~= nil)
			check(recipeName .. " size " .. member.group, DressingConfig.fallbackSizes[member.group] ~= nil)
		end
	end
	check("mobile under desktop", DressingConfig.budgets.mobile.triangles < DressingConfig.budgets.desktop.triangles)
end)

group("ground height", function()
	check("lane is the floor", DressingPlanner.groundHeight(DressingConfig, "City", 0) == 0.5)
	check("city sidewalk", DressingPlanner.groundHeight(DressingConfig, "City", -32) == 0.9)
	check("city edge is the apron", DressingPlanner.groundHeight(DressingConfig, "City", 38) == 0.5)
	check("forest floor part", DressingPlanner.groundHeight(DressingConfig, "Forest", 40) == 0.7)
	check("forest lane", DressingPlanner.groundHeight(DressingConfig, "Forest", 10) == 0.5)
	check("unknown biome", DressingPlanner.groundHeight(DressingConfig, "Moon", 40) == 0.5)
end)

group("placements stay in their zones", function()
	for _, biome in BIOMES do
		for seed = 1, 12 do
			local lastCluster = 0
			for _, p in planFor(biome, seed) do
				local anchor = p.cluster ~= lastCluster
				check(biome .. " clusters are numbered in order", p.cluster == lastCluster or p.cluster == lastCluster + 1)
				lastCluster = p.cluster
				local inner, outer = zoneRange(biome, p.zone)
				local distance = math.abs(p.x)
				local half = math.max(p.size[1], p.size[2]) / 2
				local slack = math.max(0, half - (outer - inner) / 2)
				check(biome .. " inside zone", distance >= inner - slack - 1e-6 and distance <= outer + slack + 1e-6, string.format("%s %s x=%.1f", p.recipe, p.group, p.x))
				check(biome .. " off the lanes", distance - p.size[1] / 2 >= 25.9, string.format("%s x=%.1f", p.group, p.x))
				check(biome .. " inside the chunk", math.abs(p.z) + p.size[2] / 2 <= HALF, string.format("%s z=%.1f", p.group, p.z))
				check(biome .. " ground height", p.y == DressingPlanner.groundHeight(DressingConfig, biome, p.x))
				local zone = DressingConfig.zones[p.zone]
				check(biome .. " collide by zone", p.collide == zone.collide)
				check(biome .. " shadow by zone and height", p.shadow == (zone.shadow and p.size[3] >= DressingConfig.SHADOW_MIN_HEIGHT))
				if zone.detail and not anchor then
					check(biome .. " clutter is detail", p.detail)
				end
				if anchor then
					check(biome .. " anchor is base tier", not p.detail)
				end
			end
		end
	end
end)

group("no overlaps and counts within the cap", function()
	for _, biome in BIOMES do
		local rules = DressingConfig.biomes[biome]
		for seed = 1, 12 do
			local placements = planFor(biome, seed)
			check(biome .. " under cap", #placements <= rules.props[2], tostring(#placements))
			for i = 1, #placements do
				for j = i + 1, #placements do
					local a, b = placements[i], placements[j]
					local dx, dz = a.x - b.x, a.z - b.z
					local reach = a.radius + b.radius
					check(biome .. " no overlap", dx * dx + dz * dz >= reach * reach - 1e-6, a.group .. " vs " .. b.group)
				end
			end
		end
	end
end)

group("clusters keep their spacing", function()
	for _, biome in BIOMES do
		for seed = 1, 12 do
			local anchors: { { number } } = {}
			-- the first placement of each cluster stands for its anchor
			local lastCluster = 0
			for _, p in planFor(biome, seed) do
				if p.cluster ~= lastCluster then
					table.insert(anchors, { if p.x > 0 then 1 else -1, p.z })
					lastCluster = p.cluster
				end
			end
			for i = 1, #anchors do
				for j = i + 1, #anchors do
					local a, b = anchors[i], anchors[j]
					local gap = math.abs(a[2] - b[2])
					if a[1] == b[1] then
						check(biome .. " same side spacing", gap >= DressingConfig.SPACING_SAME_SIDE - 20, string.format("%.1f", gap))
					else
						check(biome .. " across spacing", gap >= DressingConfig.SPACING_ACROSS - 20, string.format("%.1f", gap))
					end
				end
			end
		end
	end
end)

group("sides", function()
	for seed = 1, 8 do
		local signs: { [number]: boolean } = {}
		for _, p in planFor("Cornfield", seed) do
			signs[if p.x > 0 then 1 else -1] = true
		end
		check("cornfield keeps to one side", not (signs[1] and signs[-1]))
	end
	local both = 0
	for seed = 1, 12 do
		local signs: { [number]: boolean } = {}
		for _, p in planFor("City", seed) do
			signs[if p.x > 0 then 1 else -1] = true
		end
		if signs[1] and signs[-1] then
			both += 1
		end
	end
	check("city dresses both sides", both >= 8, tostring(both))
end)

group("deterministic per seed", function()
	local a = planFor("City", 7)
	local b = planFor("City", 7)
	check("same length", #a == #b)
	for i, p in a do
		local q = b[i]
		check("same placement", q ~= nil and p.x == q.x and p.z == q.z and p.yaw == q.yaw and p.group == q.group)
	end
	local c = planFor("City", 8)
	local same = #a == #c
	if same then
		for i, p in a do
			if c[i].x ~= p.x or c[i].z ~= p.z then
				same = false
			end
		end
	end
	check("another seed differs", not same)
end)

group("fallback when nothing is loaded", function()
	for _, biome in BIOMES do
		local placements = planFor(biome, 3, {})
		for _, p in placements do
			check(biome .. " primitive stand-in", p.name == nil)
			check(biome .. " fallback size", p.size == DressingConfig.fallbackSizes[p.group])
		end
	end
	local placements = planFor("City", 3)
	local named = 0
	for _, p in placements do
		if p.name then
			named += 1
		end
	end
	check("meshes used when loaded", named == #placements and named > 0)
end)

group("half clusters never ship", function()
	-- fill the whole edge strip so no anchor can land; nothing may come out
	for _, biome in BIOMES do
		ChunkOccupancy.reset()
		for z = -HALF, HALF, 4 do
			for _, sign in { -1, 1 } do
				ChunkOccupancy.reserve(sign * 39.5, z, 6)
				ChunkOccupancy.reserve(sign * 52, z, 8)
				ChunkOccupancy.reserve(sign * 32.5, z, 4)
			end
		end
		local loaded = allSizes()
		local placements = DressingPlanner.plan(DressingConfig, biome, makeRng(5), ChunkOccupancy, { halfLength = HALF, groups = groupsFor(), sizes = loaded })
		check(biome .. " nothing on a full strip", #placements == 0, tostring(#placements))
	end
end)

group("unknown biome", function()
	check("empty plan", #planFor("Moon", 1) == 0)
end)

group("patches", function()
	local burned = 0
	for seed = 1, 20 do
		for _, p in planFor("Wasteland", seed) do
			if p.group == "car_burned" then
				burned += 1
				check("burned car has a patch", p.patch == "TFZ_GroundBurned")
			else
				check("only burned cars patch", p.patch == nil)
			end
		end
	end
	check("some burned cars placed", burned > 0)
end)

group("decals", function()
	local ids = { asphalt_patch_a = 130009179528114, graffiti_a = 0, leak_streaks = -3 }
	check("known key", DecalsConfig.idOf(ids, "asphalt_patch_a") == 130009179528114)
	check("zero key", DecalsConfig.idOf(ids, "graffiti_a") == 0)
	check("negative key", DecalsConfig.idOf(ids, "leak_streaks") == 0)
	check("missing key", DecalsConfig.idOf(ids, "blood_trail_a") == 0)
	check("no table", DecalsConfig.idOf(nil, "blood_trail_a") == 0)
	check("wrong type", DecalsConfig.idOf({ oil_stain_a = "12" }, "oil_stain_a") == 0)
	local city = DecalsConfig.forBiome("City")
	check("city has marks", #city >= 10)
	local forest = DecalsConfig.forBiome("Forest")
	for _, entry in forest do
		check("forest only blood", string.find(entry.key, "blood") ~= nil, entry.key)
	end
	for _, entry in DecalsConfig.entries do
		check(entry.key .. " layer", entry.layer >= 1 and entry.layer <= 3)
		check(entry.key .. " count", entry.count[1] <= entry.count[2])
		check(entry.key .. " zone", entry.zone == "lane" or entry.zone == "shoulder" or entry.zone == "edge" or entry.zone == "wall" or entry.zone == "floor")
		if entry.zone == "floor" then
			check(entry.key .. " tile", entry.tile ~= nil)
		end
	end
end)

group("budget", function()
	local counts = ChunkBudget.newCounts()
	counts.parts = 250
	counts.meshes = { tree_oak = 10, unknown_prop = 4 }
	counts.primitives = { Block = 200, Wedge = 10, Cylinder = 5, Ball = 5 }
	counts.instances = 400
	counts.decals = 7
	counts.lights = 5
	counts.shadows = 40
	local report = ChunkBudget.report(DressingConfig, counts)
	check("tris from meshes and primitives", report.triangles == 10 * 3918 + 4 * 1500 + 200 * 12 + 10 * 8 + 5 * 96 + 5 * 96, tostring(report.triangles))
	local overDesktop = ChunkBudget.over(report, DressingConfig.budgets.desktop)
	check("desktop fine", #overDesktop == 0, table.concat(overDesktop, ","))
	local overMobile = ChunkBudget.over(report, DressingConfig.budgets.mobile)
	check("mobile over parts, instances, decals, lights, shadows", table.concat(overMobile, ",") == "parts,instances,decals,lights,shadows", table.concat(overMobile, ","))
	local line = ChunkBudget.format("City", report, DressingConfig.budgets.desktop, DressingConfig.budgets.mobile)
	check("line names the biome", string.find(line, "^%[Chunk City%]") ~= nil, line)
	check("line lists mobile overs", string.find(line, "over mobile: parts", 1, true) ~= nil, line)
	check("line has no desktop overs", string.find(line, "over desktop", 1, true) == nil, line)
	check("thousands", string.find(line, "tris 49k/320k", 1, true) ~= nil, line)
end)

group("fog budget", function()
	-- GameConstants.SPAWN_AHEAD_DISTANCE, CHUNK_LENGTH and the streaming radius in default.project.json
	local constants = { spawnAhead = 768, chunkLength = 128, streamingRadius = VisibilityConfig.STREAMING_TARGET_RADIUS, streamingMargin = VisibilityConfig.STREAMING_MARGIN }
	local issues = FogBudget.checkAll(VisibilityConfig.visibility, VisibilityConfig.exempt, constants)
	check("every preset fits", #issues == 0, table.concat(issues, "; "))
	check("sandbox is exempt", VisibilityConfig.exempt.Sandbox == true and VisibilityConfig.visibility.Sandbox + 128 > 768)
	check("too far", #FogBudget.check("X", 700, constants, false) == 1)
	check("exempt", #FogBudget.check("X", 700, constants, true) == 0)
	check("radius too small", #FogBudget.checkStreaming({ spawnAhead = 768, chunkLength = 128, streamingRadius = 900, streamingMargin = 64 }) == 1)
	for _, biome in BIOMES do
		check(biome .. " has visibility", VisibilityConfig.visibility[biome] ~= nil)
		check(biome .. " night has visibility", VisibilityConfig.visibility[biome .. "Night"] ~= nil)
		check(biome .. " night sees less", VisibilityConfig.visibility[biome .. "Night"] < VisibilityConfig.visibility[biome])
	end
end)

if failures > 0 then
	print(string.format("%d check(s) failed", failures))
	error("world tests failed")
end
print("all world tests passed")
