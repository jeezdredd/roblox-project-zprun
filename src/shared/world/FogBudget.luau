--!strict

-- Ties each preset's visibility to chunk spawning and streaming, so a chunk is always
-- replicated and fogged before it can be seen. Pure Luau; the constants come in as
-- numbers (GameConstants on the server, literals in the tests).

export type Constants = {
	spawnAhead: number,
	chunkLength: number,
	streamingRadius: number,
	streamingMargin: number,
}

local FogBudget = {}

-- Problems with one preset, as sentences; empty when it is fine.
function FogBudget.check(id: string, visibility: number, constants: Constants, exempt: boolean): { string }
	local issues = {}
	if not exempt and visibility + constants.chunkLength > constants.spawnAhead then
		table.insert(
			issues,
			string.format("%s: visibility %d + chunk %d exceeds the spawn distance %d", id, visibility, constants.chunkLength, constants.spawnAhead)
		)
	end
	return issues
end

-- Problems with the constants themselves, independent of any preset.
function FogBudget.checkStreaming(constants: Constants): { string }
	local issues = {}
	local needed = constants.spawnAhead + constants.chunkLength + constants.streamingMargin
	if constants.streamingRadius < needed then
		table.insert(issues, string.format("streaming radius %d is below the %d a spawned chunk needs", constants.streamingRadius, needed))
	end
	return issues
end

function FogBudget.checkAll(visibilities: { [string]: number }, exempt: { [string]: boolean }, constants: Constants): { string }
	local issues = FogBudget.checkStreaming(constants)
	local ids = {}
	for id in visibilities do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		for _, issue in FogBudget.check(id, visibilities[id], constants, exempt[id] == true) do
			table.insert(issues, issue)
		end
	end
	return issues
end

return FogBudget
