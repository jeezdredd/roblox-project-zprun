--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local SettingsService = require(script.Parent.Parent.systems.SettingsService)

local CameraController = {}

local RENDER_NAME = "RunnerCamera"

local bound = false

local function updateCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local runDirection = GameConstants.RUN_DIRECTION

	if SettingsService.get("firstPerson") == true then
		local eyePosition = root.Position + Vector3.new(0, 1.4, 0) + runDirection * 1
		local lookTarget = eyePosition + runDirection * GameConstants.CAMERA_LOOK_AHEAD
		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(eyePosition, lookTarget), 0.35)
		return
	end

	local cameraPosition = root.Position
		- runDirection * GameConstants.CAMERA_BACK_DISTANCE
		+ Vector3.new(0, GameConstants.CAMERA_HEIGHT, 0)
	local lookTarget = root.Position + runDirection * GameConstants.CAMERA_LOOK_AHEAD
	local targetCFrame = CFrame.lookAt(cameraPosition, lookTarget)

	camera.CFrame = camera.CFrame:Lerp(targetCFrame, GameConstants.CAMERA_SMOOTHING)
end

function CameraController.start()
	if bound then
		return
	end
	bound = true
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value, updateCamera)
end

function CameraController.stop()
	if not bound then
		return
	end
	bound = false
	RunService:UnbindFromRenderStep(RENDER_NAME)

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

return CameraController
