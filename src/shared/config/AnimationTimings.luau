--!strict

export type Step = {
	pose: string,
	duration: number,
	easing: string,
	phase: string?,
	fallback: string?,
}

export type Sequence = {
	id: string,
	steps: { Step },
	priority: number,
	looped: boolean,
	blendTime: number?,
}

local AnimationTimings = {}

AnimationTimings.BLEND_TIME = 0.12

AnimationTimings.sequences = {
	Equip = {
		id = "Equip",
		priority = 2,
		looped = false,
		steps = {
			{ pose = "equip", duration = 0, easing = "linear" },
			{ pose = "rackGrab", duration = 0.3, easing = "outCubic", fallback = "idle" },
			{ pose = "rackPull", duration = 0.12, easing = "inOutQuad", phase = "BoltBack", fallback = "idle" },
			{ pose = "rackRelease", duration = 0.1, easing = "outQuad", phase = "BoltForward", fallback = "idle" },
			{ pose = "idle", duration = 0.22, easing = "outCubic" },
		},
	},

	Fire = {
		id = "Fire",
		priority = 3,
		looped = false,
		blendTime = 0,
		steps = {
			{ pose = "fire", duration = 0.02, easing = "linear" },
			{ pose = "idle", duration = 0.18, easing = "outCubic" },
		},
	},

	ReloadShort = {
		id = "ReloadShort",
		priority = 2,
		looped = false,
		steps = {
			{ pose = "reloadStart", duration = 0.18, easing = "outQuad" },
			{ pose = "grabMag", duration = 0.2, easing = "inOutQuad", fallback = "reloadStart" },
			{ pose = "magOut", duration = 0.18, easing = "inOutQuad", phase = "MagOut" },
			{ pose = "magAway", duration = 0.3, easing = "inOutQuad", fallback = "magOut" },
			{ pose = "magReturn", duration = 0.36, easing = "inOutQuad", fallback = "magOut" },
			{ pose = "magIn", duration = 0.18, easing = "outQuad", phase = "MagIn" },
			{ pose = "magSeat", duration = 0.08, easing = "outQuad", fallback = "magIn" },
			{ pose = "reloadEnd", duration = 0.22, easing = "inOutQuad" },
			{ pose = "idle", duration = 0.16, easing = "outCubic" },
		},
	},

	ReloadFull = {
		id = "ReloadFull",
		priority = 2,
		looped = false,
		steps = {
			{ pose = "reloadStart", duration = 0.16, easing = "outQuad" },
			{ pose = "grabMag", duration = 0.18, easing = "inOutQuad", fallback = "reloadStart" },
			{ pose = "magOut", duration = 0.16, easing = "inOutQuad", phase = "MagOut" },
			{ pose = "magAway", duration = 0.28, easing = "inOutQuad", fallback = "magOut" },
			{ pose = "magReturn", duration = 0.32, easing = "inOutQuad", fallback = "magOut" },
			{ pose = "magIn", duration = 0.16, easing = "outQuad", phase = "MagIn" },
			{ pose = "magSeat", duration = 0.08, easing = "outQuad", fallback = "magIn" },
			{ pose = "boltBack", duration = 0.18, easing = "inOutQuad", phase = "BoltBack" },
			{ pose = "boltForward", duration = 0.1, easing = "outQuad", phase = "BoltForward" },
			{ pose = "reloadEnd", duration = 0.2, easing = "inOutQuad" },
			{ pose = "idle", duration = 0.14, easing = "outCubic" },
		},
	},

	Inspect = {
		id = "Inspect",
		priority = 1,
		looped = false,
		steps = {
			{ pose = "inspectA", duration = 0.3, easing = "outCubic" },
			{ pose = "inspectB", duration = 0.42, easing = "inOutQuad" },
			{ pose = "inspectC", duration = 0.34, easing = "inOutQuad" },
			{ pose = "idle", duration = 0.28, easing = "outCubic" },
		},
	},

	Sprint = {
		id = "Sprint",
		priority = 1,
		looped = true,
		steps = {
			{ pose = "sprint", duration = 0.24, easing = "outCubic" },
		},
	},
} :: { [string]: Sequence }

function AnimationTimings.get(id: string): Sequence?
	return AnimationTimings.sequences[id]
end

function AnimationTimings.duration(id: string): number
	local sequence = AnimationTimings.sequences[id]
	if not sequence then
		return 0
	end
	local total = 0
	for _, step in sequence.steps do
		total += step.duration
	end
	return total
end

return AnimationTimings
