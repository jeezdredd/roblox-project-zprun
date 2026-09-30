--!strict

-- Pure rules for the third-person locomotion clips: which clip set a weapon class
-- uses, which gait the movement state asks for, which loaded clip answers it (with the
-- fallbacks down to the generic Run clip) and how fast it plays. No services and no
-- requires, so tests/animation/run.luau runs it under the standalone Luau CLI.
-- Design: docs/animation/third-person-locomotion.md.

local LocomotionMath = {}

export type Gait = "idle" | "walk" | "run" | "sprint" | "strafe_left" | "strafe_right"

export type Thresholds = {
	-- below this speed a moving character walks
	walkMax: number,
	-- lateral input at or beyond this magnitude strafes
	strafeAxis: number,
	-- the strafe clips are walking side steps: at or above this speed a character with
	-- lateral input keeps its run (the auto-run swerves; it never side-steps at speed)
	strafeMaxSpeed: number,
}

export type References = { [string]: number }

LocomotionMath.GAITS = { "idle", "walk", "run", "sprint", "strafe_left", "strafe_right" } :: { Gait }

-- clip id suffix per gait
local SUFFIX: { [string]: string } = {
	idle = "Idle",
	walk = "Walk",
	run = "Run",
	sprint = "Sprint",
	strafe_left = "StrafeLeft",
	strafe_right = "StrafeRight",
}

-- gaits tried in turn inside a set when the wanted one has no clip
local FALLBACK: { [string]: { string } } = {
	idle = {},
	walk = { "run" },
	run = {},
	sprint = { "run" },
	strafe_left = { "run" },
	strafe_right = { "run" },
}

-- the legacy additive strafe clips, played over Run when a set has no strafe gait
local LEGACY_STRAFE: { [string]: string } = {
	strafe_left = "StrafeLeft",
	strafe_right = "StrafeRight",
}

-- The clip set a weapon class runs with: the pistol set for a pistol, the rifle set for
-- everything else (SMGs and shotguns are carried two-handed).
function LocomotionMath.setFor(class: string?): string
	return if class == "Pistol" then "Pistol" else "Rifle"
end

-- Clip id of a gait in a set: ("Rifle", "strafe_left") -> "RifleStrafeLeft".
function LocomotionMath.clipId(set: string, gait: string): string
	return set .. (SUFFIX[gait] or "")
end

-- The gait the movement asks for. `sprinting` is the hysteresis decision made from the
-- sprint threshold (BodyMath.sprintTarget); a sprint never strafes.
function LocomotionMath.gaitFor(moving: boolean, speed: number, lateral: number, sprinting: boolean, thresholds: Thresholds): Gait
	if not moving then
		return "idle"
	end
	if sprinting then
		return "sprint"
	end
	if math.abs(lateral) >= thresholds.strafeAxis and speed < thresholds.strafeMaxSpeed then
		return if lateral < 0 then "strafe_left" else "strafe_right"
	end
	if speed < thresholds.walkMax then
		return "walk"
	end
	return "run"
end

-- Clip weights that answer a gait with what is loaded: the set's own clip, else the
-- set's fallback gaits, else the generic Run (with the legacy additive strafe on top
-- when it exists). Idle with no idle clip plays nothing, as before the sets existed.
function LocomotionMath.targets(set: string, gait: Gait, available: { [string]: boolean }): { [string]: number }
	local out: { [string]: number } = {}
	local own = LocomotionMath.clipId(set, gait)
	if available[own] then
		out[own] = 1
		return out
	end
	for _, fallback in FALLBACK[gait] do
		local id = LocomotionMath.clipId(set, fallback)
		if available[id] then
			out[id] = 1
			return out
		end
	end
	if gait == "idle" then
		return out
	end
	if available.Run then
		out.Run = 1
	end
	local legacy = LEGACY_STRAFE[gait]
	if legacy and available[legacy] then
		out[legacy] = 1
	end
	return out
end

-- Playback rate of a gait clip so the feet match the ground speed: the speed over the
-- gait's reference speed, clamped. Idle plays at 1.
function LocomotionMath.playbackRatio(gait: Gait, speed: number, references: References, min: number, max: number): number
	if gait == "idle" then
		return 1
	end
	local reference = references[gait] or references.run
	if not reference or reference <= 0 then
		return 1
	end
	return math.clamp(speed / reference, min, max)
end

return LocomotionMath
