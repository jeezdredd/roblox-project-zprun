--!strict

local AssetIds = require(script.Parent.AssetIds)

export type ClipConfig = {
	id: string,
	assetId: number,
	priority: Enum.AnimationPriority,
	looped: boolean,
	weight: number,
	speed: number,
}

local AnimationsConfig = {}

AnimationsConfig.ENABLED = true
AnimationsConfig.BLEND_SPEED = 6

AnimationsConfig.clips = {
	Run = {
		id = "Run",
		assetId = AssetIds.animation.player.run,
		priority = Enum.AnimationPriority.Core,
		looped = true,
		weight = 1,
		speed = 1,
	},
	StrafeLeft = {
		id = "StrafeLeft",
		assetId = AssetIds.animation.player.strafe_left,
		priority = Enum.AnimationPriority.Movement,
		looped = true,
		weight = 0,
		speed = 1,
	},
	StrafeRight = {
		id = "StrafeRight",
		assetId = AssetIds.animation.player.strafe_right,
		priority = Enum.AnimationPriority.Movement,
		looped = true,
		weight = 0,
		speed = 1,
	},
	Stumble = {
		id = "Stumble",
		assetId = AssetIds.animation.player.stumble,
		priority = Enum.AnimationPriority.Action,
		looped = false,
		weight = 1,
		speed = 1,
	},
	Death = {
		id = "Death",
		assetId = AssetIds.animation.player.death,
		priority = Enum.AnimationPriority.Action4,
		looped = false,
		weight = 1,
		speed = 1,
	},
} :: { [string]: ClipConfig }

local function gait(id: string, assetId: number): ClipConfig
	return { id = id, assetId = assetId, priority = Enum.AnimationPriority.Core, looped = true, weight = 1, speed = 1 }
end

local function action(id: string, assetId: number): ClipConfig
	return { id = id, assetId = assetId, priority = Enum.AnimationPriority.Action, looped = false, weight = 1, speed = 1 }
end

local playerClips = AssetIds.animation.player

AnimationsConfig.SIT_CLIP = {
	id = "SitIdle",
	assetId = AssetIds.animation.player.sit_idle,
	priority = Enum.AnimationPriority.Action,
	looped = true,
	weight = 1,
	speed = 1,
} :: ClipConfig
AnimationsConfig.SIT_FADE = 0.25

AnimationsConfig.locomotionClips = {
	RifleIdle = gait("RifleIdle", playerClips.rifle_idle),
	RifleWalk = gait("RifleWalk", playerClips.rifle_walk),
	RifleRun = gait("RifleRun", playerClips.rifle_run),
	RifleSprint = gait("RifleSprint", playerClips.rifle_sprint),
	RifleStrafeLeft = gait("RifleStrafeLeft", playerClips.rifle_strafe_left),
	RifleStrafeRight = gait("RifleStrafeRight", playerClips.rifle_strafe_right),
	RifleReload = action("RifleReload", playerClips.rifle_reload),
	PistolIdle = gait("PistolIdle", playerClips.pistol_idle),
	PistolWalk = gait("PistolWalk", playerClips.pistol_walk),
	PistolRun = gait("PistolRun", playerClips.pistol_run),
	PistolStrafeLeft = gait("PistolStrafeLeft", playerClips.pistol_strafe_left),
	PistolStrafeRight = gait("PistolStrafeRight", playerClips.pistol_strafe_right),
	HitRifle = action("HitRifle", playerClips.hit_rifle),
} :: { [string]: ClipConfig }

AnimationsConfig.locomotionSets = {
	Rifle = {
		idle = "RifleIdle",
		walk = "RifleWalk",
		run = "RifleRun",
		sprint = "RifleSprint",
		strafe_left = "RifleStrafeLeft",
		strafe_right = "RifleStrafeRight",
		reload = "RifleReload",
		hit = "HitRifle",
	},
	Pistol = {
		idle = "PistolIdle",
		walk = "PistolWalk",
		run = "PistolRun",
		strafe_left = "PistolStrafeLeft",
		strafe_right = "PistolStrafeRight",
		hit = "HitRifle",
	},
} :: { [string]: { [string]: string } }

AnimationsConfig.GAIT_REFERENCE = { walk = 10, run = 24, sprint = 36 }
AnimationsConfig.SET_GAIT_REFERENCE = {
	Rifle = { walk = 3.3, run = 8.6, sprint = 18.9, strafe_left = 3.8, strafe_right = 2.1 },
	Pistol = { walk = 7.2, run = 13.4, sprint = 13.4, strafe_left = 6.1, strafe_right = 6.9 },
} :: { [string]: { [string]: number } }
AnimationsConfig.WALK_SPEED_MAX = 6
AnimationsConfig.STRAFE_AXIS = 0.7
AnimationsConfig.SPRINT_SPEED = 14
AnimationsConfig.SPRINT_HYSTERESIS = 2

AnimationsConfig.weaponClips = {
	Fire = {
		id = "Fire",
		assetId = AssetIds.animation.weapon.fire,
		priority = Enum.AnimationPriority.Action,
		looped = false,
		weight = 1,
		speed = 1,
	},
	Reload = {
		id = "Reload",
		assetId = AssetIds.animation.weapon.reload,
		priority = Enum.AnimationPriority.Action,
		looped = false,
		weight = 1,
		speed = 1,
	},
	Equip = {
		id = "Equip",
		assetId = AssetIds.animation.weapon.equip,
		priority = Enum.AnimationPriority.Action,
		looped = false,
		weight = 1,
		speed = 1,
	},
	Inspect = {
		id = "Inspect",
		assetId = AssetIds.animation.weapon.inspect,
		priority = Enum.AnimationPriority.Action,
		looped = false,
		weight = 1,
		speed = 1,
	},
	Sprint = {
		id = "Sprint",
		assetId = AssetIds.animation.weapon.sprint,
		priority = Enum.AnimationPriority.Movement,
		looped = true,
		weight = 1,
		speed = 1,
	},
} :: { [string]: ClipConfig }

function AnimationsConfig.weaponClip(id: string): ClipConfig?
	local clip = AnimationsConfig.weaponClips[id]
	if clip and clip.assetId > 0 then
		return clip
	end
	return nil
end

AnimationsConfig.RUN_SPEED_REFERENCE = 24
AnimationsConfig.RUN_SPEED_MIN = 0.6
AnimationsConfig.RUN_SPEED_MAX = 2

return AnimationsConfig
