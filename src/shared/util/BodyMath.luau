--!strict

-- Pure math for the third-person body: aim smoothing and spread, the wire encoding of
-- the aim, recoil springs, the reload / equip / pump gesture timelines built from
-- WeaponsConfig numbers, the sprint blend and the LOD bands. Numbers in, numbers out,
-- no Roblox services or datatypes, so `luau tests/body/run.luau` exercises it outside
-- Studio and the server relay can share the validation. Angles are degrees, times
-- seconds, distances studs.

local BodyMath = {}

export type AimSpread = {
	waistPitch: number,
	neckPitch: number,
	armPitch: number,
	waistYaw: number,
	neckYaw: number,
}

export type AimShares = {
	waistPitch: number,
	neckPitch: number,
	armPitch: number,
	waistYaw: number,
	neckYaw: number,
	pitchClamp: number,
	yawClamp: number,
}

export type SpringState = { value: number, velocity: number }

export type Keyframe = { t: number, pose: string }

export type Timeline = { Keyframe }

export type PoseSample = { from: string, to: string, alpha: number }

export type ShellReloadNumbers = {
	start: number,
	perShell: number,
	addAt: number,
	finish: number,
	chamber: number,
	exit: number,
}

export type LodBands = {
	full: number,
	half: number,
	quarter: number,
	ikRange: number,
}

function BodyMath.wrapDegrees(angle: number): number
	local wrapped = (angle + 180) % 360 - 180
	return if wrapped == -180 then 180 else wrapped
end

-- Exponential approach with a time constant, wrapping so the short way round is taken.
function BodyMath.approachAngle(current: number, target: number, deltaTime: number, timeConstant: number): number
	local difference = BodyMath.wrapDegrees(target - current)
	if timeConstant <= 0 then
		return current + difference
	end
	return current + difference * (1 - math.exp(-deltaTime / timeConstant))
end

function BodyMath.approach(current: number, target: number, deltaTime: number, timeConstant: number): number
	if timeConstant <= 0 then
		return target
	end
	return current + (target - current) * (1 - math.exp(-deltaTime / timeConstant))
end

function BodyMath.smoothstep(alpha: number): number
	local t = math.clamp(alpha, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Signed yaw of a flat direction relative to a flat reference direction: positive when
-- the direction is to the left of the reference (a positive Y rotation).
function BodyMath.signedYaw(referenceX: number, referenceZ: number, directionX: number, directionZ: number): number
	local cross = referenceZ * directionX - referenceX * directionZ
	local dot = referenceX * directionX + referenceZ * directionZ
	if cross == 0 and dot == 0 then
		return 0
	end
	return math.deg(math.atan2(cross, dot))
end

-- Pitch of a look vector from its vertical component: positive looking up.
function BodyMath.pitchOf(lookY: number): number
	return math.deg(math.asin(math.clamp(lookY, -1, 1)))
end

-- The aim split over the joints: the torso twists before the feet turn, the head looks
-- at the target, the arms carry the rest of the pitch. Clamped first, so the shares of
-- a clamped angle always sum to the clamp.
function BodyMath.spreadAim(pitch: number, yaw: number, shares: AimShares, armScale: number): AimSpread
	local clampedPitch = math.clamp(pitch, -shares.pitchClamp, shares.pitchClamp)
	local clampedYaw = math.clamp(yaw, -shares.yawClamp, shares.yawClamp)
	return {
		waistPitch = clampedPitch * shares.waistPitch,
		neckPitch = clampedPitch * shares.neckPitch,
		armPitch = clampedPitch * shares.armPitch * armScale,
		waistYaw = clampedYaw * shares.waistYaw,
		neckYaw = clampedYaw * shares.neckYaw,
	}
end

-- Whole degrees on the wire.
function BodyMath.quantize(angle: number): number
	return math.floor(angle + 0.5)
end

-- Send when either angle moved a whole degree and the rate allows, or on the keepalive.
function BodyMath.shouldSend(
	lastPitch: number,
	lastYaw: number,
	pitch: number,
	yaw: number,
	sinceLastSend: number,
	minInterval: number,
	keepalive: number,
	minChange: number
): boolean
	if sinceLastSend < minInterval then
		return false
	end
	if sinceLastSend >= keepalive then
		return true
	end
	return math.abs(pitch - lastPitch) >= minChange or math.abs(BodyMath.wrapDegrees(yaw - lastYaw)) >= minChange
end

-- Server-side check of an aim packet: both numbers, finite, clamped into the limits.
function BodyMath.validateAim(pitch: any, yaw: any, pitchLimit: number, yawLimit: number): (boolean, number, number)
	if typeof(pitch) ~= "number" or typeof(yaw) ~= "number" then
		return false, 0, 0
	end
	if pitch ~= pitch or yaw ~= yaw or math.abs(pitch) == math.huge or math.abs(yaw) == math.huge then
		return false, 0, 0
	end
	return true, math.clamp(pitch, -pitchLimit, pitchLimit), math.clamp(BodyMath.wrapDegrees(yaw), -yawLimit, yawLimit)
end

-- Damped spring toward zero, stepped with the closed-form solution of the oscillator
-- (under-, critically and over-damped branches), so any frame time lands on the exact
-- curve: no substeps, no numerical over-damping, and the peak of an impulse is where
-- impulseForPeak says. The recoil kick and snap are impulses on the velocity.
function BodyMath.springStep(state: SpringState, stiffness: number, damping: number, deltaTime: number): number
	if deltaTime <= 0 then
		return state.value
	end
	local omega = math.sqrt(math.max(stiffness, 1e-9))
	local zeta = damping / (2 * omega)
	local x = state.value
	local v = state.velocity
	local t = deltaTime
	if zeta < 1 - 1e-6 then
		local damped = omega * math.sqrt(1 - zeta * zeta)
		local decay = math.exp(-zeta * omega * t)
		local cosine = math.cos(damped * t)
		local sine = math.sin(damped * t)
		local a = x
		local b = (v + zeta * omega * x) / damped
		state.value = decay * (a * cosine + b * sine)
		state.velocity = decay * ((-zeta * omega * a + damped * b) * cosine + (-zeta * omega * b - damped * a) * sine)
	elseif zeta <= 1 + 1e-6 then
		local decay = math.exp(-omega * t)
		local slope = v + omega * x
		state.value = decay * (x + slope * t)
		state.velocity = decay * (v - omega * slope * t)
	else
		local root = omega * math.sqrt(zeta * zeta - 1)
		local r1 = -zeta * omega + root
		local r2 = -zeta * omega - root
		local c1 = (v - r2 * x) / (r1 - r2)
		local c2 = x - c1
		local e1 = math.exp(r1 * t)
		local e2 = math.exp(r2 * t)
		state.value = c1 * e1 + c2 * e2
		state.velocity = c1 * r1 * e1 + c2 * r2 * e2
	end
	return state.value
end

function BodyMath.springImpulse(state: SpringState, impulse: number)
	state.velocity += impulse
end

-- The velocity impulse that makes a spring near critical damping peak at `peak`: with
-- x(t) = v t e^(-w t) the peak is v / (w e) at t = 1 / w.
function BodyMath.impulseForPeak(peak: number, stiffness: number): number
	return peak * math.sqrt(math.max(stiffness, 1e-6)) * math.exp(1)
end

-- The magazine reload as poses of the support hand over time: to the belt, to the mag
-- well with the fresh magazine, the seat at ammo-add, then the chambering action from
-- empty (bolt / charging handle: the hand to the charge socket, pulled, released) and
-- back on the gun by the total. `chargeTime` is how long the pull and release take.
function BodyMath.magazineTimeline(ammoAdd: number, total: number, empty: boolean, chargeTime: number): Timeline
	local seat = math.min(ammoAdd, total)
	local travel = math.min(0.45, seat * 0.4)
	local timeline: Timeline = {
		{ t = 0, pose = "grip" },
		{ t = math.max(seat - travel * 2, 0.05), pose = "belt" },
		{ t = math.max(seat - travel * 0.45, 0.1), pose = "well" },
		{ t = seat, pose = "seat" },
	}
	local after = seat
	if empty and chargeTime > 0 then
		local pull = math.min(chargeTime, math.max(total - seat, 0.05))
		table.insert(timeline, { t = seat + pull * 0.35, pose = "charge" })
		table.insert(timeline, { t = seat + pull * 0.7, pose = "chargePulled" })
		table.insert(timeline, { t = seat + pull, pose = "charge" })
		after = seat + pull
	end
	table.insert(timeline, { t = math.max(total, after + 0.05), pose = "grip" })
	return timeline
end

-- The pump shotgun reload: the gun rolls over (`start`), one belt-to-port cycle per
-- shell seated at `addAt` inside it, the finish, and the pump when nothing was chambered.
function BodyMath.shellTimeline(shell: ShellReloadNumbers, shells: number, empty: boolean, scale: number): Timeline
	local timeline: Timeline = { { t = 0, pose = "grip" } }
	local start = shell.start * scale
	local perShell = shell.perShell * scale
	local addAt = shell.addAt * scale
	local finish = shell.finish * scale
	local count = math.max(shells, 0)
	for index = 1, count do
		local cycle = start + (index - 1) * perShell
		table.insert(timeline, { t = cycle, pose = "belt" })
		table.insert(timeline, { t = cycle + addAt * 0.75, pose = "port" })
		table.insert(timeline, { t = cycle + addAt, pose = "seat" })
	end
	local loopEnd = start + count * perShell
	local total = loopEnd + finish
	if empty then
		local chamber = shell.chamber * scale
		table.insert(timeline, { t = loopEnd + finish * 0.5, pose = "pump" })
		table.insert(timeline, { t = loopEnd + finish * 0.5 + chamber * 0.45, pose = "pumpBack" })
		table.insert(timeline, { t = loopEnd + finish * 0.5 + chamber * 0.9, pose = "pump" })
		total += chamber
	end
	table.insert(timeline, { t = total, pose = "grip" })
	return timeline
end

-- The pump stroke after a shot on a weapon that does not eject on fire, starting `delay`
-- seconds after the shot so the kick reads first.
function BodyMath.pumpTimeline(duration: number, delay: number): Timeline
	return {
		{ t = 0, pose = "grip" },
		{ t = delay, pose = "grip" },
		{ t = delay + duration * 0.4, pose = "pumpBack" },
		{ t = delay + duration * 0.85, pose = "pump" },
		{ t = delay + duration, pose = "grip" },
	}
end

-- The draw: from the lowered pose up to the grip over the weapon's draw time.
function BodyMath.equipTimeline(drawTime: number): Timeline
	return {
		{ t = 0, pose = "lowered" },
		{ t = drawTime * 0.8, pose = "grip" },
		{ t = drawTime, pose = "grip" },
	}
end

function BodyMath.timelineDuration(timeline: Timeline): number
	local last = timeline[#timeline]
	return if last then last.t else 0
end

-- The segment of a timeline at `elapsed` with a smoothstep alpha between its two poses;
-- before the first keyframe it holds the first pose, after the last it holds the last.
function BodyMath.poseAt(timeline: Timeline, elapsed: number, sample: PoseSample): PoseSample
	local count = #timeline
	if count == 0 then
		sample.from = "grip"
		sample.to = "grip"
		sample.alpha = 1
		return sample
	end
	local first = timeline[1]
	if elapsed <= first.t then
		sample.from = first.pose
		sample.to = first.pose
		sample.alpha = 1
		return sample
	end
	for index = 2, count do
		local keyframe = timeline[index]
		if elapsed <= keyframe.t then
			local previous = timeline[index - 1]
			local span = keyframe.t - previous.t
			sample.from = previous.pose
			sample.to = keyframe.pose
			sample.alpha = if span <= 0 then 1 else BodyMath.smoothstep((elapsed - previous.t) / span)
			return sample
		end
	end
	local last = timeline[count]
	sample.from = last.pose
	sample.to = last.pose
	sample.alpha = 1
	return sample
end

-- Sprint switches on above the threshold and off below it minus the hysteresis, so a
-- speed hovering at the edge does not flicker the pose.
function BodyMath.sprintTarget(speed: number, threshold: number, hysteresis: number, sprinting: boolean): boolean
	if sprinting then
		return speed > threshold - hysteresis
	end
	return speed >= threshold
end

-- Update cadence in frames for a character at `distance` (0 means never) and whether
-- the hand IK stays on.
function BodyMath.lodBand(distance: number, bands: LodBands): (number, boolean)
	local ikOn = distance <= bands.ikRange
	if distance <= bands.full then
		return 1, ikOn
	elseif distance <= bands.half then
		return 2, ikOn
	elseif distance <= bands.quarter then
		return 4, ikOn
	end
	return 0, false
end

-- Whether a character with `index` in the round robin updates this frame at `cadence`.
function BodyMath.updatesThisFrame(frame: number, index: number, cadence: number): boolean
	if cadence <= 0 then
		return false
	end
	return (frame + index) % cadence == 0
end

return BodyMath
