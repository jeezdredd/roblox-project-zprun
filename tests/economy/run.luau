--!strict

-- Pure tests for the run economy and the perk rules. Run from the repository root with
-- the standalone Luau CLI:  luau tests/economy/run.luau
-- One line per group; the run exits non-zero when any check failed.

local RunEconomyConfig = require("../../src/shared/config/RunEconomyConfig")
local RunEconomyMath = require("../../src/shared/util/RunEconomyMath")
local PerksConfig = require("../../src/shared/config/PerksConfig")

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

local C = RunEconomyConfig

group("streaks", function()
	check("first kill", RunEconomyMath.streakAfter(nil, 0, 10, C.STREAK_WINDOW) == 1)
	check("inside the window", RunEconomyMath.streakAfter(10, 1, 13, C.STREAK_WINDOW) == 2)
	check("at the window", RunEconomyMath.streakAfter(10, 3, 14, C.STREAK_WINDOW) == 4)
	check("past the window resets", RunEconomyMath.streakAfter(10, 5, 14.5, C.STREAK_WINDOW) == 1)
	check("no bonus on the first", RunEconomyMath.streakBonus(C, 1) == 0)
	check("step per position", RunEconomyMath.streakBonus(C, 3) == 2 * C.STREAK_STEP)
	check("capped", RunEconomyMath.streakBonus(C, 40) == C.STREAK_CAP)
end)

group("kill pay", function()
	check("walker", RunEconomyMath.killPay(C, "Walker", false, 1, 1) == 25)
	check("runner", RunEconomyMath.killPay(C, "Runner", false, 1, 1) == 40)
	check("unknown id is default", RunEconomyMath.killPay(C, "Boss", false, 1, 1) == C.KILL_PAY_DEFAULT)
	check("nil id is default", RunEconomyMath.killPay(C, nil, false, 1, 1) == C.KILL_PAY_DEFAULT)
	check("headshot", RunEconomyMath.killPay(C, "Walker", true, 1, 1) == 35)
	check("streak", RunEconomyMath.killPay(C, "Walker", false, 3, 1) == 35)
	check("headshot and streak", RunEconomyMath.killPay(C, "Runner", true, 6, 1) == 40 + 10 + 25)
	check("multiplier floors", RunEconomyMath.killPay(C, "Walker", false, 1, 1.5) == 37)
	check("hard pays more", RunEconomyMath.killPay(C, "Walker", false, 1, 2) == 50)
	check("zero multiplier pays nothing", RunEconomyMath.killPay(C, "Walker", true, 5, 0) == 0)
	check("negative multiplier pays nothing", RunEconomyMath.killPay(C, "Walker", true, 5, -1) == 0)
end)

group("distance", function()
	check("ten studs a credit", RunEconomyMath.distanceCredits(C, 100, 1) == 10)
	check("floored", RunEconomyMath.distanceCredits(C, 99, 1) == 9)
	check("multiplied", RunEconomyMath.distanceCredits(C, 100, 1.5) == 15)
	check("never negative", RunEconomyMath.distanceCredits(C, -50, 1) == 0)
end)

group("balance and banking", function()
	local balance = { kills = 120, distance = 45 }
	check("total", RunEconomyMath.total(balance) == 165)
	local banked, rest = RunEconomyMath.bank(balance)
	check("bank pays everything", banked == 165)
	check("bank leaves nothing", rest.kills == 0 and rest.distance == 0)
	check("bank of nothing", RunEconomyMath.bank({ kills = 0, distance = 0 }) == 0)
end)

group("perk prices and values", function()
	local perk = PerksConfig.get("Toughness") :: PerksConfig.PerkConfig
	check("level 1 price", PerksConfig.priceFor(perk, 0) == 400)
	check("level 3 price", PerksConfig.priceFor(perk, 2) == 1600)
	check("max has no price", PerksConfig.priceFor(perk, 3) == nil)
	check("value at 2", PerksConfig.valueAt(perk, 2) == 30)
	check("value at 0 is nil", PerksConfig.valueAt(perk, 0) == nil)
	check("value clamps high", PerksConfig.valueAt(perk, 9) == 45)
	check("slot 2 price", PerksConfig.slotPrice(1) == 1500)
	check("slot 3 price", PerksConfig.slotPrice(2) == 3500)
	check("all slots owned", PerksConfig.slotPrice(3) == nil)
	for _, id in PerksConfig.order do
		local config = PerksConfig.get(id)
		check(id .. " exists", config ~= nil)
		if config then
			check(id .. " has three prices", #config.levelPrices == config.maxLevel and #config.values == config.maxLevel)
			check(id .. " prices rise", config.levelPrices[1] < config.levelPrices[2] and config.levelPrices[2] < config.levelPrices[3])
			check(id .. " badge is two letters", #config.badge == 2)
		end
	end
	local names: { [string]: boolean } = {}
	for _, id in PerksConfig.order do
		names[(PerksConfig.get(id) :: PerksConfig.PerkConfig).displayName] = true
	end
	for _, skillName in { "Toughness", "Endurance", "Fast Hands", "Scavenger" } do
		check("no perk reads like the skill " .. skillName, not names[skillName])
	end
end)

group("equip validation", function()
	local levels = { Toughness = 1, SteadyAim = 2, FieldMedic = 3 }
	check("one perk in one slot", PerksConfig.validateEquipped({ "Toughness" }, 1, levels))
	check("empty is fine", PerksConfig.validateEquipped({}, 1, levels))
	check("two perks need two slots", not PerksConfig.validateEquipped({ "Toughness", "SteadyAim" }, 1, levels))
	check("two perks in two slots", PerksConfig.validateEquipped({ "Toughness", "SteadyAim" }, 2, levels))
	check("no duplicates", not PerksConfig.validateEquipped({ "Toughness", "Toughness" }, 3, levels))
	check("unknown perk", not PerksConfig.validateEquipped({ "Luck" }, 3, levels))
	check("level 0 cannot ride", not PerksConfig.validateEquipped({ "Scavenger" }, 3, levels))
	check("slots clamp at max", not PerksConfig.validateEquipped({ "Toughness", "SteadyAim", "FieldMedic", "Sprinter" }, 9, levels))
	check("slots clamp at one", PerksConfig.validateEquipped({ "Toughness" }, 0, levels))
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all economy tests passed")
