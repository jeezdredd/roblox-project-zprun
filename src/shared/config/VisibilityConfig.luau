--!strict

local VisibilityConfig = {}

VisibilityConfig.visibility = {
	Sandbox = 1400,
	Hub = 600,
	City = 340,
	Forest = 300,
	Wasteland = 420,
	Farmstead = 360,
	Cornfield = 220,
	Night = 260,
	CityNight = 300,
	ForestNight = 220,
	WastelandNight = 380,
	FarmsteadNight = 300,
	CornfieldNight = 180,
} :: { [string]: number }

VisibilityConfig.exempt = {
	Sandbox = true,
	Hub = true,
} :: { [string]: boolean }

VisibilityConfig.STREAMING_TARGET_RADIUS = 1024

VisibilityConfig.STREAMING_MARGIN = 64

return VisibilityConfig
