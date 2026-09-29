--!strict

-- Loads the first-person pack rigs (skinned arms + weapon, uploaded as Model assets by
-- scripts/upload_assets.py) into ReplicatedStorage.ViewModelPacks, one Model per class,
-- for the client's PackViewmodel to clone. Skinned MeshParts and their Bone tree cannot
-- be written by Rojo, so they come in through InsertService at server start.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local ViewmodelPackConfig = require(ReplicatedStorage.Shared.config.ViewmodelPackConfig)

local ViewmodelPacks = {}

local function prepare(model: Model)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.CastShadow = false
			item.Massless = true
		elseif item:IsA("AnimationController") or (item:IsA("Folder") and item.Name == "InitialPoses") then
			item:Destroy()
		end
	end
	local root = model:FindFirstChild("RootPart", true)
	if root and root:IsA("BasePart") then
		root.Transparency = 1
		model.PrimaryPart = root
	end
end

local function loadOne(folder: Folder, class: string, assetId: number)
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not result then
		warn(`[ViewmodelPacks] {class} ({assetId}) failed to load: {result}`)
		return
	end
	local container = result :: Model
	local model = container:FindFirstChildWhichIsA("Model") or container
	model.Name = class
	prepare(model)
	model.Parent = folder
	if model ~= container then
		container:Destroy()
	end
end

function ViewmodelPacks.init()
	local folder = Instance.new("Folder")
	folder.Name = "ViewModelPacks"
	folder.Parent = ReplicatedStorage
	local ids = (AssetIds :: any).viewmodel and (AssetIds :: any).viewmodel.fps or {}
	for class, pack in ViewmodelPackConfig.classes do
		local entry = ids[pack.asset]
		local assetId = if entry then entry.rig else nil
		if typeof(assetId) == "number" and assetId > 0 then
			task.spawn(loadOne, folder, class, assetId)
		end
	end
end

return ViewmodelPacks
