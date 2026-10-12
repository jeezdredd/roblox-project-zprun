--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SurfaceTemplates = {}

function SurfaceTemplates.dress(part: MeshPart, folderName: string, surfaces: { [string]: string }?, replace: boolean?): boolean
	local existing = part:FindFirstChildOfClass("SurfaceAppearance")
	if not surfaces or (existing and not replace) then
		return false
	end
	local best: string? = nil
	for material in surfaces do
		if string.find(part.Name, material, 1, true) and (not best or #material > #best) then
			best = material
		end
	end
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	local template = if best and folder then folder:FindFirstChild(surfaces[best]) else nil
	if not (template and template:IsA("SurfaceAppearance")) then
		return false
	end
	if existing then
		existing:Destroy()
	end
	template:Clone().Parent = part
	return true
end

function SurfaceTemplates.dressAll(root: Instance, folderName: string, surfaces: { [string]: string }?, replace: boolean?): number
	if not surfaces then
		return 0
	end
	local count = 0
	for _, item in root:GetDescendants() do
		if item:IsA("MeshPart") and SurfaceTemplates.dress(item, folderName, surfaces, replace) then
			count += 1
		end
	end
	return count
end

return SurfaceTemplates
