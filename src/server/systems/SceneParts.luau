--!strict

-- Parts from data: the PartSpec shape of PickupScenesConfig and UpgradeStationConfig
-- (primitives with sizes, offsets and colours as plain numbers, or a WorldMeshConfig
-- group with primitive fallbacks) turned into anchored parts in a scene's frame. Shared
-- by WeaponPickups and UpgradeStations.

local WorldMeshes = require(script.Parent.WorldMeshes)

export type PartSpec = {
	kind: string,
	name: string,
	size: { number }?,
	at: { number },
	yaw: number?,
	pitch: number?,
	roll: number?,
	color: { number }?,
	material: string?,
	collide: boolean?,
	transparency: number?,
	group: string?,
	length: number?,
	height: number?,
	fallback: { PartSpec }?,
}

local SceneParts = {}

function SceneParts.color(spec: { number }?): Color3
	if not spec then
		return Color3.fromRGB(120, 120, 120)
	end
	return Color3.fromRGB(spec[1], spec[2], spec[3])
end

local function material(name: string?): Enum.Material
	if name then
		local ok, value = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		if ok and typeof(value) == "EnumItem" then
			return value :: Enum.Material
		end
	end
	return Enum.Material.SmoothPlastic
end

local function frame(spec: PartSpec): CFrame
	return CFrame.new(spec.at[1], spec.at[2], spec.at[3])
		* CFrame.Angles(math.rad(spec.pitch or 0), math.rad(spec.yaw or 0), math.rad(spec.roll or 0))
end

function SceneParts.makePart(spec: PartSpec, base: CFrame, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = spec.name
	if spec.kind == "cylinder" then
		part.Shape = Enum.PartType.Cylinder
	elseif spec.kind == "ball" then
		part.Shape = Enum.PartType.Ball
	end
	local size = spec.size or { 1, 1, 1 }
	part.Size = Vector3.new(size[1], size[2], size[3])
	part.CFrame = base * frame(spec)
	part.Anchored = true
	part.CanCollide = spec.collide == true
	part.CanQuery = spec.collide == true
	part.CanTouch = false
	part.CastShadow = true
	part.Color = SceneParts.color(spec.color)
	part.Material = material(spec.material)
	part.Transparency = spec.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function SceneParts.build(specs: { PartSpec }, base: CFrame, rng: Random, parent: Instance)
	for _, spec in specs do
		if spec.kind == "mesh" then
			local name = if spec.group then WorldMeshes.pick(spec.group, rng) else nil
			local at = base * frame(spec)
			local placed: MeshPart? = nil
			if name then
				local options = { collide = spec.collide == true, shadow = true, sink = 0.15 }
				if spec.length then
					placed = WorldMeshes.placeByLength(name, at, spec.length, parent, options)
				elseif spec.height then
					placed = WorldMeshes.place(name, at, spec.height, parent, options)
				else
					placed = WorldMeshes.placeNatural(name, at, parent, options)
				end
			end
			if placed then
				placed.Name = spec.name
			elseif spec.fallback then
				SceneParts.build(spec.fallback, at, rng, parent)
			end
		else
			SceneParts.makePart(spec, base, parent)
		end
	end
end

return SceneParts
