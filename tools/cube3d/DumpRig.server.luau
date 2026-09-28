--!nonstrict

local Workspace = game:GetService("Workspace")

local MODEL_NAME = "rifle_VM_import"
local MARKER_PARENT = {
	Muzzle = "Barrel",
	CasingEject = "Main",
	HandRMount = "Grip",
	HandLMount = "Main",
}
local SURFACE_MAPS = { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" }

local function assetNumber(content: string): string
	return content:match("%d+") or ""
end

local function components(cf: CFrame): string
	local values = {}
	for _, value in { cf:GetComponents() } do
		table.insert(values, ("%f"):format(value))
	end
	return table.concat(values, "|")
end

local model = Workspace:FindFirstChild(MODEL_NAME)
if not model then
	warn(("no Workspace.%s"):format(MODEL_NAME))
	return
end
local main = model:FindFirstChild("Main")
if not main or not main:IsA("BasePart") then
	warn("model has no Main part")
	return
end

local parts = { main }
for _, child in model:GetChildren() do
	if child:IsA("BasePart") and child ~= main then
		table.insert(parts, child)
	end
end
for markerName in MARKER_PARENT do
	if not model:FindFirstChild(markerName) then
		warn(("marker %s missing; add a 0.05 transparent part named %s and re-run"):format(markerName, markerName))
	end
end

local partLines = { "PART|name|sizeX|sizeY|sizeZ|meshId|textureId|colorR|colorG|colorB|material|transparency|relToMain" }
local surfaceLines = { "SURFACE|part|colorMap|normalMap|roughnessMap|metalnessMap|alphaMode" }
local jointLines = { "JOINT|class|name|part0|part1|C0" }

for _, part in parts do
	local meshId = if part:IsA("MeshPart") then assetNumber(part.MeshId) else ""
	local textureId = if part:IsA("MeshPart") then assetNumber(part.TextureID) else ""
	local surface = part:FindFirstChildOfClass("SurfaceAppearance")
	if surface then
		textureId = ""
		local fields = { "SURFACE", part.Name }
		for _, mapName in SURFACE_MAPS do
			table.insert(fields, assetNumber((surface :: any)[mapName]))
		end
		table.insert(fields, surface.AlphaMode.Name)
		table.insert(surfaceLines, table.concat(fields, "|"))
	end
	table.insert(partLines, table.concat({
		"PART",
		part.Name,
		("%f"):format(part.Size.X),
		("%f"):format(part.Size.Y),
		("%f"):format(part.Size.Z),
		meshId,
		textureId,
		("%f"):format(part.Color.R),
		("%f"):format(part.Color.G),
		("%f"):format(part.Color.B),
		part.Material.Name,
		("%.2f"):format(part.Transparency),
		components(main.CFrame:ToObjectSpace(part.CFrame)),
	}, "|"))
end

for _, part in parts do
	if part == main then
		continue
	end
	local parentName = MARKER_PARENT[part.Name]
	if parentName then
		local parent = model:FindFirstChild(parentName) or main
		table.insert(jointLines, table.concat({ "JOINT", "Weld", part.Name, parent.Name, part.Name, components(parent.CFrame:ToObjectSpace(part.CFrame)) }, "|"))
	else
		table.insert(jointLines, table.concat({ "JOINT", "Motor6D", part.Name, "Main", part.Name, components(main.CFrame:ToObjectSpace(part.CFrame)) }, "|"))
	end
end

print(("\n--- copy everything below into assets/viewmodels/<name>.rig.txt (from %s) ---\n"):format(MODEL_NAME))
print(table.concat(partLines, "\n"))
if #surfaceLines > 1 then
	print(table.concat(surfaceLines, "\n"))
end
print(table.concat(jointLines, "\n"))
print("\n--- end of dump ---")
