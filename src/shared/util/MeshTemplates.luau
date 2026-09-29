--!strict

-- Real MeshParts for templates mounted by Rojo.
--
-- A MeshPart that Rojo writes (live sync or a model.json) carries its MeshId but not the
-- mesh's native size (MeshSize reads 0,0,0), and Roblox then draws the mesh at its native
-- size instead of stretching it to Size. Measured 2026-09-28: the M4A1 meshes are
-- natively about a fifth of their part size, so the rifle rendered as a toy under
-- oversized arms, and the arm and zombie meshes were drawn 1/SCALE too large.
--
-- AssetService:CreateMeshPartAsync returns a MeshPart with the native size filled in, so
-- each distinct MeshId is loaded once through it and every later use clones that part
-- and copies the template's properties and children (SurfaceAppearance) onto it.
-- `clone` never yields: while a mesh is still loading it hands back a plain clone of the
-- template, so callers should `prefetch` early and `waitFor` where they can yield.

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

-- Starts loading every MeshPart under `root` (or `root` itself). Does not yield.
function MeshTemplates.prefetch(root: Instance)
	local list: { Instance } = root:GetDescendants()
	table.insert(list, root)
	for _, item in list do
		if item:IsA("MeshPart") and valid(item.MeshId) then
			task.spawn(load, item.MeshId)
		end
	end
end

-- Yields until every MeshPart under `root` has loaded or failed, or `timeout` passes.
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

-- A copy of `template` backed by a correctly sized mesh when one is loaded.
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

-- Replaces every MeshPart directly under `model` with a correctly sized copy.
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
