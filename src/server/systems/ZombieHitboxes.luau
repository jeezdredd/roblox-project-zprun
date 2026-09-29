--!strict

-- Hit parts of skinned zombies. A skinned MeshPart is raycast against in its bind pose
-- (a T-pose), so the parts WeaponService and ZombieAI look for (Head, UpperTorso,
-- LowerTorso, limbs) are invisible boxes jointed to the HumanoidRootPart with a Motor6D,
-- and every PreSimulation (after the Animator has posed the bones, before physics moves
-- the assembly) each joint's Transform is set so the box sits on its bone as the clip has
-- posed it. Motor6D.Transform does not replicate, which is what we want: only the
-- server raycasts against these.

local RunService = game:GetService("RunService")

local ZombieHitboxes = {}

type Entry = { motor: Motor6D, bone: Bone, offset: CFrame }
type Rig = { root: BasePart, entries: { Entry }, far: boolean }

local Players = game:GetService("Players")

-- Zombies further than this from every player keep their boxes where they are: nobody
-- shoots that far through the fog, and reading bone transforms costs.
local FOLLOW_RANGE = 220
local RANGE_CHECK_INTERVAL = 0.5

local rigs: { [Model]: Rig } = {}

-- `boxes`: hit part -> (driving bone, box world CFrame at rest). Call while the rig is
-- still in its bind pose (no clip applied), right after building.
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

-- Stop following (corpses: the model is anchored and posed once).
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
