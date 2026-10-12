--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraNearFade = {}

local STEP_NAME = "CameraNearFade"
local STEP_PRIORITY = Enum.RenderPriority.Camera.Value + 3
local MARGIN = 0.6
local SKINNED_MARGIN = 1.1
local ZOMBIE_RANGE = 10

local faded: { [BasePart]: number } = {}
local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = false

local function boxDistance(part: BasePart, point: Vector3): number
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local outside = Vector3.new(
		math.max(math.abs(localPoint.X) - half.X, 0),
		math.max(math.abs(localPoint.Y) - half.Y, 0),
		math.max(math.abs(localPoint.Z) - half.Z, 0)
	)
	return outside.Magnitude
end

local function consider(part: BasePart, point: Vector3, margin: number, inside: { [BasePart]: boolean })
	if part.Transparency >= 1 or inside[part] then
		return
	end
	if boxDistance(part, point) > margin then
		return
	end
	inside[part] = true
	if faded[part] == nil then
		faded[part] = part.LocalTransparencyModifier
	end
	part.LocalTransparencyModifier = 1
end

local function scanModel(model: Instance, point: Vector3, margin: number, inside: { [BasePart]: boolean })
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			consider(descendant, point, margin, inside)
		end
	end
end

local function step()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local point = camera.CFrame.Position
	local inside: { [BasePart]: boolean } = {}

	local character = Players.LocalPlayer.Character
	if character then
		scanModel(character, point, MARGIN, inside)
	end

	local zombies = Workspace:FindFirstChild("Zombies")
	if zombies then
		for _, zombie in zombies:GetChildren() do
			if zombie:IsA("Model") and (zombie:GetPivot().Position - point).Magnitude < ZOMBIE_RANGE then
				scanModel(zombie, point, SKINNED_MARGIN, inside)
			end
		end
	end

	params.FilterDescendantsInstances = if character then { camera, character } else { camera }
	for _, part in Workspace:GetPartBoundsInRadius(point, MARGIN, params) do
		consider(part, point, MARGIN, inside)
	end

	for part, before in faded do
		if not inside[part] then
			faded[part] = nil
			if part.Parent and part.LocalTransparencyModifier == 1 then
				part.LocalTransparencyModifier = before
			end
		end
	end
end

function CameraNearFade.init()
	RunService:BindToRenderStep(STEP_NAME, STEP_PRIORITY, step)
end

return CameraNearFade
