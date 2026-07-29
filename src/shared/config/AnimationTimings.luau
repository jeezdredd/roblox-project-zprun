--!strict

-- Sequence timings live apart from the poses because they get retuned far more often.
-- A step holds until `duration` elapses, easing from the previous step's pose.
-- `phase` names fire a PhaseReached signal the moment the step starts, which is what
-- drives reload audio — a marker in the sequence, never a wall-clock timer.

export type Step = {
	pose: string,
	duration: number,
	easing: string,
	phase: string?,
}

export type Sequence = {
	id: string,
	steps: { Step },
	priority: number,
	looped: boolean,
	blendTime: number?,
}

local AnimationTimings = {}

-- Default blend-in for a sequence that replaces another. A sequence shorter than this
-- must set its own `blendTime`, otherwise the blend is still ramping in while the pose
-- is already easing out and the authored offsets only ever render at a fraction.
AnimationTimings.BLEND_TIME = 0.12

AnimationTimings.sequences = {
	Equip = {
		id = "Equip",
		priority = 2,
		looped = false,
		steps = {
			{ pose = "equip", duration = 0, easing = "linear" },
			{ pose = "idle", duration = 0.34, easing = "outCubic" },
		},
	},

	-- Recoil snaps and decays: no blend-in at all, otherwise the kick reads as a nudge.
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

	-- magazine still has rounds: no chambering pass
	ReloadShort = {
		id = "ReloadShort",
		priority = 2,
		looped = false,
		steps = {
			{ pose = "reloadStart", duration = 0.16, easing = "outQuad" },
			{ pose = "magOut", duration = 0.22, easing = "inOutQuad", phase = "MagOut" },
			{ pose = "magIn", duration = 0.28, easing = "outQuad", phase = "MagIn" },
			{ pose = "reloadEnd", duration = 0.16, easing = "outQuad" },
			{ pose = "idle", duration = 0.14, easing = "outCubic" },
		},
	},

	-- magazine ran dry: adds the bolt/slide pass at the end
	ReloadFull = {
		id = "ReloadFull",
		priority = 2,
		looped = false,
		steps = {
			{ pose = "reloadStart", duration = 0.16, easing = "outQuad" },
			{ pose = "magOut", duration = 0.24, easing = "inOutQuad", phase = "MagOut" },
			{ pose = "magIn", duration = 0.3, easing = "outQuad", phase = "MagIn" },
			{ pose = "boltBack", duration = 0.16, easing = "outQuad", phase = "BoltBack" },
			{ pose = "boltForward", duration = 0.12, easing = "outQuad", phase = "BoltForward" },
			{ pose = "reloadEnd", duration = 0.14, easing = "outQuad" },
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
