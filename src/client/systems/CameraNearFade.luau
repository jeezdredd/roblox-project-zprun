--!strict

-- Hides whatever the camera is inside. The death camera lies at the corpse's eye with
-- the zombies feeding on it, the third-person orbit swings through the soldier's own
-- arms and helmet, and a revived body stands where the camera comes back: on the
-- owner's recording (2026-09-30) the screen filled with the inside of a sleeve, a
-- zombie's arm and the helmet shell. Every frame after the camera has moved, the parts
-- whose box reaches within the margin of the camera get LocalTransparencyModifier 1 and
-- get their value back once the camera leaves them. The viewmodel lives under the
-- camera and is never touched.
--
-- Candidates are the local character, the zombies near the camera (their skinned
-- visual parts are CanQuery false, so a spatial query cannot see them) and whatever a
-- bounds query finds.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraNearFade = {}

local STEP_NAME = "CameraNearFade"
-- after the camera and its effects (Camera, Camera + 1) and the death camera (Camera + 1)
local STEP_PRIORITY = Enum.RenderPriority.Camera.Value + 3
-- studs from the camera to a part's box; the near plane is 0.1, so anything this close
-- fills the view
local MARGIN = 0.6
-- a skinned zombie's part box is its bind pose, and the clips move the mesh outside it
local SKINNED_MARGIN = 1.1
-- zombies whose pivot is farther than this are skipped
local ZOMBIE_RANGE = 10

-- parts faded now, with the modifier they had before
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
			-- someone else may have set it meanwhile (the first-person hide): leave theirs
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
