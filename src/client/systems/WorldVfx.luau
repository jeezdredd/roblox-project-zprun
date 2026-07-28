--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VfxConfig = require(ReplicatedStorage.Shared.config.VfxConfig)

local WorldVfx = {}

local PHASE_ATTRIBUTE = "FlowPhase"

local random = Random.new()
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

local function buildFlies(host: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 2.5, 0)
	attachment.Parent = host

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Flies"
	emitter.Color = ColorSequence.new(Color3.fromRGB(24, 22, 20))
	emitter.Transparency = NumberSequence.new(0.15)
	emitter.Size = NumberSequence.new(0.07)
	emitter.Lifetime = NumberRange.new(1.4, 2.6)
	emitter.Rate = 12 * VfxConfig.DENSITY
	emitter.Speed = NumberRange.new(2.5, 5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.Acceleration = Vector3.new(0, 1.5, 0)
	emitter.LightInfluence = 1
	emitter.Parent = attachment
end

local function buildSparkLamp(host: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Parent = host

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 226, 150))
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Size = NumberSequence.new(0.18, 0.02)
	sparks.Lifetime = NumberRange.new(0.4, 0.9)
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(9, 18)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Parent = attachment

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 228, 170)
	light.Range = 22
	light.Brightness = 1.4
	light.Parent = host

	task.spawn(function()
		while host.Parent do
			task.wait(random:NextNumber(2.5, 7))
			if not host.Parent then
				break
			end
			for _ = 1, random:NextInteger(2, 5) do
				light.Enabled = not light.Enabled
				task.wait(random:NextNumber(0.04, 0.12))
			end
			light.Enabled = true
			sparks:Emit(math.floor(6 * VfxConfig.DENSITY + 0.5))
		end
	end)
end

local function buildExhaustHaze(host: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Parent = host

	local haze = Instance.new("ParticleEmitter")
	haze.Name = "ExhaustHaze"
	haze.Color = ColorSequence.new(Color3.fromRGB(210, 210, 214))
	haze.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.4, 0.93),
		NumberSequenceKeypoint.new(1, 1),
	})
	haze.Size = NumberSequence.new(1.4, 4.5)
	haze.Lifetime = NumberRange.new(0.8, 1.5)
	haze.Rate = 12 * VfxConfig.DENSITY
	haze.Speed = NumberRange.new(4, 8)
	haze.SpreadAngle = Vector2.new(18, 18)
	haze.Drag = 3
	haze.LightInfluence = 1
	haze.Parent = attachment
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
			local lampCount = 0
			for _, descendant in hangar:GetDescendants() do
				if not descendant:IsA("BasePart") then
					continue
				end
				if descendant.Name == "PadHBar" then
					buildRotorWash(descendant)
				elseif descendant.Name == "Exhaust" then
					buildExhaustHaze(descendant)
				elseif descendant.Name == "CeilingLamp" and lampCount < 3 then
					buildSparkLamp(descendant)
					lampCount += 1
				elseif descendant.Name == "FuelDrum" and random:NextNumber() < 0.4 then
					buildFlies(descendant)
				end
			end
		end
	end)

	RunService.Heartbeat:Connect(step)
end

return WorldVfx
