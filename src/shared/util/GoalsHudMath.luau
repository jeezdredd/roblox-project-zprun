--!strict

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
	value: number,
	target: number,
	done: boolean,
	text: string,
	rewardCredits: number,
}

local GoalsHudMath = {}

local PAIR = ";"
local VALUE = "="

function GoalsHudMath.stepped(value: number, step: number?): number
	local unit = math.max(math.floor(step or 1), 1)
	return math.floor(math.max(value, 0) / unit) * unit
end

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
