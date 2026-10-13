--!strict

export type State = {
	validated: number,
	best: number,
	start: number,
	elapsed: number,
	strikes: number,
	lastStrikeAt: number,
}

export type Verdict = "ok" | "clamped" | "strike" | "snap"

local RunDistanceGuard = {}

RunDistanceGuard.STEP_SLACK = 1.25
RunDistanceGuard.STEP_EPSILON = 0.25
RunDistanceGuard.TOTAL_SLACK = 1.1
RunDistanceGuard.TOTAL_MARGIN = 20
RunDistanceGuard.JUMP_FACTOR = 3
RunDistanceGuard.JUMP_MARGIN = 10
RunDistanceGuard.GAP_LIMIT = 80
RunDistanceGuard.SNAP_STRIKES = 3
RunDistanceGuard.STRIKE_WINDOW = 5

function RunDistanceGuard.new(start: number): State
	return {
		validated = start,
		best = start,
		start = start,
		elapsed = 0,
		strikes = 0,
		lastStrikeAt = -math.huge,
	}
end

function RunDistanceGuard.stepAllowance(maxSpeed: number, deltaTime: number): number
	return maxSpeed * deltaTime * RunDistanceGuard.STEP_SLACK + RunDistanceGuard.STEP_EPSILON
end

function RunDistanceGuard.cap(state: State, maxSpeed: number): number
	return state.start + state.elapsed * maxSpeed * RunDistanceGuard.TOTAL_SLACK + RunDistanceGuard.TOTAL_MARGIN
end

local function strike(state: State, now: number): Verdict
	if now - state.lastStrikeAt > RunDistanceGuard.STRIKE_WINDOW then
		state.strikes = 0
	end
	state.strikes += 1
	state.lastStrikeAt = now
	if state.strikes >= RunDistanceGuard.SNAP_STRIKES then
		state.strikes = 0
		return "snap"
	end
	return "strike"
end

function RunDistanceGuard.step(state: State, forward: number, moved: number, deltaTime: number, maxSpeed: number, now: number): Verdict
	state.elapsed += math.max(deltaTime, 0)
	local allowed = RunDistanceGuard.stepAllowance(maxSpeed, deltaTime)
	local verdict: Verdict = "ok"
	if moved > allowed * RunDistanceGuard.JUMP_FACTOR + RunDistanceGuard.JUMP_MARGIN then
		verdict = strike(state, now)
	else
		local delta = forward - state.validated
		if delta > allowed then
			state.validated += allowed
			verdict = "clamped"
		else
			state.validated += delta
		end
		if forward - state.validated > RunDistanceGuard.GAP_LIMIT then
			state.strikes = 0
			verdict = "snap"
		end
	end
	local capped = math.min(state.validated, RunDistanceGuard.cap(state, maxSpeed))
	if capped > state.best then
		state.best = capped
	end
	return verdict
end

function RunDistanceGuard.rebase(state: State, forward: number)
	state.validated = forward
	state.start = forward
	state.elapsed = 0
	state.strikes = 0
end

return RunDistanceGuard
