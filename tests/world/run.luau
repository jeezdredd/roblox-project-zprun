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
local MapsConfig = require("../../src/shared/config/MapsConfig")
local MapMath = require("../../src/shared/world/MapMath")

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

-- Map segments (wiki: Map Segments) --------------------------------------------------

-- GameConstants and LocationsConfig hold engine types, so their numbers are mirrored
-- here; the "constants mirror" group keeps the mirror honest where it can
local CONSTANTS: MapMath.Constants = {
	chunkLength = 128,
	spawnAhead = 768,
	baseSpeed = 24,
	maxSpeed = 60,
	floorFactor = MapsConfig.FLOOR_FACTOR,
	-- ForkConfig.FIRST_DIVIDER_AT + DIVIDER_LENGTH + VOTE_LEAD
	forkSpan = 300 + 384 + 638,
}
local LOCATIONS = { City = true, Forest = true, Wasteland = true, Farmstead = true, Cornfield = true }
local MAPS = MapsConfig.maps :: any

local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-6)
end

group("maps: the table", function()
	local problems = MapMath.check(MAPS, LOCATIONS)
	check("no problems", #problems == 0, table.concat(problems, "; "))
	check("today's content enabled", MapsConfig.isValid("City") and MapsConfig.isValid("Wasteland") and MapsConfig.isValid("Forest") and MapsConfig.isValid("Farmland"))
	for _, id in { "Suburbs", "Highway", "Desert", "Mountains", "Swamp" } do
		check(id .. " is planned but disabled", MAPS[id] ~= nil and not MapsConfig.isValid(id))
	end
	check("Random is selectable, a disabled map is not", MapsConfig.isSelectable("Random") and not MapsConfig.isSelectable("Desert"))
	check("Farmland mixes Farmstead and Cornfield", #MAPS.Farmland.locationIds == 2)
	check("never city straight into desert", not table.find(MAPS.City.neighbours, "Desert") and not table.find(MAPS.Desert.neighbours, "City"))
	check("default durations 120 to 180 s", MapsConfig.DEFAULT_DURATION.min == 120 and MapsConfig.DEFAULT_DURATION.max == 180)
	check("map transition is 5 chunks", MapsConfig.MAP_TRANSITION_CHUNKS == 5)
	local broken = {
		A = { id = "A", enabled = true, locationIds = { "City" }, durationSeconds = { min = 10, max = 5 }, neighbours = { "B", "Nope" }, preloadSeconds = 1 },
		B = { id = "B", enabled = true, locationIds = {}, durationSeconds = { min = 1, max = 2 }, neighbours = {}, preloadSeconds = 1 },
	}
	check("a broken table is reported", #MapMath.check(broken :: any, LOCATIONS) >= 5, tostring(#MapMath.check(broken :: any, LOCATIONS)))
end)

group("maps: speed and distance", function()
	check("constant speed", MapMath.speedAt(nil, 24, 60, 100) == 24)
	local ramp: MapMath.SpeedProfile = { initial = 24, max = 48, rampTime = 60 }
	check("ramp start", MapMath.speedAt(ramp, 24, 60, 0) == 24)
	check("ramp middle", near(MapMath.speedAt(ramp, 24, 60, 30), 36))
	check("ramp end holds", MapMath.speedAt(ramp, 24, 60, 300) == 48)
	check("capped at the top speed", MapMath.speedAt({ initial = 80 }, 24, 60, 0) == 60)
	check("constant distance is exact", MapMath.distanceOver(nil, 24, 60, 0, 150) == 3600)
	-- 0..60 s ramp 24 -> 48 is 2160 studs, then 30 s at 48 is 1440
	check("ramp distance", near(MapMath.distanceOver(ramp, 24, 60, 0, 90), 3600, 2), tostring(MapMath.distanceOver(ramp, 24, 60, 0, 90)))
	check("later in the run is faster", MapMath.distanceOver(ramp, 24, 60, 60, 60) > MapMath.distanceOver(ramp, 24, 60, 0, 60))
end)

group("maps: lengths and the floor", function()
	-- the owner's floor: spawn distance + top speed x the next map's build time x 1.5
	check("floor from the preload", near(MapMath.floorLength(CONSTANTS, 8), 768 + 60 * 8 * 1.5))
	check("floor never under the fork's own span", MapMath.floorLength(CONSTANTS, 0) == CONSTANTS.forkSpan)
	local city = MAPS.City
	check("120 s at 24 studs/s is 23 chunks", MapMath.lengthChunks(CONSTANTS, city, 0, 120, 6) == 23)
	check("180 s at 24 studs/s is 34 chunks", MapMath.lengthChunks(CONSTANTS, city, 0, 180, 6) == 34)
	check("a short duration stops at the floor", MapMath.lengthChunks(CONSTANTS, city, 0, 5, 8) == math.ceil((768 + 720) / 128))
	local fast = table.clone(city)
	fast.speed = { initial = 60 }
	check("at 60 studs/s the same minutes are longer", MapMath.lengthChunks(CONSTANTS, fast, 0, 120, 6) == math.ceil(7200 / 128))
	check("duration from the roll", MapMath.duration(city, 0) == 120 and MapMath.duration(city, 1) == 180 and MapMath.duration(city, 0.5) == 150)
end)

group("maps: forks between neighbours", function()
	for id, map in MAPS do
		if not map.enabled then
			continue
		end
		local enabled = MapMath.enabledNeighbours(MAPS, id)
		check(id .. " has two enabled neighbours", #enabled >= 2, tostring(#enabled))
		for _, roll in { 0, 0.2, 0.5, 0.8, 0.999 } do
			for _, roll2 in { 0, 0.5, 0.999 } do
				local options = MapMath.forkOptions(MAPS, id, roll, roll2)
				if not options then
					check(id .. " forks", false)
				else
					check(id .. " options differ", options[1] ~= options[2])
					for _, option in options do
						check(id .. " -> " .. option .. " is a neighbour", table.find(map.neighbours, option) ~= nil)
						check(id .. " -> " .. option .. " is enabled", MAPS[option].enabled)
						check(id .. " -> " .. option .. " is not itself", option ~= id)
					end
				end
			end
		end
	end
	local lonely = { A = { id = "A", enabled = true, locationIds = { "City" }, durationSeconds = { min = 1, max = 2 }, neighbours = { "B" }, preloadSeconds = 1 }, B = { id = "B", enabled = true, locationIds = { "City" }, durationSeconds = { min = 1, max = 2 }, neighbours = { "A" }, preloadSeconds = 1 } }
	check("one neighbour cannot fork", MapMath.forkOptions(lonely :: any, "A", 0.3, 0.3) == nil)
end)

group("maps: sub-locations and the start", function()
	local farmland = MAPS.Farmland
	for _, roll in { 0, 0.4, 0.99 } do
		check("no sub-location twice running", MapMath.nextLocation(farmland, "Farmstead", roll) == "Cornfield")
	end
	check("a one-location map repeats", MapMath.nextLocation(MAPS.City, "City", 0.5) == "City")
	check("a chosen map starts", MapMath.startMap(MAPS, MapsConfig.order, "Forest", 0.9) == "Forest")
	local enabled = MapsConfig.enabledIds()
	for _, roll in { 0, 0.3, 0.6, 0.999 } do
		local id = MapMath.startMap(MAPS, MapsConfig.order, "Random", roll)
		check("Random starts on an enabled map", id ~= nil and table.find(enabled, id) ~= nil, tostring(id))
	end
	check("a disabled choice falls back to an enabled map", MapsConfig.isValid(MapMath.startMap(MAPS, MapsConfig.order, "Desert", 0.1) :: string))
end)

group("maps: transitions", function()
	local n = MapsConfig.MAP_TRANSITION_CHUNKS
	check("first chunk a sixth in", near(MapMath.transitionAlpha(0, n) :: number, 1 / 6))
	check("last chunk five sixths in", near(MapMath.transitionAlpha(n - 1, n) :: number, 5 / 6))
	check("outside the transition", MapMath.transitionAlpha(n, n) == nil and MapMath.transitionAlpha(-1, n) == nil)
	local previous = 0
	for k = 0, n - 1 do
		local alpha = MapMath.transitionAlpha(k, n) :: number
		check("alpha rises at chunk " .. k, alpha > previous)
		previous = alpha
	end
	check("zone before", MapMath.zoneAlpha(90, 100, 740) == 0)
	check("zone after", MapMath.zoneAlpha(800, 100, 740) == 1)
	check("zone middle", near(MapMath.zoneAlpha(420, 100, 740), 0.5))
	for _, a in { 0, 0.25, 0.5, 0.75, 1 } do
		local old, new = MapMath.crossfade(a)
		check("equal power at " .. a, near(old * old + new * new, 1))
	end
	local old, new = MapMath.crossfade(0)
	check("crossfade ends", near(old, 1) and near(new, 0))
end)

group("maps: vote lead", function()
	local widest = MapMath.maxVisibility(VisibilityConfig.visibility, VisibilityConfig.exempt)
	check("widest run fog is Wasteland's 420", widest == 420, tostring(widest))
	local lead = MapMath.voteLead(widest, 128, 60, 1.5)
	check("lead 638 studs", lead == 638, tostring(lead))
	check("closer than the old 1024", lead < 768 + 2 * 128)
	check("the held boundary stays out of sight", lead > widest + 128)
end)

group("maps: pools freed two steps behind", function()
	-- City, then Wasteland, now Forest with Farmland and City as options: nothing of
	-- City goes (an option), Wasteland stays (one step behind)
	check("an option keeps its pools", #MapMath.poolsToFree(MAPS, { "City", "Wasteland", "Forest" }, { "Farmland", "City" }) == 0)
	local freed = MapMath.poolsToFree(MAPS, { "City", "Wasteland", "Forest" }, { "Farmland", "Wasteland" })
	check("two steps behind frees", #freed == 1 and freed[1] == "City", table.concat(freed, ","))
	local farm = MapMath.poolsToFree(MAPS, { "Farmland", "Forest", "Wasteland", "City" }, { "Wasteland", "Forest" })
	check("both farm locations go", #farm == 2 and table.find(farm, "Farmstead") ~= nil and table.find(farm, "Cornfield") ~= nil, table.concat(farm, ","))
	check("short history frees nothing", #MapMath.poolsToFree(MAPS, { "City", "Forest" }, {}) == 0)
end)

group("dressing density", function()
	local function count(density: number?): number
		ChunkOccupancy.reset()
		return #DressingPlanner.plan(DressingConfig, "City", makeRng(77), ChunkOccupancy, {
			halfLength = HALF,
			groups = groupsFor(),
			sizes = allSizes(),
			density = density,
		})
	end
	local full = count(nil)
	check("density 1 is the full plan", count(1) == full)
	check("density 0 places nothing", count(0) == 0)
	check("half density places fewer", count(0.5) < full and count(0.5) > 0, `{count(0.5)} of {full}`)
end)

if failures > 0 then
	print(string.format("%d check(s) failed", failures))
	error("world tests failed")
end
print("all world tests passed")
