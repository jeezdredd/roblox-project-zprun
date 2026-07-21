--!strict

local HangarConfig = {
	HUB_CENTER = Vector3.new(300, 0, 0),
	HUB_FLOOR_SIZE = Vector3.new(180, 1, 180),
	HUB_WALL_HEIGHT = 32,
	HUB_WALL_THICKNESS = 2,
	HUB_SPAWN_CFRAME = CFrame.lookAt(Vector3.new(300, 4, 60), Vector3.new(300, 4, 0)),

	RUN_START_CFRAME = CFrame.lookAt(Vector3.new(0, 5, 0), Vector3.new(0, 5, -20)),

	SQUAD_CAPACITY = 3,
	SQUAD_SPAWN_SPACING = 8,
	LAUNCH_COUNTDOWN = 4,
	BOARD_PROMPT_DISTANCE = 12,

	HELICOPTER_PADS = {
		CFrame.new(250, 0.5, -10),
		CFrame.new(300, 0.5, -10),
		CFrame.new(350, 0.5, -10),
	},
	HELICOPTER_BODY_SIZE = Vector3.new(12, 7, 24),

	FLOOR_COLOR = Color3.fromRGB(70, 72, 78),
	WALL_COLOR = Color3.fromRGB(48, 50, 55),
	HELI_COLOR = Color3.fromRGB(58, 66, 58),
	SEAT_COLOR = Color3.fromRGB(40, 44, 40),
}

return table.freeze(HangarConfig)
