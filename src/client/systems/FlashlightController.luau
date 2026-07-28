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
