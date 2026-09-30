--!strict

-- Reflections for loud events (the MW2019 approach): a fan of rays from the source
-- finds nearby surfaces, and each hit plays the sound again from that point, later by
-- the extra path over the direct one, quieter by the path and the surface, and
-- low-passed by the material. An open field has no hits and no reflections; a street
-- gets slapback from its facades; an interior keeps at most two because the bus reverb
-- already carries the rest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpatialAudioConfig = require(ReplicatedStorage.Shared.config.SpatialAudioConfig)
local AudioEngine = require(script.Parent.AudioEngine)
local AudioEnvironment = require(script.Parent.AudioEnvironment)
local AudioMath = require(script.Parent.AudioMath)

local AudioReflections = {}

local REFLECTIONS = SpatialAudioConfig.REFLECTIONS
local random = Random.new()

type Hit = { position: Vector3, normal: Vector3, material: SpatialAudioConfig.MaterialSpec, sourceToHit: number }

local function fan(rays: number): { Vector3 }
	local directions: { Vector3 } = {}
	local yaw = random:NextNumber(0, math.pi * 2)
	local pitch = math.rad(REFLECTIONS.upwardRayDegrees)
	for index = 1, rays do
		local angle = yaw + (index - 1) * math.pi * 2 / rays
		-- every third ray looks a little up, for balconies, canopies and ceilings
		local up = if index % 3 == 0 then math.sin(pitch) else 0
		local flat = if index % 3 == 0 then math.cos(pitch) else 1
		table.insert(directions, Vector3.new(math.cos(angle) * flat, up, math.sin(angle) * flat))
	end
	return directions
end

-- `id` is the recording to reflect (usually the shot itself), `bus` the bus of the
-- event's class, `volume` the event's volume before the class gain. `rays` overrides
-- the profile count.
function AudioReflections.fire(position: Vector3, id: number, bus: string, volume: number, pitch: number, rays: number)
	if not AudioEngine.enabled() or id <= 0 or rays <= 0 then
		return
	end
	local listener = AudioEngine.listenerPosition()
	local direct = (position - listener).Magnitude
	local environment = AudioEnvironment.environmentAt(position)
	local cap = if SpatialAudioConfig.INTERIOR_ENVIRONMENTS[environment] then REFLECTIONS.interiorCap else rays

	local hits: { Hit } = {}
	for _, direction in fan(rays) do
		if #hits >= cap then
			break
		end
		local result = AudioEnvironment.cast(position, direction * REFLECTIONS.range)
		if not result then
			continue
		end
		local merged = false
		for _, existing in hits do
			if (existing.position - result.Position).Magnitude < REFLECTIONS.mergeDistance then
				merged = true
				break
			end
		end
		if merged then
			continue
		end
		table.insert(hits, {
			position = result.Position,
			normal = result.Normal,
			material = AudioEnvironment.material(result.Material),
			sourceToHit = result.Distance,
		})
	end

	for _, hit in hits do
		local hitToListener = (hit.position - listener).Magnitude
		local extra = AudioMath.reflectionDelay(hit.sourceToHit, hitToListener, direct, SpatialAudioConfig.SPEED_OF_SOUND_STUDS)
		if extra < REFLECTIONS.minDelay then
			continue
		end
		local path = hit.sourceToHit + hitToListener
		local gain = AudioMath.reflectionGain(path, hit.material.reflect, REFLECTIONS.gain, REFLECTIONS.referenceDistance)
		-- the engine adds the hit-to-listener leg itself (Reflection has delay = true),
		-- so only the source-to-hit leg goes in here
		AudioEngine.play({
			id = id,
			class = "Reflection",
			bus = bus,
			position = hit.position + hit.normal,
			volume = volume * gain,
			pitch = pitch * REFLECTIONS.pitch,
			delay = hit.sourceToHit / SpatialAudioConfig.SPEED_OF_SOUND_STUDS,
			cutoff = hit.material.cutoff,
		})
	end
end

return AudioReflections
