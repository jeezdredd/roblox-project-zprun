--!strict

-- Test yard station for the environment pass: one pure chunk per biome, side by side
-- south of the yard floor, built with the wiki's measurement seed so the counter lines
-- are comparable. Fixed screenshot cameras per biome (docs/world/environment.md,
-- section 6) are selected from Studio by setting the Workspace attribute
-- BiomeStripShot to "<Biome>/<Shot>" (for example "City/A"); the station then writes
-- DevCameraCFrame, which CameraController honours, and DevLightingPreset, which
-- LightingDirector honours. An empty string gives both back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DevConfig = require(ReplicatedStorage.Shared.config.DevConfig)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LightingConfig = require(ReplicatedStorage.Shared.config.LightingConfig)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local ChunkFactory = require(script.Parent.ChunkFactory)
local WorldMeshes = require(script.Parent.WorldMeshes)

local SandboxBiomeStrip = {}

export type Shot = {
	id: string,
	-- relative to the chunk centre (floor top at y = 0.5)
	eye: Vector3,
	look: Vector3,
	night: boolean?,
	what: string,
}

-- south of the yard floor, which ends at z = -400 from the origin
local STRIP_OFFSET = Vector3.new(0, 0, -560)
local CHUNK_GAP = 20
-- the wiki's measurement setup (Performance.md): seed 1234, obstacle count 3
local SEED = 1234
local OBSTACLE_COUNT = 3
local SHOT_ATTRIBUTE = "BiomeStripShot"
local CAMERA_ATTRIBUTE = "DevCameraCFrame"
local PRESET_ATTRIBUTE = "DevLightingPreset"

SandboxBiomeStrip.shots = {
	{ id = "A", eye = Vector3.new(0, 5, 60), look = Vector3.new(0, 3, -60), what = "runner: lanes clear, clusters read as one thing each, nothing floats at the edge" },
	{ id = "B", eye = Vector3.new(-22, 3.5, 30), look = Vector3.new(40, 4, -20), what = "kerb: edge row and cluster do not intersect, shadows only on edge and apron props" },
	{ id = "C", eye = Vector3.new(0, 42, 120), look = Vector3.new(0, 8, -40), what = "wide: middle band fits its slots, far band is silhouette, the strip's far end is in fog" },
	{ id = "D", eye = Vector3.new(0, 5, 60), look = Vector3.new(0, 3, -60), night = true, what = "night: one warm accent, fog not black, lamp halos stay round" },
	{ id = "E", eye = Vector3.new(8, 2.2, 10), look = Vector3.new(8, 0.5, -6), what = "feet: no texel blur, variant seams, floor texture tiling" },
} :: { Shot }

local origin: Vector3 = DevConfig.SANDBOX.origin
local built = false

local function chunkCentre(index: number): Vector3
	return origin + STRIP_OFFSET + Vector3.new((index - 3) * (GameConstants.LANE_WIDTH + CHUNK_GAP), 0, 0)
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
	gui.Size = UDim2.fromOffset(520, 90)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 400
	gui.Parent = anchor
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.TextScaled = true
	textLabel.TextWrapped = true
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextColor3 = Color3.fromRGB(255, 200, 90)
	textLabel.TextStrokeTransparency = 0.4
	textLabel.Text = text
	textLabel.Parent = gui
end

local function build()
	if built then
		return
	end
	built = true
	WorldMeshes.waitReady(10)
	local folder = Instance.new("Folder")
	folder.Name = "SandboxBiomeStrip"
	folder.Parent = Workspace
	for index, id in LocationsConfig.order do
		local location = LocationsConfig.get(id)
		if not location then
			continue
		end
		local model = ChunkFactory.build(location, nil, Random.new(SEED), OBSTACLE_COUNT)
		model.Name = "Strip_" .. id
		local centre = chunkCentre(index)
		model:PivotTo(CFrame.new(centre))
		model.Parent = folder
		local line = model:GetAttribute("BudgetLine")
		label(id .. "\n" .. (if typeof(line) == "string" then line else ""), centre + Vector3.new(0, 26, GameConstants.CHUNK_LENGTH / 2 + 6), folder)
	end
end

-- Camera and preset for a shot of a biome, or nil for an unknown pair.
function SandboxBiomeStrip.shotFor(biome: string, shotId: string): (CFrame?, string?)
	local index = table.find(LocationsConfig.order, biome)
	if not index then
		return nil, nil
	end
	for _, shot in SandboxBiomeStrip.shots do
		if shot.id == shotId then
			local centre = chunkCentre(index)
			local cframe = CFrame.lookAt(centre + shot.eye, centre + shot.look)
			return cframe, if shot.night then LightingConfig.nightFor(biome) else biome
		end
	end
	return nil, nil
end

local function applyShot()
	local value = Workspace:GetAttribute(SHOT_ATTRIBUTE)
	local biome, shotId = nil, nil
	if typeof(value) == "string" then
		biome, shotId = string.match(value, "^(%a+)/(%a)$")
	end
	local cframe, preset = nil, nil
	if biome and shotId then
		cframe, preset = SandboxBiomeStrip.shotFor(biome, shotId)
	end
	Workspace:SetAttribute(CAMERA_ATTRIBUTE, cframe)
	Workspace:SetAttribute(PRESET_ATTRIBUTE, preset)
end

function SandboxBiomeStrip.init()
	if not DevConfig.SANDBOX.enabled then
		return
	end
	task.spawn(build)
	Workspace:GetAttributeChangedSignal(SHOT_ATTRIBUTE):Connect(applyShot)
end

return SandboxBiomeStrip
