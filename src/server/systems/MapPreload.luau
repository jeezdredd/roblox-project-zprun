--!strict

-- Prepares the next map while the squad runs the current one (wiki: Map Segments).
-- When a map becomes current (the lead runner enters it), for both fork options at its
-- end:
--   - warms each sub-location's chunk pool to MapsConfig.POOL_WARM_CHUNKS;
--   - builds the map transition's blended chunks (the old map's last sub-location into
--     the option's first one, MAP_TRANSITION_CHUNKS of them), so the vote's choice is
--     placed the moment it closes;
--   - tells the clients to preload the options' meshes and textures (the MapPreload
--     Workspace attribute, MapPreloader on the client);
-- and frees the pools of maps two steps behind. The work runs in a queue under a
-- per-frame budget (MapsConfig.WARM_BUDGET_MS, at least one chunk a frame), into
-- ServerStorage (ChunkPools), so nothing replicates until it is placed. In Studio the
-- time to warm both options is printed and kept as MapWarmSeconds (the measurement
-- behind MapsConfig.preloadSeconds).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local MapsConfig = require(ReplicatedStorage.Shared.config.MapsConfig)
local MapMath = require(ReplicatedStorage.Shared.world.MapMath)
local ChunkFactory = require(script.Parent.ChunkFactory)
local ChunkPools = require(script.Parent.ChunkPools)
local DistanceTracker = require(script.Parent.DistanceTracker)
local MissionConfig = require(script.Parent.MissionConfig)
local MissionState = require(script.Parent.MissionState)
local RoutePlan = require(script.Parent.RoutePlan)

local MapPreload = {}

type Job = {
	kind: string,
	location: string,
	-- transition jobs: the blend's target, its index and the option it serves
	to: string?,
	k: number?,
	option: string,
}

local PRELOAD_ATTRIBUTE = "MapPreload"
local WARM_ATTRIBUTE = "MapWarmSeconds"

local random = Random.new()
local queue: { Job } = {}
local queuedPools: { [string]: number } = {}
local currentRun: RoutePlan.MapRun? = nil
local warmStartedAt: number? = nil

local function obstacleCount(): number
	local density = MissionConfig.getDifficulty().obstacleDensity
	return math.floor(density * random:NextNumber(0.6, 1.4) + 0.5)
end

local function buildJob(job: Job)
	local location = LocationsConfig.get(job.location)
	if not location then
		return
	end
	if job.kind == "pool" then
		queuedPools[job.location] = math.max((queuedPools[job.location] or 1) - 1, 0)
		ChunkPools.put(job.location, ChunkFactory.build(location, nil, random, obstacleCount()))
		return
	end
	local target = LocationsConfig.get(job.to :: string)
	local alpha = MapMath.transitionAlpha(job.k :: number, MapsConfig.MAP_TRANSITION_CHUNKS)
	if target and alpha then
		local key = ChunkPools.transitionKey(job.location, target.id, job.k :: number)
		if not ChunkPools.hasTransition(key) then
			ChunkPools.putTransition(key, ChunkFactory.build(location, { next = target, alpha = alpha }, random, obstacleCount()))
		end
	end
end

local function queuePools(option: string)
	local map = MapsConfig.get(option)
	if not map then
		return
	end
	for _, location in map.locationIds do
		local missing = MapsConfig.POOL_WARM_CHUNKS - ChunkPools.count(location) - (queuedPools[location] or 0)
		for _ = 1, missing do
			queuedPools[location] = (queuedPools[location] or 0) + 1
			table.insert(queue, { kind = "pool", location = location, option = option })
		end
	end
end

local function onMapCurrent(run: RoutePlan.MapRun, index: number)
	currentRun = run
	local options = run.options or {}
	for _, location in MapMath.poolsToFree(MapsConfig.maps :: any, RoutePlan.mapHistory(index), options) do
		ChunkPools.free(location)
	end
	local fork = RoutePlan.forkAfter(run)
	local info = if fork then fork.fork else nil
	-- the transition chunks first (the vote waits on them), then the pools
	if fork and info and fork.prevLocationId then
		for slot, option in info.options do
			for k = 0, MapsConfig.MAP_TRANSITION_CHUNKS - 1 do
				table.insert(queue, {
					kind = "transition",
					location = fork.prevLocationId,
					to = info.firstLocations[slot],
					k = k,
					option = option,
				})
			end
		end
	end
	for _, option in options do
		queuePools(option)
	end
	Workspace:SetAttribute(PRELOAD_ATTRIBUTE, table.concat(options, ","))
	warmStartedAt = if #queue > 0 then os.clock() else nil
end

local function processQueue()
	if #queue == 0 then
		return
	end
	local deadline = os.clock() + MapsConfig.WARM_BUDGET_MS / 1000
	repeat
		local job = table.remove(queue, 1) :: Job
		buildJob(job)
	until #queue == 0 or os.clock() >= deadline
	if #queue == 0 and warmStartedAt then
		local seconds = os.clock() - warmStartedAt
		warmStartedAt = nil
		Workspace:SetAttribute(WARM_ATTRIBUTE, math.floor(seconds * 100 + 0.5) / 100)
		if RunService:IsStudio() then
			print(string.format("[MapPreload] options warm in %.2f s; %s", seconds, ChunkPools.describe()))
		end
	end
end

local function step()
	if not MissionState.isActive() then
		-- the run is over: nothing stays warm in ServerStorage between runs
		if currentRun or #queue > 0 then
			queue = {}
			queuedPools = {}
			currentRun = nil
			warmStartedAt = nil
			ChunkPools.clearAll()
			Workspace:SetAttribute(PRELOAD_ATTRIBUTE, nil)
		end
		return
	end
	local index = RoutePlan.indexForDistance(DistanceTracker.getMaxDistance())
	RoutePlan.entryAt(index)
	local run = RoutePlan.mapAt(index)
	if run and run ~= currentRun then
		onMapCurrent(run, index)
	end
	processQueue()
end

-- The vote chose `choice`: the other option's queued work and pre-built transition
-- chunks go (unless both options start in the same sub-location).
function MapPreload.onForkResolved(entry: RoutePlan.PlanEntry, choice: string)
	local info = entry.fork
	if not info then
		return
	end
	local chosenSlot = table.find(info.options, choice)
	-- locations still needed: the chosen map's and the current map's
	local needed: { [string]: boolean } = {}
	local current = if currentRun then currentRun.id else choice
	for _, id in { choice, current } do
		local map = if id then MapsConfig.get(id) else nil
		for _, location in if map then map.locationIds else {} do
			needed[location] = true
		end
	end
	for slot, option in info.options do
		if option ~= choice then
			local to = info.firstLocations[slot]
			local keep = chosenSlot ~= nil and info.firstLocations[chosenSlot] == to
			for i = #queue, 1, -1 do
				if queue[i].option == option and not needed[queue[i].location] then
					if queue[i].kind == "pool" then
						queuedPools[queue[i].location] = math.max((queuedPools[queue[i].location] or 1) - 1, 0)
					end
					table.remove(queue, i)
				elseif queue[i].option == option and queue[i].kind == "transition" then
					table.remove(queue, i)
				end
			end
			if not keep and entry.prevLocationId then
				ChunkPools.dropTransitions(entry.prevLocationId, to)
			end
			-- the option not taken: its warmed pools go now (it never joins the history)
			local map = MapsConfig.get(option)
			for _, location in if map then map.locationIds else {} do
				if not needed[location] then
					ChunkPools.free(location)
				end
			end
		end
	end
end

function MapPreload.configure(seed: number)
	random = Random.new(seed + 13)
	queue = {}
	queuedPools = {}
	currentRun = nil
	warmStartedAt = nil
	ChunkPools.clearAll()
	Workspace:SetAttribute(PRELOAD_ATTRIBUTE, nil)
end

function MapPreload.init()
	RunService.Heartbeat:Connect(step)
end

return MapPreload
