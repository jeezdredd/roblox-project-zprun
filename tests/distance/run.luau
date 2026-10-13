--!strict

local Guard = require("../../src/shared/util/RunDistanceGuard")

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

local MAX = 60
local DT = 1 / 60

local function runAt(speed: number, seconds: number): Guard.State
	local state = Guard.new(0)
	local position = 0
	local now = 0
	for _ = 1, math.floor(seconds / DT) do
		position += speed * DT
		now += DT
		Guard.step(state, position, speed * DT, DT, MAX, now)
	end
	return state
end

group("honest runs earn the full distance", function()
	local slow = runAt(24, 30)
	check("24 studs/s for 30 s", math.abs(slow.best - 720) < 1, tostring(slow.best))
	local fast = runAt(MAX, 30)
	check("max speed for 30 s", math.abs(fast.best - 1800) < 1, tostring(fast.best))
end)

group("speed hack is clamped", function()
	local state = runAt(MAX * 3, 10)
	local limit = 10 * (MAX * Guard.STEP_SLACK + Guard.STEP_EPSILON / DT)
	check("never above the per-step allowance", state.best <= limit + 1, tostring(state.best))
	check("never above the total cap", state.best <= Guard.cap(state, MAX) + 0.001)
end)

group("teleport forward earns nothing", function()
	local state = runAt(24, 5)
	local before = state.best
	local verdict = Guard.step(state, 120 + 5000, 5000, DT, MAX, 5 + DT)
	check("first jump is a strike", verdict == "strike", verdict)
	check("no credit from the jump", state.best == before, tostring(state.best - before))
	local next_ = Guard.step(state, 120 + 5000, 0, DT, MAX, 5 + 2 * DT)
	check("standing far ahead asks for a snap", next_ == "snap", next_)
	check("still no credit", state.best <= before + Guard.stepAllowance(MAX, DT) + 0.001, tostring(state.best - before))
end)

group("repeated jumps snap back", function()
	local state = Guard.new(0)
	local verdicts = {}
	for index = 1, Guard.SNAP_STRIKES do
		table.insert(verdicts, Guard.step(state, 0, 500, DT, MAX, index * 0.1))
	end
	check("third strike snaps", verdicts[Guard.SNAP_STRIKES] == "snap", verdicts[Guard.SNAP_STRIKES])
	check("strikes reset after the snap", state.strikes == 0)
end)

group("strikes expire", function()
	local state = Guard.new(0)
	Guard.step(state, 0, 500, DT, MAX, 0)
	Guard.step(state, 0, 500, DT, MAX, Guard.STRIKE_WINDOW + 1)
	check("old strike forgotten", state.strikes == 1, tostring(state.strikes))
end)

group("server teleports rebase without credit", function()
	local state = runAt(24, 5)
	local before = state.best
	Guard.rebase(state, before)
	local verdict = Guard.step(state, before + 0.3, 0.3, DT, MAX, 10)
	check("small step after rebase is fine", verdict == "ok", verdict)
	check("rebase does not credit", state.best <= before + 0.31)
	local behind = Guard.new(-500)
	Guard.rebase(behind, 0)
	Guard.step(behind, 0.4, 0.4, DT, MAX, 1)
	check("cap restarts at the rebase point", behind.best > 0, tostring(behind.best))
end)

group("moving back is free", function()
	local state = runAt(24, 2)
	local best = state.best
	Guard.step(state, best - 1, 1, DT, MAX, 3)
	check("best kept", state.best == best)
	check("validated follows back", math.abs(state.validated - (best - 1)) < 1e-6)
end)

if failures > 0 then
	error(string.format("%d check(s) failed", failures))
end
