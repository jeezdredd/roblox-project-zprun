--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FlashlightController = {}

local NIGHT_ATTRIBUTE = "NightMission"
local RENDER_NAME = "FlashlightAim"

local beam: Part? = nil
local light: SpotLight? = nil
local bound = false

local function ensureBeam(): Part
	local existing = beam
	if existing and existing.Parent then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "Flashlight"
	part.Size = Vector3.new(0.3, 0.3, 0.3)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.Anchored = true
	part.Parent = Workspace

	local spot = Instance.new("SpotLight")
	spot.Color = Color3.fromRGB(255, 246, 220)
	spot.Range = 90
	spot.Brightness = 5
	spot.Angle = 58
	spot.Face = Enum.NormalId.Front
	spot.Shadows = true
	spot.Parent = part

	local motesAttachment = Instance.new("Attachment")
	motesAttachment.Position = Vector3.new(0, 0, -8)
	motesAttachment.Parent = part

	local motes = Instance.new("ParticleEmitter")
	motes.Name = "DustMotes"
	motes.Color = ColorSequence.new(Color3.fromRGB(240, 234, 214))
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.65),
		NumberSequenceKeypoint.new(0.4, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	motes.Size = NumberSequence.new(0.06, 0.12)
	motes.Lifetime = NumberRange.new(1.6, 3)
	motes.Rate = 26
	motes.Speed = NumberRange.new(0.4, 1.6)
	motes.SpreadAngle = Vector2.new(50, 50)
	motes.Acceleration = Vector3.new(0.4, -0.6, 0)
	motes.LightEmission = 0.6
	motes.LightInfluence = 1
	motes.Parent = motesAttachment

	beam = part
	light = spot
	return part
end

local function update()
	local camera = Workspace.CurrentCamera
	local part = beam
	if not camera or not part then
		return
	end
	part.CFrame = camera.CFrame * CFrame.new(0, -0.6, -1)
end

local function setEnabled(enabled: boolean)
	if enabled then
		ensureBeam()
		if light then
			light.Enabled = true
		end
		if not bound then
			bound = true
			RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 2, update)
		end
	else
		if light then
			light.Enabled = false
		end
		if bound then
			bound = false
			RunService:UnbindFromRenderStep(RENDER_NAME)
		end
	end
end

local function refresh()
	local isNight = Workspace:GetAttribute(NIGHT_ATTRIBUTE) == true
	local inMission = Players.LocalPlayer:GetAttribute("FlowPhase") == "Mission"
	setEnabled(isNight and inMission)
end

function FlashlightController.init()
	Workspace:GetAttributeChangedSignal(NIGHT_ATTRIBUTE):Connect(refresh)
	Players.LocalPlayer:GetAttributeChangedSignal("FlowPhase"):Connect(refresh)
	refresh()
end

return FlashlightController
