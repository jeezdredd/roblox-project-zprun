--!strict

-- Pure tests for the third-person locomotion rules. Run from the repository root with
-- the standalone Luau CLI:  luau tests/animation/run.luau
-- One line per group; the run exits non-zero when any check failed.

local LocomotionMath = require("../../src/shared/util/LocomotionMath")

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

local THRESHOLDS: LocomotionMath.Thresholds = { walkMax = 12, strafeAxis = 0.5 }
local REFERENCES = { walk = 10, run = 24, sprint = 36 }

local function keys(targets: { [string]: number }): string
	local names = {}
	for id, weight in targets do
		table.insert(names, string.format("%s=%d", id, weight))
	end
	table.sort(names)
	return table.concat(names, " ")
end

group("clip set by class", function()
	check("pistol", LocomotionMath.setFor("Pistol") == "Pistol")
	check("rifle", LocomotionMath.setFor("Rifle") == "Rifle")
	check("smg is rifle", LocomotionMath.setFor("SMG") == "Rifle")
	check("shotgun is rifle", LocomotionMath.setFor("Shotgun") == "Rifle")
	check("no weapon is rifle", LocomotionMath.setFor(nil) == "Rifle")
	check("clip id", LocomotionMath.clipId("Rifle", "strafe_left") == "RifleStrafeLeft")
	check("clip id run", LocomotionMath.clipId("Pistol", "run") == "PistolRun")
end)

group("gait from movement", function()
	check("still is idle", LocomotionMath.gaitFor(false, 0, 0, false, THRESHOLDS) == "idle")
	check("still with input is idle", LocomotionMath.gaitFor(false, 30, 1, true, THRESHOLDS) == "idle")
	check("slow is walk", LocomotionMath.gaitFor(true, 8, 0, false, THRESHOLDS) == "walk")
	check("walk max is run", LocomotionMath.gaitFor(true, 12, 0, false, THRESHOLDS) == "run")
	check("fast is run", LocomotionMath.gaitFor(true, 30, 0, false, THRESHOLDS) == "run")
	check("sprint flag wins", LocomotionMath.gaitFor(true, 40, 0, true, THRESHOLDS) == "sprint")
	check("sprint never strafes", LocomotionMath.gaitFor(true, 40, -1, true, THRESHOLDS) == "sprint")
	check("left input strafes left", LocomotionMath.gaitFor(true, 24, -1, false, THRESHOLDS) == "strafe_left")
	check("right input strafes right", LocomotionMath.gaitFor(true, 24, 0.6, false, THRESHOLDS) == "strafe_right")
	check("small input runs", LocomotionMath.gaitFor(true, 24, 0.3, false, THRESHOLDS) == "run")
	check("strafe while slow", LocomotionMath.gaitFor(true, 6, 1, false, THRESHOLDS) == "strafe_right")
end)

group("targets and fallbacks", function()
	local full = { RifleIdle = true, RifleWalk = true, RifleRun = true, RifleSprint = true, RifleStrafeLeft = true, RifleStrafeRight = true, Run = true, StrafeLeft = true }
	check("own clip", keys(LocomotionMath.targets("Rifle", "run", full)) == "RifleRun=1")
	check("own strafe", keys(LocomotionMath.targets("Rifle", "strafe_left", full)) == "RifleStrafeLeft=1")
	check("own idle", keys(LocomotionMath.targets("Rifle", "idle", full)) == "RifleIdle=1")
	check("own sprint", keys(LocomotionMath.targets("Rifle", "sprint", full)) == "RifleSprint=1")

	local runOnly = { RifleRun = true, Run = true, StrafeLeft = true, StrafeRight = true }
	check("walk falls to the set run", keys(LocomotionMath.targets("Rifle", "walk", runOnly)) == "RifleRun=1")
	check("sprint falls to the set run", keys(LocomotionMath.targets("Rifle", "sprint", runOnly)) == "RifleRun=1")
	check("strafe falls to the set run", keys(LocomotionMath.targets("Rifle", "strafe_right", runOnly)) == "RifleRun=1")
	check("idle without a clip plays nothing", keys(LocomotionMath.targets("Rifle", "idle", runOnly)) == "")

	local legacy = { Run = true, StrafeLeft = true, StrafeRight = true }
	check("no set: run is Run", keys(LocomotionMath.targets("Pistol", "run", legacy)) == "Run=1")
	check("no set: walk is Run", keys(LocomotionMath.targets("Pistol", "walk", legacy)) == "Run=1")
	check("no set: sprint is Run", keys(LocomotionMath.targets("Rifle", "sprint", legacy)) == "Run=1")
	check("no set: strafe is Run plus the lean", keys(LocomotionMath.targets("Rifle", "strafe_left", legacy)) == "Run=1 StrafeLeft=1")
	check("no set: strafe without a lean is Run", keys(LocomotionMath.targets("Rifle", "strafe_right", { Run = true })) == "Run=1")
	check("no set: idle is nothing", keys(LocomotionMath.targets("Rifle", "idle", legacy)) == "")
	check("nothing loaded", keys(LocomotionMath.targets("Rifle", "run", {})) == "")
	check("pistol never borrows rifle clips", keys(LocomotionMath.targets("Pistol", "run", { RifleRun = true, Run = true })) == "Run=1")
end)

group("playback ratio", function()
	check("idle is 1", LocomotionMath.playbackRatio("idle", 30, REFERENCES, 0.8, 1.45) == 1)
	check("run at reference", LocomotionMath.playbackRatio("run", 24, REFERENCES, 0.8, 1.45) == 1)
	check("walk at reference", LocomotionMath.playbackRatio("walk", 10, REFERENCES, 0.8, 1.45) == 1)
	check("sprint at reference", LocomotionMath.playbackRatio("sprint", 36, REFERENCES, 0.8, 1.45) == 1)
	check("strafe uses the run reference", LocomotionMath.playbackRatio("strafe_left", 12, REFERENCES, 0.8, 1.45) == 0.8)
	check("clamped high", LocomotionMath.playbackRatio("run", 60, REFERENCES, 0.8, 1.45) == 1.45)
	check("clamped low", LocomotionMath.playbackRatio("run", 1, REFERENCES, 0.8, 1.45) == 0.8)
	check("missing reference is 1", LocomotionMath.playbackRatio("run", 30, {}, 0.8, 1.45) == 1)
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all locomotion tests passed")
