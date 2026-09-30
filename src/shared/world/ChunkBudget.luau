--!strict

-- Per-chunk cost estimate against the desktop and mobile budgets. Pure Luau with no
-- requires: the counts and the triangle tables (DressingConfig) come in as arguments,
-- so the server counter (ChunkBudgetCounter) and the tests share the arithmetic.

export type Budget = {
	parts: number,
	triangles: number,
	instances: number,
	decals: number,
	lights: number,
	shadows: number,
}

export type Config = {
	triangles: { [string]: number },
	TRIANGLES_DEFAULT: number,
	primitiveTriangles: { [string]: number },
}

export type Counts = {
	parts: number,
	-- mesh instances per mesh name
	meshes: { [string]: number },
	-- primitive parts per shape name (Block, Wedge, Cylinder, Ball)
	primitives: { [string]: number },
	instances: number,
	decals: number,
	lights: number,
	shadows: number,
}

export type Report = Budget

local ChunkBudget = {}

local MEASURES = { "parts", "triangles", "instances", "decals", "lights", "shadows" }

function ChunkBudget.newCounts(): Counts
	return { parts = 0, meshes = {}, primitives = {}, instances = 0, decals = 0, lights = 0, shadows = 0 }
end

function ChunkBudget.triangles(config: Config, counts: Counts): number
	local total = 0
	for name, count in counts.meshes do
		total += (config.triangles[name] or config.TRIANGLES_DEFAULT) * count
	end
	for shape, count in counts.primitives do
		total += (config.primitiveTriangles[shape] or config.primitiveTriangles.Block) * count
	end
	return total
end

function ChunkBudget.report(config: Config, counts: Counts): Report
	return {
		parts = counts.parts,
		triangles = ChunkBudget.triangles(config, counts),
		instances = counts.instances,
		decals = counts.decals,
		lights = counts.lights,
		shadows = counts.shadows,
	}
end

-- Names of the measures over the budget, in the table's order.
function ChunkBudget.over(report: Report, budget: Budget): { string }
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

function ChunkBudget.format(biome: string, report: Report, desktop: Budget, mobile: Budget): string
	local line = string.format(
		"[Chunk %s] parts %d/%d (m %d) tris %s/%s (m %s) inst %d/%d (m %d) decals %d lights %d shadows %d",
		biome,
		report.parts,
		desktop.parts,
		mobile.parts,
		thousands(report.triangles),
		thousands(desktop.triangles),
		thousands(mobile.triangles),
		report.instances,
		desktop.instances,
		mobile.instances,
		report.decals,
		report.lights,
		report.shadows
	)
	local overDesktop = ChunkBudget.over(report, desktop)
	local overMobile = ChunkBudget.over(report, mobile)
	if #overDesktop > 0 then
		line ..= " | over desktop: " .. table.concat(overDesktop, ", ")
	end
	if #overMobile > 0 then
		line ..= " | over mobile: " .. table.concat(overMobile, ", ")
	end
	return line
end

return ChunkBudget
