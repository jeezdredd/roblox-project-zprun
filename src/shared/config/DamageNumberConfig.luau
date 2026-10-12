--!strict

local DamageNumberConfig = {}

DamageNumberConfig.POOL_SIZE = 24
DamageNumberConfig.DURATION = 0.6
DamageNumberConfig.RISE = 2.5
DamageNumberConfig.JITTER = 0.6
DamageNumberConfig.FADE_FROM = 0.4
DamageNumberConfig.GUI_SIZE = { 160, 60 }
DamageNumberConfig.MAX_DISTANCE = 150

DamageNumberConfig.TEXT_SIZE = {
	Hit = 24,
	Headshot = 32,
	Kill = 42,
} :: { [string]: number }

DamageNumberConfig.SETTING_KEY = "damageNumbers"

return DamageNumberConfig
