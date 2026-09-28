--!nonstrict

local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local WEAPON = "rifle"
local MODEL_NAME = "rifle_VM"
local RECEIVER = "http://127.0.0.1:8973/save/"
local CHUNK = 900 * 1024

HttpService.HttpEnabled = true

local function post(name, body)
	HttpService:PostAsync(RECEIVER .. name, body, Enum.HttpContentType.TextPlain)
end

local function exportMesh(part: MeshPart)
	local editable = AssetService:CreateEditableMeshAsync(part.MeshContent)
	local lines = {}
	local vertexIndex, uvIndex, normalIndex = {}, {}, {}
	for i, id in editable:GetVertices() do
		vertexIndex[id] = i
		local p = editable:GetPosition(id)
		table.insert(lines, ("v %f %f %f"):format(p.X, p.Y, p.Z))
	end
	for i, id in editable:GetUVs() do
		uvIndex[id] = i
		local uv = editable:GetUV(id)
		table.insert(lines, ("vt %f %f"):format(uv.X, uv.Y))
	end
	for i, id in editable:GetNormals() do
		normalIndex[id] = i
		local n = editable:GetNormal(id)
		table.insert(lines, ("vn %f %f %f"):format(n.X, n.Y, n.Z))
	end
	local faceCount = 0
	for _, face in editable:GetFaces() do
		local vertices = editable:GetFaceVertices(face)
		local uvs = editable:GetFaceUVs(face)
		local normals = editable:GetFaceNormals(face)
		local tokens = { "f" }
		for k, vertexId in vertices do
			table.insert(tokens, ("%d/%d/%d"):format(vertexIndex[vertexId], uvIndex[uvs[k]], normalIndex[normals[k]]))
		end
		table.insert(lines, table.concat(tokens, " "))
		faceCount += 1
	end
	post(("%s_%s.obj"):format(WEAPON, part.Name), table.concat(lines, "\n"))
	print(("%s: %d faces exported"):format(part.Name, faceCount))
end

local function exportTexture(part: MeshPart)
	local image = AssetService:CreateEditableImageAsync(part.TextureContent)
	local size = image.Size
	local raw = buffer.tostring(image:ReadPixelsBuffer(Vector2.new(0, 0), size))
	local total = math.ceil(#raw / CHUNK)
	for i = 1, total do
		local piece = raw:sub((i - 1) * CHUNK + 1, i * CHUNK)
		post(("%s_%s_tex_%dx%d.rgba.part%02d"):format(WEAPON, part.Name, size.X, size.Y, i), piece)
	end
	print(("%s: %dx%d texture in %d chunks"):format(part.Name, size.X, size.Y, total))
end

local model = Workspace:FindFirstChild(MODEL_NAME)
if not model then
	warn(("no Workspace.%s"):format(MODEL_NAME))
	return
end

for _, part in model:GetDescendants() do
	if part:IsA("MeshPart") then
		local ok, err = pcall(exportMesh, part)
		if not ok then
			warn(("mesh export failed for %s: %s"):format(part.Name, tostring(err)))
		end
		local okTex, errTex = pcall(exportTexture, part)
		if not okTex then
			warn(("texture export failed for %s: %s"):format(part.Name, tostring(errTex)))
		end
	end
end
print(("extraction done; next: python3 scripts/mesh_pipeline.py convert %s"):format(WEAPON))
