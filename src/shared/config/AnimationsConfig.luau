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

AnimationsConfig.RUN_SPEED_REFERENCE = 34
AnimationsConfig.RUN_SPEED_MIN = 0.8
AnimationsConfig.RUN_SPEED_MAX = 1.45

return AnimationsConfig
