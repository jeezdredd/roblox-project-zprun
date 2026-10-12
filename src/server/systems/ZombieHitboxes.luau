--!strict

local RunService = game:GetService("RunService")

local ZombieHitboxes = {}

type Entry = { motor: Motor6D, bone: Bone, offset: CFrame }
type Rig = { root: BasePart, entries: { Entry }, far: boolean }

local Players = game:GetService("Players")

local FOLLOW_RANGE = 220
local RANGE_CHECK_INTERVAL = 0.5

local rigs: { [Model]: Rig } = {}

function ZombieHitboxes.attach(model: Model, root: BasePart, boxes: { [BasePart]: { bone: Bone, rest: CFrame } })
	local entries = {}
	for part, info in boxes do
		local motor = Instance.new("Motor6D")
		motor.Name = part.Name .. "Follow"
		motor.Part0 = root
		motor.Part1 = part
		motor.C0 = CFrame.identity
		motor.C1 = CFrame.identity
		motor.Transform = root.CFrame:ToObjectSpace(info.rest)
		motor.Parent = root
		table.insert(entries, { motor = motor, bone = info.bone, offset = info.bone.WorldCFrame:ToObjectSpace(info.rest) })
	end
	rigs[model] = { root = root, entries = entries, far = false }
	model.Destroying:Connect(function()
		rigs[model] = nil
	end)
end

function ZombieHitboxes.detach(model: Model)
	rigs[model] = nil
end

local sinceCheck = 0
RunService.Heartbeat:Connect(function(deltaTime)
	sinceCheck += deltaTime
	if sinceCheck < RANGE_CHECK_INTERVAL then
		return
	end
	sinceCheck = 0
	local positions = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(positions, root.Position)
		end
	end
	for _, rig in rigs do
		local far = true
		local here = rig.root.Position
		for _, position in positions do
			if (position - here).Magnitude < FOLLOW_RANGE then
				far = false
				break
			end
		end
		rig.far = far
	end
end)

RunService.PreSimulation:Connect(function()
	for model, rig in rigs do
		if not model.Parent or rig.far then
			continue
		end
		local inverse = rig.root.CFrame:Inverse()
		for _, entry in rig.entries do
			entry.motor.Transform = inverse * entry.bone.TransformedWorldCFrame * entry.offset
		end
	end
end)

return ZombieHitboxes
