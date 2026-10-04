--!strict

-- Pure helpers for PrebuiltMaps (no services, no engine types), tested by
-- `luau tests/cityimport/run.luau`: checking a generated layout module, where each mesh
-- goes, what its collision hint means, and the budget line per cell and per map.

export type Mesh = {
	name: string,
	offset: { number },
	size: { number },
	triangles: number,
	collision: string,
}

export type Cell = {
	name: string,
	position: { number },
	size: { number },
	triangles: number,
	textures: number,
	meshes: { Mesh },
}

export type Layout = {
	map: string,
	source: string?,
	scale: number,
	cellSize: number,
	maxTris: number,
	cells: { Cell },
}

export type Collision = {
	canCollide: boolean,
	canQuery: boolean,
	canTouch: boolean,
	-- the CollisionFidelity item name, nil for none
	fidelity: string?,
}

export type Budget = {
	meshes: number,
	triangles: number,
	textures: number,
}

export type Report = Budget

local PrebuiltMapMath = {}

PrebuiltMapMath.HINTS = {
	none = { canCollide = false, canQuery = false, canTouch = false, fidelity = nil },
	box = { canCollide = true, canQuery = true, canTouch = false, fidelity = "Box" },
	hull = { canCollide = true, canQuery = true, canTouch = false, fidelity = "Hull" },
	-- ground, roads and terrain (meshes wider than a cell): Roblox's own decomposition
	-- when near-planar, the precise one where there is relief
	default = { canCollide = true, canQuery = true, canTouch = false, fidelity = "Default" },
	precise = { canCollide = true, canQuery = true, canTouch = false, fidelity = "PreciseConvexDecomposition" },
} :: { [string]: Collision }

local function isVector(value: any): boolean
	return type(value) == "table" and #value == 3 and type(value[1]) == "number" and type(value[2]) == "number" and type(value[3]) == "number"
end

-- Every problem with a loaded layout module, as lines; empty when it is usable.
function PrebuiltMapMath.check(layout: any): { string }
	local problems: { string } = {}
	if type(layout) ~= "table" then
		return { "the layout is not a table" }
	end
	if type(layout.map) ~= "string" or layout.map == "" then
		table.insert(problems, "no map name")
	end
	if type(layout.cells) ~= "table" then
		table.insert(problems, "no cells")
		return problems
	end
	local seen: { [string]: boolean } = {}
	for index, entry in ipairs(layout.cells) do
		local cell = entry :: any
		local label = if type(cell) == "table" and type(cell.name) == "string" then cell.name else `cell {index}`
		if type(cell) ~= "table" or type(cell.name) ~= "string" then
			table.insert(problems, `{label}: no name`)
			continue
		end
		if seen[cell.name] then
			table.insert(problems, `{label}: listed twice`)
		end
		seen[cell.name] = true
		if not isVector(cell.position) or not isVector(cell.size) then
			table.insert(problems, `{label}: position and size must be three numbers`)
		end
		if type(cell.meshes) ~= "table" or #cell.meshes == 0 then
			table.insert(problems, `{label}: no meshes`)
			continue
		end
		for _, item in cell.meshes do
			local mesh = item :: any
			if type(mesh.name) ~= "string" or not isVector(mesh.offset) or not isVector(mesh.size) then
				table.insert(problems, `{label}: a mesh without name, offset or size`)
			elseif PrebuiltMapMath.HINTS[mesh.collision] == nil then
				table.insert(problems, `{mesh.name}: unknown collision hint {mesh.collision}`)
			elseif mesh.size[1] <= 0 or mesh.size[2] <= 0 or mesh.size[3] <= 0 then
				table.insert(problems, `{mesh.name}: size must be positive`)
			end
		end
	end
	return problems
end

-- A point of the scene (studs) placed by the map entry: turned by yaw degrees about Y
-- (the same turn as CFrame.Angles(0, yaw, 0)), then moved to the origin.
function PrebuiltMapMath.place(origin: { number }, yawDegrees: number, point: { number }): { number }
	local yaw = math.rad(yawDegrees)
	local c, s = math.cos(yaw), math.sin(yaw)
	local x, y, z = point[1], point[2], point[3]
	return { origin[1] + x * c + z * s, origin[2] + y, origin[3] - x * s + z * c }
end

-- Where a mesh's centre goes: the cell's position plus the mesh's offset, placed.
function PrebuiltMapMath.meshCentre(origin: { number }, yawDegrees: number, cell: Cell, mesh: Mesh): { number }
	local point = {
		cell.position[1] + mesh.offset[1],
		cell.position[2] + mesh.offset[2],
		cell.position[3] + mesh.offset[3],
	}
	return PrebuiltMapMath.place(origin, yawDegrees, point)
end

function PrebuiltMapMath.collision(hint: string): Collision
	return PrebuiltMapMath.HINTS[hint] or PrebuiltMapMath.HINTS.hull
end

-- Names in the cell's layout that the loaded asset does not have.
function PrebuiltMapMath.missing(cell: Cell, found: { [string]: boolean }): { string }
	local out = {}
	for _, mesh in cell.meshes do
		if not found[mesh.name] then
			table.insert(out, mesh.name)
		end
	end
	return out
end

function PrebuiltMapMath.cellReport(cell: Cell): Report
	return { meshes = #cell.meshes, triangles = cell.triangles, textures = cell.textures }
end

function PrebuiltMapMath.mapReport(layout: Layout): Report
	local report = { meshes = 0, triangles = 0, textures = 0 }
	for _, cell in layout.cells do
		report.meshes += #cell.meshes
		report.triangles += cell.triangles
		report.textures += cell.textures
	end
	return report
end

local MEASURES = { "meshes", "triangles", "textures" }

function PrebuiltMapMath.over(report: Report, budget: Budget): { string }
	local out = {}
	for _, measure in MEASURES do
		if (report :: any)[measure] > (budget :: any)[measure] then
			table.insert(out, measure)
		end
	end
	return out
end

local function thousands(value: number): string
	if value >= 1000 then
		return string.format("%dk", math.floor(value / 1000 + 0.5))
	end
	return tostring(value)
end

-- One line in the chunk reports' style: "[Prebuilt city c_p000_p000] meshes 12/60 (m 30)
-- tris 31k/120k (m 50k) textures 4/12 (m 6)", plus the measures over either budget.
function PrebuiltMapMath.format(label: string, report: Report, desktop: Budget, mobile: Budget): string
	local line = string.format(
		"[Prebuilt %s] meshes %d/%d (m %d) tris %s/%s (m %s) textures %d/%d (m %d)",
		label,
		report.meshes,
		desktop.meshes,
		mobile.meshes,
		thousands(report.triangles),
		thousands(desktop.triangles),
		thousands(mobile.triangles),
		report.textures,
		desktop.textures,
		mobile.textures
	)
	local overDesktop = PrebuiltMapMath.over(report, desktop)
	local overMobile = PrebuiltMapMath.over(report, mobile)
	if #overDesktop > 0 then
		line ..= " | over desktop: " .. table.concat(overDesktop, ", ")
	end
	if #overMobile > 0 then
		line ..= " | over mobile: " .. table.concat(overMobile, ", ")
	end
	return line
end

return PrebuiltMapMath
