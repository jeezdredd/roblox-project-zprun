--!strict

local WeaponAudioMath = {}

export type Lookup = (key: string) -> number

WeaponAudioMath.TAIL_INTERIOR_VOLUME = 0.34
WeaponAudioMath.TAIL_CLASS_VOLUME = 1
WeaponAudioMath.TAIL_GENERIC_VOLUME = 0.46

WeaponAudioMath.INTERIOR_ENVIRONMENTS = { Interior = true, Hangar = true } :: { [string]: boolean }

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

function WeaponAudioMath.gate(lastAt: number, now: number, interval: number): (boolean, number)
	if now - lastAt < interval then
		return false, lastAt
	end
	return true, now
end

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

function WeaponAudioMath.impactFamily(materialName: string): string
	return IMPACT_FAMILY[materialName] or "concrete"
end

function WeaponAudioMath.impactKeys(family: string, variations: number): { string }
	local keys = {}
	for index = 1, variations do
		table.insert(keys, string.format("impact_%s_%02d", family, index))
	end
	return keys
end

function WeaponAudioMath.impactsToPlay(hits: number, cap: number): number
	return math.clamp(hits, 0, cap)
end

return WeaponAudioMath
