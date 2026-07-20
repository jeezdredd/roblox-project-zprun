--!strict

local BootConfig = {
	TITLE_PRIMARY = "TASK FORCE Z",
	TAGLINE = "SPECIAL LIQUIDATION SQUAD",
	LORE_LINE = "A global outbreak spreads. One squad answers the call.",

	DISPLAY_ORDER = 1000,
	MIN_DISPLAY_SECONDS = 1.2,
	LOADING_STEPS = { "Establishing uplink", "Loading assets", "Priming systems", "Deploying" },
	STEP_DURATION = 0.35,
	LOADED_WAIT_DEADLINE = 6,

	INTRO_TITLE_TIME = 0.8,
	INTRO_LINE_TIME = 0.5,
	INTRO_HOLD = 1.6,
	FADE_TIME = 0.6,
	READY_TIMEOUT = 8,

	BACKGROUND_COLOR = Color3.fromRGB(8, 9, 12),
	PANEL_COLOR = Color3.fromRGB(18, 20, 24),
	BAR_COLOR = Color3.fromRGB(190, 55, 55),
	TEXT_COLOR = Color3.fromRGB(228, 228, 230),
	MUTED_COLOR = Color3.fromRGB(150, 152, 158),
	ACCENT_COLOR = Color3.fromRGB(190, 55, 55),
}

return table.freeze(BootConfig)
