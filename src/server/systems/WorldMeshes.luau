--!strict

-- Mesh templates for world dressing. At server start every entry in WorldMeshConfig
-- is turned into a MeshPart template with AssetService:CreateMeshPartAsync (MeshId is
-- not writable from scripts, so templates are the only way to spawn meshes at run
-- time). Builders call place() and get nil back while a mesh is missing or still
-- loading; they then fall back to their primitive shapes, so a failed load never
-- leaves a hole in the world.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldMeshConfig = require(ReplicatedStorage.Shared.config.WorldMeshConfig)

local WorldMeshes = {}

export type PlaceOptions = {
	collide: boolean?,
	query: boolean?,
	shadow: boolean?,
	-- per-axis multipliers applied after the height scale (x and z are the footprint)
	stretch: Vector3?,
	-- studs to sink the mesh into the ground so it never floats on its lowest vertex
	sink: number?,
}

local templates: { [string]: MeshPart } = {}
-- studs per mesh unit at the entry's real size (WorldMeshConfig studsPerUnit)
local units: { [string]: number } = {}
local loading = false

local function load(name: string, entry: WorldMeshConfig.MeshEntry)
	if entry.mesh <= 0 then
		return
	end
	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromUri("rbxassetid://" .. tostring(entry.mesh)), {
			CollisionFidelity = entry.collision,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	if not ok or not result then
		warn(("[WorldMeshes] %s (%d) failed to load: %s"):format(name, entry.mesh, tostring(result)))
		return
	end
	local part = result :: MeshPart
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = true
	local surfaces = entry.surface and ReplicatedStorage:FindFirstChild("PropSurfaces")
	local surface = surfaces and surfaces:FindFirstChild(entry.surface :: string)
	if surface and surface:IsA("SurfaceAppearance") then
		surface:Clone().Parent = part
	elseif entry.texture > 0 then
		part.TextureID = "rbxassetid://" .. tostring(entry.texture)
	end
	templates[name] = part
	units[name] = entry.studsPerUnit or 1
end

-- Loads every template, all requests in parallel. Blocks until every request has
-- finished, so call it from a spawned thread at server start (init does), or
-- directly in an Edit preview.
local ready = false
function WorldMeshes.loadAll()
	if loading then
		return
	end
	loading = true
	if not WorldMeshConfig.ENABLED then
		ready = true
		return
	end
	local pending = 0
	local current = coroutine.running()
	for name, entry in WorldMeshConfig.meshes do
		if not templates[name] then
			pending += 1
			task.spawn(function()
				load(name, entry)
				pending -= 1
				if pending == 0 and coroutine.status(current) == "suspended" then
					task.spawn(current)
				end
			end)
		end
	end
	if pending > 0 then
		coroutine.yield()
	end
	ready = true
end

-- Waits for loadAll to finish, at most `timeout` seconds. The first run after a
-- server start calls this so its opening chunks are not built from primitives.
function WorldMeshes.waitReady(timeout: number)
	local deadline = os.clock() + timeout
	while not ready and os.clock() < deadline do
		task.wait(0.1)
	end
end

function WorldMeshes.isLoaded(name: string): boolean
	return templates[name] ~= nil
end

-- One loaded member of a group, or nil when none of them loaded.
function WorldMeshes.pick(group: string, rng: Random): string?
	local members = WorldMeshConfig.groups[group]
	if not members then
		return nil
	end
	local loaded = {}
	for _, name in members do
		if templates[name] then
			table.insert(loaded, name)
		end
	end
	if #loaded == 0 then
		return nil
	end
	return loaded[rng:NextInteger(1, #loaded)]
end

-- Places a mesh standing on `base` (its position is the ground point under the
-- mesh centre, its rotation is the mesh yaw), scaled uniformly so it is `height`
-- studs tall. Returns nil when the template is not available.
function WorldMeshes.place(name: string, base: CFrame, height: number, parent: Instance, options: PlaceOptions?): MeshPart?
	local template = templates[name]
	if not template then
		return nil
	end
	local opts: PlaceOptions = options or {}
	local native = template.Size
	local scale = height / native.Y
	local stretch = opts.stretch or Vector3.one
	local size = Vector3.new(native.X * scale * stretch.X, height * stretch.Y, native.Z * scale * stretch.Z)
	local part = template:Clone()
	part.Size = size
	part.CFrame = base * CFrame.new(0, size.Y / 2 - (opts.sink or 0.15), 0)
	part.CanCollide = opts.collide == true
	part.CanQuery = opts.query == true or opts.collide == true
	part.CastShadow = opts.shadow ~= false
	part.Parent = parent
	return part
end

function WorldMeshes.nativeSize(name: string): Vector3?
	local template = templates[name]
	return if template then template.Size else nil
end

-- Places a mesh scaled so its footprint length (z) is `length` studs, keeping its
-- proportions. Used for vehicles, whose size is set by the lane layout.
function WorldMeshes.placeByLength(name: string, base: CFrame, length: number, parent: Instance, options: PlaceOptions?): MeshPart?
	local native = WorldMeshes.nativeSize(name)
	if not native then
		return nil
	end
	return WorldMeshes.place(name, base, length * native.Y / native.Z, parent, options)
end

-- Places a mesh at its real size (mesh units times the entry's studsPerUnit), for the
-- props modelled in metres. `scale` multiplies that (default 1).
function WorldMeshes.placeNatural(name: string, base: CFrame, parent: Instance, options: PlaceOptions?, scale: number?): MeshPart?
	local native = WorldMeshes.nativeSize(name)
	if not native then
		return nil
	end
	return WorldMeshes.place(name, base, native.Y * (units[name] or 1) * (scale or 1), parent, options)
end

-- Real size in studs of a loaded mesh (see placeNatural).
function WorldMeshes.naturalSize(name: string): Vector3?
	local native = WorldMeshes.nativeSize(name)
	return if native then native * (units[name] or 1) else nil
end

-- Picks from a group and places in one call.
function WorldMeshes.placeFrom(group: string, rng: Random, base: CFrame, height: number, parent: Instance, options: PlaceOptions?): MeshPart?
	local name = WorldMeshes.pick(group, rng)
	if not name then
		return nil
	end
	return WorldMeshes.place(name, base, height, parent, options)
end

function WorldMeshes.init()
	task.spawn(WorldMeshes.loadAll)
end

return WorldMeshes
