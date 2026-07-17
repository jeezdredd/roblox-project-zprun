--!strict

local TrackBuilder = require(script.systems.TrackBuilder)
local CharacterSetup = require(script.systems.CharacterSetup)
local DistanceTracker = require(script.systems.DistanceTracker)
local ZombieAI = require(script.systems.ZombieAI)
local ChunkSpawner = require(script.systems.ChunkSpawner)

TrackBuilder.build()
CharacterSetup.init()
DistanceTracker.init()
ZombieAI.init()
ChunkSpawner.init()

print("[ZombieRunner][Server] Server started")
