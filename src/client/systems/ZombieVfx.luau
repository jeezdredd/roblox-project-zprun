--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local VfxConfig = require(ReplicatedStorage.Shared.config.VfxConfig)
local SettingsService = require(script.Parent.SettingsService)

local ZombieVfx = {}

local AGGRO_ATTRIBUTE = "ZombiesAggro"
local WAKE_RANGE = 90
local WAKE_MAX = 8

local random = Random.new()
local started = false

local function burst(position: Vector3, color: Color3, count: number, speed: number, size: number, lifetime: number)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(position)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new(size, size * 0.3)
	emitter.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -18, 0)
	emitter.Parent = attachment
	emitter:Emit(math.max(1, math.floor(count * VfxConfig.DENSITY + 0.5)))

	Debris:AddItem(anchor, lifetime + 1)
end

local function nearbyZombieBodies(origin: Vector3, range: number, limit: number): { BasePart }
	local result: { BasePart } = {}
	local folder = Workspace:FindFirstChild("Zombies")
	if not folder then
		return result
	end
	for _, model in folder:GetChildren() do
		if #result >= limit then
			break
		end
		local body = model:IsA("Model") and model:FindFirstChild("Body")
		if body and body:IsA("BasePart") and (body.Position - origin).Magnitude <= range then
			table.insert(result, body)
		end
	end
	return result
end

local function onAggroChanged()
	if Workspace:GetAttribute(AGGRO_ATTRIBUTE) ~= true then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	for _, body in nearbyZombieBodies(root.Position, WAKE_RANGE, WAKE_MAX) do
		burst(body.Position - Vector3.new(0, 1.4, 0), Color3.fromRGB(132, 118, 96), 8, 6, 0.9, 0.8)
	end
end

function ZombieVfx.bloodAt(position: Vector3)
	if not VfxConfig.ENABLED or SettingsService.get("bloodEnabled") ~= true then
		return
	end
	burst(position, Color3.fromRGB(122, 26, 26), 12, 12, 0.7, 0.55)

	if random:NextNumber() < 0.3 then
		local stain = Instance.new("Part")
		stain.Name = "BloodStain"
		stain.Size = Vector3.new(random:NextNumber(2, 4), 0.06, random:NextNumber(2, 4))
		stain.CFrame = CFrame.new(position.X, 0.58, position.Z) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0)
		stain.Anchored = true
		stain.CanCollide = false
		stain.CanQuery = false
		stain.CastShadow = false
		stain.Color = Color3.fromRGB(78, 14, 14)
		stain.Material = Enum.Material.SmoothPlastic
		stain.Transparency = 0.25
		stain.Parent = Workspace
		Debris:AddItem(stain, 25)
	end
end

function ZombieVfx.init()
	if started or not VfxConfig.ENABLED then
		return
	end
	started = true
	Workspace:GetAttributeChangedSignal(AGGRO_ATTRIBUTE):Connect(onAggroChanged)
end

return ZombieVfx
