--!strict

export type ReadyCheck = {
	members: { number },
	ready: { [number]: boolean },
	startedAt: number,
	timeout: number,
}

export type ReadyStatus = "Waiting" | "AllReady" | "TimedOut" | "Empty"

export type SkipVote = {
	members: { number },
	votes: { [number]: boolean },
}

export type CrashConfig = {
	CRASH_LENGTH: number,
	CRASH_LENGTH_REPEAT: number,
	CRASH_LENGTH_MIN: number,
	CRASH_LENGTH_MAX: number,
}

local IntermissionMath = {}

function IntermissionMath.newReadyCheck(members: { number }, now: number, timeout: number): ReadyCheck
	return { members = table.clone(members), ready = {}, startedAt = now, timeout = math.max(timeout, 0) }
end

function IntermissionMath.setReady(check: ReadyCheck, member: number, ready: boolean): boolean
	if table.find(check.members, member) == nil then
		return false
	end
	check.ready[member] = if ready then true else nil
	return true
end

function IntermissionMath.removeMember(check: ReadyCheck, member: number)
	local index = table.find(check.members, member)
	if index then
		table.remove(check.members, index)
	end
	check.ready[member] = nil
end

function IntermissionMath.readyCount(check: ReadyCheck): number
	local count = 0
	for _, member in check.members do
		if check.ready[member] then
			count += 1
		end
	end
	return count
end

function IntermissionMath.endsAt(check: ReadyCheck): number
	return check.startedAt + check.timeout
end

function IntermissionMath.readyStatus(check: ReadyCheck, now: number): ReadyStatus
	if #check.members == 0 then
		return "Empty"
	end
	if IntermissionMath.readyCount(check) == #check.members then
		return "AllReady"
	end
	if now >= IntermissionMath.endsAt(check) then
		return "TimedOut"
	end
	return "Waiting"
end

function IntermissionMath.newSkipVote(members: { number }): SkipVote
	return { members = table.clone(members), votes = {} }
end

function IntermissionMath.voteSkip(vote: SkipVote, member: number): boolean
	if table.find(vote.members, member) == nil then
		return false
	end
	vote.votes[member] = true
	return true
end

function IntermissionMath.removeVoter(vote: SkipVote, member: number)
	local index = table.find(vote.members, member)
	if index then
		table.remove(vote.members, index)
	end
	vote.votes[member] = nil
end

function IntermissionMath.skipCount(vote: SkipVote): number
	local count = 0
	for _, member in vote.members do
		if vote.votes[member] then
			count += 1
		end
	end
	return count
end

function IntermissionMath.skipPasses(vote: SkipVote): boolean
	return #vote.members > 0 and IntermissionMath.skipCount(vote) == #vote.members
end

function IntermissionMath.crashFor(config: CrashConfig, runs: { number }): (number, boolean)
	local full = math.clamp(config.CRASH_LENGTH, config.CRASH_LENGTH_MIN, config.CRASH_LENGTH_MAX)
	if #runs == 0 then
		return full, false
	end
	for _, count in runs do
		if count < 1 then
			return full, false
		end
	end
	return math.min(config.CRASH_LENGTH_REPEAT, full), true
end

function IntermissionMath.graceUntil(now: number, seconds: number): number
	return now + math.max(seconds, 0)
end

function IntermissionMath.inGrace(graceUntil: any, now: number): boolean
	return type(graceUntil) == "number" and now < graceUntil
end

export type LookConfig = {
	LOOK_YAW: number,
	LOOK_PITCH_MIN: number,
	LOOK_PITCH_MAX: number,
	LOOK_SENSITIVITY: number,
	LOOK_EASE: number,
}

function IntermissionMath.lookAfter(config: LookConfig, yaw: number, pitch: number, dx: number, dy: number): (number, number)
	local nextYaw = math.clamp(yaw - dx * config.LOOK_SENSITIVITY, -config.LOOK_YAW, config.LOOK_YAW)
	local nextPitch = math.clamp(pitch - dy * config.LOOK_SENSITIVITY, config.LOOK_PITCH_MIN, config.LOOK_PITCH_MAX)
	return nextYaw, nextPitch
end

function IntermissionMath.easeLook(config: LookConfig, current: number, target: number, deltaTime: number): number
	local nextValue = current + (target - current) * (1 - math.exp(-config.LOOK_EASE * math.max(deltaTime, 0)))
	if math.abs(target - nextValue) < 0.01 then
		return target
	end
	return nextValue
end

function IntermissionMath.secondsLeft(endsAt: number, now: number): number
	return math.max(math.ceil(endsAt - now), 0)
end

return IntermissionMath
