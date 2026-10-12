--!strict

local AudioMath = {}

AudioMath.METRES_PER_STUD = 0.28

AudioMath.SPEED_OF_SOUND = 343 / AudioMath.METRES_PER_STUD

export type CurveShape = "natural" | "power" | "linear"

export type AbsorptionParams = {
	dbPer100mAt8k: number,
	exaggeration: number,
	frequencySlope: number,
	kneeMetres: number,
	thresholdDb: number,
	floorHz: number,
	ceilingHz: number,
}

export type LayerBand = { lo: number, hi: number }

function AudioMath.dbToGain(db: number): number
	return 10 ^ (db / 20)
end

function AudioMath.gainToDb(gain: number): number
	if gain <= 0 then
		return -math.huge
	end
	return 20 * math.log10(gain)
end

function AudioMath.clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

function AudioMath.attenuationAt(shape: CurveShape, range: number, hold: number, distance: number): number
	if distance <= hold then
		return 1
	end
	if distance >= range or range <= hold then
		return 0
	end
	local linear = (range - distance) / (range - hold)
	if shape == "linear" then
		return linear
	end
	local taper = linear * linear
	local inverse = if shape == "power" then (hold / distance) ^ 0.7 else hold / distance
	return math.min(inverse, taper)
end

function AudioMath.attenuationCurve(shape: CurveShape, range: number, hold: number): { [number]: number }
	local curve: { [number]: number } = {}
	curve[0] = 1
	curve[hold] = 1
	local span = range - hold
	if span <= 0 then
		curve[range] = 0
		return curve
	end
	local fractions = { 0.02, 0.05, 0.1, 0.16, 0.24, 0.34, 0.46, 0.6, 0.75, 0.9 }
	for _, fraction in fractions do
		local distance = hold + span * fraction
		curve[distance] = AudioMath.attenuationAt(shape, range, hold, distance)
	end
	curve[range] = 0
	return curve
end

function AudioMath.absorptionCutoff(distance: number, strength: number, params: AbsorptionParams): number
	local metres = math.max(0, distance * AudioMath.METRES_PER_STUD - params.kneeMetres)
	local perMetre = params.dbPer100mAt8k * params.exaggeration * strength / 100
	local lossAt8k = perMetre * metres
	if lossAt8k <= 0 then
		return params.ceilingHz
	end
	local cutoff = 8000 * (params.thresholdDb / lossAt8k) ^ (1 / params.frequencySlope)
	return math.clamp(cutoff, params.floorHz, params.ceilingHz)
end

function AudioMath.distanceDelay(distance: number, minDistance: number, speed: number?): number
	if distance < minDistance then
		return 0
	end
	return distance / (speed or AudioMath.SPEED_OF_SOUND)
end

function AudioMath.layerWeight(distance: number, bands: { LayerBand }, index: number): number
	local band = bands[index]
	if not band or distance < band.lo or distance > band.hi then
		return 0
	end
	local weight = 1
	local previous = bands[index - 1]
	if previous and distance < previous.hi and previous.hi > band.lo then
		weight *= (distance - band.lo) / (previous.hi - band.lo)
	end
	local following = bands[index + 1]
	if following and distance > following.lo and band.hi > following.lo then
		weight *= (band.hi - distance) / (band.hi - following.lo)
	end
	return math.sin(math.clamp(weight, 0, 1) * math.pi / 2)
end

function AudioMath.layerWeights(distance: number, bands: { LayerBand }): { number }
	local weights = table.create(#bands, 0)
	for index in bands do
		weights[index] = AudioMath.layerWeight(distance, bands, index)
	end
	return weights
end

function AudioMath.fallbackLayer(available: { [string]: boolean }, wanted: string, order: { string }): string?
	local wantedIndex = table.find(order, wanted)
	if not wantedIndex then
		return nil
	end
	for step = 1, #order do
		local offset = step - 1
		for _, index in { wantedIndex - offset, wantedIndex + offset } do
			local key = order[index]
			if key and available[key] then
				return key
			end
		end
	end
	return nil
end

function AudioMath.approach(current: number, target: number, deltaTime: number, timeConstant: number): number
	if timeConstant <= 0 then
		return target
	end
	return current + (target - current) * (1 - math.exp(-deltaTime / timeConstant))
end

function AudioMath.smoothOcclusion(current: number, target: number, deltaTime: number, attack: number, release: number): number
	local timeConstant = if target < current then attack else release
	return AudioMath.approach(current, target, deltaTime, timeConstant)
end

function AudioMath.occlusionGain(lossDb: number, strength: number, blocked: number): number
	return AudioMath.dbToGain(lossDb * strength * blocked)
end

function AudioMath.occlusionCutoff(materialCutoff: number, strength: number, blocked: number, ceilingHz: number): number
	local amount = math.clamp(strength * blocked, 0, 1)
	if amount <= 0 then
		return ceilingHz
	end
	local logCeiling = math.log(ceilingHz)
	local logCutoff = math.log(math.max(materialCutoff, 20))
	return math.exp(logCeiling + (logCutoff - logCeiling) * amount)
end

function AudioMath.reflectionDelay(sourceToHit: number, hitToListener: number, direct: number, speed: number?): number
	local extra = sourceToHit + hitToListener - direct
	return math.max(0, extra) / (speed or AudioMath.SPEED_OF_SOUND)
end

function AudioMath.reflectionGain(pathLength: number, reflect: number, gain: number, referenceDistance: number): number
	return gain * reflect / (1 + pathLength / referenceDistance)
end

function AudioMath.stealScore(priority: number, distance: number, range: number, age: number): number
	local reach = if range > 0 then math.clamp(1 - distance / range, 0, 1) else 1
	return priority * 100 + reach * 50 - math.min(age, 30)
end

function AudioMath.jitter(random01: number, amount: number): number
	return 1 + (random01 * 2 - 1) * amount
end

return AudioMath
