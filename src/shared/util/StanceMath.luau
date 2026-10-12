--!strict

export type Pose = {
	aside: number,
	up: number,
	back: number,
	pitch: number,
	yaw: number,
	roll: number,
}

type RaiseTimes = { high: number, low: number }

export type Config = {
	CYCLE: { string },
	poses: { [string]: Pose },
	EASE_IN: number,
	EASE_OUT: number,
	raiseTime: { [string]: RaiseTimes },
	RAISE_DEFAULT: RaiseTimes,
	RETURN_AFTER: number,
	UP_THRESHOLD: number,
	LEAN: {
		mode: string,
		offset: number,
		drop: number,
		roll: number,
		easeIn: number,
		easeOut: number,
		viewmodelCounterRoll: number,
		viewmodelAside: number,
		castRadius: number,
		wallMargin: number,
		bodyRoll: number,
	},
	MAG_CHECK: {
		holdTime: number,
		minShow: number,
		easeIn: number,
		easeOut: number,
		showAt: number,
		raiseTime: number,
		readout: string,
		hideAmmoCounter: boolean,
		pose: Pose,
	},
}

type Raise = {
	fromHigh: number,
	fromLow: number,
	fromMag: number,
	elapsed: number,
	duration: number,
}

export type State = {
	selected: string,
	high: number,
	low: number,
	mag: number,
	raising: Raise?,
	upUntil: number,
	checking: boolean,
	checkStartedAt: number,
	checkReleased: boolean,
}

local StanceMath = {}

StanceMath.ZERO = table.freeze({ aside = 0, up = 0, back = 0, pitch = 0, yaw = 0, roll = 0 }) :: Pose

local FIELDS = { "aside", "up", "back", "pitch", "yaw", "roll" }

function StanceMath.new(): State
	return {
		selected = "mid",
		high = 0,
		low = 0,
		mag = 0,
		raising = nil,
		upUntil = -math.huge,
		checking = false,
		checkStartedAt = 0,
		checkReleased = false,
	}
end

function StanceMath.scaled(pose: Pose, factor: number): Pose
	local out = {} :: any
	for _, field in FIELDS do
		out[field] = (pose :: any)[field] * factor
	end
	return out :: Pose
end

function StanceMath.added(a: Pose, b: Pose): Pose
	local out = {} :: any
	for _, field in FIELDS do
		out[field] = (a :: any)[field] + (b :: any)[field]
	end
	return out :: Pose
end

function StanceMath.pose(config: Config, state: State): Pose
	local pose = StanceMath.added(StanceMath.scaled(config.poses.high, state.high), StanceMath.scaled(config.poses.low, state.low))
	return StanceMath.added(pose, StanceMath.scaled(config.MAG_CHECK.pose, state.mag))
end

local function smoothstep(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

function StanceMath.ease(current: number, target: number, rateIn: number, rateOut: number, deltaTime: number): number
	local rate = if target > current then rateIn else rateOut
	local nextValue = current + (target - current) * (1 - math.exp(-rate * math.max(deltaTime, 0)))
	if math.abs(target - nextValue) < 1e-3 then
		return target
	end
	return nextValue
end

function StanceMath.nextStance(config: Config, current: string): string
	local cycle = config.CYCLE
	for index, name in cycle do
		if name == current then
			return cycle[index % #cycle + 1]
		end
	end
	return cycle[1]
end

function StanceMath.select(state: State, stance: string)
	state.selected = stance
end

function StanceMath.isUp(config: Config, state: State): boolean
	local threshold = config.UP_THRESHOLD
	return state.raising == nil and state.high <= threshold and state.low <= threshold and state.mag <= threshold
end

function StanceMath.raiseDuration(config: Config, state: State, class: string?): number
	local times = (if class then config.raiseTime[class] else nil) or config.RAISE_DEFAULT
	return math.max(times.high * state.high, times.low * state.low, config.MAG_CHECK.raiseTime * state.mag)
end

function StanceMath.requestFire(config: Config, state: State, class: string?, now: number): boolean
	state.checking = false
	state.checkReleased = false
	if StanceMath.isUp(config, state) then
		state.upUntil = now + config.RETURN_AFTER
		return true
	end
	if state.raising == nil then
		local duration = StanceMath.raiseDuration(config, state, class)
		state.raising = { fromHigh = state.high, fromLow = state.low, fromMag = state.mag, elapsed = 0, duration = duration }
		state.upUntil = now + duration + config.RETURN_AFTER
	end
	return false
end

function StanceMath.raiseRemaining(state: State): number
	local raise = state.raising
	if not raise then
		return 0
	end
	return math.max(raise.duration - raise.elapsed, 0)
end

function StanceMath.step(config: Config, state: State, deltaTime: number, now: number, suppressed: boolean)
	local raise = state.raising
	if raise then
		raise.elapsed += math.max(deltaTime, 0)
		local remaining = if raise.duration > 0 then 1 - smoothstep(raise.elapsed / raise.duration) else 0
		if raise.elapsed >= raise.duration then
			remaining = 0
			state.raising = nil
		end
		state.high = raise.fromHigh * remaining
		state.low = raise.fromLow * remaining
		state.mag = raise.fromMag * remaining
		return
	end

	if state.checking and state.checkReleased and now - state.checkStartedAt >= config.MAG_CHECK.minShow then
		state.checking = false
		state.checkReleased = false
	end

	local up = suppressed or now < state.upUntil
	local targetHigh = if not up and state.selected == "high" then 1 else 0
	local targetLow = if not up and state.selected == "low" then 1 else 0
	local targetMag = if state.checking and not suppressed then 1 else 0
	if targetMag > 0 then
		targetHigh = 0
		targetLow = 0
	end
	state.high = StanceMath.ease(state.high, targetHigh, config.EASE_IN, config.EASE_OUT, deltaTime)
	state.low = StanceMath.ease(state.low, targetLow, config.EASE_IN, config.EASE_OUT, deltaTime)
	local check = config.MAG_CHECK
	state.mag = StanceMath.ease(state.mag, targetMag, check.easeIn, check.easeOut, deltaTime)
end

function StanceMath.isHold(config: Config, heldFor: number): boolean
	return heldFor >= config.MAG_CHECK.holdTime
end

function StanceMath.startCheck(state: State, now: number)
	if state.checking then
		return
	end
	state.checking = true
	state.checkReleased = false
	state.checkStartedAt = now
end

function StanceMath.releaseCheck(config: Config, state: State, now: number)
	if not state.checking then
		return
	end
	if now - state.checkStartedAt >= config.MAG_CHECK.minShow then
		state.checking = false
		state.checkReleased = false
	else
		state.checkReleased = true
	end
end

function StanceMath.cancelCheck(state: State)
	state.checking = false
	state.checkReleased = false
end

function StanceMath.countVisible(config: Config, state: State): boolean
	return state.mag >= config.MAG_CHECK.showAt
end

function StanceMath.readout(mode: string, mag: number, size: number): string
	local rounds = math.max(math.floor(mag), 0)
	if mode ~= "estimate" then
		return string.format("%d / %d", rounds, size)
	end
	if rounds <= 0 then
		return "Empty"
	end
	local share = if size > 0 then rounds / size else 0
	if share >= 1 then
		return "Full"
	elseif share >= 0.7 then
		return "Almost full"
	elseif share >= 0.35 then
		return "About half"
	end
	return "Almost empty"
end

function StanceMath.leanHeld(leftHeld: boolean, rightHeld: boolean, lastSide: number): number
	if leftHeld and rightHeld then
		return if lastSide < 0 then -1 else 1
	elseif leftHeld then
		return -1
	elseif rightHeld then
		return 1
	end
	return 0
end

function StanceMath.leanToggled(current: number, side: number): number
	if current == side then
		return 0
	end
	return side
end

function StanceMath.leanRoom(config: Config, hitDistance: number?): number
	local lean = config.LEAN
	if hitDistance == nil or lean.offset <= 0 then
		return 1
	end
	return math.clamp((hitDistance - lean.wallMargin) / lean.offset, 0, 1)
end

function StanceMath.leanCamera(config: Config, lean: number, room: number): (number, number, number)
	local settings = config.LEAN
	local value = math.clamp(lean, -1, 1)
	local share = math.clamp(room, 0, 1)
	return value * settings.offset * share, -math.abs(value) * settings.drop * share, -value * settings.roll
end

function StanceMath.leanViewmodel(config: Config, lean: number): Pose
	local settings = config.LEAN
	local value = math.clamp(lean, -1, 1)
	return {
		aside = value * settings.viewmodelAside,
		up = 0,
		back = 0,
		pitch = 0,
		yaw = 0,
		roll = value * settings.roll * settings.viewmodelCounterRoll,
	}
end

function StanceMath.bodyRoll(config: Config, lean: number): number
	return -math.clamp(lean, -1, 1) * config.LEAN.bodyRoll
end

function StanceMath.quantizeLean(lean: number): number
	return math.floor(math.clamp(lean, -1, 1) * 10 + 0.5) / 10
end

function StanceMath.validateLean(value: any): number
	if typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return 0
	end
	return math.clamp(value, -1, 1)
end

return StanceMath
