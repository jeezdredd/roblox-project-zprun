--!strict

local GameConstants = require(script.Parent.GameConstants)
local VisibilityConfig = require(script.Parent.VisibilityConfig)
local MapMath = require(script.Parent.Parent.world.MapMath)

-- Route forks: every map ends in a fork between two of its neighbours, and the squad
-- votes with their feet (wiki: Route Forks, Map Segments).
--
-- Streaming sets the geometry. Before map segments the last TRANSITION_CHUNKS of a
-- biome blended into the next, so the vote had to close a full spawn distance before
-- that blend: SPAWN_AHEAD_DISTANCE + 2 chunks = 1024 studs before the boundary. Now the
-- map transition starts at the boundary (the new map's first chunks blend from the old
-- one) and both options' first chunks are built while the squad runs the map, so
-- the spawner only holds at the boundary and places the chosen option's chunks the
-- moment the vote closes. The vote can then close as late as keeps the held boundary
-- out of sight while those chunks are placed and reach the clients: the widest fog
-- plus a chunk plus SETTLE_SECONDS at the top speed.

local ForkConfig = {}

ForkConfig.ENABLED = true

-- seconds for the held chunks to be placed and stream to the clients, measured in
-- Studio (wiki: Map Segments) with margin
ForkConfig.SETTLE_SECONDS = 1.5

-- How far before the map boundary the vote closes: 420 + 128 + 60 * 1.5 = 638 studs
-- with today's presets (was 1024).
ForkConfig.VOTE_LEAD = MapMath.voteLead(
	MapMath.maxVisibility(VisibilityConfig.visibility, VisibilityConfig.exempt),
	GameConstants.CHUNK_LENGTH,
	GameConstants.MAX_RUN_SPEED,
	ForkConfig.SETTLE_SECONDS
)

-- Length of the centre divider that splits the corridor into the two choices, ending
-- at the vote line. At BASE_RUN_SPEED 24 this is 16 s, at MAX_RUN_SPEED 60 about 6 s.
ForkConfig.DIVIDER_LENGTH = 384

-- No divider starts before this distance into a map: the squad settles into each map
-- before the next choice (part of every map's minimum length, MapMath.floorLength).
ForkConfig.FIRST_DIVIDER_AT = 300

-- Signs and HUD: options[1] is the left side of the divider, options[2] the right,
-- as seen by a runner facing RUN_DIRECTION.
ForkConfig.SIGN_HEIGHT = 14
ForkConfig.RESULT_SHOW_TIME = 3

return table.freeze(ForkConfig)
