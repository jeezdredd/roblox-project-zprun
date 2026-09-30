--!strict

-- Which pickup scenes hold a Highlight this pass (docs/gameplay/weapon-pickups.md).
-- Roblox renders at most 31 Highlight instances, so the client keeps a pool below
-- that and hands the outlines to the nearest scenes; a scene that already holds one
-- keeps it unless a scene without one is closer by `margin`, so two scenes at the same
-- distance never trade the outline back and forth. Pure Luau, tested by
-- tests/pickups/run.luau.

export type Candidate = {
	id: string,
	distance: number,
}

export type Assignment = {
	-- the ids holding a highlight after this pass
	keep: { [string]: boolean },
	-- ids to hand a highlight to, nearest first
	acquire: { string },
	-- ids to take the highlight back from
	release: { string },
}

local HighlightBudget = {}

function HighlightBudget.assign(candidates: { Candidate }, budget: number, held: { [string]: boolean }, margin: number): Assignment
	local ranked = table.clone(candidates)
	local function score(candidate: Candidate): number
		return candidate.distance - (if held[candidate.id] then margin else 0)
	end
	table.sort(ranked, function(a, b)
		local sa, sb = score(a), score(b)
		if sa ~= sb then
			return sa < sb
		end
		return a.id < b.id
	end)

	local keep: { [string]: boolean } = {}
	local acquire: { string } = {}
	local limit = math.max(math.floor(budget), 0)
	local kept = 0
	for _, candidate in ranked do
		if kept >= limit then
			break
		end
		if not keep[candidate.id] then
			keep[candidate.id] = true
			kept += 1
			if not held[candidate.id] then
				table.insert(acquire, candidate.id)
			end
		end
	end

	local release: { string } = {}
	for id in held do
		if not keep[id] then
			table.insert(release, id)
		end
	end
	table.sort(release)

	return { keep = keep, acquire = acquire, release = release }
end

return HighlightBudget
