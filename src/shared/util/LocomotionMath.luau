--!strict

local LocomotionMath = {}

export type Gait = "idle" | "walk" | "run" | "sprint" | "strafe_left" | "strafe_right"

export type Thresholds = {
	walkMax: number,
	strafeAxis: number,
}

export type References = { [string]: number }

LocomotionMath.GAITS = { "idle", "walk", "run", "sprint", "strafe_left", "strafe_right" } :: { Gait }

local SUFFIX: { [string]: string } = {
	idle = "Idle",
	walk = "Walk",
	run = "Run",
	sprint = "Sprint",
	strafe_left = "StrafeLeft",
	strafe_right = "StrafeRight",
}

local FALLBACK: { [string]: { string } } = {
	idle = {},
	walk = { "run" },
	run = {},
	sprint = { "run" },
	strafe_left = { "run" },
	strafe_right = { "run" },
}

local LEGACY_STRAFE: { [string]: string } = {
	strafe_left = "StrafeLeft",
	strafe_right = "StrafeRight",
}

function LocomotionMath.setFor(class: string?): string
	return if class == "Pistol" then "Pistol" else "Rifle"
end

function LocomotionMath.clipId(set: string, gait: string): string
	return set .. (SUFFIX[gait] or "")
end

function LocomotionMath.gaitFor(moving: boolean, speed: number, lateral: number, sprinting: boolean, thresholds: Thresholds): Gait
	if not moving then
		return "idle"
	end
	if math.abs(lateral) >= thresholds.strafeAxis then
		return if lateral < 0 then "strafe_left" else "strafe_right"
	end
	if sprinting then
		return "sprint"
	end
	if speed < thresholds.walkMax then
		return "walk"
	end
	return "run"
end

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
