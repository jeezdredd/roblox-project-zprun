--!strict

-- Diegetic weapon pickups (docs/gameplay/weapon-pickups.md): weapons lie in the world
-- as staged scenes placed along the corridor by the world generator, deterministic
-- from the run seed, taken by holding the prompt. Data only, no engine types: the pure
-- planner (src/shared/world/PickupPlanner.luau) and its tests read this table under the
-- standalone Luau CLI, so colours are {r, g, b} and sizes {x, y, z}; the server builder
-- (WeaponPickups) turns them into parts. Scenes are built from primitives and the props
-- already in WorldMeshConfig (police car, sandbags, supply crate): no new asset, no id.

export type Vec = { number }

-- One part of a scene, in the scene's own frame (x right, y up, -z toward the road).
export type PartSpec = {
	-- "box", "cylinder" (axis along x, as Roblox cylinders are), "ball", or "mesh" (a
	-- WorldMeshConfig group placed through WorldMeshes with `fallback` when not loaded)
	kind: string,
	name: string,
	size: Vec?,
	at: Vec,
	-- degrees
	yaw: number?,
	pitch: number?,
	roll: number?,
	color: Vec?,
	material: string?,
	collide: boolean?,
	group: string?,
	-- mesh: the footprint length along z (placeByLength) or the height
	length: number?,
	height: number?,
	fallback: { PartSpec }?,
}

export type SceneConfig = {
	id: string,
	displayName: string,
	-- the WeaponsConfig id handed over; a disabled scene may name a weapon that does not
	-- exist yet (the chainsaw)
	weaponId: string,
	enabled: boolean,
	-- the prompt's object text
	prompt: string,
	-- biomes (LocationsConfig ids) the scene may appear in; nil means any
	biomes: { string }?,
	-- pick weight among the scenes allowed in a biome
	weight: number,
	-- ground footprint radius, for the occupancy check against the chunk's props
	radius: number,
	-- where the weapon prop sits in the scene frame; the prompt and the highlight
	-- anchor there
	weaponAt: Vec,
	weaponYaw: number?,
	weaponPitch: number?,
	weaponRoll: number?,
	parts: { PartSpec },
}

local PickupScenesConfig = {}

-- The prompt: hold this long, from this far. The server accepts a trigger from a
-- little further than the prompt shows, for the latency of a running player.
PickupScenesConfig.HOLD_DURATION = 0.3
PickupScenesConfig.PROMPT_DISTANCE = 10
PickupScenesConfig.PICKUP_DISTANCE = 16

-- Highlights: Roblox renders 31 at once, the pool never holds more than this many; the
-- nearest scenes get them and a held one keeps its slot until a new scene is closer by
-- the margin (studs), so two scenes at the same distance never trade the outline.
PickupScenesConfig.HIGHLIGHT_BUDGET = 24
PickupScenesConfig.HIGHLIGHT_SWAP_MARGIN = 6
PickupScenesConfig.HIGHLIGHT_REFRESH = 0.25
PickupScenesConfig.HIGHLIGHT_OUTLINE = { 232, 200, 120 }
PickupScenesConfig.HIGHLIGHT_OUTLINE_DROP = { 236, 74, 58 }

-- Placement: no scene in the first chunks (the squad starts with its loadout), clear
-- of the chunk ends, on the road shoulder this far inside the playable edge, facing
-- the road with a little yaw jitter. The planner offers this many candidate spots per
-- scene and the server takes the first one free of the chunk's props.
PickupScenesConfig.START_CLEARANCE_CHUNKS = 2
PickupScenesConfig.END_CLEARANCE = 14
PickupScenesConfig.SHOULDER_INSET = { 4, 12 }
PickupScenesConfig.YAW_JITTER = 20
PickupScenesConfig.CANDIDATES = 3
-- the supply drop lands in the middle of the lane, this fraction of the playable half
-- width either side, and never within this many studs along the road of a scene
PickupScenesConfig.DROP_LANE_FRACTION = 0.5
PickupScenesConfig.SCENE_DROP_GAP = 24

-- Chance of one scene per chunk, per biome (LocationsConfig ids).
PickupScenesConfig.density = {
	City = 0.45,
	Wasteland = 0.4,
	Farmstead = 0.35,
	Forest = 0.3,
	Cornfield = 0.25,
} :: { [string]: number }

-- The crashed supply drop (the reworked mystery box): red smoke, opened for run
-- credits, the weapon rolled from the weighted table server-side. Green smoke stays
-- the ammo crate's (AmmoCrates).
PickupScenesConfig.supplyDrop = {
	cost = 250,
	chance = {
		City = 0.12,
		Wasteland = 0.12,
		Farmstead = 0.1,
		Forest = 0.08,
		Cornfield = 0.08,
	} :: { [string]: number },
	order = { "Shotgun", "SMG", "Rifle", "Pistol" },
	weights = { Shotgun = 4, SMG = 4, Rifle = 3, Pistol = 1 } :: { [string]: number },
	radius = 5,
	displayName = "Supply drop",
	smoke = { 236, 60, 48 },
}

local OLIVE = { 74, 78, 58 }
local SKIN = { 150, 120, 96 }
local BOOT = { 40, 36, 32 }
local BLOOD = { 88, 18, 16 }
local WOOD = { 108, 84, 56 }
local STEEL = { 70, 66, 62 }
local SAND = { 150, 134, 96 }
local POLICE_WHITE = { 214, 214, 210 }
local POLICE_BLACK = { 30, 30, 34 }
local CRATE = { 92, 98, 70 }

-- The weapon props by weapon id, in the gun's frame (-z along the barrel, y up).
PickupScenesConfig.weaponProps = {
	Pistol = {
		{ kind = "box", name = "Slide", size = { 0.34, 0.36, 1.5 }, at = { 0, 0.18, -0.2 }, color = POLICE_BLACK, material = "Metal" },
		{ kind = "box", name = "Grip", size = { 0.32, 0.9, 0.42 }, at = { 0, -0.3, 0.35 }, color = STEEL, material = "Metal" },
	},
	SMG = {
		{ kind = "box", name = "Receiver", size = { 0.5, 0.5, 2.2 }, at = { 0, 0.25, -0.2 }, color = POLICE_BLACK, material = "Metal" },
		{ kind = "cylinder", name = "Barrel", size = { 0.9, 0.2, 0.2 }, at = { 0, 0.3, -1.7 }, yaw = 90, color = STEEL, material = "Metal" },
		{ kind = "box", name = "Magazine", size = { 0.28, 1.0, 0.5 }, at = { 0, -0.45, 0.1 }, color = STEEL, material = "Metal" },
		{ kind = "box", name = "Grip", size = { 0.3, 0.7, 0.4 }, at = { 0, -0.3, 0.7 }, color = STEEL, material = "Metal" },
	},
	Shotgun = {
		{ kind = "box", name = "Receiver", size = { 0.42, 0.46, 1.6 }, at = { 0, 0.23, 0 }, color = POLICE_BLACK, material = "Metal" },
		{ kind = "cylinder", name = "Barrel", size = { 2.2, 0.22, 0.22 }, at = { 0, 0.32, -1.8 }, yaw = 90, color = STEEL, material = "Metal" },
		{ kind = "cylinder", name = "Tube", size = { 1.8, 0.2, 0.2 }, at = { 0, 0.08, -1.6 }, yaw = 90, color = STEEL, material = "Metal" },
		{ kind = "box", name = "Stock", size = { 0.36, 0.5, 1.4 }, at = { 0, 0.1, 1.4 }, pitch = -8, color = WOOD, material = "Wood" },
	},
	Rifle = {
		{ kind = "box", name = "Receiver", size = { 0.42, 0.5, 2.1 }, at = { 0, 0.25, 0 }, color = POLICE_BLACK, material = "Metal" },
		{ kind = "box", name = "Handguard", size = { 0.4, 0.4, 1.2 }, at = { 0, 0.25, -1.6 }, color = STEEL, material = "Metal" },
		{ kind = "cylinder", name = "Barrel", size = { 1.2, 0.16, 0.16 }, at = { 0, 0.3, -2.7 }, yaw = 90, color = STEEL, material = "Metal" },
		{ kind = "box", name = "Magazine", size = { 0.28, 0.9, 0.5 }, at = { 0, -0.35, -0.3 }, pitch = 12, color = STEEL, material = "Metal" },
		{ kind = "box", name = "Stock", size = { 0.34, 0.5, 1.0 }, at = { 0, 0.15, 1.5 }, color = POLICE_BLACK, material = "Metal" },
	},
} :: { [string]: { PartSpec } }

local function scene(config: SceneConfig): SceneConfig
	return config
end

PickupScenesConfig.order = { "DeadSoldier", "FencePost", "PoliceCar", "Checkpoint", "Sawmill" }

PickupScenesConfig.scenes = {
	-- A soldier who did not make it, his carbine beside him. Any biome.
	DeadSoldier = scene({
		id = "DeadSoldier",
		displayName = "Fallen soldier",
		weaponId = "Rifle",
		enabled = true,
		prompt = "R4 Carbine",
		biomes = nil,
		weight = 3,
		radius = 4,
		weaponAt = { 1.7, 0.3, 0.2 },
		weaponYaw = 100,
		weaponRoll = 90,
		parts = {
			{ kind = "box", name = "Blood", size = { 5.2, 0.05, 5.6 }, at = { 0.3, 0.03, 0.2 }, yaw = 20, color = BLOOD, material = "SmoothPlastic" },
			{ kind = "box", name = "Torso", size = { 2.0, 0.8, 3.0 }, at = { 0, 0.4, 0 }, color = OLIVE, material = "Fabric" },
			{ kind = "ball", name = "Head", size = { 1.1, 1.1, 1.1 }, at = { 0.2, 0.5, -2.0 }, color = SKIN, material = "SmoothPlastic" },
			{ kind = "box", name = "Helmet", size = { 1.25, 0.7, 1.25 }, at = { 0.2, 0.75, -2.05 }, color = OLIVE, material = "Metal" },
			{ kind = "box", name = "LegL", size = { 0.8, 0.6, 2.6 }, at = { -0.55, 0.3, 2.7 }, yaw = 8, color = OLIVE, material = "Fabric" },
			{ kind = "box", name = "LegR", size = { 0.8, 0.6, 2.6 }, at = { 0.6, 0.3, 2.6 }, yaw = -14, color = OLIVE, material = "Fabric" },
			{ kind = "box", name = "BootL", size = { 0.7, 0.5, 0.9 }, at = { -0.7, 0.25, 4.3 }, yaw = 8, color = BOOT, material = "Leather" },
			{ kind = "box", name = "BootR", size = { 0.7, 0.5, 0.9 }, at = { 0.95, 0.25, 4.1 }, yaw = -14, color = BOOT, material = "Leather" },
			{ kind = "box", name = "ArmL", size = { 0.6, 0.5, 2.2 }, at = { -1.4, 0.25, -0.4 }, yaw = 30, color = OLIVE, material = "Fabric" },
			{ kind = "box", name = "ArmR", size = { 0.6, 0.5, 2.0 }, at = { 1.35, 0.25, 0.6 }, yaw = -40, color = OLIVE, material = "Fabric" },
			{ kind = "box", name = "Pack", size = { 1.6, 0.7, 1.4 }, at = { -0.1, 1.0, 0.6 }, color = { 60, 62, 48 }, material = "Fabric" },
		},
	}),
	-- A pump shotgun left leaning on a fence post at the field's edge.
	FencePost = scene({
		id = "FencePost",
		displayName = "Fence post",
		weaponId = "Shotgun",
		enabled = true,
		prompt = "S870 Shotgun",
		biomes = { "Farmstead", "Cornfield", "Forest" },
		weight = 3,
		radius = 3.5,
		weaponAt = { 0.55, 1.9, 0.35 },
		weaponYaw = 8,
		weaponPitch = -62,
		parts = {
			{ kind = "cylinder", name = "Post", size = { 4.6, 0.55, 0.55 }, at = { 0, 2.3, 0 }, roll = 90, color = WOOD, material = "Wood", collide = true },
			{ kind = "cylinder", name = "PostFar", size = { 4.2, 0.5, 0.5 }, at = { 5.5, 2.1, 0 }, roll = 90, color = WOOD, material = "Wood", collide = true },
			{ kind = "box", name = "RailTop", size = { 6.2, 0.22, 0.14 }, at = { 2.75, 3.4, 0 }, color = WOOD, material = "Wood" },
			{ kind = "box", name = "RailLow", size = { 6.2, 0.22, 0.14 }, at = { 2.75, 1.7, 0 }, color = WOOD, material = "Wood" },
			{ kind = "box", name = "Crate", size = { 1.6, 1.2, 1.6 }, at = { -1.6, 0.6, 0.6 }, yaw = 15, color = CRATE, material = "WoodPlanks" },
		},
	}),
	-- A sidearm on the hood of an abandoned police car.
	PoliceCar = scene({
		id = "PoliceCar",
		displayName = "Police car",
		weaponId = "Pistol",
		enabled = true,
		prompt = "M9 Sidearm",
		biomes = { "City", "Wasteland" },
		weight = 2,
		radius = 8,
		weaponAt = { 0.6, 2.9, -3.6 },
		weaponYaw = 70,
		parts = {
			{
				kind = "mesh",
				name = "Car",
				group = "car_police",
				at = { 0, 0, 0 },
				yaw = 180,
				length = 12.4,
				collide = true,
				fallback = {
					{ kind = "box", name = "Body", size = { 6, 2.2, 12 }, at = { 0, 1.5, 0 }, color = POLICE_WHITE, material = "Metal", collide = true },
					{ kind = "box", name = "Cab", size = { 4.6, 1.6, 5 }, at = { 0, 3.4, 0.4 }, color = POLICE_BLACK, material = "Glass" },
					{ kind = "box", name = "DoorL", size = { 0.2, 2.0, 5 }, at = { -3.0, 1.5, 0.4 }, color = POLICE_BLACK, material = "Metal" },
					{ kind = "box", name = "DoorR", size = { 0.2, 2.0, 5 }, at = { 3.0, 1.5, 0.4 }, color = POLICE_BLACK, material = "Metal" },
					{ kind = "box", name = "LightBar", size = { 3.2, 0.4, 0.9 }, at = { 0, 4.4, 0 }, color = { 60, 90, 200 }, material = "Neon" },
				},
			},
			{ kind = "box", name = "Cone", size = { 0.9, 1.4, 0.9 }, at = { 4.6, 0.7, 5.2 }, color = { 226, 96, 40 }, material = "SmoothPlastic" },
		},
	}),
	-- An SMG on the sandbags of an abandoned checkpoint.
	Checkpoint = scene({
		id = "Checkpoint",
		displayName = "Checkpoint",
		weaponId = "SMG",
		enabled = true,
		prompt = "K10 SMG",
		biomes = { "City", "Wasteland", "Farmstead" },
		weight = 2,
		radius = 5,
		weaponAt = { 0.4, 1.9, -0.2 },
		weaponYaw = 105,
		weaponRoll = 90,
		parts = {
			{
				kind = "mesh",
				name = "Sandbags",
				group = "sandbags",
				at = { 0, 0, 0 },
				yaw = 90,
				collide = true,
				fallback = {
					{ kind = "box", name = "BagsLow", size = { 5.2, 0.9, 1.6 }, at = { 0, 0.45, 0 }, color = SAND, material = "Fabric", collide = true },
					{ kind = "box", name = "BagsTop", size = { 4.4, 0.8, 1.5 }, at = { 0.2, 1.3, 0.05 }, color = SAND, material = "Fabric", collide = true },
				},
			},
			{ kind = "box", name = "Barrel", size = { 1.6, 2.6, 1.6 }, at = { -3.6, 1.3, 1.2 }, color = { 150, 90, 40 }, material = "CorrodedMetal", collide = true },
			{ kind = "box", name = "Sign", size = { 2.4, 1.2, 0.1 }, at = { 3.4, 2.2, 0.8 }, yaw = -15, color = { 190, 40, 34 }, material = "SmoothPlastic" },
			{ kind = "box", name = "SignPost", size = { 0.16, 2.2, 0.16 }, at = { 3.4, 1.1, 0.8 }, color = STEEL, material = "Metal" },
		},
	}),
	-- The chainsaw at the sawmill: a config entry only, until a melee system exists.
	Sawmill = scene({
		id = "Sawmill",
		displayName = "Sawmill",
		weaponId = "Chainsaw",
		enabled = false,
		prompt = "Chainsaw",
		biomes = { "Forest", "Farmstead" },
		weight = 1,
		radius = 5,
		weaponAt = { 0, 1.2, 0 },
		parts = {
			{ kind = "box", name = "Bench", size = { 6, 1.1, 2.4 }, at = { 0, 0.55, 0 }, color = WOOD, material = "WoodPlanks", collide = true },
			{ kind = "box", name = "Logs", size = { 5, 1.6, 1.6 }, at = { 0, 0.8, 3 }, color = WOOD, material = "Wood", collide = true },
		},
	}),
} :: { [string]: SceneConfig }

function PickupScenesConfig.get(id: string): SceneConfig?
	return PickupScenesConfig.scenes[id]
end

-- Whether a scene may appear in `biome`.
function PickupScenesConfig.allowedIn(config: SceneConfig, biome: string): boolean
	if not config.enabled then
		return false
	end
	if config.biomes == nil then
		return true
	end
	return table.find(config.biomes :: { string }, biome) ~= nil
end

return PickupScenesConfig
