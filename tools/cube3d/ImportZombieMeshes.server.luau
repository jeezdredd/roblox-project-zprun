--!nonstrict

local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local Workspace = game:GetService("Workspace")

local RECEIVER = "http://127.0.0.1:8973/"
local PARTS = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" }
local PLACE_AT = CFrame.new(0, 12, 0)

HttpService.HttpEnabled = true

local manifest = HttpService:JSONDecode(HttpService:GetAsync(RECEIVER .. "manifest.json"))

local existing = Workspace:FindFirstChild("ZombieMesh_import")
if existing then
	existing:Destroy()
end
local imported = Instance.new("Model")
imported.Name = "ZombieMesh_import"
imported.Parent = Workspace

local meshIds = {}
for index, partName in PARTS do
	local entry = manifest["zombie/mesh/" .. partName:lower()]
	local modelId = entry and tonumber(entry.assetId) or 0
	if modelId <= 0 then
		warn(("no approved model id for %s"):format(partName))
		continue
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(modelId)
	end)
	if not ok then
		warn(("LoadAsset %d failed for %s: %s"):format(modelId, partName, tostring(result)))
		continue
	end
	local part = result:FindFirstChildWhichIsA("MeshPart", true)
	if not part then
		warn(("model %d holds no MeshPart"):format(modelId))
		continue
	end
	part.Name = partName
	part.Anchored = true
	part.CFrame = PLACE_AT * CFrame.new((index - 4) * 3, 0, 0)
	part.Parent = imported
	result:Destroy()
	meshIds[partName:lower()] = tonumber(part.MeshId:match("%d+"))
end

HttpService:PostAsync(RECEIVER .. "save/zombie_meshids.json", HttpService:JSONEncode(meshIds), Enum.HttpContentType.ApplicationJson)
print("zombie mesh ids", HttpService:JSONEncode(meshIds))
