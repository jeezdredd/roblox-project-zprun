--!nonstrict

local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local Workspace = game:GetService("Workspace")

local WEAPON = "rifle"
local SOURCE_MODEL = "rifle_VM"
local RENAME = { Bolt = "Slide" }
local PLACE_AT = CFrame.new(0, 7, 0)
local SCALE = 1
local RECEIVER = "http://127.0.0.1:8973/"

HttpService.HttpEnabled = true

local source = Workspace:FindFirstChild(SOURCE_MODEL)
if not source or not source:FindFirstChild("Main") then
	warn(("Workspace.%s with a Main part is required for offsets"):format(SOURCE_MODEL))
	return
end

local manifest = HttpService:JSONDecode(HttpService:GetAsync(RECEIVER .. "manifest.json"))
local prefix = ("viewmodel/%s/"):format(WEAPON)

local function manifestId(kind, partName)
	local entry = manifest[prefix .. kind .. "_" .. partName:lower()]
	if entry and entry.assetId and entry.assetId > 0 then
		return entry.assetId
	end
	return nil
end

local existing = Workspace:FindFirstChild(WEAPON .. "_VM_import")
if existing then
	existing:Destroy()
end
local imported = Instance.new("Model")
imported.Name = WEAPON .. "_VM_import"
imported.Parent = Workspace

local mainCFrame = source.Main.CFrame
local meshIds = {}

for _, sourcePart in source:GetDescendants() do
	if sourcePart:IsA("MeshPart") then
		local modelId = manifestId("model", sourcePart.Name)
		if not modelId then
			warn(("no approved model id for %s in manifest"):format(sourcePart.Name))
			continue
		end
		local ok, result = pcall(function()
			return InsertService:LoadAsset(modelId)
		end)
		if not ok then
			warn(("LoadAsset %d failed for %s: %s"):format(modelId, sourcePart.Name, tostring(result)))
			continue
		end
		local part = result:FindFirstChildWhichIsA("MeshPart", true)
		if not part then
			warn(("model %d holds no MeshPart"):format(modelId))
			result:Destroy()
			continue
		end
		local finalName = RENAME[sourcePart.Name] or sourcePart.Name
		local offset = mainCFrame:ToObjectSpace(sourcePart.CFrame).Position
		part.Name = finalName
		part.Anchored = true
		part.CanCollide = false
		part.Size = part.Size * SCALE
		part.CFrame = PLACE_AT * CFrame.new(-offset.X * SCALE, offset.Y * SCALE, -offset.Z * SCALE)
		local textureId = manifestId("tex", sourcePart.Name)
		if textureId then
			part.TextureID = "rbxassetid://" .. textureId
		end
		part.Parent = imported
		result:Destroy()
		local meshId = tonumber(part.MeshId:match("%d+"))
		meshIds[finalName] = meshId
		print(("%s -> %s meshId=%s"):format(sourcePart.Name, finalName, tostring(meshId)))
	end
end

imported.PrimaryPart = imported:FindFirstChild("Main")
HttpService:PostAsync(RECEIVER .. "save/" .. WEAPON .. "_meshids.json", HttpService:JSONEncode(meshIds), Enum.HttpContentType.ApplicationJson)
print(("assembled Workspace.%s at %s; next: python3 scripts/mesh_pipeline.py finalize %s"):format(imported.Name, tostring(PLACE_AT.Position), WEAPON))
