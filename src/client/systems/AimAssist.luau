--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local AimAssist = {}

local MAX_ANGLE = math.rad(9)
local MAX_DISTANCE = 220
local MAGNETISM = 0.85
local PULL_PER_SECOND = 2.2
local PULL_ANGLE = math.rad(14)

local player = Players.LocalPlayer

local function zombieFolder(): Instance?
	return Workspace:FindFirstChild("Zombies")
end

local function targetPoint(model: Model): Vector3?
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function hasLineOfSight(origin: Vector3, target: Vector3, model: Model): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter: { Instance } = { model }
	local character = player.Character
	if character then
		table.insert(filter, character)
	end
	params.FilterDescendantsInstances = filter
	local direction = target - origin
	local result = Workspace:Raycast(origin, direction, params)
	return result == nil
end

function AimAssist.findTarget(origin: Vector3, look: Vector3, maxAngle: number?): (Vector3?, Model?)
	local folder = zombieFolder()
	if not folder then
		return nil, nil
	end

	local limit = maxAngle or MAX_ANGLE
	local bestPoint: Vector3? = nil
	local bestModel: Model? = nil
	local bestAngle = limit

	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		local humanoid = child:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end
		local point = targetPoint(child)
		if not point then
			continue
		end
		local offset = point - origin
		local distance = offset.Magnitude
		if distance > MAX_DISTANCE or distance < 1 then
			continue
		end
		local angle = math.acos(math.clamp(offset.Unit:Dot(look), -1, 1))
		if angle >= bestAngle then
			continue
		end
		if not hasLineOfSight(origin, point, child) then
			continue
		end
		bestAngle = angle
		bestPoint = point
		bestModel = child
	end

	return bestPoint, bestModel
end

function AimAssist.adjustFireDirection(origin: Vector3, look: Vector3): Vector3
	local point = AimAssist.findTarget(origin, look)
	if not point then
		return look
	end
	local desired = (point - origin).Unit
	return look:Lerp(desired, MAGNETISM).Unit
end

function AimAssist.cameraPull(origin: Vector3, look: Vector3, deltaTime: number): Vector3?
	local point = AimAssist.findTarget(origin, look, PULL_ANGLE)
	if not point then
		return nil
	end
	local desired = (point - origin).Unit
	local alpha = math.clamp(deltaTime * PULL_PER_SECOND, 0, 0.35)
	return look:Lerp(desired, alpha).Unit
end

return AimAssist
