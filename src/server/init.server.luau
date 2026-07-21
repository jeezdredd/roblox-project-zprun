--!strict

local FlowService = require(script.systems.FlowService)
local HangarBuilder = require(script.systems.HangarBuilder)
local DistanceTracker = require(script.systems.DistanceTracker)
local MissionConfig = require(script.systems.MissionConfig)
local ZombieAI = require(script.systems.ZombieAI)
local ChunkSpawner = require(script.systems.ChunkSpawner)
local MissionService = require(script.systems.MissionService)
local SquadService = require(script.systems.SquadService)

MissionConfig.init()
FlowService.init()
DistanceTracker.init()
ZombieAI.init()
ChunkSpawner.init()
MissionService.init()

local helicopters = HangarBuilder.build()
SquadService.init(helicopters)

print("[TaskForceZ][Server] Server started")
