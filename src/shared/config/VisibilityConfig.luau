--!strict

-- How far each lighting preset lets you see, in studs: the distance at which its fog
-- swallows a 10-stud object, judged in Studio (docs/world/environment.md, screenshot
-- plan shot C). FogBudget checks these against the chunk spawn distance so a chunk is
-- never spawned inside sight. Kept apart from LightingConfig, which needs Color3, so the
-- check runs under the standalone Luau CLI.

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

-- No run is spawned under these presets, so the spawn-edge rule does not apply.
VisibilityConfig.exempt = {
	Sandbox = true,
	Hub = true,
} :: { [string]: boolean }

-- Mirrors Workspace.StreamingTargetRadius in default.project.json, which Luau cannot read.
VisibilityConfig.STREAMING_TARGET_RADIUS = 1024

-- Slack between the spawn edge plus one chunk and the streaming radius.
VisibilityConfig.STREAMING_MARGIN = 64

return VisibilityConfig
