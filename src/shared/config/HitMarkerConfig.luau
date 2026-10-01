--!strict

-- Hit and kill markers (docs/gameplay/hit-markers.md), after Modern Warfare 2019's hip
-- fire: four short diagonal ticks around the crosshair on the server's confirmation of
-- damage to a zombie by the local shooter, a tint for a headshot, larger red ticks for a
-- kill. Data only, no engine types: the pure HitMarkerMath and its tests read it under
-- the standalone Luau CLI. Colours are {r, g, b}; sizes are pixels at scale 1.

local HitMarkerConfig = {}

-- How long each variant shows, seconds.
HitMarkerConfig.HIT_DURATION = 0.12
HitMarkerConfig.KILL_DURATION = 0.25

-- A hit's ticks grow a little with the damage the shot dealt: scale 1 at
-- DAMAGE_REFERENCE (a rifle body shot), DAMAGE_SCALE of the relative difference, kept
-- within SCALE_MIN..SCALE_MAX so a shotgun's full pellet sum or a pistol graze stay
-- readable. A kill is always KILL_SCALE.
HitMarkerConfig.DAMAGE_REFERENCE = 30
HitMarkerConfig.DAMAGE_SCALE = 0.25
HitMarkerConfig.SCALE_MIN = 0.9
HitMarkerConfig.SCALE_MAX = 1.25
HitMarkerConfig.KILL_SCALE = 1.35

-- Each marker pops in this much larger and settles to its scale over the first share
-- of its time, holds full, then fades out over the last share.
HitMarkerConfig.POP = 1.15
HitMarkerConfig.POP_SHARE = 0.3
HitMarkerConfig.FADE_FROM = 0.55

-- The ticks: distance of each tick's centre from the crosshair along the diagonal,
-- length and thickness.
HitMarkerConfig.GAP = 11
HitMarkerConfig.TICK_LENGTH = 8
HitMarkerConfig.TICK_THICKNESS = 2

HitMarkerConfig.colors = {
	Hit = { 236, 236, 230 },
	Headshot = { 255, 196, 70 },
	Kill = { 226, 52, 44 },
} :: { [string]: { number } }

-- AssetIds.audio.ui keys; 0 (the slots are `needed`) plays nothing.
HitMarkerConfig.SOUND_HIT = "hit_marker"
HitMarkerConfig.SOUND_KILL = "kill_marker"
HitMarkerConfig.SOUND_VOLUME = 0.5

-- The settings key (SettingsConfig) that turns the markers off.
HitMarkerConfig.SETTING_KEY = "hitMarkers"

return HitMarkerConfig
