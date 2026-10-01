--!strict

-- Pure tests for PrebuiltMapMath: the layout check, where a mesh goes (the map's origin
-- and turn), the collision hints, the missing-mesh list and the budget lines. Run from
-- the repository root with the standalone Luau CLI:  luau tests/cityimport/run.luau
-- The splitter itself is tested by python3 tests/cityimport/run.py.

local PrebuiltMapMath = require("../../src/shared/world/PrebuiltMapMath")
local PrebuiltMapsConfig = require("../../src/shared/config/PrebuiltMapsConfig")

local failures = 0

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		return
	end
	failures += 1
	print(string.format("  FAIL %s%s", name, if detail then " (" .. detail .. ")" else ""))
end

local function group(name: string, body: () -> ())
	local before = failures
	body()
	print(string.format("%s %s", if failures == before then "ok  " else "FAIL", name))
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

local M = PrebuiltMapMath

local function layout(): any
	return {
		map = "test_city",
		source = "city.glb",
		scale = 3.5714,
		cellSize = 64,
		maxTris = 18000,
		cells = {
			{
				name = "c_p000_p000",
				position = { 32, 2, 32 },
				size = { 64, 4, 64 },
				triangles = 5000,
				textures = 2,
				meshes = {
					{ name = "c_p000_p000_000", offset = { 0, -1, 0 }, size = { 64, 0.05, 64 }, triangles = 2000, collision = "box" },
					{ name = "c_p000_p000_001", offset = { 10, 1, -5 }, size = { 20, 20, 20 }, triangles = 3000, collision = "hull" },
				},
			},
			{
				name = "c_m001_p000",
				position = { -32, 0, 32 },
				size = { 64, 2, 64 },
				triangles = 200000,
				textures = 20,
				meshes = {
					{ name = "c_m001_p000_000", offset = { 0, 0, 0 }, size = { 3, 2, 3 }, triangles = 200000, collision = "none" },
				},
			},
		},
	}
end

group("check", function()
	check("good layout", #M.check(layout()) == 0, table.concat(M.check(layout()), "; "))
	check("not a table", #M.check(nil) == 1)
	local noCells = layout()
	noCells.cells = nil
	check("no cells", #M.check(noCells) == 1)
	local twice = layout()
	twice.cells[2].name = "c_p000_p000"
	check("listed twice", #M.check(twice) == 1)
	local badHint = layout()
	badHint.cells[1].meshes[1].collision = "mesh"
	check("unknown hint", #M.check(badHint) == 1)
	local badSize = layout()
	badSize.cells[1].meshes[2].size = { 1, 0, 1 }
	check("zero size", #M.check(badSize) == 1)
	local short = layout()
	short.cells[1].position = { 1, 2 }
	check("two-number position", #M.check(short) == 1)
	local empty = layout()
	empty.cells[2].meshes = {}
	check("no meshes", #M.check(empty) == 1)
end)

group("placement", function()
	local cells = layout().cells
	local centre = M.meshCentre({ 0, 0, 0 }, 0, cells[1], cells[1].meshes[2])
	check("no turn", near(centre[1], 42) and near(centre[2], 3) and near(centre[3], 27))
	local moved = M.meshCentre({ 100, 5, -50 }, 0, cells[1], cells[1].meshes[2])
	check("origin", near(moved[1], 142) and near(moved[2], 8) and near(moved[3], -23))
	-- CFrame.Angles(0, 90 degrees, 0) takes +X to -Z and +Z to +X
	local turned = M.place({ 0, 0, 0 }, 90, { 1, 0, 0 })
	check("90 degrees: +X to -Z", near(turned[1], 0) and near(turned[3], -1), `{turned[1]} {turned[3]}`)
	local turnedZ = M.place({ 0, 0, 0 }, 90, { 0, 0, 1 })
	check("90 degrees: +Z to +X", near(turnedZ[1], 1) and near(turnedZ[3], 0))
	local half = M.place({ 10, 0, 10 }, 180, { 3, 1, 4 })
	check("180 degrees", near(half[1], 7) and near(half[2], 1) and near(half[3], 6))
end)

group("collision", function()
	check("none", not M.collision("none").canCollide and not M.collision("none").canQuery and M.collision("none").fidelity == nil)
	check("box", M.collision("box").canCollide and M.collision("box").fidelity == "Box")
	check("hull", M.collision("hull").canCollide and M.collision("hull").fidelity == "Hull")
	check("unknown falls back to hull", M.collision("weird").fidelity == "Hull")
	check("nothing touches", not M.collision("box").canTouch and not M.collision("hull").canTouch)
end)

group("missing meshes", function()
	local cell = layout().cells[1]
	local missing = M.missing(cell, { c_p000_p000_000 = true })
	check("one missing", #missing == 1 and missing[1] == "c_p000_p000_001")
	check("none missing", #M.missing(cell, { c_p000_p000_000 = true, c_p000_p000_001 = true }) == 0)
end)

group("budget lines", function()
	local data = layout()
	local budgets = PrebuiltMapsConfig.budgets
	local light = M.cellReport(data.cells[1])
	check("cell report", light.meshes == 2 and light.triangles == 5000 and light.textures == 2)
	local line = M.format("test_city c_p000_p000", light, budgets.desktop, budgets.mobile)
	check("line shape", string.find(line, "[Prebuilt test_city c_p000_p000] meshes 2/", 1, true) == 1, line)
	check("light cell within budget", string.find(line, "over", 1, true) == nil, line)
	local heavy = M.format("test_city c_m001_p000", M.cellReport(data.cells[2]), budgets.desktop, budgets.mobile)
	check("heavy cell over desktop", string.find(heavy, "over desktop: triangles, textures", 1, true) ~= nil, heavy)
	check("heavy cell over mobile", string.find(heavy, "over mobile: triangles, textures", 1, true) ~= nil, heavy)
	check("thousands", string.find(heavy, "tris 200k/120k (m 50k)", 1, true) ~= nil, heavy)
	local total = M.mapReport(data)
	check("map report", total.meshes == 3 and total.triangles == 205000 and total.textures == 22)
end)

group("config", function()
	check("no map listed by default", #PrebuiltMapsConfig.maps == 0)
	check("mobile tighter than desktop", PrebuiltMapsConfig.budgets.mobile.triangles < PrebuiltMapsConfig.budgets.desktop.triangles)
	check("concurrency positive", PrebuiltMapsConfig.LOAD_CONCURRENCY >= 1)
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all prebuilt map tests passed")
