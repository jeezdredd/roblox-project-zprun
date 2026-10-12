--!strict

local GameConstants = require(script.Parent.GameConstants)
local VisibilityConfig = require(script.Parent.VisibilityConfig)
local MapMath = require(script.Parent.Parent.world.MapMath)

local ForkConfig = {}

ForkConfig.ENABLED = true

ForkConfig.SETTLE_SECONDS = 1.5

ForkConfig.VOTE_LEAD = MapMath.voteLead(
	MapMath.maxVisibility(VisibilityConfig.visibility, VisibilityConfig.exempt),
	GameConstants.CHUNK_LENGTH,
	GameConstants.MAX_RUN_SPEED,
	ForkConfig.SETTLE_SECONDS
)

ForkConfig.DIVIDER_LENGTH = 384

ForkConfig.FIRST_DIVIDER_AT = 300

ForkConfig.SIGN_HEIGHT = 14
ForkConfig.RESULT_SHOW_TIME = 3

return table.freeze(ForkConfig)
