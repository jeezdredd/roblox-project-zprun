--!strict

-- Pure tests for the helicopter intermission: the ready check, the skip vote, the
-- crash length and the grace window. Run from the repository root with the standalone
-- Luau CLI:  luau tests/intermission/run.luau
-- One line per group; the run exits non-zero when any check failed.

local IntermissionConfig = require("../../src/shared/config/IntermissionConfig")
local IntermissionMath = require("../../src/shared/util/IntermissionMath")

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

local C = IntermissionConfig :: any
local M = IntermissionMath

group("ready check: all ready", function()
	local check_ = M.newReadyCheck({ 11, 22, 33 }, 100, 90)
	check("waiting at the start", M.readyStatus(check_, 100) == "Waiting")
	check("ends at start plus timeout", M.endsAt(check_) == 190)
	M.setReady(check_, 11, true)
	M.setReady(check_, 22, true)
	check("two of three", M.readyCount(check_) == 2 and M.readyStatus(check_, 150) == "Waiting")
	M.setReady(check_, 33, true)
	check("all ready", M.readyStatus(check_, 150) == "AllReady")
	M.setReady(check_, 33, false)
	check("unready again waits", M.readyStatus(check_, 150) == "Waiting" and M.readyCount(check_) == 2)
	check("a stranger cannot vote", not M.setReady(check_, 99, true) and M.readyCount(check_) == 2)
	M.setReady(check_, 22, true)
	check("ready twice counts once", M.readyCount(check_) == 2)
	local solo = M.newReadyCheck({ 7 }, 0, 90)
	M.setReady(solo, 7, true)
	check("a solo squad starts on its own ready", M.readyStatus(solo, 1) == "AllReady")
	local source = { 1, 2 }
	local copied = M.newReadyCheck(source, 0, 90)
	M.removeMember(copied, 1)
	check("the member list is a copy", #source == 2)
end)

group("ready check: timeout", function()
	local check_ = M.newReadyCheck({ 11, 22 }, 100, IntermissionConfig.READY_TIMEOUT)
	check("ninety seconds", IntermissionConfig.READY_TIMEOUT == 90)
	M.setReady(check_, 11, true)
	check("one second before", M.readyStatus(check_, 189) == "Waiting")
	check("at the timeout", M.readyStatus(check_, 190) == "TimedOut")
	check("after the timeout", M.readyStatus(check_, 500) == "TimedOut")
	check("nobody ready still times out", M.readyStatus(M.newReadyCheck({ 5 }, 0, 90), 90) == "TimedOut")
	M.setReady(check_, 22, true)
	check("all ready wins over the timeout", M.readyStatus(check_, 500) == "AllReady")
	check("negative timeout is zero", M.readyStatus(M.newReadyCheck({ 5 }, 10, -4), 10) == "TimedOut")
	check("seconds left rounds up", M.secondsLeft(190, 100.2) == 90 and M.secondsLeft(190, 189.01) == 1 and M.secondsLeft(190, 200) == 0)
end)

group("ready check: a member leaving", function()
	local check_ = M.newReadyCheck({ 11, 22, 33 }, 0, 90)
	M.setReady(check_, 11, true)
	M.setReady(check_, 22, true)
	M.removeMember(check_, 33)
	check("the last unready leaves: all ready", M.readyStatus(check_, 5) == "AllReady")
	local other = M.newReadyCheck({ 11, 22 }, 0, 90)
	M.setReady(other, 22, true)
	M.removeMember(other, 22)
	check("a ready member leaving takes the vote", M.readyCount(other) == 0 and M.readyStatus(other, 5) == "Waiting")
	M.removeMember(other, 11)
	check("everyone left: empty", M.readyStatus(other, 5) == "Empty")
	check("empty wins over the timeout", M.readyStatus(other, 500) == "Empty")
	M.removeMember(other, 11)
	check("removing twice is harmless", #other.members == 0)
	check("a member who left cannot vote", not M.setReady(other, 11, true))
end)

group("skip vote", function()
	local vote = M.newSkipVote({ 1, 2, 3 })
	check("nobody voted", not M.skipPasses(vote) and M.skipCount(vote) == 0)
	M.voteSkip(vote, 1)
	M.voteSkip(vote, 2)
	check("two of three is not enough", not M.skipPasses(vote))
	check("a stranger cannot vote", not M.voteSkip(vote, 9) and M.skipCount(vote) == 2)
	M.voteSkip(vote, 2)
	check("voting twice counts once", M.skipCount(vote) == 2)
	M.voteSkip(vote, 3)
	check("all three skip", M.skipPasses(vote))
	local leaving = M.newSkipVote({ 1, 2 })
	M.voteSkip(leaving, 1)
	M.removeVoter(leaving, 2)
	check("the holdout leaving passes it", M.skipPasses(leaving))
	local gone = M.newSkipVote({ 1 })
	M.removeVoter(gone, 1)
	check("an empty squad never passes", not M.skipPasses(gone))
	local voter = M.newSkipVote({ 4 })
	M.voteSkip(voter, 4)
	M.removeVoter(voter, 4)
	check("a voter leaving takes the vote", M.skipCount(voter) == 0)
end)

group("crash length", function()
	local length, skippable = M.crashFor(C, { 0, 3 })
	check("a first-timer gets the full crash", length == IntermissionConfig.CRASH_LENGTH and not skippable)
	check("the full crash is 12 to 15 s", IntermissionConfig.CRASH_LENGTH >= 12 and IntermissionConfig.CRASH_LENGTH <= 15)
	length, skippable = M.crashFor(C, { 2, 7, 1 })
	check("veterans get 5 s, skippable", length == 5 and skippable)
	length, skippable = M.crashFor(C, {})
	check("no members: full, not skippable", length == IntermissionConfig.CRASH_LENGTH and not skippable)
	local wild = table.clone(C)
	wild.CRASH_LENGTH = 40
	check("the full length is clamped to the range", (M.crashFor(wild, { 0 })) == 15)
	wild.CRASH_LENGTH = 3
	check("and from below", (M.crashFor(wild, { 0 })) == 12)
	wild.CRASH_LENGTH_REPEAT = 30
	check("the repeat never runs longer than the full", (M.crashFor(wild, { 1 })) == 12)
end)

group("grace window", function()
	local graceUntil = M.graceUntil(1000, IntermissionConfig.GRACE_SECONDS)
	check("six seconds", IntermissionConfig.GRACE_SECONDS == 6 and graceUntil == 1006)
	check("protected at the spawn", M.inGrace(graceUntil, 1000))
	check("protected just before the end", M.inGrace(graceUntil, 1005.99))
	check("not at the end", not M.inGrace(graceUntil, 1006))
	check("not after", not M.inGrace(graceUntil, 2000))
	check("no attribute, no grace", not M.inGrace(nil, 0))
	check("a string never protects", not M.inGrace("9999999", 0))
	check("negative seconds is no window", M.graceUntil(50, -3) == 50 and not M.inGrace(M.graceUntil(50, -3), 50))
end)

group("cabin look", function()
	local yaw, pitch = M.lookAfter(C, 0, 0, 40, 0)
	check("mouse right turns right", yaw == -40 * IntermissionConfig.LOOK_SENSITIVITY and pitch == 0)
	yaw, pitch = M.lookAfter(C, 0, 0, 0, 40)
	check("mouse down looks down", pitch == -40 * IntermissionConfig.LOOK_SENSITIVITY)
	yaw = M.lookAfter(C, 0, 0, -100000, 0)
	check("yaw clamps left", yaw == IntermissionConfig.LOOK_YAW and IntermissionConfig.LOOK_YAW == 100)
	yaw = M.lookAfter(C, 0, 0, 100000, 0)
	check("yaw clamps right", yaw == -100)
	local _, low = M.lookAfter(C, 0, 0, 0, 100000)
	local _, high = M.lookAfter(C, 0, 0, 0, -100000)
	check("pitch clamps -50..40", low == -50 and high == 40)
	local eased = M.easeLook(C, 0, 30, 1 / 60)
	check("eases, no snap", eased > 0 and eased < 30, tostring(eased))
	local value = 0
	for _ = 1, 120 do
		value = M.easeLook(C, value, 30, 1 / 60)
	end
	check("lands on the target", value == 30)
	check("a zero step stays", M.easeLook(C, 12, 30, 0) == 12)
	local slow = M.easeLook(C, 0, 30, 1 / 30)
	local fastTwice = M.easeLook(C, M.easeLook(C, 0, 30, 1 / 60), 30, 1 / 60)
	check("frame-rate independent", math.abs(slow - fastTwice) < 1e-6)
end)

group("cabin layout", function()
	check("a seat per squad member", #IntermissionConfig.seats == 3)
	for index, seat in IntermissionConfig.seats do
		check("seat " .. index .. " inside the cabin", math.abs(seat[1]) < 4.5 and math.abs(seat[3]) < 8)
	end
	local names: { [string]: boolean } = {}
	for _, part in IntermissionConfig.parts do
		check("unique part name " .. part.name, not names[part.name])
		names[part.name] = true
	end
	check("the crew is pilot and copilot", #IntermissionConfig.crew == 2 and IntermissionConfig.crew[1].name == "Pilot" and IntermissionConfig.crew[2].name == "Copilot")
	check("far off the map", math.abs(IntermissionConfig.CABIN_ORIGIN[1]) >= 2000 and IntermissionConfig.CABIN_ORIGIN[2] >= 200)
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all intermission tests passed")
