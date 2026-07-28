--!strict

local HangarConfig = {
	HUB_CENTER = Vector3.new(300, 0, 0),
	HUB_FLOOR_SIZE = Vector3.new(360, 1, 320),
	HUB_WALL_HEIGHT = 46,
	HUB_WALL_THICKNESS = 3,
	HUB_SPAWN_CFRAME = CFrame.lookAt(Vector3.new(300, 4, 92), Vector3.new(300, 4, 20)),

	WINDOW_SILL = 15,
	WINDOW_BAND_HEIGHT = 17,
	WINDOW_SEGMENT = 24,
	GATE_HALF_WIDTH = 62,
	GATE_HEIGHT = 34,

	RUN_START_CFRAME = CFrame.lookAt(Vector3.new(0, 5, 0), Vector3.new(0, 5, -20)),

	SQUAD_CAPACITY = 3,
	SQUAD_SPAWN_SPACING = 8,
	LAUNCH_COUNTDOWN = 4,
	BOARD_PROMPT_DISTANCE = 14,

	HELICOPTER_PADS = {
		CFrame.new(210, 0.5, -108),
		CFrame.new(300, 0.5, -108),
		CFrame.new(390, 0.5, -108),
	},

	CITY_NEAR_Z = -230,
	CITY_FAR_Z = -760,
	CITY_HALF_WIDTH = 420,
	CITY_BLOCKS = 46,
	CITY_FIRES = 9,
	CITY_CHOPPERS = 3,

	FLOOR_COLOR = Color3.fromRGB(198, 198, 202),
	WALL_COLOR = Color3.fromRGB(58, 60, 66),
	TRIM_COLOR = Color3.fromRGB(150, 122, 44),
	HELI_COLOR = Color3.fromRGB(58, 66, 58),
	SEAT_COLOR = Color3.fromRGB(40, 44, 40),
}

return table.freeze(HangarConfig)
