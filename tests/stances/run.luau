--!strict

-- Pure tests for StanceMath: the stance cycle and easing, the raise a shot from high or
-- low ready waits for (per class, scaled by how far in the stance is), the stay-up
-- timer, suppression, the magazine check's hold, minimum show and readout, and the
-- lean's camera offset, wall room, viewmodel counter-pose, body roll and wire value.
-- Run from the repository root with the standalone Luau CLI:  luau tests/stances/run.luau
-- One line per group; the run exits non-zero when any check failed.

local StanceConfig = require("../../src/shared/config/StanceConfig")
local StanceMath = require("../../src/shared/util/StanceMath")

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

local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-6)
end

local C = StanceConfig :: any
local M = StanceMath
local DT = 1 / 60

-- steps the state for `seconds` at 60 fps from `now`; returns the new time
local function run(state: StanceMath.State, now: number, seconds: number, suppressed: boolean?): number
	local frames = math.floor(seconds / DT + 0.5)
	for _ = 1, frames do
		now += DT
		M.step(C, state, DT, now, suppressed == true)
	end
	return now
end

group("cycle", function()
	check("mid to high", M.nextStance(C, "mid") == "high")
	check("high to low", M.nextStance(C, "high") == "low")
	check("low to mid", M.nextStance(C, "low") == "mid")
	check("unknown to the first", M.nextStance(C, "prone") == "mid")
end)

group("easing into a stance", function()
	local state = M.new()
	check("starts up", M.isUp(C, state))
	M.select(state, "low")
	local now = run(state, 0, 0.05)
	check("partly in after 50 ms", state.low > 0.2 and state.low < 0.6, tostring(state.low))
	check("not up while lowering", not M.isUp(C, state))
	now = run(state, now, 1)
	check("fully in after a second", state.low == 1, tostring(state.low))
	check("no high weight", state.high == 0)
	local pose = M.pose(C, state)
	check("pose is the low pose", near(pose.pitch, C.poses.low.pitch) and near(pose.up, C.poses.low.up))
	M.select(state, "high")
	now = run(state, now, 0.1)
	check("blending low out and high in", state.low < 1 and state.high > 0)
	run(state, now, 1)
	check("high fully in", state.high == 1 and state.low == 0)
end)

group("ease is frame-rate independent and lands", function()
	local a, b = 0, 0
	for _ = 1, 60 do
		a = M.ease(a, 1, 9, 12, 1 / 60)
	end
	for _ = 1, 30 do
		b = M.ease(b, 1, 9, 12, 1 / 30)
	end
	check("same curve at 30 and 60 fps", near(a, b, 1e-3), `{a} {b}`)
	check("lands exactly", M.ease(0.9995, 1, 9, 12, DT) == 1)
	check("negative time does nothing", M.ease(0.5, 1, 9, 12, -1) == 0.5)
end)

group("raise before the shot", function()
	local state = M.new()
	M.select(state, "low")
	local now = run(state, 0, 1)
	local expected = C.raiseTime.Rifle.low
	check("raise duration from full low", near(M.raiseDuration(C, state, "Rifle"), expected))
	check("first request waits", not M.requestFire(C, state, "Rifle", now))
	check("raise running", state.raising ~= nil and near(M.raiseRemaining(state), expected))
	check("a second request does not restart it", not M.requestFire(C, state, "Rifle", now + 0.05) and near(M.raiseRemaining(state), expected))
	local before = state.low
	now = run(state, now, expected * 0.5)
	check("halfway down the raise", state.low < before and state.low > 0, tostring(state.low))
	now = run(state, now, expected * 0.5 + DT)
	check("up after the class's time", M.isUp(C, state) and state.raising == nil, tostring(state.low))
	check("now it fires", M.requestFire(C, state, "Rifle", now))
	-- stays up while firing, returns after RETURN_AFTER
	now = run(state, now, C.RETURN_AFTER - 0.1)
	check("still up just before the return", state.low == 0)
	now = run(state, now, 0.3)
	check("easing back to low after the return", state.low > 0)
	run(state, now, 1)
	check("back in low ready", state.low == 1)
end)

group("raise per class and partial stance", function()
	local state = M.new()
	M.select(state, "high")
	run(state, 0, 1)
	check("pistol is quicker than the shotgun", M.raiseDuration(C, state, "Pistol") < M.raiseDuration(C, state, "Shotgun"))
	check("unknown class uses the default", near(M.raiseDuration(C, state, "Bow"), C.RAISE_DEFAULT.high))
	state.high = 0.5
	check("half in, half the time", near(M.raiseDuration(C, state, "Rifle"), C.raiseTime.Rifle.high * 0.5))
end)

group("mid fires at once", function()
	local state = M.new()
	check("up in mid", M.requestFire(C, state, "SMG", 0))
	check("no raise", state.raising == nil)
	check("stay-up timer set", near(state.upUntil, C.RETURN_AFTER))
end)

group("suppressed", function()
	local state = M.new()
	M.select(state, "low")
	local now = run(state, 0, 1)
	now = run(state, now, 1, true)
	check("a reload eases the stance out", state.low == 0)
	check("the stance stays chosen", state.selected == "low")
	run(state, now, 1)
	check("and comes back after", state.low == 1)
end)

group("magazine check", function()
	check("short press is a reload", not M.isHold(C, C.MAG_CHECK.holdTime - 0.01))
	check("long press is a check", M.isHold(C, C.MAG_CHECK.holdTime))
	local state = M.new()
	M.select(state, "high")
	local now = run(state, 0, 1)
	M.startCheck(state, now)
	now = run(state, now, 0.05)
	check("count hidden while tipping in", not M.countVisible(C, state))
	now = run(state, now, 0.6)
	check("check replaces the stance", state.high == 0 and state.mag > 0.98, `{state.high} {state.mag}`)
	check("count shown once in", M.countVisible(C, state))
	-- released early: stays for minShow
	M.releaseCheck(C, state, now)
	check("still checking before minShow", state.checking)
	now = run(state, now, C.MAG_CHECK.minShow)
	check("ends after minShow", not state.checking)
	now = run(state, now, 1)
	check("count hidden after", not M.countVisible(C, state))
	check("back in high ready", state.high == 1 and state.mag == 0)

	-- released late: ends at once
	M.startCheck(state, now)
	now = run(state, now, C.MAG_CHECK.minShow + 0.2)
	M.releaseCheck(C, state, now)
	check("late release ends it at once", not state.checking)

	-- a shot during the check brings the gun up first
	M.startCheck(state, now)
	now = run(state, now, 1)
	check("shot waits for the check to clear", not M.requestFire(C, state, "Pistol", now))
	check("check ended by the shot", not state.checking)
	check("raise from the check", near(M.raiseDuration(C, { selected = "mid", high = 0, low = 0, mag = 1, raising = nil, upUntil = 0, checking = false, checkStartedAt = 0, checkReleased = false }, "Pistol"), C.MAG_CHECK.raiseTime))
	run(state, now, 0.5)
	check("up after the raise", M.isUp(C, state))

	M.startCheck(state, 0)
	M.cancelCheck(state)
	check("cancel ends it", not state.checking)
end)

group("readout", function()
	check("exact", M.readout("exact", 27, 30) == "27 / 30")
	check("exact floors and clamps", M.readout("exact", -2, 30) == "0 / 30")
	check("estimate full", M.readout("estimate", 30, 30) == "Full")
	check("estimate almost full", M.readout("estimate", 24, 30) == "Almost full")
	check("estimate half", M.readout("estimate", 15, 30) == "About half")
	check("estimate almost empty", M.readout("estimate", 3, 30) == "Almost empty")
	check("estimate empty", M.readout("estimate", 0, 30) == "Empty")
end)

group("lean input", function()
	check("none", M.leanHeld(false, false, 1) == 0)
	check("left", M.leanHeld(true, false, 1) == -1)
	check("right", M.leanHeld(false, true, -1) == 1)
	check("both: last pressed wins", M.leanHeld(true, true, -1) == -1 and M.leanHeld(true, true, 1) == 1)
	check("toggle on", M.leanToggled(0, 1) == 1)
	check("toggle off", M.leanToggled(1, 1) == 0)
	check("toggle across", M.leanToggled(-1, 1) == 1)
end)

group("lean camera, room and counter-pose", function()
	local lean = C.LEAN
	local x, y, roll = M.leanCamera(C, 1, 1)
	check("full right offset", near(x, lean.offset) and near(y, -lean.drop))
	check("right lean rolls the view right (negative Z)", near(roll, -lean.roll))
	local lx, _, lroll = M.leanCamera(C, -1, 1)
	check("left mirrors right", near(lx, -lean.offset) and near(lroll, lean.roll))
	local hx, _, hroll = M.leanCamera(C, 0.5, 0.5)
	check("half lean, half room", near(hx, lean.offset * 0.25) and near(hroll, -lean.roll * 0.5))
	check("clear side: full room", M.leanRoom(C, nil) == 1)
	check("wall at the margin: no room", M.leanRoom(C, lean.wallMargin) == 0)
	check("wall inside the margin: no room", M.leanRoom(C, 0.05) == 0)
	check("wall halfway", near(M.leanRoom(C, lean.wallMargin + lean.offset * 0.5), 0.5))
	local counter = M.leanViewmodel(C, 1)
	check("counter-roll takes part of the roll back", counter.roll > 0 and counter.roll < lean.roll, tostring(counter.roll))
	check("counter nudges toward the lean", counter.aside > 0)
	check("no counter without lean", M.leanViewmodel(C, 0).roll == 0)
	check("body roll right is negative Z", near(M.bodyRoll(C, 1), -lean.bodyRoll))
	check("body roll clamps", near(M.bodyRoll(C, -3), lean.bodyRoll))
end)

group("lean on the wire", function()
	check("tenths", M.quantizeLean(0.46) == 0.5 and M.quantizeLean(-0.44) == -0.4)
	check("clamped", M.quantizeLean(2) == 1)
	check("valid", M.validateLean(0.3) == 0.3)
	check("clamp", M.validateLean(-7) == -1)
	check("missing is 0", M.validateLean(nil) == 0)
	check("nan is 0", M.validateLean(0 / 0) == 0)
	check("inf is 0", M.validateLean(math.huge) == 0)
	check("string is 0", M.validateLean("1") == 0)
end)

group("config", function()
	check("cycle starts at mid", C.CYCLE[1] == "mid")
	check("mid pose is zero", C.poses.mid.pitch == 0 and C.poses.mid.back == 0)
	check("every class has both raise times", (function()
		for _, times in C.raiseTime do
			if type(times.high) ~= "number" or type(times.low) ~= "number" then
				return false
			end
		end
		return true
	end)())
	check("hold time under the minimum show", C.MAG_CHECK.holdTime < C.MAG_CHECK.minShow)
	check("lean mode known", C.LEAN.mode == "hold" or C.LEAN.mode == "toggle")
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all stance tests passed")
