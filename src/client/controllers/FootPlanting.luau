--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FootPlanting = {}

local RAY_UP = 2.2
local RAY_DOWN = 4.5
local MAX_OFFSET = 1.6
local LERP_SPEED = 9

type FootRig = {
	control: IKControl,
	target: Attachment,
	restY: number,
	current: number,
}

local rig: { FootRig } = {}
local rayParams = RaycastParams.new()
local started = false

local function clearRig()
	for _, foot in rig do
		if foot.control.Parent then
			foot.control:Destroy()
		end
		if foot.target.Parent then
			foot.target:Destroy()
		end
	end
	rig = {}
end

local function buildFoot(character: Model, humanoid: Humanoid, footName: string, endEffectorName: string)
	local foot = character:FindFirstChild(footName)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not foot or not foot:IsA("BasePart") or not root or not root:IsA("BasePart") then
		return
	end

	local target = Instance.new("Attachment")
	target.Name = footName .. "IkTarget"
	target.WorldPosition = foot.Position
	target.Parent = Workspace.Terrain

	local control = Instance.new("IKControl")
	control.Name = footName .. "Ik"
	control.Type = Enum.IKControlType.Position
	control.ChainRoot = character:FindFirstChild("LowerTorso") or root
	control.EndEffector = character:FindFirstChild(endEffectorName) or foot
	control.Target = target
	control.Weight = 0
	control.Parent = humanoid

	table.insert(rig, { control = control, target = target, restY = foot.Position.Y, current = 0 })
end

local function setupCharacter(character: Model)
	clearRig()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	character:WaitForChild("LeftFoot", 5)
	buildFoot(character, humanoid, "LeftFoot", "LeftFoot")
	buildFoot(character, humanoid, "RightFoot", "RightFoot")
end

local function update(deltaTime: number)
	if #rig == 0 then
		return
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local inHub = Players.LocalPlayer:GetAttribute("FlowPhase") ~= "Mission"
	if not character or not humanoid or humanoid.Health <= 0 or not inHub then
		for _, foot in rig do
			foot.control.Weight = math.max(0, foot.control.Weight - deltaTime * 4)
		end
		return
	end

	rayParams.FilterDescendantsInstances = { character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	for index, foot in rig do
		local footName = if index == 1 then "LeftFoot" else "RightFoot"
		local part = character:FindFirstChild(footName)
		if not part or not part:IsA("BasePart") then
			continue
		end
		local origin = part.Position + Vector3.new(0, RAY_UP, 0)
		local result = Workspace:Raycast(origin, Vector3.new(0, -(RAY_UP + RAY_DOWN), 0), rayParams)
		local targetY = if result then result.Position.Y + 0.55 else part.Position.Y
		local offset = math.clamp(targetY - part.Position.Y, -MAX_OFFSET, MAX_OFFSET)
		foot.current += (offset - foot.current) * (1 - math.exp(-LERP_SPEED * deltaTime))
		foot.target.WorldPosition = part.Position + Vector3.new(0, foot.current, 0)
		foot.control.Weight = math.min(1, foot.control.Weight + deltaTime * 4)
	end
end

function FootPlanting.init()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function(character)
		task.spawn(setupCharacter, character)
	end)
	if player.Character then
		task.spawn(setupCharacter, player.Character)
	end

	RunService.Stepped:Connect(update)
end

return FootPlanting
