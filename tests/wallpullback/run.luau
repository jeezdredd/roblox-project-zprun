--!strict

-- Pure tests for the wall pull-back: the blend from the hit distance, the easing, the
-- pose, the fire block with its margin. Run from the repository root with the
-- standalone Luau CLI:  luau tests/wallpullback/run.luau
-- One line per group; the run exits non-zero when any check failed.

local WallPullbackConfig = require("../../src/shared/config/WallPullbackConfig")
local WallPullbackMath = require("../../src/shared/util/WallPullbackMath")
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

local C = WallPullbackConfig :: any
local M = WallPullbackMath

group("reach", function()
	for _, id in WeaponsConfig.order do
		local class = (WeaponsConfig.get(id) :: WeaponsConfig.WeaponConfig).class
		check(class .. " has a reach", WallPullbackConfig.reach[class] ~= nil)
	end
	check("an unknown class gets the default", M.reachFor(C, "Flamethrower") == WallPullbackConfig.REACH_DEFAULT)
	check("nil class gets the default", M.reachFor(C, nil) == WallPullbackConfig.REACH_DEFAULT)
	check("the pistol reaches least", M.reachFor(C, "Pistol") < M.reachFor(C, "Rifle"))
	check("full at 45 percent", math.abs(M.fullDistance(C, 3.4) - 1.53) < 1e-9)
end)

group("distance to blend", function()
	local reach = 3.4
	check("nothing hit, no pull", M.targetFor(C, nil, reach) == 0)
	check("beyond the reach, none", M.targetFor(C, 5, reach) == 0)
	check("at the reach, none", M.targetFor(C, reach, reach) == 0)
	check("at the full distance, all", M.targetFor(C, M.fullDistance(C, reach), reach) == 1)
	check("closer than full, all", M.targetFor(C, 0.2, reach) == 1)
	check("touching, all", M.targetFor(C, 0, reach) == 1)
	local previous = 0
	local monotone = true
	for i = 0, 100 do
		local d = reach - (reach / 100) * i
		local t = M.targetFor(C, d, reach)
		if t < previous - 1e-12 then
			monotone = false
		end
		previous = t
	end
	check("closer never pulls less", monotone)
	local mid = M.targetFor(C, (reach + M.fullDistance(C, reach)) / 2, reach)
	check("halfway is half (smoothstep)", math.abs(mid - 0.5) < 1e-9, tostring(mid))
	local nearEdge = M.targetFor(C, reach - 0.01, reach)
	check("gentle at the edge, no jump", nearEdge > 0 and nearEdge < 0.01, tostring(nearEdge))
	check("a zero reach never pulls", M.targetFor(C, 0, 0) == 0)
end)

group("easing", function()
	local first = M.ease(C, 0, 1, 1 / 60)
	check("eases in, no pop", first > 0 and first < 0.5, tostring(first))
	local out = M.ease(C, 1, 0, 1 / 60)
	check("eases out, no pop", out < 1 and out > 0.5, tostring(out))
	check("in faster than out", first > 1 - out)
	local value = 0
	for _ = 1, 120 do
		value = M.ease(C, value, 1, 1 / 60)
	end
	check("lands on full", value == 1)
	for _ = 1, 180 do
		value = M.ease(C, value, 0, 1 / 60)
	end
	check("lands back on zero", value == 0)
	local twoSmall = M.ease(C, M.ease(C, 0, 1, 1 / 120), 1, 1 / 120)
	local oneBig = M.ease(C, 0, 1, 1 / 60)
	check("frame-rate independent", math.abs(twoSmall - oneBig) < 1e-9)
	check("no step, no change", M.ease(C, 0.4, 1, 0) == 0.4)
	check("stays within 0..1", M.ease(C, 0.5, 1, 100) == 1 and M.ease(C, 0.5, 0, 100) == 0)
end)

group("pose", function()
	local none = M.poseAt(C, 0)
	check("ready pose at 0", none.back == 0 and none.pitchUp == 0 and none.yawAside == 0 and none.roll == 0)
	local full = M.poseAt(C, 1)
	check("full pose at 1", full.back == WallPullbackConfig.pose.back and full.pitchUp == WallPullbackConfig.pose.pitchUp)
	local half = M.poseAt(C, 0.5)
	check("half way at 0.5", math.abs(half.back - WallPullbackConfig.pose.back / 2) < 1e-12)
	check("clamped above 1", M.poseAt(C, 3).back == WallPullbackConfig.pose.back)
	check("clamped below 0", M.poseAt(C, -1).back == 0)
	check("back toward the chest, muzzle up", WallPullbackConfig.pose.back > 0 and WallPullbackConfig.pose.pitchUp > 0)
end)

group("fire block", function()
	local reach = 3.4
	local full = M.fullDistance(C, reach)
	check("nothing hit, fires", not M.blocked(C, false, nil, reach))
	check("partly pulled, fires", not M.blocked(C, false, full + 0.3, reach))
	check("fully pulled, blocked", M.blocked(C, false, full, reach))
	check("inside the wall, blocked", M.blocked(C, false, 0.1, reach))
	check("held inside the margin", M.blocked(C, true, full + WallPullbackConfig.RELEASE_MARGIN * 0.5, reach))
	check("released past the margin", not M.blocked(C, true, full + WallPullbackConfig.RELEASE_MARGIN + 0.01, reach))
	check("released with nothing hit", not M.blocked(C, true, nil, reach))
	check("not blocked just past full without history", not M.blocked(C, false, full + 0.05, reach))
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all wall pull-back tests passed")
