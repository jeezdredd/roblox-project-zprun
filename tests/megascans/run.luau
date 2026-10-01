--!strict

-- Pure tests for MaterialSets: reading the generated Megascans list (entries checked
-- field by field, bad ones dropped), merging it after the built-in sets, the stand-in
-- for a replaced set, and which set gets a base material's override. Run from the
-- repository root with the standalone Luau CLI:  luau tests/megascans/run.luau
-- The importer itself is tested by python3 tests/megascans/run.py.

local MaterialSets = require("../../src/shared/util/MaterialSets")

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

local M = MaterialSets

local function entry(overrides: { [string]: any }?): { [string]: any }
	local raw: { [string]: any } = {
		name = "TFZ_MS_AsphaltCracked",
		asset = "Cracked Asphalt",
		baseMaterial = "Asphalt",
		color = 101,
		normal = 102,
		roughness = 103,
		studsPerTile = 7.14,
		override = false,
		replaces = "TFZ_AsphaltCracked",
	}
	for key, value in overrides or {} do
		raw[key] = value
	end
	return raw
end

group("validate keeps a good entry", function()
	local ok, why = M.validate(entry())
	check("accepted", ok ~= nil, why)
	if ok then
		check("name", ok.name == "TFZ_MS_AsphaltCracked")
		check("ids", ok.color == 101 and ok.normal == 102 and ok.roughness == 103)
		check("no metalness", ok.metalness == nil)
		check("studs", ok.studsPerTile == 7.14)
		check("replaces", ok.replaces == "TFZ_AsphaltCracked")
	end
	local metal = M.validate(entry({ name = "TFZ_MS_Rust", baseMaterial = "CorrodedMetal", metalness = 104 }))
	check("metal accepted", metal ~= nil and metal.metalness == 104)
end)

group("validate drops bad entries", function()
	check("not a table", M.validate(5) == nil)
	check("prefix", M.validate(entry({ name = "TFZ_Asphalt" })) == nil)
	check("no base", M.validate(entry({ baseMaterial = "" })) == nil)
	check("zero id", M.validate(entry({ color = 0 })) == nil)
	check("fraction id", M.validate(entry({ normal = 1.5 })) == nil)
	check("string id", M.validate(entry({ roughness = "103" })) == nil)
	check("bad metalness", M.validate(entry({ metalness = 0 })) == nil)
	check("studs zero", M.validate(entry({ studsPerTile = 0 })) == nil)
	check("override type", M.validate(entry({ override = "yes" })) == nil)
	check("replaces type", M.validate(entry({ replaces = 3 })) == nil)
end)

group("readList", function()
	local entries, dropped = M.readList({ entry(), entry({ color = 0 }), entry(), entry({ name = "TFZ_MS_Grass" }) })
	check("two kept", #entries == 2, tostring(#entries))
	check("two dropped", #dropped == 2, tostring(#dropped))
	check("order kept", entries[1].name == "TFZ_MS_AsphaltCracked" and entries[2].name == "TFZ_MS_Grass")
	local none, why = M.readList(nil)
	check("missing list", #none == 0 and #why == 1)
	local empty, quiet = M.readList({})
	check("empty list", #empty == 0 and #quiet == 0)
end)

group("merge appends new names only", function()
	local base = { { name = "TFZ_Asphalt" }, { name = "TFZ_Metal" } }
	local merged = M.merge(base, { { name = "TFZ_MS_Asphalt" }, { name = "TFZ_Metal" } })
	check("three sets", #merged == 3, tostring(#merged))
	check("base first", merged[1].name == "TFZ_Asphalt" and merged[2].name == "TFZ_Metal")
	check("extra last", merged[3].name == "TFZ_MS_Asphalt")
	check("base untouched", #base == 2)
	check("nothing extra", #M.merge(base, {}) == 2)
end)

group("replacements and resolve", function()
	local sets = {
		{ name = "TFZ_AsphaltCracked", baseMaterial = "Asphalt" },
		{ name = "TFZ_MS_AsphaltCracked", baseMaterial = "Asphalt", replaces = "TFZ_AsphaltCracked" },
		{ name = "TFZ_MS_Other", baseMaterial = "Asphalt", replaces = "TFZ_AsphaltCracked" },
		{ name = "TFZ_MS_Self", baseMaterial = "Asphalt", replaces = "TFZ_MS_Self" },
	}
	local map = M.replacements(sets)
	check("first claim wins", map.TFZ_AsphaltCracked == "TFZ_MS_AsphaltCracked")
	check("no self replacement", map.TFZ_MS_Self == nil)
	check(
		"stand-in when registered",
		M.resolve("TFZ_AsphaltCracked", map, { TFZ_AsphaltCracked = true, TFZ_MS_AsphaltCracked = true })
			== "TFZ_MS_AsphaltCracked"
	)
	check(
		"original when the stand-in is missing",
		M.resolve("TFZ_AsphaltCracked", map, { TFZ_AsphaltCracked = true }) == "TFZ_AsphaltCracked"
	)
	check("unrelated name", M.resolve("TFZ_Sand", map, { TFZ_Sand = true }) == "TFZ_Sand")
end)

group("overrides", function()
	local sets = {
		{ name = "TFZ_Metal", baseMaterial = "Metal", override = true },
		{ name = "TFZ_Grass", baseMaterial = "Grass", override = true },
		{ name = "TFZ_Sand", baseMaterial = "Sand" },
		{ name = "TFZ_MS_Metal", baseMaterial = "Metal", override = true },
	}
	local all = M.overrides(sets, { TFZ_Metal = true, TFZ_Grass = true, TFZ_Sand = true, TFZ_MS_Metal = true })
	check("megascans takes metal", all.Metal == "TFZ_MS_Metal")
	check("grass kept", all.Grass == "TFZ_Grass")
	check("no override asked", all.Sand == nil)
	local missing = M.overrides(sets, { TFZ_Metal = true, TFZ_Grass = true })
	check("built-in kept while the variant is missing", missing.Metal == "TFZ_Metal")
	check("nothing registered", next(M.overrides(sets, {})) == nil)
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all megascans material set tests passed")
