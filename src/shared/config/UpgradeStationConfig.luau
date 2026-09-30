--!strict

-- The upgrade station (docs/gameplay/upgrade-station.md): a field armourer's bench
-- placed mid-run by the world generator, where the carried weapon is upgraded one
-- level for run credits. The ladder it drives is WeaponsConfig's (MAX_LEVEL,
-- upgradePrice, damageAt); the level bought here lasts the run and never touches the
-- profile. Data only, no engine types: the pure UpgradeStationMath and its tests read
-- this table under the standalone Luau CLI. Parts follow PickupScenesConfig's PartSpec
-- shape and are built by the same code; the meshes are WorldMeshConfig groups already
-- in the manifest (oil_barrel), no asset added.

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
	group: string?,
	length: number?,
	height: number?,
	fallback: { PartSpec }?,
}

local UpgradeStationConfig = {}

-- Where along the run: one station per SPACING_STUDS of road (the chunk whose span
-- crosses a multiple of it gets one), none before START_CLEARANCE_STUDS, and only in
-- these biomes (a chunk of another biome that crosses the mark gets nothing: the next
-- mark is 640 studs on).
UpgradeStationConfig.SPACING_STUDS = 640
UpgradeStationConfig.START_CLEARANCE_STUDS = 512
UpgradeStationConfig.biomes = { "City", "Wasteland", "Farmstead" }

-- The spot: on the road shoulder this far inside the playable edge, clear of the chunk
-- ends, facing the road with a little yaw jitter; CANDIDATES spots in order, the
-- server takes the first one free of the chunk's props.
UpgradeStationConfig.END_CLEARANCE = 16
UpgradeStationConfig.SHOULDER_INSET = { 6, 11 }
UpgradeStationConfig.YAW_JITTER = 12
UpgradeStationConfig.CANDIDATES = 3
-- covers every part in `parts` (the generator reaches about 8.4 studs from the
-- origin); tests/upgrade computes the extent from the parts
UpgradeStationConfig.RADIUS = 9

-- The prompt: hold this long from this far; the server accepts a trigger from a little
-- further than the prompt shows, for the latency of a running player.
UpgradeStationConfig.HOLD_DURATION = 0.6
UpgradeStationConfig.PROMPT_DISTANCE = 10
UpgradeStationConfig.USE_DISTANCE = 16
UpgradeStationConfig.DISPLAY_NAME = "Upgrade station"

-- The outline (through the pickup highlight pool) and the bench lamp.
UpgradeStationConfig.HIGHLIGHT_OUTLINE = { 120, 200, 240 }
UpgradeStationConfig.LAMP_COLOR = { 200, 226, 255 }
UpgradeStationConfig.WARNING_COLOR = { 240, 160, 40 }

-- Announcer lines (AssetIds.audio.upgrade.*): played 2D on the client when the id is
-- non-zero; the slots are `needed` in the manifest until real licensed files exist.
UpgradeStationConfig.ANNOUNCER_UPGRADE = { "announcer_upgrade_01", "announcer_upgrade_02" }
UpgradeStationConfig.ANNOUNCER_MAX = "announcer_max"
UpgradeStationConfig.ANNOUNCER_VOLUME = 0.8

local STEEL = { 70, 66, 62 }
local DARK = { 40, 40, 44 }
local OLIVE = { 84, 90, 66 }
local WOOD = { 108, 84, 56 }
local RUST = { 150, 90, 40 }

-- The station in its own frame (x right, y up, -z toward the road): a generator with
-- its exhaust and warning light, the bench with a vise and a tool board behind it, a
-- lamp stand, two barrels.
UpgradeStationConfig.parts = {
	{ kind = "box", name = "Bench", size = { 8, 0.5, 3 }, at = { 0, 3.2, 0 }, color = STEEL, material = "DiamondPlate", collide = true },
	{ kind = "box", name = "BenchLegL", size = { 0.5, 3, 2.6 }, at = { -3.5, 1.5, 0 }, color = DARK, material = "Metal", collide = true },
	{ kind = "box", name = "BenchLegR", size = { 0.5, 3, 2.6 }, at = { 3.5, 1.5, 0 }, color = DARK, material = "Metal", collide = true },
	{ kind = "box", name = "Vise", size = { 1.4, 1, 1 }, at = { 2.2, 3.95, -0.4 }, color = DARK, material = "Metal" },
	{ kind = "cylinder", name = "ViseHandle", size = { 1.6, 0.14, 0.14 }, at = { 2.2, 3.95, -1.1 }, color = STEEL, material = "Metal" },
	{ kind = "box", name = "ToolBoard", size = { 8, 4, 0.3 }, at = { 0, 5.5, 1.6 }, color = OLIVE, material = "WoodPlanks", collide = true },
	{ kind = "box", name = "Tool1", size = { 0.2, 1.6, 0.12 }, at = { -2.6, 5.6, 1.4 }, color = STEEL, material = "Metal" },
	{ kind = "box", name = "Tool2", size = { 0.2, 1.2, 0.12 }, at = { -1.8, 5.8, 1.4 }, roll = 20, color = STEEL, material = "Metal" },
	{ kind = "box", name = "Tool3", size = { 1.4, 0.3, 0.12 }, at = { 0.4, 6.2, 1.4 }, color = WOOD, material = "Wood" },
	{ kind = "box", name = "Tool4", size = { 0.24, 1.8, 0.12 }, at = { 1.6, 5.5, 1.4 }, roll = -10, color = DARK, material = "Metal" },
	{ kind = "box", name = "Generator", size = { 3.2, 2.6, 2.2 }, at = { -6.4, 1.3, 0.6 }, yaw = -8, color = OLIVE, material = "Metal", collide = true },
	{ kind = "cylinder", name = "Exhaust", size = { 1.8, 0.35, 0.35 }, at = { -6.6, 3.2, 1.2 }, roll = 90, color = DARK, material = "CorrodedMetal" },
	{ kind = "box", name = "GeneratorPanel", size = { 1.2, 0.8, 0.1 }, at = { -6.2, 1.6, -0.5 }, yaw = -8, color = DARK, material = "SmoothPlastic" },
	{ kind = "ball", name = "WarningLight", size = { 0.5, 0.5, 0.5 }, at = { -6.4, 2.85, 0.6 }, color = { 240, 160, 40 }, material = "Neon" },
	{ kind = "cylinder", name = "LampPole", size = { 7, 0.18, 0.18 }, at = { 5.4, 3.5, 1.2 }, roll = 90, color = DARK, material = "Metal" },
	{ kind = "cylinder", name = "LampBase", size = { 0.2, 1.4, 1.4 }, at = { 5.4, 0.1, 1.2 }, roll = 90, color = DARK, material = "Metal" },
	{ kind = "box", name = "LampArm", size = { 0.16, 0.16, 2.2 }, at = { 5.4, 7, 0.2 }, color = DARK, material = "Metal" },
	{ kind = "box", name = "LampShade", size = { 1.2, 0.5, 1.2 }, at = { 5.4, 6.8, -0.8 }, color = STEEL, material = "Metal" },
	{ kind = "box", name = "LampFace", size = { 1.0, 0.1, 1.0 }, at = { 5.4, 6.5, -0.8 }, color = { 200, 226, 255 }, material = "Neon" },
	{
		kind = "mesh",
		name = "BarrelA",
		group = "oil_barrel",
		at = { -3.2, 0, 3.2 },
		yaw = 30,
		collide = true,
		fallback = {
			{ kind = "cylinder", name = "BarrelA", size = { 3.6, 2.4, 2.4 }, at = { 0, 1.8, 0 }, roll = 90, color = RUST, material = "CorrodedMetal", collide = true },
		},
	},
	{
		kind = "mesh",
		name = "BarrelB",
		group = "oil_barrel",
		at = { -0.8, 0, 3.6 },
		yaw = -50,
		collide = true,
		fallback = {
			{ kind = "cylinder", name = "BarrelB", size = { 3.6, 2.4, 2.4 }, at = { 0, 1.8, 0 }, roll = 90, color = RUST, material = "CorrodedMetal", collide = true },
		},
	},
	{ kind = "box", name = "Mat", size = { 12, 0.06, 7 }, at = { -0.6, 0.03, 0.4 }, color = { 48, 46, 42 }, material = "Fabric" },
} :: { PartSpec }

-- The prompt anchor and the weapon rest on the bench.
UpgradeStationConfig.anchorAt = { -0.6, 4.2, -0.2 }

return UpgradeStationConfig
