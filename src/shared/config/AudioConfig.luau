--!strict

local AssetIds = require(script.Parent.AssetIds)

local AudioConfig = {
	MENU_MUSIC_ID = AssetIds.audio.music.menu,
	MISSION_MUSIC_ID = AssetIds.audio.music.mission,
	DEATH_SCREAM_ID = AssetIds.audio.player.death_scream,

	CITY_SIREN_ID = AssetIds.audio.city.siren_facility,
	POLICE_SIREN_ID = AssetIds.audio.city.siren_police,
	AMBULANCE_SIREN_ID = AssetIds.audio.city.siren_ambulance,
	CIVIL_SIREN_ID = AssetIds.audio.city.siren_civil,
	HELI_LOOP_ID = AssetIds.audio.city.helicopter,

	ZOMBIE_GROWL_ID = AssetIds.audio.zombie.growl_01,

	MENU_MUSIC_VOLUME = 0.5,
	MUSIC_FADE_TIME = 1.2,
	SIREN_VOLUME = 0.11,
	POLICE_VOLUME = 0.14,
	HELI_VOLUME = 0.22,
	ZOMBIE_VOLUME = 0.5,

	SIREN_PATROL_COUNT = 3,
	SIREN_BURST_MIN = 7,
	SIREN_BURST_MAX = 14,
	SIREN_GAP_MIN = 14,
	SIREN_GAP_MAX = 38,
	SIREN_PATROL_RADIUS_MIN = 240,
	SIREN_PATROL_RADIUS_MAX = 520,
	SIREN_PATROL_SPEED_MIN = 0.05,
	SIREN_PATROL_SPEED_MAX = 0.11,

	AMBIENCE_ROLLOFF_MIN = 90,
	AMBIENCE_ROLLOFF_MAX = 1500,
	ZOMBIE_ROLLOFF_MIN = 10,
	ZOMBIE_ROLLOFF_MAX = 120,

	MASTER_GROUP = "TFZ_Master",
	MUSIC_GROUP = "TFZ_Music",
	SFX_GROUP = "TFZ_Sfx",
}

return table.freeze(AudioConfig)
