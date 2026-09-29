--!strict

-- Skinned zombie rigs from Sketchfab (tools/zombie_pack): which rig each ZombiesConfig
-- entry wears, the rig's key bones (hit parts follow them), and its clips with their
-- ground speed (studs/s at playback speed 1, measured from root travel or the planted
-- foot by build_zombie_anims.py) so the playback speed keeps the feet planted.
-- Bone names are the ones Roblox built on import (tools/zombie_pack/roblox_bones.json).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)

export type Clip = { id: number, speed: number }
export type Limb = { from: string, to: string, width: number }
export type Skin = {
	name: string,
	asset: number,
	head: string,
	chest: string,
	hips: string,
	limbs: { [string]: Limb },
	idle: { Clip },
	walk: { Clip },
	run: { Clip },
	attack: { Clip },
	death: { Clip },
	hit: Clip?,
	spotted: Clip?,
	-- fastest the AI may move this skin, for rigs with no run cycle
	maxSpeed: number?,
	-- where the rig sits against its imported bind pose: some packs' clips hold the
	-- skeleton root away from the bind in every frame, and the rig is moved the other way
	offset: Vector3?,
}

local ZombieSkins = {}

local anim = (AssetIds.animation :: any).zombie_sf or {}
local rigs = ((AssetIds :: any).zombie and (AssetIds :: any).zombie.sketchfab) or {}

local function clip(set: any, slot: string, speed: number): Clip?
	local id = set and set[slot]
	if typeof(id) == "number" and id > 0 then
		return { id = id, speed = speed }
	end
	return nil
end

local function list(...: Clip?): { Clip }
	local out = {}
	for i = 1, select("#", ...) do
		local item = select(i, ...)
		if item then
			table.insert(out, item)
		end
	end
	return out
end

local walker = anim.walker
local hazmat = anim.hazmat
local ghoul = anim.ghoul

ZombieSkins.skins = {
	-- "Zombie" by pxltiger (3ds Max Biped skeleton)
	Walker = {
		name = "Walker",
		asset = if rigs.walker then rigs.walker.rig else 0,
		head = "Base HumanHead_09",
		chest = "Base HumanRibcage_07",
		hips = "Base HumanPelvis_01",
		limbs = {
			LeftUpperLeg = { from = "Base HumanLLegThigh_051", to = "Base HumanLLegCalf_052", width = 0.75 },
			LeftLowerLeg = { from = "Base HumanLLegCalf_052", to = "Base HumanLLegFoot_053", width = 0.65 },
			RightUpperLeg = { from = "Base HumanRThigh_02", to = "Base HumanRCalf_03", width = 0.75 },
			RightLowerLeg = { from = "Base HumanRCalf_03", to = "Base HumanRFoot_04", width = 0.65 },
			LeftUpperArm = { from = "Base HumanLArmUpperarm_034", to = "Base HumanLArmForearm_035", width = 0.55 },
			LeftLowerArm = { from = "Base HumanLArmForearm_035", to = "Base HumanLArmPalm_036", width = 0.5 },
			RightUpperArm = { from = "Base HumanRArmUpperarm_016", to = "Base HumanRArmForearm_017", width = 0.55 },
			RightLowerArm = { from = "Base HumanRArmForearm_017", to = "Base HumanRArmPalm_018", width = 0.5 },
		},
		idle = list(clip(walker, "idle", 0)),
		walk = list(clip(walker, "walk_a", 0.876), clip(walker, "walk_b", 0.876)),
		run = list(clip(walker, "run", 12.015)),
		attack = list(clip(walker, "attack", 0)),
		death = list(clip(walker, "death_back", 0), clip(walker, "death_forward", 0)),
	},
	-- "Zombie Hazmat" by LxNazarov (Mixamo skeleton)
	Hazmat = {
		name = "Hazmat",
		asset = if rigs.hazmat then rigs.hazmat.rig else 0,
		head = "mixamorig:Head_06",
		chest = "mixamorig:Spine2_04",
		hips = "mixamorig:Hips_01",
		limbs = {
			LeftUpperLeg = { from = "mixamorig:LeftUpLeg_044", to = "mixamorig:LeftLeg_045", width = 0.8 },
			LeftLowerLeg = { from = "mixamorig:LeftLeg_045", to = "mixamorig:LeftFoot_046", width = 0.7 },
			RightUpperLeg = { from = "mixamorig:RightUpLeg_048", to = "mixamorig:RightLeg_049", width = 0.8 },
			RightLowerLeg = { from = "mixamorig:RightLeg_049", to = "mixamorig:RightFoot_050", width = 0.7 },
			LeftUpperArm = { from = "mixamorig:LeftArm_07", to = "mixamorig:LeftForeArm_08", width = 0.6 },
			LeftLowerArm = { from = "mixamorig:LeftForeArm_08", to = "mixamorig:LeftHand_09", width = 0.55 },
			RightUpperArm = { from = "mixamorig:RightArm_026", to = "mixamorig:RightForeArm_027", width = 0.6 },
			RightLowerArm = { from = "mixamorig:RightForeArm_027", to = "mixamorig:RightHand_028", width = 0.55 },
		},
		idle = list(clip(hazmat, "idle", 0)),
		walk = list(clip(hazmat, "walk_a", 0.774)),
		run = {},
		attack = list(clip(hazmat, "attack", 0)),
		death = {},
		spotted = clip(hazmat, "spotted", 0),
		-- only a shuffle: past about 2.6x the cycle reads as frantic
		maxSpeed = 2,
	},
	-- "ZOMBIE. Animation test for the game" by stasbelyk13 (Blender skeleton), the runner
	Ghoul = {
		name = "Ghoul",
		asset = if rigs.ghoul then rigs.ghoul.rig else 0,
		head = "Bone.005_3",
		chest = "Bone.002_53",
		hips = "Bone_66",
		limbs = {
			LeftUpperLeg = { from = "Bone.013.L_59", to = "Bone.014.L_58", width = 0.6 },
			LeftLowerLeg = { from = "Bone.014.L_58", to = "Bone.015.L_57", width = 0.5 },
			RightUpperLeg = { from = "Bone.013.R_64", to = "Bone.014.R_63", width = 0.6 },
			RightLowerLeg = { from = "Bone.014.R_63", to = "Bone.015.R_62", width = 0.5 },
			LeftUpperArm = { from = "Bone.010.L_26", to = "Bone.011.L_25", width = 0.45 },
			LeftLowerArm = { from = "Bone.011.L_25", to = "Bone.017.L_8", width = 0.4 },
			RightUpperArm = { from = "Bone.010.R_50", to = "Bone.011.R_49", width = 0.45 },
			RightLowerArm = { from = "Bone.011.R_49", to = "Bone.017.R_32", width = 0.4 },
		},
		idle = list(clip(ghoul, "idle", 0), clip(ghoul, "idle_b", 0)),
		walk = list(clip(ghoul, "walk_a", 5.939), clip(ghoul, "walk_b", 8.961)),
		run = list(clip(ghoul, "run", 15.22), clip(ghoul, "run_b", 20.706)),
		attack = list(clip(ghoul, "attack", 0), clip(ghoul, "attack_b", 0)),
		death = list(clip(ghoul, "death_back", 0), clip(ghoul, "death_forward", 0)),
		hit = clip(ghoul, "hit", 0),
		-- every Ghoul clip holds Bone.009 3.08 studs below its bind (measured 2026-09-29
		-- from the Pose tracks: a constant, the same in all 11 clips), which sank the body
		offset = Vector3.new(0, 3.077, -0.2),
	},
} :: { [string]: Skin }

-- which skins each ZombiesConfig id wears, with weights
ZombieSkins.byConfig = {
	Walker = { { skin = "Walker", weight = 0.65 }, { skin = "Hazmat", weight = 0.35 } },
	Runner = { { skin = "Ghoul", weight = 1 } },
} :: { [string]: { { skin: string, weight: number } } }

function ZombieSkins.get(name: string): Skin?
	local skin = ZombieSkins.skins[name]
	if skin and skin.asset > 0 and #skin.idle > 0 then
		return skin
	end
	return nil
end

-- `withDeath`: only skins that have a death clip (corpses are posed from it)
function ZombieSkins.pick(configId: string, rng: Random, withDeath: boolean?): Skin?
	local options = ZombieSkins.byConfig[configId]
	if not options then
		return nil
	end
	local function usable(name: string): Skin?
		local skin = ZombieSkins.get(name)
		if skin and withDeath and #skin.death == 0 then
			return nil
		end
		return skin
	end
	local total = 0
	for _, option in options do
		if usable(option.skin) then
			total += option.weight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, option in options do
		local skin = usable(option.skin)
		if skin then
			roll -= option.weight
			if roll <= 0 then
				return skin
			end
		end
	end
	return nil
end

return ZombieSkins
