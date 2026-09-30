--!strict

-- Pure tests for the goals HUD and the Gunsmith ladder text. Run from the repository
-- root with the standalone Luau CLI:  luau tests/goals/run.luau
-- One line per group; the run exits non-zero when any check failed.

local MissionGoalsConfig = require("../../src/shared/config/MissionGoalsConfig")
local WeaponsConfig = require("../../src/shared/config/WeaponsConfig")
local GoalsHudMath = require("../../src/shared/util/GoalsHudMath")
local WeaponLadderText = require("../../src/shared/util/WeaponLadderText")

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

local G = MissionGoalsConfig :: any
local L = WeaponsConfig :: any

group("goal progress round trip", function()
	local encoded = GoalsHudMath.encode(G, { Distance = 320.7, Kills = 4, CleanDistance = 120 })
	check("config order, floored", encoded == "Distance1500=320;Kills25=4;NoDamage500=120", encoded)
	local values = GoalsHudMath.decode(encoded)
	check("decodes every goal", values.Distance1500 == 320 and values.Kills25 == 4 and values.NoDamage500 == 120)
	check("missing metric reads zero", GoalsHudMath.encode(G, {}) == "Distance1500=0;Kills25=0;NoDamage500=0")
	check("negative clamps to zero", GoalsHudMath.encode(G, { Distance = -5 }) == "Distance1500=0;Kills25=0;NoDamage500=0")
	check("empty string decodes to nothing", next(GoalsHudMath.decode("")) == nil)
	local junk = GoalsHudMath.decode("Distance1500=12;garbage;Kills25=x;=3;NoDamage500=7")
	check("malformed pairs are skipped", junk.Distance1500 == 12 and junk.Kills25 == nil and junk.NoDamage500 == 7)
	check("same progress, same string", GoalsHudMath.encode(G, { Distance = 320.2, Kills = 4 }) == GoalsHudMath.encode(G, { Distance = 320.9, Kills = 4 }))
end)

group("goal rows", function()
	local rows = GoalsHudMath.rows(G, { Distance1500 = 320, Kills25 = 25, NoDamage500 = 900 })
	check("three rows in order", #rows == 3 and rows[1].id == "Distance1500" and rows[2].id == "Kills25" and rows[3].id == "NoDamage500")
	check("progress text", rows[1].text == "320 / 1500" and not rows[1].done)
	check("done at target", rows[2].text == "25 / 25" and rows[2].done)
	check("clamped over target", rows[3].value == 500 and rows[3].text == "500 / 500" and rows[3].done)
	check("names and rewards from config", rows[1].displayName == "Long Haul" and rows[2].rewardCredits == 300)
	local empty = GoalsHudMath.rows(G, {})
	check("no values reads zero", empty[1].text == "0 / 1500" and not empty[1].done)
	local decoded = GoalsHudMath.rows(G, GoalsHudMath.decode(GoalsHudMath.encode(G, { Kills = 7 })))
	check("encode, decode, rows", decoded[2].text == "7 / 25")
end)

group("ladder text", function()
	local rifle = WeaponsConfig.get("Rifle") :: WeaponsConfig.WeaponConfig
	local n = WeaponLadderText.number
	check("whole numbers stay whole", n(30) == "30" and n(30.04) == "30" and n(2.96) == "3")
	check("one decimal otherwise", n(32.4) == "32.4" and n(2.45) == "2.5")
	for level = 1, WeaponsConfig.MAX_LEVEL do
		check("damage matches damageAt at L" .. level, math.abs(WeaponLadderText.damageAt(L, rifle, level) - WeaponsConfig.damageAt(rifle, level)) < 1e-9)
		check("price matches upgradePrice at L" .. level, WeaponLadderText.priceFor(L, level) == WeaponsConfig.upgradePrice(level))
	end
	local unowned = WeaponLadderText.describe(L, rifle, 0)
	check("unowned keeps the class, rpm and mag", string.find(unowned, rifle.class, 1, true) ~= nil and string.find(unowned, "rpm", 1, true) ~= nil and string.find(unowned, "mag " .. rifle.magSize, 1, true) ~= nil, unowned)
	check("unowned names the ladder", string.find(unowned, "L1 of 5", 1, true) ~= nil, unowned)
	local l1 = WeaponLadderText.describe(L, rifle, 1)
	local gain = WeaponsConfig.damageAt(rifle, 2) - WeaponsConfig.damageAt(rifle, 1)
	check("L1 quotes the next level's price", string.find(l1, "next L2: 400 CR", 1, true) ~= nil, l1)
	check("L1 quotes the damage gain", string.find(l1, "+" .. n(gain) .. " dmg", 1, true) ~= nil, l1)
	check("L1 shows the damage now", string.find(l1, n(rifle.damage) .. " dmg", 1, true) ~= nil, l1)
	local l4 = WeaponLadderText.describe(L, rifle, 4)
	check("L4 quotes 1450", string.find(l4, "next L5: 1450 CR", 1, true) ~= nil, l4)
	local l5 = WeaponLadderText.describe(L, rifle, 5)
	check("max reads top of the ladder", string.find(l5, "top of the ladder", 1, true) ~= nil and string.find(l5, "next", 1, true) == nil, l5)
	check("max shows the max damage", string.find(l5, n(WeaponsConfig.damageAt(rifle, 5)) .. " dmg", 1, true) ~= nil, l5)
	check("above max reads as max", WeaponLadderText.describe(L, rifle, 9) == l5)
	for _, id in WeaponsConfig.order do
		local weapon = WeaponsConfig.get(id) :: WeaponsConfig.WeaponConfig
		for level = 0, WeaponsConfig.MAX_LEVEL do
			local text = WeaponLadderText.describe(L, weapon, level)
			check(id .. " L" .. level .. " text fits a row", #text <= 64, text)
		end
	end
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all goals tests passed")
