--!strict

-- Pure-math tests for the spatial audio engine. Run from the repository root with the
-- standalone Luau CLI:  luau tests/audio/run.luau
-- Every group prints one line; the first failing assertion stops the run with a
-- non-zero exit.

local AudioMath = require("../../src/client/audio/AudioMath")

local failures = 0

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		return
	end
	failures += 1
	print(string.format("  FAIL %s%s", name, if detail then " (" .. detail .. ")" else ""))
end

local function near(a: number, b: number, tolerance: number): boolean
	return math.abs(a - b) <= tolerance
end

local function group(name: string, body: () -> ())
	local before = failures
	body()
	print(string.format("%s %s", if failures == before then "ok  " else "FAIL", name))
end

local ABSORPTION: AudioMath.AbsorptionParams = {
	dbPer100mAt8k = 10.5,
	exaggeration = 6,
	frequencySlope = 1.7,
	kneeMetres = 25,
	thresholdDb = 6,
	floorHz = 1200,
	ceilingHz = 22000,
}

group("decibels", function()
	check("0 dB is unity", near(AudioMath.dbToGain(0), 1, 1e-9))
	check("-6 dB halves", near(AudioMath.dbToGain(-6.0206), 0.5, 1e-4))
	check("round trip", near(AudioMath.gainToDb(AudioMath.dbToGain(-13)), -13, 1e-9))
	check("silence is -inf", AudioMath.gainToDb(0) == -math.huge)
end)

group("attenuation curves", function()
	for _, shape in { "natural", "power", "linear" } :: { AudioMath.CurveShape } do
		check(shape .. " full inside hold", AudioMath.attenuationAt(shape, 100, 10, 5) == 1)
		check(shape .. " full at hold", AudioMath.attenuationAt(shape, 100, 10, 10) == 1)
		check(shape .. " silent at range", AudioMath.attenuationAt(shape, 100, 10, 100) == 0)
		check(shape .. " silent past range", AudioMath.attenuationAt(shape, 100, 10, 500) == 0)
		local previous = 1
		for distance = 10, 100, 1 do
			local value = AudioMath.attenuationAt(shape, 100, 10, distance)
			check(shape .. " monotonic at " .. distance, value <= previous + 1e-9, tostring(value))
			previous = value
		end
	end
	-- natural follows 1/d near the hold: 10 studs hold, 20 studs is half
	check("natural is inverse near hold", near(AudioMath.attenuationAt("natural", 1000, 10, 20), 0.5, 1e-6))
	-- power falls slower than natural
	check("power louder than natural", AudioMath.attenuationAt("power", 1000, 10, 100) > AudioMath.attenuationAt("natural", 1000, 10, 100))
	-- degenerate range
	check("range inside hold is silent", AudioMath.attenuationAt("natural", 5, 10, 12) == 0)

	local curve = AudioMath.attenuationCurve("natural", 120, 10)
	check("curve starts at 1", curve[0] == 1 and curve[10] == 1)
	check("curve ends at 0", curve[120] == 0)
	local count = 0
	for distance, volume in curve do
		count += 1
		check("curve point in range", distance >= 0 and distance <= 120 and volume >= 0 and volume <= 1)
	end
	check("curve has 13 points", count == 13, tostring(count))
end)

group("air absorption", function()
	check("no filter at the knee", AudioMath.absorptionCutoff(80, 1, ABSORPTION) == 22000)
	check("no filter with strength 0", AudioMath.absorptionCutoff(2000, 0, ABSORPTION) == 22000)
	local at30m = AudioMath.absorptionCutoff(30 / 0.28, 1, ABSORPTION)
	local at50m = AudioMath.absorptionCutoff(50 / 0.28, 1, ABSORPTION)
	local at70m = AudioMath.absorptionCutoff(70 / 0.28, 1, ABSORPTION)
	local at112m = AudioMath.absorptionCutoff(400, 1, ABSORPTION)
	-- Hunt's schedule: light 30..70 m, strong beyond
	check("light at 30 m", at30m > 9000 and at30m < 14000, tostring(at30m))
	check("mid at 50 m", at50m > 3500 and at50m < 6000, tostring(at50m))
	check("strong at 70 m", at70m > 2500 and at70m < 4000, tostring(at70m))
	check("stronger at 112 m", at112m > 1500 and at112m < 3000, tostring(at112m))
	check("floor far out", AudioMath.absorptionCutoff(3000, 1, ABSORPTION) == 1200)
	check("strength scales", AudioMath.absorptionCutoff(400, 0.5, ABSORPTION) > at112m)
	local previous = 22000
	for distance = 0, 3000, 25 do
		local cutoff = AudioMath.absorptionCutoff(distance, 1, ABSORPTION)
		check("cutoff monotonic at " .. distance, cutoff <= previous + 1e-6)
		previous = cutoff
	end
end)

group("speed of sound", function()
	check("1225 studs per second", near(AudioMath.SPEED_OF_SOUND, 1225, 1))
	check("36 studs is 29 ms", near(AudioMath.distanceDelay(36, 0), 0.0294, 0.0005))
	check("357 studs is 292 ms", near(AudioMath.distanceDelay(357, 0), 0.2914, 0.001))
	check("below min distance is 0", AudioMath.distanceDelay(30, 40) == 0)
	check("custom speed", near(AudioMath.distanceDelay(100, 0, 50), 2, 1e-9))
end)

group("distance layers", function()
	local bands = { { lo = 0, hi = 60 }, { lo = 40, hi = 350 }, { lo = 250, hi = 1400 } }
	local close = AudioMath.layerWeights(10, bands)
	check("close only near", close[1] == 1 and close[2] == 0 and close[3] == 0)
	local mid = AudioMath.layerWeights(150, bands)
	check("mid only in the middle", mid[1] == 0 and mid[2] == 1 and mid[3] == 0)
	local far = AudioMath.layerWeights(1000, bands)
	check("far only far", far[1] == 0 and far[2] == 0 and far[3] == 1)
	local blend = AudioMath.layerWeights(50, bands)
	check("crossfade has both", blend[1] > 0 and blend[2] > 0 and blend[3] == 0)
	check("equal power at the midpoint", near(blend[1], blend[2], 1e-9) and near(blend[1], math.sin(math.pi / 4), 1e-9))
	check("nothing past the end", AudioMath.layerWeights(2000, bands)[3] == 0)
	-- weights never exceed 1 and every band is continuous across its edges
	for distance = 0, 1400, 5 do
		local weights = AudioMath.layerWeights(distance, bands)
		for index, weight in weights do
			check("weight bounded", weight >= 0 and weight <= 1, string.format("%d %d %f", distance, index, weight))
		end
	end

	local order = { "close", "mid", "far" }
	check("fallback exact", AudioMath.fallbackLayer({ close = true, far = true }, "close", order) == "close")
	check("fallback nearest inward", AudioMath.fallbackLayer({ close = true }, "far", order) == "close")
	check("fallback nearest outward", AudioMath.fallbackLayer({ far = true }, "close", order) == "far")
	check("fallback prefers the closer neighbour", AudioMath.fallbackLayer({ close = true, far = true }, "mid", order) == "close")
	check("fallback nothing", AudioMath.fallbackLayer({}, "mid", order) == nil)
	check("fallback unknown key", AudioMath.fallbackLayer({ close = true }, "huge", order) == nil)
end)

group("occlusion smoothing", function()
	local value = 0
	for _ = 1, 60 do
		value = AudioMath.smoothOcclusion(value, 1, 1 / 60, 0.12, 0.25)
	end
	check("closes over a second", value > 0.95, tostring(value))
	local opened = value
	for _ = 1, 30 do
		opened = AudioMath.smoothOcclusion(opened, 0, 1 / 60, 0.12, 0.25)
	end
	check("opens faster than it closes", opened < 0.05, tostring(opened))
	check("approach with zero constant snaps", AudioMath.approach(0, 1, 0.016, 0) == 1)
	check("approach is stable", AudioMath.approach(1, 1, 0.016, 0.3) == 1)

	check("occlusion gain open is unity", AudioMath.occlusionGain(-30, 1, 0) == 1)
	check("occlusion gain full is the loss", near(AudioMath.occlusionGain(-30, 1, 1), AudioMath.dbToGain(-30), 1e-9))
	check("occlusion gain scales with strength", near(AudioMath.occlusionGain(-30, 0.5, 1), AudioMath.dbToGain(-15), 1e-9))
	check("occlusion cutoff open is ceiling", AudioMath.occlusionCutoff(600, 1, 0, 22000) == 22000)
	check("occlusion cutoff blocked is the material", near(AudioMath.occlusionCutoff(600, 1, 1, 22000), 600, 1e-6))
	local half = AudioMath.occlusionCutoff(600, 1, 0.5, 22000)
	check("occlusion cutoff halfway is geometric", near(half, math.sqrt(600 * 22000), 1e-3), tostring(half))
end)

group("reflections", function()
	-- a facade 36 studs (10 m) to the side, source and listener together: 72 studs extra
	local delay = AudioMath.reflectionDelay(36, 36, 0)
	check("10 m facade is 58 ms", near(delay, 0.0588, 0.001), tostring(delay))
	check("no negative delay", AudioMath.reflectionDelay(10, 10, 100) == 0)
	check("gain falls with path", AudioMath.reflectionGain(60, 1, 0.5, 60) < AudioMath.reflectionGain(10, 1, 0.5, 60))
	check("gain at reference is half", near(AudioMath.reflectionGain(60, 1, 0.5, 60), 0.25, 1e-9))
	check("soft surface reflects less", AudioMath.reflectionGain(60, 0.2, 0.5, 60) < AudioMath.reflectionGain(60, 0.9, 0.5, 60))
end)

group("voice stealing", function()
	check("priority wins", AudioMath.stealScore(90, 100, 200, 0) > AudioMath.stealScore(30, 0, 200, 0))
	check("far voice goes before near", AudioMath.stealScore(50, 190, 200, 0) < AudioMath.stealScore(50, 10, 200, 0))
	check("old voice goes before new", AudioMath.stealScore(50, 10, 200, 20) < AudioMath.stealScore(50, 10, 200, 1))
	check("2D voices count as in range", AudioMath.stealScore(50, 0, 0, 0) == AudioMath.stealScore(50, 5, 0, 0))
	check("jitter centre", AudioMath.jitter(0.5, 0.1) == 1)
	check("jitter edges", near(AudioMath.jitter(0, 0.1), 0.9, 1e-9) and near(AudioMath.jitter(1, 0.1), 1.1, 1e-9))
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all audio math tests passed")
