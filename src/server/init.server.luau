--!strict

local TrackBuilder = require(script.systems.TrackBuilder)
local CharacterSetup = require(script.systems.CharacterSetup)
local DistanceTracker = require(script.systems.DistanceTracker)
local ChunkSpawner = require(script.systems.ChunkSpawner)

TrackBuilder.build()
CharacterSetup.init()
DistanceTracker.init()
ChunkSpawner.init()

print("[ZombieRunner][Server] Server started")
