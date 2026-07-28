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

AnimationsConfig.RUN_SPEED_REFERENCE = 34
AnimationsConfig.RUN_SPEED_MIN = 0.8
AnimationsConfig.RUN_SPEED_MAX = 1.45

return AnimationsConfig
