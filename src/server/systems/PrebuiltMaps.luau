--!strict

-- Places the prebuilt maps (docs/environment/prebuilt-maps.md): every enabled entry in
-- PrebuiltMapsConfig.maps reads its generated layout module (src/server/prebuilt/<map>.luau,
-- server only,
-- from tools/city_import/split_scene.py), loads each cell's Model asset
-- (AssetIds.model.maps.<map>.<cell>) through InsertService and puts its meshes where the
-- layout says, under Workspace.PrebuiltMaps/<map>/<cell>. One Model per cell, streamed
-- atomically, so a cell arrives or leaves as a whole. Collision follows the layout's hint
-- (none, box, hull). In Studio each cell prints a budget line like the chunk reports and
-- keeps it as the BudgetLine attribute. A missing layout, id or mesh is a warning, never
-- an error: the rest of the map still builds.

local AssetService = game:GetService("AssetService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local PrebuiltMapsConfig = require(ReplicatedStorage.Shared.config.PrebuiltMapsConfig)
local PrebuiltMapMath = require(ReplicatedStorage.Shared.world.PrebuiltMapMath)

local PrebuiltMaps = {}

local LINE_ATTRIBUTE = "BudgetLine"

local function rootFolder(): Folder
	local existing = Workspace:FindFirstChild(PrebuiltMapsConfig.FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = PrebuiltMapsConfig.FOLDER
	folder.Parent = Workspace
	return folder
end

local function loadLayout(map: string): PrebuiltMapMath.Layout?
	local folder = script.Parent.Parent:FindFirstChild("prebuilt")
	local module = folder and folder:FindFirstChild(map)
	if not (module and module:IsA("ModuleScript")) then
		warn(`[PrebuiltMaps] {map}: no layout module src/server/prebuilt/{map}.luau, map skipped`)
		return nil
	end
	local ok, layout = pcall(require, module)
	if not ok then
		warn(`[PrebuiltMaps] {map}: layout did not load ({layout}), map skipped`)
		return nil
	end
	local problems = PrebuiltMapMath.check(layout)
	if #problems > 0 then
		warn(`[PrebuiltMaps] {map}: layout unusable: {table.concat(problems, "; ")}`)
		return nil
	end
	return layout :: PrebuiltMapMath.Layout
end

local function cellIds(map: string): { [string]: any }
	local model = (AssetIds :: any).model
	local maps = model and model.maps
	return (maps and maps[map]) or {}
end

local function vector(values: { number }): Vector3
	return Vector3.new(values[1], values[2], values[3])
end

-- The collision the hint asks for. A Box or Hull fidelity can only come from a fresh
-- mesh build (CollisionFidelity is not writable at run time), so the part takes the
-- geometry of a MeshPart built with it; the part keeps its size and SurfaceAppearance.
local function applyCollision(part: MeshPart, hint: string)
	local collision = PrebuiltMapMath.collision(hint)
	part.CanCollide = collision.canCollide
	part.CanQuery = collision.canQuery
	part.CanTouch = collision.canTouch
	local fidelity = collision.fidelity
	if not fidelity or part.CollisionFidelity.Name == fidelity then
		return
	end
	local ok, fresh = pcall(function()
		return AssetService:CreateMeshPartAsync(part.MeshContent, {
			CollisionFidelity = (Enum.CollisionFidelity :: any)[fidelity],
			RenderFidelity = part.RenderFidelity,
		})
	end)
	if not ok or not fresh then
		warn(`[PrebuiltMaps] {part.Name} kept its collision: {fresh}`)
		return
	end
	local size = part.Size
	part:ApplyMesh(fresh)
	part.Size = size
	fresh:Destroy()
end

local function report(holder: Instance, label: string, result: PrebuiltMapMath.Report, budgets: { [string]: PrebuiltMapMath.Budget })
	if not RunService:IsStudio() then
		return
	end
	local line = PrebuiltMapMath.format(label, result, budgets.desktop, budgets.mobile)
	holder:SetAttribute(LINE_ATTRIBUTE, line)
	print(line)
end

-- One cell; runs inside a worker's pcall, so an error here only loses this cell.
local function buildCell(entry: PrebuiltMapsConfig.MapEntry, layout: PrebuiltMapMath.Layout, cell: PrebuiltMapMath.Cell, assetId: number, parent: Instance)
	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not container then
		warn(`[PrebuiltMaps] {layout.map}/{cell.name} ({assetId}) failed to load: {container}`)
		return
	end

	local parts: { [string]: MeshPart } = {}
	local found: { [string]: boolean } = {}
	for _, item in (container :: Instance):GetDescendants() do
		if item:IsA("MeshPart") and parts[item.Name] == nil then
			parts[item.Name] = item
			found[item.Name] = true
		end
	end
	local missing = PrebuiltMapMath.missing(cell, found)
	if #missing > 0 then
		warn(`[PrebuiltMaps] {layout.map}/{cell.name}: {#missing} meshes not in the asset ({missing[1]}, ...)`)
	end

	local model = Instance.new("Model")
	model.Name = cell.name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local turn = CFrame.Angles(0, math.rad(entry.yaw), 0) * CFrame.Angles(0, math.rad(PrebuiltMapsConfig.MESH_TURN_DEGREES), 0)
	for _, mesh in cell.meshes do
		local part = parts[mesh.name]
		if not part then
			continue
		end
		local centre = PrebuiltMapMath.meshCentre(entry.origin, entry.yaw, cell, mesh)
		part.Anchored = true
		part.Size = vector(mesh.size)
		part.CFrame = CFrame.new(vector(centre)) * turn
		part.CastShadow = math.max(mesh.size[1], mesh.size[2], mesh.size[3]) >= PrebuiltMapsConfig.SHADOW_MIN_SIZE
		applyCollision(part, mesh.collision)
		part.Parent = model
	end
	model.WorldPivot = CFrame.new(vector(PrebuiltMapMath.place(entry.origin, entry.yaw, cell.position))) * CFrame.Angles(0, math.rad(entry.yaw), 0)
	model.Parent = parent
	;(container :: Instance):Destroy()
	report(model, `{layout.map} {cell.name}`, PrebuiltMapMath.cellReport(cell), PrebuiltMapsConfig.budgets)
end

local function buildMap(entry: PrebuiltMapsConfig.MapEntry)
	local layout = loadLayout(entry.map)
	if not layout then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = entry.map
	folder.Parent = rootFolder()
	local ids = cellIds(entry.map)
	local jobs: { { cell: PrebuiltMapMath.Cell, assetId: number } } = {}
	for _, cell in layout.cells do
		local assetId = ids[cell.name]
		if typeof(assetId) == "number" and assetId > 0 then
			table.insert(jobs, { cell = cell, assetId = assetId })
		end
	end
	local skipped = #layout.cells - #jobs
	if skipped > 0 then
		warn(`[PrebuiltMaps] {entry.map}: {skipped} of {#layout.cells} cells have no asset id yet (model/maps/{entry.map}/)`)
	end

	-- a fixed pool of workers takes the cells in order; each cell runs in pcall, so a
	-- failure never holds a slot or stops the others
	local nextJob = 1
	local running = 0
	local function worker()
		while nextJob <= #jobs do
			local job = jobs[nextJob]
			nextJob += 1
			local ok, err = pcall(buildCell, entry, layout, job.cell, job.assetId, folder)
			if not ok then
				warn(`[PrebuiltMaps] {entry.map}/{job.cell.name} failed: {err}`)
			end
		end
		running -= 1
	end
	local workers = math.min(math.max(PrebuiltMapsConfig.LOAD_CONCURRENCY, 1), #jobs)
	running = workers
	for _ = 1, workers do
		task.spawn(worker)
	end
	while running > 0 do
		task.wait(0.2)
	end
	report(folder, entry.map, PrebuiltMapMath.mapReport(layout), PrebuiltMapsConfig.mapBudgets)
end

function PrebuiltMaps.init()
	if not PrebuiltMapsConfig.ENABLED then
		return
	end
	for _, entry in PrebuiltMapsConfig.maps do
		if entry.enabled then
			task.spawn(buildMap, entry)
		end
	end
end

return PrebuiltMaps
