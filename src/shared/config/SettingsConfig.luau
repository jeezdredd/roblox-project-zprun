--!strict

-- "credits" is read-only: the panel shows CreditsConfig there, nothing is stored
export type SettingKind = "toggle" | "slider" | "credits"

export type SettingSpec = {
	key: string,
	category: string,
	label: string,
	kind: SettingKind,
	default: any,
	min: number?,
	max: number?,
	step: number?,
}

local SettingsConfig = {}

SettingsConfig.categories = { "Audio", "Graphics", "Interface", "Content", "Credits" }

SettingsConfig.order = {
	"masterVolume",
	"musicVolume",
	"muted",
	"firstPersonBody",
	"shadows",
	"effectsQuality",
	"fpsCounter",
	"hitMarkers",
	"bloodEnabled",
	"dismembermentEnabled",
	"credits",
}

SettingsConfig.byKey = {
	masterVolume = { key = "masterVolume", category = "Audio", label = "Master Volume", kind = "slider", default = 0.7, min = 0, max = 1, step = 0.05 },
	musicVolume = { key = "musicVolume", category = "Audio", label = "Music Volume", kind = "slider", default = 0.5, min = 0, max = 1, step = 0.05 },
	muted = { key = "muted", category = "Audio", label = "Mute All", kind = "toggle", default = false },
	firstPersonBody = { key = "firstPersonBody", category = "Graphics", label = "Show Own Body", kind = "toggle", default = true },
	shadows = { key = "shadows", category = "Graphics", label = "Shadows", kind = "toggle", default = true },
	effectsQuality = { key = "effectsQuality", category = "Graphics", label = "Effects Density", kind = "slider", default = 1, min = 0.4, max = 1, step = 0.2 },
	fpsCounter = { key = "fpsCounter", category = "Graphics", label = "FPS Counter", kind = "toggle", default = false },
	hitMarkers = { key = "hitMarkers", category = "Interface", label = "Hit markers", kind = "toggle", default = true },
	bloodEnabled = { key = "bloodEnabled", category = "Content", label = "Blood Effects", kind = "toggle", default = true },
	credits = { key = "credits", category = "Credits", label = "Credits", kind = "credits", default = nil },
	dismembermentEnabled = { key = "dismembermentEnabled", category = "Content", label = "Dismemberment", kind = "toggle", default = true },
} :: { [string]: SettingSpec }

return SettingsConfig
