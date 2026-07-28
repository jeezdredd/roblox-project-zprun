--!strict

export type BreathLayer = {
	id: string,
	soundId: number,
	volume: number,
	rangeMin: number,
	rangeMax: number,
	pitch: number,
}

local AssetIds = require(script.Parent.AssetIds)

local BreathingConfig = {}

BreathingConfig.FADE_SPEED = 1.6

BreathingConfig.layers = {
	{ id = "Calm", soundId = AssetIds.audio.player.breath_calm, volume = 0.28, rangeMin = 0, rangeMax = 0.4, pitch = 1 },
	{ id = "Heavy", soundId = AssetIds.audio.player.breath_heavy, volume = 0.42, rangeMin = 0.4, rangeMax = 0.75, pitch = 1 },
	{ id = "Gasp", soundId = AssetIds.audio.player.breath_gasp, volume = 0.55, rangeMin = 0.75, rangeMax = 1, pitch = 1.04 },
} :: { BreathLayer }

function BreathingConfig.weightFor(layer: BreathLayer, exertion: number): number
	local center = (layer.rangeMin + layer.rangeMax) / 2
	local halfWidth = math.max((layer.rangeMax - layer.rangeMin) / 2, 0.01)
	local distance = math.abs(exertion - center)
	return math.clamp(1 - distance / (halfWidth * 2), 0, 1)
end

return BreathingConfig
