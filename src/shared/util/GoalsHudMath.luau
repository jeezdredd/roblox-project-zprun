--!strict

-- The mission goals on the run HUD (docs/gameplay/goals-hud-and-ladder.md): the
-- server packs each participant's goal progress into one attribute string and the
-- HUD unpacks it into rows. Pure Luau: no services, no engine types, no requires, so
-- it runs under the standalone Luau CLI (tests/goals/run.luau); the goals come in as
-- the MissionGoalsConfig table.

export type GoalRule = {
	id: string,
	displayName: string,
	metric: string,
	target: number,
	rewardCredits: number,
}

export type Config = {
	order: { string },
	goals: { [string]: GoalRule },
}

export type Row = {
	id: string,
	displayName: string,
	-- progress clamped to the target, whole
	value: number,
	target: number,
	done: boolean,
	-- "320 / 1500"
	text: string,
	rewardCredits: number,
}

local GoalsHudMath = {}

local PAIR = ";"
local VALUE = "="

-- The progress as the HUD shows it: floored to the metric's step (`steps`, e.g. 5 studs
-- for the distances, so the string changes at most once per step), 1 by default, and
-- capped at the goal's target (a step never lands a goal short of it, since the
-- targets are whole steps).
function GoalsHudMath.stepped(value: number, step: number?): number
	local unit = math.max(math.floor(step or 1), 1)
	return math.floor(math.max(value, 0) / unit) * unit
end

-- "Distance1500=320;Kills25=4": every goal in config order, its metric's progress
-- stepped, so the string only changes when a whole step changes.
function GoalsHudMath.encode(config: Config, progress: { [string]: number }, steps: { [string]: number }?): string
	local parts: { string } = {}
	for _, id in config.order do
		local goal = config.goals[id]
		if goal then
			local step = if steps then steps[goal.metric] else nil
			table.insert(parts, id .. VALUE .. tostring(GoalsHudMath.stepped(progress[goal.metric] or 0, step)))
		end
	end
	return table.concat(parts, PAIR)
end

-- The progress per goal id from an encoded string; anything malformed is skipped.
function GoalsHudMath.decode(encoded: string): { [string]: number }
	local values: { [string]: number } = {}
	if encoded == "" then
		return values
	end
	for _, pair in string.split(encoded, PAIR) do
		local id, raw = string.match(pair, "^([%w_]+)" .. VALUE .. "(%-?%d+)$")
		if id and raw then
			values[id] = tonumber(raw) or 0
		end
	end
	return values
end

-- The HUD rows in config order from decoded values (a goal missing from the string
-- reads 0).
function GoalsHudMath.rows(config: Config, values: { [string]: number }): { Row }
	local rows: { Row } = {}
	for _, id in config.order do
		local goal = config.goals[id]
		if goal then
			local value = math.clamp(math.floor(values[id] or 0), 0, goal.target)
			table.insert(rows, {
				id = id,
				displayName = goal.displayName,
				value = value,
				target = goal.target,
				done = value >= goal.target,
				text = string.format("%d / %d", value, goal.target),
				rewardCredits = goal.rewardCredits,
			})
		end
	end
	return rows
end

return GoalsHudMath
