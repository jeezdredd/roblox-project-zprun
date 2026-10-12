--!strict

local ChunkOccupancy = {}

local circles: { { number } } = {}
local remembered: { [any]: { { number } } } = setmetatable({}, { __mode = "k" }) :: any

local function freeAmong(list: { { number } }, x: number, z: number, radius: number): boolean
	for _, c in list do
		local dx, dz = x - c[1], z - c[2]
		local reach = radius + c[3]
		if dx * dx + dz * dz < reach * reach then
			return false
		end
	end
	return true
end

function ChunkOccupancy.reset()
	table.clear(circles)
end

function ChunkOccupancy.isFree(x: number, z: number, radius: number): boolean
	return freeAmong(circles, x, z, radius)
end

function ChunkOccupancy.claim(x: number, z: number, radius: number): boolean
	if not ChunkOccupancy.isFree(x, z, radius) then
		return false
	end
	table.insert(circles, { x, z, radius })
	return true
end

function ChunkOccupancy.reserve(x: number, z: number, radius: number)
	table.insert(circles, { x, z, radius })
end

function ChunkOccupancy.reserveBox(x0: number, z0: number, x1: number, z1: number)
	local minX, maxX = math.min(x0, x1), math.max(x0, x1)
	local minZ, maxZ = math.min(z0, z1), math.max(z0, z1)
	local w, d = maxX - minX, maxZ - minZ
	if w >= d then
		local r = d / 2
		local steps = math.max(1, math.ceil(w / math.max(d, 1)))
		for i = 0, steps do
			table.insert(circles, { minX + w * i / steps, minZ + r, r })
		end
	else
		local r = w / 2
		local steps = math.max(1, math.ceil(d / math.max(w, 1)))
		for i = 0, steps do
			table.insert(circles, { minX + r, minZ + d * i / steps, r })
		end
	end
end

function ChunkOccupancy.remember(key: any)
	local copy: { { number } } = {}
	for _, c in circles do
		table.insert(copy, { c[1], c[2], c[3] })
	end
	remembered[key] = copy
end

function ChunkOccupancy.forget(key: any)
	remembered[key] = nil
end

function ChunkOccupancy.isFreeFor(key: any, x: number, z: number, radius: number): boolean
	local list = remembered[key]
	if not list then
		return true
	end
	return freeAmong(list, x, z, radius)
end

function ChunkOccupancy.findSpot(radius: number, attempts: number, sample: () -> (number, number)): (number?, number?)
	for _ = 1, attempts do
		local x, z = sample()
		if ChunkOccupancy.claim(x, z, radius) then
			return x, z
		end
	end
	return nil, nil
end

return ChunkOccupancy
