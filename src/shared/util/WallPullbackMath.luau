--!strict

export type Pose = {
	back: number,
	down: number,
	aside: number,
	pitchUp: number,
	yawAside: number,
	roll: number,
}

export type Config = {
	reach: { [string]: number },
	REACH_DEFAULT: number,
	FULL_SHARE: number,
	EASE_IN: number,
	EASE_OUT: number,
	RELEASE_MARGIN: number,
	pose: Pose,
}

local WallPullbackMath = {}

function WallPullbackMath.reachFor(config: Config, class: string?): number
	local reach = if class then config.reach[class] else nil
	return reach or config.REACH_DEFAULT
end

function WallPullbackMath.fullDistance(config: Config, reach: number): number
	return math.max(reach, 0) * config.FULL_SHARE
end

local function smoothstep(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

function WallPullbackMath.targetFor(config: Config, distance: number?, reach: number): number
	if distance == nil or reach <= 0 or distance >= reach then
		return 0
	end
	local full = WallPullbackMath.fullDistance(config, reach)
	if distance <= full then
		return 1
	end
	return smoothstep((reach - distance) / (reach - full))
end

function WallPullbackMath.ease(config: Config, current: number, target: number, deltaTime: number): number
	local rate = if target > current then config.EASE_IN else config.EASE_OUT
	local nextValue = current + (target - current) * (1 - math.exp(-rate * math.max(deltaTime, 0)))
	if math.abs(target - nextValue) < 1e-3 then
		return target
	end
	return math.clamp(nextValue, 0, 1)
end

function WallPullbackMath.poseAt(config: Config, blend: number): Pose
	local b = math.clamp(blend, 0, 1)
	local full = config.pose
	return {
		back = full.back * b,
		down = full.down * b,
		aside = full.aside * b,
		pitchUp = full.pitchUp * b,
		yawAside = full.yawAside * b,
		roll = full.roll * b,
	}
end

function WallPullbackMath.blocked(config: Config, wasBlocked: boolean, distance: number?, reach: number): boolean
	if distance == nil then
		return false
	end
	local full = WallPullbackMath.fullDistance(config, reach)
	if wasBlocked then
		return distance <= full + config.RELEASE_MARGIN
	end
	return distance <= full
end

return WallPullbackMath
