--!strict

local TrackBuilder = require(script.systems.TrackBuilder)
local CharacterSetup = require(script.systems.CharacterSetup)

TrackBuilder.build()
CharacterSetup.init()

print("[ZombieRunner][Server] Server started")
