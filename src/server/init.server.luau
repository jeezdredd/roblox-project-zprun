--!strict

local FlowService = require(script.systems.FlowService)
local HangarBuilder = require(script.systems.HangarBuilder)
local DistanceTracker = require(script.systems.DistanceTracker)
local MissionConfig = require(script.systems.MissionConfig)
local ZombieAI = require(script.systems.ZombieAI)
local ChunkSpawner = require(script.systems.ChunkSpawner)
local MissionService = require(script.systems.MissionService)
local DeathService = require(script.systems.DeathService)
local SquadService = require(script.systems.SquadService)
local SkinService = require(script.systems.SkinService)
local VendorRooms = require(script.systems.VendorRooms)
local CityDiorama = require(script.systems.CityDiorama)

local function runStage(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(`[TaskForceZ][Server] Stage "{name}" failed: {err}`)
	end
end

runStage("MissionConfig", MissionConfig.init)
runStage("FlowService", FlowService.init)
runStage("DistanceTracker", DistanceTracker.init)
runStage("ZombieAI", ZombieAI.init)
runStage("ChunkSpawner", ChunkSpawner.init)
runStage("MissionService", MissionService.init)
runStage("DeathService", DeathService.init)
runStage("SkinService", SkinService.init)

runStage("Hangar", function()
	local helicopters = HangarBuilder.build()
	SquadService.init(helicopters)
end)
runStage("VendorRooms", VendorRooms.build)
runStage("CityDiorama", CityDiorama.build)

print("[TaskForceZ][Server] Server started")
