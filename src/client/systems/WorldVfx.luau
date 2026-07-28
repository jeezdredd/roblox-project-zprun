--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VfxConfig = require(ReplicatedStorage.Shared.config.VfxConfig)

local WorldVfx = {}

local PHASE_ATTRIBUTE = "FlowPhase"

local ashEmitter: ParticleEmitter? = nil
local ashPart: Part? = nil
local emberCount = 0
local started = false

local function buildAshLayer()
	local part = Instance.new("Part")
	part.Name = "AshLayer"
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Ash"
	emitter.Color = ColorSequence.new(Color3.fromRGB(186, 180, 170))
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.5, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new(0.12, 0.28)
	emitter.Lifetime = NumberRange.new(5, 9)
	emitter.Rate = 9 * VfxConfig.DENSITY
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(3, -2.2, 0)
	emitter.Drag = 1.5
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-25, 25)
	emitter.LightInfluence = 1
	emitter.Parent = attachment

	ashPart = part
	ashEmitter = emitter
end

local function attachEmbers(anchor: BasePart)
	if emberCount >= VfxConfig.MAX_ACTIVE_EMITTERS then
		return
	end
	emberCount += 1

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Embers"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 190, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 60, 20)),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new(0.35, 0.08)
	emitter.Lifetime = NumberRange.new(3, 6)
	emitter.Rate = 7 * VfxConfig.DENSITY
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.Acceleration = Vector3.new(2, 9, 0)
	emitter.Drag = 1.2
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Parent = attachment
end

local function buildRotorWash(pad: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, -2, 0)
	attachment.Parent = pad

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "RotorWash"
	emitter.Color = ColorSequence.new(Color3.fromRGB(176, 170, 160))
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new(2, 7)
	emitter.Lifetime = NumberRange.new(1.2, 2)
	emitter.Rate = 6 * VfxConfig.DENSITY
	emitter.Speed = NumberRange.new(9, 15)
	emitter.SpreadAngle = Vector2.new(85, 85)
	emitter.Acceleration = Vector3.new(0, -3, 0)
	emitter.Drag = 2.5
	emitter.LightInfluence = 1
	emitter.Parent = attachment
end

local function step()
	local part = ashPart
	local emitter = ashEmitter
	if not part or not emitter then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	part.Position = camera.CFrame.Position + camera.CFrame.LookVector * 30 + Vector3.new(0, 14, 0)
	emitter.Enabled = Players.LocalPlayer:GetAttribute(PHASE_ATTRIBUTE) ~= "Mission"
		or Workspace:GetAttribute("Biome") == "City"
end

function WorldVfx.init()
	if started or not VfxConfig.ENABLED then
		return
	end
	started = true

	buildAshLayer()

	task.spawn(function()
		local diorama = Workspace:WaitForChild("CityDiorama", 30)
		if diorama then
			for _, descendant in diorama:GetDescendants() do
				if descendant:IsA("BasePart") and descendant.Name == "FireAnchor" then
					attachEmbers(descendant)
				end
			end
		end

		local hangar = Workspace:WaitForChild("Hangar", 30)
		if hangar then
			for _, descendant in hangar:GetDescendants() do
				if descendant:IsA("BasePart") and descendant.Name == "PadHBar" then
					buildRotorWash(descendant)
				end
			end
		end
	end)

	RunService.Heartbeat:Connect(step)
end

return WorldVfx
