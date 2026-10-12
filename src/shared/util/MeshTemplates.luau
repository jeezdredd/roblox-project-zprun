--!strict

local AssetService = game:GetService("AssetService")

local MeshTemplates = {}

local loaded: { [string]: MeshPart } = {}
local failed: { [string]: boolean } = {}
local inFlight: { [string]: boolean } = {}

local COPIED_PROPERTIES = {
	"Name",
	"Size",
	"CFrame",
	"Color",
	"Material",
	"Transparency",
	"Reflectance",
	"TextureID",
	"Anchored",
	"CanCollide",
	"CanQuery",
	"CanTouch",
	"CastShadow",
	"Massless",
}

local function valid(meshId: string): boolean
	return meshId ~= "" and meshId ~= "rbxassetid://0"
end

local function load(meshId: string)
	if loaded[meshId] or failed[meshId] or inFlight[meshId] then
		return
	end
	inFlight[meshId] = true
	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromUri(meshId), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Precise,
		})
	end)
	inFlight[meshId] = nil
	if ok and result then
		loaded[meshId] = result :: MeshPart
	else
		failed[meshId] = true
		warn(("[MeshTemplates] %s failed to load: %s"):format(meshId, tostring(result)))
	end
end

function MeshTemplates.prefetch(root: Instance)
	local list: { Instance } = root:GetDescendants()
	table.insert(list, root)
	for _, item in list do
		if item:IsA("MeshPart") and valid(item.MeshId) then
			task.spawn(load, item.MeshId)
		end
	end
end

function MeshTemplates.waitFor(root: Instance, timeout: number): boolean
	MeshTemplates.prefetch(root)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local pending = false
		for _, item in root:GetDescendants() do
			if item:IsA("MeshPart") and valid(item.MeshId) and not loaded[item.MeshId] and not failed[item.MeshId] then
				pending = true
				break
			end
		end
		if not pending then
			return true
		end
		task.wait(0.05)
	end
	return false
end

function MeshTemplates.clone(template: MeshPart): MeshPart
	local base = loaded[template.MeshId]
	if not base then
		if valid(template.MeshId) then
			task.spawn(load, template.MeshId)
		end
		return template:Clone()
	end
	local part = base:Clone()
	for _, property in COPIED_PROPERTIES do
		(part :: any)[property] = (template :: any)[property]
	end
	for attribute, value in template:GetAttributes() do
		part:SetAttribute(attribute, value)
	end
	for _, child in template:GetChildren() do
		child:Clone().Parent = part
	end
	return part
end

function MeshTemplates.resolveChildren(model: Instance)
	for _, child in model:GetChildren() do
		if child:IsA("MeshPart") and loaded[child.MeshId] then
			local part = MeshTemplates.clone(child)
			part.Parent = model
			child:Destroy()
		end
	end
end

return MeshTemplates
