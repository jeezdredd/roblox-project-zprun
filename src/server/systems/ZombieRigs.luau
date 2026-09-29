--!strict

-- Loads the skinned zombie rigs (ZombieSkins) from their Model assets into
-- ServerStorage.ZombieRigs at require time, one template per skin, prepared for
-- ZombieFactory: the part that holds the Bones is renamed "Rig" (the clips address it by
-- that name), the importer's AnimationController and InitialPoses go, and every visual
-- part is made non-colliding, non-queryable and massless.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ZombieSkins = require(ReplicatedStorage.Shared.config.ZombieSkins)

local ZombieRigs = {}

local folder = Instance.new("Folder")
folder.Name = "ZombieRigs"
folder.Parent = ServerStorage

local pending: { [string]: boolean } = {}

local function prepare(model: Model): Model?
	local holder: BasePart? = nil
	for _, item in model:GetDescendants() do
		if item:IsA("Bone") and item.Parent and item.Parent:IsA("BasePart") then
			holder = item.Parent :: BasePart
			break
		end
	end
	if not holder then
		return nil
	end
	for _, item in model:GetDescendants() do
		if item:IsA("AnimationController") or (item:IsA("Folder") and item.Name == "InitialPoses") then
			item:Destroy()
		end
	end
	holder.Name = "Rig"
	-- flatten: every part straight under the model
	local flat = Instance.new("Model")
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Parent = flat
		end
	end
	for _, part in flat:GetChildren() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.CastShadow = true
		end
	end
	return flat
end

local function load(skin: ZombieSkins.Skin)
	if pending[skin.name] or folder:FindFirstChild(skin.name) then
		return
	end
	pending[skin.name] = true
	local ok, result = pcall(function()
		return InsertService:LoadAsset(skin.asset)
	end)
	if ok and result then
		local model = prepare(result :: Model)
		if model then
			model.Name = skin.name
			model.Parent = folder
		else
			warn(`[ZombieRigs] {skin.name}: no bones in asset {skin.asset}`)
		end
		result:Destroy()
	else
		warn(`[ZombieRigs] {skin.name} ({skin.asset}) failed to load: {result}`)
	end
	pending[skin.name] = nil
end

for name in ZombieSkins.skins do
	local skin = ZombieSkins.get(name)
	if skin then
		task.spawn(load, skin)
	end
end

-- The template for a skin, waiting up to `timeout` seconds while it loads.
function ZombieRigs.get(name: string, timeout: number?): Model?
	local found = folder:FindFirstChild(name)
	if found or not timeout or not coroutine.isyieldable() then
		return if found and found:IsA("Model") then found else nil
	end
	local model = folder:WaitForChild(name, timeout)
	return if model and model:IsA("Model") then model else nil
end

return ZombieRigs
