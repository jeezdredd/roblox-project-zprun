--!strict

-- Pure tests for the weapon pickups: seeded placement, the highlight pool and the
-- supply drop roll. Run from the repository root with the standalone Luau CLI:
--   luau tests/pickups/run.luau
-- One line per group; the run exits non-zero when any check failed.

local PickupScenesConfig = require("../../src/shared/config/PickupScenesConfig")
local PickupPlanner = require("../../src/shared/world/PickupPlanner")
local HighlightBudget = require("../../src/shared/util/HighlightBudget")
local WeaponsConfig = require("../../src/shared/config/WeaponsConfig")

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
local function makeRng(seed: number): PickupPlanner.Rng
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

local C = PickupScenesConfig :: any
local OPTIONS: PickupPlanner.Options = { halfLength = 64, halfWidth = 30 }
local BIOMES = { "City", "Forest", "Wasteland", "Farmstead", "Cornfield" }

local function planFor(biome: string, index: number, seed: number): { PickupPlanner.Placement }
	return PickupPlanner.plan(C, biome, index, makeRng(seed * 7919 + index), OPTIONS)
end

local function signature(placements: { PickupPlanner.Placement }): string
	local parts = {}
	for _, placement in placements do
		local spots = {}
		for _, spot in placement.spots do
			table.insert(spots, string.format("%.3f,%.3f,%.3f", spot.x, spot.z, spot.yaw))
		end
		table.insert(parts, string.format("%s:%s:%s", placement.kind, placement.sceneId or "-", table.concat(spots, ";")))
	end
	return table.concat(parts, "|")
end

group("config", function()
	for _, id in PickupScenesConfig.order do
		local scene = PickupScenesConfig.get(id)
		check(id .. " exists", scene ~= nil)
		if scene then
			check(id .. " id matches", scene.id == id)
			check(id .. " has parts", #scene.parts > 0)
			check(id .. " has a weight", scene.weight > 0 and scene.radius > 0)
			if scene.enabled then
				check(id .. " names a real weapon", WeaponsConfig.get(scene.weaponId) ~= nil, scene.weaponId)
				check(id .. " has a weapon prop", PickupScenesConfig.weaponProps[scene.weaponId] ~= nil)
			end
		end
	end
	local sawmill = PickupScenesConfig.get("Sawmill")
	check("chainsaw scene is a config entry only", sawmill ~= nil and not sawmill.enabled and sawmill.weaponId == "Chainsaw")
	check("no melee weapon exists", WeaponsConfig.get("Chainsaw") == nil)
	for _, id in PickupScenesConfig.supplyDrop.order do
		check("drop weapon " .. id .. " exists", WeaponsConfig.get(id) ~= nil)
		check("drop weapon " .. id .. " weighted", (PickupScenesConfig.supplyDrop.weights[id] or 0) > 0)
	end
	for _, biome in BIOMES do
		check(biome .. " has a density", PickupScenesConfig.density[biome] ~= nil)
		check(biome .. " has a drop chance", PickupScenesConfig.supplyDrop.chance[biome] ~= nil)
	end
	check("highlight budget under the renderer's 31", PickupScenesConfig.HIGHLIGHT_BUDGET <= 30 and PickupScenesConfig.HIGHLIGHT_BUDGET > 0)
	check("hold is 0.3 s", PickupScenesConfig.HOLD_DURATION == 0.3)
	check("server accepts from further than the prompt shows", PickupScenesConfig.PICKUP_DISTANCE >= PickupScenesConfig.PROMPT_DISTANCE)
	check("drop cost is run credits", PickupScenesConfig.supplyDrop.cost > 0)
	check("drop smoke is red", PickupScenesConfig.supplyDrop.smoke[1] > 200 and PickupScenesConfig.supplyDrop.smoke[2] < 100)
end)

group("weighted pick", function()
	local order = { "A", "B", "C" }
	local weights = { A = 1, B = 2, C = 1 }
	check("unit 0 is the first", PickupPlanner.weightedPick(order, weights, 0) == "A")
	check("just past the first", PickupPlanner.weightedPick(order, weights, 0.26) == "B")
	check("the middle", PickupPlanner.weightedPick(order, weights, 0.5) == "B")
	check("the last band", PickupPlanner.weightedPick(order, weights, 0.8) == "C")
	check("unit 1 clamps to the last", PickupPlanner.weightedPick(order, weights, 1) == "C")
	check("zero weight never wins", PickupPlanner.weightedPick(order, { A = 0, B = 1, C = 0 }, 0) == "B" and PickupPlanner.weightedPick(order, { A = 0, B = 1, C = 0 }, 0.99) == "B")
	check("missing weight never wins", PickupPlanner.weightedPick(order, { B = 1 }, 0.5) == "B")
	check("all zero is nil", PickupPlanner.weightedPick(order, { A = 0 }, 0.5) == nil)
	check("empty order is nil", PickupPlanner.weightedPick({}, weights, 0.5) == nil)
	-- the proportions over a sweep
	local counts: { [string]: number } = { Shotgun = 0, SMG = 0, Rifle = 0, Pistol = 0 }
	local sweep = 1200
	for i = 0, sweep - 1 do
		local id = PickupPlanner.rollDrop(C, i / sweep) :: string
		counts[id] += 1
	end
	check("shotgun 4 of 12", counts.Shotgun == 400, tostring(counts.Shotgun))
	check("smg 4 of 12", counts.SMG == 400, tostring(counts.SMG))
	check("rifle 3 of 12", counts.Rifle == 300, tostring(counts.Rifle))
	check("pistol 1 of 12", counts.Pistol == 100, tostring(counts.Pistol))
end)

group("scene choice", function()
	check("chainsaw never allowed", table.find(PickupPlanner.allowedScenes(C, "Forest"), "Sawmill") == nil)
	check("police car not in the forest", table.find(PickupPlanner.allowedScenes(C, "Forest"), "PoliceCar") == nil)
	check("police car in the city", table.find(PickupPlanner.allowedScenes(C, "City"), "PoliceCar") ~= nil)
	check("fence post not in the city", table.find(PickupPlanner.allowedScenes(C, "City"), "FencePost") == nil)
	check("dead soldier everywhere", table.find(PickupPlanner.allowedScenes(C, "Cornfield"), "DeadSoldier") ~= nil)
	check("dead soldier even on the moon", PickupPlanner.chooseScene(C, "Moon", makeRng(1)) == "DeadSoldier")
	local restricted = table.clone(C)
	restricted.order = { "PoliceCar", "Sawmill" }
	check("none allowed is nil", PickupPlanner.chooseScene(restricted, "Forest", makeRng(1)) == nil)
	local seen: { [string]: boolean } = {}
	for seed = 1, 200 do
		local id = PickupPlanner.chooseScene(C, "City", makeRng(seed))
		if id then
			seen[id] = true
		end
	end
	check("city rolls every allowed scene", seen.DeadSoldier and seen.PoliceCar and seen.Checkpoint and not seen.FencePost and not seen.Sawmill)
end)

group("seeded placement", function()
	check("same seed, same plan", signature(planFor("City", 5, 42)) == signature(planFor("City", 5, 42)))
	local differs = false
	for index = 2, 12 do
		if signature(planFor("City", index, 42)) ~= signature(planFor("City", index, 43)) then
			differs = true
		end
	end
	check("another seed differs somewhere", differs)
	check("nothing in the first chunks", #planFor("City", 0, 42) == 0 and #planFor("City", 1, 42) == 0)

	local sceneChunks, dropChunks, total = 0, 0, 0
	for seed = 1, 60 do
		for index = 2, 40 do
			total += 1
			for _, placement in planFor("City", index, seed) do
				check("candidates per placement", #placement.spots == PickupScenesConfig.CANDIDATES)
				if placement.kind == "Scene" then
					sceneChunks += 1
					local rule = PickupScenesConfig.get(placement.sceneId :: string)
					check("scene is allowed in the city", rule ~= nil and PickupScenesConfig.allowedIn(rule :: any, "City"))
					check("scene radius from config", rule ~= nil and placement.radius == rule.radius)
					for _, spot in placement.spots do
						local inset = OPTIONS.halfWidth - math.abs(spot.x)
						check("scene on the shoulder", inset >= PickupScenesConfig.SHOULDER_INSET[1] - 1e-6 and inset <= PickupScenesConfig.SHOULDER_INSET[2] + 1e-6, tostring(spot.x))
						check("scene clear of the chunk ends", math.abs(spot.z) <= OPTIONS.halfLength - PickupScenesConfig.END_CLEARANCE + 1e-6)
						local facing = if spot.x > 0 then math.pi / 2 else -math.pi / 2
						check("scene faces the road", math.abs(spot.yaw - facing) <= math.rad(PickupScenesConfig.YAW_JITTER) + 1e-6)
					end
				else
					dropChunks += 1
					check("drop radius from config", placement.radius == PickupScenesConfig.supplyDrop.radius)
					for _, spot in placement.spots do
						check("drop in the lane", math.abs(spot.x) <= OPTIONS.halfWidth * PickupScenesConfig.DROP_LANE_FRACTION + 1e-6)
						check("drop clear of the chunk ends", math.abs(spot.z) <= OPTIONS.halfLength - PickupScenesConfig.END_CLEARANCE + 1e-6)
					end
				end
			end
		end
	end
	local sceneRate = sceneChunks / total
	local dropRate = dropChunks / total
	check("scene rate near the city density", math.abs(sceneRate - PickupScenesConfig.density.City) < 0.06, string.format("%.3f", sceneRate))
	check("drop rate near the city chance", math.abs(dropRate - PickupScenesConfig.supplyDrop.chance.City) < 0.04, string.format("%.3f", dropRate))

	-- a biome with no density and no drops places nothing
	local quiet = table.clone(C)
	quiet.density = { City = 0 }
	quiet.supplyDrop = table.clone(C.supplyDrop)
	quiet.supplyDrop.chance = { City = 0 }
	check("zero density places nothing", #PickupPlanner.plan(quiet, "City", 10, makeRng(3), OPTIONS) == 0)

	-- a biome that always gets both keeps the drop away from the scene's first spot
	local busy = table.clone(C)
	busy.density = { City = 1 }
	busy.supplyDrop = table.clone(C.supplyDrop)
	busy.supplyDrop.chance = { City = 1 }
	for seed = 1, 80 do
		local placements = PickupPlanner.plan(busy, "City", 10, makeRng(seed), OPTIONS)
		check("both placed", #placements == 2 and placements[1].kind == "Scene" and placements[2].kind == "Drop")
		if #placements == 2 then
			local sceneZ = placements[1].spots[1].z
			for _, spot in placements[2].spots do
				check("drop keeps its gap from the scene", math.abs(spot.z - sceneZ) >= PickupScenesConfig.SCENE_DROP_GAP - 1e-6 or math.abs(spot.z) >= OPTIONS.halfLength - PickupScenesConfig.END_CLEARANCE - 1e-6)
			end
		end
	end
end)

group("highlight pool", function()
	local function candidates(n: number, spread: number): { HighlightBudget.Candidate }
		local list = {}
		for i = 1, n do
			table.insert(list, { id = "s" .. i, distance = i * spread })
		end
		return list
	end
	local first = HighlightBudget.assign(candidates(40, 10), 24, {}, 6)
	local kept = 0
	for _ in first.keep do
		kept += 1
	end
	check("budget respected", kept == 24 and #first.acquire == 24 and #first.release == 0)
	check("nearest first", first.acquire[1] == "s1" and first.keep.s24 and not first.keep.s25)
	check("fewer than the budget all get one", (function()
		local a = HighlightBudget.assign(candidates(5, 10), 24, {}, 6)
		return #a.acquire == 5
	end)())

	-- the player moves on: the far ones hand theirs back
	local held: { [string]: boolean } = {}
	for id in first.keep do
		held[id] = true
	end
	local moved = {}
	for i = 1, 40 do
		table.insert(moved, { id = "s" .. i, distance = math.abs(i - 30) * 10 })
	end
	local second = HighlightBudget.assign(moved, 24, held, 6)
	check("far scenes release", table.find(second.release, "s1") ~= nil and table.find(second.release, "s2") ~= nil)
	check("scenes ahead acquire", table.find(second.acquire, "s30") ~= nil and table.find(second.acquire, "s40") ~= nil)
	local keptSecond = 0
	for _ in second.keep do
		keptSecond += 1
	end
	check("budget still respected", keptSecond == 24)
	check("held near ones stay", second.keep.s24 and table.find(second.acquire, "s24") == nil)

	-- hysteresis: a held scene keeps its slot against a rival inside the margin
	local held2 = { a = true }
	local tie = HighlightBudget.assign({ { id = "a", distance = 12 }, { id = "b", distance = 8 } }, 1, held2, 6)
	check("held wins inside the margin", tie.keep.a and not tie.keep.b and #tie.acquire == 0 and #tie.release == 0)
	local clear = HighlightBudget.assign({ { id = "a", distance = 12 }, { id = "b", distance = 4 } }, 1, held2, 6)
	check("a much closer rival takes it", clear.keep.b and not clear.keep.a and clear.acquire[1] == "b" and clear.release[1] == "a")

	-- a zero budget releases everything
	local none = HighlightBudget.assign({ { id = "a", distance = 1 } }, 0, { a = true }, 6)
	check("zero budget releases", next(none.keep) == nil and none.release[1] == "a")
	-- a scene that vanished (taken) releases too
	local gone = HighlightBudget.assign({ { id = "b", distance = 1 } }, 24, { a = true }, 6)
	check("vanished scene releases", gone.release[1] == "a" and gone.keep.b)
	-- duplicates never double count
	local dup = HighlightBudget.assign({ { id = "a", distance = 1 }, { id = "a", distance = 2 }, { id = "b", distance = 3 } }, 2, {}, 6)
	check("duplicate ids count once", dup.keep.a and dup.keep.b and #dup.acquire == 2)
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all pickup tests passed")
