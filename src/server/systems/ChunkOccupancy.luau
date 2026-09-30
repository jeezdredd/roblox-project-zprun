--!strict

-- Footprints already taken in the chunk being built, so props do not spawn inside
-- each other. Chunk building is synchronous, so one module-level list is enough:
-- ChunkFactory.build resets it, then every placement either claims a circle or skips.
-- Coordinates are chunk-local x/z; radii are the prop's ground footprint, not its
-- canopy (a tree's crown may overlap a car, its trunk may not).

local ChunkOccupancy = {}

local circles: { { number } } = {}
-- the claims of every built chunk, keyed by the chunk model (weak: a destroyed chunk
-- takes its list with it; a pooled one keeps it, its props stay where they were), so
-- things placed after the build (WeaponPickups) can avoid what the query cannot see
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

-- Takes the circle when it is free. Returns whether it was taken.
function ChunkOccupancy.claim(x: number, z: number, radius: number): boolean
	if not ChunkOccupancy.isFree(x, z, radius) then
		return false
	end
	table.insert(circles, { x, z, radius })
	return true
end

-- Records a footprint without checking (for things placed by construction, such as
-- a lamp row or a building slot, that later random props must avoid).
function ChunkOccupancy.reserve(x: number, z: number, radius: number)
	table.insert(circles, { x, z, radius })
end

-- Reserves a rectangle as a row of circles along its long axis.
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

-- Keeps a copy of the current claims under `key` (the chunk model) for isFreeFor.
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

-- Whether the circle is free of the claims remembered under `key` (true when nothing
-- was remembered: a chunk built before this existed).
function ChunkOccupancy.isFreeFor(key: any, x: number, z: number, radius: number): boolean
	local list = remembered[key]
	if not list then
		return true
	end
	return freeAmong(list, x, z, radius)
end

-- Tries a few random spots from `sample` and claims the first free one.
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
