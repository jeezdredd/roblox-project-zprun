--!strict

-- Test yard station for map segments (wiki: Map Segments): every map transition the
-- fork graph allows, one row each, laid out as a run would build it: a plain chunk of
-- the old map's sub-location, the MAP_TRANSITION_CHUNKS blended chunks, a plain chunk of
-- the new map's. Built on demand (it is large): set the Workspace attribute
-- MapStripPair to "City>Forest" for one row or "all" for every pair; MapStripShot set to
-- a pair puts the Studio camera at the row's start looking down it (DevCameraCFrame) in
-- the old map's lighting (DevLightingPreset). An empty string gives both back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DevConfig = require(ReplicatedStorage.Shared.config.DevConfig)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local MapsConfig = require(ReplicatedStorage.Shared.config.MapsConfig)
local MapMath = require(ReplicatedStorage.Shared.world.MapMath)
local ChunkFactory = require(script.Parent.ChunkFactory)
local WorldMeshes = require(script.Parent.WorldMeshes)

local SandboxMapStrip = {}

export type Pair = { from: string, to: string }

-- south of the biome strip (SandboxBiomeStrip sits at z = -560 from the yard origin)
local STRIP_OFFSET = Vector3.new(0, 0, -1400)
-- one row's width: lane, barriers and both aprons, with a gap
local ROW_SPACING = GameConstants.LANE_WIDTH + 2 * GameConstants.APRON_WIDTH + 40
local SEED = 1234
local OBSTACLE_COUNT = 3
local PAIR_ATTRIBUTE = "MapStripPair"
local SHOT_ATTRIBUTE = "MapStripShot"

local origin: Vector3 = DevConfig.SANDBOX.origin
local folder: Folder? = nil
local builtRows: { [string]: boolean } = {}

-- Every ordered transition the fork graph allows between enabled maps.
function SandboxMapStrip.pairs(): { Pair }
	local out: { Pair } = {}
	for _, id in MapsConfig.order do
		if MapsConfig.isValid(id) then
			for _, other in MapMath.enabledNeighbours(MapsConfig.maps :: any, id) do
				table.insert(out, { from = id, to = other })
			end
		end
	end
	return out
end

local function pairName(pair: Pair): string
	return pair.from .. ">" .. pair.to
end

local function rowStart(row: number): Vector3
	return origin + STRIP_OFFSET + Vector3.new((row - 1) * ROW_SPACING, 0, 0)
end

local function label(text: string, position: Vector3, parent: Instance)
	local anchor = Instance.new("Part")
	anchor.Name = "Label"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Parent = parent
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(420, 60)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 600
	gui.Parent = anchor
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextColor3 = Color3.fromRGB(255, 200, 90)
	textLabel.TextStrokeTransparency = 0.4
	textLabel.Text = text
	textLabel.Parent = gui
end

local function store(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "SandboxMapStrip"
	created.Parent = Workspace
	folder = created
	return created
end

local function buildRow(row: number, pair: Pair)
	local name = pairName(pair)
	if builtRows[name] then
		return
	end
	local fromMap = MapsConfig.get(pair.from)
	local toMap = MapsConfig.get(pair.to)
	local fromLocation = if fromMap then LocationsConfig.get(fromMap.locationIds[#fromMap.locationIds]) else nil
	local toLocation = if toMap then LocationsConfig.get(toMap.locationIds[1]) else nil
	if not (fromLocation and toLocation) then
		return
	end
	builtRows[name] = true
	local rowFolder = Instance.new("Model")
	rowFolder.Name = "Row_" .. pair.from .. "_" .. pair.to
	rowFolder.Parent = store()

	local n = MapsConfig.MAP_TRANSITION_CHUNKS
	local start = rowStart(row)
	local function place(model: Model, slot: number)
		local centre = start + GameConstants.RUN_DIRECTION * (slot * GameConstants.CHUNK_LENGTH + GameConstants.CHUNK_LENGTH / 2)
		model:PivotTo(CFrame.new(centre))
		model.Parent = rowFolder
	end
	place(ChunkFactory.build(fromLocation, nil, Random.new(SEED), OBSTACLE_COUNT), 0)
	for k = 0, n - 1 do
		local alpha = MapMath.transitionAlpha(k, n) :: number
		place(ChunkFactory.build(fromLocation, { next = toLocation, alpha = alpha }, Random.new(SEED + k + 1), OBSTACLE_COUNT), k + 1)
	end
	place(ChunkFactory.build(toLocation, nil, Random.new(SEED), OBSTACLE_COUNT), n + 1)
	label(`{pair.from} > {pair.to}\n{fromLocation.id} to {toLocation.id}`, start + Vector3.new(0, 30, 0), rowFolder)
end

local function build(which: string)
	WorldMeshes.waitReady(10)
	for row, pair in SandboxMapStrip.pairs() do
		if which == "all" or which == pairName(pair) then
			buildRow(row, pair)
		end
	end
end

-- Camera and preset for a row's shot, or nil for an unknown pair.
function SandboxMapStrip.shotFor(name: string): (CFrame?, string?)
	for row, pair in SandboxMapStrip.pairs() do
		if pairName(pair) == name then
			local start = rowStart(row)
			local eye = start - GameConstants.RUN_DIRECTION * 30 + Vector3.new(0, 6, 0)
			local look = start + GameConstants.RUN_DIRECTION * 200 + Vector3.new(0, 3, 0)
			local map = MapsConfig.get(pair.from)
			return CFrame.lookAt(eye, look), if map then map.lighting else nil
		end
	end
	return nil, nil
end

function SandboxMapStrip.init()
	if not DevConfig.SANDBOX.enabled then
		return
	end
	Workspace:GetAttributeChangedSignal(PAIR_ATTRIBUTE):Connect(function()
		local value = Workspace:GetAttribute(PAIR_ATTRIBUTE)
		if typeof(value) == "string" and value ~= "" then
			task.spawn(build, value)
		end
	end)
	Workspace:GetAttributeChangedSignal(SHOT_ATTRIBUTE):Connect(function()
		local value = Workspace:GetAttribute(SHOT_ATTRIBUTE)
		local cframe, preset = nil, nil
		if typeof(value) == "string" and value ~= "" then
			cframe, preset = SandboxMapStrip.shotFor(value)
		end
		Workspace:SetAttribute("DevCameraCFrame", cframe)
		Workspace:SetAttribute("DevLightingPreset", preset)
	end)
end

return SandboxMapStrip
