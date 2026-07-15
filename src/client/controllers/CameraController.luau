--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)

local CameraController = {}

function CameraController.init()
	RunService:BindToRenderStep("RunnerCamera", Enum.RenderPriority.Camera.Value, function()
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
		local cameraPosition = root.Position
			- runDirection * GameConstants.CAMERA_BACK_DISTANCE
			+ Vector3.new(0, GameConstants.CAMERA_HEIGHT, 0)
		local lookTarget = root.Position + runDirection * GameConstants.CAMERA_LOOK_AHEAD
		local targetCFrame = CFrame.lookAt(cameraPosition, lookTarget)

		camera.CFrame = camera.CFrame:Lerp(targetCFrame, GameConstants.CAMERA_SMOOTHING)
	end)
end

return CameraController
