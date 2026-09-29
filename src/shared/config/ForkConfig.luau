--!strict

local GameConstants = require(script.Parent.GameConstants)

-- Route forks: at some biome boundaries the squad votes with their feet between two
-- next locations. See wiki/project-zprun/Route Forks.md.
--
-- Streaming sets the geometry. Chunks exist SPAWN_AHEAD_DISTANCE ahead of the lead
-- runner and the last TRANSITION_CHUNKS of a biome are cross-faded into the next one,
-- so the next biome must be known before the lead runner is closer than
-- SPAWN_AHEAD_DISTANCE to the start of that blend. That is why the vote line sits
-- VOTE_LEAD before the boundary and not at it: resolving any later would leave a
-- visible hole at the far end of the streamed corridor.

local ForkConfig = {}

ForkConfig.ENABLED = true

-- How far before the biome boundary the vote closes.
ForkConfig.VOTE_LEAD = GameConstants.SPAWN_AHEAD_DISTANCE + GameConstants.TRANSITION_CHUNKS * GameConstants.CHUNK_LENGTH

-- Length of the centre divider that splits the corridor into the two choices, ending
-- at the vote line. At BASE_RUN_SPEED 24 this is 16 s, at MAX_RUN_SPEED 60 about 6 s.
ForkConfig.DIVIDER_LENGTH = 384

-- No fork whose divider would start before this distance: gives the squad the start
-- of the run to settle before the first choice.
ForkConfig.FIRST_DIVIDER_AT = 300

-- Minimum distance between two fork boundaries. Also stops the divider of one fork
-- overlapping the vote window of the previous one.
ForkConfig.MIN_SPACING = 2200

-- Signs and HUD: options[1] is the left side of the divider, options[2] the right,
-- as seen by a runner facing RUN_DIRECTION.
ForkConfig.SIGN_HEIGHT = 14
ForkConfig.RESULT_SHOW_TIME = 3

return table.freeze(ForkConfig)
