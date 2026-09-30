--!strict

-- Pure tests for the upgrade station: the price ladder, the quote and its refusals,
-- the seeded placement. Run from the repository root with the standalone Luau CLI:
--   luau tests/upgrade/run.luau
-- One line per group; the run exits non-zero when any check failed.

local UpgradeStationConfig = require("../../src/shared/config/UpgradeStationConfig")
local UpgradeStationMath = require("../../src/shared/world/UpgradeStationMath")
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
local function makeRng(seed: number): UpgradeStationMath.Rng
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

local L = WeaponsConfig :: any
local C = UpgradeStationConfig :: any
local CHUNK = 128
local START = 64

local function optionsFor(index: number): UpgradeStationMath.Options
	return { halfLength = CHUNK / 2, halfWidth = 30, chunkStart = START + index * CHUNK }
end

group("price ladder", function()
	check("level 1 to 2", UpgradeStationMath.priceFor(L, 1) == 400 and WeaponsConfig.upgradePrice(1) == 400)
	check("level 2 to 3", UpgradeStationMath.priceFor(L, 2) == 750)
	check("level 3 to 4", UpgradeStationMath.priceFor(L, 3) == 1100)
	check("level 4 to 5", UpgradeStationMath.priceFor(L, 4) == 1450)
	for level = 1, WeaponsConfig.MAX_LEVEL do
		check("matches the Gunsmith at L" .. level, UpgradeStationMath.priceFor(L, level) == WeaponsConfig.upgradePrice(level))
	end
	check("below one is level one's price", UpgradeStationMath.priceFor(L, 0) == 400)
	local rifle = WeaponsConfig.get("Rifle") :: WeaponsConfig.WeaponConfig
	check("damage scale matches damageAt", math.abs(UpgradeStationMath.damageScale(L, 3) * rifle.damage - WeaponsConfig.damageAt(rifle, 3)) < 1e-9)
	check("damage scale at one is one", UpgradeStationMath.damageScale(L, 1) == 1)
	check("damage scale clamps at max", UpgradeStationMath.damageScale(L, 9) == UpgradeStationMath.damageScale(L, WeaponsConfig.MAX_LEVEL))
end)

group("quote", function()
	local q = UpgradeStationMath.quote(L, 1)
	check("level one buys two", q.ok and q.level == 2 and q.price == 400 and q.reason == nil)
	q = UpgradeStationMath.quote(L, 4, 1450)
	check("exactly enough", q.ok and q.level == 5 and q.price == 1450)
	q = UpgradeStationMath.quote(L, 4, 1449)
	check("too poor refuses with the price", not q.ok and q.price == 1450 and q.reason == "Need 1450 CR")
	q = UpgradeStationMath.quote(L, WeaponsConfig.MAX_LEVEL, 99999)
	check("max level refuses", not q.ok and q.price == 0 and q.reason ~= nil and string.find(q.reason :: string, "top") ~= nil)
	q = UpgradeStationMath.quote(L, 9, 99999)
	check("above max refuses too", not q.ok)
	q = UpgradeStationMath.quote(L, 0, 400)
	check("level zero reads as one", q.ok and q.level == 2)
	q = UpgradeStationMath.quote(L, 2.7, 750)
	check("fractional level floors", q.ok and q.level == 3 and q.price == 750)
end)

group("station chunks", function()
	local has: { number } = {}
	for index = 0, 40 do
		if UpgradeStationMath.chunkHasStation(C, "City", START + index * CHUNK, CHUNK) then
			table.insert(has, index)
		end
	end
	-- multiples of 640 from 640 on: 640 is in chunk 4 (576..704), 1280 in chunk 9
	-- (1216..1344), 1920 in chunk 14, 2560 in chunk 19, 3200 in chunk 24, ...
	check("one chunk per spacing", table.concat(has, ",") == "4,9,14,19,24,29,34,39", table.concat(has, ","))
	check("nothing before the clearance", not UpgradeStationMath.chunkHasStation(C, "City", 0, CHUNK) and not UpgradeStationMath.chunkHasStation(C, "City", 320, CHUNK))
	check("forest never", not UpgradeStationMath.chunkHasStation(C, "Forest", START + 4 * CHUNK, CHUNK))
	check("cornfield never", not UpgradeStationMath.chunkHasStation(C, "Cornfield", START + 4 * CHUNK, CHUNK))
	check("wasteland yes", UpgradeStationMath.chunkHasStation(C, "Wasteland", START + 9 * CHUNK, CHUNK))
	-- a mark exactly on a chunk's near edge belongs to that chunk, not the one before
	check("mark on the edge belongs to the chunk starting there", UpgradeStationMath.chunkHasStation(C, "City", 640, 128) and not UpgradeStationMath.chunkHasStation(C, "City", 512, 128))
	-- a mark before the clearance is skipped, one at the clearance counts
	local tight = table.clone(C)
	tight.START_CLEARANCE_STUDS = 700
	check("a mark under the clearance is skipped", not UpgradeStationMath.chunkHasStation(tight, "City", 576, 128) and UpgradeStationMath.chunkHasStation(tight, "City", 1216, 128))
	tight.START_CLEARANCE_STUDS = 640
	check("a mark at the clearance counts", UpgradeStationMath.chunkHasStation(tight, "City", 576, 128))
end)

group("seeded placement", function()
	local function signature(spots: { UpgradeStationMath.Spot }): string
		local parts = {}
		for _, spot in spots do
			table.insert(parts, string.format("%.3f,%.3f,%.3f", spot.x, spot.z, spot.yaw))
		end
		return table.concat(parts, ";")
	end
	local a = UpgradeStationMath.plan(C, "City", makeRng(42), optionsFor(4))
	local b = UpgradeStationMath.plan(C, "City", makeRng(42), optionsFor(4))
	check("same seed, same spots", #a == UpgradeStationConfig.CANDIDATES and signature(a) == signature(b))
	check("another seed differs", signature(UpgradeStationMath.plan(C, "City", makeRng(43), optionsFor(4))) ~= signature(a))
	check("a chunk without a station has no spots", #UpgradeStationMath.plan(C, "City", makeRng(42), optionsFor(5)) == 0)
	check("a forest chunk has none", #UpgradeStationMath.plan(C, "Forest", makeRng(42), optionsFor(4)) == 0)
	for seed = 1, 60 do
		for _, spot in UpgradeStationMath.plan(C, "Wasteland", makeRng(seed), optionsFor(9)) do
			local inset = 30 - math.abs(spot.x)
			check("on the shoulder", inset >= UpgradeStationConfig.SHOULDER_INSET[1] - 1e-6 and inset <= UpgradeStationConfig.SHOULDER_INSET[2] + 1e-6, tostring(spot.x))
			check("clear of the chunk ends", math.abs(spot.z) <= CHUNK / 2 - UpgradeStationConfig.END_CLEARANCE + 1e-6)
			local facing = if spot.x > 0 then math.pi / 2 else -math.pi / 2
			check("faces the road", math.abs(spot.yaw - facing) <= math.rad(UpgradeStationConfig.YAW_JITTER) + 1e-6)
		end
	end
	check("the station radius covers the bench and the generator", UpgradeStationConfig.RADIUS >= 7)
	check("prompt inside the server's reach", UpgradeStationConfig.USE_DISTANCE >= UpgradeStationConfig.PROMPT_DISTANCE)
	check("announcer lines named", #UpgradeStationConfig.ANNOUNCER_UPGRADE >= 1 and UpgradeStationConfig.ANNOUNCER_MAX ~= "")
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all upgrade tests passed")
