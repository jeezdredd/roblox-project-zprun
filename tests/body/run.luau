--!strict

-- Pure-math tests for the third-person body. Run from the repository root with the
-- standalone Luau CLI:  luau tests/body/run.luau
-- One line per group; the run errors on the first group with a failed assertion.

local BodyMath = require("../../src/shared/util/BodyMath")

local failures = 0

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		return
	end
	failures += 1
	print(string.format("  FAIL %s%s", name, if detail then " (" .. detail .. ")" else ""))
end

local function near(a: number, b: number, tolerance: number): boolean
	return math.abs(a - b) <= tolerance
end

local function group(name: string, body: () -> ())
	local before = failures
	body()
	print(string.format("%s %s", if failures == before then "ok  " else "FAIL", name))
end

local SHARES: BodyMath.AimShares = {
	waistPitch = 0.35,
	waistYaw = 0.55,
	pitchClamp = 70,
	yawClamp = 60,
}

group("angles", function()
	check("wrap 190", BodyMath.wrapDegrees(190) == -170)
	check("wrap -190", BodyMath.wrapDegrees(-190) == 170)
	check("wrap 180", BodyMath.wrapDegrees(180) == 180)
	check("wrap 540", BodyMath.wrapDegrees(540) == 180)
	check("yaw left is positive", near(BodyMath.signedYaw(0, -1, -1, 0), 90, 1e-9))
	check("yaw right is negative", near(BodyMath.signedYaw(0, -1, 1, 0), -90, 1e-9))
	check("yaw ahead is zero", BodyMath.signedYaw(0, -1, 0, -1) == 0)
	check("yaw degenerate", BodyMath.signedYaw(0, 0, 0, 0) == 0)
	check("pitch up", near(BodyMath.pitchOf(0.5), 30, 1e-6))
	check("pitch clamps", near(BodyMath.pitchOf(2), 90, 1e-9))
end)

group("approach", function()
	local value = 0
	for _ = 1, 60 do
		value = BodyMath.approachAngle(value, 40, 1 / 60, 0.08)
	end
	check("settles within a second", near(value, 40, 0.01), tostring(value))
	check("takes the short way", BodyMath.approachAngle(170, -170, 0.016, 0.08) > 170)
	check("snaps with zero constant", BodyMath.approachAngle(10, 50, 0.016, 0) == 50)
	check("plain approach", near(BodyMath.approach(0, 1, 0.08, 0.08), 1 - math.exp(-1), 1e-9))
	check("smoothstep ends", BodyMath.smoothstep(0) == 0 and BodyMath.smoothstep(1) == 1)
	check("smoothstep middle", BodyMath.smoothstep(0.5) == 0.5)
	check("smoothstep clamps", BodyMath.smoothstep(2) == 1)
end)

group("aim spread", function()
	local spread = BodyMath.spreadAim(40, 20, SHARES, 1)
	check("head and gun take the whole aim", spread.pitch == 40 and spread.yaw == 20 and spread.gunPitch == 40)
	check("chest takes its share", near(spread.waistPitch, 14, 1e-9) and near(spread.waistYaw, 11, 1e-9))
	local clamped = BodyMath.spreadAim(120, -100, SHARES, 1)
	check("pitch clamps", clamped.pitch == 70 and clamped.gunPitch == 70 and near(clamped.waistPitch, 24.5, 1e-9))
	check("yaw clamps", clamped.yaw == -60 and near(clamped.waistYaw, -33, 1e-9))
	local sprint = BodyMath.spreadAim(40, 0, SHARES, 0.5)
	check("sprint halves the gun pitch", near(sprint.gunPitch, 20, 1e-9))
	check("sprint keeps the chest share", near(sprint.waistPitch, 14, 1e-9) and sprint.pitch == 40)
end)

group("wire", function()
	check("quantize rounds", BodyMath.quantize(12.4) == 12 and BodyMath.quantize(12.5) == 13 and BodyMath.quantize(-0.6) == -1)
	check("rate limited", not BodyMath.shouldSend(0, 0, 30, 30, 0.02, 0.05, 1, 1))
	check("sends on change", BodyMath.shouldSend(0, 0, 1, 0, 0.06, 0.05, 1, 1))
	check("holds without change", not BodyMath.shouldSend(10, 10, 10.4, 10.2, 0.06, 0.05, 1, 1))
	check("keepalive", BodyMath.shouldSend(10, 10, 10, 10, 1.01, 0.05, 1, 1))
	check("yaw change wraps", BodyMath.shouldSend(0, 179, 0, -179, 0.06, 0.05, 1, 1))
	local ok, pitch, yaw = BodyMath.validateAim(95, 400, 89, 179)
	check("validate clamps", ok and pitch == 89 and yaw == 40, string.format("%s %d %d", tostring(ok), pitch, yaw))
	check("validate rejects strings", not BodyMath.validateAim("a", 0, 89, 179))
	check("validate rejects nil", not BodyMath.validateAim(nil, 0, 89, 179))
	check("validate rejects nan", not BodyMath.validateAim(0 / 0, 0, 89, 179))
	check("validate rejects inf", not BodyMath.validateAim(math.huge, 0, 89, 179))
end)

group("recoil spring", function()
	local state: BodyMath.SpringState = { value = 0, velocity = 0 }
	BodyMath.springImpulse(state, 12)
	local peak = 0
	local samples = 0
	for _ = 1, 120 do
		local value = BodyMath.springStep(state, 200, 25, 1 / 60)
		peak = math.max(peak, value)
		samples += 1
	end
	check("kicks then settles", peak > 0.2 and near(state.value, 0, 0.01), string.format("peak %.3f end %.4f", peak, state.value))
	local critical: BodyMath.SpringState = { value = 1, velocity = 0 }
	local dipped = false
	for _ = 1, 120 do
		if BodyMath.springStep(critical, 100, 20, 1 / 60) < -1e-6 then
			dipped = true
		end
	end
	check("critical damping never crosses", not dipped)
	local hitch: BodyMath.SpringState = { value = 1, velocity = 0 }
	BodyMath.springStep(hitch, 300, 10, 0.5)
	check("long step stays bounded", math.abs(hitch.value) < 1, tostring(hitch.value))
	local over: BodyMath.SpringState = { value = 1, velocity = 0 }
	local crossed = false
	for _ = 1, 200 do
		if BodyMath.springStep(over, 100, 60, 1 / 60) < -1e-9 then
			crossed = true
		end
	end
	check("overdamped decays without crossing", not crossed and over.value < 0.05, tostring(over.value))
	local split: BodyMath.SpringState = { value = 0, velocity = 5 }
	local whole: BodyMath.SpringState = { value = 0, velocity = 5 }
	for _ = 1, 10 do
		BodyMath.springStep(split, 150, 12, 0.01)
	end
	BodyMath.springStep(whole, 150, 12, 0.1)
	check("step size does not change the curve", near(split.value, whole.value, 1e-9) and near(split.velocity, whole.velocity, 1e-7))
	check("zero step is a no-op", BodyMath.springStep(whole, 150, 12, 0) == whole.value)
	local sized: BodyMath.SpringState = { value = 0, velocity = 0 }
	BodyMath.springImpulse(sized, BodyMath.impulseForPeak(0.5, 200))
	local top = 0
	for _ = 1, 120 do
		top = math.max(top, BodyMath.springStep(sized, 200, 2 * math.sqrt(200), 1 / 120))
	end
	check("impulse for peak lands on the peak", near(top, 0.5, 0.01), tostring(top))
end)

group("magazine timeline", function()
	local tactical = BodyMath.magazineTimeline(1.52, 2.1, false, 0.3)
	check("starts at grip", tactical[1].pose == "grip" and tactical[1].t == 0)
	check("seats at ammo-add", tactical[4].pose == "seat" and near(tactical[4].t, 1.52, 1e-9))
	check("ends at the total", BodyMath.timelineDuration(tactical) == 2.1 and tactical[#tactical].pose == "grip")
	check("no charge on a tactical", #tactical == 5)
	local previous = -1
	for _, keyframe in tactical do
		check("monotonic", keyframe.t >= previous)
		previous = keyframe.t
	end
	local empty = BodyMath.magazineTimeline(2.63, 3.4, true, 0.4)
	check("empty adds the charge", #empty == 8 and empty[6].pose == "chargePulled")
	check("charge after the seat", empty[5].t > 2.63 and empty[7].t <= 3.4)
	check("empty ends at the total", BodyMath.timelineDuration(empty) == 3.4)
	local short = BodyMath.magazineTimeline(0.2, 0.25, true, 0.5)
	previous = -1
	for _, keyframe in short do
		check("short timeline monotonic", keyframe.t >= previous, string.format("%s %.3f", keyframe.pose, keyframe.t))
		previous = keyframe.t
	end
end)

group("shell timeline", function()
	local shell: BodyMath.ShellReloadNumbers = { start = 0.75, perShell = 0.9, addAt = 0.64, finish = 0.7, chamber = 0.55, exit = 0.2 }
	local four = BodyMath.shellTimeline(shell, 4, true, 1)
	check("one belt per shell", #four == 1 + 4 * 3 + 3 + 1)
	check("second shell seats at its add point", four[7].pose == "seat" and near(four[7].t, 0.75 + 0.9 + 0.64, 1e-9))
	check("pump after the finish", four[15].pose == "pumpBack")
	check("total with the chamber", near(BodyMath.timelineDuration(four), 0.75 + 4 * 0.9 + 0.7 + 0.55, 1e-9))
	local two = BodyMath.shellTimeline(shell, 2, false, 1.2)
	check("scaled without the chamber", near(BodyMath.timelineDuration(two), (0.75 + 2 * 0.9 + 0.7) * 1.2, 1e-9))
	local previous = -1
	for _, keyframe in four do
		check("shells monotonic", keyframe.t >= previous, string.format("%s %.3f", keyframe.pose, keyframe.t))
		previous = keyframe.t
	end
	local none = BodyMath.shellTimeline(shell, 0, false, 1)
	check("zero shells still returns", #none == 2)
end)

group("pose sampling", function()
	local timeline = BodyMath.equipTimeline(0.85)
	local sample: BodyMath.PoseSample = { from = "", to = "", alpha = 0 }
	BodyMath.poseAt(timeline, -1, sample)
	check("before start holds first", sample.from == "lowered" and sample.alpha == 1)
	BodyMath.poseAt(timeline, 0.34, sample)
	check("middle blends", sample.from == "lowered" and sample.to == "grip" and near(sample.alpha, 0.5, 1e-9), tostring(sample.alpha))
	BodyMath.poseAt(timeline, 5, sample)
	check("after end holds last", sample.from == "grip" and sample.to == "grip" and sample.alpha == 1)
	BodyMath.poseAt({}, 1, sample)
	check("empty timeline is grip", sample.from == "grip")
	local pump = BodyMath.pumpTimeline(0.5, 0.15)
	check("pump goes back and forward", pump[3].pose == "pumpBack" and pump[4].pose == "pump" and near(BodyMath.timelineDuration(pump), 0.65, 1e-9))
	BodyMath.poseAt(pump, 0.1, sample)
	check("pump waits for the delay", sample.from == "grip" and sample.to == "grip")
	BodyMath.poseAt({ { t = 0, pose = "a" }, { t = 0, pose = "b" } }, 0, sample)
	check("zero-length segment snaps", sample.alpha == 1)
end)

group("sprint and lod", function()
	check("sprint on above", BodyMath.sprintTarget(36, 36, 4, false))
	check("sprint stays on inside the hysteresis", BodyMath.sprintTarget(33, 36, 4, true))
	check("sprint off below", not BodyMath.sprintTarget(31, 36, 4, true))
	check("no sprint below when off", not BodyMath.sprintTarget(35, 36, 4, false))
	local bands: BodyMath.LodBands = { full = 60, half = 150, quarter = 300, ikRange = 150 }
	local cadence, ik = BodyMath.lodBand(10, bands)
	check("near is every frame with IK", cadence == 1 and ik)
	cadence, ik = BodyMath.lodBand(100, bands)
	check("mid is every 2nd with IK", cadence == 2 and ik)
	cadence, ik = BodyMath.lodBand(200, bands)
	check("far is every 4th without IK", cadence == 4 and not ik)
	cadence, ik = BodyMath.lodBand(500, bands)
	check("beyond is never", cadence == 0 and not ik)
	check("round robin", BodyMath.updatesThisFrame(4, 0, 2) and not BodyMath.updatesThisFrame(4, 1, 2))
	check("cadence 0 never updates", not BodyMath.updatesThisFrame(4, 0, 0))
	check("cadence 1 always updates", BodyMath.updatesThisFrame(7, 3, 1))
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all body math tests passed")
