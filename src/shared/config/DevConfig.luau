--!strict

local DevConfig = {}

DevConfig.QUICK_RUN = {
	enabled = true,
	delay = 1,
	relaunchAfterDeath = true,
	relaunchDelay = 1.5,
	seed = nil,
	mapId = nil,
}

DevConfig.QUICK_LAUNCH = {
	intermission = true,
}

DevConfig.SKIP_GORE_WARNING = true

DevConfig.FREEZE_RUN = false

DevConfig.THIRD_PERSON_VIEW = false

DevConfig.TARGET_RANGE = {
	enabled = true,
	distances = { 10, 25, 50, 100 },
	spacing = 4,
	health = 100,
	respawnDelay = 1.5,
}

DevConfig.SANDBOX = {
	enabled = true,
	origin = Vector3.new(3000, 0, 0),
	respawnDelay = 3,
	waveSize = 6,
}

return DevConfig
