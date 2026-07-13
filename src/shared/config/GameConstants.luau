--!strict

local GameConstants = {
	BASE_RUN_SPEED = 24,
	SPEED_GAIN_PER_STUD = 0.002,
	ZOMBIE_AGGRO_DISTANCE_THRESHOLD = 5000,
	LANE_WIDTH = 24,
}

return table.freeze(GameConstants)
