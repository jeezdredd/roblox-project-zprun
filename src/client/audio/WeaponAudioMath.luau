--!strict

-- Pure rules for the weapon sounds on the engine (WeaponSfx): which tail a shot takes
-- in an environment, the reflection fan's rate limit, the distance layer keys of a
-- remote shot, the impact family of a material. No services and no requires, so
-- tests/audio/run.luau runs it under the standalone Luau CLI.

local WeaponAudioMath = {}

export type Lookup = (key: string) -> number

-- share of the shot volume each tail plays at
WeaponAudioMath.TAIL_INTERIOR_VOLUME = 0.34
WeaponAudioMath.TAIL_CLASS_VOLUME = 1
WeaponAudioMath.TAIL_GENERIC_VOLUME = 0.46

-- environments whose reverb carries the room, so the shot takes the interior tail
WeaponAudioMath.INTERIOR_ENVIRONMENTS = { Interior = true, Hangar = true } :: { [string]: boolean }

-- The tail of a shot: the interior recording inside a room or the hangar, the class's
-- own outdoor reflection elsewhere, the generic outdoor tail (quieter) when the class
-- has none. Returns the id (0 for none) and the volume as a share of the shot volume.
function WeaponAudioMath.tailFor(environment: string, class: string, lookup: Lookup): (number, number)
	if WeaponAudioMath.INTERIOR_ENVIRONMENTS[environment] then
		return lookup("tail_interior"), WeaponAudioMath.TAIL_INTERIOR_VOLUME
	end
	local classTail = lookup("tail_open_" .. string.lower(class))
	if classTail > 0 then
		return classTail, WeaponAudioMath.TAIL_CLASS_VOLUME
	end
	return lookup("tail_open"), WeaponAudioMath.TAIL_GENERIC_VOLUME
end

-- Rate limit for the reflection fan: `lastAt` is when the last fan fired, `now` the
-- clock, `interval` the minimum gap. Returns whether this one may fire and the new
-- `lastAt` to store.
function WeaponAudioMath.gate(lastAt: number, now: number, interval: number): (boolean, number)
	if now - lastAt < interval then
		return false, lastAt
	end
	return true, now
end

-- Distance layers of a remote shot: the close take always, mid and far only when they
-- have an id. The engine's layer fallback plays the nearest layer that exists.
function WeaponAudioMath.layerIds(closeId: number, midId: number, farId: number): { [string]: number }
	local ids: { [string]: number } = {}
	if closeId > 0 then
		ids.close = closeId
	end
	if midId > 0 then
		ids.mid = midId
	end
	if farId > 0 then
		ids.far = farId
	end
	return ids
end

WeaponAudioMath.IMPACT_FAMILIES = { "concrete", "metal", "wood", "dirt", "flesh" }

local IMPACT_FAMILY: { [string]: string } = {
	Metal = "metal",
	DiamondPlate = "metal",
	CorrodedMetal = "metal",
	Foil = "metal",
	Wood = "wood",
	WoodPlanks = "wood",
	Cardboard = "wood",
	Plastic = "wood",
	SmoothPlastic = "wood",
	Grass = "dirt",
	LeafyGrass = "dirt",
	Sand = "dirt",
	Mud = "dirt",
	Ground = "dirt",
	Snow = "dirt",
	Fabric = "dirt",
	Carpet = "dirt",
	Salt = "dirt",
	Water = "dirt",
	Flesh = "flesh",
}

-- Which impact recording set a hit on `materialName` plays; stone and everything
-- unlisted is concrete.
function WeaponAudioMath.impactFamily(materialName: string): string
	return IMPACT_FAMILY[materialName] or "concrete"
end

-- The keys an impact tries, in order: the family's own recordings, then the generic
-- placeholder key for the family.
function WeaponAudioMath.impactKeys(family: string, variations: number): { string }
	local keys = {}
	for index = 1, variations do
		table.insert(keys, string.format("impact_%s_%02d", family, index))
	end
	return keys
end

-- How many of one volley's hits get a sound: the first few, so a shotgun's pellets
-- read as one impact, not eight.
function WeaponAudioMath.impactsToPlay(hits: number, cap: number): number
	return math.clamp(hits, 0, cap)
end

return WeaponAudioMath
