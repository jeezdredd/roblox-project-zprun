--!strict

-- Pure propagation math for the spatial audio engine: attenuation curves, air absorption,
-- speed-of-sound delay, distance-layer crossfades, occlusion smoothing and reflection
-- timing. Numbers in, numbers out; no Roblox services or datatypes, so
-- `luau tests/audio/run.luau` exercises it outside Studio. Distances are studs
-- (1 stud = 0.28 m), times are seconds, frequencies are hertz.

local AudioMath = {}

AudioMath.METRES_PER_STUD = 0.28

-- 343 m/s at 20 C, in studs per second.
AudioMath.SPEED_OF_SOUND = 343 / AudioMath.METRES_PER_STUD

export type CurveShape = "natural" | "power" | "linear"

export type AbsorptionParams = {
	-- ISO 9613-1 attenuation of the 8 kHz band at 20 C, 50 % RH, in dB per 100 m
	dbPer100mAt8k: number,
	-- games exaggerate air absorption for readability; 1 is physical
	exaggeration: number,
	-- absorption grows with frequency roughly as f^slope between 1 and 8 kHz
	frequencySlope: number,
	-- metres of free filtering before the low-pass starts (Hunt: none below 30 m)
	kneeMetres: number,
	-- the cutoff is the frequency attenuated by this many dB
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

-- Volume (0..1) of a class curve at `distance`. Every shape holds full volume inside
-- `hold` and reaches zero at `range`:
--   natural: the inverse law (hold / d) tapered by a linear-square fall so the end is
--            silent rather than an abrupt cut (Roblox's InverseTapered idea);
--   power:   the inverse law bent flatter, (hold / d) ^ 0.7, for loud sources that stay
--            audible over most of their range, with the same taper;
--   linear:  a straight fall from hold to range, for loops that should stay present.
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

-- The curve as the distance -> volume table `AudioEmitter:SetDistanceAttenuation` takes:
-- the emitter interpolates linearly between the points, so they are spaced where the
-- inverse part bends most. The table is sorted-key friendly (numeric keys).
function AudioMath.attenuationCurve(shape: CurveShape, range: number, hold: number): { [number]: number }
	local curve: { [number]: number } = {}
	curve[0] = 1
	curve[hold] = 1
	local span = range - hold
	if span <= 0 then
		curve[range] = 0
		return curve
	end
	-- denser near the hold radius, where 1/d changes fastest
	local fractions = { 0.02, 0.05, 0.1, 0.16, 0.24, 0.34, 0.46, 0.6, 0.75, 0.9 }
	for _, fraction in fractions do
		local distance = hold + span * fraction
		curve[distance] = AudioMath.attenuationAt(shape, range, hold, distance)
	end
	curve[range] = 0
	return curve
end

-- Low-pass cutoff standing in for air absorption at `distance`. The 8 kHz band loses
-- `dbPer100mAt8k * exaggeration * strength` dB per 100 m past the knee; absorption at
-- other frequencies scales as (f / 8 kHz) ^ slope, so the frequency that has lost
-- `thresholdDb` is the cutoff. Strength 0 (or no distance past the knee) is the
-- ceiling, so a 2D or near voice is untouched.
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

-- Seconds a sound emitted `distance` studs away takes to arrive. Below `minDistance`
-- no delay is applied (the owner's knob if near shots read as lag).
function AudioMath.distanceDelay(distance: number, minDistance: number, speed: number?): number
	if distance < minDistance then
		return 0
	end
	return distance / (speed or AudioMath.SPEED_OF_SOUND)
end

-- Crossfade weight of band `index` among distance layers ordered close -> far. Each band
-- is full inside its own range and ramps across the overlap with its neighbours, with an
-- equal-power shape so the sum stays level in the crossfade; 0 outside the band. A
-- playing layer asks for its own weight every update, so this builds no table.
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

-- Every band's weight at `distance`, for picking the layers to start.
function AudioMath.layerWeights(distance: number, bands: { LayerBand }): { number }
	local weights = table.create(#bands, 0)
	for index in bands do
		weights[index] = AudioMath.layerWeight(distance, bands, index)
	end
	return weights
end

-- The layer to play for `wanted` when a class lists layers but the sound only has some
-- of the keys: the nearest one that exists in `order` (close, mid, far), searching
-- outwards from the wanted index. Nil when nothing exists.
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

-- Exponential approach with a time constant: after `timeConstant` seconds the gap has
-- closed by 63 %, after three it is gone for listening purposes.
function AudioMath.approach(current: number, target: number, deltaTime: number, timeConstant: number): number
	if timeConstant <= 0 then
		return target
	end
	return current + (target - current) * (1 - math.exp(-deltaTime / timeConstant))
end

-- Occlusion (0 open .. 1 blocked) smoothed with separate speeds: a path that clears
-- opens quickly (attack) and a path that closes does so a little slower (release), so a
-- door frame passing the line of sight never clicks.
function AudioMath.smoothOcclusion(current: number, target: number, deltaTime: number, attack: number, release: number): number
	local timeConstant = if target < current then attack else release
	return AudioMath.approach(current, target, deltaTime, timeConstant)
end

-- Gain multiplier for an occluded voice: the material loss scaled by the class's
-- occlusion strength and by how much of the path is blocked.
function AudioMath.occlusionGain(lossDb: number, strength: number, blocked: number): number
	return AudioMath.dbToGain(lossDb * strength * blocked)
end

-- Cutoff of an occluded voice: from the ceiling towards the material cutoff as the path
-- blocks, in the log domain so the sweep sounds even.
function AudioMath.occlusionCutoff(materialCutoff: number, strength: number, blocked: number, ceilingHz: number): number
	local amount = math.clamp(strength * blocked, 0, 1)
	if amount <= 0 then
		return ceilingHz
	end
	local logCeiling = math.log(ceilingHz)
	local logCutoff = math.log(math.max(materialCutoff, 20))
	return math.exp(logCeiling + (logCutoff - logCeiling) * amount)
end

-- Extra travel of a reflection over the direct path, as a delay.
function AudioMath.reflectionDelay(sourceToHit: number, hitToListener: number, direct: number, speed: number?): number
	local extra = sourceToHit + hitToListener - direct
	return math.max(0, extra) / (speed or AudioMath.SPEED_OF_SOUND)
end

-- Gain of a reflection: the class's reflection gain, the surface's reflectivity, and a
-- soft inverse fall over the full path so a slap off a far facade is quiet but present.
function AudioMath.reflectionGain(pathLength: number, reflect: number, gain: number, referenceDistance: number): number
	return gain * reflect / (1 + pathLength / referenceDistance)
end

-- Steal score for a voice: higher priority survives, and among equals the one furthest
-- out of its range and longest playing goes first. Lower score is stolen first.
function AudioMath.stealScore(priority: number, distance: number, range: number, age: number): number
	local reach = if range > 0 then math.clamp(1 - distance / range, 0, 1) else 1
	return priority * 100 + reach * 50 - math.min(age, 30)
end

-- Symmetric jitter: random01 in 0..1 maps to 1 - amount .. 1 + amount.
function AudioMath.jitter(random01: number, amount: number): number
	return 1 + (random01 * 2 - 1) * amount
end

return AudioMath
