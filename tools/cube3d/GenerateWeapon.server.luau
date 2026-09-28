--!nonstrict

local GenerationService = game:GetService("GenerationService")
local Workspace = game:GetService("Workspace")

local WEAPON = {
	name = "rifle",
	prompt = "a modern military assault carbine, matte black polymer and steel, "
		.. "short handguard with picatinny rail, straight box magazine, collapsible stock, "
		.. "prominent steel bolt carrier with charging handle on top of the receiver",
	groups = { "Main", "Bolt", "Magazine", "Barrel", "Grip" },
	size = Vector3.new(0.6, 1.4, 5.0),
	maxTriangles = 6000,
}

local function dumpTree(node: Instance, depth: number)
	local info = node.ClassName
	if node:IsA("BasePart") then
		info ..= (" size=%.2f,%.2f,%.2f"):format(node.Size.X, node.Size.Y, node.Size.Z)
	end
	print(("%s%s [%s]"):format(string.rep("  ", depth), node.Name, info))
	for _, child in node:GetChildren() do
		dumpTree(child, depth + 1)
	end
end

local function run()
	local inputs = {
		TextPrompt = WEAPON.prompt,
		Size = WEAPON.size,
		MaxTriangles = WEAPON.maxTriangles,
		GenerateTextures = true,
	}
	local schema = { SchemaDefinition = { Groups = WEAPON.groups } }

	print(("generating %s ..."):format(WEAPON.name))
	local ok, model = pcall(function()
		return GenerationService:GenerateModelAsync(inputs, schema)
	end)
	if not ok or not model then
		warn("generation failed: " .. tostring(model))
		return
	end

	model.Name = WEAPON.name .. "_VM"
	model.Parent = Workspace
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	print("--- generated hierarchy ---")
	dumpTree(model, 0)
	print("--- end hierarchy ---")

	local flattened = 0
	for _, groupName in WEAPON.groups do
		local node = model:FindFirstChild(groupName, true)
		if not node then
			warn(("group %s missing from the generated model"):format(groupName))
			continue
		end
		local part = if node:IsA("MeshPart") then node else node:FindFirstChildWhichIsA("MeshPart", true)
		if not part then
			warn(("group %s produced no MeshPart"):format(groupName))
			continue
		end
		part.Name = groupName
		part.Parent = model
		if node ~= part then
			node:Destroy()
		end
		flattened += 1
	end

	if not model:FindFirstChild("Main") then
		warn("no Main part; the dump and the runtime builder both require it. Re-roll.")
		return
	end
	print(("%d of %d groups flattened into Workspace.%s; inspect the geometry, then run ExtractMeshes.server.luau"):format(flattened, #WEAPON.groups, model.Name))
end

run()
