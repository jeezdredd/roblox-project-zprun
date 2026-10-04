--!strict

-- Built chunks waiting to be placed (wiki: Map Segments), kept in ServerStorage so they
-- never replicate until the spawner moves them into Workspace:
--   pools: plain chunks per location (no blend), reused as the run passes them;
--   transitions: the blended first chunks of a map, built ahead for each fork option
--   under the key "<from>|<to>|<k>".
-- ChunkSpawner takes from both; MapPreload fills them over several frames and frees
-- what the run has left behind.

local ServerStorage = game:GetService("ServerStorage")

local ChunkPools = {}

local pools: { [string]: { Model } } = {}
local transitions: { [string]: Model } = {}
local folder: Folder? = nil

local function store(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "ChunkPool"
	created.Parent = ServerStorage
	folder = created
	return created
end

function ChunkPools.transitionKey(fromLocation: string, toLocation: string, k: number): string
	return `{fromLocation}|{toLocation}|{k}`
end

function ChunkPools.take(locationId: string): Model?
	local pool = pools[locationId]
	return if pool then table.remove(pool) else nil
end

function ChunkPools.put(locationId: string, model: Model)
	local pool = pools[locationId]
	if not pool then
		pool = {}
		pools[locationId] = pool
	end
	model.Parent = store()
	table.insert(pool, model)
end

function ChunkPools.count(locationId: string): number
	local pool = pools[locationId]
	return if pool then #pool else 0
end

-- Destroys a location's pooled chunks (the run has left every map that uses it).
function ChunkPools.free(locationId: string): number
	local pool = pools[locationId]
	if not pool then
		return 0
	end
	local freed = #pool
	for _, model in pool do
		model:Destroy()
	end
	pools[locationId] = nil
	return freed
end

function ChunkPools.putTransition(key: string, model: Model)
	local old = transitions[key]
	if old then
		old:Destroy()
	end
	model.Parent = store()
	transitions[key] = model
end

function ChunkPools.hasTransition(key: string): boolean
	return transitions[key] ~= nil
end

function ChunkPools.takeTransition(key: string): Model?
	local model = transitions[key]
	transitions[key] = nil
	return model
end

-- Drops every pre-built transition chunk into `toLocation` from `fromLocation` (the
-- option the vote did not choose, or all of them with nil).
function ChunkPools.dropTransitions(fromLocation: string?, toLocation: string?)
	for key, model in transitions do
		local from, to = string.match(key, "^([^|]+)|([^|]+)|")
		if (fromLocation == nil or from == fromLocation) and (toLocation == nil or to == toLocation) then
			model:Destroy()
			transitions[key] = nil
		end
	end
end

function ChunkPools.clearAll()
	for id in pools do
		ChunkPools.free(id)
	end
	ChunkPools.dropTransitions(nil, nil)
end

-- Pooled chunk counts per location and the transition count, for the Studio line.
function ChunkPools.describe(): string
	local parts = {}
	for id, pool in pools do
		table.insert(parts, `{id} {#pool}`)
	end
	table.sort(parts)
	local count = 0
	for _ in transitions do
		count += 1
	end
	return `pools: {table.concat(parts, ", ")}; transitions: {count}`
end

return ChunkPools
