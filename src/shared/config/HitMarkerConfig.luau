--!strict

local HitMarkerConfig = {}

HitMarkerConfig.HIT_DURATION = 0.12
HitMarkerConfig.KILL_DURATION = 0.25

HitMarkerConfig.DAMAGE_REFERENCE = 30
HitMarkerConfig.DAMAGE_SCALE = 0.25
HitMarkerConfig.SCALE_MIN = 0.9
HitMarkerConfig.SCALE_MAX = 1.25
HitMarkerConfig.KILL_SCALE = 1.35

HitMarkerConfig.POP = 1.15
HitMarkerConfig.POP_SHARE = 0.3
HitMarkerConfig.FADE_FROM = 0.55

HitMarkerConfig.GAP = 11
HitMarkerConfig.TICK_LENGTH = 8
HitMarkerConfig.TICK_THICKNESS = 2

HitMarkerConfig.colors = {
	Hit = { 236, 236, 230 },
	Headshot = { 255, 196, 70 },
	Kill = { 226, 52, 44 },
} :: { [string]: { number } }

HitMarkerConfig.SOUND_HIT = "hit_marker"
HitMarkerConfig.SOUND_KILL = "kill_marker"
HitMarkerConfig.SOUND_VOLUME = 0.5

HitMarkerConfig.SETTING_KEY = "hitMarkers"

return HitMarkerConfig
