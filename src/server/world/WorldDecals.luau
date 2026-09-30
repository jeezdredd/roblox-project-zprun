--!strict

-- The decal layer of a chunk: marks from DecalsConfig placed as thin cards on the
-- ground, cards in front of road-facing walls, and a tiled Texture on the floor. Ids
-- come from AssetIds.texture.decal; a key that is missing or 0 places nothing.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local DecalsConfig = require(ReplicatedStorage.Shared.config.DecalsConfig)
local DressingConfig = require(ReplicatedStorage.Shared.config.DressingConfig)
local DressingPlanner = require(ReplicatedStorage.Shared.world.DressingPlanner)

local WorldDecals = {}

local CARD_THICKNESS = 0.05

local decalIds: { [string]: any }? = (AssetIds.texture :: any).decal

local function assetUrl(id: number): string
	return "rbxassetid://" .. tostring(id)
end

local function card(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function decal(id: number, face: Enum.NormalId, transparency: number, layer: number, parent: Instance): Decal
	local d = Instance.new("Decal")
	d.Texture = assetUrl(id)
	d.Face = face
	d.Transparency = transparency
	d.ZIndex = layer
	d.Parent = parent
	return d
end

local function cardSize(entry: DecalsConfig.Entry, rng: Random): (number, number)
	if entry.fixed then
		return entry.size[1], entry.size[2]
	end
	local side = rng:NextNumber(entry.size[1], entry.size[2])
	return side, side
end

-- Chunk-local x for a ground zone, either side of the road.
local function zoneX(entry: DecalsConfig.Entry, width: number, halfWidth: number, rng: Random): number?
	if entry.zone == "lane" then
		local limit = math.min(DecalsConfig.LANE_HALF, halfWidth) - width / 2
		if limit <= 0 then
			return nil
		end
		return rng:NextNumber(-limit, limit)
	end
	local zone = DressingConfig.zones[entry.zone]
	if not zone then
		return nil
	end
	local sign = if rng:NextNumber() < 0.5 then -1 else 1
	local low, high = zone.inner + width / 2, zone.outer - width / 2
	if low > high then
		return sign * (zone.inner + zone.outer) / 2
	end
	return sign * rng:NextNumber(low, high)
end

local function placeGround(entry: DecalsConfig.Entry, id: number, biome: string, rng: Random, halfWidth: number, halfLength: number, index: number, parent: Instance): boolean
	local width, depth = cardSize(entry, rng)
	local x = zoneX(entry, width, halfWidth, rng)
	if not x then
		return false
	end
	local reach = halfLength - DecalsConfig.END_CLEARANCE - depth / 2
	if reach <= 0 then
		return false
	end
	local z = rng:NextNumber(-reach, reach)
	local yaw = if entry.fixed then rng:NextNumber(-0.3, 0.3) else rng:NextNumber(0, math.pi * 2)
	local ground = DressingPlanner.groundHeight(DressingConfig, biome, x)
	local y = ground + DecalsConfig.CARD_LIFT + entry.layer * DecalsConfig.LAYER_STEP + CARD_THICKNESS / 2
	local p = card("Mark_" .. entry.key, Vector3.new(width, CARD_THICKNESS, depth), CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0), parent)
	decal(id, Enum.NormalId.Top, rng:NextNumber(entry.transparency[1], entry.transparency[2]), entry.layer, p)
	if index > DecalsConfig.BASE_CARDS then
		CollectionService:AddTag(p, DressingConfig.TAGS.detail)
	end
	return true
end

-- A card in front of a thin, axis-aligned wall part, on the face that looks at the road.
local function placeWall(entry: DecalsConfig.Entry, id: number, wall: BasePart, rng: Random, index: number, parent: Instance)
	local width, height = cardSize(entry, rng)
	width = math.min(width, wall.Size.Z - 0.4)
	height = math.min(height, wall.Size.Y - 0.4)
	if width <= 0.5 or height <= 0.5 then
		return
	end
	local sign = if wall.Position.X >= 0 then 1 else -1
	local zOffset = rng:NextNumber(-(wall.Size.Z - width) / 2, (wall.Size.Z - width) / 2)
	local yOffset = -wall.Size.Y / 2 + height / 2 + 0.2
	local cframe = wall.CFrame * CFrame.new(-sign * (wall.Size.X / 2 + DecalsConfig.WALL_GAP), yOffset, zOffset)
	local p = card("Mark_" .. entry.key, Vector3.new(CARD_THICKNESS, height, width), cframe, parent)
	decal(id, if sign > 0 then Enum.NormalId.Left else Enum.NormalId.Right, rng:NextNumber(entry.transparency[1], entry.transparency[2]), entry.layer, p)
	if index > DecalsConfig.BASE_CARDS then
		CollectionService:AddTag(p, DressingConfig.TAGS.detail)
	end
end

local function placeFloor(entry: DecalsConfig.Entry, id: number, floor: BasePart, rng: Random)
	local tile = entry.tile
	if not tile then
		return
	end
	local texture = Instance.new("Texture")
	texture.Name = "Mark_" .. entry.key
	texture.Texture = assetUrl(id)
	texture.Face = Enum.NormalId.Top
	texture.StudsPerTileU = tile[1]
	texture.StudsPerTileV = tile[2]
	texture.OffsetStudsV = rng:NextNumber(0, tile[2])
	texture.Transparency = rng:NextNumber(entry.transparency[1], entry.transparency[2])
	texture.ZIndex = entry.layer
	texture.Parent = floor
end

-- Wall parts of the chunk that may take a card, in a fixed order so the rng stays in step.
local function wallCandidates(parent: Instance): { BasePart }
	local out: { BasePart } = {}
	for _, item in parent:GetDescendants() do
		if item:IsA("BasePart") and table.find(DecalsConfig.WALL_PARTS, item.Name) and item.Size.Y >= 2.5 and item.Size.Z >= 4 then
			table.insert(out, item)
		end
	end
	return out
end

-- Places the biome's marks in the chunk; returns the number placed.
function WorldDecals.dress(biome: string, rng: Random, floor: BasePart, halfWidth: number, halfLength: number, parent: Instance): number
	local placed = 0
	local walls: { BasePart }? = nil
	for _, entry in DecalsConfig.forBiome(biome) do
		local id = DecalsConfig.idOf(decalIds, entry.key)
		if id <= 0 then
			continue
		end
		local count = rng:NextInteger(entry.count[1], entry.count[2])
		for _ = 1, count do
			if entry.zone == "floor" then
				placeFloor(entry, id, floor, rng)
				placed += 1
			elseif entry.zone == "wall" then
				if not walls then
					walls = wallCandidates(parent)
				end
				local list = walls :: { BasePart }
				if #list == 0 then
					break
				end
				local wall = table.remove(list, rng:NextInteger(1, #list)) :: BasePart
				placeWall(entry, id, wall, rng, placed + 1, parent)
				placed += 1
			elseif placeGround(entry, id, biome, rng, halfWidth, halfLength, placed + 1, parent) then
				placed += 1
			end
		end
	end
	return placed
end

return WorldDecals
