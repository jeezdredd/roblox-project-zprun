--!strict

-- The hit markers' rules (docs/gameplay/hit-markers.md): which variant a confirmed
-- shot shows, how big and how long, and the marker's look at a moment. One marker at a
-- time: a new confirmation restarts it (no stacked copies), except that a hit or a
-- headshot does not cut short a kill marker still showing. Pure Luau: no services, no
-- engine types, no requires; tests/hitmarkers/run.luau.

export type Variant = "Hit" | "Headshot" | "Kill"

-- What the server confirmed for one shot of the local shooter (all pellets summed).
export type Confirm = {
	damage: number,
	headshot: boolean,
	killed: boolean,
}

export type Config = {
	HIT_DURATION: number,
	KILL_DURATION: number,
	DAMAGE_REFERENCE: number,
	DAMAGE_SCALE: number,
	SCALE_MIN: number,
	SCALE_MAX: number,
	KILL_SCALE: number,
	POP: number,
	POP_SHARE: number,
	FADE_FROM: number,
}

export type State = {
	variant: Variant?,
	startedAt: number,
	duration: number,
	scale: number,
}

export type Frame = {
	visible: boolean,
	variant: Variant?,
	alpha: number,
	scale: number,
}

local HitMarkerMath = {}

local PRIORITY: { [string]: number } = { Hit = 1, Headshot = 2, Kill = 3 }

function HitMarkerMath.idle(): State
	return { variant = nil, startedAt = 0, duration = 0, scale = 1 }
end

-- The variant for a confirmation, or nil when it confirmed nothing (no damage, no kill).
function HitMarkerMath.variantFor(confirm: Confirm): Variant?
	if confirm.killed then
		return "Kill"
	end
	if confirm.damage <= 0 then
		return nil
	end
	return if confirm.headshot then "Headshot" else "Hit"
end

function HitMarkerMath.durationFor(config: Config, variant: Variant): number
	return if variant == "Kill" then config.KILL_DURATION else config.HIT_DURATION
end

function HitMarkerMath.scaleFor(config: Config, variant: Variant, damage: number): number
	if variant == "Kill" then
		return config.KILL_SCALE
	end
	local reference = math.max(config.DAMAGE_REFERENCE, 1)
	local scale = 1 + (math.max(damage, 0) / reference - 1) * config.DAMAGE_SCALE
	return math.clamp(scale, config.SCALE_MIN, config.SCALE_MAX)
end

-- Whether the state still shows at `now`.
function HitMarkerMath.showing(state: State, now: number): boolean
	return state.variant ~= nil and now - state.startedAt < state.duration
end

-- The state after a confirmation at `now`: the marker restarts in the new variant,
-- unless a higher-priority one (a kill over a hit) is still showing, which stays.
function HitMarkerMath.start(config: Config, state: State, now: number, confirm: Confirm): State
	local variant = HitMarkerMath.variantFor(confirm)
	if not variant then
		return state
	end
	local current = state.variant
	if current and HitMarkerMath.showing(state, now) and PRIORITY[current] > PRIORITY[variant] then
		return state
	end
	return {
		variant = variant,
		startedAt = now,
		duration = HitMarkerMath.durationFor(config, variant),
		scale = HitMarkerMath.scaleFor(config, variant, confirm.damage),
	}
end

-- The marker's look at `now`: visible, its alpha (1 opaque) and scale (popping in from
-- POP times the scale, settling by POP_SHARE of the duration, fading after FADE_FROM).
function HitMarkerMath.frame(config: Config, state: State, now: number): Frame
	if not HitMarkerMath.showing(state, now) or state.duration <= 0 then
		return { visible = false, variant = nil, alpha = 0, scale = state.scale }
	end
	local t = math.clamp((now - state.startedAt) / state.duration, 0, 1)
	local alpha = 1
	if t > config.FADE_FROM then
		alpha = math.clamp(1 - (t - config.FADE_FROM) / math.max(1 - config.FADE_FROM, 1e-6), 0, 1)
	end
	local settle = math.clamp(t / math.max(config.POP_SHARE, 1e-6), 0, 1)
	local pop = config.POP + (1 - config.POP) * settle
	return { visible = true, variant = state.variant, alpha = alpha, scale = state.scale * pop }
end

-- Sums one shot's outcomes per pellet into the confirmation the shooter gets: the
-- damage dealt, whether any pellet hit a head, whether any killed. nil when no pellet
-- hurt a zombie.
function HitMarkerMath.combine(outcomes: { Confirm }): Confirm?
	local damage, headshot, killed, any = 0, false, false, false
	for _, outcome in outcomes do
		if outcome.damage > 0 or outcome.killed then
			any = true
			damage += math.max(outcome.damage, 0)
			headshot = headshot or outcome.headshot
			killed = killed or outcome.killed
		end
	end
	if not any then
		return nil
	end
	return { damage = damage, headshot = headshot, killed = killed }
end

return HitMarkerMath
