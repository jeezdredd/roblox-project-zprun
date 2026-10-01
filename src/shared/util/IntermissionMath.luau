--!strict

-- The helicopter intermission's rules (docs/gameplay/heli-intermission.md): the ready
-- check, the skip vote, the crash length and the grace window. Pure Luau: no
-- services, no engine types, no requires, so it runs under the standalone Luau CLI
-- (tests/intermission/run.luau). Members are keys (the server uses the player's
-- UserId); times are server seconds passed in.

export type ReadyCheck = {
	members: { number },
	ready: { [number]: boolean },
	startedAt: number,
	timeout: number,
}

-- "Waiting": someone is not ready and time remains. "AllReady": every member still
-- here is ready. "TimedOut": the AFK timeout passed; the run starts for whoever is
-- here. "Empty": nobody is left.
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

-- Marks a member ready or not; false for someone who is not a member.
function IntermissionMath.setReady(check: ReadyCheck, member: number, ready: boolean): boolean
	if table.find(check.members, member) == nil then
		return false
	end
	check.ready[member] = if ready then true else nil
	return true
end

-- A member left (the game, or the cabin): their vote goes with them.
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

-- A member's vote to skip; false for someone who is not a member. A vote cannot be
-- taken back (one press, like the reference).
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

-- Passes when every member still here voted (and someone is here).
function IntermissionMath.skipPasses(vote: SkipVote): boolean
	return #vote.members > 0 and IntermissionMath.skipCount(vote) == #vote.members
end

-- The crash's length and whether it can be skipped: the short, skippable version only
-- when every member has run before (`runs` per member, the profile's lifetime count);
-- an empty squad gets the full length. The full length is clamped to the config range.
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

-- The grace window: until when a player at the wreck is ignored, and whether they are
-- now. A missing or non-number value never protects.
function IntermissionMath.graceUntil(now: number, seconds: number): number
	return now + math.max(seconds, 0)
end

function IntermissionMath.inGrace(graceUntil: any, now: number): boolean
	return type(graceUntil) == "number" and now < graceUntil
end

-- Seconds left, whole and rounded up, for a countdown label (0 when past).
function IntermissionMath.secondsLeft(endsAt: number, now: number): number
	return math.max(math.ceil(endsAt - now), 0)
end

return IntermissionMath
