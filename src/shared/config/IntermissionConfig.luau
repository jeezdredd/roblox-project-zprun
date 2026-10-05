--!strict

-- The helicopter intermission (docs/gameplay/heli-intermission.md): between the
-- squad's launch countdown and the run, the squad sits in a helicopter cabin off the
-- map for a ready check, then waits out the crash cinematic, then wakes at the wreck
-- with a grace window. Data only, no engine types: the pure IntermissionMath and its
-- tests read this table under the standalone Luau CLI. Positions are {x, y, z},
-- colours {r, g, b}; the server builds CFrames from them. The cabin is primitives
-- through SceneParts (PartSpec shape), no asset.

export type Vec = { number }

export type PartSpec = {
	kind: string,
	name: string,
	size: Vec?,
	at: Vec,
	yaw: number?,
	pitch: number?,
	roll: number?,
	color: Vec?,
	material: string?,
	collide: boolean?,
	transparency: number?,
	group: string?,
	length: number?,
	height: number?,
	fallback: { PartSpec }?,
}

local IntermissionConfig = {}

-- The ready check: everyone ready, or this many seconds and the run starts for
-- whoever is there.
IntermissionConfig.READY_TIMEOUT = 90

-- The crash cinematic: the server only waits this long. The first time a squad sees
-- it (any member with no run in the profile) it is the full length and cannot be
-- skipped; a squad of members who have all run before gets the short version, ended
-- early when every member votes to skip.
IntermissionConfig.CRASH_LENGTH = 13
IntermissionConfig.CRASH_LENGTH_REPEAT = 5
IntermissionConfig.CRASH_LENGTH_MIN = 12
IntermissionConfig.CRASH_LENGTH_MAX = 15

-- The wake-up: zombies ignore a player whose GraceUntil (server time) is ahead, for
-- this many seconds after the spawn at the wreck; the client shows "RUN" meanwhile.
IntermissionConfig.GRACE_SECONDS = 6

-- Where the squad wakes: an offset from HangarConfig.RUN_START_CFRAME, in its frame
-- (-z is the run direction), so the wreck stays on the start platform.
IntermissionConfig.WRECK_OFFSET = { 0, 0, -4 }

-- The cabin, far off the map and high (no chunk, hub or diorama is near it).
IntermissionConfig.CABIN_ORIGIN = { 4000, 600, 4000 }
-- red cabin light
IntermissionConfig.CABIN_LIGHT = { 255, 70, 50 }
-- fill lights in the cabin's frame (from the floor's top): warm over the seats, green
-- from the instrument console
IntermissionConfig.CABIN_FILL_LIGHTS = {
	{ name = "DomeLight", at = { -1.5, 6.2, 0 }, color = { 255, 222, 190 }, brightness = 2.2, range = 18 },
	{ name = "ConsoleLight", at = { 0, 3.6, -12.6 }, color = { 90, 220, 140 }, brightness = 2, range = 12 },
} :: { { name: string, at: Vec, color: Vec, brightness: number, range: number } }

-- Remote rate limit per player for the ready and skip toggles.
IntermissionConfig.TOGGLE_COOLDOWN = 0.25

-- The troop seats along the left wall, facing the open door on the right wall (+x).
-- One per squad member (HangarConfig.SQUAD_CAPACITY is 3).
IntermissionConfig.seats = {
	{ -3.3, 1.0, -3.2 },
	{ -3.3, 1.0, 0 },
	{ -3.3, 1.0, 3.2 },
} :: { Vec }
-- the seat faces this yaw in degrees (-90 looks along +x, at the door)
IntermissionConfig.SEAT_YAW = -90
-- the seated eye, from the seat's centre in the seat's frame, and how far down the
-- view tilts (degrees)
IntermissionConfig.EYE_OFFSET = { 0, 3.1, -0.2 }
IntermissionConfig.VIEW_PITCH = -8

-- Look around during the ready check while the right mouse button is held (the cursor
-- stays free for the panel): degrees from the SeatView frame, yaw either side and
-- pitch down/up, degrees per pixel of mouse travel, and how fast the view eases to
-- where the mouse put it (per second, exponential). The crash beat keeps the fixed view.
IntermissionConfig.LOOK_YAW = 100
IntermissionConfig.LOOK_PITCH_MIN = -50
IntermissionConfig.LOOK_PITCH_MAX = 40
IntermissionConfig.LOOK_SENSITIVITY = 0.25
IntermissionConfig.LOOK_EASE = 12

local OLIVE = { 70, 78, 62 }
local DARK = { 38, 40, 38 }
local STEEL = { 82, 86, 88 }
local WEBBING = { 96, 92, 70 }
local FLIGHT = { 60, 66, 54 }
local SKIN = { 150, 120, 96 }

-- The cabin in its own frame: origin on the cabin floor's centre, x across (the door
-- at +x), y up, -z toward the cockpit.
IntermissionConfig.parts = {
	{ kind = "box", name = "Floor", size = { 9, 0.6, 16 }, at = { 0, -0.3, 0 }, color = DARK, material = "DiamondPlate", collide = true },
	{ kind = "box", name = "WallLeft", size = { 0.4, 7, 16 }, at = { -4.7, 3.5, 0 }, color = OLIVE, material = "Metal", collide = true },
	{ kind = "box", name = "WallRightAft", size = { 0.4, 7, 5 }, at = { 4.7, 3.5, 5.5 }, color = OLIVE, material = "Metal", collide = true },
	{ kind = "box", name = "WallRightFore", size = { 0.4, 7, 5 }, at = { 4.7, 3.5, -5.5 }, color = OLIVE, material = "Metal", collide = true },
	{ kind = "box", name = "DoorLintel", size = { 0.4, 1.5, 6 }, at = { 4.7, 6.25, 0 }, color = OLIVE, material = "Metal", collide = true },
	{ kind = "box", name = "DoorSill", size = { 0.6, 0.3, 6 }, at = { 4.7, 0.15, 0 }, color = STEEL, material = "Metal", collide = true },
	{ kind = "box", name = "DoorRail", size = { 0.12, 0.12, 6 }, at = { 4.5, 4.2, 0 }, color = STEEL, material = "Metal" },
	{ kind = "box", name = "Roof", size = { 9.8, 0.4, 16 }, at = { 0, 7.2, 0 }, color = OLIVE, material = "Metal", collide = true },
	{ kind = "box", name = "RearWall", size = { 9.8, 7, 0.4 }, at = { 0, 3.5, 8.2 }, color = OLIVE, material = "Metal", collide = true },
	{ kind = "box", name = "BulkheadLeft", size = { 3, 7, 0.4 }, at = { -3.4, 3.5, -8.2 }, color = OLIVE, material = "Metal", collide = true },
	{ kind = "box", name = "BulkheadRight", size = { 3, 7, 0.4 }, at = { 3.4, 3.5, -8.2 }, color = OLIVE, material = "Metal", collide = true },
	{ kind = "box", name = "BulkheadTop", size = { 3.8, 2, 0.4 }, at = { 0, 6, -8.2 }, color = OLIVE, material = "Metal", collide = true },
	{ kind = "box", name = "SeatRail", size = { 0.3, 0.3, 12 }, at = { -4.3, 2.9, 0 }, color = STEEL, material = "Metal" },
	{ kind = "box", name = "Webbing1", size = { 0.1, 2.4, 1.6 }, at = { -4.45, 3.2, -3.2 }, color = WEBBING, material = "Fabric" },
	{ kind = "box", name = "Webbing2", size = { 0.1, 2.4, 1.6 }, at = { -4.45, 3.2, 0 }, color = WEBBING, material = "Fabric" },
	{ kind = "box", name = "Webbing3", size = { 0.1, 2.4, 1.6 }, at = { -4.45, 3.2, 3.2 }, color = WEBBING, material = "Fabric" },
	{ kind = "box", name = "LightStrip", size = { 0.3, 0.12, 10 }, at = { 0, 6.94, 0 }, color = { 255, 70, 50 }, material = "Neon" },
	{ kind = "box", name = "CrateA", size = { 2.4, 1.6, 1.8 }, at = { 2.6, 0.8, 6.4 }, yaw = 8, color = { 92, 98, 70 }, material = "WoodPlanks", collide = true },
	{ kind = "box", name = "CrateB", size = { 1.8, 1.2, 1.6 }, at = { 2.4, 2.2, 6.5 }, yaw = -6, color = { 84, 90, 64 }, material = "WoodPlanks", collide = true },
	{ kind = "box", name = "CargoNet", size = { 4, 3, 0.08 }, at = { 1.6, 2.4, 7.9 }, color = { 60, 60, 50 }, material = "Fabric", transparency = 0.35 },
	{ kind = "cylinder", name = "Extinguisher", size = { 1.2, 0.5, 0.5 }, at = { -4.2, 1.2, 6.6 }, roll = 90, color = { 190, 40, 34 }, material = "SmoothPlastic" },
	-- the cockpit beyond the bulkhead opening
	{ kind = "box", name = "CockpitFloor", size = { 9, 0.6, 6 }, at = { 0, -0.3, -11.2 }, color = DARK, material = "DiamondPlate", collide = true },
	{ kind = "box", name = "CockpitLeft", size = { 0.4, 7, 6 }, at = { -4.7, 3.5, -11.2 }, color = OLIVE, material = "Metal", collide = true },
	{ kind = "box", name = "CockpitRight", size = { 0.4, 7, 6 }, at = { 4.7, 3.5, -11.2 }, color = OLIVE, material = "Metal", collide = true },
	{ kind = "box", name = "CockpitRoof", size = { 9.8, 0.4, 6 }, at = { 0, 7.2, -11.2 }, color = OLIVE, material = "Metal", collide = true },
	{ kind = "box", name = "Console", size = { 8, 1.6, 1.4 }, at = { 0, 2.2, -13.2 }, pitch = -12, color = DARK, material = "Metal", collide = true },
	{ kind = "box", name = "ConsoleGlow", size = { 6, 0.1, 0.6 }, at = { 0, 3.05, -13.0 }, pitch = -12, color = { 80, 200, 120 }, material = "Neon" },
	{ kind = "box", name = "Windscreen", size = { 9, 4, 0.2 }, at = { 0, 4.8, -14.2 }, color = { 150, 170, 180 }, material = "Glass", transparency = 0.7 },
	{ kind = "box", name = "NoseFloor", size = { 9, 2, 0.6 }, at = { 0, 1, -14.2 }, color = OLIVE, material = "Metal", collide = true },
	{ kind = "box", name = "PilotSeat", size = { 2, 1, 2 }, at = { -1.9, 1.0, -11.4 }, color = DARK, material = "Fabric", collide = true },
	{ kind = "box", name = "CopilotSeat", size = { 2, 1, 2 }, at = { 1.9, 1.0, -11.4 }, color = DARK, material = "Fabric", collide = true },
} :: { PartSpec }

-- The two crew figures, each built into its own Model (Pilot, Copilot) so the crash
-- cinematic can move them; parts in the figure's frame, the figure's origin on its seat.
IntermissionConfig.crew = {
	{
		name = "Pilot",
		at = { -1.9, 1.5, -11.4 },
		parts = {
			{ kind = "box", name = "Torso", size = { 1.6, 2, 1 }, at = { 0, 1.0, 0.2 }, color = FLIGHT, material = "Fabric" },
			{ kind = "ball", name = "Head", size = { 1, 1, 1 }, at = { 0, 2.5, 0.1 }, color = SKIN, material = "SmoothPlastic" },
			{ kind = "box", name = "Helmet", size = { 1.15, 0.7, 1.15 }, at = { 0, 2.8, 0.1 }, color = DARK, material = "SmoothPlastic" },
			{ kind = "box", name = "Visor", size = { 0.9, 0.3, 0.1 }, at = { 0, 2.55, -0.45 }, color = { 30, 30, 34 }, material = "Glass" },
			{ kind = "box", name = "ArmL", size = { 0.5, 0.5, 1.4 }, at = { -0.9, 1.3, -0.5 }, color = FLIGHT, material = "Fabric" },
			{ kind = "box", name = "ArmR", size = { 0.5, 0.5, 1.4 }, at = { 0.9, 1.3, -0.5 }, color = FLIGHT, material = "Fabric" },
		},
	},
	{
		name = "Copilot",
		at = { 1.9, 1.5, -11.4 },
		parts = {
			{ kind = "box", name = "Torso", size = { 1.6, 2, 1 }, at = { 0, 1.0, 0.2 }, color = FLIGHT, material = "Fabric" },
			{ kind = "ball", name = "Head", size = { 1, 1, 1 }, at = { 0, 2.5, 0.1 }, color = SKIN, material = "SmoothPlastic" },
			{ kind = "box", name = "Helmet", size = { 1.15, 0.7, 1.15 }, at = { 0, 2.8, 0.1 }, color = DARK, material = "SmoothPlastic" },
			{ kind = "box", name = "Visor", size = { 0.9, 0.3, 0.1 }, at = { 0, 2.55, -0.45 }, color = { 30, 30, 34 }, material = "Glass" },
			{ kind = "box", name = "ArmL", size = { 0.5, 0.5, 1.4 }, at = { -0.9, 1.3, -0.5 }, color = FLIGHT, material = "Fabric" },
			{ kind = "box", name = "ArmR", size = { 0.5, 0.5, 1.4 }, at = { 0.9, 1.3, -0.5 }, color = FLIGHT, material = "Fabric" },
		},
	},
} :: { { name: string, at: Vec, parts: { PartSpec } } }

return IntermissionConfig
