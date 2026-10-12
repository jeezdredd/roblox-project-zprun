--!strict

export type Entry = {
	name: string,
	asset: string?,
	baseMaterial: string,
	color: number,
	normal: number,
	roughness: number,
	metalness: number?,
	studsPerTile: number,
	override: boolean?,
	replaces: string?,
}

type Named = {
	name: string,
	baseMaterial: any,
	override: boolean?,
	replaces: string?,
}

local MaterialSets = {}

MaterialSets.PREFIX = "TFZ_MS_"

local function positiveId(value: any): boolean
	return type(value) == "number" and value > 0 and value == math.floor(value)
end

function MaterialSets.validate(raw: any): (Entry?, string?)
	if type(raw) ~= "table" then
		return nil, "not a table"
	end
	local name = raw.name
	if type(name) ~= "string" or string.sub(name, 1, #MaterialSets.PREFIX) ~= MaterialSets.PREFIX then
		return nil, `name must start with {MaterialSets.PREFIX}`
	end
	if type(raw.baseMaterial) ~= "string" or raw.baseMaterial == "" then
		return nil, `{name}: no baseMaterial`
	end
	for _, field in { "color", "normal", "roughness" } do
		if not positiveId(raw[field]) then
			return nil, `{name}: {field} is not an asset id`
		end
	end
	if raw.metalness ~= nil and not positiveId(raw.metalness) then
		return nil, `{name}: metalness is not an asset id`
	end
	if type(raw.studsPerTile) ~= "number" or raw.studsPerTile <= 0 then
		return nil, `{name}: studsPerTile must be positive`
	end
	if raw.override ~= nil and type(raw.override) ~= "boolean" then
		return nil, `{name}: override must be a boolean`
	end
	if raw.replaces ~= nil and type(raw.replaces) ~= "string" then
		return nil, `{name}: replaces must be a set name`
	end
	return {
		name = name,
		asset = if type(raw.asset) == "string" then raw.asset else nil,
		baseMaterial = raw.baseMaterial,
		color = raw.color,
		normal = raw.normal,
		roughness = raw.roughness,
		metalness = raw.metalness,
		studsPerTile = raw.studsPerTile,
		override = raw.override,
		replaces = raw.replaces,
	},
		nil
end

function MaterialSets.readList(list: any): ({ Entry }, { string })
	local entries: { Entry } = {}
	local dropped: { string } = {}
	if type(list) ~= "table" then
		return entries, { "the list is not a table" }
	end
	local seen: { [string]: boolean } = {}
	for index, raw in ipairs(list) do
		local entry, why = MaterialSets.validate(raw)
		if not entry then
			table.insert(dropped, `entry {index}: {why}`)
		elseif seen[entry.name] then
			table.insert(dropped, `entry {index}: {entry.name} listed twice`)
		else
			seen[entry.name] = true
			table.insert(entries, entry)
		end
	end
	return entries, dropped
end

function MaterialSets.merge<T>(base: { T }, extra: { T }): { T }
	local merged: { T } = table.clone(base)
	local taken: { [string]: boolean } = {}
	for _, set in base do
		taken[(set :: any).name] = true
	end
	for _, set in extra do
		local name = (set :: any).name
		if not taken[name] then
			taken[name] = true
			table.insert(merged, set)
		end
	end
	return merged
end

function MaterialSets.replacements(sets: { any }): { [string]: string }
	local map: { [string]: string } = {}
	for _, set in sets do
		local named = set :: Named
		if named.replaces and named.replaces ~= named.name and map[named.replaces] == nil then
			map[named.replaces] = named.name
		end
	end
	return map
end

function MaterialSets.resolve(name: string, replacements: { [string]: string }, registered: { [string]: boolean }): string
	local standIn = replacements[name]
	if standIn and registered[standIn] then
		return standIn
	end
	return name
end

function MaterialSets.overrides(sets: { any }, registered: { [string]: boolean }): { [any]: string }
	local map: { [any]: string } = {}
	for _, set in sets do
		local named = set :: Named
		if named.override and registered[named.name] then
			map[named.baseMaterial] = named.name
		end
	end
	return map
end

return MaterialSets
