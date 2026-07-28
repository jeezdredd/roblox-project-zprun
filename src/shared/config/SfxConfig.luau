--!strict

local AssetIds = require(script.Parent.AssetIds)

local SfxConfig = {}

SfxConfig.FOLEY_GEAR_IDS = { AssetIds.audio.foley.gear_01, AssetIds.audio.foley.gear_02, AssetIds.audio.foley.gear_03 }
SfxConfig.FOLEY_GEAR_VOLUME = 0.18
SfxConfig.FOLEY_GEAR_PITCH_JITTER = 0.12

SfxConfig.LAND_SOFT_ID = AssetIds.audio.foley.land_soft
SfxConfig.LAND_HARD_ID = AssetIds.audio.foley.land_hard
SfxConfig.LAND_HARD_SPEED = 45
SfxConfig.LAND_VOLUME = 0.55

SfxConfig.WHOOSH_ID = AssetIds.audio.foley.cloth_whoosh
SfxConfig.WHOOSH_VOLUME = 0.35
SfxConfig.WHOOSH_COOLDOWN = 0.4
SfxConfig.WHOOSH_MIN_SPEED = 26

SfxConfig.HEARTBEAT_ID = AssetIds.audio.player.heartbeat
SfxConfig.HEARTBEAT_THRESHOLD = 0.3
SfxConfig.HEARTBEAT_VOLUME = 0.55
SfxConfig.HEARTBEAT_PITCH_MIN = 0.9
SfxConfig.HEARTBEAT_PITCH_MAX = 1.5

SfxConfig.WIND_ID = AssetIds.audio.player.wind
SfxConfig.WIND_VOLUME_MAX = 0.42
SfxConfig.WIND_SPEED_MIN = 22
SfxConfig.WIND_SPEED_MAX = 60

SfxConfig.CONCUSSION_DURATION = 1.5
SfxConfig.CONCUSSION_HIGH_GAIN = -22
SfxConfig.CONCUSSION_LOW_GAIN = 0

SfxConfig.ZOMBIE_IDLE_IDS = { AssetIds.audio.zombie.idle_01, AssetIds.audio.zombie.idle_02 }
SfxConfig.ZOMBIE_IDLE_VOLUME = 0.38
SfxConfig.ZOMBIE_IDLE_INTERVAL_MIN = 5
SfxConfig.ZOMBIE_IDLE_INTERVAL_MAX = 13
SfxConfig.ZOMBIE_IDLE_RANGE = 90
SfxConfig.ZOMBIE_IDLE_MAX_VOICES = 6

SfxConfig.ZOMBIE_ALERT_ID = AssetIds.audio.zombie.alert_bark
SfxConfig.ZOMBIE_ALERT_VOLUME = 0.65
SfxConfig.ZOMBIE_ALERT_RANGE = 120
SfxConfig.ZOMBIE_ALERT_MAX_VOICES = 5

SfxConfig.ZOMBIE_BITE_IDS = { AssetIds.audio.zombie.bite_01, AssetIds.audio.zombie.bite_02, AssetIds.audio.zombie.bite_03 }
SfxConfig.ZOMBIE_BITE_VOLUME = 0.7

SfxConfig.HORDE_WALLA_ID = AssetIds.audio.zombie.horde_walla
SfxConfig.HORDE_WALLA_VOLUME_MAX = 0.45
SfxConfig.HORDE_WALLA_RANGE = 160
SfxConfig.HORDE_WALLA_FULL_COUNT = 12

SfxConfig.FIRE_CRACKLE_ID = AssetIds.audio.world.fire_crackle
SfxConfig.FIRE_CRACKLE_VOLUME = 0.5
SfxConfig.FIRE_ROLLOFF_MIN = 40
SfxConfig.FIRE_ROLLOFF_MAX = 320
SfxConfig.FIRE_MAX_SOURCES = 10

SfxConfig.DISTANT_BOOM_ID = AssetIds.audio.world.distant_boom
SfxConfig.DISTANT_BOOM_VOLUME = 0.45
SfxConfig.DISTANT_BOOM_MIN_GAP = 20
SfxConfig.DISTANT_BOOM_MAX_GAP = 60

SfxConfig.ROOMTONE_ID = AssetIds.audio.world.hangar_roomtone
SfxConfig.ROOMTONE_VOLUME = 0.3
SfxConfig.REVERB_HUB = Enum.ReverbType.Hangar
SfxConfig.REVERB_MISSION = Enum.ReverbType.NoReverb

SfxConfig.RADIO_IDS = { AssetIds.audio.world.radio_01 }
SfxConfig.RADIO_VOLUME = 0.5
SfxConfig.RADIO_GAP_MIN = 12
SfxConfig.RADIO_GAP_MAX = 30

SfxConfig.UI_HOVER_ID = AssetIds.audio.ui.hover
SfxConfig.UI_CLICK_ID = AssetIds.audio.ui.click
SfxConfig.UI_COUNTDOWN_TICK_ID = AssetIds.audio.ui.countdown_tick
SfxConfig.UI_COUNTDOWN_GO_ID = AssetIds.audio.ui.countdown_go
SfxConfig.UI_REWARD_TICK_ID = AssetIds.audio.ui.reward_tick
SfxConfig.UI_VOLUME = 0.45

SfxConfig.MUSIC_DUCK_DB = 0.5
SfxConfig.MUSIC_DUCK_RANGE = 60
SfxConfig.MUSIC_DUCK_RELEASE = 3
SfxConfig.MUSIC_DUCK_SPEED = 3

return SfxConfig
